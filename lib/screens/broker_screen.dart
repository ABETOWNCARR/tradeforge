import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_bits.dart';

class BrokerScreen extends StatefulWidget {
  const BrokerScreen({super.key});

  @override
  State<BrokerScreen> createState() => _BrokerScreenState();
}

class _BrokerScreenState extends State<BrokerScreen> {
  final _keyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _paper = true;
  bool _busy = false;
  bool _showSecret = false;
  bool _liveAck = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final state = context.read<AppState>();
    if (_keyCtrl.text.trim().isEmpty || _secretCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both Alpaca API key and secret')),
      );
      return;
    }
    if (!_paper && !_liveAck) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm the live-money warning to continue')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await state.connectAlpaca(
        apiKey: _keyCtrl.text.trim(),
        apiSecret: _secretCtrl.text.trim(),
        paper: _paper,
        enableLive: !_paper,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _keyCtrl.clear();
        _secretCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_paper
                ? 'Alpaca Paper connected'
                : 'Alpaca LIVE connected — real money'),
            backgroundColor: _paper ? AppTheme.profit : AppTheme.loss,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error']?.toString() ?? 'Connect failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final broker = state.broker ?? {};
    final mode = broker['broker_mode']?.toString() ?? 'sim';
    final label = broker['label']?.toString() ?? 'TradeForge Paper (sim)';
    final isLive = broker['is_live'] == true;
    final acct = broker['account_live'] as Map<String, dynamic>? ??
        broker['account'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text(
          'Brokerage',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Start on sim paper. Connect Alpaca when you’re ready — paper first, live later.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 14),
        Card(
          color: isLive
              ? AppTheme.loss.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: ListTile(
            leading: Icon(
              isLive ? Icons.warning_amber_rounded : Icons.account_balance_outlined,
              color: isLive ? AppTheme.loss : null,
            ),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              mode == 'sim'
                  ? 'Virtual \$10k — no brokerage keys needed'
                  : isLive
                      ? 'REAL MONEY — bot will place live orders'
                      : 'Alpaca paper account (simulated cash at Alpaca)',
            ),
          ),
        ),
        if (acct != null) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _kv('Status', '${acct['status'] ?? '—'}'),
                  _kv('Equity', '\$${acct['equity'] ?? '—'}'),
                  _kv('Cash', '\$${acct['cash'] ?? '—'}'),
                  if (acct['buying_power'] != null)
                    _kv('Buying power', '\$${acct['buying_power']}'),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const SectionHeader(
          title: 'Active broker',
          subtitle: 'Where the bot places orders',
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sim', label: Text('Sim'), icon: Icon(Icons.science_outlined, size: 16)),
            ButtonSegment(value: 'alpaca_paper', label: Text('Alpaca paper'), icon: Icon(Icons.article_outlined, size: 16)),
            ButtonSegment(value: 'alpaca_live', label: Text('LIVE'), icon: Icon(Icons.bolt, size: 16)),
          ],
          selected: {
            mode == 'alpaca_live'
                ? 'alpaca_live'
                : mode == 'alpaca_paper'
                    ? 'alpaca_paper'
                    : 'sim',
          },
          onSelectionChanged: _busy
              ? null
              : (s) async {
                  final next = s.first;
                  if (next == 'alpaca_live') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Enable LIVE trading?'),
                        content: const Text(
                          'This uses REAL money through Alpaca. '
                          'Confirm risk limits, kill switch, and position size first.\n\n'
                          'Not financial advice. You are solely responsible for losses.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.loss),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('I understand — go LIVE'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  setState(() => _busy = true);
                  try {
                    await state.setBrokerMode(next, liveConfirm: next == 'alpaca_live');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        const SizedBox(height: 22),
        const SectionHeader(
          title: 'Connect Alpaca',
          subtitle: 'Create free paper keys at app.alpaca.markets',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Paper keys')),
                    ButtonSegment(value: false, label: Text('Live keys')),
                  ],
                  selected: {_paper},
                  onSelectionChanged: (s) => setState(() {
                    _paper = s.first;
                    if (_paper) _liveAck = false;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key ID',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _secretCtrl,
                  obscureText: !_showSecret,
                  decoration: InputDecoration(
                    labelText: 'API Secret',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showSecret = !_showSecret),
                    ),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                if (!_paper) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _liveAck,
                    onChanged: (v) => setState(() => _liveAck = v ?? false),
                    title: const Text(
                      'I understand these are LIVE keys and real money can be lost',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: Text(_paper ? 'Connect Alpaca Paper' : 'Connect Alpaca LIVE'),
                    style: !_paper
                        ? FilledButton.styleFrom(backgroundColor: AppTheme.loss)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await state.disconnectBroker();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Disconnected — back on sim paper')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect broker (use sim paper)'),
        ),
        const SizedBox(height: 20),
        Text(
          'How this works\n'
          '• Sim: TradeForge virtual \$10k (default, safest for testing the app).\n'
          '• Alpaca Paper: same bot logic against Alpaca’s paper account.\n'
          '• Alpaca Live: real money — requires explicit confirmation.\n'
          '• Keys are stored on the TradeForge backend for your device ID only.\n'
          '• Kill switch, daily entry limits, and position size still apply.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.grey))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
