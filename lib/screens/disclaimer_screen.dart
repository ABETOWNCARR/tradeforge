import 'package:flutter/material.dart';

import '../widgets/ui_bits.dart';

class DisclaimerScreen extends StatefulWidget {
  final VoidCallback onAccept;
  const DisclaimerScreen({super.key, required this.onAccept});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 48),
              const SizedBox(height: 18),
              Text(
                'Before you continue',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'TradeForge is educational, paper-first software. Please read this carefully.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _point(context, 'Not financial, investment, or tax advice.'),
                        _point(context, 'Paper trading uses virtual money. Results do not predict live performance.'),
                        _point(context, 'Chart patterns and confidence scores are heuristics, not guarantees.'),
                        _point(context, 'All trading involves risk of loss, including loss of principal.'),
                        _point(context, 'You are solely responsible for any real-money decisions outside paper mode.'),
                        _point(context, 'By continuing you acknowledge these risks and the Privacy Policy.'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                child: CheckboxListTile(
                  value: _checked,
                  onChanged: (v) => setState(() => _checked = v ?? false),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I understand this is educational / paper-first software',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checked ? widget.onAccept : null,
                  child: const Text('I Agree — Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
