import 'package:flutter_test/flutter_test.dart';
import 'package:bismark_app/main.dart';

void main() {
  testWidgets('App startet', (tester) async {
    await tester.pumpWidget(const BismarkApp());
    expect(find.text('Bismark Wasser'), findsOneWidget);
  });
}
