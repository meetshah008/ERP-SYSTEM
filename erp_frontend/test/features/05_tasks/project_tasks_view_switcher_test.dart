import 'package:erp_frontend/features/05_tasks/project_tasks_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowDesktopViewSwitcher', () {
    test('Admin and Super Admin keep the Projects / General Tasks tabs', () {
      expect(shouldShowDesktopViewSwitcher('Super Admin'), isTrue);
      expect(shouldShowDesktopViewSwitcher('admin'), isTrue);
      expect(shouldShowDesktopViewSwitcher(' Admin '), isTrue);
    });

    test('Managers and Employees use the sidebar instead', () {
      expect(shouldShowDesktopViewSwitcher('Module Manager'), isFalse);
      expect(shouldShowDesktopViewSwitcher('Project Module Manager'), isFalse);
      expect(shouldShowDesktopViewSwitcher('Employee'), isFalse);
    });
  });

  group('buildTaskQueryParams', () {
    test('Projects module manager gets an unscoped all-tasks request', () {
      expect(
        buildTaskQueryParams(
          role: 'Module Manager',
          permissions: const {'tasks_view': true},
          employeeId: 7,
          userId: 12,
        ),
        isEmpty,
      );
      expect(
        buildTaskQueryParams(
          role: 'Project Module Manager',
          permissions: const {},
          employeeId: 7,
          userId: 12,
        ),
        isEmpty,
      );
    });

    test('Employee stays scoped to their own tasks', () {
      expect(
        buildTaskQueryParams(
          role: 'Employee',
          permissions: const {},
          employeeId: 7,
          userId: 12,
        ),
        equals(['employee_id=7', 'user_id=12', 'role=Employee']),
      );
    });

    test('Super Admin keeps the role-only request', () {
      expect(
        buildTaskQueryParams(
          role: 'Super Admin',
          permissions: const {},
          employeeId: 7,
          userId: 12,
        ),
        equals(['role=Super Admin']),
      );
    });
  });
}
