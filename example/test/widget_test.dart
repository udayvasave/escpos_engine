import 'package:flutter_test/flutter_test.dart';
import 'package:escpos_engine_example/main.dart';

void main() {
  testWidgets('shows transport test UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.textContaining('escpos_engine'), findsOneWidget);
    expect(find.text('BLE'), findsOneWidget);
  });
}
