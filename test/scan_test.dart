import 'package:carsense_obd/diagnostics/health_engine.dart';
import 'package:carsense_obd/diagnostics/models.dart';
import 'package:carsense_obd/elm327/elm327.dart';
import 'package:carsense_obd/obd/dtc.dart';
import 'package:carsense_obd/obd/obd_service.dart';
import 'package:carsense_obd/obd/pids.dart';
import 'package:carsense_obd/transport/mock_transport.dart';
import 'package:carsense_obd/vehicles/profiles.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(ScanReport, MockTransport)> _scan(DemoCar car) async {
  final mock = MockTransport(car, latency: const Duration(milliseconds: 1), seed: 7);
  final elm = Elm327(mock);
  await elm.connect();
  final data = await ObdService(elm).scan(sampling: const Duration(seconds: 3));
  final report = const HealthEngine().evaluate(data);
  await elm.close();
  return (report, mock);
}

void main() {
  test('healthy Nexon: detected as Tata, CAN, high score, no faults', () async {
    final (r, mock) = await _scan(DemoCar.nexonHealthy);
    expect(r.profileId, nexonPetrol.id);
    expect(r.maker, 'Tata Motors');
    expect(r.vin, 'MAT627108NLK12345');
    expect(r.protocol, contains('CAN'));
    expect(r.dtcs, isEmpty);
    expect(r.engineRunning, isTrue);
    expect(r.score, greaterThanOrEqualTo(85), reason: r.sensors.where((s) => s.status.index >= 2).map((s) => '${s.name}: ${s.message}').join('\n'));
    expect(r.detectedSensors, contains(o2Label('B1S1')));
    expect(r.detectedSensors, contains(o2Label('B1S2')));
    expect(r.detectedSensors.any((s) => s.contains('coolant')), isTrue);
    // Never sent anything outside the read-only set.
    expect(mock.received.where((c) => c == '04' || c.startsWith('04')), isEmpty);
  });

  test('healthy Swift detected as Maruti Swift', () async {
    final (r, _) = await _scan(DemoCar.swiftHealthy);
    expect(r.profileId, swiftPetrol.id);
    expect(r.overall, Status.ok);
  });

  test('faulty Swift: catalyst, lean trims, codes and MIL found', () async {
    final (r, _) = await _scan(DemoCar.swiftFaulty);
    expect(r.dtcs.map((d) => '${d.code}/${d.kind.name}'), containsAll(['P0420/stored', 'P0171/pending']));
    expect(r.monitors!.milOn, isTrue);
    final ltft = r.sensors.firstWhere((s) => s.channelId == 'LTFT1');
    expect(ltft.status, Status.warn);
    final rear = r.sensors.firstWhere((s) => s.channelId == 'O2V_B1S2');
    expect(rear.status, Status.warn);
    expect(rear.message, contains('catalytic'));
    final faults = r.systems.firstWhere((s) => s.system == CarSystem.faults);
    expect(faults.status, Status.fail);
    expect(r.score, lessThan(60));
    expect(DtcKind.values, hasLength(3));
  });

  test('battery test: healthy vs weak', () {
    const e = HealthEngine();
    List<List<double>> trace(double rest, double crank, double run) => [
          for (var i = 0; i < 15; i++) [i * 0.2, rest],
          for (var i = 0; i < 5; i++) [3 + i * 0.2, crank],
          for (var i = 0; i < 20; i++) [4 + i * 0.2, run],
        ];
    final good = e.analyseBattery(trace(12.6, 10.4, 14.1));
    expect(good.status, Status.ok);
    expect(good.crankMin, 10.4);
    expect(good.chargingVoltage, 14.1);
    final weak = e.analyseBattery(trace(12.2, 9.3, 13.0));
    expect(weak.status, Status.warn);
    final dead = e.analyseBattery(trace(11.7, 8.1, 12.2));
    expect(dead.status, Status.fail);
  });

  test('report survives JSON round trip', () async {
    final (r, _) = await _scan(DemoCar.swiftFaulty);
    final back = ScanReport.fromJson(r.toJson());
    expect(back.score, r.score);
    expect(back.dtcs.length, r.dtcs.length);
    expect(back.sensors.length, r.sensors.length);
  });
}
