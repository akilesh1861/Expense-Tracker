import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker_desktop/main.dart';

void main() {
  testWidgets('dashboard renders core sections', (tester) async {
    await tester.pumpWidget(const LuxeBudgetApp());

    expect(find.text('Monthly Snapshot'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
  });
}
