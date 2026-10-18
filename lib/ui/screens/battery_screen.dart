import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../diagnostics/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final b = theme.brightness;
    final running = s.busy == Busy.battery;
    final res = s.batteryResult ?? s.report?.battery;
    final trace = running || s.batteryTrace.isNotEmpty ? s.batteryTrace : res?.trace ?? const <List<double>>[];

    Widget stat(String label, double? v, IconData icon) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Icon(icon),
                const SizedBox(height: 4),
                Text(v == null ? '—' : '${v.toStringAsFixed(2)} V', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              ]),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Battery & charging test', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('1. Engine OFF, ignition ON (all lights and A/C off).\n'
                  '2. Press "Start test", wait 3 seconds, then START the engine.\n'
                  '3. Let it idle until the test finishes (20 s).'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: s.busy == Busy.none && s.elm != null ? () => s.runBatteryTest() : null,
                icon: running
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(running ? 'Recording… ${s.batterySecondsLeft}s – start the engine now' : 'Start test'),
              ),
              if (s.elm == null) ...[
                const SizedBox(height: 8),
                Text('Connect an adapter first.', style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
        ),
        const SectionTitle('Voltage over time'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: TimeChart(
              points: [for (final p in trace) (p[0], p[1])],
              color: statusColor(res?.status ?? Status.info, b),
              minY: 8,
              maxY: 16,
              height: 240,
              xLabel: 'seconds',
              bands: [
                (13.2, 14.8, statusColor(Status.ok, b)),
                (8, 9.6, statusColor(Status.fail, b)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('Green band = normal charging (13.2–14.8 V). Red band = cranking dip too deep (< 9.6 V).',
              style: theme.textTheme.bodySmall),
        ),
        if (res != null && !running) ...[
          const SizedBox(height: 12),
          Row(children: [
            stat('At rest', res.restVoltage, Icons.battery_std),
            const SizedBox(width: 8),
            stat('Lowest while cranking', res.crankMin, Icons.offline_bolt_outlined),
            const SizedBox(width: 8),
            stat('Charging', res.chargingVoltage, Icons.electric_bolt),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [StatusPill(res.status), const SizedBox(width: 8), Expanded(child: Text(res.verdict.first.split('.').first, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                const SizedBox(height: 8),
                for (final v in res.verdict)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• ${v.contains('. ') && v == res.verdict.first ? v.substring(v.indexOf('. ') + 2) : v}')),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
