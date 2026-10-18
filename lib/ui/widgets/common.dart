import 'package:flutter/material.dart';

import '../../diagnostics/models.dart';
import '../theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.label});
  final Status status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon(status), size: 14, color: c),
        const SizedBox(width: 4),
        Text(label ?? status.label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ]),
          ),
        ),
      );
}

/// Responsive grid: 1 column on phones, more on tablets / Windows.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 300, this.spacing = 12});
  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, 4);
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      });
}
