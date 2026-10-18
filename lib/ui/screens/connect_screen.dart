import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../transport/replay_transport.dart';
import '../../transport/transport.dart';
import '../widgets/common.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key, required this.onConnected});
  final VoidCallback onConnected;

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final real = s.adapters.where((a) => !a.isDemo).toList();
    final demo = s.adapters.where((a) => a.isDemo && a is! ReplayCandidate).toList();
    final sims = s.adapters.whereType<ReplayCandidate>().toList();

    Future<void> connect(TransportCandidate c) async {
      final state = context.read<AppState>();
      await state.connect(c);
      if (state.link == Link.connected) onConnected();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Connect your car', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _Step(1, 'Plug the USB OBD-II adapter into the port under the dashboard (driver side, near your knees).'),
                    _Step(2, isAndroid
                        ? 'Connect the adapter to your phone with a USB-OTG adapter and allow USB access when asked.'
                        : 'Connect the adapter to this PC. It appears as a COM port (install the CH340/FTDI driver if it does not).'),
                    _Step(3, 'Turn the ignition ON (engine may be off or idling). Car must be parked.'),
                    _Step(4, 'Pick your adapter below.'),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Check-only: CarSense only reads data and never changes or clears anything in your car.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (s.error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                    title: Text(s.error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ),
              ],
              SectionTitle(
                'USB adapters',
                trailing: s.discovering
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(tooltip: 'Refresh', onPressed: s.refreshAdapters, icon: const Icon(Icons.refresh)),
              ),
              if (real.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.usb_off),
                    title: const Text('No adapter found'),
                    subtitle: Text(isAndroid
                        ? 'Plug in the adapter via OTG and tap refresh.'
                        : 'Plug in the adapter and tap refresh. Check Device Manager → Ports (COM & LPT).'),
                  ),
                ),
              for (final a in real)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.usb),
                    title: Text(a.title),
                    subtitle: Text(a.subtitle),
                    trailing: s.link == Link.connecting && s.connectedName == a.title
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: s.link == Link.connecting ? null : () => connect(a),
                  ),
                ),
              const SectionTitle('Try without a car'),
              for (final a in demo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: Text(a.title),
                      subtitle: Text(a.subtitle),
                      trailing: s.link == Link.connecting && s.connectedName == a.title
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: s.link == Link.connecting ? null : () => connect(a),
                    ),
                  ),
                ),
              if (sims.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.functions),
                    title: Text('MATLAB simulations (${sims.length})'),
                    subtitle: const Text('Nexon & Swift fault scenarios recorded from the car simulation'),
                    children: [
                      for (final a in sims)
                        ListTile(
                          dense: true,
                          title: Text(a.title.replaceFirst('MATLAB sim: ', '')),
                          subtitle: Text(a.subtitle),
                          trailing: s.link == Link.connecting && s.connectedName == a.title
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.chevron_right),
                          onTap: s.link == Link.connecting ? null : () => connect(a),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 11, backgroundColor: cs.primary, child: Text('$n', style: TextStyle(fontSize: 12, color: cs.onPrimary))),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: cs.onPrimaryContainer))),
      ]),
    );
  }
}
