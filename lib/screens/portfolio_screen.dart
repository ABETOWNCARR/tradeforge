import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  String _money(num? v) => NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(v ?? 0);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.portfolio;
    final positions = Map<String, dynamic>.from(p?['positions'] as Map? ?? {});
    final equity = (p?['equity'] as num?)?.toDouble() ?? 0;
    final cash = (p?['cash'] as num?)?.toDouble() ?? 0;
    final pnl = (p?['total_pnl'] as num?)?.toDouble() ?? 0;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Paper portfolio',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Equity', _money(equity)),
                  _row('Cash', _money(cash)),
                  _row('Total P&L', _money(pnl),
                      color: pnl >= 0 ? AppTheme.profit : AppTheme.loss),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset paper account?'),
                      content: const Text('This clears positions and restores \$10,000 cash.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                      ],
                    ),
                  );
                  if (ok == true) await state.resetPaper();
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Open positions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (positions.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.inbox_outlined),
                title: Text('No open positions'),
                subtitle: Text('Run a scan or bot cycle to open paper trades.'),
              ),
            )
          else
            ...positions.entries.map((e) {
              final pos = Map<String, dynamic>.from(e.value as Map);
              final upnl = (pos['unrealized_pnl'] as num?)?.toDouble() ?? 0;
              return Card(
                child: ListTile(
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Qty ${(pos['qty'] as num?)?.toStringAsFixed(4)} @ ${_money(pos['avg_price'] as num?)}\n'
                    'Stop ${pos['stop_level'] ?? '—'} · Target ${pos['target_level'] ?? '—'}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_money(pos['market_value'] as num?),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${upnl >= 0 ? '+' : ''}${_money(upnl)}',
                        style: TextStyle(
                            color: upnl >= 0 ? AppTheme.profit : AppTheme.loss, fontSize: 12),
                      ),
                    ],
                  ),
                  onLongPress: () async {
                    await state.paperTrade(ticker: e.key, side: 'sell', reason: 'Manual close');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Closed ${e.key}')),
                      );
                    }
                  },
                ),
              );
            }),
          const SizedBox(height: 16),
          Text('Trade journal',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (state.journal.isEmpty)
            const Card(child: ListTile(title: Text('No trades yet')))
          else
            ...state.journal.take(30).map((t) {
              final buy = t['side'] == 'buy';
              final realized = t['realized_pnl'];
              return Card(
                child: ListTile(
                  leading: Icon(buy ? Icons.south_west : Icons.north_east,
                      color: buy ? AppTheme.profit : AppTheme.loss),
                  title: Text('${(t['side'] as String?)?.toUpperCase()} ${t['ticker']}'),
                  subtitle: Text(
                      '${t['reason'] ?? ''}\n${t['timestamp'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  trailing: Text(_money(t['notional'] as num?),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  dense: true,
                  onTap: realized != null
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Realized P&L: ${_money(realized as num)}')),
                          );
                        }
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
