import 'package:carsense_obd/elm327/elm327.dart';
import 'package:carsense_obd/elm327/read_only_guard.dart';
import 'package:carsense_obd/transport/mock_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadOnlyGuard', () {
    test('allows read-only OBD services', () {
      for (final c in ['0100', '010C', '01 05', '03', '07', '0A', '0902', '0202', '0600']) {
        expect(ReadOnlyGuard.isAllowed(c), isTrue, reason: c);
      }
    });

    test('blocks clearing codes and any write / control service', () {
      for (final c in [
        '04', // clear DTCs / reset MIL
        '05', '08', '0801', // actuator tests
        '1003', '1101', '14FF00', '2EF190', '3101', '3400', '2701', '22F190',
        'XYZ', '', '0', '010', // malformed
      ]) {
        expect(ReadOnlyGuard.isAllowed(c), isFalse, reason: c);
      }
    });

    test('allows harmless AT commands and blocks risky ones', () {
      for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH1', 'ATSP0', 'ATDPN', 'ATRV', 'ATAT1', 'ATI', 'ATPC']) {
        expect(ReadOnlyGuard.isAllowed(c), isTrue, reason: c);
      }
      for (final c in ['ATPP0CSV23', 'ATPP0CON', 'ATSD01', 'ATBRD45', 'ATSH7E0', 'ATMA', 'ATCRA7E8', 'ATWM']) {
        expect(ReadOnlyGuard.isAllowed(c), isFalse, reason: c);
      }
    });

    test('Elm327.send refuses blocked commands before touching the transport', () async {
      final mock = MockTransport(DemoCar.swiftFaulty, latency: Duration.zero);
      final elm = Elm327(mock);
      await elm.connect();
      final before = mock.received.length;
      expect(() => elm.send('04'), throwsA(isA<ReadOnlyViolation>()));
      expect(mock.received.length, before);
      expect(mock.received.where((c) => c.startsWith('04')), isEmpty);
      await elm.close();
    });
  });
}
