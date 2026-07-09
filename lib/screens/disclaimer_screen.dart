import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Icon(Icons.shield_moon_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text('Before you continue',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('TradeForge is educational software. Read carefully.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '• Not financial, investment, or tax advice.\n\n'
                      '• Paper trading uses virtual money. Results do not predict live performance.\n\n'
                      '• Chart patterns and confidence scores are heuristic signals, not guarantees.\n\n'
                      '• All trading involves risk of loss, including loss of principal.\n\n'
                      '• You are solely responsible for any real-money decisions made outside paper mode.\n\n'
                      '• Past pattern performance does not guarantee future results.\n\n'
                      '• By continuing you agree to the in-app Privacy Policy and acknowledge these risks.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _checked,
                onChanged: (v) => setState(() => _checked = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I understand this is educational / paper-first software'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checked ? widget.onAccept : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('I Agree — Continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
