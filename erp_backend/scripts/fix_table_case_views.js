const mysql = require('mysql2/promise');

async function fixViews() {
  console.log('⏳ Connecting to Aiven to create case-insensitive compatibility views...');
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || 'mysql-3a44ae2e-erp-system.a.aivencloud.com',
    port: parseInt(process.env.DB_PORT || '11850', 10),
    user: process.env.DB_USER || 'avnadmin',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'defaultdb',
    ssl: { rejectUnauthorized: false }
  });

  const lowercaseViews = [
    { view: 'employee', target: 'EMPLOYEE' },
    { view: 'department', target: 'DEPARTMENT' },
    { view: 'company', target: 'COMPANY' },
    { view: 'branch', target: 'BRANCH' },
    { view: 'user', target: 'USER' },
    { view: 'role', target: 'ROLE' },
    { view: 'permission', target: 'PERMISSION' },
    { view: 'role_permission', target: 'ROLE_PERMISSION' },
    { view: 'attendance', target: 'ATTENDANCE' },
    { view: 'attendance_import', target: 'ATTENDANCE_IMPORT' },
    { view: 'leave_request', target: 'LEAVE_REQUEST' },
    { view: 'employee_permission', target: 'EMPLOYEE_PERMISSION' }
  ];

  const uppercaseViews = [
    { view: 'PROJECT', target: 'project' },
    { view: 'TASK', target: 'task' },
    { view: 'PROJECT_MEMBER', target: 'project_member' },
    { view: 'TASK_ASSIGNEES', target: 'task_assignees' },
    { view: 'TASK_SUBTASK', target: 'task_subtask' },
    { view: 'PROJECT_TIMESHEET', target: 'project_timesheet' },
    { view: 'PROJECT_MATERIAL', target: 'project_material' },
    { view: 'NOTIFICATION', target: 'notification' }
  ];

  for (const item of [...lowercaseViews, ...uppercaseViews]) {
    try {
      await conn.query(`CREATE OR REPLACE VIEW \`${item.view}\` AS SELECT * FROM \`${item.target}\``);
      console.log(`✅ View created: \`${item.view}\` -> \`${item.target}\``);
    } catch (e) {
      console.warn(`⚠️ Error for \`${item.view}\`:`, e.message);
    }
  }

  await conn.end();
  console.log('🎉 ALL COMPATIBILITY VIEWS CREATED!');
}

fixViews().catch(console.error);
