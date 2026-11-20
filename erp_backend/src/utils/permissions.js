/**
 * Role-Based Default Permission Presets
 */
function getDefaultPermissions(roleName = 'Employee', deptName = '', managerModule = '') {
  const normRole = (roleName || '').trim().toLowerCase();
  const normDept = (deptName || '').trim().toLowerCase();
  const normMod = (managerModule || '').trim().toLowerCase();
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

  // 2. MODULE MANAGER (Supervisor for a SPECIFIC Chosen Module)
  if (isManager) {
    // Determine which module this manager oversees
    let mod = normMod;
    if (!mod) {
      if (normDept.includes('hr') || normDept.includes('human') || normDept.includes('personnel')) mod = 'hr';
      else if (normDept.includes('it') || normDept.includes('tech') || normDept.includes('eng') || normDept.includes('project') || normDept.includes('soft')) mod = 'projects';
      else if (normDept.includes('invent') || normDept.includes('store') || normDept.includes('ware') || normDept.includes('stock')) mod = 'inventory';
      else if (normDept.includes('manuf') || normDept.includes('prod') || normDept.includes('plant') || normDept.includes('operat')) mod = 'manufacturing';
      else if (normDept.includes('fin') || normDept.includes('acc') || normDept.includes('bill') || normDept.includes('pay')) mod = 'finance';
      else mod = 'hr';
    }

    const isHR = mod === 'hr';
    const isProjects = mod === 'projects';
    const isInventory = mod === 'inventory';
    const isManufacturing = mod === 'manufacturing';
    const isFinance = mod === 'finance';

    return {
      // General Common Base for Managers
      leaves_apply: true,
      tasks_create_self: true,
      tasks_log_timesheet: true,

      // HR Module:
      hr_view_directory: isHR,
      hr_manage_staff: isHR,
      hr_view_lifecycle: isHR,
      attendance_view_logs: isHR,
      attendance_import_excel: isHR,
      attendance_biometric_manage: isHR,
      leaves_approve: isHR,
      hr_manage_departments: false, // Super Admin only
      attendance_override: false,   // Super Admin only

      // Projects & Tasks Module:
      tasks_view: isProjects,
      projects_create: isProjects,
      projects_edit: isProjects,
      projects_delete: false,       // Super Admin only
      tasks_create_assign: isProjects,
      tasks_edit: isProjects,
      tasks_delete: false,          // Super Admin only

      // Inventory Module:
      inventory_view_stock: isInventory || isManufacturing,
      inventory_manage_material: isInventory,

      // Manufacturing Module:
      manufacturing_view_bom: isManufacturing,
      manufacturing_work_orders: isManufacturing,

      // Finance & Appraisal Module:
      finance_view_reports: isFinance,
      salary_manage_increment: isFinance,

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
