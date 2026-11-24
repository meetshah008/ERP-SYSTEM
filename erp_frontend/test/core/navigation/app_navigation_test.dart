import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erp_frontend/core/navigation/app_navigation.dart';
import 'package:erp_frontend/core/widgets/permission_sidebar.dart';
import 'package:erp_frontend/features/05_tasks/project_tasks_screen.dart';

Map<String, bool> _perms(List<String> keys) => {
      for (final key in AppNavCatalog.allItems
          .map((item) => item.permissionKey)
          .whereType<String>())
      key: keys.contains(key),
    };

List<String> labels(List<AppNavGroup> groups) => groups
    .expand((group) => group.items)
    .map((item) => item.label)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppNavResolver', () {
    test('HR manager only sees the pages their permissions unlock', () {
      final groups = AppNavResolver.resolve(
        'Module Manager',
        _perms(const [
          'hr_view_directory',
          'hr_manage_staff',
          'attendance_view_logs',
          'leaves_apply',
          'tasks_create_self',
        ]),
      );

      final visible = labels(groups);
      expect(visible, contains('Dashboard'));
      expect(visible, contains('Employee Directory'));
      expect(visible, contains('Biometric Attendance'));
      expect(visible, contains('Staff Leave Management'));
      // HR managers get their own General Tasks board, but not Projects.
      expect(visible, contains('General Tasks'));

      // Items removed from the sidebar stay hidden even when permitted.
      expect(visible, isNot(contains('Employee Management')));
      expect(visible, isNot(contains('Employee Lifecycle')));
      expect(visible, isNot(contains('Employee Onboarding')));
      expect(visible, isNot(contains('Leave Approvals')));

      // Unrelated and ungranted modules stay hidden.
      expect(visible, isNot(contains('Projects & Tasks')));
      expect(visible, isNot(contains('Department Management')));
      expect(visible, isNot(contains('Payroll & Increments')));
      expect(visible, isNot(contains('Accounts & Finance')));
      // Settings & Logs is a personal workspace item, visible to every role.
      expect(
        groups.map((g) => g.id),
        equals(['general', 'hr', 'projects', 'system']),
      );
    });

    test('revoking a permission removes its item, granting one adds it', () {
      final managerPermissions = _perms(const ['hr_view_directory']);
      final before = labels(AppNavResolver.resolve('Module Manager', managerPermissions));
      expect(before, contains('Employee Directory'));
      expect(before, isNot(contains('Department Management')));

      // TEST 3: revoke
      managerPermissions['hr_view_directory'] = false;
      final revoked = labels(AppNavResolver.resolve('Module Manager', managerPermissions));
      expect(revoked, isNot(contains('Employee Directory')));
      expect(AppNavResolver.canOpen(
              'Module Manager', managerPermissions, 'hr_view_directory'),
          isFalse);

      // TEST 4: grant
      managerPermissions['hr_manage_departments'] = true;
      managerPermissions['salary_manage_increment'] = true;
      final granted = labels(AppNavResolver.resolve('Module Manager', managerPermissions));
      expect(granted, contains('Department Management'));
      expect(granted, contains('Payroll & Increments'));
      expect(AppNavResolver.canOpen(
              'Module Manager', managerPermissions, 'hr_manage_departments'),
          isTrue);
    });

    test('employee sees only employee-authorized items', () {
      final groups = AppNavResolver.resolve(
        'Employee',
        _perms(const [
          'hr_view_directory',
          'leaves_apply',
          'tasks_view',
          'tasks_create_self',
          'tasks_log_timesheet',
        ]),
      );
      final visible = labels(groups);

      expect(visible, containsAll([
        'Dashboard',
        'Employee Directory',
        'Staff Leave Management',
        'Projects & Tasks',
        'Personal Tasks',
        'General Tasks',
      ]));
      expect(visible, isNot(contains('Employee Management')));
      expect(visible, isNot(contains('Employee Lifecycle')));
      expect(visible, isNot(contains('Leave Approvals')));
      expect(visible, isNot(contains('Department Management')));
      expect(visible, contains('Settings & Logs'));
      expect(visible, isNot(contains('Timesheets')));
      expect(visible, isNot(contains('Biometric Attendance')));
      expect(visible, isNot(contains('Attendance Override')));
      expect(visible, isNot(contains('Advanced Biometric Tools')));
    });

    test('projects module manager sees only the project board in the sidebar', () {
      // Both the seeded backend label and an explicit project-manager label
      // are treated the same; the underlying permissions are unchanged.
      for (final role in const ['Module Manager', 'Project Module Manager']) {
        final perms = _perms(const [
          'tasks_view',
          'projects_create',
          'projects_edit',
          'projects_delete',
          'tasks_create_assign',
          'tasks_create_self',
          'tasks_edit',
          'tasks_delete',
          'tasks_log_timesheet',
        ]);
        final visible = labels(AppNavResolver.resolve(role, perms));

        expect(visible, contains('Projects & Tasks'));
        expect(visible, contains('General Tasks'));

        for (final label in const [
          'Create Project',
          'Project Workspace',
          'Project Deletion',
          'Assign Task',
          'Personal Tasks',
          'Task Editing',
          'Task Deletion',
        ]) {
          expect(
            visible,
            isNot(contains(label)),
            reason: '$label should be hidden for $role',
          );
        }
      }

      // Other roles keep the entries when the backend grants the permissions.
      final employeeVisible = labels(
        AppNavResolver.resolve(
          'Employee',
          _perms(const [
            'tasks_view',
            'projects_delete',
            'tasks_delete',
          ]),
        ),
      );
      expect(employeeVisible, contains('Project Deletion'));
      expect(employeeVisible, contains('Task Deletion'));
    });

    test('Super Admin resolver exposes everything (original UI stays in use)', () {
      final groups = AppNavResolver.resolve('Super Admin', const {});
      expect(groups.length, equals(AppNavCatalog.groups.length));
      expect(labels(groups).length, equals(AppNavCatalog.allItems.length));
      expect(AppNavResolver.canOpen('Super Admin', const {}, 'system_audit_logs'),
          isTrue);
    });

    test('catalog uses only real backend keys; requested items stay hidden', () {
      const backendKeys = <String>{
        'hr_view_directory',
        'hr_manage_staff',
        'hr_manage_departments',
        'hr_view_lifecycle',
        'attendance_view_logs',
        'attendance_import_excel',
        'attendance_override',
        'attendance_biometric_manage',
        'leaves_apply',
        'leaves_approve',
        'tasks_view',
        'projects_create',
        'projects_edit',
        'projects_delete',
        'tasks_create_assign',
        'tasks_create_self',
        'tasks_edit',
        'tasks_delete',
        'tasks_log_timesheet',
        'inventory_view_stock',
        'inventory_manage_material',
        'manufacturing_view_bom',
        'manufacturing_work_orders',
        'finance_view_reports',
        'salary_manage_increment',
        'system_audit_logs',
      };
      final mapped = AppNavCatalog.allItems
          .map((item) => item.permissionKey)
          .whereType<String>()
          .toSet();
      // The catalog may only use keys that really exist in the backend.
      expect(mapped.difference(backendKeys), isEmpty);

      // These items were intentionally removed from the sidebar.
      // Their permissions still exist and are still enforced inside screens.
      for (final key in const [
        'attendance_override',
        'attendance_biometric_manage',
        'tasks_log_timesheet',
        'hr_view_lifecycle',
        'leaves_approve',
      ]) {
        expect(mapped, isNot(contains(key)), reason: '$key should be hidden');
      }
      for (final id in const [
        'attendance_override',
        'attendance_biometric_tools',
        'tasks_timesheet',
        'hr_onboarding',
        'hr_lifecycle',
        'leaves_approve',
      ]) {
        expect(AppNavCatalog.itemById(id), isNull, reason: '$id was removed');
      }
    });

    test('General Tasks targets the dashboard tab that opens the board', () {
      final item = AppNavCatalog.itemById('general_tasks');
      expect(item, isNotNull);
      expect(item!.permissionKey, equals('tasks_create_self'));
      expect(item.targetMenu, equals('General Tasks'));
      expect(item.screenBuilder, isNull);
      // The dashboard renders this screen with its General Tasks tab active.
      const screen = ProjectTasksScreen(initialTopView: 1);
      expect(screen.initialTopView, equals(1));
    });

    test('every item opens an existing dashboard tab or an existing screen', () {
      const dashboardMenus = <String>{
        'Dashboard',
        'Projects & Tasks',
        'General Tasks',
        'Inventory & Stock',
        'Manufacturing & BOM',
        'Accounts & Finance',
        'Settings & Logs',
      };
      for (final item in AppNavCatalog.allItems) {
        if (item.targetMenu != null) {
          expect(dashboardMenus, contains(item.targetMenu),
              reason: '${item.id} targets a missing dashboard tab');
        } else {
          expect(item.screenBuilder, isNotNull,
              reason: '${item.id} has no screen builder');
          expect(item.screenBuilder!(), isA<Widget>(),
              reason: '${item.id} did not build a widget');
        }
      }
    });
  });

  group('PermissionSidebar', () {
    Future<void> pumpSidebar(
      WidgetTester tester, {
      required double width,
      required List<AppNavGroup> groups,
      ValueChanged<AppNavItem>? onItemSelected,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 900,
            child: PermissionSidebar(
              groups: groups,
              companyName: 'Apex Technologies',
              role: 'Module Manager',
              userName: 'hr.manager',
              activeNavId: 'dashboard',
              activeMenu: 'Dashboard',
              onItemSelected: onItemSelected ?? (_) {},
              onLogout: () {},
            ),
          ),
        ),
      ));
    }

    testWidgets('renders grouped items on desktop and tablet widths',
        (tester) async {
      final groups = AppNavResolver.resolve(
        'Module Manager',
        _perms(const [
          'hr_view_directory',
          'attendance_view_logs',
          'leaves_apply',
        ]),
      );

      for (final width in [1440.0, 1024.0]) {
        await pumpSidebar(tester, width: width, groups: groups);
        expect(find.text('HR MANAGEMENT'), findsOneWidget);
        expect(find.text('Employee Directory'), findsOneWidget);
        expect(find.text('Biometric Attendance'), findsOneWidget);
        expect(find.text('Staff Leave Management'), findsOneWidget);
        expect(find.text('Leave Approvals'), findsNothing);
        expect(find.text('Projects & Tasks'), findsNothing);
        expect(find.byTooltip('Logout'), findsOneWidget);
      }
    });

    testWidgets('group headers collapse and items report selection', (tester) async {
      final groups = AppNavResolver.resolve(
        'Module Manager',
        _perms(const ['hr_view_directory', 'leaves_apply']),
      );
      AppNavItem? selected;
      await pumpSidebar(
        tester,
        width: 270,
        groups: groups,
        onItemSelected: (item) => selected = item,
      );

      expect(find.text('Employee Directory'), findsOneWidget);
      await tester.tap(find.text('HR MANAGEMENT'));
      await tester.pumpAndSettle();
      expect(find.text('Employee Directory'), findsNothing);

      await tester.tap(find.text('HR MANAGEMENT'));
      await tester.pumpAndSettle();
      expect(find.text('Employee Directory'), findsOneWidget);

      await tester.tap(find.text('Employee Directory'));
      expect(selected?.id, equals('hr_directory'));
    });
  });

  group('PermissionGate', () {
    testWidgets('blocks a restricted page even if pushed directly', (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_role': 'Module Manager',
        'user_permissions': '{"hr_manage_staff": false}',
      });

      await tester.pumpWidget(const MaterialApp(
        home: PermissionGate(
          permissionKey: 'hr_manage_staff',
          moduleTitle: 'Employee Management',
          child: Text('RESTRICTED CONTENT'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('RESTRICTED CONTENT'), findsNothing);
    });
  });
}
