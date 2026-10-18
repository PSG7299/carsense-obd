import 'dart:convert';
import 'dart:io';

import 'package:carsense_obd/diagnostics/health_engine.dart';
import 'package:carsense_obd/elm327/elm327.dart';
import 'package:carsense_obd/obd/dtc.dart';
import 'package:carsense_obd/obd/obd_service.dart';
import 'package:carsense_obd/transport/replay_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-checks the app against the independent MATLAB implementation:
/// every replay recorded by simulation/run_simulation.m is "connected" to,
/// scanned and diagnosed by the app, and the verdicts must equal the ones
/// MATLAB stored under "expected".
void main() {
  final files = Directory('assets/simulations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('replay files exist', () => expect(files.length, greaterThanOrEqualTo(18)));

  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceAll('.json', '');
    test('app matches MATLAB: $name', () async {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final expected = json['expected'] as Map<String, dynamic>;
      final transport = ReplayTransport(json, latency: Duration.zero);
      final elm = Elm327(transport);
      await elm.connect();
      // 2 full passes + 298 fast rounds = the same 300-sample window MATLAB judged.
      final data = await ObdService(elm).scan(fastRounds: 298);
      await elm.close();
      final report = const HealthEngine().evaluate(data);

      expect(report.vin, json['vin']);
      final statuses = {for (final s in report.sensors) s.channelId: s.status.name};
      for (final e in expected['statuses'] as List) {
        final id = e['id'] as String;
        expect(statuses[id], e['status'], reason: '$name: $id (${report.sensors.where((s) => s.channelId == id).map((s) => s.message).join()})');
      }
      String codes(DtcKind k) => (report.dtcs.where((d) => d.kind == k).map((d) => d.code).toList()..sort()).join(',');
      expect(codes(DtcKind.stored), (List<String>.from(expected['stored'] as List)..sort()).join(','));
      expect(codes(DtcKind.pending), (List<String>.from(expected['pending'] as List)..sort()).join(','));
      expect(report.score, closeTo(expected['score'] as int, 2), reason: '$name score');

      final trace = [
        for (final (i, s) in (json['atrv_test'] as List).indexed) [i * 0.1, double.parse((s as String).replaceAll('V', ''))],
      ];
      expect(const HealthEngine().analyseBattery(trace).status.name, expected['battery'], reason: '$name battery');
    });
  }
}
