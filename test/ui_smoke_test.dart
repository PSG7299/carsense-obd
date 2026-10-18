import 'dart:io';
import 'dart:ui' as ui;

import 'package:carsense_obd/data/history_store.dart';
import 'package:carsense_obd/main.dart';
import 'package:carsense_obd/state/app_state.dart';
import 'package:carsense_obd/transport/mock_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives the whole app against the simulated faulty Swift.
/// Set SCREENSHOT_DIR to also save PNG screenshots of every screen.
void main() {
  final shotDir = Platform.environment['SCREENSHOT_DIR'];
  final boundary = GlobalKey();

  Future<void> loadFonts() async {
    final cache = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
    if (!Directory(cache).existsSync()) return;
    Future<void> load(String family, List<String> files) async {
      final l = FontLoader(family);
      for (final f in files) {
        l.addFont(Future.value(ByteData.sublistView(File('$cache/$f').readAsBytesSync())));
      }
      await l.load();
    }

    await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
    await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (shotDir == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await ro.toImage(pixelRatio: 1.5);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$shotDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final (label, size) in [('phone', const Size(412, 915)), ('desktop', const Size(1280, 860))]) {
    testWidgets('full demo flow ($label)', (tester) async {
      await tester.runAsync(loadFonts);
      tester.view.physicalSize = size * 1.0;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tmp = Directory.systemTemp.createTempSync('carsense');
      final state = AppState(store: HistoryStore(dir: tmp));
      await tester.runAsync(state.refreshAdapters);

      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ChangeNotifierProvider.value(value: state, child: const CarSenseApp()),
      ));
      await tester.pump();
      expect(find.text('Connect your car'), findsOneWidget);
      await shot(tester, '${label}_1_connect');

      final demo = state.adapters.firstWhere((a) => a is MockCandidate && a.car == DemoCar.swiftFaulty);
      await tester.runAsync(() => state.connect(demo));
      await tester.pump();
      expect(find.text('Run full health check'), findsOneWidget);
      await shot(tester, '${label}_2_ready');

      await tester.runAsync(state.runScan);
      await tester.pump();
      expect(state.report, isNotNull);
      expect(find.text('Condition by system'), findsOneWidget);
      await shot(tester, '${label}_3_dashboard');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(tester, '${label}_4_dashboard_scrolled');

      await tester.tap(find.text('Sensors').last);
      await shot(tester, '${label}_5_sensors');

      await tester.tap(find.text('Battery').last);
      await tester.pump();
      await tester.runAsync(() => state.runBatteryTest(seconds: 8));
      await shot(tester, '${label}_6_battery');

      await tester.tap(find.text('Live').last);
      await tester.pump();
      await tester.runAsync(() async {
        // ignore: unawaited_futures
        state.startLive();
        await Future<void>.delayed(const Duration(seconds: 4));
        state.stopLive();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await shot(tester, '${label}_7_live');

      // A second scan so the history chart has a trend.
      await tester.runAsync(state.runScan);
      await tester.tap(find.text('History').last);
      await shot(tester, '${label}_8_history');

      await tester.runAsync(state.disconnect);
      await tester.pump(const Duration(seconds: 1));
      tmp.deleteSync(recursive: true);
    });
  }
}
