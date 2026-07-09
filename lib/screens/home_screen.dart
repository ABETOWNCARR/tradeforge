import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _money(num? v) {
    final f = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return f.format(v ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.portfolio;
    final equity = (p?['equity'] as num?)?.toDouble() ?? 10000;
    final pnl = (p?['total_pnl'] as num?)?.toDouble() ?? 0;
    final pnlPct = (p?['total_pnl_pct'] as num?)?.toDouble() ?? 0;
    final cash = (p?['cash'] as num?)?.toDouble() ?? 10000;
    final posCount = p?['position_count'] as int? ?? 0;
    final pnlColor = pnl >= 0 ? AppTheme.profit : AppTheme.loss;
    final cfg = state.risk?['config'] as Map<String, dynamic>?;
    final kill = cfg?['kill_switch'] == true;
    final paused = cfg?['is_paused'] == true;
    final mode = cfg?['trading_mode']?.toString() ?? 'paper';
    final canTrade = state.risk?['can_trade_now'] == true;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('TradeForge',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              _Chip(
                label: state.marketOpen ? 'Market open' : 'Market closed',
                color: state.marketOpen ? AppTheme.profit : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Paper portfolio',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Equity', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(_money(equity),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    '${pnl >= 0 ? '+' : ''}${_money(pnl)}  (${pnlPct.toStringAsFixed(2)}%)',
                    style: TextStyle(color: pnlColor, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: StatCard(label: 'Cash', value: _money(cash), icon: Icons.payments_outlined)),
              const SizedBox(width: 10),
              Expanded(
                  child: StatCard(
                      label: 'Positions', value: '$posCount', icon: Icons.pie_chart_outline)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Bot mode',
                  value: mode.toUpperCase(),
                  icon: Icons.smart_toy_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Status',
                  value: kill
                      ? 'KILL SWITCH'
                      : paused
                          ? 'PAUSED'
                          : canTrade
                              ? 'ARMED'
                              : 'IDLE',
                  valueColor: kill
                      ? AppTheme.loss
                      : canTrade
                          ? AppTheme.profit
                          : AppTheme.warning,
                  icon: Icons.shield_outlined,
                ),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.cloud_off),
                title: const Text('Backend unreachable'),
                subtitle: Text(
                  'Start the TradeForge API, then pull to refresh.\n${state.error}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('High-confidence signals',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (state.alerts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.radar, size: 40, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text('No alerts yet — run a scan from the Scanner tab.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: state.loading ? null : () => state.runScan(),
                      child: state.loading
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Scan now'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...state.alerts.take(8).map((a) {
              final conf = ((a['confidence'] as num?)?.toDouble() ?? 0) * 100;
              final bullish = a['signal']?.toString() == 'bullish';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (bullish ? AppTheme.profit : AppTheme.loss).withValues(alpha: 0.15),
                    child: Icon(
                      bullish ? Icons.trending_up : Icons.trending_down,
                      color: bullish ? AppTheme.profit : AppTheme.loss,
                    ),
                  ),
                  title: Text('${a['ticker']} · ${a['pattern']}'),
                  subtitle: Text(
                      '${a['signal']} · stop ${a['stop_level']} · target ${a['target_level']}'),
                  trailing: Text('${conf.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: conf >= 80 ? AppTheme.profit : AppTheme.warning)),
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Quick actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: state.loading ? null : () => state.runBotCycle(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run bot cycle'),
              ),
              OutlinedButton.icon(
                onPressed: () => state.setKillSwitch(!kill),
                icon: Icon(kill ? Icons.play_circle_outline : Icons.stop_circle_outlined),
                label: Text(kill ? 'Disable kill switch' : 'Kill switch'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
