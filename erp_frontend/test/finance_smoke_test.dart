import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erp_frontend/features/06_finance/finance_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'jwt_token': 'test-token',
      'is_logged_in': true,
      'user_role': 'Super Admin',
      'company_id': 1,
      'user_permissions': '{}',
    });
  });

  testWidgets('finance screen builds without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: SizedBox(
            height: 600,
            child: Builder(builder: (_) => const FinanceScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Accounts & Finance'), findsOneWidget);
  });
}
