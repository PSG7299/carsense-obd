import '../obd/dtc.dart';
import '../obd/monitors.dart';
import '../obd/pids.dart';

enum Status {
  ok('Good'),
  info('Info'),
  warn('Check'),
  fail('Problem');

  const Status(this.label);
  final String label;

  Status worst(Status other) => index >= other.index ? this : other;
}

class SensorResult {
  SensorResult({
    required this.channelId,
    required this.name,
    required this.unit,
    required this.system,
    required this.min,
    required this.max,
    required this.avg,
    required this.last,
    required this.status,
    required this.message,
    this.normal = '',
    this.samples = const [],
  });

  final String channelId;
  final String name;
  final String unit;
  final CarSystem system;
  final double min, max, avg, last;
  final Status status;
  final String message;
  final String normal;
  final List<double> samples;

  Map<String, dynamic> toJson() => {
        'id': channelId,
        'name': name,
        'unit': unit,
        'system': system.name,
        'min': min,
        'max': max,
        'avg': avg,
        'last': last,
        'status': status.name,
        'message': message,
        'normal': normal,
        'samples': samples,
      };

  factory SensorResult.fromJson(Map<String, dynamic> j) => SensorResult(
        channelId: j['id'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        system: CarSystem.values.byName(j['system'] as String),
        min: (j['min'] as num).toDouble(),
        max: (j['max'] as num).toDouble(),
        avg: (j['avg'] as num).toDouble(),
        last: (j['last'] as num).toDouble(),
        status: Status.values.byName(j['status'] as String),
        message: j['message'] as String,
        normal: j['normal'] as String? ?? '',
        samples: [for (final s in (j['samples'] as List? ?? [])) (s as num).toDouble()],
      );
}

class SystemResult {
  SystemResult(this.system, this.status, this.score, this.summary);
  final CarSystem system;
  final Status status;
  final int score;
  final String summary;

  Map<String, dynamic> toJson() =>
      {'system': system.name, 'status': status.name, 'score': score, 'summary': summary};
  factory SystemResult.fromJson(Map<String, dynamic> j) => SystemResult(
        CarSystem.values.byName(j['system'] as String),
        Status.values.byName(j['status'] as String),
        j['score'] as int,
        j['summary'] as String,
      );
}

class BatteryTestResult {
  BatteryTestResult({
    required this.restVoltage,
    required this.crankMin,
    required this.chargingVoltage,
    required this.status,
    required this.verdict,
    required this.trace,
  });

  final double? restVoltage;

  /// Median voltage during cranking (the starter-motor dip).
  final double? crankMin;
  final double? chargingVoltage;
  final Status status;
  final List<String> verdict;

  /// (seconds since start, volts)
  final List<List<double>> trace;

  Map<String, dynamic> toJson() => {
        'rest': restVoltage,
        'crank': crankMin,
        'charging': chargingVoltage,
        'status': status.name,
        'verdict': verdict,
        'trace': trace,
      };

  factory BatteryTestResult.fromJson(Map<String, dynamic> j) => BatteryTestResult(
        restVoltage: (j['rest'] as num?)?.toDouble(),
        crankMin: (j['crank'] as num?)?.toDouble(),
        chargingVoltage: (j['charging'] as num?)?.toDouble(),
        status: Status.values.byName(j['status'] as String),
        verdict: List<String>.from(j['verdict'] as List),
        trace: [
          for (final p in j['trace'] as List)
            [for (final v in p as List) (v as num).toDouble()]
        ],
      );
}

class ScanReport {
  ScanReport({
    required this.time,
    required this.profileId,
    required this.vehicleName,
    required this.vin,
    required this.maker,
    required this.modelYear,
    required this.protocol,
    required this.adapter,
    required this.engineRunning,
    required this.score,
    required this.systems,
    required this.sensors,
    required this.dtcs,
    required this.monitors,
    required this.detectedSensors,
    required this.notes,
    this.fuelSystem,
    this.battery,
  });

  final DateTime time;
  final String profileId;
  final String vehicleName;
  final String? vin;
  final String maker;
  final int? modelYear;
  final String protocol;
  final String adapter;
  final bool engineRunning;
  final int score;
  final List<SystemResult> systems;
  final List<SensorResult> sensors;
  final List<Dtc> dtcs;
  final MonitorStatus? monitors;
  final List<String> detectedSensors;
  final List<String> notes;
  final String? fuelSystem;
  BatteryTestResult? battery;

  Status get overall => score >= 80
      ? Status.ok
      : score >= 55
          ? Status.warn
          : Status.fail;

  double? channelAvg(String id) {
    for (final s in sensors) {
      if (s.channelId == id) return s.avg;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'profileId': profileId,
        'vehicleName': vehicleName,
        'vin': vin,
        'maker': maker,
        'modelYear': modelYear,
        'protocol': protocol,
        'adapter': adapter,
        'engineRunning': engineRunning,
        'score': score,
        'systems': [for (final s in systems) s.toJson()],
        'sensors': [for (final s in sensors) s.toJson()],
        'dtcs': [for (final d in dtcs) d.toJson()],
        'monitors': monitors?.toJson(),
        'detectedSensors': detectedSensors,
        'notes': notes,
        'fuelSystem': fuelSystem,
        'battery': battery?.toJson(),
      };

  factory ScanReport.fromJson(Map<String, dynamic> j) => ScanReport(
        time: DateTime.parse(j['time'] as String),
        profileId: j['profileId'] as String,
        vehicleName: j['vehicleName'] as String,
        vin: j['vin'] as String?,
        maker: j['maker'] as String,
        modelYear: j['modelYear'] as int?,
        protocol: j['protocol'] as String,
        adapter: j['adapter'] as String,
        engineRunning: j['engineRunning'] as bool,
        score: j['score'] as int,
        systems: [for (final s in j['systems'] as List) SystemResult.fromJson(s as Map<String, dynamic>)],
        sensors: [for (final s in j['sensors'] as List) SensorResult.fromJson(s as Map<String, dynamic>)],
        dtcs: [for (final d in j['dtcs'] as List) Dtc.fromJson(d as Map<String, dynamic>)],
        monitors: j['monitors'] == null ? null : MonitorStatus.fromJson(j['monitors'] as Map<String, dynamic>),
        detectedSensors: List<String>.from(j['detectedSensors'] as List),
        notes: List<String>.from(j['notes'] as List),
        fuelSystem: j['fuelSystem'] as String?,
        battery: j['battery'] == null ? null : BatteryTestResult.fromJson(j['battery'] as Map<String, dynamic>),
      );
}
