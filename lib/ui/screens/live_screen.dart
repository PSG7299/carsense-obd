import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../obd/pids.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/health_gauge.dart';

/// Typical display ranges for the live gauges and charts.
const _displayRange = <String, (double, double)>{
  'RPM': (0, 6500),
  'ECT': (0, 120),
  'IAT': (0, 80),
  'MAP': (0, 250),
  'BATT': (10, 16),
  'ECU_V': (10, 16),
  'O2V_B1S1': (0, 1),
  'O2V_B1S2': (0, 1),
  'STFT1': (-25, 25),
  'LTFT1': (-25, 25),
  'TPS': (0, 100),
  'LOAD': (0, 100),
  'VSS': (0, 200),
  'TIMING': (-10, 40),
};

const _palette = [
  Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFE53935), Color(0xFF8E24AA),
  Color(0xFFFB8C00), Color(0xFF00ACC1), Color(0xFF6D4C41), Color(0xFF3949AB),
];

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final chans = s.liveChannels;
    final running = s.busy == Busy.live;
    final selected = [for (final id in chans.keys) if (s.liveSelection.contains(id)) id];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text('Live data', style: Theme.of(context).textTheme.titleLarge)),
          FilledButton.icon(
            onPressed: running
                ? s.stopLive
                : s.busy == Busy.none
                    ? s.startLive
                    : null,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? 'Stop' : 'Start'),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Pick up to 8 readings. Fewer readings = faster updates.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in chans.keys)
            FilterChip(
              label: Text(channelTable[id]?.name ?? id),
              selected: s.liveSelection.contains(id),
              onSelected: (_) => s.toggleLiveChannel(id),
            ),
        ]),
        const SizedBox(height: 16),
        ResponsiveGrid(minWidth: 360, children: [
          for (var i = 0; i < selected.length; i++) _LiveCard(id: selected[i], color: _palette[i % _palette.length], points: s.live[selected[i]] ?? const []),
        ]),
        if (selected.isEmpty) const EmptyState(icon: Icons.show_chart, title: 'Nothing selected', text: 'Choose readings above, then press Start.'),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.id, required this.color, required this.points});
  final String id;
  final Color color;
  final List<LivePoint> points;

  @override
  Widget build(BuildContext context) {
    final ch = channelTable[id];
    final theme = Theme.of(context);
    final range = _displayRange[id];
    final last = points.isEmpty ? null : points.last.v;
    final frac = last == null || range == null ? 0.0 : (last - range.$1) / (range.$2 - range.$1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(ch?.name ?? id, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (range != null) MiniMeter(fraction: frac, color: color),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(last == null ? '—' : fmtValue(last), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(ch?.unit ?? '')),
          ]),
          const SizedBox(height: 8),
          TimeChart(
            points: [for (final p in points) (p.t, p.v)],
            color: color,
            minY: range?.$1,
            maxY: range?.$2,
            height: 140,
            xFormatter: (v) => '${v.toStringAsFixed(0)}s',
          ),
        ]),
      ),
    );
  }
}
