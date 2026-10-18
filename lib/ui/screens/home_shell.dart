import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'battery_screen.dart';
import 'connect_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'live_screen.dart';
import 'sensors_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const _dest = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.sensors_outlined, Icons.sensors, 'Sensors'),
    (Icons.show_chart_outlined, Icons.show_chart, 'Live'),
    (Icons.battery_charging_full_outlined, Icons.battery_charging_full, 'Battery'),
    (Icons.history_outlined, Icons.history, 'History'),
  ];

  void go(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = switch (index) {
      0 => DashboardScreen(onNavigate: go),
      1 => const SensorsScreen(),
      2 => const LiveScreen(),
      3 => const BatteryScreen(),
      _ => HistoryScreen(onOpen: () => go(0)),
    };

    final content = s.link == Link.connected || index == 4 || s.report != null && index < 2
        ? body
        : ConnectScreen(onConnected: () => go(0));

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.directions_car_filled),
          SizedBox(width: 8),
          Text('CarSense', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          _ConnectionChip(state: s),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
        Expanded(child: SafeArea(top: false, child: content)),
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: go,
              destinations: [
                for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (state.link) {
      Link.connected => InputChip(
          avatar: Icon(Icons.usb, color: cs.primary, size: 18),
          label: Text(state.isDemo ? 'Demo' : 'Connected'),
          onDeleted: state.busy == Busy.scanning ? null : state.disconnect,
          deleteIcon: const Icon(Icons.link_off, size: 18),
          deleteButtonTooltipMessage: 'Disconnect',
        ),
      Link.connecting => const Chip(
          avatar: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text('Connecting…'),
        ),
      Link.disconnected => Chip(avatar: Icon(Icons.usb_off, size: 18, color: cs.outline), label: const Text('Not connected')),
    };
  }
}
