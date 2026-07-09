import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

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
      ..sort((a, b) {
        final ac = _bestConf(a.value);
        final bc = _bestConf(b.value);
        return bc.compareTo(ac);
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Pattern scanner',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  FilledButton.icon(
                    onPressed: state.loading ? null : () => state.runScan(minConfidence: _minConf),
                    icon: state.loading
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.radar),
                    label: const Text('Scan'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Min confidence: ${(_minConf * 100).round()}%'),
              Slider(
                value: _minConf,
                min: 0.4,
                max: 0.9,
                divisions: 10,
                label: '${(_minConf * 100).round()}%',
                onChanged: (v) => setState(() => _minConf = v),
              ),
              if (state.lastScan != null)
                Text(
                  'Last scan: ${state.lastScan} · ${state.tickersScanned ?? 0} tickers',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    state.loading ? 'Scanning market…' : 'Tap Scan to detect patterns',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final ticker = entries[i].key;
                    final patterns = (entries[i].value as List)
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    final best = patterns.first;
                    final conf = ((best['confidence'] as num?)?.toDouble() ?? 0) * 100;
                    final bullish = best['signal']?.toString() == 'bullish';
                    return Card(
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              (bullish ? AppTheme.profit : AppTheme.loss).withValues(alpha: 0.15),
                          child: Text(ticker.substring(0, ticker.length.clamp(0, 2)),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: bullish ? AppTheme.profit : AppTheme.loss,
                                  fontSize: 11)),
                        ),
                        title: Text(ticker, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${best['pattern']} · ${best['signal']}'),
                        trailing: Text('${conf.round()}%',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: conf >= 80 ? AppTheme.profit : AppTheme.warning)),
                        children: [
                          ...patterns.map((p) => ListTile(
                                dense: true,
                                title: Text('${p['pattern']} (${((p['confidence'] as num?)?.toDouble() ?? 0) * 100}%)'),
                                subtitle: Text(
                                    'Px ${p['price']} · BO ${p['breakout_level']} · SL ${p['stop_level']} · TP ${p['target_level']}'),
                              )),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: () async {
                                      await state.paperTrade(
                                        ticker: ticker,
                                        side: 'buy',
                                        dollars: 250,
                                        reason: 'Manual from scanner: ${best['pattern']}',
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Paper bought $ticker (\$250)')),
                                        );
                                      }
                                    },
                                    child: const Text('Paper buy \$250'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
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
