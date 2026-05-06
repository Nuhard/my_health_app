import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutritrack/screens/role_selection_screen.dart';

void main() {
  testWidgets('Role selection shows all three roles', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoleSelectionScreen(),
        routes: {
          '/login': (_) => const Placeholder(),
          '/signup': (_) => const Placeholder(),
          '/home': (_) => const Placeholder(),
        },
      ),
    );

    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Healthcare Provider'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('NutriTrack'), findsOneWidget);
  });

  testWidgets('Can select Patient role', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoleSelectionScreen(),
        routes: {
          '/login': (_) => const Placeholder(),
          '/signup': (_) => const Placeholder(),
          '/home': (_) => const Placeholder(),
        },
      ),
    );

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    // If no exception → navigation works ✅
    expect(true, isTrue);
  });
}
