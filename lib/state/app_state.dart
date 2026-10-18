import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/history_store.dart';
import '../diagnostics/health_engine.dart';
import '../diagnostics/models.dart';
import '../elm327/elm327.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../transport/discovery.dart';
import '../transport/mock_transport.dart';
import '../transport/transport.dart';
import '../vehicles/profiles.dart';
import '../vehicles/vehicle_profile.dart';

enum Link { disconnected, connecting, connected }

enum Busy { none, scanning, live, battery }

class LivePoint {
  LivePoint(this.t, this.v);
  final double t;
  final double v;
}

class AppState extends ChangeNotifier {
  AppState({HistoryStore? store}) : store = store ?? HistoryStore();

  final HistoryStore store;
  final engine = const HealthEngine();

  // ---------------------------------------------------------------- adapters
  List<TransportCandidate> adapters = [];
  bool discovering = false;

  Future<void> refreshAdapters() async {
    discovering = true;
    notifyListeners();
    adapters = await discoverAdapters();
    discovering = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- connection
  Link link = Link.disconnected;
  String? error;
  String? connectedName;
  ObdTransport? _transport;
  Elm327? elm;
  ObdService? obd;
  bool get isDemo => _transport is MockTransport;

  Future<void> connect(TransportCandidate c) async {
    await disconnect();
    link = Link.connecting;
    error = null;
    connectedName = c.title;
    notifyListeners();
    try {
      _transport = await c.create();
      elm = Elm327(_transport!);
      await elm!.connect();
      obd = ObdService(elm!);
      await obd!.discoverSupportedPids();
      await obd!.readVin();
      link = Link.connected;
      _defaultLiveSelection();
    } catch (e) {
      error = e.toString();
      link = Link.disconnected;
      elm = null;
      obd = null;
      _transport = null;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    stopLive();
    final e = elm;
    elm = null;
    _lastData = null;
    obd = null;
    _transport = null;
    link = Link.disconnected;
    busy = Busy.none;
    if (e != null) {
      try {
        await e.close();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Car profile: user override, else detected from the VIN.
  VehicleProfile? profileOverride;
  VehicleProfile get profile => profileOverride ?? profileForMaker(obd?.maker ?? 'Unknown');

  void setProfile(VehicleProfile? p) {
    profileOverride = p;
    notifyListeners();
  }

  // -------------------------------------------------------------------- scan
  Busy busy = Busy.none;
  String progressText = '';
  double progress = 0;
  ScanReport? report;
  ScanData? _lastData;

  Future<void> runScan() async {
    if (obd == null || busy != Busy.none) return;
    busy = Busy.scanning;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final data = await obd!.scan(
        profileOverride: profile,
        sampling: isDemo ? const Duration(seconds: 6) : const Duration(seconds: 15),
        onProgress: (s, f) {
          progressText = s;
          progress = f;
          notifyListeners();
        },
      );
      _lastData = data;
      report = engine.evaluate(data, battery: _lastBattery);
      await store.save(report!);
      await loadHistory();
    } catch (e) {
      error = 'Scan failed: $e';
    }
    busy = Busy.none;
    progress = 0;
    notifyListeners();
  }

  // ----------------------------------------------------------------- history
  List<ScanReport> history = [];

  Future<void> loadHistory() async {
    try {
      history = await store.loadAll();
    } catch (_) {
      history = [];
    }
    notifyListeners();
  }

  void openReport(ScanReport r) {
    report = r;
    notifyListeners();
  }

  Future<void> deleteReport(ScanReport r) async {
    await store.delete(r);
    if (identical(report, r)) report = null;
    await loadHistory();
  }

  // -------------------------------------------------------------------- live
  final Map<String, List<LivePoint>> live = {};
  final Set<String> liveSelection = {};
  Timer? _liveNotify;
  bool _liveRun = false;
  final _liveClock = Stopwatch();

  /// Channels the connected car can provide, keyed by channel id -> PID.
  Map<String, int> get liveChannels {
    final out = <String, int>{};
    for (final pid in obd?.pollablePids ?? const <int>[]) {
      for (final ch in pidTable[pid]!.channels) {
        out[ch.id] = pid;
      }
    }
    if (obd != null) out[batteryChannel.id] = -1;
    return out;
  }

  void _defaultLiveSelection() {
    liveSelection.clear();
    final avail = liveChannels.keys.toSet();
    for (final id in ['RPM', 'ECT', 'O2V_B1S1', 'STFT1', 'MAP', 'BATT']) {
      if (avail.contains(id)) liveSelection.add(id);
    }
  }

  void toggleLiveChannel(String id) {
    if (!liveSelection.remove(id)) {
      if (liveSelection.length >= 8) return;
      liveSelection.add(id);
    }
    notifyListeners();
  }

  Future<void> startLive() async {
    if (obd == null || busy != Busy.none) return;
    busy = Busy.live;
    live.clear();
    _liveRun = true;
    _liveClock
      ..reset()
      ..start();
    _liveNotify = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
    notifyListeners();
    final chans = liveChannels;
    while (_liveRun && obd != null) {
      final pids = {for (final id in liveSelection) chans[id]}.whereType<int>().toList();
      if (pids.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      for (final pid in pids) {
        if (!_liveRun) break;
        final t = _liveClock.elapsedMilliseconds / 1000;
        if (pid == -1) {
          final v = await elm?.batteryVoltage();
          if (v != null) _addLive(batteryChannel.id, t, v);
        } else {
          for (final r in await obd!.readPid(pid)) {
            _addLive(r.channel, t, r.value);
          }
        }
      }
    }
  }

  void _addLive(String id, double t, double v) {
    final l = live.putIfAbsent(id, () => []);
    l.add(LivePoint(t, v));
    // Keep the last 90 seconds.
    while (l.isNotEmpty && l.first.t < t - 90) {
      l.removeAt(0);
    }
  }

  void stopLive() {
    _liveRun = false;
    _liveNotify?.cancel();
    _liveNotify = null;
    if (busy == Busy.live) busy = Busy.none;
    notifyListeners();
  }

  // ---------------------------------------------------------------- battery
  List<List<double>> batteryTrace = [];
  BatteryTestResult? _lastBattery;
  BatteryTestResult? get batteryResult => _lastBattery;
  int batterySecondsLeft = 0;

  Future<void> runBatteryTest({int seconds = 20}) async {
    if (elm == null || busy != Busy.none) return;
    busy = Busy.battery;
    batteryTrace = [];
    _lastBattery = null;
    notifyListeners();
    final t = _transport;
    if (t is MockTransport) t.simulateEngineStart();
    final sw = Stopwatch()..start();
    while (sw.elapsed.inSeconds < seconds && elm != null) {
      final v = await elm!.batteryVoltage();
      if (v != null) batteryTrace.add([sw.elapsedMilliseconds / 1000, v]);
      batterySecondsLeft = seconds - sw.elapsed.inSeconds;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    _lastBattery = engine.analyseBattery(batteryTrace);
    final old = report;
    if (old != null) {
      if (_lastData != null && old.vin == _lastData!.vin && old.profileId == _lastData!.profile.id) {
        // Re-score the latest scan with the battery result included.
        await store.delete(old);
        report = engine.evaluate(_lastData!, battery: _lastBattery);
      } else {
        old.battery = _lastBattery;
      }
      await store.save(report!);
      await loadHistory();
    }
    busy = Busy.none;
    notifyListeners();
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }
}
