import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../diagnostics/models.dart';
import '../../obd/pids.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart' show systemIcon;

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  bool problemsOnly = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.report;
    if (r == null) {
      return const EmptyState(
        icon: Icons.sensors,
        title: 'No scan yet',
        text: 'Run a full health check from the Dashboard to see every sensor, its value and whether it is working.',
      );
    }
    final list = r.sensors.where((x) => !problemsOnly || x.status.index >= Status.warn.index).toList();
    final bySystem = <CarSystem, List<SensorResult>>{};
    for (final x in list) {
      bySystem.putIfAbsent(x.system, () => []).add(x);
    }
    final problems = r.sensors.where((x) => x.status.index >= Status.warn.index).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: Text('${r.sensors.length} readings · $problems need attention', style: Theme.of(context).textTheme.titleMedium),
          ),
          FilterChip(
            label: const Text('Problems only'),
            selected: problemsOnly,
            onSelected: (v) => setState(() => problemsOnly = v),
          ),
        ]),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.sensors),
          title: Text('${r.detectedSensors.length} sensors detected on this car'),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [for (final d in r.detectedSensors) Chip(label: Text(d))]),
            const SizedBox(height: 8),
          ],
        ),
        for (final e in bySystem.entries) ...[
          SectionTitle(e.key.label, trailing: Icon(systemIcon(e.key), size: 20)),
          ResponsiveGrid(minWidth: 340, children: [for (final x in e.value) _SensorCard(x)]),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard(this.x);
  final SensorResult x;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = statusColor(x.status, theme.brightness);
    return Card(
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 4))),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(x.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            StatusPill(x.status),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtValue(x.avg), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(x.unit)),
            const Spacer(),
            Text('min ${fmtValue(x.min)} · max ${fmtValue(x.max)}', style: theme.textTheme.bodySmall),
          ]),
          if (x.samples.length > 2) ...[
            const SizedBox(height: 6),
            Sparkline(values: x.samples, color: c),
          ],
          const SizedBox(height: 6),
          Text(x.message),
          if (x.normal.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Normal: ${x.normal}', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}
