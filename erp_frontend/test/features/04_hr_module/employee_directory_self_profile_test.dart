import 'package:erp_frontend/features/04_hr_module/employee_management_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowOwnEmployeeProfileOnly', () {
    test('Employee with only directory access sees their own profile', () {
      expect(
        shouldShowOwnEmployeeProfileOnly(
          role: 'Employee',
          canManageStaff: false,
          canViewLifecycle: false,
        ),
        isTrue,
      );
    });

    test('HR managers and admins keep the full directory', () {
      expect(
        shouldShowOwnEmployeeProfileOnly(
          role: 'Module Manager',
          canManageStaff: true,
          canViewLifecycle: true,
        ),
        isFalse,
      );
      expect(
        shouldShowOwnEmployeeProfileOnly(
          role: 'Super Admin',
          canManageStaff: false,
          canViewLifecycle: false,
        ),
        isFalse,
      );
    });
  });
}
