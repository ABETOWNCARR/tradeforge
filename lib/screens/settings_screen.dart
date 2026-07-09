import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cfg = Map<String, dynamic>.from(state.risk?['config'] as Map? ?? {});
    final schedule = cfg['trade_schedule']?.toString() ?? 'market_hours_only';
    final autoExit = cfg['auto_exit'] != false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Device ID'),
            subtitle: Text(state.deviceId ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('API endpoint'),
            subtitle: Text(ApiService.baseUrl),
          ),
        ),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Market hours only'),
            subtitle: const Text('Bot only enters during NYSE session'),
            value: schedule == 'market_hours_only',
            onChanged: (v) => state.updateConfig({
              'trade_schedule': v ? 'market_hours_only' : 'always',
            }),
          ),
        ),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.exit_to_app),
            title: const Text('Auto exits'),
            subtitle: const Text('Close paper positions on stop / target'),
            value: autoExit,
            onChanged: (v) => state.updateConfig({'auto_exit': v}),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(
              Uri.parse('${ApiService.baseUrl}/privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About TradeForge'),
            subtitle: const Text(
                'Educational paper-first auto trading assistant.\nNot financial advice. v1.0.0'),
            isThreeLine: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => state.refreshAll(),
          icon: const Icon(Icons.sync),
          label: const Text('Reconnect / refresh'),
        ),
        const SizedBox(height: 24),
        Text(
          'TradeForge is separate from Robin the Hood / AutoTrade. '
          'Compare both apps and choose what you prefer for Play Store publishing.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
