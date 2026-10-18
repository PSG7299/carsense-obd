/// SAE J1979 mode 01 PID definitions and decoders.
library;

import 'dart:typed_data';

/// Which part of the car a reading belongs to – used to group the dashboard.
enum CarSystem {
  engine('Engine', 'Speed, load, timing'),
  intake('Air intake', 'MAP, MAF, throttle, air temp'),
  fuel('Fuel system', 'Fuel trims, fuel level, pressure'),
  o2Catalyst('O2 sensors & catalyst', 'Lambda sensors, catalytic converter'),
  cooling('Cooling', 'Coolant & oil temperature'),
  electrical('Battery & charging', 'Battery voltage, alternator'),
  emissions('Emissions self-tests', 'Readiness monitors, EVAP, EGR'),
  faults('Fault codes', 'Stored, pending and permanent DTCs');

  const CarSystem(this.label, this.description);
  final String label;
  final String description;
}

/// One decoded value. A single PID can yield several (e.g. O2 voltage + trim).
class Reading {
  const Reading(this.channel, this.value);
  final String channel;
  final double value;
}

/// Static description of a measurable channel.
class Channel {
  const Channel(this.id, this.name, this.unit, this.system,
      {this.min = 0, this.max = 100, this.sensor});
  final String id;
  final String name;
  final String unit;
  final CarSystem system;

  /// Physical range of the encoding – values pinned at an extreme often mean
  /// an open or shorted sensor circuit.
  final double min;
  final double max;

  /// Physical sensor this channel comes from (for the "detected sensors" list).
  final String? sensor;
}

typedef Decoder = List<Reading> Function(Uint8List d);

class PidDef {
  const PidDef(this.pid, this.channels, this.decode);
  final int pid;
  final List<Channel> channels;
  final Decoder decode;
}

double _a(Uint8List d) => d[0].toDouble();
double _ab(Uint8List d) => (d[0] * 256 + d[1]).toDouble();
double _pct(Uint8List d) => d[0] * 100 / 255;
double _trim(int v) => (v - 128) * 100 / 128;

PidDef _single(int pid, Channel c, double Function(Uint8List) f, {int bytes = 1}) =>
    PidDef(pid, [c], (d) => d.length < bytes ? const [] : [Reading(c.id, f(d))]);

const _o2Names = ['B1S1', 'B1S2', 'B1S3', 'B1S4', 'B2S1', 'B2S2', 'B2S3', 'B2S4'];

String o2Label(String pos) {
  final bank = pos[1];
  final s = pos[3];
  final where = s == '1' ? 'upstream / before catalyst' : 'downstream / after catalyst';
  return 'O2 sensor bank $bank sensor $s ($where)';
}

final Map<int, PidDef> pidTable = _buildTable();

Map<int, PidDef> _buildTable() {
  final t = <int, PidDef>{};
  void add(PidDef p) => t[p.pid] = p;

  add(_single(0x04, const Channel('LOAD', 'Calculated engine load', '%', CarSystem.engine), _pct));
  add(_single(
      0x05,
      const Channel('ECT', 'Coolant temperature', '°C', CarSystem.cooling,
          min: -40, max: 215, sensor: 'Engine coolant temperature sensor (ECT)'),
      (d) => _a(d) - 40));
  add(_single(0x06, const Channel('STFT1', 'Short-term fuel trim B1', '%', CarSystem.fuel, min: -100, max: 99.2), (d) => _trim(d[0])));
  add(_single(0x07, const Channel('LTFT1', 'Long-term fuel trim B1', '%', CarSystem.fuel, min: -100, max: 99.2), (d) => _trim(d[0])));
  add(_single(0x08, const Channel('STFT2', 'Short-term fuel trim B2', '%', CarSystem.fuel, min: -100, max: 99.2), (d) => _trim(d[0])));
  add(_single(0x09, const Channel('LTFT2', 'Long-term fuel trim B2', '%', CarSystem.fuel, min: -100, max: 99.2), (d) => _trim(d[0])));
  add(_single(
      0x0A,
      const Channel('FP', 'Fuel pressure (gauge)', 'kPa', CarSystem.fuel, max: 765, sensor: 'Fuel pressure sensor'),
      (d) => _a(d) * 3));
  add(_single(
      0x0B,
      const Channel('MAP', 'Intake manifold pressure', 'kPa', CarSystem.intake,
          max: 255, sensor: 'Manifold absolute pressure sensor (MAP / T-MAP)'),
      _a));
  add(_single(
      0x0C,
      const Channel('RPM', 'Engine speed', 'rpm', CarSystem.engine,
          max: 16383, sensor: 'Crankshaft position sensor (CKP)'),
      (d) => _ab(d) / 4,
      bytes: 2));
  add(_single(
      0x0D,
      const Channel('VSS', 'Vehicle speed', 'km/h', CarSystem.engine,
          max: 255, sensor: 'Vehicle speed sensor (VSS / ABS wheel speed)'),
      _a));
  add(_single(0x0E, const Channel('TIMING', 'Ignition timing advance', '°', CarSystem.engine, min: -64, max: 63.5), (d) => _a(d) / 2 - 64));
  add(_single(
      0x0F,
      const Channel('IAT', 'Intake air temperature', '°C', CarSystem.intake,
          min: -40, max: 215, sensor: 'Intake air temperature sensor (IAT)'),
      (d) => _a(d) - 40));
  add(_single(
      0x10,
      const Channel('MAF', 'Mass air flow', 'g/s', CarSystem.intake, max: 655, sensor: 'Mass air flow sensor (MAF)'),
      (d) => _ab(d) / 100,
      bytes: 2));
  add(_single(
      0x11,
      const Channel('TPS', 'Throttle position', '%', CarSystem.intake, sensor: 'Throttle position sensor (TPS)'),
      _pct));

  // Narrow-band O2 sensors 0x14..0x1B: voltage + short-term trim.
  for (var i = 0; i < 8; i++) {
    final pos = _o2Names[i];
    final v = Channel('O2V_$pos', 'O2 $pos voltage', 'V', CarSystem.o2Catalyst,
        max: 1.275, sensor: o2Label(pos));
    final tr = Channel('O2T_$pos', 'O2 $pos fuel trim', '%', CarSystem.o2Catalyst, min: -100, max: 99.2);
    add(PidDef(0x14 + i, [v, tr], (d) {
      if (d.length < 2) return const [];
      return [
        Reading(v.id, d[0] / 200),
        if (d[1] != 0xFF) Reading(tr.id, _trim(d[1])),
      ];
    }));
  }

  add(_single(0x1F, const Channel('RUNTIME', 'Run time since start', 's', CarSystem.engine, max: 65535), _ab, bytes: 2));
  add(_single(0x21, const Channel('DIST_MIL', 'Distance with check-engine light on', 'km', CarSystem.faults, max: 65535), _ab, bytes: 2));
  add(_single(0x2C, const Channel('EGR_CMD', 'Commanded EGR', '%', CarSystem.emissions), _pct));
  add(_single(0x2E, const Channel('EVAP', 'Commanded EVAP purge', '%', CarSystem.emissions, sensor: 'EVAP purge solenoid'), _pct));
  add(_single(0x2F, const Channel('FUEL_LVL', 'Fuel tank level', '%', CarSystem.fuel, sensor: 'Fuel level sender'), _pct));
  add(_single(0x30, const Channel('WARMUPS', 'Warm-ups since codes cleared', '', CarSystem.emissions, max: 255), _a));
  add(_single(0x31, const Channel('DIST_CLR', 'Distance since codes cleared', 'km', CarSystem.emissions, max: 65535), _ab, bytes: 2));
  add(_single(
      0x33,
      const Channel('BARO', 'Barometric pressure', 'kPa', CarSystem.intake, max: 255, sensor: 'Barometric pressure sensor'),
      _a));

  // Wide-band O2 sensors 0x24..0x2B (lambda + voltage) and 0x34..0x3B (lambda + current).
  for (var i = 0; i < 8; i++) {
    final pos = _o2Names[i];
    final lam = Channel('LAMBDA_$pos', 'Wide-band O2 $pos lambda', 'λ', CarSystem.o2Catalyst,
        max: 2, sensor: 'Wide-band ${o2Label(pos)}');
    add(PidDef(0x24 + i, [lam], (d) => d.length < 4 ? const [] : [Reading(lam.id, _ab(d) * 2 / 65536)]));
    final lam2 = Channel('LAMBDA_$pos', 'Wide-band O2 $pos lambda', 'λ', CarSystem.o2Catalyst,
        max: 2, sensor: 'Wide-band ${o2Label(pos)}');
    final cur = Channel('O2I_$pos', 'Wide-band O2 $pos current', 'mA', CarSystem.o2Catalyst, min: -128, max: 128);
    add(PidDef(0x34 + i, [lam2, cur], (d) {
      if (d.length < 4) return const [];
      return [
        Reading(lam2.id, _ab(d) * 2 / 65536),
        Reading(cur.id, (d[2] * 256 + d[3]) / 256 - 128),
      ];
    }));
  }

  add(_single(
      0x3C,
      const Channel('CAT_B1S1', 'Catalyst temperature B1S1', '°C', CarSystem.o2Catalyst,
          min: -40, max: 6513, sensor: 'Catalyst temperature (B1S1)'),
      (d) => _ab(d) / 10 - 40,
      bytes: 2));
  add(_single(
      0x3E,
      const Channel('CAT_B1S2', 'Catalyst temperature B1S2', '°C', CarSystem.o2Catalyst,
          min: -40, max: 6513, sensor: 'Catalyst temperature (B1S2)'),
      (d) => _ab(d) / 10 - 40,
      bytes: 2));
  add(_single(0x42, const Channel('ECU_V', 'Control module voltage', 'V', CarSystem.electrical, max: 65.5), (d) => _ab(d) / 1000, bytes: 2));
  add(_single(0x43, const Channel('ABS_LOAD', 'Absolute load', '%', CarSystem.engine, max: 25700), (d) => _ab(d) * 100 / 255, bytes: 2));
  add(_single(0x44, const Channel('LAMBDA_CMD', 'Commanded air-fuel ratio', 'λ', CarSystem.fuel, max: 2), (d) => _ab(d) * 2 / 65536, bytes: 2));
  add(_single(0x45, const Channel('TPS_REL', 'Relative throttle position', '%', CarSystem.intake), _pct));
  add(_single(
      0x46,
      const Channel('AMBIENT', 'Ambient air temperature', '°C', CarSystem.cooling,
          min: -40, max: 215, sensor: 'Ambient temperature sensor'),
      (d) => _a(d) - 40));
  add(_single(0x47, const Channel('TPS_B', 'Absolute throttle position B', '%', CarSystem.intake, sensor: 'Throttle position sensor (TPS)'), _pct));
  add(_single(0x48, const Channel('TPS_C', 'Absolute throttle position C', '%', CarSystem.intake), _pct));
  add(_single(
      0x49,
      const Channel('APP_D', 'Accelerator pedal position D', '%', CarSystem.intake, sensor: 'Accelerator pedal position sensor (APP)'),
      _pct));
  add(_single(0x4A, const Channel('APP_E', 'Accelerator pedal position E', '%', CarSystem.intake, sensor: 'Accelerator pedal position sensor (APP)'), _pct));
  add(_single(0x4B, const Channel('APP_F', 'Accelerator pedal position F', '%', CarSystem.intake), _pct));
  add(_single(0x4C, const Channel('TAC', 'Commanded throttle actuator', '%', CarSystem.intake, sensor: 'Electronic throttle body motor'), _pct));
  add(_single(0x4D, const Channel('TIME_MIL', 'Time with check-engine light on', 'min', CarSystem.faults, max: 65535), _ab, bytes: 2));
  add(_single(0x4E, const Channel('TIME_CLR', 'Time since codes cleared', 'min', CarSystem.emissions, max: 65535), _ab, bytes: 2));
  add(_single(0x52, const Channel('ETHANOL', 'Ethanol fuel %', '%', CarSystem.fuel, sensor: 'Flex-fuel (ethanol) sensor'), _pct));
  add(_single(0x5A, const Channel('APP_REL', 'Relative accelerator pedal', '%', CarSystem.intake), _pct));
  add(_single(
      0x5C,
      const Channel('OIL_T', 'Engine oil temperature', '°C', CarSystem.cooling,
          min: -40, max: 210, sensor: 'Engine oil temperature sensor'),
      (d) => _a(d) - 40));
  add(_single(0x5E, const Channel('FUEL_RATE', 'Fuel rate', 'L/h', CarSystem.fuel, max: 3276), (d) => _ab(d) / 20, bytes: 2));
  return t;
}

/// All known channels, keyed by id.
final Map<String, Channel> channelTable = {
  for (final p in pidTable.values)
    for (final c in p.channels) c.id: c,
  batteryChannel.id: batteryChannel,
  boostChannel.id: boostChannel,
};

/// Battery voltage measured by the adapter itself (ATRV, OBD pin 16).
const batteryChannel = Channel('BATT', 'Battery voltage (OBD pin 16)', 'V', CarSystem.electrical,
    max: 20, sensor: 'Battery / charging system');

/// Derived: MAP minus barometric pressure (turbo cars).
const boostChannel = Channel('BOOST', 'Boost pressure (MAP − baro)', 'kPa', CarSystem.intake, min: -100, max: 250);

/// Decodes the "supported PIDs" bitmask replies (PID 00, 20, 40 …).
Set<int> decodeSupported(int basePid, Uint8List d) {
  final out = <int>{};
  for (var byte = 0; byte < 4 && byte < d.length; byte++) {
    for (var bit = 0; bit < 8; bit++) {
      if (d[byte] & (0x80 >> bit) != 0) out.add(basePid + byte * 8 + bit + 1);
    }
  }
  return out;
}

/// PID 0x13: which O2 sensors are physically fitted.
List<String> decodeO2Present(int mask) => [
      for (var i = 0; i < 8; i++)
        if (mask & (1 << i) != 0) _o2Names[i],
    ];

/// PID 0x03 fuel system status (system 1).
String fuelSystemStatus(int a) => switch (a) {
      1 => 'Open loop – engine still warming up',
      2 => 'Closed loop – using O2 sensor feedback (normal)',
      4 => 'Open loop – engine load or fuel cut',
      8 => 'Open loop – system fault',
      16 => 'Closed loop – fault in at least one O2 sensor',
      _ => 'Unknown ($a)',
    };

/// PID 0x51 fuel type.
String fuelType(int a) => switch (a) {
      1 => 'Petrol',
      2 => 'Methanol',
      3 => 'Ethanol',
      4 => 'Diesel',
      5 => 'LPG',
      6 => 'CNG',
      8 => 'Electric',
      9 => 'Bi-fuel petrol',
      17 => 'Hybrid petrol',
      _ => 'Type $a',
    };
