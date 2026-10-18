import 'dart:async';

import '../transport/transport.dart';
import 'read_only_guard.dart';
import 'response_parser.dart';

/// Talks the ELM327 text protocol over an [ObdTransport].
///
/// Every command is checked by [ReadOnlyGuard] – there is deliberately no way
/// to bypass it.
class Elm327 {
  Elm327(this.transport);

  final ObdTransport transport;
  final _buffer = StringBuffer();
  StreamSubscription<String>? _sub;
  Completer<String>? _pending;
  Future<void> _queue = Future.value();

  ObdProtocol protocol = ObdProtocol.auto;
  late final ResponseParser parser = ResponseParser(protocol);
  String adapterId = '';

  /// Most recent raw exchanges, for the "send log" troubleshooting screen.
  final List<String> log = [];

  static const baudRates = [38400, 115200, 9600, 230400, 500000];

  /// Opens the transport (probing baud rates when needed) and initialises the
  /// adapter. Returns the detected protocol.
  Future<ObdProtocol> connect() async {
    final rates = transport.supportsBaudProbe ? baudRates : [38400];
    Object? lastError;
    for (final baud in rates) {
      try {
        await transport.open(baud);
        _listen();
        // Wake the adapter, flush garbage, then identify.
        await transport.write('\r');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        bool isElm(String r) => r.contains('ELM') || r.contains('STN') || r.contains('OBD');
        var id = await send('ATZ', timeout: const Duration(seconds: 3));
        // A stray prompt from the wake-up CR can swallow the ATZ reply – ask again.
        if (!isElm(id)) id = await send('ATI', timeout: const Duration(seconds: 2));
        if (isElm(id)) {
          adapterId = id.replaceAll(RegExp(r'[\r\n>]+'), ' ').trim();
          _addLog('# adapter at $baud baud: $adapterId');
          return await _initialise();
        }
        lastError = 'No ELM327 reply at $baud baud';
      } catch (e) {
        lastError = e;
      }
      await _sub?.cancel();
      _sub = null;
      try {
        await transport.close();
      } catch (_) {}
    }
    throw TransportException(
        'Adapter did not answer. Check the cable and that ignition is ON. ($lastError)');
  }

  Future<ObdProtocol> _initialise() async {
    for (final c in ['ATE0', 'ATL0', 'ATS0', 'ATH1', 'ATAT1', 'ATSP0']) {
      await send(c);
    }
    // First real request triggers the protocol search ("SEARCHING...").
    final r = await send('0100', timeout: const Duration(seconds: 12));
    final err = ResponseParser.errorIn(r);
    if (err != null && err != 'NO DATA') {
      throw TransportException(
          'Car did not respond ($err). Turn the ignition ON and try again.');
    }
    protocol = ObdProtocol.fromDpn(await send('ATDPN'));
    parser.protocol = protocol;
    _addLog('# protocol: ${protocol.label}');
    return protocol;
  }

  void _listen() {
    _sub ??= transport.incoming.listen((chunk) {
      _buffer.write(chunk);
      final s = _buffer.toString();
      if (s.contains('>') && _pending != null && !_pending!.isCompleted) {
        _buffer.clear();
        _pending!.complete(s);
      }
    });
  }

  /// Sends one command and returns the raw reply (up to the `>` prompt).
  /// Commands are serialised – callers may fire concurrently.
  Future<String> send(String command,
      {Duration timeout = const Duration(seconds: 3)}) {
    ReadOnlyGuard.check(command);
    final result = _queue.then((_) => _sendNow(command, timeout));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _sendNow(String command, Duration timeout) async {
    _buffer.clear();
    _pending = Completer<String>();
    await transport.write('$command\r');
    try {
      final reply = await _pending!.future.timeout(timeout);
      _addLog('> $command\n$reply');
      return reply;
    } on TimeoutException {
      _addLog('> $command\n(timeout) ${_buffer.toString()}');
      _buffer.clear();
      return 'NO DATA';
    }
  }

  /// Sends an OBD request and returns parsed per-ECU payloads whose service
  /// byte matches the request (mode + 0x40). Empty when unsupported.
  Future<List<EcuMessage>> request(String obdCommand,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final raw = await send(obdCommand, timeout: timeout);
    if (ResponseParser.errorIn(raw) != null) return const [];
    final mode = int.parse(obdCommand.substring(0, 2), radix: 16);
    return parser
        .parse(raw)
        .where((m) => m.data.isNotEmpty && m.data[0] == mode + 0x40)
        .toList();
  }

  /// Battery voltage measured by the adapter at OBD pin 16 (`ATRV`).
  Future<double?> batteryVoltage() async {
    final r = await send('ATRV');
    final m = RegExp(r'(\d+(\.\d+)?)\s*V').firstMatch(r.toUpperCase());
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  void _addLog(String s) {
    log.add(s);
    if (log.length > 400) log.removeRange(0, log.length - 400);
  }

  Future<void> close() async {
    try {
      await send('ATPC', timeout: const Duration(milliseconds: 500));
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    await transport.close();
  }
}
