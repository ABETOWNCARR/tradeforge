import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/ui_bits.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  double _minConf = 0.5;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.scanResults.entries.toList()
      ..sort((a, b) => _bestConf(b.value).compareTo(_bestConf(a.value)));

    return LoadingOverlay(
      loading: state.loading,
      message: 'Scanning market…',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pattern scanner',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: state.loading ? null : () => state.runScan(minConfidence: _minConf),
                      icon: const Icon(Icons.radar, size: 18),
                      label: const Text('Scan'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  state.lastScan != null
                      ? '${state.tickersScanned ?? 0} tickers · ${Fmt.timeAgo(state.lastScan)}'
                      : 'Scan equities for chart setups ranked by confidence',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Min confidence', style: TextStyle(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            StatusPill(
                              label: '${(_minConf * 100).round()}%',
                              color: AppTheme.seedDeep,
                              dense: true,
                            ),
                          ],
                        ),
                        Slider(
                          value: _minConf,
                          min: 0.4,
                          max: 0.9,
                          divisions: 10,
                          label: '${(_minConf * 100).round()}%',
                          onChanged: (v) => setState(() => _minConf = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entries.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      EmptyStateCard(
                        icon: Icons.query_stats_rounded,
                        title: state.loading ? 'Scanning…' : 'Ready to scan',
                        body: state.loading
                            ? 'Fetching market data and running pattern detectors.'
                            : 'Tap Scan to detect bull flags, triangles, RSI bounces, and more.',
                        action: state.loading
                            ? null
                            : FilledButton.tonalIcon(
                                onPressed: () => state.runScan(minConfidence: _minConf),
                                icon: const Icon(Icons.radar),
                                label: const Text('Start scan'),
                              ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final ticker = entries[i].key;
                      final patterns = (entries[i].value as List)
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList();
                      final best = patterns.first;
                      final conf = ((best['confidence'] as num?)?.toDouble() ?? 0);
                      final confPct = conf <= 1 ? conf : conf / 100;
                      final bullish = best['signal']?.toString() == 'bullish';
                      final color = bullish ? AppTheme.profit : AppTheme.loss;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            leading: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                ticker.length > 4 ? ticker.substring(0, 4) : ticker,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            title: Text(ticker, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${best['pattern']} · ${best['signal']}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  Fmt.confidence(confPct),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: confPct >= 0.8 ? AppTheme.profit : AppTheme.warning,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 48,
                                  child: ConfidenceBar(value: confPct, height: 4),
                                ),
                              ],
                            ),
                            children: [
                              ...patterns.map((p) {
                                final c = ((p['confidence'] as num?)?.toDouble() ?? 0);
                                final cp = c <= 1 ? c : c / 100;
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${p['pattern']} · ${Fmt.confidence(cp)}',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Px ${p['price']}  ·  BO ${p['breakout_level']}  ·  SL ${p['stop_level']}  ·  TP ${p['target_level']}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: () async {
                                    await state.paperTrade(
                                      ticker: ticker,
                                      side: 'buy',
                                      dollars: 250,
                                      reason: 'Manual from scanner: ${best['pattern']}',
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Paper bought $ticker (\$250)'),
                                          backgroundColor: AppTheme.profit,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.add_shopping_cart_outlined),
                                  label: const Text('Paper buy \$250'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  double _bestConf(dynamic value) {
    if (value is! List || value.isEmpty) return 0;
    final first = value.first;
    if (first is Map && first['confidence'] is num) {
      return (first['confidence'] as num).toDouble();
    }
    return 0;
  }
}
