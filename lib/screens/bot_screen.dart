import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/ui_bits.dart';

class BotScreen extends StatelessWidget {
  const BotScreen({super.key});

  static const _strategyLabels = {
    'rsi_bounce': 'RSI Oversold Bounce',
    'bull_flag': 'Bull Flag',
    'ascending_triangle': 'Ascending Triangle',
    'cup_handle': 'Cup & Handle',
    'head_shoulders': 'Head & Shoulders',
    'ma_cross': 'MA Cross (20/50)',
    'volume_breakout': 'Volume Breakout',
  };

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
    final canTrade = state.risk?['can_trade_now'] == true;

    return LoadingOverlay(
      loading: state.loading,
      message: 'Updating bot…',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Text(
            'Trading bot',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Autonomous paper engine with hard risk gates',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Card(
            color: kill
                ? AppTheme.loss.withValues(alpha: 0.10)
                : canTrade
                    ? AppTheme.profit.withValues(alpha: 0.08)
                    : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    kill ? Icons.dangerous_outlined : Icons.shield_moon_outlined,
                    color: kill ? AppTheme.loss : AppTheme.seedDeep,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kill
                              ? 'Kill switch ON'
                              : canTrade
                                  ? 'Bot armed'
                                  : 'Bot idle',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          kill
                              ? 'All autonomous entries halted'
                              : 'Mode: ${mode == 'approval' ? 'Approvals' : 'Auto paper'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: state.marketOpen ? 'Open' : 'Closed',
                    color: state.marketOpen ? AppTheme.profit : Colors.blueGrey,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Icon(Icons.power_settings_new, color: kill ? AppTheme.loss : null),
              title: const Text('Kill switch', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(kill ? 'Trading halted' : 'Allow bot activity'),
              value: kill,
              onChanged: (v) => state.setKillSwitch(v),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: const Icon(Icons.pause_circle_outline),
              title: const Text('Pause trading', style: TextStyle(fontWeight: FontWeight.w700)),
              value: paused && !kill,
              onChanged: kill ? null : (v) => state.updateConfig({'is_paused': v}),
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Mode', subtitle: 'How the bot handles signals'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'paper', label: Text('Auto paper'), icon: Icon(Icons.bolt, size: 18)),
              ButtonSegment(value: 'approval', label: Text('Approvals'), icon: Icon(Icons.fact_check, size: 18)),
            ],
            selected: {mode == 'approval' ? 'approval' : 'paper'},
            onSelectionChanged: (s) => state.updateConfig({'trading_mode': s.first}),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Risk limits', subtitle: 'Hard guards for every entry'),
          _sliderCard(
            context,
            title: 'Min confidence',
            value: (cfg['min_confidence'] as num?)?.toDouble() ?? 0.75,
            min: 0.5,
            max: 0.95,
            label: Fmt.confidence((cfg['min_confidence'] as num?)?.toDouble() ?? 0.75),
            onChanged: (v) => state.updateConfig({'min_confidence': double.parse(v.toStringAsFixed(2))}),
          ),
          _sliderCard(
            context,
            title: 'Position size % of equity',
            value: (cfg['position_size_pct'] as num?)?.toDouble() ?? 5,
            min: 1,
            max: 25,
            divisions: 24,
            label: '${((cfg['position_size_pct'] as num?)?.toDouble() ?? 5).round()}%',
            onChanged: (v) => state.updateConfig({'position_size_pct': v.roundToDouble()}),
          ),
          _sliderCard(
            context,
            title: 'Max \$ per position (cap)',
            value: (cfg['max_position_dollars'] as num?)?.toDouble() ?? 500,
            min: 50,
            max: 5000,
            divisions: 99,
            label: Fmt.money((cfg['max_position_dollars'] as num?)?.toDouble() ?? 500),
            onChanged: (v) => state.updateConfig({'max_position_dollars': v.roundToDouble()}),
          ),
          _sliderCard(
            context,
            title: 'Max open positions',
            value: ((cfg['max_open_positions'] as num?)?.toDouble() ?? 8),
            min: 1,
            max: 20,
            divisions: 19,
            label: '${cfg['max_open_positions'] ?? 8}',
            onChanged: (v) => state.updateConfig({'max_open_positions': v.round()}),
          ),
          _sliderCard(
            context,
            title: 'Max entries / day',
            value: ((cfg['max_trades_per_day'] as num?)?.toDouble() ?? 15),
            min: 1,
            max: 40,
            divisions: 39,
            label: '${cfg['max_trades_per_day'] ?? 15}',
            onChanged: (v) => state.updateConfig({'max_trades_per_day': v.round()}),
          ),
          _sliderCard(
            context,
            title: 'Daily loss limit',
            value: (cfg['daily_loss_limit'] as num?)?.toDouble() ?? 200,
            min: 25,
            max: 1000,
            divisions: 39,
            label: Fmt.money((cfg['daily_loss_limit'] as num?)?.toDouble() ?? 200),
            onChanged: (v) => state.updateConfig({'daily_loss_limit': v.roundToDouble()}),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Today', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                'Entries ${daily['entries'] ?? daily['trades'] ?? 0}'
                '/${daily['max_entries'] ?? cfg['max_trades_per_day'] ?? 15}'
                '  ·  Realized ${Fmt.signedMoney(daily['realized_pnl'] as num?)}',
              ),
            ),
          ),
          if (state.performance?['stats'] != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Performance', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Win rate ${(state.performance!['stats'] as Map)['win_rate_pct']}%'
                  '  ·  Buys ${(state.performance!['stats'] as Map)['buys']}'
                  '  ·  Sells ${(state.performance!['stats'] as Map)['sells']}',
                ),
              ),
            ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Strategies', subtitle: 'Toggle detectors independently'),
          ..._strategyLabels.entries.map((e) {
            final on = strategies[e.key] != false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  value: on,
                  onChanged: (v) => state.updateConfig({
                    'strategies': {e.key: v},
                  }),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: state.loading
                ? null
                : () async {
                    await state.runBotCycle();
                    if (context.mounted && state.lastCycleMessage != null) {
                      final n = (state.lastCycle?['entries'] as List?)?.length ?? 0;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(state.lastCycleMessage!),
                          backgroundColor: n > 0 ? AppTheme.profit : null,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Run bot cycle now'),
          ),
          if (state.lastCycleMessage != null) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(
                  ((state.lastCycle?['entries'] as List?)?.isNotEmpty ?? false)
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: ((state.lastCycle?['entries'] as List?)?.isNotEmpty ?? false)
                      ? AppTheme.profit
                      : AppTheme.warning,
                ),
                title: const Text('Last bot cycle', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(state.lastCycleMessage!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const SectionHeader(
            title: 'Entry style',
            subtitle: 'Setup = near breakout (paper-friendly). Confirmed = full breakout only.',
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'setup', label: Text('Setup'), icon: Icon(Icons.flash_on, size: 16)),
              ButtonSegment(value: 'confirmed', label: Text('Confirmed'), icon: Icon(Icons.verified, size: 16)),
            ],
            selected: {
              (cfg['entry_style']?.toString() == 'confirmed') ? 'confirmed' : 'setup',
            },
            onSelectionChanged: (s) => state.updateConfig({'entry_style': s.first}),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Pending approvals',
            subtitle: pending.isEmpty ? 'Queue is empty' : '${pending.length} waiting',
          ),
          if (pending.isEmpty)
            const EmptyStateCard(
              icon: Icons.fact_check_outlined,
              title: 'No pending approvals',
              body: 'Switch to Approvals mode and run a cycle to queue signals for review.',
            )
          else
            ...pending.map((a) {
              final conf = ((a['confidence'] as num?)?.toDouble() ?? 0);
              final confPct = conf <= 1 ? conf : conf / 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${a['ticker']}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const Spacer(),
                            StatusPill(
                              label: Fmt.confidence(confPct),
                              color: AppTheme.seedDeep,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${a['pattern']} · \$${a['dollar_amount']}'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => state.resolveApproval(a['id'].toString(), false),
                                icon: const Icon(Icons.close, color: AppTheme.loss),
                                label: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => state.resolveApproval(a['id'].toString(), true),
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
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
      ),
    );
  }
}
