const db = require('./db');

async function migrate() {
  try {
    console.log('🔄 Checking EMPLOYEE schema updates...');
    const columns = [
      { name: 'employment_type', sql: "VARCHAR(50) DEFAULT 'Permanent'" },
      { name: 'weekly_off', sql: "VARCHAR(50) DEFAULT 'Sunday'" },
      { name: 'salary_grade', sql: "VARCHAR(50) DEFAULT 'Grade B'" },
      { name: 'salary_base', sql: "DECIMAL(12,2) DEFAULT 35000.00" },
      { name: 'leave_balance_casual', sql: "INT DEFAULT 12" },
      { name: 'leave_balance_sick', sql: "INT DEFAULT 8" },
      { name: 'leave_balance_paid', sql: "INT DEFAULT 15" },
      { name: 'role', sql: "VARCHAR(50) DEFAULT 'Employee'" },
      { name: 'age', sql: "INT NULL" },
      { name: 'gender', sql: "VARCHAR(20) DEFAULT 'Male'" },
      { name: 'dob', sql: "DATE NULL" },
      { name: 'city', sql: "VARCHAR(100) NULL" },
      { name: 'state', sql: "VARCHAR(100) NULL" },
      { name: 'address', sql: "TEXT NULL" },
      { name: 'aadhar_number', sql: "VARCHAR(30) NULL" },
      { name: 'pan_number', sql: "VARCHAR(30) NULL" },
      { name: 'emergency_contact', sql: "VARCHAR(50) NULL" },
      { name: 'unpaid_leave_limit', sql: "INT DEFAULT 10" },
      { name: 'unpaid_leave_per_day_deduction', sql: "DECIMAL(12,2) DEFAULT 0.00" }
    ];

    for (const col of columns) {
      try {
        await db.query(`ALTER TABLE EMPLOYEE ADD COLUMN ${col.name} ${col.sql}`);
        console.log(`✅ Added column: ${col.name}`);
      } catch (err) {
        if (err.code === 'ER_DUP_FIELDNAME') {
          console.log(`ℹ️ Column already exists: ${col.name}`);
        } else {
          console.warn(`⚠️ Warning for ${col.name}:`, err.message);
        }
      }
    }

    console.log('🔄 Checking EMPLOYEE_PERMISSION table...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
        employee_id INT NOT NULL,
        permission_key VARCHAR(60) NOT NULL,
        is_granted TINYINT(1) DEFAULT 1,
        PRIMARY KEY (employee_id, permission_key),
        CONSTRAINT fk_emp_perm FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);
    console.log('✅ Table EMPLOYEE_PERMISSION is ready!');
    console.log('🎉 Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

migrate();
