# Vendored plugins

Patched copies of two plugins whose Android build files no longer work with
current Android Gradle Plugin versions (they use the removed `jcenter()`
repository). Used via `dependency_overrides` in `pubspec.yaml`.

| Package | Version | Change |
|---|---|---|
| `flutter_libserialport` | 0.6.0 | Android platform removed (the app only uses it on Windows/Linux/macOS; Android uses `usb_serial`). Example and docs removed. |
| `usb_serial` | 0.5.2 | `android/build.gradle` modernised: `mavenCentral()` instead of `jcenter()`, no legacy buildscript block, `compileSdk 34`, `minSdk 21`, Java 17. Example removed. |

Original licenses are kept in each folder (flutter_libserialport: MIT, with the bundled libserialport C library under LGPL-3.0; usb_serial: BSD-3-Clause).
