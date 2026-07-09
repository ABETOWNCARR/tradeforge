import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tradeforge/main.dart';
import 'package:tradeforge/services/app_state.dart';

void main() {
  testWidgets('TradeForge app builds', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const TradeForgeApp(),
      ),
    );
    await tester.pump();
    // Disclaimer is first gate
    expect(find.textContaining('Before you continue'), findsOneWidget);
  });
}
