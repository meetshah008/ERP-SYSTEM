import 'package:flutter/material.dart';

import '../../features/04_hr_module/attendance_screen.dart';
import '../../features/04_hr_module/biometric_import_screen.dart';
import '../../features/04_hr_module/departments_screen.dart';
import '../../features/04_hr_module/employee_management_screen.dart';
import '../../features/04_hr_module/leave_management_screen.dart';
import '../../features/04_hr_module/salary_increment_screen.dart';
import '../../features/05_tasks/project_edit_screen.dart';
import '../../features/05_tasks/project_tasks_screen.dart';
import '../../features/05_tasks/task_form_screen.dart';
import '../network/session_manager.dart';

/// Logical module a navigation entry belongs to.
enum AppNavModule {
  general,
  hr,
  projects,
  inventory,
  manufacturing,
  finance,
  system,
}

/// One navigation entry. [permissionKey] is the exact key used by the backend
/// permission engine (`getDefaultPermissions` / `EMPLOYEE_PERMISSION`).
class AppNavItem {
  const AppNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.module,
    this.permissionKey,
    this.targetMenu,
    this.screenBuilder,
    this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final AppNavModule module;
  final String? permissionKey;

  /// When set, selecting this item switches the dashboard's inline tab instead
  /// of pushing a full screen. Keeps the existing dashboard content intact.
  final String? targetMenu;

  /// When set, selecting this item pushes that existing screen.
  final Widget Function()? screenBuilder;

  final String? description;

  bool get opensScreen => screenBuilder != null;
}

/// A collapsible group in the sidebar.
class AppNavGroup {
  const AppNavGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<AppNavItem> items;
}

/// Single source of truth for "which permission unlocks which page".
///
/// Keys are deliberately the exact backend keys; no duplicate permission
/// vocabulary is introduced here. Adding a permission in the backend and
/// granting it to a manager automatically makes the mapped page appear.
abstract final class AppNavCatalog {
  static const String dashboardMenu = 'Dashboard';

  static const AppNavItem dashboard = AppNavItem(
    id: 'dashboard',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    module: AppNavModule.general,
    targetMenu: dashboardMenu,
  );

  static final List<AppNavGroup> groups = [
    const AppNavGroup(
      id: 'general',
      label: '',
      icon: Icons.dashboard_outlined,
      items: [dashboard],
    ),
    AppNavGroup(
      id: 'hr',
      label: 'HR MANAGEMENT',
      icon: Icons.people_alt_outlined,
      items: [
        const AppNavItem(
          id: 'hr_directory',
          label: 'Employee Directory',
          icon: Icons.badge_outlined,
          module: AppNavModule.hr,
          permissionKey: 'hr_view_directory',
          screenBuilder: _openEmployeeManagement,
          description: 'Browse the company employee directory',
        ),
        AppNavItem(
          id: 'attendance_logs',
          label: 'Biometric Attendance',
          icon: Icons.fingerprint_rounded,
          module: AppNavModule.hr,
          permissionKey: 'attendance_view_logs',
          screenBuilder: () => const AttendanceScreen(),
        ),
        AppNavItem(
          id: 'attendance_import',
          label: 'Biometric Excel Import',
          icon: Icons.upload_file_outlined,
          module: AppNavModule.hr,
          permissionKey: 'attendance_import_excel',
          screenBuilder: () => const BiometricImportScreen(),
        ),
        AppNavItem(
          id: 'leaves_apply',
          label: 'Staff Leave Management',
          icon: Icons.event_available_outlined,
          module: AppNavModule.hr,
          permissionKey: 'leaves_apply',
          screenBuilder: () => const LeaveManagementScreen(),
        ),
        AppNavItem(
          id: 'hr_departments',
          label: 'Department Management',
          icon: Icons.account_tree_outlined,
          module: AppNavModule.hr,
          permissionKey: 'hr_manage_departments',
          screenBuilder: () => const DepartmentsScreen(),
        ),
        AppNavItem(
          id: 'hr_payroll',
          label: 'Payroll & Increments',
          icon: Icons.payments_outlined,
          module: AppNavModule.hr,
          permissionKey: 'salary_manage_increment',
          screenBuilder: () => const SalaryIncrementScreen(),
        ),
      ],
    ),
    const AppNavGroup(
      id: 'projects',
      label: 'PROJECTS & TASKS',
      icon: Icons.assignment_outlined,
      items: [
        AppNavItem(
          id: 'projects_tasks',
          label: 'Projects & Tasks',
          icon: Icons.assignment_outlined,
          module: AppNavModule.projects,
          permissionKey: 'tasks_view',
          targetMenu: 'Projects & Tasks',
        ),
        AppNavItem(
          id: 'projects_create',
          label: 'Create Project',
          icon: Icons.create_new_folder_outlined,
          module: AppNavModule.projects,
          permissionKey: 'projects_create',
          screenBuilder: _openProjectEdit,
        ),
        AppNavItem(
          id: 'projects_workspace',
          label: 'Project Workspace',
          icon: Icons.view_kanban_outlined,
          module: AppNavModule.projects,
          permissionKey: 'projects_edit',
          screenBuilder: _openProjectTasks,
        ),
        AppNavItem(
          id: 'projects_delete',
          label: 'Project Deletion',
          icon: Icons.delete_forever_outlined,
          module: AppNavModule.projects,
          permissionKey: 'projects_delete',
          screenBuilder: _openProjectTasks,
        ),
        AppNavItem(
          id: 'tasks_assign',
          label: 'Assign Task',
          icon: Icons.add_task_outlined,
          module: AppNavModule.projects,
          permissionKey: 'tasks_create_assign',
          screenBuilder: _openTaskForm,
        ),
        AppNavItem(
          id: 'tasks_self',
          label: 'Personal Tasks',
          icon: Icons.task_alt_outlined,
          module: AppNavModule.projects,
          permissionKey: 'tasks_create_self',
          screenBuilder: _openTaskForm,
        ),
        AppNavItem(
          id: 'tasks_edit',
          label: 'Task Editing',
          icon: Icons.edit_outlined,
          module: AppNavModule.projects,
          permissionKey: 'tasks_edit',
          screenBuilder: _openProjectTasks,
        ),
        AppNavItem(
          id: 'tasks_delete',
          label: 'Task Deletion',
          icon: Icons.delete_outline,
          module: AppNavModule.projects,
          permissionKey: 'tasks_delete',
          screenBuilder: _openProjectTasks,
        ),
        AppNavItem(
          id: 'general_tasks',
          label: 'General Tasks',
          icon: Icons.checklist_outlined,
          module: AppNavModule.projects,
          // Every non-admin role can create self tasks, including HR managers.
          // Their task query stays scoped to their own employee record.
          permissionKey: 'tasks_create_self',
          // Rendered inside the dashboard workspace (like Projects & Tasks),
          // not as a separate pushed route, so it always becomes visible.
          targetMenu: 'General Tasks',
        ),
      ],
    ),
    const AppNavGroup(
      id: 'inventory',
      label: 'INVENTORY',
      icon: Icons.inventory_2_outlined,
      items: [
        AppNavItem(
          id: 'inventory_stock',
          label: 'Inventory & Stock',
          icon: Icons.inventory_2_outlined,
          module: AppNavModule.inventory,
          permissionKey: 'inventory_view_stock',
          targetMenu: 'Inventory & Stock',
        ),
        AppNavItem(
          id: 'inventory_material',
          label: 'Issue Materials',
          icon: Icons.local_shipping_outlined,
          module: AppNavModule.inventory,
          permissionKey: 'inventory_manage_material',
          targetMenu: 'Inventory & Stock',
        ),
      ],
    ),
    const AppNavGroup(
      id: 'manufacturing',
      label: 'MANUFACTURING',
      icon: Icons.factory_outlined,
      items: [
        AppNavItem(
          id: 'manufacturing_bom',
          label: 'Manufacturing & BOM',
          icon: Icons.factory_outlined,
          module: AppNavModule.manufacturing,
          permissionKey: 'manufacturing_view_bom',
          targetMenu: 'Manufacturing & BOM',
        ),
        AppNavItem(
          id: 'manufacturing_work_orders',
          label: 'Work Orders',
          icon: Icons.precision_manufacturing_outlined,
          module: AppNavModule.manufacturing,
          permissionKey: 'manufacturing_work_orders',
          targetMenu: 'Manufacturing & BOM',
        ),
      ],
    ),
    const AppNavGroup(
      id: 'finance',
      label: 'ACCOUNTS & FINANCE',
      icon: Icons.account_balance_wallet_outlined,
      items: [
        AppNavItem(
          id: 'finance_reports',
          label: 'Accounts & Finance',
          icon: Icons.account_balance_wallet_outlined,
          module: AppNavModule.finance,
          permissionKey: 'finance_view_reports',
          targetMenu: 'Accounts & Finance',
        ),
      ],
    ),
    const AppNavGroup(
      id: 'system',
      label: 'WORKSPACE',
      icon: Icons.settings_outlined,
      items: [
        AppNavItem(
          id: 'settings_logs',
          label: 'Settings & Logs',
          icon: Icons.settings_outlined,
          module: AppNavModule.system,
          // Settings is a personal workspace screen (theme, profile, logout),
          // so it stays visible to every role.
          permissionKey: null,
          targetMenu: 'Settings & Logs',
        ),
      ],
    ),
  ];

  static Widget _openEmployeeManagement() => const EmployeeManagementScreen();
  static Widget _openProjectTasks() => const ProjectTasksScreen();
  static Widget _openProjectEdit() => const ProjectEditScreen();
  static Widget _openTaskForm() => const TaskFormScreen();

  static List<AppNavItem> get allItems =>
      groups.expand((group) => group.items).toList();

  static AppNavItem? itemById(String id) {
    for (final item in allItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  static String? permissionKeyForMenu(String menu) {
    for (final item in allItems) {
      if (item.targetMenu == menu) return item.permissionKey;
    }
    return null;
  }
}

/// Resolves the visible sidebar tree from the *stored* login permissions.
///
/// The resolver is a pure function so it can be unit tested and so sidebar
/// visibility and route guards share exactly the same rules.
abstract final class AppNavResolver {
  /// Keep this consistent with the dashboard's Super Admin branch. Super Admin
  /// keeps its original UI, so the dynamic sidebar is never used for it.
  static bool isSuperAdmin(String role) => role.trim() == 'Super Admin';

  static bool canOpen(
    String role,
    Map<String, bool> permissions,
    String? permissionKey,
  ) {
    if (permissionKey == null) return true;
    if (isSuperAdmin(role)) return true;
    return permissions[permissionKey] ?? false;
  }

  /// Sidebar-only entries hidden from a Projects module manager.
  ///
  /// The backend permissions stay untouched, so direct route guards still
  /// behave exactly as before; only the navigation list is simplified.
  static const Set<String> _hiddenForProjectsManager = {
    'projects_create',
    'projects_workspace',
    'projects_delete',
    'tasks_assign',
    'tasks_self',
    'tasks_edit',
    'tasks_delete',
  };

  /// Shared Projects-module-manager detection.
  ///
  /// Used for sidebar simplification and for the General Tasks query so the
  /// manager sees all non-private tasks without duplicating the role rules.
  static bool isProjectsModuleManager(
    String role,
    Map<String, bool> permissions,
  ) {
    if (isSuperAdmin(role)) return false;

    final lower = role.trim().toLowerCase();
    final roleNamesProjectManager = lower.contains('project') &&
        (lower.contains('manager') || lower.contains('supervisor'));

    // The seeded backend role is simply "Module Manager"; the granted
    // permissions tell us which module that manager owns.
    final seededProjectsManager = lower == 'module manager' &&
        (permissions['tasks_view'] ?? false) &&
        !(permissions['hr_view_directory'] ?? false);

    return roleNamesProjectManager || seededProjectsManager;
  }

  static List<AppNavGroup> resolve(
    String role,
    Map<String, bool> permissions,
  ) {
    final resolved = <AppNavGroup>[];
    final hideProjectsManagerItems = isProjectsModuleManager(role, permissions);

    for (final group in AppNavCatalog.groups) {
      final items = group.items
          .where(
            (item) =>
                canOpen(role, permissions, item.permissionKey) &&
                !(hideProjectsManagerItems &&
                    _hiddenForProjectsManager.contains(item.id)),
          )
          .toList();
      if (items.isEmpty) continue;
      resolved.add(AppNavGroup(
        id: group.id,
        label: group.label,
        icon: group.icon,
        items: items,
      ));
    }

    return resolved;
  }
}

/// Wraps a screen so a restricted page can never be rendered, even if it is
/// pushed from an old shortcut that was written before this navigation system.
class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.permissionKey,
    required this.moduleTitle,
    required this.child,
  });

  final String permissionKey;
  final String moduleTitle;
  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final session = await SessionManager.getUserSession();
    final role = (session['role'] as String?) ?? '';
    final permissions = await SessionManager.getPermissions();
    final allowed = AppNavResolver.canOpen(
      role,
      permissions,
      widget.permissionKey,
    );
    if (mounted) setState(() => _allowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_allowed == false) {
      return Scaffold(
        body: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_person_rounded,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    'Access Restricted',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You do not have permission to access ${widget.moduleTitle}.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
