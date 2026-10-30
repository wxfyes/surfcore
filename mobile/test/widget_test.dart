import 'package:flutter_test/flutter_test.dart';
import 'package:surfcore_mobile/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SurfCoreApp());
    expect(find.text('SurfCore 伴侣'), findsNothing); // title in MaterialApp
  });
}
