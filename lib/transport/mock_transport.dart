import 'dart:async';
import 'dart:math' as math;

import 'transport.dart';

enum DemoCar {
  nexonHealthy('Demo: Tata Nexon petrol (healthy)', 'MAT627108NLK12345'),
  swiftHealthy('Demo: Maruti Swift petrol (healthy)', 'MA3ZFEB1SR0123456'),
  swiftFaulty('Demo: Maruti Swift petrol (with faults)', 'MA3ZFEB1SR0654321');

  const DemoCar(this.title, this.vin);
  final String title;
  final String vin;
}

/// A simulated ELM327 + car at warm idle, used for the demo mode and tests.
/// Answers exactly like a real adapter (CAN 11-bit, headers on, ISO-TP).
class MockTransport implements ObdTransport, EngineStartSimulator {
  /// With [virtualTime] the simulated clock advances 40 ms per request
  /// instead of following the wall clock, making tests independent of
  /// machine speed.
  MockTransport(this.car, {this.latency = const Duration(milliseconds: 12), int? seed, this.virtualTime = false})
      : _rnd = math.Random(seed);

  final bool virtualTime;
  int _requests = 0;

  final DemoCar car;
  final Duration latency;
  final math.Random _rnd;
  StreamController<String>? _ctrl;
  final _clock = Stopwatch();
  String _pending = '';

  /// When set, ATRV follows a "key off → crank → running" trace (seconds).
  double? _crankAt;

  /// Last command received – lets tests assert what was sent.
  final List<String> received = [];

  @override
  String get name => car.title;

  @override
  bool get supportsBaudProbe => false;

  bool get _faulty => car == DemoCar.swiftFaulty;
  bool get _nexon => car == DemoCar.nexonHealthy;
  double get _t => virtualTime ? _requests * 0.04 : _clock.elapsedMilliseconds / 1000;

  @override
  Future<void> open(int baudRate) async {
    _ctrl = StreamController<String>();
    _clock
      ..reset()
      ..start();
  }

  @override
  Stream<String> get incoming => _ctrl!.stream;

  @override
  Future<void> close() async {
    await _ctrl?.close();
    _ctrl = null;
  }

  /// Battery test demo: the simulated driver starts the engine in 3 s.
  @override
  void simulateEngineStart() => _crankAt = _t + 3;

  @override
  Future<void> write(String data) async {
    _pending += data;
    while (_pending.contains('\r')) {
      final i = _pending.indexOf('\r');
      final cmd = _pending.substring(0, i).trim().toUpperCase().replaceAll(' ', '');
      _pending = _pending.substring(i + 1);
      if (cmd.isEmpty) continue;
      received.add(cmd);
      _requests++;
      final reply = _answer(cmd);
      Future<void>.delayed(latency, () => _ctrl?.add('$reply\r\r>'));
    }
  }

  // ---------------------------------------------------------------- answers

  String _answer(String cmd) {
    if (cmd.startsWith('AT')) return _at(cmd.substring(2));
    final mode = cmd.substring(0, 2);
    switch (mode) {
      case '01':
        final pid = int.parse(cmd.substring(2, 4), radix: 16);
        final d = _pid(pid);
        return d == null ? 'NO DATA' : _frames([0x41, pid, ...d]);
      case '03':
        final codes = _faulty ? [0x04, 0x20] : <int>[];
        return _frames([0x43, codes.length ~/ 2, ...codes]);
      case '07':
        final codes = _faulty ? [0x01, 0x71] : <int>[];
        return _frames([0x47, codes.length ~/ 2, ...codes]);
      case '0A':
        return _frames([0x4A, 0]);
      case '09':
        if (cmd == '0902') return _frames([0x49, 0x02, 0x01, ...car.vin.codeUnits]);
        return 'NO DATA';
      default:
        return 'NO DATA';
    }
  }

  String _at(String c) {
    if (c == 'Z' || c == 'I') return '\rELM327 v1.5';
    if (c == 'DPN') return 'A6';
    if (c == 'DP') return 'AUTO, ISO 15765-4 (CAN 11/500)';
    if (c == 'RV') return '${_battery().toStringAsFixed(1)}V';
    return 'OK';
  }

  double _battery() {
    final noise = (_rnd.nextDouble() - 0.5) * 0.06;
    if (_crankAt != null) {
      final dt = _t - _crankAt!;
      final rest = _faulty ? 12.25 : 12.62;
      if (dt < 0) return rest + noise;
      if (dt < 1.2) return (_faulty ? 9.3 : 10.4) + noise * 4;
      if (dt < 2.0) return 12.0 + noise;
      return (_faulty ? 13.05 : 14.15) + noise;
    }
    return (_faulty ? 13.05 : 14.1) + noise;
  }

  /// Supported PIDs for each demo car.
  Set<int> get _supported => {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x11, 0x13, 0x14, 0x15, 0x1C, 0x1F, 0x21, 0x2E, 0x2F, 0x30, 0x31,
        0x33, 0x3C, 0x42, 0x43, 0x44, 0x45, 0x47, 0x49, 0x4A, 0x4C, 0x51,
        if (_nexon) 0x46,
      };

  List<int>? _supportedMask(int base) {
    final s = _supported;
    if (base > 0 && !s.any((p) => p > base && p <= base + 0x20)) return null;
    final mask = [0, 0, 0, 0];
    for (var i = 1; i <= 32; i++) {
      final pid = base + i;
      final on = s.contains(pid) || (i == 32 && s.any((p) => p > base + 0x20));
      if (on) mask[(i - 1) ~/ 8] |= 0x80 >> ((i - 1) % 8);
    }
    return mask;
  }

  double _n(double amp) => (_rnd.nextDouble() - 0.5) * 2 * amp;

  List<int>? _pid(int pid) {
    if (pid % 0x20 == 0) return _supportedMask(pid);
    if (!_supported.contains(pid)) return null;
    final t = _t;
    int pct(double v) => (v * 255 / 100).round().clamp(0, 255);
    int trim(double v) => (v * 128 / 100 + 128).round().clamp(0, 255);
    List<int> w(double v) {
      final x = v.round().clamp(0, 65535);
      return [x >> 8, x & 0xFF];
    }

    final rpm = 790 + 18 * math.sin(t * 3) + (_faulty ? _n(160) : _n(10));
    switch (pid) {
      case 0x01:
        // MIL + count, spark ignition, misfire/fuel/components supported & complete.
        final a = _faulty ? 0x80 | 1 : 0;
        final c = 0x01 | 0x04 | 0x20 | 0x40; // catalyst, EVAP, O2, O2 heater
        final d = _faulty ? 0x01 : 0x00; // catalyst monitor incomplete
        return [a, 0x07, c, d];
      case 0x03:
        return [0x02, 0x00];
      case 0x04:
        return [pct(24 + _n(1.5))];
      case 0x05:
        return [(89 + _n(0.4) + 40).round()];
      case 0x06:
        return [trim((_faulty ? 6 : 0) + 4 * math.sin(t * 5))];
      case 0x07:
        return [trim(_faulty ? 17.2 : 2.3)];
      case 0x0B:
        return [(_nexon ? 36 : 33) + _n(1).round()];
      case 0x0C:
        return w(rpm * 4);
      case 0x0D:
        return [0];
      case 0x0E:
        return [((8 + _n(1.5) + 64) * 2).round()];
      case 0x0F:
        return [(38 + 40 + _n(0.4)).round()];
      case 0x11:
        return [pct(15.3 + _n(0.2))];
      case 0x13:
        return [0x03]; // B1S1 + B1S2
      case 0x14:
        final v = 0.475 + 0.39 * math.sin(t * 9);
        return [(v * 200).round().clamp(0, 255), trim(1)];
      case 0x15:
        final v = _faulty ? 0.45 + 0.38 * math.sin(t * 8.6) : 0.68 + _n(0.02);
        return [(v * 200).round().clamp(0, 255), 0xFF];
      case 0x1C:
        return [0x0B]; // EOBD
      case 0x1F:
        return w(640 + t);
      case 0x21:
        return w(_faulty ? 186 : 0);
      case 0x2E:
        return [pct(12)];
      case 0x2F:
        return [pct(_faulty ? 8 : 56)];
      case 0x30:
        return [_faulty ? 22 : 64];
      case 0x31:
        return w(_faulty ? 410 : 2240);
      case 0x33:
        return [98];
      case 0x3C:
        return w((520 + _n(4) + 40) * 10);
      case 0x42:
        return w(_battery() * 1000);
      case 0x43:
        return w(22 * 255 / 100);
      case 0x44:
        return w(32768);
      case 0x45:
        return [pct(4.5)];
      case 0x46:
        return [31 + 40];
      case 0x47:
        return [pct(30.5)];
      case 0x49:
        return [pct(14.1)];
      case 0x4A:
        return [pct(7.1)];
      case 0x4C:
        return [pct(4.3)];
      case 0x51:
        return [1]; // petrol
    }
    return null;
  }

  /// Encodes a payload as CAN 11-bit ISO-TP frames with headers (ATH1, ATS0).
  static String _frames(List<int> payload) {
    String h(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (payload.length <= 7) {
      return '7E8${h(payload.length)}${payload.map(h).join()}';
    }
    final lines = <String>[];
    final len = payload.length;
    lines.add('7E81${h(len >> 8).substring(1)}${h(len & 0xFF)}${payload.take(6).map(h).join()}');
    var seq = 1;
    for (var i = 6; i < len; i += 7) {
      final chunk = payload.skip(i).take(7).toList();
      while (chunk.length < 7) {
        chunk.add(0x00);
      }
      lines.add('7E82${(seq & 0xF).toRadixString(16).toUpperCase()}${chunk.map(h).join()}');
      seq++;
    }
    return lines.join('\r');
  }
}

class MockCandidate extends TransportCandidate {
  MockCandidate(this.car);
  final DemoCar car;
  @override
  String get title => car.title;
  @override
  String get subtitle => 'Simulated adapter – try the app without a car';
  @override
  bool get isDemo => true;
  @override
  Future<ObdTransport> create() async => MockTransport(car);
}
