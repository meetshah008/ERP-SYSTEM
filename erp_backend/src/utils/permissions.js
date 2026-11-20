/**
 * Role-Based Default Permission Presets
 */
function getDefaultPermissions(roleName = 'Employee', deptName = '') {
  const normRole = (roleName || '').trim().toLowerCase();
  const normDept = (deptName || '').trim().toLowerCase();
  const isSuperAdmin = normRole.includes('admin') || normRole.includes('executive');
  const isManager = !isSuperAdmin && (normRole.includes('manager') || normRole.includes('supervisor'));

  // 1. SUPER ADMIN (Full Executive Privileges)
  if (isSuperAdmin) {
    return {
      hr_view_directory: true,
      hr_manage_staff: true,
      hr_manage_departments: true,
      hr_view_lifecycle: true,
      attendance_view_logs: true,
      attendance_import_excel: true,
      attendance_override: true,
      attendance_biometric_manage: true,
      leaves_apply: true,
      leaves_approve: true,
      tasks_view: true,
      projects_create: true,
      projects_edit: true,
      projects_delete: true,
      tasks_create_assign: true,
      tasks_create_self: true,
      tasks_edit: true,
      tasks_delete: true,
      tasks_log_timesheet: true,
      inventory_view_stock: true,
      inventory_manage_material: true,
      manufacturing_view_bom: true,
      manufacturing_work_orders: true,
      finance_view_reports: true,
      salary_manage_increment: true,
      system_audit_logs: true
    };
  }

  // 2. MODULE MANAGER (Full Privileges for Assigned Department / Module)
  if (isManager) {
    const isHR = normDept.includes('hr') || normDept.includes('human') || normDept.includes('personnel');
    const isProjects = normDept.includes('it') || normDept.includes('tech') || normDept.includes('eng') || normDept.includes('project') || normDept.includes('soft');
    const isInventory = normDept.includes('invent') || normDept.includes('store') || normDept.includes('ware') || normDept.includes('stock');
    const isManufacturing = normDept.includes('manuf') || normDept.includes('prod') || normDept.includes('plant') || normDept.includes('operat');
    const isFinance = normDept.includes('fin') || normDept.includes('acc') || normDept.includes('bill') || normDept.includes('pay');

    return {
      // General Common Base for Managers
      hr_view_directory: true,
      attendance_view_logs: true,
      leaves_apply: true,
      leaves_approve: true,
      tasks_view: true,
      tasks_create_self: true,
      tasks_log_timesheet: true,

      // HR Module:
      hr_manage_staff: isHR || (!isProjects && !isInventory && !isManufacturing && !isFinance),
      hr_view_lifecycle: isHR || (!isProjects && !isInventory && !isManufacturing && !isFinance),
      attendance_import_excel: isHR || (!isProjects && !isInventory && !isManufacturing && !isFinance),
      attendance_biometric_manage: isHR || (!isProjects && !isInventory && !isManufacturing && !isFinance),
      hr_manage_departments: false, // Super Admin only
      attendance_override: false,   // Super Admin only

      // Projects & Tasks Module:
      projects_create: isProjects || (!isHR && !isInventory && !isManufacturing && !isFinance),
      projects_edit: isProjects || (!isHR && !isInventory && !isManufacturing && !isFinance),
      projects_delete: false,       // Super Admin only
      tasks_create_assign: isProjects || (!isHR && !isInventory && !isManufacturing && !isFinance),
      tasks_edit: isProjects || (!isHR && !isInventory && !isManufacturing && !isFinance),
      tasks_delete: false,          // Super Admin only

      // Inventory Module:
      inventory_view_stock: isInventory || isManufacturing || (!isHR && !isFinance),
      inventory_manage_material: isInventory || (!isHR && !isProjects && !isFinance),

      // Manufacturing Module:
      manufacturing_view_bom: isManufacturing || isInventory || (!isHR && !isFinance),
      manufacturing_work_orders: isManufacturing || (!isHR && !isProjects && !isInventory && !isFinance),

      // Finance & Appraisal Module:
      finance_view_reports: isFinance,
      salary_manage_increment: isFinance || isHR,

      // System Security
      system_audit_logs: false
    };
  }

  // 3. EMPLOYEE (Standard Staff): Strictly filtered as requested by user
  return {
    hr_view_directory: true,              // View Employee Directory
    hr_manage_staff: false,
    hr_manage_departments: false,
    hr_view_lifecycle: false,
    attendance_view_logs: true,           // View punch logs
    attendance_import_excel: false,
    attendance_override: false,
    attendance_biometric_manage: false,
    leaves_apply: true,                   // Apply For Leaves
    leaves_approve: false,
    tasks_view: true,                     // View Projects & Kanban Tasks
    projects_create: false,
    projects_edit: false,
    projects_delete: false,
    tasks_create_assign: false,          // Cannot assign tasks to others
    tasks_create_self: true,             // Can create self personal tasks
    tasks_edit: false,
    tasks_delete: false,
    tasks_log_timesheet: true,            // Log Work Timesheets
    inventory_view_stock: false,
    inventory_manage_material: false,
    manufacturing_view_bom: false,
    manufacturing_work_orders: false,
    finance_view_reports: false,
    salary_manage_increment: false,
    system_audit_logs: false
  };
}

module.exports = {
  getDefaultPermissions
};
