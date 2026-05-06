import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutritrack/screens/login_screen.dart';

void main() {
  testWidgets('Login screen has email and password fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    // Two TextFormFields: Email + Password
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Login button
    expect(find.text('Login'), findsOneWidget);

    // Sign up text (partial match)
    expect(find.textContaining('Sign up'), findsOneWidget);
  });

  testWidgets('Login button is tappable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.text('Login'));
    await tester.pump();

    // No crash = pass
    expect(true, isTrue);
  });
}
