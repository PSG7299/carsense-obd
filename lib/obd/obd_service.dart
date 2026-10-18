import 'dart:async';
import 'dart:typed_data';

import '../diagnostics/health_engine.dart';
import '../elm327/elm327.dart';
import '../vehicles/profiles.dart';
import '../vehicles/vehicle_profile.dart';
import 'dtc.dart';
import 'monitors.dart';
import 'pids.dart';
import 'vin.dart';

typedef Progress = void Function(String step, double fraction);

/// High-level, read-only OBD-II operations on top of [Elm327].
class ObdService {
  ObdService(this.elm);
  final Elm327 elm;

  Set<int> supported = {};
  String? vin;
  String maker = 'Unknown';
  int? modelYear;

  bool get isCan => elm.protocol.isCan;

  Future<Set<int>> discoverSupportedPids() async {
    final out = <int>{};
    for (var base = 0x00; base <= 0xC0; base += 0x20) {
      if (base != 0 && !out.contains(base)) break;
      final msgs = await elm.request('01${_h(base)}');
      if (msgs.isEmpty) break;
      for (final m in msgs) {
        if (m.data.length >= 6 && m.data[1] == base) {
          out.addAll(decodeSupported(base, m.data.sublist(2)));
        }
      }
    }
    supported = out;
    return out;
  }

  /// Raw data bytes (after service + PID) from the first ECU that answers.
  Future<Uint8List?> _pidData(int pid) async {
    final msgs = await elm.request('01${_h(pid)}');
    for (final m in msgs) {
      if (m.data.length > 2 && m.data[1] == pid) return m.data.sublist(2);
    }
    return null;
  }

  Future<List<Reading>> readPid(int pid) async {
    final def = pidTable[pid];
    if (def == null) return const [];
    final d = await _pidData(pid);
    if (d == null) return const [];
    try {
      return def.decode(d);
    } catch (_) {
      return const [];
    }
  }

  Future<MonitorStatus?> readMonitors() async {
    final d = await _pidData(0x01);
    return d == null || d.length < 4 ? null : MonitorStatus.decode(d);
  }

  Future<int?> readFuelSystem() async {
    if (!supported.contains(0x03)) return null;
    final d = await _pidData(0x03);
    return d == null || d.isEmpty ? null : d[0];
  }

  Future<List<String>> readO2Present() async {
    if (!supported.contains(0x13)) return const [];
    final d = await _pidData(0x13);
    return d == null || d.isEmpty ? const [] : decodeO2Present(d[0]);
  }

  Future<String?> readFuelType() async {
    if (!supported.contains(0x51)) return null;
    final d = await _pidData(0x51);
    return d == null || d.isEmpty ? null : fuelType(d[0]);
  }

  Future<List<Dtc>> readDtcs() async {
    final out = <Dtc>[];
    for (final (cmd, kind) in [('03', DtcKind.stored), ('07', DtcKind.pending), ('0A', DtcKind.permanent)]) {
      final msgs = await elm.request(cmd, timeout: const Duration(seconds: 5));
      for (final m in msgs) {
        for (final code in decodeDtcPayload(m.data, isCan: isCan)) {
          out.add(Dtc(code, kind, ecu: m.ecu));
        }
      }
    }
    return out;
  }

  Future<String?> readVin() async {
    final msgs = await elm.request('0902', timeout: const Duration(seconds: 5));
    for (final m in msgs) {
      final v = decodeVin(m.data);
      if (v != null && v.length == 17) {
        vin = v;
        maker = makerFromVin(v);
        modelYear = modelYearFromVin(v);
        return v;
      }
    }
    return null;
  }

  /// Every mode 01 PID we can decode and the car supports (excluding status PIDs).
  List<int> get pollablePids => [
        for (final p in supported.toList()..sort())
          if (pidTable.containsKey(p)) p,
      ];

  /// Full read-only health scan. [profileOverride] forces a car profile.
  Future<ScanData> scan({
    VehicleProfile? profileOverride,
    Duration sampling = const Duration(seconds: 12),
    Progress? onProgress,
  }) async {
    void p(String s, double f) => onProgress?.call(s, f);

    p('Reading vehicle identity (VIN)…', 0.05);
    await readVin();
    final profile = profileOverride ?? profileForMaker(maker);

    p('Detecting which sensors this car has…', 0.12);
    await discoverSupportedPids();
    final o2 = await readO2Present();

    p('Reading check-engine light & self-tests…', 0.2);
    final monitors = await readMonitors();
    final fuelSys = await readFuelSystem();

    p('Reading fault codes (stored / pending / permanent)…', 0.28);
    final dtcs = await readDtcs();

    final samples = <String, List<double>>{};
    Future<void> sample(int pid) async {
      for (final r in await readPid(pid)) {
        samples.putIfAbsent(r.channel, () => []).add(r.value);
      }
    }

    Future<void> battery() async {
      final v = await elm.batteryVoltage();
      if (v != null) samples.putIfAbsent(batteryChannel.id, () => []).add(v);
    }

    void prog(Stopwatch sw, String s) =>
        p(s, 0.3 + 0.65 * (sw.elapsed.inMilliseconds / sampling.inMilliseconds).clamp(0.0, 1.0));

    // Phase 1: every supported reading, twice.
    final pids = pollablePids;
    final sw = Stopwatch()..start();
    for (var round = 1; round <= 2; round++) {
      for (final pid in pids) {
        await sample(pid);
      }
      await battery();
      prog(sw, 'Reading ${pids.length} live values (pass $round of 2)…');
    }

    // Phase 2: fast loop on signals that need many samples (idle stability,
    // O2 switching, short-term trims), so slow adapters still get enough data.
    final fast = [
      for (final pid in [0x0C, 0x06, 0x08, ...List.generate(8, (i) => 0x14 + i), ...List.generate(8, (i) => 0x24 + i), ...List.generate(8, (i) => 0x34 + i)])
        if (supported.contains(pid)) pid,
    ];
    var n = 0;
    while (sw.elapsed < sampling && fast.isNotEmpty) {
      for (final pid in fast) {
        await sample(pid);
      }
      if (++n % 8 == 0) {
        await battery();
        prog(sw, 'Watching O2 sensors and idle stability…');
      }
    }
    p('Analysing…', 0.98);

    return ScanData(
      profile: profile,
      vin: vin,
      maker: maker,
      modelYear: modelYear,
      protocol: elm.protocol.label,
      adapter: elm.adapterId,
      supportedPids: supported,
      o2Present: o2,
      fuelSystemCode: fuelSys,
      monitors: monitors,
      dtcs: dtcs,
      samples: samples,
    );
  }
}

String _h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
