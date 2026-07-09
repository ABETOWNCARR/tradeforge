import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/ui_bits.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.portfolio;
    final positions = Map<String, dynamic>.from(p?['positions'] as Map? ?? {});
    final equity = (p?['equity'] as num?)?.toDouble() ?? 0;
    final cash = (p?['cash'] as num?)?.toDouble() ?? 0;
    final pnl = (p?['total_pnl'] as num?)?.toDouble() ?? 0;
    final pnlPct = (p?['total_pnl_pct'] as num?)?.toDouble() ?? 0;
    final posValue = (p?['positions_value'] as num?)?.toDouble() ?? 0;

    return LoadingOverlay(
      loading: state.loading,
      message: 'Updating…',
      child: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Text(
              'Portfolio',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Virtual paper account',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _kv('Equity', Fmt.money(equity), bold: true),
                    const Divider(height: 20),
                    _kv('Cash', Fmt.money(cash)),
                    const SizedBox(height: 10),
                    _kv('Positions value', Fmt.money(posValue)),
                    const SizedBox(height: 10),
                    _kv(
                      'Total P&L',
                      '${Fmt.signedMoney(pnl)} (${Fmt.pct(pnlPct, signed: true)})',
                      color: pnl >= 0 ? AppTheme.profit : AppTheme.loss,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset paper account?'),
                    content: const Text(
                      'This clears all positions and restores \$10,000 cash. Trade journal will be wiped.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.loss),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await state.resetPaper();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Paper account reset to \$10,000')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset to \$10,000'),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Open positions',
              subtitle: positions.isEmpty
                  ? 'No holdings yet'
                  : '${positions.length} position${positions.length == 1 ? '' : 's'}',
            ),
            if (positions.isEmpty)
              const EmptyStateCard(
                icon: Icons.inbox_outlined,
                title: 'No open positions',
                body: 'Buy from Scanner or run the bot to open paper trades. Long-press a position to close it.',
              )
            else
              ...positions.entries.map((e) {
                final pos = Map<String, dynamic>.from(e.value as Map);
                final upnl = (pos['unrealized_pnl'] as num?)?.toDouble() ?? 0;
                final upnlPct = (pos['unrealized_pnl_pct'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onLongPress: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Close ${e.key}?'),
                            content: const Text('Sell the full paper position at market.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await state.paperTrade(ticker: e.key, side: 'sell', reason: 'Manual close');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Closed ${e.key}')),
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                                const Spacer(),
                                Text(
                                  Fmt.signedMoney(upnl),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: upnl >= 0 ? AppTheme.profit : AppTheme.loss,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty ${(pos['qty'] as num?)?.toStringAsFixed(4)} @ ${Fmt.money(pos['avg_price'] as num?)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                StatusPill(
                                  label: Fmt.pct(upnlPct, signed: true),
                                  color: upnl >= 0 ? AppTheme.profit : AppTheme.loss,
                                  dense: true,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'SL ${pos['stop_level'] ?? '—'}  ·  TP ${pos['target_level'] ?? '—'}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  Fmt.money(pos['market_value'] as num?),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Long-press to close',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            SectionHeader(
              title: 'Trade journal',
              subtitle: state.journal.isEmpty ? 'No trades yet' : '${state.journal.length} recent',
            ),
            if (state.journal.isEmpty)
              const EmptyStateCard(
                icon: Icons.receipt_long_outlined,
                title: 'Journal is empty',
                body: 'Paper buys and sells will show here with reasons and timestamps.',
              )
            else
              ...state.journal.take(30).map((t) {
                final buy = t['side'] == 'buy';
                final color = buy ? AppTheme.profit : AppTheme.loss;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          buy ? Icons.south_west_rounded : Icons.north_east_rounded,
                          color: color,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '${(t['side'] as String?)?.toUpperCase()} ${t['ticker']}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${t['reason'] ?? '—'}\n${Fmt.shortIso(t['timestamp']?.toString())}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        Fmt.money(t['notional'] as num?),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            color: color,
            fontSize: bold ? 18 : 15,
          ),
        ),
      ],
    );
  }
}
