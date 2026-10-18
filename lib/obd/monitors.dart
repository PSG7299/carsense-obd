import 'dart:typed_data';

/// Decoded mode 01 PID 01 – check-engine light state and readiness monitors.
class MonitorStatus {
  MonitorStatus({
    required this.milOn,
    required this.dtcCount,
    required this.sparkIgnition,
    required this.monitors,
  });

  final bool milOn;
  final int dtcCount;
  final bool sparkIgnition;

  /// Monitor name -> true if complete, false if not yet complete.
  /// Only monitors the car actually supports are listed.
  final Map<String, bool> monitors;

  int get incomplete => monitors.values.where((c) => !c).length;

  Map<String, dynamic> toJson() => {
        'milOn': milOn,
        'dtcCount': dtcCount,
        'sparkIgnition': sparkIgnition,
        'monitors': monitors,
      };

  factory MonitorStatus.fromJson(Map<String, dynamic> j) => MonitorStatus(
        milOn: j['milOn'] as bool,
        dtcCount: j['dtcCount'] as int,
        sparkIgnition: j['sparkIgnition'] as bool,
        monitors: Map<String, bool>.from(j['monitors'] as Map),
      );

  static MonitorStatus decode(Uint8List d) {
    final a = d[0], b = d[1], c = d[2], dd = d[3];
    final spark = b & 0x08 == 0;
    final m = <String, bool>{};
    void common(int bit, String name) {
      if (b & (1 << bit) != 0) m[name] = b & (1 << (bit + 4)) == 0;
    }

    common(0, 'Misfire');
    common(1, 'Fuel system');
    common(2, 'Comprehensive components');

    final names = spark
        ? ['Catalyst', 'Heated catalyst', 'EVAP system', 'Secondary air', 'A/C refrigerant', 'O2 sensor', 'O2 sensor heater', 'EGR / VVT']
        : ['NMHC catalyst', 'NOx/SCR', 'Reserved', 'Boost pressure', 'Reserved', 'Exhaust gas sensor', 'PM filter', 'EGR / VVT'];
    for (var bit = 0; bit < 8; bit++) {
      if (names[bit] == 'Reserved') continue;
      if (c & (1 << bit) != 0) m[names[bit]] = dd & (1 << bit) == 0;
    }
    return MonitorStatus(milOn: a & 0x80 != 0, dtcCount: a & 0x7F, sparkIgnition: spark, monitors: m);
  }
}
