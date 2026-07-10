import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_bits.dart';
import 'broker_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cfg = Map<String, dynamic>.from(state.risk?['config'] as Map? ?? {});
    final schedule = cfg['trade_schedule']?.toString() ?? 'market_hours_only';
    final autoExit = cfg['auto_exit'] != false;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'TradeForge · v1.0.0',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const BrandMark(size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TradeForge', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(
                        'Educational paper-first trading assistant',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Brokerage'),
        Card(
          child: ListTile(
            leading: Icon(
              state.broker?['is_live'] == true
                  ? Icons.warning_amber_rounded
                  : Icons.account_balance_outlined,
              color: state.broker?['is_live'] == true ? AppTheme.loss : AppTheme.seedDeep,
            ),
            title: Text(
              state.broker?['label']?.toString() ?? 'TradeForge Paper (sim)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Sim paper · Alpaca paper · Alpaca live'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BrokerScreen()),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Connection'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.cloud_done_outlined, color: AppTheme.seedDeep),
                title: const Text('API endpoint', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(ApiService.baseUrl, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Device ID', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(state.deviceId ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: state.deviceId == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: state.deviceId!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device ID copied')),
                          );
                        },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Trading preferences'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.schedule),
                title: const Text('Market hours only', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Bot only enters during NYSE session'),
                value: schedule == 'market_hours_only',
                onChanged: (v) => state.updateConfig({
                  'trade_schedule': v ? 'market_hours_only' : 'always',
                }),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.exit_to_app),
                title: const Text('Auto exits', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Close paper positions on stop / target'),
                value: autoExit,
                onChanged: (v) => state.updateConfig({'auto_exit': v}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Legal & about'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(
                  Uri.parse('${ApiService.baseUrl}/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Disclaimer', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Not financial advice. Paper results ≠ live results.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () => state.refreshAll(),
          icon: const Icon(Icons.sync),
          label: const Text('Reconnect / refresh'),
        ),
        const SizedBox(height: 20),
        Text(
          'TradeForge is a separate project from Robin the Hood / AutoTrade. '
          'Compare both and pick what you prefer for the Play Store.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}
