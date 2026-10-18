import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'transport.dart';

/// Plays back adapter replies recorded by the MATLAB car simulation
/// (`simulation/run_simulation.m` → `assets/simulations/*.json`).
///
/// Each live PID has a time series of replies; every request for that PID
/// returns the next one, so the app sees the simulated signal in order.
class ReplayTransport implements ObdTransport, EngineStartSimulator {
  ReplayTransport(this.replay, {this.latency = const Duration(milliseconds: 2)}) {
    for (final s in replay['static'] as List) {
      _static[s['cmd'] as String] = s['reply'] as String;
    }
    for (final s in replay['series'] as List) {
      _series[s['cmd'] as String] = List<String>.from(s['replies'] as List);
    }
  }

  factory ReplayTransport.fromJson(String json) =>
      ReplayTransport(jsonDecode(json) as Map<String, dynamic>);

  final Map<String, dynamic> replay;
  final Duration latency;
  final _static = <String, String>{};
  final _series = <String, List<String>>{};
  final _index = <String, int>{};
  bool _batteryTest = false;
  StreamController<String>? _ctrl;
  String _pending = '';

  String get title => replay['title'] as String;
  String get description => replay['description'] as String;

  @override
  String get name => title;

  @override
  bool get supportsBaudProbe => false;

  @override
  Future<void> open(int baudRate) async {
    _ctrl = StreamController<String>();
    _index.clear();
    _batteryTest = false;
  }

  @override
  Stream<String> get incoming => _ctrl!.stream;

  @override
  Future<void> close() async {
    await _ctrl?.close();
    _ctrl = null;
  }

  /// Battery test: ATRV switches to the recorded key-on → crank → run trace.
  @override
  void simulateEngineStart() {
    _batteryTest = true;
    _index.remove('ATRV');
  }

  @override
  Future<void> write(String data) async {
    _pending += data;
    while (_pending.contains('\r')) {
      final i = _pending.indexOf('\r');
      final cmd = _pending.substring(0, i).trim().toUpperCase().replaceAll(' ', '');
      _pending = _pending.substring(i + 1);
      if (cmd.isEmpty) continue;
      final reply = _answer(cmd);
      Future<void>.delayed(latency, () => _ctrl?.add('$reply\r\r>'));
    }
  }

  String _next(String key, List<String> list) {
    final i = _index[key] ?? 0;
    _index[key] = i + 1;
    return list[i % list.length];
  }

  String _answer(String cmd) {
    if (cmd == 'ATZ' || cmd == 'ATI') return '\rELM327 v1.5';
    if (cmd == 'ATDPN') return 'A6';
    if (cmd == 'ATRV') {
      final list = List<String>.from((_batteryTest ? replay['atrv_test'] : replay['atrv']) as List);
      return _next('ATRV', list);
    }
    if (cmd.startsWith('AT')) return 'OK';
    final series = _series[cmd];
    if (series != null) return _next(cmd, series);
    return _static[cmd] ?? 'NO DATA';
  }
}

class ReplayCandidate extends TransportCandidate {
  ReplayCandidate(this.asset, this.json);
  final String asset;
  final Map<String, dynamic> json;

  @override
  String get title => json['title'] as String;
  @override
  String get subtitle => json['description'] as String;
  @override
  bool get isDemo => true;
  bool get isSimulation => true;
  @override
  Future<ObdTransport> create() async => ReplayTransport(json);

  /// Replay files bundled with the app.
  static Future<List<ReplayCandidate>> list() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final out = <ReplayCandidate>[];
    for (final a in manifest.listAssets().where((a) => a.startsWith('assets/simulations/') && a.endsWith('.json')).toList()..sort()) {
      out.add(ReplayCandidate(a, jsonDecode(await rootBundle.loadString(a)) as Map<String, dynamic>));
    }
    return out;
  }
}
