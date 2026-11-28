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

                        // 2F. Task Work Attachments / File Sharing
                        try {
                          await connection.query(`
                            CREATE TABLE IF NOT EXISTS task_attachments (
                              attachment_id INT AUTO_INCREMENT PRIMARY KEY,
                              company_id INT NOT NULL DEFAULT 1,
                              task_id INT NOT NULL,
                              uploaded_by INT NULL,
                              file_name VARCHAR(255) NOT NULL,
                              mime_type VARCHAR(120) DEFAULT 'application/octet-stream',
                              file_size INT DEFAULT 0,
                              file_data LONGBLOB NOT NULL,
                              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                              INDEX idx_ta_task (task_id)
                            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                          `);
                        } catch (_) {}



             // 3. Core Accounting Tables (Module 1 - Multi-Tenant by company_id)
             const financeDdls = [
               `CREATE TABLE IF NOT EXISTS finance_financial_year (
                 fy_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 fy_name VARCHAR(30) NOT NULL,
                 start_date DATE NOT NULL,
                 end_date DATE NOT NULL,
                 is_active TINYINT(1) NOT NULL DEFAULT 1,
                 is_closed TINYINT(1) NOT NULL DEFAULT 0,
                 INDEX idx_fy_company (company_id),
                 UNIQUE KEY uk_fy_company_name (company_id, fy_name)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_account (
                 account_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 account_code VARCHAR(20) NOT NULL,
                 account_name VARCHAR(120) NOT NULL,
                 account_type ENUM('Asset', 'Liability', 'Equity', 'Income', 'Expense') NOT NULL,
                 sub_group VARCHAR(80) DEFAULT 'General',
                 opening_balance DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 current_balance DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 is_active TINYINT(1) NOT NULL DEFAULT 1,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 INDEX idx_fa_company (company_id),
                 UNIQUE KEY uk_fa_company_code (company_id, account_code)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_voucher (
                 voucher_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 voucher_no VARCHAR(40) NOT NULL,
                 voucher_type ENUM('Payment', 'Receipt', 'Journal', 'Contra', 'Sales', 'Purchase') NOT NULL,
                 voucher_date DATE NOT NULL,
                 narration TEXT NULL,
                 total_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 status ENUM('POSTED', 'CANCELLED') NOT NULL DEFAULT 'POSTED',
                 cancel_reason VARCHAR(255) NULL,
                 created_by INT NULL,
                 cancelled_by INT NULL,
                 cancelled_at DATETIME NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 INDEX idx_fv_company (company_id),
                 INDEX idx_fv_date (voucher_date),
                 INDEX idx_fv_status (status),
                 UNIQUE KEY uk_fv_company_no (company_id, voucher_no)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_voucher_item (
                 item_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 voucher_id INT NOT NULL,
                 account_id INT NOT NULL,
                 debit_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 credit_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 description VARCHAR(255) NULL,
                 department_id INT NULL,
                 project_id INT NULL,
                 INDEX idx_fvi_voucher (voucher_id),
                 INDEX idx_fvi_account (account_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_voucher_attachment (
                 attachment_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 voucher_id INT NOT NULL,
                 file_name VARCHAR(255) NOT NULL,
                 mime_type VARCHAR(120) NULL,
                 file_size INT NOT NULL DEFAULT 0,
                 file_data LONGBLOB NOT NULL,
                 uploaded_by INT NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 UNIQUE KEY uk_fva_voucher (voucher_id),
                 INDEX idx_fva_company (company_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_vendor (
                 vendor_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 vendor_name VARCHAR(150) NOT NULL,
                 tax_no VARCHAR(50) NULL,
                 contact VARCHAR(100) NULL,
                 payment_terms VARCHAR(80) NULL,
                 is_active TINYINT(1) NOT NULL DEFAULT 1,
                 UNIQUE KEY uk_fvend_company_name (company_id, vendor_name)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_customer (
                 customer_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 customer_name VARCHAR(150) NOT NULL,
                 tax_no VARCHAR(50) NULL,
                 contact VARCHAR(100) NULL,
                 is_active TINYINT(1) NOT NULL DEFAULT 1,
                 UNIQUE KEY uk_fcust_company_name (company_id, customer_name)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_bank_account (
                 bank_account_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 bank_name VARCHAR(120) NOT NULL,
                 account_ref VARCHAR(80) NOT NULL,
                 ifsc VARCHAR(30) NULL,
                 current_balance DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 is_active TINYINT(1) NOT NULL DEFAULT 1,
                 UNIQUE KEY uk_fbank_company_ref (company_id, account_ref)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_bill (
                 bill_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 vendor_id INT NOT NULL,
                 bill_no VARCHAR(40) NOT NULL,
                 bill_date DATE NOT NULL,
                 po_no VARCHAR(60) NULL,
                 grn_no VARCHAR(60) NULL,
                 po_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 grn_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 total_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 match_status ENUM('NOT_CHECKED','MATCHED','FLAGGED') NOT NULL DEFAULT 'NOT_CHECKED',
                 status ENUM('DRAFT','FLAGGED','APPROVED','PAID','CANCELLED') NOT NULL DEFAULT 'DRAFT',
                 hold_reason VARCHAR(255) NULL,
                 created_by INT NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 UNIQUE KEY uk_fbill_company_no (company_id, bill_no),
                 INDEX idx_fbill_vendor (vendor_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_bill_item (
                 item_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 bill_id INT NOT NULL,
                 description VARCHAR(255) NULL,
                 qty DECIMAL(12,3) NOT NULL DEFAULT 1,
                 rate DECIMAL(14,2) NOT NULL DEFAULT 0,
                 amount DECIMAL(14,2) NOT NULL DEFAULT 0,
                 INDEX idx_fbi_bill (bill_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_invoice (
                 invoice_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 customer_id INT NOT NULL,
                 project_id INT NULL,
                 invoice_no VARCHAR(40) NOT NULL,
                 invoice_date DATE NOT NULL,
                 total_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
                 status ENUM('DRAFT','ISSUED','PAID','CANCELLED') NOT NULL DEFAULT 'DRAFT',
                 created_by INT NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 UNIQUE KEY uk_finv_company_no (company_id, invoice_no),
                 INDEX idx_finv_customer (customer_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_invoice_item (
                 item_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 invoice_id INT NOT NULL,
                 description VARCHAR(255) NULL,
                 qty DECIMAL(12,3) NOT NULL DEFAULT 1,
                 rate DECIMAL(14,2) NOT NULL DEFAULT 0,
                 amount DECIMAL(14,2) NOT NULL DEFAULT 0,
                 INDEX idx_fii_invoice (invoice_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_payment (
                 payment_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 bill_id INT NULL,
                 invoice_id INT NULL,
                 bank_account_id INT NOT NULL,
                 pay_date DATE NOT NULL,
                 amount DECIMAL(14,2) NOT NULL,
                 mode ENUM('NEFT','RTGS','Cheque','Cash','UPI') NOT NULL DEFAULT 'NEFT',
                 reference_no VARCHAR(80) NULL,
                 voucher_id INT NULL,
                 created_by INT NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 INDEX idx_fpay_company_date (company_id, pay_date)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_number_series (
                 series_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 doc_type ENUM('INVOICE','BILL') NOT NULL,
                 prefix VARCHAR(12) NOT NULL DEFAULT 'DOC',
                 last_number INT NOT NULL DEFAULT 0,
                 updated_by INT NULL,
                 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                 UNIQUE KEY uk_fns_company_type (company_id, doc_type)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
               `CREATE TABLE IF NOT EXISTS finance_audit_log (
                 log_id INT AUTO_INCREMENT PRIMARY KEY,
                 company_id INT NOT NULL,
                 entity VARCHAR(40) NOT NULL,
                 entity_id INT NULL,
                 action VARCHAR(30) NOT NULL,
                 summary VARCHAR(255) NULL,
                 before_json TEXT NULL,
                 after_json TEXT NULL,
                 created_by INT NULL,
                 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                 INDEX idx_fal_company_date (company_id, created_at),
                 INDEX idx_fal_entity (company_id, entity, entity_id)
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
             ];
             for (const ddl of financeDdls) {
               try {
                 await connection.query(ddl);
               } catch (_) {}
             }

                         // Upgrade EMPLOYEE with bank & statutory details for Payroll
                         const payrollEmpColumns = [
                           `ALTER TABLE EMPLOYEE ADD COLUMN bank_name VARCHAR(120) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN bank_account_no VARCHAR(60) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN bank_ifsc VARCHAR(20) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN pan_no VARCHAR(20) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN pf_uan VARCHAR(30) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN esi_no VARCHAR(30) NULL`,
                           `ALTER TABLE EMPLOYEE ADD COLUMN exit_date DATE NULL`
                         ];
                         for (const alterSql of payrollEmpColumns) {
                           try {
                             await connection.query(alterSql);
                           } catch (_) {}
                         }

                         // Payroll & Salary Module Tables (DECIMAL(15,2) only, never FLOAT)
                         const payrollDdls = [
                           `CREATE TABLE IF NOT EXISTS salary_components (
                             component_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             code VARCHAR(30) NOT NULL,
                             name VARCHAR(100) NOT NULL,
                             component_type ENUM('EARNING', 'DEDUCTION') NOT NULL,
                             calc_mode ENUM('FIXED', 'PERCENT_OF_BASIC') NOT NULL DEFAULT 'FIXED',
                             default_value DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             is_taxable TINYINT(1) NOT NULL DEFAULT 1,
                             is_statutory TINYINT(1) NOT NULL DEFAULT 0,
                             is_active TINYINT(1) NOT NULL DEFAULT 1,
                             display_order INT NOT NULL DEFAULT 10,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             UNIQUE KEY uk_sc_company_code (company_id, code),
                             INDEX idx_sc_company (company_id)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS employee_salary_structures (
                             structure_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             employee_id INT NOT NULL,
                             salary_type ENUM('MONTHLY', 'DAILY', 'HOURLY', 'PIECE_RATE') NOT NULL DEFAULT 'MONTHLY',
                             base_pay DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             gross_monthly DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             effective_from DATE NOT NULL,
                             effective_to DATE NULL,
                             is_current TINYINT(1) NOT NULL DEFAULT 1,
                             pf_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             esi_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             pt_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             tds_monthly DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             notes VARCHAR(255) NULL,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             INDEX idx_ess_emp (company_id, employee_id, is_current)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS employee_salary_structure_items (
                             item_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             structure_id INT NOT NULL,
                             component_id INT NOT NULL,
                             calc_mode ENUM('FIXED', 'PERCENT_OF_BASIC') NOT NULL DEFAULT 'FIXED',
                             amount_or_percent DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             computed_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             INDEX idx_essi_struct (structure_id)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS payroll_settings (
                             setting_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL UNIQUE,
                             days_in_month_mode ENUM('CALENDAR_DAYS', 'FIXED_30', 'WORKING_DAYS') NOT NULL DEFAULT 'CALENDAR_DAYS',
                             standard_shift_hours DECIMAL(5,2) NOT NULL DEFAULT 8.00,
                             ot_multiplier DECIMAL(5,2) NOT NULL DEFAULT 1.50,
                             ot_fixed_hourly_rate DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             late_grace_count INT NOT NULL DEFAULT 3,
                             late_deduction_days DECIMAL(5,2) NOT NULL DEFAULT 0.50,
                             early_going_deduction_days DECIMAL(5,2) NOT NULL DEFAULT 0.50,
                             auto_lock_attendance TINYINT(1) NOT NULL DEFAULT 0,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS statutory_settings (
                             stat_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL UNIQUE,
                             pf_enabled TINYINT(1) NOT NULL DEFAULT 1,
                             pf_employee_rate DECIMAL(5,2) NOT NULL DEFAULT 12.00,
                             pf_employer_rate DECIMAL(5,2) NOT NULL DEFAULT 12.00,
                             pf_wage_ceiling DECIMAL(15,2) NOT NULL DEFAULT 15000.00,
                             esi_enabled TINYINT(1) NOT NULL DEFAULT 1,
                             esi_employee_rate DECIMAL(5,2) NOT NULL DEFAULT 0.75,
                             esi_employer_rate DECIMAL(5,2) NOT NULL DEFAULT 3.25,
                             esi_wage_ceiling DECIMAL(15,2) NOT NULL DEFAULT 21000.00,
                             pt_enabled TINYINT(1) NOT NULL DEFAULT 1,
                             pt_slabs_json TEXT NOT NULL,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS payroll_runs (
                             run_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             run_code VARCHAR(40) NOT NULL,
                             pay_year INT NOT NULL,
                             pay_month INT NOT NULL,
                             department_id INT NULL,
                             status ENUM('DRAFT', 'APPROVED', 'PAID', 'LOCKED', 'CANCELLED') NOT NULL DEFAULT 'DRAFT',
                             attendance_locked TINYINT(1) NOT NULL DEFAULT 0,
                             total_employees INT NOT NULL DEFAULT 0,
                             total_gross DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             total_deductions DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             total_employer_contrib DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             total_net_pay DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             approval_voucher_id INT NULL,
                             approved_by INT NULL,
                             approved_at DATETIME NULL,
                             locked_by INT NULL,
                             locked_at DATETIME NULL,
                             cancel_reason VARCHAR(255) NULL,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             UNIQUE KEY uk_pr_company_period (company_id, pay_year, pay_month, department_id),
                             INDEX idx_pr_company_status (company_id, status)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS payroll_run_employees (
                             run_emp_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             run_id INT NOT NULL,
                             employee_id INT NOT NULL,
                             structure_id INT NULL,
                             salary_type VARCHAR(20) NOT NULL DEFAULT 'MONTHLY',
                             total_days INT NOT NULL DEFAULT 30,
                             working_days DECIMAL(6,2) NOT NULL DEFAULT 30.00,
                             present_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             absent_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             half_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             paid_leave_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             unpaid_leave_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             weekly_off_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             holiday_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             late_marks INT NOT NULL DEFAULT 0,
                             early_goings INT NOT NULL DEFAULT 0,
                             late_penalty_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             payable_days DECIMAL(6,2) NOT NULL DEFAULT 0.00,
                             overtime_hours DECIMAL(8,2) NOT NULL DEFAULT 0.00,
                             overtime_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             bonus_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             manual_adjustment DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             adjustment_note VARCHAR(255) NULL,
                             gross_earnings DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             pf_employee DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             pf_employer DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             esi_employee DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             esi_employer DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             pt_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             tds_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             advance_recovery DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             attendance_deduction DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             total_deductions DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             net_payable DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             paid_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                             payment_status ENUM('UNPAID', 'PARTIAL', 'PAID') NOT NULL DEFAULT 'UNPAID',
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             UNIQUE KEY uk_pre_run_emp (run_id, employee_id),
                             INDEX idx_pre_company_emp (company_id, employee_id)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS salary_payments (
                             salary_payment_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             run_id INT NOT NULL,
                             run_emp_id INT NULL,
                             employee_id INT NOT NULL,
                             bank_account_id INT NOT NULL,
                             payment_date DATE NOT NULL,
                             amount DECIMAL(15,2) NOT NULL,
                             payment_mode ENUM('Bank Transfer', 'Cash', 'Cheque', 'UPI') NOT NULL DEFAULT 'Bank Transfer',
                             reference_no VARCHAR(80) NULL,
                             voucher_id INT NULL,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             INDEX idx_sp_run (run_id),
                             INDEX idx_sp_emp (company_id, employee_id)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

                           `CREATE TABLE IF NOT EXISTS salary_templates (
                             template_id INT AUTO_INCREMENT PRIMARY KEY,
                             company_id INT NOT NULL,
                             template_name VARCHAR(100) NOT NULL,
                             description VARCHAR(255) NULL,
                             salary_type ENUM('MONTHLY', 'DAILY', 'HOURLY') NOT NULL DEFAULT 'MONTHLY',
                             basic_percent DECIMAL(5,2) NOT NULL DEFAULT 50.00,
                             hra_percent DECIMAL(5,2) NOT NULL DEFAULT 40.00,
                             conveyance_fixed DECIMAL(15,2) NOT NULL DEFAULT 1600.00,
                             pf_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             esi_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             pt_applicable TINYINT(1) NOT NULL DEFAULT 1,
                             is_active TINYINT(1) NOT NULL DEFAULT 1,
                             created_by INT NULL,
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                             UNIQUE KEY uk_st_company_name (company_id, template_name)
                           ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
                         ];
                         for (const ddl of payrollDdls) {
                           await connection.query(ddl);
                         }

                         try {
                           await connection.query(`ALTER TABLE employee_salary_structures ADD COLUMN template_id INT NULL AFTER employee_id`);
                         } catch (_) {}

             // Upgrade existing finance tables created by earlier versions.
             const financeUpgrades = [
               `ALTER TABLE finance_voucher ADD COLUMN cancelled_by INT NULL AFTER created_by`,
               `ALTER TABLE finance_voucher ADD COLUMN cancelled_at DATETIME NULL AFTER cancelled_by`,
               `ALTER TABLE finance_voucher ADD INDEX idx_fv_date (voucher_date)`,
               `ALTER TABLE finance_voucher ADD INDEX idx_fv_status (status)`,
               `ALTER TABLE finance_voucher ADD UNIQUE KEY uk_fv_company_no (company_id, voucher_no)`,
               `ALTER TABLE finance_account ADD UNIQUE KEY uk_fa_company_code (company_id, account_code)`,
               `ALTER TABLE finance_financial_year ADD UNIQUE KEY uk_fy_company_name (company_id, fy_name)`,
               `ALTER TABLE finance_vendor ADD COLUMN gstin VARCHAR(20) NULL AFTER tax_no`,
               `ALTER TABLE finance_vendor ADD COLUMN pan VARCHAR(20) NULL AFTER gstin`,
               `ALTER TABLE finance_vendor ADD COLUMN address TEXT NULL AFTER contact`,
               `ALTER TABLE finance_vendor ADD COLUMN bank_name VARCHAR(120) NULL AFTER payment_terms`,
               `ALTER TABLE finance_vendor ADD COLUMN bank_account_no VARCHAR(60) NULL AFTER bank_name`,
               `ALTER TABLE finance_vendor ADD COLUMN bank_ifsc VARCHAR(20) NULL AFTER bank_account_no`,
               `ALTER TABLE finance_vendor ADD COLUMN credit_limit DECIMAL(14,2) NOT NULL DEFAULT 0.00 AFTER bank_ifsc`,
               `ALTER TABLE finance_customer ADD COLUMN gstin VARCHAR(20) NULL AFTER tax_no`,
               `ALTER TABLE finance_customer ADD COLUMN pan VARCHAR(20) NULL AFTER gstin`,
               `ALTER TABLE finance_customer ADD COLUMN address TEXT NULL AFTER contact`,
               `ALTER TABLE finance_customer ADD COLUMN credit_limit DECIMAL(14,2) NOT NULL DEFAULT 0.00 AFTER address`,
               `ALTER TABLE finance_customer ADD COLUMN payment_terms VARCHAR(80) NULL AFTER credit_limit`,
               `ALTER TABLE finance_bank_account ADD COLUMN branch VARCHAR(120) NULL AFTER ifsc`,
               `ALTER TABLE finance_bank_account ADD COLUMN account_type VARCHAR(40) NULL AFTER branch`,
               `ALTER TABLE finance_bill ADD COLUMN due_date DATE NULL AFTER bill_date`,
               `ALTER TABLE finance_invoice ADD COLUMN due_date DATE NULL AFTER invoice_date`
             ];
             for (const ddl of financeUpgrades) {
               try {
                 await connection.query(ddl);
               } catch (_) {}
             }

              // HR Category Master table & EMPLOYEE link
              await connection.query(`
                CREATE TABLE IF NOT EXISTS hr_categories (
                  category_id INT AUTO_INCREMENT PRIMARY KEY,
                  company_id INT NOT NULL,
                  category_name VARCHAR(100) NOT NULL,
                  category_code VARCHAR(30) NOT NULL,
                  description VARCHAR(255) NULL,
                  is_active TINYINT(1) NOT NULL DEFAULT 1,
                  created_by INT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                  UNIQUE KEY uk_hrcat_company_code (company_id, category_code),
                  INDEX idx_hrcat_company_active (company_id, is_active)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
              `);
              try {
                await connection.query(`ALTER TABLE employee ADD COLUMN hr_category_id INT NULL`);
              } catch (e) {
                if (e.code !== 'ER_DUP_FIELDNAME') {
                  try {
                    await connection.query(`ALTER TABLE EMPLOYEE ADD COLUMN hr_category_id INT NULL`);
                  } catch (e2) {
                    if (e2.code !== 'ER_DUP_FIELDNAME') {
                      console.error('hr_category_id migration warning:', e2.message);
                    }
                  }
                }
              }

                await connection.query(`
                  CREATE TABLE IF NOT EXISTS salary_template_items (
                    item_id INT AUTO_INCREMENT PRIMARY KEY,
                    company_id INT NOT NULL,
                    template_id INT NOT NULL,
                    component_id INT NOT NULL,
                    calc_mode ENUM('FIXED', 'PERCENT_OF_BASIC') NOT NULL DEFAULT 'FIXED',
                    value_override DECIMAL(15,2) NOT NULL DEFAULT 0.00,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uk_sti_tpl_comp (template_id, component_id),
                    INDEX idx_sti_tpl (template_id)
                  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                `);
                try {
                  await connection.query('ALTER TABLE hr_categories ADD COLUMN default_template_id INT NULL AFTER description');
                } catch (_) {}
                try {
                  await connection.query('ALTER TABLE hr_categories ADD COLUMN default_gross DECIMAL(15,2) NULL AFTER default_template_id');
                } catch (_) {}

    console.log('✅ Master Database tables & columns verified!');
    connection.release();
  } catch (error) {
    console.error('❌ MySQL Connection Failed:', error.message);
    console.log('💡 Note: Ensure MySQL Server is running and .env has the right username/password.');
  }
}


testConnection();

module.exports = pool;
