import 'package:flutter/material.dart';

import '../diagnostics/models.dart';

const _seed = Color(0xFF1565C0);

ThemeData buildTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
    );

Color statusColor(Status s, [Brightness b = Brightness.light]) => switch (s) {
      Status.ok => b == Brightness.dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32),
      Status.warn => b == Brightness.dark ? const Color(0xFFFFCA28) : const Color(0xFFF9A825),
      Status.fail => b == Brightness.dark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
      Status.info => b == Brightness.dark ? const Color(0xFF90A4AE) : const Color(0xFF607D8B),
    };

IconData statusIcon(Status s) => switch (s) {
      Status.ok => Icons.check_circle,
      Status.warn => Icons.warning_amber_rounded,
      Status.fail => Icons.error,
      Status.info => Icons.info_outline,
    };

String fmtValue(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
