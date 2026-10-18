import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import 'transport.dart';

/// USB-OTG serial adapter on Android (FTDI, CH340, CP210x, PL2303, CDC).
class UsbAndroidTransport implements ObdTransport {
  UsbAndroidTransport(this.device);

  final UsbDevice device;
  UsbPort? _port;
  StreamController<String>? _ctrl;
  StreamSubscription<Uint8List>? _sub;

  @override
  String get name => device.productName ?? device.deviceName;

  @override
  bool get supportsBaudProbe => true;

  @override
  Future<void> open(int baudRate) async {
    _port ??= await device.create();
    final port = _port;
    if (port == null) throw TransportException('USB permission denied or unsupported adapter chip.');
    if (!await port.open()) throw TransportException('Could not open USB adapter.');
    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    _ctrl = StreamController<String>();
    _sub = port.inputStream?.listen((d) => _ctrl?.add(latin1.decode(d, allowInvalid: true)));
  }

  @override
  Stream<String> get incoming => _ctrl!.stream;

  @override
  Future<void> write(String data) async => _port?.write(Uint8List.fromList(latin1.encode(data)));

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _ctrl?.close();
    _sub = null;
    _ctrl = null;
    await _port?.close();
    _port = null;
  }
}

class UsbAndroidCandidate extends TransportCandidate {
  UsbAndroidCandidate(this.device);
  final UsbDevice device;

  @override
  String get title => device.productName ?? 'USB serial adapter';

  @override
  String get subtitle => [
        device.manufacturerName,
        'VID ${device.vid?.toRadixString(16).padLeft(4, '0')} PID ${device.pid?.toRadixString(16).padLeft(4, '0')}',
      ].whereType<String>().join(' · ');

  @override
  Future<ObdTransport> create() async => UsbAndroidTransport(device);

  static Future<List<TransportCandidate>> list() async =>
      [for (final d in await UsbSerial.listDevices()) UsbAndroidCandidate(d)];
}
