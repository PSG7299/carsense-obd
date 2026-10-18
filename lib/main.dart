import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()
        ..refreshAdapters()
        ..loadHistory(),
      child: const CarSenseApp(),
    ),
  );
}

class CarSenseApp extends StatelessWidget {
  const CarSenseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CarSense OBD',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
      );
}
