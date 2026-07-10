import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/ui_bits.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
    final blockedReason = state.risk?['blocked_reason']?.toString();
    final daily = state.risk?['daily'] as Map<String, dynamic>?;
    final entriesUsed = (daily?['entries'] as num?)?.toInt() ??
        (daily?['trades'] as num?)?.toInt() ??
        0;
    final entriesMax = (daily?['max_entries'] as num?)?.toInt() ??
        (cfg?['max_trades_per_day'] as num?)?.toInt() ??
        15;

    String statusLabel;
    Color statusColor;
    if (kill) {
      statusLabel = 'Kill switch';
      statusColor = AppTheme.loss;
    } else if (paused) {
      statusLabel = 'Paused';
      statusColor = AppTheme.warning;
    } else if (canTrade) {
      statusLabel = 'Armed';
      statusColor = AppTheme.profit;
    } else {
      statusLabel = 'Blocked';
      statusColor = AppTheme.warning;
    }

    return LoadingOverlay(
      loading: state.loading,
      message: 'Working…',
      child: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Row(
              children: [
                const BrandMark(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TradeForge',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                      ),
                      Text(
                        'Paper portfolio',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(
                      label: state.marketOpen ? 'Market open' : 'Market closed',
                      color: state.marketOpen ? AppTheme.profit : Colors.blueGrey,
                      icon: state.marketOpen ? Icons.circle : Icons.nightlight_round,
                      dense: true,
                    ),
                    const SizedBox(height: 6),
                    StatusPill(
                      label: state.broker?['label']?.toString() ?? 'Sim paper',
                      color: state.broker?['is_live'] == true ? AppTheme.loss : AppTheme.seedDeep,
                      icon: Icons.account_balance_outlined,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EquityHero(
              equity: equity,
              pnl: pnl,
              pnlPct: pnlPct,
              pnlColor: pnlColor,
              brokerLabel: state.broker?['label']?.toString(),
            ),
            if (blockedReason != null || !canTrade) ...[
              const SizedBox(height: 10),
              Card(
                color: AppTheme.warning.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline, color: AppTheme.warning),
                  title: const Text('Bot not opening new trades',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    blockedReason ??
                        'Daily entries $entriesUsed/$entriesMax used, or all candidates already open. '
                            'Exits still run every 5 min. Raise the limit on the Bot tab if you want more entries today.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Today entries',
                    value: '$entriesUsed / $entriesMax',
                    icon: Icons.today_outlined,
                    valueColor: entriesUsed >= entriesMax ? AppTheme.warning : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Cash',
                    value: Fmt.money(cash),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Positions',
                    value: '$posCount open',
                    icon: Icons.pie_chart_outline_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Bot mode',
                    value: mode == 'approval' ? 'Approvals' : 'Auto paper',
                    icon: Icons.smart_toy_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StatTile(
              label: 'Status',
              value: statusLabel,
              valueColor: statusColor,
              icon: Icons.shield_outlined,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.onErrorContainer),
                  title: Text(
                    'Connection issue',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  subtitle: Text(
                    'Pull to refresh. ${state.error}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SectionHeader(
              title: 'High-confidence signals',
              subtitle: state.lastScan != null
                  ? 'Updated ${Fmt.timeAgo(state.lastScan)}'
                  : 'Run a scan to populate this list',
              trailing: TextButton(
                onPressed: state.loading ? null : () => state.runScan(),
                child: const Text('Scan'),
              ),
            ),
            if (state.alerts.isEmpty)
              EmptyStateCard(
                icon: Icons.radar,
                title: 'No signals yet',
                body: 'Scan the market for chart patterns with 75%+ confidence.',
                action: FilledButton.tonalIcon(
                  onPressed: state.loading ? null : () => state.runScan(),
                  icon: const Icon(Icons.radar),
                  label: const Text('Scan now'),
                ),
              )
            else
              ...state.alerts.take(8).map((a) => _SignalCard(alert: a)),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Quick actions',
              subtitle: 'Safe controls for paper trading',
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.loading
                        ? null
                        : () async {
                            await state.runBotCycle();
                            if (context.mounted && state.lastCycleMessage != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(state.lastCycleMessage!),
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run bot'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => state.setKillSwitch(!kill),
                    icon: Icon(kill ? Icons.play_circle_outline : Icons.stop_circle_outlined),
                    label: Text(kill ? 'Resume' : 'Kill switch'),
                    style: kill
                        ? OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.loss,
                            side: const BorderSide(color: AppTheme.loss),
                          )
                        : null,
                  ),
                ),
              ],
            ),
            if (state.lastCycleMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last cycle: ${state.lastCycleMessage}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EquityHero extends StatelessWidget {
  final double equity;
  final double pnl;
  final double pnlPct;
  final Color pnlColor;
  final String? brokerLabel;

  const _EquityHero({
    required this.equity,
    required this.pnl,
    required this.pnlPct,
    required this.pnlColor,
    this.brokerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badge = (brokerLabel ?? 'PAPER').toUpperCase().contains('LIVE') ? 'LIVE' : 'PAPER';
    final live = badge == 'LIVE';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? const [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFDC2626)]
              : isDark
                  ? const [Color(0xFF134E4A), Color(0xFF0F766E), Color(0xFF115E59)]
                  : const [Color(0xFF0F766E), Color(0xFF14B8A6), Color(0xFF2DD4BF)],
        ),
        boxShadow: [
          BoxShadow(
            color: (live ? AppTheme.loss : AppTheme.seed).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Equity',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Fmt.money(equity),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${Fmt.signedMoney(pnl)}  (${Fmt.pct(pnlPct, signed: true)})',
              style: TextStyle(
                color: pnl >= 0 ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _SignalCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final conf = ((alert['confidence'] as num?)?.toDouble() ?? 0);
    final confPct = conf <= 1 ? conf : conf / 100;
    final bullish = alert['signal']?.toString() == 'bullish';
    final color = bullish ? AppTheme.profit : AppTheme.loss;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      bullish ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${alert['ticker']}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          '${alert['pattern']}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: Fmt.confidence(confPct),
                    color: confPct >= 0.8 ? AppTheme.profit : AppTheme.warning,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConfidenceBar(value: confPct),
              const SizedBox(height: 10),
              Row(
                children: [
                  _mini('Stop', '${alert['stop_level'] ?? '—'}'),
                  _mini('Target', '${alert['target_level'] ?? '—'}'),
                  _mini('Signal', '${alert['signal'] ?? '—'}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(String k, String v) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
          Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
