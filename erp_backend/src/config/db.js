const mysql = require('mysql2/promise');
const dotenv = require('dotenv');

const path = require('path');
dotenv.config({ path: path.resolve(__dirname, '../../.env') });
dotenv.config();

// Create connection pool to MySQL (Supports both individual env vars and full DATABASE_URL/Service URI)
let pool;
if (process.env.DATABASE_URL) {
  let cleanUri = process.env.DATABASE_URL.split('?')[0];
  pool = mysql.createPool({
    uri: cleanUri,
    ssl: { rejectUnauthorized: false },
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
  });
} else {
  pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || 'root',
    database: process.env.DB_NAME || 'manufacturing_erp',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    ssl: (process.env.DB_SSL === 'true' || process.env.DB_SSL === 'REQUIRED' || process.env.DB_SSL === 'required')
      ? { rejectUnauthorized: false }
      : undefined,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
  });
}

// Test connection & Auto Schema Setup
async function testConnection() {
  try {
    const connection = await pool.getConnection();
    console.log('✅ Successfully connected to MySQL Database!');

    // 1. Auto-create EMPLOYEE_PERMISSION
    await connection.query(`
      CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
        employee_id INT NOT NULL,
        permission_key VARCHAR(60) NOT NULL,
        is_granted TINYINT(1) DEFAULT 1,
        PRIMARY KEY (employee_id, permission_key),
        CONSTRAINT fk_emp_perm FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // 2. Auto-create LEAVE_REQUEST
    await connection.query(`
      CREATE TABLE IF NOT EXISTS LEAVE_REQUEST (
        leave_id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT NOT NULL DEFAULT 1,
        employee_id INT NOT NULL,
        leave_type VARCHAR(50) NOT NULL,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        total_days INT NOT NULL DEFAULT 1,
        reason TEXT,
        status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // 2B. Auto-create task_assignees (Multi-worker assignment support)
    await connection.query(`
      CREATE TABLE IF NOT EXISTS task_assignees (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        employee_id INT NOT NULL,
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_task_emp (task_id, employee_id),
        FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE,
        FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    // 2C. Auto-create task_reviewers (multi-reviewer approval support)
    try {
      await connection.query(`
        CREATE TABLE IF NOT EXISTS task_reviewers (
          id INT AUTO_INCREMENT PRIMARY KEY,
          task_id INT NOT NULL,
          employee_id INT NOT NULL,
          assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE KEY uq_task_reviewer (task_id, employee_id),
          INDEX idx_tr_task (task_id),
          INDEX idx_tr_emp (employee_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
      `);
      await connection.query("CREATE OR REPLACE VIEW TASK_REVIEWERS AS SELECT * FROM task_reviewers");
    } catch (_) {}

    // 3. Ensure EMPLOYEE columns exist
    const columns = [
      { name: 'employment_type', sql: "VARCHAR(50) DEFAULT 'Permanent'" },
      { name: 'weekly_off', sql: "VARCHAR(50) DEFAULT 'Sunday'" },
      { name: 'salary_grade', sql: "VARCHAR(50) DEFAULT 'Grade B'" },
      { name: 'salary_base', sql: "DECIMAL(12,2) DEFAULT 35000.00" },
      { name: 'leave_balance_casual', sql: "INT DEFAULT 12" },
      { name: 'leave_balance_sick', sql: "INT DEFAULT 8" },
      { name: 'leave_balance_paid', sql: "INT DEFAULT 15" },
      { name: 'phone', sql: "VARCHAR(20) NULL" },
      { name: 'email', sql: "VARCHAR(120) NULL" },
      { name: 'unpaid_leave_limit', sql: "INT DEFAULT 10" },
      { name: 'unpaid_leave_per_day_deduction', sql: "DECIMAL(12,2) DEFAULT 0.00" },
      { name: 'unpaid_leaves_taken', sql: "INT DEFAULT 0" },
      { name: 'total_leave_deduction', sql: "DECIMAL(12,2) DEFAULT 0.00" }
    ];

    for (const col of columns) {
      try {
        await connection.query(`ALTER TABLE EMPLOYEE ADD COLUMN ${col.name} ${col.sql}`);
      } catch (_) {}
    }

    try {
      await connection.query("ALTER TABLE task ADD COLUMN is_private TINYINT(1) DEFAULT 0");
    } catch (_) {}

    // Approval workflow metadata. Guarded so existing databases upgrade cleanly.
    for (const column of [
      { name: 'assigned_by', sql: 'INT NULL' },
      { name: 'reviewed_by', sql: 'INT NULL' },
      { name: 'reviewed_at', sql: 'DATETIME NULL' },
    ]) {
      try {
        await connection.query(`ALTER TABLE task ADD COLUMN ${column.name} ${column.sql}`);
      } catch (_) {}
    }

    // Older schemas used ENUM without REVIEW; VARCHAR keeps all legacy values.
    try {
      await connection.query("ALTER TABLE task MODIFY COLUMN status VARCHAR(20) NOT NULL DEFAULT 'TODO'");
    } catch (_) {}

    // Refresh views so all new columns (assigned_by, reviewed_by, etc.) are visible
    try {
      await connection.query("CREATE OR REPLACE VIEW TASK AS SELECT * FROM task");
    } catch (_) {}

                // 2D. Auto-create attendance_settings (per company configurable rules)
                try {
                  await connection.query(`
                    CREATE TABLE IF NOT EXISTS attendance_settings (
                      setting_id INT AUTO_INCREMENT PRIMARY KEY,
                      company_id INT NOT NULL UNIQUE,
                      shift_start VARCHAR(10) NOT NULL DEFAULT '09:00',
                      shift_end VARCHAR(10) NOT NULL DEFAULT '18:00',
                      grace_minutes INT NOT NULL DEFAULT 30,
                      no_punch_default_status VARCHAR(20) NOT NULL DEFAULT 'Absent',
                      enable_late_warning_quota TINYINT(1) NOT NULL DEFAULT 1,
                      late_warning_limit INT NOT NULL DEFAULT 3,
                      late_penalty_action VARCHAR(20) NOT NULL DEFAULT 'Half-Day',
                      full_day_minutes INT NOT NULL DEFAULT 480,
                      half_day_minutes INT NOT NULL DEFAULT 240,
                      missing_out_punch_status VARCHAR(20) NOT NULL DEFAULT 'Missing',
                      enable_early_going_rule TINYINT(1) NOT NULL DEFAULT 1,
                      early_going_grace_minutes INT NOT NULL DEFAULT 15,
                      early_going_action VARCHAR(20) NOT NULL DEFAULT 'Half-Day',
                      enable_auto_overtime TINYINT(1) NOT NULL DEFAULT 1,
                      overtime_buffer_minutes INT NOT NULL DEFAULT 30,
                      overtime_rate_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.50,
                      overtime_fixed_hourly_rate DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                      enable_leave_integration TINYINT(1) NOT NULL DEFAULT 1,
                      auto_sync_payroll_deduction TINYINT(1) NOT NULL DEFAULT 1,
                      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                  `);
                  for (const col of [
                    { name: 'no_punch_default_status', sql: "VARCHAR(20) NOT NULL DEFAULT 'Absent'" },
                    { name: 'late_penalty_action', sql: "VARCHAR(20) NOT NULL DEFAULT 'Half-Day'" },
                    { name: 'full_day_minutes', sql: 'INT NOT NULL DEFAULT 480' },
                    { name: 'enable_early_going_rule', sql: 'TINYINT(1) NOT NULL DEFAULT 1' },
                    { name: 'early_going_grace_minutes', sql: 'INT NOT NULL DEFAULT 15' },
                    { name: 'early_going_action', sql: "VARCHAR(20) NOT NULL DEFAULT 'Half-Day'" },
                    { name: 'overtime_rate_multiplier', sql: 'DECIMAL(4,2) NOT NULL DEFAULT 1.50' },
                    { name: 'overtime_fixed_hourly_rate', sql: 'DECIMAL(10,2) NOT NULL DEFAULT 0.00' },
                    { name: 'enable_leave_integration', sql: 'TINYINT(1) NOT NULL DEFAULT 1' },
                    { name: 'auto_sync_payroll_deduction', sql: 'TINYINT(1) NOT NULL DEFAULT 1' },
                  ]) {
                    try {
                      await connection.query(`ALTER TABLE attendance_settings ADD COLUMN ${col.name} ${col.sql}`);
                    } catch (_) {}
                  }
                  await connection.query("CREATE OR REPLACE VIEW ATTENDANCE_SETTINGS AS SELECT * FROM attendance_settings");
                } catch (_) {}


                    // 2E. Attendance Master Tables (Status, Shift, Holiday, Weekly Off, Leave Type, Device)
                    const masterDdls = [
                      `CREATE TABLE IF NOT EXISTS att_master_status (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        code VARCHAR(10) NOT NULL,
                        name VARCHAR(60) NOT NULL,
                        is_paid TINYINT(1) NOT NULL DEFAULT 1,
                        color_hex VARCHAR(16) NOT NULL DEFAULT '#059669'
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                      `CREATE TABLE IF NOT EXISTS att_master_shift (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        shift_name VARCHAR(80) NOT NULL,
                        start_time VARCHAR(10) NOT NULL DEFAULT '09:00',
                        end_time VARCHAR(10) NOT NULL DEFAULT '18:00',
                        break_minutes INT NOT NULL DEFAULT 60
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                      `CREATE TABLE IF NOT EXISTS att_master_holiday (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        holiday_name VARCHAR(100) NOT NULL,
                        holiday_date DATE NOT NULL,
                        holiday_type VARCHAR(30) NOT NULL DEFAULT 'Public Holiday'
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                      `CREATE TABLE IF NOT EXISTS att_master_weekly_off (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        rule_name VARCHAR(80) NOT NULL,
                        off_days VARCHAR(100) NOT NULL DEFAULT 'Sunday',
                        saturday_rule VARCHAR(50) NOT NULL DEFAULT 'All Working'
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                      `CREATE TABLE IF NOT EXISTS att_master_leave_type (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        leave_code VARCHAR(12) NOT NULL,
                        leave_name VARCHAR(80) NOT NULL,
                        annual_quota INT NOT NULL DEFAULT 12,
                        is_paid TINYINT(1) NOT NULL DEFAULT 1
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                      `CREATE TABLE IF NOT EXISTS att_master_device (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        company_id INT NOT NULL,
                        device_name VARCHAR(80) NOT NULL,
                        device_code VARCHAR(40) NOT NULL,
                        device_type VARCHAR(30) NOT NULL DEFAULT 'Biometric',
                        ip_address VARCHAR(50) NULL,
                        location VARCHAR(80) NULL,
                        status VARCHAR(20) NOT NULL DEFAULT 'Active'
                      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
                    ];
                    for (const ddl of masterDdls) {
                      try {
                        await connection.query(ddl);
                      } catch (_) {}
                    }

    console.log('✅ Master Database tables & columns verified!');
    connection.release();
  } catch (error) {
    console.error('❌ MySQL Connection Failed:', error.message);
    console.log('💡 Note: Ensure MySQL Server is running and .env has the right username/password.');
  }
}


testConnection();

module.exports = pool;
