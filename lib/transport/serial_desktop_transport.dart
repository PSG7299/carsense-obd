import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'transport.dart';

/// COM-port adapter on Windows (also works on Linux / macOS).
class SerialDesktopTransport implements ObdTransport {
  SerialDesktopTransport(this.portName);

  final String portName;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamController<String>? _ctrl;
  StreamSubscription<Uint8List>? _sub;

  @override
  String get name => portName;

  @override
  bool get supportsBaudProbe => true;

  @override
  Future<void> open(int baudRate) async {
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw TransportException('Cannot open $portName: ${err?.message ?? 'busy or missing driver'}');
    }
    final cfg = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..setFlowControl(SerialPortFlowControl.none);
    port.config = cfg;
    cfg.dispose();
    _port = port;
    _ctrl = StreamController<String>();
    _reader = SerialPortReader(port, timeout: 50);
    _sub = _reader!.stream.listen(
      (d) => _ctrl?.add(latin1.decode(d, allowInvalid: true)),
      onError: (Object e) => _ctrl?.addError(e),
    );
  }

  @override
  Stream<String> get incoming => _ctrl!.stream;

  @override
  Future<void> write(String data) async {
    _port?.write(Uint8List.fromList(latin1.encode(data)), timeout: 500);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _reader?.close();
    await _ctrl?.close();
    _port?.close();
    _port?.dispose();
    _sub = null;
    _reader = null;
    _ctrl = null;
    _port = null;
  }
}

class SerialDesktopCandidate extends TransportCandidate {
  SerialDesktopCandidate(this.portName, this.description);
  final String portName;
  final String description;

  @override
  String get title => portName;
  @override
  String get subtitle => description;
  @override
  Future<ObdTransport> create() async => SerialDesktopTransport(portName);

  static List<TransportCandidate> list() {
    final out = <TransportCandidate>[];
    for (final name in SerialPort.availablePorts) {
      var desc = 'Serial port';
      try {
        final p = SerialPort(name);
        desc = p.description ?? p.productName ?? desc;
        p.dispose();
      } catch (_) {}
      out.add(SerialDesktopCandidate(name, desc));
    }
    return out;
  }
}
