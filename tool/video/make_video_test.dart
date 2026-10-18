// Records the "How to use CarSense" tutorial video.
//
// The app screens are the real CarSense UI driven by its built-in demo car;
// slides and captions explain the hardware steps. Frames are written as PNGs
// plus an ffmpeg concat list:
//
//   VIDEO_DIR=/tmp/frames FLUTTER_ROOT=$(dirname $(dirname $(which flutter))) \
//     flutter test tool/video/make_video_test.dart
//   tool/video/encode.sh /tmp/frames docs/video/CarSense-how-to.mp4
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carsense_obd/data/history_store.dart';
import 'package:carsense_obd/state/app_state.dart';
import 'package:carsense_obd/transport/mock_transport.dart';
import 'package:carsense_obd/transport/transport.dart';
import 'package:carsense_obd/ui/screens/home_shell.dart';
import 'package:carsense_obd/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const stageSize = Size(1280, 720);
const pixelRatio = 1.5; // -> 1920 x 1080
const _bg1 = Color(0xFF0B1E33);
const _bg2 = Color(0xFF16324F);
const _accent = Color(0xFFFFC857);

// --------------------------------------------------------------- transport

/// Plays the demo car but looks like a real USB adapter to the app.
class _VideoTransport implements ObdTransport {
  _VideoTransport(this.mock, this.name);
  final MockTransport mock;
  @override
  final String name;
  @override
  bool get supportsBaudProbe => false;
  @override
  Future<void> open(int baudRate) => mock.open(baudRate);
  @override
  Stream<String> get incoming => mock.incoming;
  @override
  Future<void> write(String data) => mock.write(data);
  @override
  Future<void> close() => mock.close();
}

class _VideoAdapter extends TransportCandidate {
  _VideoAdapter(this.title, this.subtitle, this.car);
  @override
  final String title;
  @override
  final String subtitle;
  final DemoCar car;
  MockTransport? last;
  @override
  Future<ObdTransport> create() async => _VideoTransport(last = MockTransport(car), title);
}

// ------------------------------------------------------------------- stage

class StageCtl extends ChangeNotifier {
  String badge = '';
  String title = '';
  String caption = '';
  Widget? content;
  Offset? tap;
  double tapT = 0;
  double fade = 0;

  void set({String? badge, String? title, String? caption, Widget? content}) {
    if (badge != null) this.badge = badge;
    if (title != null) this.title = title;
    if (caption != null) this.caption = caption;
    if (content != null) this.content = content;
    notifyListeners();
  }

  void update() => notifyListeners();
}

class Stage extends StatelessWidget {
  const Stage(this.c, {super.key});
  final StageCtl c;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_bg1, _bg2]),
        ),
        child: Stack(children: [
          Positioned(
            left: 40,
            right: 40,
            top: 22,
            child: Row(children: [
              if (c.badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(20)),
                  child: Text(c.badge, style: const TextStyle(color: _bg1, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              Expanded(
                child: Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.directions_car_filled, color: Colors.white38, size: 22),
              const SizedBox(width: 6),
              const Text('CarSense OBD', style: TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          ),
          Positioned(left: 0, right: 0, top: 72, bottom: 104, child: Center(child: c.content ?? const SizedBox())),
          if (c.caption.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1080, minHeight: 70),
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(c.caption,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 21, height: 1.3, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          if (c.tap != null)
            Positioned(
              left: c.tap!.dx - 30,
              top: c.tap!.dy - 30,
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  child: Container(
                    width: 18 + 38 * c.tapT,
                    height: 18 + 38 * c.tapT,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accent.withValues(alpha: 0.35 * (1 - c.tapT) + 0.15),
                      border: Border.all(color: _accent, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          if (c.fade > 0)
            Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: c.fade)))),
        ]),
      ),
    );
  }
}

/// The app inside a Windows-style window.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key});
  static const size = Size(1000, 530);

  @override
  Widget build(BuildContext context) {
    const bar = 30.0;
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          height: bar,
          color: const Color(0xFFF3F3F3),
          padding: const EdgeInsets.only(left: 10),
          child: Row(children: [
            const Icon(Icons.directions_car_filled, size: 16, color: Color(0xFF1565C0)),
            const SizedBox(width: 8),
            const Text('CarSense OBD', style: TextStyle(fontSize: 12, color: Colors.black87)),
            const Spacer(),
            for (final i in [Icons.remove, Icons.crop_square, Icons.close])
              SizedBox(width: 44, child: Icon(i, size: 15, color: Colors.black54)),
          ]),
        ),
        Expanded(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(size.width, size.height - bar), padding: EdgeInsets.zero),
            child: Theme(data: buildTheme(Brightness.light, fontFamily: 'Roboto'), child: const HomeShell()),
          ),
        ),
      ]),
    );
  }
}

/// The app inside an Android phone.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, this.side});
  static const screen = Size(360, 760);
  final Widget? side;

  @override
  Widget build(BuildContext context) {
    final phone = SizedBox(
      height: 548,
      child: FittedBox(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(54),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(42),
            child: SizedBox(
              width: screen.width,
              height: screen.height,
              child: ColoredBox(
                color: Colors.white,
                child: Column(children: [
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    color: const Color(0xFFF7F9FF),
                    child: const Row(children: [
                      Text('10:30', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Spacer(),
                      Icon(Icons.usb, size: 14),
                      SizedBox(width: 4),
                      Icon(Icons.signal_cellular_alt, size: 14),
                      SizedBox(width: 4),
                      Icon(Icons.battery_5_bar, size: 14),
                    ]),
                  ),
                  Expanded(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: Size(screen.width, screen.height - 30), padding: EdgeInsets.zero),
                      child: Theme(data: buildTheme(Brightness.light, fontFamily: 'Roboto'), child: const HomeShell()),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    if (side == null) return phone;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [phone, const SizedBox(width: 48), SizedBox(width: 520, child: side)]);
  }
}

// ------------------------------------------------------------ slide parts

const _p = TextStyle(color: Colors.white, fontSize: 20, height: 1.35);
const _small = TextStyle(color: Colors.white70, fontSize: 16, height: 1.3);

Widget card(IconData icon, String title, String text, {double width = 340}) => Container(
      width: width,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: _accent, size: 46),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(text, style: _small),
      ]),
    );

Widget steps(List<String> items, {double width = 560}) => SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: _accent,
                child: Text('${i + 1}', style: const TextStyle(color: _bg1, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(items[i], style: _p)),
            ]),
          ),
      ]),
    );

Widget node(IconData icon, String label) => Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white30)),
        child: Icon(icon, color: Colors.white, size: 56),
      ),
      const SizedBox(height: 10),
      SizedBox(width: 150, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16))),
    ]);

Widget arrow([String label = '']) => Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: _accent, fontSize: 13)),
        const Icon(Icons.arrow_forward_rounded, color: _accent, size: 40),
      ]),
    );

/// Simplified OBD-II socket drawing (16 pins, J1962).
class ObdPortPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w * 0.9, h)
      ..lineTo(w * 0.1, h)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF2B2B2B));
    canvas.drawPath(body, Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    final highlight = {4, 5, 6, 14, 16};
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < 8; i++) {
        final pin = row * 8 + i + 1;
        final x = w * (0.17 + i * 0.094) + (row == 1 ? w * 0.0 : 0);
        final y = h * (row == 0 ? 0.32 : 0.68);
        final r = Rect.fromCenter(center: Offset(x, y), width: w * 0.05, height: h * 0.2);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()..color = highlight.contains(pin) ? _accent : const Color(0xFFB0B0B0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Right-hand-drive dashboard sketch with the OBD port location.
class DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()
      ..color = Colors.white60
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final dash = Path()
      ..moveTo(0, s.height * 0.35)
      ..quadraticBezierTo(s.width / 2, s.height * 0.05, s.width, s.height * 0.35)
      ..lineTo(s.width, s.height * 0.55)
      ..lineTo(0, s.height * 0.55)
      ..close();
    canvas.drawPath(dash, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawPath(dash, line);
    // Steering wheel on the right (India = right-hand drive).
    final wheel = Offset(s.width * 0.72, s.height * 0.5);
    canvas.drawCircle(wheel, s.height * 0.22, line);
    canvas.drawCircle(wheel, s.height * 0.05, line);
    canvas.drawLine(wheel + Offset(-s.height * 0.22, 0), wheel + Offset(-s.height * 0.05, 0), line);
    canvas.drawLine(wheel + Offset(s.height * 0.05, 0), wheel + Offset(s.height * 0.22, 0), line);
    canvas.drawLine(wheel + Offset(0, s.height * 0.05), wheel + Offset(0, s.height * 0.22), line);
    // Centre console / screen.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width * 0.36, s.height * 0.2, s.width * 0.16, s.height * 0.16), const Radius.circular(6)), line);
    // Port location: lower dash, driver side, near the knees.
    final port = Rect.fromCenter(center: Offset(s.width * 0.62, s.height * 0.8), width: 46, height: 26);
    canvas.drawRRect(RRect.fromRectAndRadius(port, const Radius.circular(5)), Paint()..color = _accent);
    canvas.drawCircle(port.center, 34, Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget mockWindow(String title, Widget body, {double width = 460, Color bar = const Color(0xFFF3F3F3)}) => Container(
      width: width,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)]),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: bar,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ),
        Padding(padding: const EdgeInsets.all(16), child: body),
      ]),
    );

Widget mockDialog(String title, String text, List<String> buttons, {String? check, double width = 340}) => Container(
      width: width,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: const Color(0xFFEEF1F8), borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35)),
        if (check != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.check_box, color: Color(0xFF1565C0), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(check, style: const TextStyle(fontSize: 13, color: Colors.black87))),
          ]),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          for (final b in buttons)
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(b, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: b == buttons.last ? const Color(0xFF1565C0) : Colors.black54)),
            ),
        ]),
      ]),
    );

// ------------------------------------------------------------------ script

void main() {
  final outDir = Platform.environment['VIDEO_DIR'];
  final boundary = GlobalKey();

  testWidgets('record tutorial video', (t) async {
    if (outDir == null) {
      markTestSkipped('Set VIDEO_DIR to record the video');
      return;
    }
    Directory(outDir).createSync(recursive: true);
    final cache = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    await t.runAsync(() async {
      Future<void> load(String family, List<String> files) async {
        final l = FontLoader(family);
        for (final f in files) {
          l.addFont(Future.value(ByteData.sublistView(File('$cache/$f').readAsBytesSync())));
        }
        await l.load();
      }

      await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
      await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
    });

    t.view.physicalSize = stageSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final tmp = Directory.systemTemp.createTempSync('carsense_video');
    final state = AppState(store: HistoryStore(dir: tmp));
    final ctl = StageCtl();

    await t.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
        home: ChangeNotifierProvider.value(value: state, child: AnimatedBuilder(animation: ctl, builder: (_, _) => Stage(ctl))),
      ),
    ));

    // ---- frame capture
    var n = 0;
    final list = StringBuffer();
    var total = 0.0;
    Future<void> cap(double dur) async {
      await t.pump(const Duration(milliseconds: 16));
      final file = 'f${(n++).toString().padLeft(5, '0')}.png';
      await t.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: pixelRatio);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        File('$outDir/$file').writeAsBytesSync(png!.buffer.asUint8List());
      });
      list.writeln("file '$file'");
      list.writeln('duration ${dur.toStringAsFixed(3)}');
      total += dur;
    }

    /// Holds the current picture for [secs] (after letting animations settle).
    Future<void> hold(double secs) async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await cap(secs);
    }

    /// Records [secs] of animation at 10 fps.
    Future<void> anim(double secs, {bool Function()? until}) async {
      final frames = (secs * 10).round();
      for (var i = 0; i < frames; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await cap(0.1);
        if (until != null && until()) break;
      }
    }

    /// Records until [done] is true (real work in progress), at most [maxSecs]
    /// of video. Each frame is 0.1 s of video.
    Future<void> record(bool Function() done, {double maxSecs = 30}) async {
      var frames = 0;
      while (!done() && frames < maxSecs * 10) {
        await t.pump(const Duration(milliseconds: 100));
        await cap(0.1);
        frames++;
      }
    }

    Future<void> fadeOut() async {
      for (var i = 1; i <= 5; i++) {
        ctl.fade = i / 5;
        ctl.update();
        await t.pump();
        await cap(0.06);
      }
    }

    Future<void> fadeIn() async {
      for (var i = 4; i >= 0; i--) {
        ctl.fade = i / 5;
        ctl.update();
        await t.pump();
        await cap(0.06);
      }
    }

    Future<void> scene({String? badge, String? title, String? caption, Widget? content}) async {
      await fadeOut();
      ctl.set(badge: badge, title: title, caption: caption, content: content);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await fadeIn();
    }

    Future<void> say(String caption, double secs, {String? title}) async {
      ctl.set(caption: caption, title: title);
      await hold(secs);
    }

    Future<void> tapOn(Finder f, {bool doTap = true}) async {
      ctl.tap = t.getCenter(f.first);
      for (var i = 0; i <= 6; i++) {
        ctl.tapT = i / 6;
        ctl.update();
        await t.pump(const Duration(milliseconds: 16));
        await cap(0.07);
      }
      if (doTap) await t.tap(f.first, warnIfMissed: false);
      ctl.tap = null;
      ctl.update();
    }

    Future<void> scrollBy(double dy, {double secs = 2}) async {
      final pos = t.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first).position;
      unawaited(pos.animateTo((pos.pixels + dy).clamp(0.0, pos.maxScrollExtent), duration: Duration(milliseconds: (secs * 1000).round()), curve: Curves.easeInOut));
      await anim(secs + 0.2);
    }

    Finder nav(String label) => find.descendant(
          of: find.byWidgetPredicate((w) => w is NavigationRail || w is NavigationBar),
          matching: find.text(label),
        );

    // ================================================================ INTRO
    ctl.fade = 1;
    ctl.set(
      title: '',
      caption: '',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.directions_car_filled, color: _accent, size: 96),
        const SizedBox(height: 16),
        const Text('CarSense OBD', style: TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('How to check your car\'s health on Windows & Android', style: TextStyle(color: Colors.white, fontSize: 26)),
        const SizedBox(height: 26),
        Wrap(spacing: 12, children: [
          for (final s in ['Tata Nexon petrol', 'Maruti Swift petrol', 'Read-only – never changes your car'])
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
              child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ]),
      ]),
    );
    await t.pump();
    await fadeIn();
    await hold(4);
    await say('In this video the app runs with its built-in demo car, so the readings shown are simulated.', 4);

    // ======================================================= WHAT YOU NEED
    await scene(
      title: 'What you need',
      caption: 'One USB OBD-II adapter works with both Windows and Android.',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        card(Icons.usb, 'USB OBD-II adapter', 'ELM327 v1.5 USB cable (budget), or vLinker FS USB / OBDLink EX (recommended). Avoid "v2.1" clones.'),
        const SizedBox(width: 24),
        card(Icons.laptop_windows, 'Windows PC  or  Android phone', 'For a phone you also need a small USB-OTG adapter (USB-A female to USB-C).'),
        const SizedBox(width: 24),
        card(Icons.download_rounded, 'The CarSense app', 'Download from the GitHub Releases page: CarSense-windows.zip or CarSense-android.apk.'),
      ]),
    );
    await hold(7);

    // ============================================================ OBD PORT
    await scene(
      title: 'Find the OBD-II port',
      caption: 'Nexon and Swift: under the dashboard on the driver\'s side, near your knees. Sometimes behind a small cover.',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 520, height: 330, child: CustomPaint(painter: DashPainter())),
        const SizedBox(width: 50),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 300, height: 110, child: CustomPaint(painter: ObdPortPainter())),
          const SizedBox(height: 18),
          const Text('16-pin OBD-II socket', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Trapezoid shape – the plug only fits\none way round. Push it in firmly.', style: _small),
        ]),
      ]),
    );
    await hold(7);

    // ========================================================== CONNECTION
    await scene(
      title: 'How it connects',
      caption: 'Park the car and switch the ignition ON. The engine can be off or idling – idling gives the most complete check.',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          node(Icons.directions_car, 'Car OBD-II port'),
          arrow(),
          node(Icons.usb, 'USB OBD adapter'),
          arrow('USB'),
          node(Icons.laptop_windows, 'Windows PC'),
        ]),
        const SizedBox(height: 26),
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          node(Icons.directions_car, 'Car OBD-II port'),
          arrow(),
          node(Icons.usb, 'USB OBD adapter'),
          arrow('USB'),
          node(Icons.cable, 'USB-OTG adapter'),
          arrow(),
          node(Icons.phone_android, 'Android phone'),
        ]),
      ]),
    );
    await hold(7);

    // ============================================================ WINDOWS
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await scene(
      badge: 'WINDOWS',
      title: 'Install on Windows',
      caption: 'Windows may warn about an unknown app the first time – click "More info", then "Run anyway".',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        steps([
          'Open github.com/PSG7299/carsense-obd → Releases and download CarSense-windows.zip',
          'Right-click the zip → Extract All…',
          'Open the folder and double-click carsense_obd.exe',
        ], width: 520),
        const SizedBox(width: 40),
        mockWindow(
          'Windows protected your PC',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Microsoft Defender SmartScreen prevented an unrecognised app from starting.', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text('More info', style: TextStyle(fontSize: 14, color: Color(0xFF1565C0), decoration: TextDecoration.underline)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: _accent, width: 2), borderRadius: BorderRadius.circular(4)),
                child: const Text('Run anyway', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFFE0E0E0),
                child: const Text("Don't run", style: TextStyle(fontSize: 14)),
              ),
            ]),
          ]),
          width: 400,
          bar: const Color(0xFF0B5CAD),
        ),
      ]),
    );
    await hold(8);

    await scene(
      badge: 'WINDOWS',
      title: 'Check the adapter is detected',
      caption: 'Plug the adapter into the PC. It should appear in Device Manager under "Ports (COM & LPT)". No COM port? Install the CH340 or FTDI driver from the seller.',
      content: mockWindow(
        'Device Manager',
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('▸  Display adapters', style: TextStyle(fontSize: 15, height: 1.8)),
          Text('▸  Keyboards', style: TextStyle(fontSize: 15, height: 1.8)),
          Text('▾  Ports (COM & LPT)', style: TextStyle(fontSize: 15, height: 1.8, fontWeight: FontWeight.w600)),
          Row(children: [
            SizedBox(width: 34),
            Icon(Icons.usb, size: 18, color: Color(0xFF1565C0)),
            SizedBox(width: 6),
            Text('USB-SERIAL CH340 (COM3)', style: TextStyle(fontSize: 15, height: 1.8, backgroundColor: Color(0x55FFC857))),
          ]),
          Text('▸  Universal Serial Bus controllers', style: TextStyle(fontSize: 15, height: 1.8)),
        ]),
        width: 520,
      ),
    );
    await hold(8);

    // ---- the real app in a window
    final com3 = _VideoAdapter('COM3', 'USB-SERIAL CH340', DemoCar.nexonHealthy);
    state.adapters = [com3, ...[for (final c in DemoCar.values) MockCandidate(c)]];
    await scene(
      badge: 'WINDOWS',
      title: 'Connect',
      caption: 'Open CarSense. Your adapter is listed under "USB adapters" – click it.',
      content: const DesktopFrame(),
    );
    await hold(4);
    await tapOn(find.text('COM3'));
    await say('CarSense connects, finds the car\'s protocol and reads the VIN…', 0.1);
    await record(() => state.link == Link.connected, maxSecs: 8);
    await say('Connected! The VIN shows it is a Tata Nexon, and CarSense lists every sensor the car reports.', 6);

    await tapOn(find.text('Run full health check'));
    await say('Run full health check: about 30 seconds (sped up here). Nothing in the car is changed.', 0.1, title: 'Run the health check');
    await record(() => state.busy == Busy.none && state.report != null, maxSecs: 14);
    await say('The dashboard: an overall health score and a score for every system.', 6, title: 'Dashboard');
    await scrollBy(420, secs: 2.5);
    await say('Each system card summarises what was checked. Fault codes and emissions self-tests are shown below.', 6);
    await scrollBy(600, secs: 2.5);
    await hold(3);

    await tapOn(nav('Sensors'));
    await say('Sensors: every reading with its value, normal range, a mini-graph and a plain-English verdict.', 6, title: 'Sensors');
    await scrollBy(500, secs: 2.5);
    await hold(2);

    await tapOn(nav('Live'));
    await say('Live: pick up to 8 readings and press Start to watch them as charts.', 4, title: 'Live data');
    await tapOn(find.text('Start'));
    await anim(1.5);
    await scrollBy(330, secs: 1.5);
    await anim(6);
    await scrollBy(-330, secs: 1);
    await say('Press Stop when done.', 0.1);
    await tapOn(find.text('Stop'));
    await hold(1.5);

    await tapOn(nav('Battery'));
    await say('Battery test: engine OFF, ignition ON. Press Start test, then start the engine after about 3 seconds.', 6, title: 'Battery & charging test');
    com3.last?.simulateEngineStart();
    await tapOn(find.text('Start test'));
    await record(() => state.busy == Busy.none, maxSecs: 16);
    await say('The chart shows the resting voltage, the dip while cranking and the alternator charging voltage – with a verdict.', 6);
    await scrollBy(300, secs: 1.5);
    await hold(4);

    await tapOn(nav('Dashboard'));
    await say('Back on the Dashboard you can scan again or export a PDF report. Every scan is saved in History.', 5, title: 'Dashboard');

    await t.runAsync(state.disconnect);
    await t.pump();
    state.report = null;

    // ============================================================ ANDROID
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await scene(
      badge: 'ANDROID',
      title: 'Install on Android',
      caption: 'Android asks for permission because the app is not from the Play Store – that is expected.',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
        steps([
          'On the phone open github.com/PSG7299/carsense-obd → Releases and download CarSense-android.apk',
          'Open the downloaded file',
          'Tap Settings → allow "Install unknown apps" for your browser, then tap Install',
        ], width: 480),
        const SizedBox(width: 40),
        Column(mainAxisSize: MainAxisSize.min, children: [
          mockDialog('Install unknown apps', 'For your security, your phone is currently not allowed to install unknown apps from this source.', ['Cancel', 'Settings']),
          const SizedBox(height: 18),
          mockDialog('CarSense', 'Do you want to install this app?', ['Cancel', 'Install']),
        ]),
      ]),
    );
    await hold(8);

    await scene(
      badge: 'ANDROID',
      title: 'Connect the phone',
      caption: 'Connect the adapter through the OTG adapter. When Android asks, tick "Always open" and tap OK.',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          node(Icons.usb, 'OBD adapter (in the car)'),
          arrow(),
          node(Icons.cable, 'USB-OTG'),
          arrow(),
          node(Icons.phone_android, 'Phone'),
        ]),
        const SizedBox(width: 40),
        mockDialog('Allow CarSense to access USB2.0-Serial?', '', ['Cancel', 'OK'], check: 'Always open CarSense when USB2.0-Serial is connected', width: 360),
      ]),
    );
    await hold(8);

    final usb = _VideoAdapter('USB2.0-Serial', 'wch.cn · VID 1a86 PID 7523', DemoCar.swiftFaulty);
    state.adapters = [usb, ...[for (final c in DemoCar.values) MockCandidate(c)]];
    Widget side(String text) => Text(text, style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.35, fontWeight: FontWeight.w600));
    await scene(
      badge: 'ANDROID',
      title: 'Check the Swift',
      caption: 'Turn the ignition ON, open CarSense and tap your adapter.',
      content: PhoneFrame(side: side('Your USB adapter appears at the top of the list.\n\nThe demo cars below let you try the app without a car.')),
    );
    await hold(4);
    await tapOn(find.text('USB2.0-Serial'));
    await record(() => state.link == Link.connected, maxSecs: 8);
    ctl.set(content: PhoneFrame(side: side('Detected: Maruti Suzuki Swift.\n\nThe chips list the sensors this car reports.')));
    await say('Connected – the Swift profile is picked automatically from the VIN.', 5);
    await tapOn(find.text('Run full health check'));
    ctl.set(content: PhoneFrame(side: side('Health check running…\n\nKeep the ignition on.')));
    await say('Run full health check (sped up).', 0.1);
    await record(() => state.busy == Busy.none && state.report != null, maxSecs: 14);
    ctl.set(content: PhoneFrame(side: side('This car has problems:\n\n• Check-engine light ON\n• P0420 – catalytic converter\n• P0171 – running lean\n• Rough idle, low charging voltage')));
    await say('Problems found! The score is low and each system shows what needs attention.', 7, title: 'Dashboard');
    await scrollBy(700, secs: 3);
    await say('Scroll down for the fault codes with plain-English meanings, and the emissions self-tests.', 6);
    await scrollBy(700, secs: 3);
    await hold(3);

    await tapOn(nav('Sensors'));
    ctl.set(content: PhoneFrame(side: side('Tap "Problems only" to see just the sensors that need attention.')));
    await say('Sensors: each card shows the value, the normal range and what it means.', 4, title: 'Sensors');
    await tapOn(find.text('Problems only'));
    await hold(5);
    await scrollBy(500, secs: 2.5);
    await hold(3);

    await tapOn(nav('History'));
    ctl.set(content: PhoneFrame(side: side('History keeps every scan on the phone, with trend charts – handy to see if a repair worked.')));
    await say('History: every scan is saved on the device.', 6, title: 'History');

    await t.runAsync(state.disconnect);
    await t.pump();

    // =============================================================== TIPS
    debugDefaultTargetPlatformOverride = null;
    await scene(
      badge: '',
      title: 'Tips',
      caption: 'Full guide, downloads and source code: github.com/PSG7299/carsense-obd',
      content: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        card(Icons.local_parking, 'Always parked', 'Run checks with the car parked and the handbrake on. Never use the app while driving.', width: 270),
        const SizedBox(width: 18),
        card(Icons.lock_outline, 'Check-only', 'CarSense only reads data. It never clears codes or changes anything in the car.', width: 270),
        const SizedBox(width: 18),
        card(Icons.thermostat, 'Warm engine', 'Idle until the engine is warm (about 5 minutes) for the most complete O2 sensor and fuel checks.', width: 270),
        const SizedBox(width: 18),
        card(Icons.build_circle_outlined, 'Not connecting?', 'Check the cable is pushed in, the ignition is ON, the driver (Windows) or OTG (Android) is OK. Try again.', width: 270),
      ]),
    );
    await hold(9);
    await scene(
      title: '',
      caption: '',
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_car_filled, color: _accent, size: 80),
        SizedBox(height: 12),
        Text('Drive safe!', style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
        SizedBox(height: 10),
        Text('github.com/PSG7299/carsense-obd', style: TextStyle(color: Colors.white70, fontSize: 24)),
      ]),
    );
    await hold(4);
    await fadeOut();

    // ffmpeg concat: repeat the last frame so its duration is honoured.
    list.writeln("file 'f${(n - 1).toString().padLeft(5, '0')}.png'");
    File('$outDir/frames.txt').writeAsStringSync(list.toString());
    // ignore: avoid_print
    print('Recorded $n frames, ${total.toStringAsFixed(1)} s of video');
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
