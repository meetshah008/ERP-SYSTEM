import 'package:erp_frontend/features/03_dashboard/admin_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dashboard scope query params', () {
    List<String> paramsFor(String role, [Map<String, bool> permissions = const {}]) {
      return buildDashboardScopeQueryParams(
        role: role,
        permissions: permissions,
        employeeId: 7,
        userId: 3,
      );
    }

    test('dashboard overview never narrows counts by role or employee', () {
      expect(paramsFor('Super Admin'), isEmpty);
      expect(paramsFor('Admin'), isEmpty);
      expect(paramsFor('ADMIN'), isEmpty);
      expect(paramsFor('Employee'), isEmpty);
      expect(paramsFor('Module Manager', {
        'tasks_view': false,
        'hr_view_directory': true,
      }), isEmpty);
    });

    test('projects module manager also gets the company-wide overview', () {
      expect(paramsFor('Projects Module Manager'), isEmpty);
      expect(
        paramsFor('Module Manager', {
          'tasks_view': true,
          'hr_view_directory': false,
        }),
        isEmpty,
      );
    });
  });

  group('dashboard counter helpers', () {
    test('only finished tasks are excluded from pending count', () {
      final tasks = <dynamic>[
        {'status': 'TODO'},
        {'status': 'IN_PROGRESS'},
        {'status': 'REVIEW'},
        {'status': 'DONE'},
        {'status': 'Completed'},
      ];

      expect(countPendingTasks(tasks), 3);
    });

    test('active projects count as pending, completed ones do not', () {
      final projects = <dynamic>[
        {'status': 'Active'},
        {'status': 'Planning'},
        {'status': 'Completed'},
      ];

      expect(countPendingProjects(projects), 2);
      expect(countCompletedProjects(projects), 1);
    });
  });

  group('settings identity labels', () {
    test('blank, null, literal null and raw ids never leak into the UI', () {
      expect(niceNameLabel(null), 'Employee');
      expect(niceNameLabel('  '), 'Employee');
      expect(niceNameLabel('null'), 'Employee');
      expect(niceNameLabel('7'), 'Employee');
    });

    test('designation wins over the generic role name', () {
      expect(
        designationLabel({
          'designation': 'Senior Flutter Developer',
          'role_name': 'Employee',
        }),
        'Senior Flutter Developer',
      );
    });

    test('role name is used when designation is missing', () {
      expect(
        designationLabel({
          'designation': null,
          'role_name': 'Module Manager',
        }),
        'Module Manager',
      );
      expect(designationLabel({}, 'Super Admin'), 'Super Admin');
    });

    test('current employee is matched by id, user id or email', () {
      final rows = <dynamic>[
        {
          'employee_id': '12',
          'user_id': 4,
          'email': 'admin@erp.com',
          'designation': 'System Administrator',
        },
      ];

      expect(
        currentEmployeeFrom(rows, employeeId: 12)?['designation'],
        'System Administrator',
      );
      expect(currentEmployeeFrom(rows, userId: 4), isNotNull);
      expect(currentEmployeeFrom(rows, email: 'ADMIN@ERP.COM'), isNotNull);
    });
  });
}
