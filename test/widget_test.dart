import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/features/onboarding/onboarding_screen.dart';
import 'package:abelnotes/main.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: HandWriterApp()),
    );
    await tester.pump();

    // First run shows the onboarding screen. Assert on the widget type, not
    // on button copy — the strings are localized now and the test
    // environment's locale (en) diverges from the Italian literals this
    // test previously hardcoded.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('AbelNotes'), findsOneWidget);
  });
}
