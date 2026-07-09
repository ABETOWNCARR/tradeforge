import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

class BotScreen extends StatelessWidget {
  const BotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cfg = Map<String, dynamic>.from(state.risk?['config'] as Map? ?? {});
    final daily = Map<String, dynamic>.from(state.risk?['daily'] as Map? ?? {});
    final mode = cfg['trading_mode']?.toString() ?? 'paper';
    final kill = cfg['kill_switch'] == true;
    final paused = cfg['is_paused'] == true;
    final strategies = Map<String, dynamic>.from(cfg['strategies'] as Map? ?? {});
    final pending = state.approvals.where((a) => a['status'] == 'pending').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Trading bot',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Autonomous paper engine with hard risk gates.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Card(
          color: kill
              ? AppTheme.loss.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: SwitchListTile(
            title: const Text('Kill switch', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(kill ? 'All auto trading halted' : 'Bot may trade when armed'),
            value: kill,
            onChanged: (v) => state.setKillSwitch(v),
          ),
        ),
        Card(
          child: SwitchListTile(
            title: const Text('Pause trading'),
            value: paused && !kill,
            onChanged: kill ? null : (v) => state.updateConfig({'is_paused': v}),
          ),
        ),
        const SizedBox(height: 12),
        Text('Mode', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'paper', label: Text('Auto paper'), icon: Icon(Icons.bolt)),
            ButtonSegment(value: 'approval', label: Text('Approvals'), icon: Icon(Icons.fact_check)),
          ],
          selected: {mode == 'approval' ? 'approval' : 'paper'},
          onSelectionChanged: (s) => state.updateConfig({'trading_mode': s.first}),
        ),
        const SizedBox(height: 16),
        Text('Risk limits',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _sliderCard(
          context,
          title: 'Min confidence',
          value: (cfg['min_confidence'] as num?)?.toDouble() ?? 0.75,
          min: 0.5,
          max: 0.95,
          label: '${(((cfg['min_confidence'] as num?)?.toDouble() ?? 0.75) * 100).round()}%',
          onChanged: (v) => state.updateConfig({'min_confidence': double.parse(v.toStringAsFixed(2))}),
        ),
        _sliderCard(
          context,
          title: 'Max position \$',
          value: (cfg['max_position_dollars'] as num?)?.toDouble() ?? 500,
          min: 50,
          max: 2000,
          divisions: 39,
          label: '\$${((cfg['max_position_dollars'] as num?)?.toDouble() ?? 500).round()}',
          onChanged: (v) => state.updateConfig({'max_position_dollars': v.roundToDouble()}),
        ),
        _sliderCard(
          context,
          title: 'Max trades / day',
          value: ((cfg['max_trades_per_day'] as num?)?.toDouble() ?? 5),
          min: 1,
          max: 20,
          divisions: 19,
          label: '${cfg['max_trades_per_day'] ?? 5}',
          onChanged: (v) => state.updateConfig({'max_trades_per_day': v.round()}),
        ),
        _sliderCard(
          context,
          title: 'Daily loss limit \$',
          value: (cfg['daily_loss_limit'] as num?)?.toDouble() ?? 200,
          min: 25,
          max: 1000,
          divisions: 39,
          label: '\$${((cfg['daily_loss_limit'] as num?)?.toDouble() ?? 200).round()}',
          onChanged: (v) => state.updateConfig({'daily_loss_limit': v.roundToDouble()}),
        ),
        Card(
          child: ListTile(
            title: const Text('Today'),
            subtitle: Text(
                'Trades: ${daily['trades'] ?? 0} · Realized P&L: \$${(daily['realized_pnl'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Strategies',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._strategyLabels.entries.map((e) {
          final on = strategies[e.key] != false;
          return Card(
            child: SwitchListTile(
              title: Text(e.value),
              value: on,
              onChanged: (v) => state.updateConfig({
                'strategies': {e.key: v},
              }),
            ),
          );
        }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.loading ? null : () => state.runBotCycle(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run bot cycle now'),
        ),
        const SizedBox(height: 20),
        Text('Pending approvals (${pending.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Card(child: ListTile(title: Text('No pending approvals')))
        else
          ...pending.map((a) => Card(
                child: ListTile(
                  title: Text('${a['ticker']} · ${a['pattern']}'),
                  subtitle: Text(
                      '${a['signal']} · conf ${((a['confidence'] as num?)?.toDouble() ?? 0) * 100}% · \$${a['dollar_amount']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.loss),
                        onPressed: () => state.resolveApproval(a['id'].toString(), false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: AppTheme.profit),
                        onPressed: () => state.resolveApproval(a['id'].toString(), true),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  static const _strategyLabels = {
    'rsi_bounce': 'RSI Oversold Bounce',
    'bull_flag': 'Bull Flag',
    'ascending_triangle': 'Ascending Triangle',
    'cup_handle': 'Cup & Handle',
    'head_shoulders': 'Head & Shoulders',
    'ma_cross': 'MA Cross (20/50)',
    'volume_breakout': 'Volume Breakout',
  };

  Widget _sliderCard(
    BuildContext context, {
    required String title,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
