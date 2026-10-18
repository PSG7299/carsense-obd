import 'dart:typed_data';

import 'package:carsense_obd/elm327/response_parser.dart';
import 'package:carsense_obd/obd/dtc.dart';
import 'package:carsense_obd/obd/monitors.dart';
import 'package:carsense_obd/obd/pids.dart';
import 'package:carsense_obd/obd/vin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponseParser CAN', () {
    final p = ResponseParser(ObdProtocol.can11_500);

    test('single frame with SEARCHING noise', () {
      final m = p.parse('SEARCHING...\r7E8064100BE3FA813\r\r>');
      expect(m, hasLength(1));
      expect(m.first.ecu, '7E8');
      expect(m.first.data, [0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13]);
    });

    test('spaces are tolerated', () {
      final m = p.parse('7E8 03 41 05 7B \r>');
      expect(m.first.data, [0x41, 0x05, 0x7B]);
    });

    test('multi-frame VIN', () {
      final m = p.parse('7E810144902014D4154\r7E8213632373130384E\r7E8224C4B3132333435\r>');
      expect(decodeVin(m.first.data), 'MAT627108NLK12345');
    });

    test('two ECUs answer', () {
      final m = p.parse('7E80641000000000\r7E906410000000001\r>');
      expect(m.map((e) => e.ecu), ['7E8', '7E9']);
    });

    test('29-bit headers', () {
      final p29 = ResponseParser(ObdProtocol.can29_500);
      final m = p29.parse('18DAF11003410C1A\r>');
      expect(m.first.ecu, '18DAF110');
      expect(m.first.data, [0x41, 0x0C, 0x1A]);
    });

    test('ATDPN protocol reply', () {
      expect(ObdProtocol.fromDpn('A6\r\r>'), ObdProtocol.can11_500);
      expect(ObdProtocol.fromDpn('7>'), ObdProtocol.can29_500);
      expect(ObdProtocol.fromDpn('A5'), ObdProtocol.kwpFast);
      expect(ObdProtocol.fromDpn('3\r>'), ObdProtocol.iso9141);
    });

    test('errors are detected', () {
      expect(ResponseParser.errorIn('NO DATA\r\r>'), 'NO DATA');
      expect(ResponseParser.errorIn('UNABLE TO CONNECT\r>'), 'UNABLE TO CONNECT');
      expect(ResponseParser.errorIn('?\r>'), '?');
      expect(ResponseParser.errorIn('7E803410C1A\r>'), isNull);
    });
  });

  group('ResponseParser legacy KWP / ISO 9141', () {
    final p = ResponseParser(ObdProtocol.kwpFast);
    test('strips 3 header bytes and checksum', () {
      final m = p.parse('486B104105 7BCC\r>'.replaceAll(' ', ''));
      expect(m.first.ecu, '10');
      expect(m.first.data, [0x41, 0x05, 0x7B]);
    });
    test('multi-line DTC reply is joined', () {
      final m = p.parse('486B104301710420000099\r486B1043030100000000AA\r>');
      final codes = decodeDtcPayload(m.first.data, isCan: false);
      expect(codes, ['P0171', 'P0420', 'P0301']);
    });
  });

  group('decoders', () {
    test('supported PID bitmask', () {
      final s = decodeSupported(0, Uint8List.fromList([0xBE, 0x3F, 0xA8, 0x13]));
      expect(s.containsAll([0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20]), isTrue);
      expect(s.contains(0x02), isFalse);
    });

    test('RPM, coolant, trims, O2', () {
      expect(pidTable[0x0C]!.decode(Uint8List.fromList([0x0C, 0x50])).first.value, 788);
      expect(pidTable[0x05]!.decode(Uint8List.fromList([0x7B])).first.value, 83);
      expect(pidTable[0x07]!.decode(Uint8List.fromList([0x80])).first.value, 0);
      final o2 = pidTable[0x14]!.decode(Uint8List.fromList([0x5A, 0xFF]));
      expect(o2, hasLength(1)); // trim 0xFF = not used
      expect(o2.first.value, closeTo(0.45, 1e-9));
      expect(pidTable[0x42]!.decode(Uint8List.fromList([0x37, 0x6E])).first.value, closeTo(14.19, 0.01));
    });

    test('DTC bytes', () {
      expect(decodeDtcBytes(0x01, 0x33), 'P0133');
      expect(decodeDtcBytes(0x44, 0x20), 'C0420');
      expect(decodeDtcBytes(0x92, 0x34), 'B1234');
      expect(decodeDtcBytes(0xC1, 0x00), 'U0100');
      expect(decodeDtcBytes(0, 0), isNull);
      expect(decodeDtcPayload(Uint8List.fromList([0x43, 0x02, 0x04, 0x20, 0x01, 0x71]), isCan: true), ['P0420', 'P0171']);
    });

    test('monitor status', () {
      final m = MonitorStatus.decode(Uint8List.fromList([0x81, 0x07, 0x65, 0x01]));
      expect(m.milOn, isTrue);
      expect(m.dtcCount, 1);
      expect(m.sparkIgnition, isTrue);
      expect(m.monitors['Catalyst'], isFalse);
      expect(m.monitors['O2 sensor'], isTrue);
      expect(m.incomplete, 1);
    });

    test('VIN maker and year', () {
      expect(makerFromVin('MAT627108NLK12345'), 'Tata Motors');
      expect(makerFromVin('MA3ZFEB1SR0123456'), 'Maruti Suzuki');
      expect(modelYearFromVin('MAT627108NLK12345'), 2022);
      expect(modelYearFromVin('MA3ZFEB1SR0123456'), 2024);
    });
  });
}
