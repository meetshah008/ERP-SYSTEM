import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erp_frontend/features/04_hr_module/employee_edit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Future<void> openCompanyTab(
    WidgetTester tester,
    Map<String, dynamic> employee,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: EmployeeEditScreen(
        employeeId: 1,
        initialData: {'employee': employee},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Company Details'));
    await tester.pumpAndSettle();
  }

  const baseEmployee = <String, dynamic>{
    'full_name': 'Test User',
    'emp_code': 'EMP001',
    'designation': 'Staff',
    'role_name': 'Employee',
    'status': 'active',
    'employment_type': 'Permanent',
    'weekly_off': 'Sunday',
    'salary_grade': 'Grade A',
    'department_id': 1,
    'salary_base': '35000',
  };

  testWidgets('Company Details tab opens for a legacy Admin role', (tester) async {
    await openCompanyTab(tester, {
      ...baseEmployee,
      'role_name': 'Admin',
    });

    expect(find.text('Workplace & Department Assignment'), findsOneWidget);
  });

  testWidgets('Company Details tab tolerates unknown stored dropdown values',
      (tester) async {
    await openCompanyTab(tester, {
      ...baseEmployee,
      'role_name': 'Supervisor',
      'employment_type': 'Contractual',
      'weekly_off': 'Fri',
      'status': 'Inactive',
      'salary_grade': 'Grade D',
      'department_id': '7',
    });

    expect(find.text('Workplace & Department Assignment'), findsOneWidget);
  });
}
