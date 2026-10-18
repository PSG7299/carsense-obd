import 'dart:math' as math;

import '../obd/dtc.dart';
import '../obd/monitors.dart';
import '../obd/pids.dart';
import '../vehicles/vehicle_profile.dart';
import 'models.dart';

/// Everything collected during a scan, before evaluation.
class ScanData {
  ScanData({
    required this.profile,
    this.vin,
    this.maker = 'Unknown',
    this.modelYear,
    this.protocol = '',
    this.adapter = '',
    this.supportedPids = const {},
    this.o2Present = const [],
    this.fuelSystemCode,
    this.monitors,
    this.dtcs = const [],
    Map<String, List<double>>? samples,
  }) : samples = samples ?? {};

  final VehicleProfile profile;
  final String? vin;
  final String maker;
  final int? modelYear;
  final String protocol;
  final String adapter;
  final Set<int> supportedPids;
  final List<String> o2Present;
  final int? fuelSystemCode;
  final MonitorStatus? monitors;
  final List<Dtc> dtcs;
  final Map<String, List<double>> samples;
}

class _Ctx {
  _Ctx(this.d);
  final ScanData d;

  double? avg(String id) {
    final s = d.samples[id];
    if (s == null || s.isEmpty) return null;
    return s.reduce((a, b) => a + b) / s.length;
  }

  bool get running => (avg('RPM') ?? 0) > 400;
  bool get warm => (avg('ECT') ?? 0) >= 70;
  bool get closedLoop => d.fuelSystemCode == 2 || d.fuelSystemCode == 16;
  bool get idling => running && (avg('VSS') ?? 0) < 3 && (_max('RPM') ?? 0) < 1600;
  double? _max(String id) {
    final s = d.samples[id];
    return s == null || s.isEmpty ? null : s.reduce(math.max);
  }
}

typedef _Eval = (Status, String, String) Function(_Ctx c, List<double> s, Channel ch);

class HealthEngine {
  const HealthEngine();

  ScanReport evaluate(ScanData d, {BatteryTestResult? battery}) {
    final c = _Ctx(d);

    // Derived boost channel for turbo cars.
    if (d.profile.turbo && d.samples.containsKey('MAP') && d.samples.containsKey('BARO')) {
      final baro = c.avg('BARO')!;
      d.samples['BOOST'] = [for (final m in d.samples['MAP']!) m - baro];
    }

    final sensors = <SensorResult>[];
    d.samples.forEach((id, s) {
      if (s.isEmpty) return;
      final ch = channelTable[id];
      if (ch == null) return;
      final (status, msg, normal) = _evaluateChannel(c, id, s, ch);
      sensors.add(SensorResult(
        channelId: id,
        name: ch.name,
        unit: ch.unit,
        system: ch.system,
        min: s.reduce(math.min),
        max: s.reduce(math.max),
        avg: s.reduce((a, b) => a + b) / s.length,
        last: s.last,
        status: status,
        message: msg,
        normal: normal,
        samples: s.length > 120 ? s.sublist(s.length - 120) : List.of(s),
      ));
    });
    sensors.sort((a, b) {
      final sys = a.system.index.compareTo(b.system.index);
      return sys != 0 ? sys : b.status.index.compareTo(a.status.index);
    });

    final notes = <String>[...d.profile.notes];
    if (!c.running) {
      notes.add('Engine was OFF during the scan. Start the engine and let it idle for a full check of '
          'O2 sensors, fuel trims and charging.');
    } else if (!c.warm) {
      notes.add('Engine is still warming up – O2 sensor and fuel trim checks are more accurate once '
          'coolant is above 80 °C.');
    }
    if ((c.avg('VSS') ?? 0) > 3) {
      notes.add('Car was moving during the scan. For safety, run scans while parked.');
    }
    final distClr = c.avg('DIST_CLR');
    if (distClr != null && distClr < 50) {
      notes.add('Codes were cleared or battery disconnected recently (${distClr.round()} km ago) – '
          'some self-tests may still be incomplete.');
    }

    final systems = _systems(d, sensors, battery);
    final score = _score(d, sensors, battery);

    return ScanReport(
      time: DateTime.now(),
      profileId: d.profile.id,
      vehicleName: d.profile.name,
      vin: d.vin,
      maker: d.maker,
      modelYear: d.modelYear,
      protocol: d.protocol,
      adapter: d.adapter,
      engineRunning: c.running,
      score: score,
      systems: systems,
      sensors: sensors,
      dtcs: d.dtcs,
      monitors: d.monitors,
      detectedSensors: detectedSensors(d),
      notes: notes,
      fuelSystem: d.fuelSystemCode == null ? null : fuelSystemStatus(d.fuelSystemCode!),
      battery: battery,
    );
  }

  /// Physical sensors this car reports, derived from its supported PIDs.
  List<String> detectedSensors(ScanData d) {
    final out = <String>{};
    for (final pid in d.supportedPids) {
      if (pid >= 0x14 && pid <= 0x1B || pid >= 0x24 && pid <= 0x2B || pid >= 0x34 && pid <= 0x3B) {
        continue; // O2 sensors come from PID 13 below.
      }
      for (final ch in pidTable[pid]?.channels ?? const <Channel>[]) {
        if (ch.sensor != null) out.add(ch.sensor!);
      }
    }
    final wideband = d.supportedPids.any((p) => p >= 0x24 && p <= 0x2B || p >= 0x34 && p <= 0x3B);
    for (final pos in d.o2Present) {
      out.add(wideband && pos.endsWith('S1') ? 'Wide-band ${o2Label(pos)}' : o2Label(pos));
    }
    if (d.o2Present.isEmpty) {
      for (var i = 0; i < 8; i++) {
        if (d.supportedPids.contains(0x14 + i)) out.add(pidTable[0x14 + i]!.channels.first.sensor!);
      }
    }
    out.add(batteryChannel.sensor!);
    return out.toList()..sort();
  }

  (Status, String, String) _evaluateChannel(_Ctx c, String id, List<double> s, Channel ch) {
    // A temperature or position pinned at its encoding limit = wiring fault.
    final last = s.last;
    final pinned = s.every((v) => v <= ch.min + 0.01) || s.every((v) => v >= ch.max - 0.01);
    if (pinned && const {'ECT', 'IAT', 'AMBIENT', 'OIL_T', 'MAP', 'TPS', 'APP_D'}.contains(id)) {
      return (
        Status.fail,
        'Reading is stuck at the limit (${_fmt(last)} ${ch.unit}) – likely open or shorted sensor circuit/connector.',
        ''
      );
    }
    final rule = _rules[id] ?? (id.startsWith('O2V_') ? _o2Voltage : id.startsWith('LAMBDA_') && id != 'LAMBDA_CMD' ? _lambda : null);
    if (rule != null) return rule(c, s, ch);
    return (Status.info, 'Current value ${_fmt(_mean(s))} ${ch.unit}', '');
  }

  static final Map<String, _Eval> _rules = {
    'RPM': (c, s, ch) {
      if (!c.running) return (Status.info, 'Engine not running.', '');
      final r = c.d.profile.idleRpm;
      final sd = _std(s);
      if (!c.idling) return (Status.ok, 'Engine running (${_fmt(_mean(s))} rpm). Idle checks need the car parked at idle.', r.describe('rpm'));
      if (!c.warm) return (Status.info, 'Fast idle while warming up is normal (${_fmt(_mean(s))} rpm).', r.describe('rpm'));
      final st = _rate(_mean(s), r);
      if (sd > 80) {
        return (Status.warn.worst(st), 'Idle is unsteady (±${sd.round()} rpm). Possible misfire, vacuum leak or dirty throttle body.', r.describe('rpm'));
      }
      return (st, st == Status.ok ? 'Idle speed steady and normal.' : 'Idle speed ${_fmt(_mean(s))} rpm is outside the normal band.', r.describe('rpm'));
    },
    'ECT': (c, s, ch) {
      final r = c.d.profile.warmCoolant;
      final v = _mean(s);
      if (v > (r.warnHigh ?? 999)) return (Status.fail, 'Engine is overheating! Stop and check coolant level, fan and thermostat.', r.describe('°C'));
      if (v > r.okHigh) return (Status.warn, 'Coolant running hot. Check coolant level and radiator fan.', r.describe('°C'));
      if (!c.running) return (Status.ok, 'Sensor reading plausible (${_fmt(v)} °C, engine off).', r.describe('°C'));
      final runtime = c.avg('RUNTIME') ?? 0;
      if (runtime > 900 && v < (r.warnLow ?? 0)) {
        return (Status.warn, 'Engine not reaching operating temperature after ${(runtime / 60).round()} min – thermostat may be stuck open.', r.describe('°C'));
      }
      if (v < r.okLow) return (Status.info, 'Engine still warming up (${_fmt(v)} °C).', r.describe('°C'));
      return (Status.ok, 'Coolant temperature normal.', r.describe('°C'));
    },
    'IAT': (c, s, ch) {
      final v = _mean(s);
      if (v > 75) return (Status.warn, 'Intake air very hot – heat soak or IAT sensor drift.', '-10–70 °C');
      return (Status.ok, 'Intake air temperature plausible.', '-10–70 °C');
    },
    'AMBIENT': (c, s, ch) => (Status.ok, 'Ambient temperature plausible.', '-10–55 °C'),
    'OIL_T': (c, s, ch) {
      final v = _mean(s);
      if (v > 145) return (Status.fail, 'Engine oil far too hot.', '80–130 °C');
      if (v > 130) return (Status.warn, 'Engine oil running hot.', '80–130 °C');
      return (Status.ok, 'Oil temperature normal.', '80–130 °C');
    },
    'MAP': (c, s, ch) {
      final v = _mean(s);
      final baro = c.avg('BARO');
      if (!c.running) {
        final ref = baro ?? 98;
        if ((v - ref).abs() > 10) {
          return (Status.warn, 'With engine off MAP should equal air pressure (~${ref.round()} kPa) but reads ${_fmt(v)} kPa – sensor drift.', '≈ barometric');
        }
        return (Status.ok, 'MAP sensor matches atmospheric pressure (engine off).', '≈ barometric');
      }
      if (!c.idling) return (Status.ok, 'MAP responding (${_fmt(s.reduce(math.min))}–${_fmt(s.reduce(math.max))} kPa).', '');
      final r = c.d.profile.idleMap;
      final st = _rate(v, r);
      return (
        st,
        st == Status.ok ? 'Idle vacuum normal.' : v > r.okHigh ? 'Weak idle vacuum – possible vacuum leak, misfire or valve timing issue.' : 'Unusually low manifold pressure at idle.',
        r.describe('kPa')
      );
    },
    'BARO': (c, s, ch) => _rangeRule(_mean(s), const Range(60, 106, warnLow: 50, warnHigh: 110), 'kPa', 'Barometric pressure plausible.', 'Barometric pressure implausible – sensor fault.'),
    'BOOST': (c, s, ch) {
      final mx = s.reduce(math.max);
      final lim = c.d.profile.maxBoostKpa;
      if (mx > lim + 30) return (Status.warn, 'Boost peaked at ${_fmt(mx)} kPa – higher than expected (overboost / wastegate).', 'up to ~${lim.round()} kPa');
      if (mx < 5) return (Status.info, 'No boost during scan (normal at idle – rev or drive to test the turbo).', 'up to ~${lim.round()} kPa');
      return (Status.ok, 'Turbo producing boost (peak ${_fmt(mx)} kPa).', 'up to ~${lim.round()} kPa');
    },
    'TPS': (c, s, ch) {
      final v = _mean(s);
      if (c.idling && v > 30) return (Status.warn, 'Throttle reads ${_fmt(v)}% at idle – throttle body dirty or sensor offset.', '< 25% at idle');
      return (Status.ok, 'Throttle position sensor responding.', '< 25% at idle');
    },
    'APP_D': (c, s, ch) {
      final v = _mean(s);
      if (!c.running || c.idling) {
        return v < 25
            ? (Status.ok, 'Pedal sensor reads released position.', '< 25% released')
            : (Status.warn, 'Pedal reads ${_fmt(v)}% while released – check pedal sensor (or pedal was pressed).', '< 25% released');
      }
      return (Status.ok, 'Pedal sensor responding.', '');
    },
    'STFT1': _trimRule,
    'STFT2': _trimRule,
    'LTFT1': _trimRule,
    'LTFT2': _trimRule,
    'CAT_B1S1': _catTemp,
    'CAT_B1S2': _catTemp,
    'BATT': _voltageRule,
    'ECU_V': _voltageRule,
    'LOAD': (c, s, ch) {
      if (!c.idling || !c.warm) return (Status.info, 'Engine load ${_fmt(_mean(s))}%.', '');
      final v = _mean(s);
      return v > 50
          ? (Status.warn, 'High load at idle (${_fmt(v)}%) – A/C on, dragging accessory or air metering error.', '15–45% at warm idle')
          : (Status.ok, 'Idle load normal.', '15–45% at warm idle');
    },
    'TIMING': (c, s, ch) {
      if (!c.idling || !c.warm) return (Status.info, 'Timing advance ${_fmt(_mean(s))}°.', '');
      final v = _mean(s);
      return v < -2
          ? (Status.warn, 'Ignition timing retarded at idle – ECU may be pulling timing for knock.', '0–20° at idle')
          : (Status.ok, 'Ignition timing normal at idle.', '0–20° at idle');
    },
    'FUEL_LVL': (c, s, ch) => _mean(s) < 10
        ? (Status.warn, 'Fuel is low (${_fmt(_mean(s))}%). Running on low fuel can overheat the fuel pump.', '> 10%')
        : (Status.ok, 'Fuel level ${_fmt(_mean(s))}%.', ''),
    'DIST_MIL': (c, s, ch) => _mean(s) > 0
        ? (Status.warn, 'Driven ${_fmt(_mean(s))} km with the check-engine light on.', '0 km')
        : (Status.ok, 'Check-engine light has not been on.', '0 km'),
    'TIME_MIL': (c, s, ch) => _mean(s) > 0
        ? (Status.warn, 'Engine run ${_fmt(_mean(s))} min with the check-engine light on.', '0 min')
        : (Status.ok, 'Check-engine light has not been on.', '0 min'),
  };

  static (Status, String, String) _trimRule(_Ctx c, List<double> s, Channel ch) {
    const normal = '−10 … +10 %';
    if (!c.running) return (Status.info, 'Fuel trims are only meaningful with the engine running.', normal);
    if (!c.closedLoop) return (Status.info, 'Engine in open loop – trims not active yet.', normal);
    final v = _mean(s);
    final a = v.abs();
    final dir = v > 0
        ? 'ECU is adding fuel → engine running lean (vacuum/intake leak, weak fuel pump, dirty injectors or MAP/MAF error).'
        : 'ECU is removing fuel → engine running rich (leaking injector, high fuel pressure, purge valve stuck open, sensor error).';
    if (a <= 10) return (Status.ok, 'Fuel mixture well balanced (${_fmt(v)}%).', normal);
    if (a <= 20) return (Status.warn, '${_fmt(v)}%: $dir', normal);
    return (Status.fail, '${_fmt(v)}%: $dir', normal);
  }

  static (Status, String, String) _o2Voltage(_Ctx c, List<double> s, Channel ch) {
    final pos = ch.id.substring(4); // B1S1
    final upstream = pos.endsWith('S1');
    const normalUp = 'switches 0.1 ↔ 0.9 V';
    const normalDown = 'steady 0.5–0.8 V';
    final normal = upstream ? normalUp : normalDown;
    if (!c.running) return (Status.info, 'Start the engine to test this O2 sensor.', normal);
    if (!c.warm || !c.closedLoop) return (Status.info, 'Engine still warming up – sensor not tested yet.', normal);

    final mn = s.reduce(math.min), mx = s.reduce(math.max), avg = _mean(s);
    final switches = _crossings(s, 0.45);
    if (upstream) {
      if (mx - mn < 0.3) {
        if (avg < 0.25) return (Status.fail, 'Stuck lean (${_fmt(avg)} V). Sensor failed, or real lean condition / exhaust leak.', normal);
        if (avg > 0.75) return (Status.fail, 'Stuck rich (${_fmt(avg)} V). Sensor contaminated or engine running rich.', normal);
        return (Status.fail, 'No activity (${_fmt(avg)} V) – sensor dead or heater not working.', normal);
      }
      if (switches < 2) return (Status.warn, 'Sensor responds slowly ($switches switches). Ageing sensor – consider replacing.', normal);
      return (Status.ok, 'Switching normally ($switches switches, ${_fmt(mn)}–${_fmt(mx)} V).', normal);
    }

    // Downstream: should be steady if the catalyst stores oxygen.
    final upKey = 'O2V_${pos.substring(0, 2)}S1';
    final up = c.d.samples[upKey];
    final upSwitches = up == null ? 0 : _crossings(up, 0.45);
    if (mx < 0.2) return (Status.warn, 'Reads lean constantly (${_fmt(avg)} V) – exhaust leak or failing sensor.', normal);
    if (upSwitches >= 4 && switches >= upSwitches * 0.75) {
      return (Status.warn, 'Switches almost as often as the front sensor – catalytic converter efficiency may be low.', normal);
    }
    return (Status.ok, 'Steady signal (${_fmt(avg)} V) – catalyst is working.', normal);
  }

  static (Status, String, String) _lambda(_Ctx c, List<double> s, Channel ch) {
    const normal = 'λ 0.97–1.03';
    if (!c.running || !c.closedLoop) return (Status.info, 'Lambda ${_fmt(_mean(s))} (tested at warm idle).', normal);
    return _rangeRule(_mean(s), const Range(0.95, 1.05, warnLow: 0.9, warnHigh: 1.1), '', 'Air-fuel ratio on target.',
        'Air-fuel ratio off target – check fuel trims and O2 sensor.');
  }

  static (Status, String, String) _catTemp(_Ctx c, List<double> s, Channel ch) => _rangeRule(
      _mean(s), const Range(-40, 900, warnHigh: 1000), '°C', 'Catalyst temperature normal.', 'Catalyst overheating – usually caused by misfires or a rich mixture.');

  static (Status, String, String) _voltageRule(_Ctx c, List<double> s, Channel ch) {
    final v = _mean(s);
    if (c.running) {
      const r = Range(13.2, 14.8, warnLow: 12.6, warnHigh: 15.0);
      final st = _rate(v, r);
      final msg = switch (st) {
        Status.ok => 'Alternator charging normally (${_fmt(v)} V).',
        _ when v > r.okHigh => 'Overcharging (${_fmt(v)} V) – voltage regulator fault; can damage the battery.',
        Status.warn => 'Low charging voltage (${_fmt(v)} V). Normal briefly with smart charging; if constant, check alternator belt/alternator.',
        _ => 'Battery is NOT being charged (${_fmt(v)} V) – alternator, belt or wiring fault.',
      };
      return (st, msg, r.describe('V running'));
    }
    const r = Range(12.4, 13.0, warnLow: 12.0, warnHigh: 13.4);
    if (v > 13.0) return (Status.ok, 'Surface charge (${_fmt(v)} V) – car was recently driven or charging.', r.describe('V engine off'));
    final st = _rate(v, r);
    final msg = switch (st) {
      Status.ok => 'Battery well charged (${_fmt(v)} V).',
      Status.warn => 'Battery partly discharged (${_fmt(v)} V). Drive for 30 min or charge it.',
      _ => 'Battery low (${_fmt(v)} V) – may fail to start. Charge and load-test the battery.',
    };
    return (st, msg, r.describe('V engine off'));
  }

  static (Status, String, String) _rangeRule(double v, Range r, String unit, String okMsg, String badMsg) {
    final st = _rate(v, r);
    return (st, st == Status.ok ? okMsg : '$badMsg (${_fmt(v)} $unit)', r.describe(unit));
  }

  static Status _rate(double v, Range r) {
    if (v >= r.okLow && v <= r.okHigh) return Status.ok;
    if (v < r.okLow) return r.warnLow == null || v >= r.warnLow! ? Status.warn : Status.fail;
    return r.warnHigh == null || v <= r.warnHigh! ? Status.warn : Status.fail;
  }

  List<SystemResult> _systems(ScanData d, List<SensorResult> sensors, BatteryTestResult? battery) {
    final out = <SystemResult>[];
    for (final sys in CarSystem.values) {
      final members = sensors.where((s) => s.system == sys && s.status != Status.info).toList();
      var status = Status.ok;
      var warn = 0, fail = 0;
      final issues = <String>[];
      for (final m in members) {
        status = status.worst(m.status);
        if (m.status == Status.warn) warn++;
        if (m.status == Status.fail) fail++;
        if (m.status.index >= Status.warn.index) issues.add(m.name);
      }
      var summary = '';
      var hasData = members.isNotEmpty;

      if (sys == CarSystem.faults) {
        hasData = true;
        final stored = d.dtcs.where((x) => x.kind != DtcKind.pending).length;
        final pending = d.dtcs.where((x) => x.kind == DtcKind.pending).length;
        fail += stored;
        warn += pending;
        if (stored > 0) status = status.worst(Status.fail);
        if (pending > 0) status = status.worst(Status.warn);
        if (d.monitors?.milOn ?? false) status = status.worst(Status.fail);
        summary = d.dtcs.isEmpty
            ? 'No fault codes stored.'
            : '${d.dtcs.length} code(s): ${d.dtcs.map((x) => x.code).toSet().join(', ')}';
        if (d.monitors?.milOn ?? false) summary = 'Check-engine light ON. $summary';
      } else if (sys == CarSystem.emissions && d.monitors != null) {
        hasData = true;
        final inc = d.monitors!.monitors.entries.where((e) => !e.value).map((e) => e.key).toList();
        if (inc.isNotEmpty) {
          status = status.worst(Status.warn);
          warn += 1;
        }
        summary = inc.isEmpty
            ? 'All ${d.monitors!.monitors.length} self-tests complete.'
            : '${inc.length} self-test(s) not complete: ${inc.join(', ')}';
      } else if (sys == CarSystem.electrical && battery != null) {
        hasData = true;
        status = status.worst(battery.status);
        if (battery.status == Status.warn) warn++;
        if (battery.status == Status.fail) fail++;
        summary = battery.verdict.first;
      }
      if (!hasData) continue;
      if (summary.isEmpty) {
        summary = issues.isEmpty ? 'All ${members.length} reading(s) normal.' : 'Check: ${issues.join(', ')}';
      }
      out.add(SystemResult(sys, status, (100 - warn * 12 - fail * 35).clamp(0, 100), summary));
    }
    return out;
  }

  int _score(ScanData d, List<SensorResult> sensors, BatteryTestResult? battery) {
    var score = 100.0;
    for (final s in sensors) {
      if (s.status == Status.warn) score -= 4;
      if (s.status == Status.fail) score -= 12;
    }
    for (final x in d.dtcs) {
      score -= switch ((x.kind, x.severity)) {
        (DtcKind.pending, _) => 5,
        (DtcKind.permanent, _) => 6,
        (_, Severity.high) => 20,
        (_, Severity.medium) => 12,
        (_, Severity.low) => 5,
      };
    }
    if (d.monitors?.milOn ?? false) score -= 10;
    score -= math.min(8, (d.monitors?.incomplete ?? 0) * 2);
    if (battery != null) {
      if (battery.status == Status.warn) score -= 6;
      if (battery.status == Status.fail) score -= 15;
    }
    return score.round().clamp(0, 100);
  }

  /// Analyses an ATRV trace recorded while the user starts the engine.
  BatteryTestResult analyseBattery(List<List<double>> trace) {
    final verdict = <String>[];
    if (trace.length < 5) {
      return BatteryTestResult(
          restVoltage: null, crankMin: null, chargingVoltage: null, status: Status.info, verdict: ['Not enough data recorded.'], trace: trace);
    }
    final volts = [for (final p in trace) p[1]];
    var minIdx = 0;
    for (var i = 1; i < volts.length; i++) {
      if (volts[i] < volts[minIdx]) minIdx = i;
    }
    final before = volts.sublist(0, math.max(1, math.min(minIdx, 10)));
    final rest = _median(before);
    final crankMin = volts[minIdx];
    final cranked = rest - crankMin > 1.0;
    final after = cranked ? volts.sublist(minIdx) : volts;
    final tail = after.sublist(math.max(0, after.length - math.min(after.length, 15)));
    final charging = _median(tail);
    final engineStarted = cranked && charging > rest + 0.3;

    var status = Status.ok;
    // Resting battery
    if (rest >= 12.4) {
      verdict.add('Battery at rest ${_fmt(rest)} V – well charged.');
    } else if (rest >= 12.0) {
      status = status.worst(Status.warn);
      verdict.add('Battery at rest ${_fmt(rest)} V – partly discharged.');
    } else {
      status = status.worst(Status.fail);
      verdict.add('Battery at rest ${_fmt(rest)} V – low; may not start the car.');
    }
    // Cranking
    if (!cranked) {
      verdict.add('No engine start detected – start the engine during the test to check cranking.');
    } else if (crankMin >= 9.6) {
      verdict.add('Cranking voltage ${_fmt(crankMin)} V – battery and starter healthy.');
    } else if (crankMin >= 9.0) {
      status = status.worst(Status.warn);
      verdict.add('Cranking voltage ${_fmt(crankMin)} V – battery is getting weak.');
    } else {
      status = status.worst(Status.fail);
      verdict.add('Cranking voltage ${_fmt(crankMin)} V – battery weak or failing; replace soon.');
    }
    // Charging
    if (engineStarted) {
      if (charging > 15.0) {
        status = status.worst(Status.fail);
        verdict.add('Charging ${_fmt(charging)} V – overcharging, regulator fault.');
      } else if (charging >= 13.2) {
        verdict.add('Charging ${_fmt(charging)} V – alternator working.');
      } else if (charging >= 12.6) {
        status = status.worst(Status.warn);
        verdict.add('Charging ${_fmt(charging)} V – low (may be smart charging; re-test with headlights + A/C on).');
      } else {
        status = status.worst(Status.fail);
        verdict.add('Charging ${_fmt(charging)} V – alternator not charging.');
      }
    }
    // Put the headline first.
    final headline = switch (status) {
      Status.ok => 'Battery & charging healthy',
      Status.warn => 'Battery & charging need attention',
      Status.fail => 'Battery or charging problem',
      Status.info => 'Battery test incomplete',
    };
    return BatteryTestResult(
      restVoltage: rest,
      crankMin: cranked ? crankMin : null,
      chargingVoltage: engineStarted ? charging : null,
      status: status,
      verdict: ['$headline. ${verdict.first}', ...verdict.skip(1)],
      trace: trace,
    );
  }
}

double _mean(List<double> s) => s.reduce((a, b) => a + b) / s.length;

double _std(List<double> s) {
  final m = _mean(s);
  return math.sqrt(s.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / s.length);
}

double _median(List<double> s) {
  final c = List.of(s)..sort();
  return c[c.length ~/ 2];
}

int _crossings(List<double> s, double level) {
  var n = 0;
  for (var i = 1; i < s.length; i++) {
    if ((s[i - 1] - level) * (s[i] - level) < 0) n++;
  }
  return n;
}

String _fmt(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
