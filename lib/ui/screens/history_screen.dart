import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../diagnostics/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? vehicle;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final b = theme.brightness;
    if (s.history.isEmpty) {
      return const EmptyState(icon: Icons.history, title: 'No saved scans', text: 'Every health check is saved here so you can track your car over time.');
    }
    final vehicles = s.history.map((r) => r.vehicleName).toSet().toList();
    final sel = vehicle != null && vehicles.contains(vehicle) ? vehicle! : vehicles.first;
    final list = s.history.where((r) => r.vehicleName == sel).toList();
    final chrono = list.reversed.toList();
    final fmt = DateFormat('d MMM');

    List<(double, double)> series(double? Function(ScanReport) f) => [
          for (var i = 0; i < chrono.length; i++)
            if (f(chrono[i]) != null) (i.toDouble(), f(chrono[i])!),
        ];
    String xf(double v) {
      final i = v.round();
      return i >= 0 && i < chrono.length && (v - i).abs() < 0.01 ? fmt.format(chrono[i].time) : '';
    }

    final battery = series((r) => r.channelAvg('BATT'));
    final ltft = series((r) => r.channelAvg('LTFT1'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (vehicles.length > 1)
          SegmentedButton<String>(
            segments: [for (final v in vehicles) ButtonSegment(value: v, label: Text(v))],
            selected: {sel},
            onSelectionChanged: (x) => setState(() => vehicle = x.first),
          ),
        const SectionTitle('Health score trend'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: TimeChart(
              points: series((r) => r.score.toDouble()),
              color: theme.colorScheme.primary,
              minY: 0,
              maxY: 100,
              height: 180,
              xFormatter: xf,
              bands: [(80, 100, statusColor(Status.ok, b)), (0, 55, statusColor(Status.fail, b))],
            ),
          ),
        ),
        if (battery.length > 1 || ltft.length > 1)
          ResponsiveGrid(minWidth: 340, children: [
            if (battery.length > 1)
              _TrendCard(title: 'Battery voltage during scans', unit: 'V', points: battery, color: const Color(0xFFFB8C00), xf: xf,
                  bands: [(13.2, 14.8, statusColor(Status.ok, b))]),
            if (ltft.length > 1)
              _TrendCard(title: 'Long-term fuel trim', unit: '%', points: ltft, color: const Color(0xFF8E24AA), xf: xf,
                  bands: [(-10, 10, statusColor(Status.ok, b))]),
          ]),
        SectionTitle('${list.length} saved scans'),
        for (final r in list)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: statusColor(r.overall, b).withValues(alpha: 0.15),
                child: Text('${r.score}', style: TextStyle(color: statusColor(r.overall, b), fontWeight: FontWeight.w800)),
              ),
              title: Text(DateFormat('d MMM yyyy, HH:mm').format(r.time)),
              subtitle: Text('${r.dtcs.length} fault code(s) · ${r.engineRunning ? 'engine running' : 'engine off'}'
                  '${r.battery != null ? ' · battery tested' : ''}'),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete this scan?'),
                      content: const Text('Only removes the saved report from this device.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok ?? false) await s.deleteReport(r);
                },
              ),
              onTap: () {
                s.openReport(r);
                widget.onOpen();
              },
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.unit, required this.points, required this.color, required this.xf, this.bands = const []});
  final String title, unit;
  final List<(double, double)> points;
  final Color color;
  final String Function(double) xf;
  final List<(double, double, Color)> bands;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(left: 8, bottom: 8), child: Text('$title ($unit)', style: Theme.of(context).textTheme.titleSmall)),
            TimeChart(points: points, color: color, height: 150, xFormatter: xf, bands: bands),
          ]),
        ),
      );
}
