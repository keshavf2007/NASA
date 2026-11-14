import 'package:flutter_test/flutter_test.dart';

import 'package:field_shift/main.dart';

void main() {
  testWidgets('requires a live NASA gateway before showing the dashboard', (tester) async {
    await tester.pumpWidget(const FieldShiftApp());
    await tester.pumpAndSettle();
    expect(find.text('NASA LIVE DATA REQUIRED'), findsOneWidget);
  });
}
