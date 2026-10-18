import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../diagnostics/health_engine.dart';
import '../../diagnostics/models.dart';
import '../../obd/dtc.dart';
import '../../obd/pids.dart';
import '../../report/pdf_report.dart';
import '../../state/app_state.dart';
import '../../vehicles/profiles.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/health_gauge.dart';

IconData systemIcon(CarSystem s) => switch (s) {
      CarSystem.engine => Icons.settings_suggest,
      CarSystem.intake => Icons.air,
      CarSystem.fuel => Icons.local_gas_station,
      CarSystem.o2Catalyst => Icons.cloud_outlined,
      CarSystem.cooling => Icons.thermostat,
      CarSystem.electrical => Icons.battery_charging_full,
      CarSystem.emissions => Icons.eco_outlined,
      CarSystem.faults => Icons.report_problem_outlined,
    };

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final void Function(int tab) onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (s.error != null) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text(s.error!)),
          ),
          const SizedBox(height: 12),
        ],
        if (s.busy == Busy.scanning) _ScanProgress(s) else if (r == null) _StartScan(s),
        if (r != null && s.busy != Busy.scanning) ..._report(context, s, r),
      ],
    );
  }

  List<Widget> _report(BuildContext context, AppState s, ScanReport r) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return [
      LayoutBuilder(builder: (context, c) {
        final gauge = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: HealthGauge(score: r.score, status: r.overall, size: c.maxWidth >= 700 ? 240 : 210)),
          ),
        );
        final car = _VehicleCard(r: r, s: s);
        if (c.maxWidth < 700) return Column(children: [gauge, const SizedBox(height: 12), car]);
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 300, child: gauge),
            const SizedBox(width: 12),
            Expanded(child: car),
          ]),
        );
      }),
      SectionTitle('Condition by system', trailing: Text('${r.systems.length} systems', style: theme.textTheme.bodySmall)),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: [
            for (final sys in r.systems)
              InkWell(
                onTap: () => sys.system == CarSystem.faults
                    ? _showFaults(context, r)
                    : sys.system == CarSystem.electrical
                        ? onNavigate(3)
                        : onNavigate(1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(systemIcon(sys.system), size: 20, color: statusColor(sys.status, b)),
                    const SizedBox(width: 10),
                    SizedBox(width: 150, child: Text(sys.system.label, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: sys.score / 100),
                          duration: const Duration(milliseconds: 700),
                          builder: (_, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 12,
                            color: statusColor(sys.status, b),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 34, child: Text('${sys.score}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      const SectionTitle('System details'),
      ResponsiveGrid(children: [
        for (final sys in r.systems)
          Card(
            child: InkWell(
              onTap: () => sys.system == CarSystem.faults
                  ? _showFaults(context, r)
                  : sys.system == CarSystem.electrical
                      ? onNavigate(3)
                      : onNavigate(1),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      backgroundColor: statusColor(sys.status, b).withValues(alpha: 0.15),
                      child: Icon(systemIcon(sys.system), color: statusColor(sys.status, b)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(sys.system.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                    StatusPill(sys.status),
                  ]),
                  const SizedBox(height: 10),
                  Text(sys.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
      ]),
      SectionTitle('Fault codes', trailing: r.dtcs.isEmpty ? null : TextButton(onPressed: () => _showFaults(context, r), child: const Text('Details'))),
      if (r.dtcs.isEmpty)
        Card(
          child: ListTile(
            leading: Icon(Icons.verified, color: statusColor(Status.ok, b)),
            title: const Text('No fault codes'),
            subtitle: Text(r.monitors?.milOn ?? false ? 'Check-engine light is ON' : 'Check-engine light is off'),
          ),
        )
      else
        for (final d in r.dtcs) _DtcTile(d),
      if (r.monitors != null) ...[
        SectionTitle('Emissions self-tests (readiness)',
            trailing: Text('${r.monitors!.monitors.length - r.monitors!.incomplete}/${r.monitors!.monitors.length} complete',
                style: theme.textTheme.bodySmall)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in r.monitors!.monitors.entries)
            StatusPill(e.value ? Status.ok : Status.warn, label: '${e.key}${e.value ? '' : ' – not ready'}'),
        ]),
      ],
      if (r.notes.isNotEmpty) ...[
        const SectionTitle('Notes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final n in r.notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lightbulb_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(n)),
                  ]),
                ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (s.link == Link.connected)
          FilledButton.icon(onPressed: s.busy == Busy.none ? s.runScan : null, icon: const Icon(Icons.refresh), label: const Text('Scan again')),
        OutlinedButton.icon(onPressed: () => _exportPdf(context, r), icon: const Icon(Icons.picture_as_pdf), label: const Text('Export PDF report')),
        if (r.battery == null && s.link == Link.connected)
          OutlinedButton.icon(onPressed: () => onNavigate(3), icon: const Icon(Icons.battery_charging_full), label: const Text('Run battery test')),
      ]),
      const SizedBox(height: 24),
    ];
  }

  static Future<void> _exportPdf(BuildContext context, ScanReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    try {
      final bytes = await buildPdfReport(r);
      final name = 'CarSense_${r.vehicleName.split(' ').take(2).join('_')}_${DateFormat('yyyyMMdd_HHmm').format(r.time)}.pdf'
          .replaceAll(RegExp(r'[^\w.\-]'), '');
      final folder = await state.store.exportsFolder();
      final f = File('$folder${Platform.pathSeparator}$name');
      await f.writeAsBytes(bytes);
      messenger.showSnackBar(SnackBar(content: Text('Saved to ${f.path}')));
      await Printing.sharePdf(bytes: bytes, filename: name);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
    }
  }

  static void _showFaults(BuildContext context, ScanReport r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Fault codes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (r.dtcs.isEmpty) const Text('No stored, pending or permanent fault codes.'),
            for (final d in r.dtcs) _DtcTile(d, expanded: true),
            const SizedBox(height: 12),
            for (final k in DtcKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${k.label}: ${k.meaning}', style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Text('CarSense is check-only and does not clear codes. Get the cause fixed, and the car will clear them itself.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DtcTile extends StatelessWidget {
  const _DtcTile(this.d, {this.expanded = false});
  final Dtc d;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final st = d.kind == DtcKind.pending
        ? Status.warn
        : d.severity == Severity.low
            ? Status.warn
            : Status.fail;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor(st, b).withValues(alpha: 0.15),
          child: Icon(Icons.report, color: statusColor(st, b)),
        ),
        title: Text('${d.code} · ${d.kind.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(expanded ? '${d.description}\nSeverity: ${d.severity.name} · ECU ${d.ecu}' : d.description),
        isThreeLine: expanded,
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.r, required this.s});
  final ScanReport r;
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData i, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(i, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            SizedBox(width: 92, child: Text(k, style: theme.textTheme.bodySmall)),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.vehicleName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          row(Icons.qr_code, 'VIN', r.vin ?? 'Not reported by car'),
          row(Icons.factory_outlined, 'Maker', '${r.maker}${r.modelYear != null ? ' · ${r.modelYear}' : ''}'),
          row(Icons.cable, 'Protocol', r.protocol),
          row(Icons.power_settings_new, 'Engine', r.engineRunning ? 'Running' : 'Off (ignition on)'),
          if (r.fuelSystem != null) row(Icons.loop, 'Fuel control', r.fuelSystem!),
          row(Icons.schedule, 'Scanned', DateFormat('d MMM yyyy, HH:mm').format(r.time)),
          row(Icons.sensors, 'Sensors', '${r.detectedSensors.length} detected'),
        ]),
      ),
    );
  }
}

class _StartScan extends StatelessWidget {
  const _StartScan(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obd = s.obd;
    final detected = obd == null
        ? <String>[]
        : const HealthEngine().detectedSensors(ScanData(profile: s.profile, supportedPids: obd.supported));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.directions_car, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.profile.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text([
                    if (obd?.vin != null) 'VIN ${obd!.vin}',
                    if (obd?.modelYear != null) '${obd!.modelYear}',
                    s.elm?.protocol.label ?? '',
                  ].where((e) => e.isNotEmpty).join(' · ')),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: s.profile.id,
              decoration: const InputDecoration(labelText: 'Car profile', border: OutlineInputBorder(), isDense: true),
              items: [for (final p in allProfiles) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (id) => s.setProfile(id == null ? null : profileById(id)),
            ),
            const SizedBox(height: 4),
            Text(s.profile.engine, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: s.busy == Busy.none ? s.runScan : null,
                icon: const Icon(Icons.health_and_safety),
                label: const Text('Run full health check', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            Text('For the most complete check, start the engine and let it idle until warm (about 5 minutes). Takes ~30 seconds.',
                style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
      SectionTitle('Sensors detected on this car', trailing: Text('${detected.length}', style: theme.textTheme.bodySmall)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in detected) Chip(avatar: const Icon(Icons.sensors, size: 16), label: Text(d)),
      ]),
      if (s.profile.expectedSensors.isNotEmpty) ...[
        SectionTitle('Fitted to a ${s.profile.name.split(' (').first} (reference)'),
        Text(
          'Sensors not listed above (e.g. knock or cam sensors) are still monitored by the engine computer and show up as fault codes if they fail.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in s.profile.expectedSensors) Chip(label: Text(d), visualDensity: VisualDensity.compact),
        ]),
      ],
    ]);
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.manage_search, size: 56),
            const SizedBox(height: 12),
            Text('Checking your car…', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: s.progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 12),
            Text(s.progressText, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Keep the ignition on. Nothing in the car is changed.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
