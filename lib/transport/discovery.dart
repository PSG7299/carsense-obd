import 'dart:io';

import 'mock_transport.dart';
import 'replay_transport.dart';
import 'serial_desktop_transport.dart';
import 'transport.dart';
import 'usb_android_transport.dart';

/// Lists real adapters for the current platform, followed by demo cars.
Future<List<TransportCandidate>> discoverAdapters() async {
  final out = <TransportCandidate>[];
  try {
    if (Platform.isAndroid) {
      out.addAll(await UsbAndroidCandidate.list());
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      out.addAll(SerialDesktopCandidate.list());
    }
  } catch (_) {
    // Plugin unavailable (e.g. tests) – demo cars still work.
  }
  out.addAll(DemoCar.values.map(MockCandidate.new));
  try {
    out.addAll(await ReplayCandidate.list());
  } catch (_) {
    // No bundled simulations (e.g. some tests).
  }
  return out;
}
