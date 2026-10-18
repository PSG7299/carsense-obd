/// Per-car knowledge: what sensors to expect and what "normal" means.
class Range {
  const Range(this.okLow, this.okHigh, {this.warnLow, this.warnHigh});

  final double okLow;
  final double okHigh;

  /// Outside ok but inside warn => warning; outside warn => fail.
  /// Null means "no fail threshold on that side".
  final double? warnLow;
  final double? warnHigh;

  String describe(String unit) => '${_f(okLow)}–${_f(okHigh)} $unit'.trim();
  static String _f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.name,
    required this.make,
    required this.engine,
    required this.turbo,
    required this.expectedSensors,
    this.idleRpm = const Range(650, 950, warnLow: 550, warnHigh: 1150),
    this.warmCoolant = const Range(82, 105, warnLow: 70, warnHigh: 112),
    this.idleMap = const Range(25, 45, warnLow: 18, warnHigh: 60),
    this.maxBoostKpa = 0,
    this.notes = const [],
  });

  final String id;
  final String name;
  final String make;
  final String engine;
  final bool turbo;
  final List<String> expectedSensors;
  final Range idleRpm;
  final Range warmCoolant;
  final Range idleMap;

  /// Typical maximum boost above atmospheric (kPa) for turbo engines.
  final double maxBoostKpa;
  final List<String> notes;
}
