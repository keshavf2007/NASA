import 'package:flutter_test/flutter_test.dart';

import 'package:field_shift/main.dart';

void main() {
  testWidgets('requires a live NASA gateway before showing the dashboard', (tester) async {
    await tester.pumpWidget(const FieldShiftApp());
    await tester.pumpAndSettle();
    expect(find.text('NASA LIVE DATA REQUIRED'), findsOneWidget);
  });

  testWidgets('field form opens below MaterialApp without localization errors', (tester) async {
    await tester.pumpWidget(const FieldShiftApp(loadLiveOnStart: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adaptations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tell us about your field').first);
    await tester.pumpAndSettle();

    expect(find.text('Analyze my field'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
