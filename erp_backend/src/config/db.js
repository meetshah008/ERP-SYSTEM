const mysql = require('mysql2/promise');
const dotenv = require('dotenv');

dotenv.config();

// Create connection pool to MySQL
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || 'root',
  database: process.env.DB_NAME || 'manufacturing_erp',
  port: process.env.DB_PORT || 3306,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

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

    console.log('✅ Master Database tables & columns verified!');
    connection.release();
  } catch (error) {
    console.error('❌ MySQL Connection Failed:', error.message);
    console.log('💡 Note: Ensure MySQL Server is running and .env has the right username/password.');
  }
}

testConnection();

module.exports = pool;
