const db = require('../../config/db');
const xlsx = require('xlsx');
const jwt = require('jsonwebtoken');
const { resolveCompanyId, resolveRequesterInfo } = require('../../utils/tenant');
const { getDefaultPermissions } = require('../../utils/permissions');
const { buildLeaveDateFilter } = require('../../utils/leave_filter');
const {
  findHeaderIndex,
  unpackRows,
  formatPreviewValue,
  parseDate,
  parseTime,
  getNormalizedValue,
} = require('../../utils/attendance_parser');

// Ensure error_logs column exists in ATTENDANCE_IMPORT
(async () => {
  try {
    await db.query("ALTER TABLE ATTENDANCE_IMPORT ADD COLUMN error_logs TEXT NULL");
  } catch (_) {}
})();

// Ensure role column exists in EMPLOYEE table
(async () => {
  try {
    await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
  } catch (_) {}
})();

// 1. ADD NEW EMPLOYEE
exports.addEmployee = async (req, res) => {
  try {
    const {
      company_id,
      branch_id,
      department_id,
      emp_code,
      biometric_emp_code,
      full_name,
      designation,
      role,
      phone,
      email,
      join_date,
      employment_type,
      weekly_off,
      salary_grade,
      salary_base,
      age,
      gender,
      dob,
      city,
      state,
      address,
      aadhar_number,
      pan_number,
      emergency_contact,
      leave_balance_casual,
      leave_balance_sick,
      leave_balance_paid,
      unpaid_leave_limit,
      unpaid_leave_per_day_deduction,
      manager_module,
      // Optional Login Account Fields for Step 5
      create_login,
      login_email,
      login_password,
      login_role,
      login_status
    } = req.body;

    if (!emp_code || !full_name || !department_id) {
      return res.status(400).json({
        success: false,
        message: 'Employee Code, Full Name, and Department are required.'
      });
    }

    // Validate login details if login account requested
    const wantLogin = Boolean(create_login || (login_email && login_password));
    const targetLoginEmail = (login_email || email || '').trim();
    if (wantLogin) {
      if (!targetLoginEmail) {
        return res.status(400).json({
          success: false,
          message: 'Login Email is required when creating a login account.'
        });
      }
      if (!login_password || login_password.trim().length < 6) {
        return res.status(400).json({
          success: false,
          message: 'Initial password must be at least 6 characters long.'
        });
      }
      const [existingUser] = await db.query('SELECT user_id FROM USER WHERE email = ?', [targetLoginEmail]);
      if (existingUser.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'This login email is already in use by another user account.'
        });
      }
    }

    // Auto ensure columns exist in EMPLOYEE table
    const safeColumns = [
      "ALTER TABLE EMPLOYEE ADD COLUMN employment_type VARCHAR(50) DEFAULT 'Permanent'",
      "ALTER TABLE EMPLOYEE ADD COLUMN weekly_off VARCHAR(50) DEFAULT 'Sunday'",
      "ALTER TABLE EMPLOYEE ADD COLUMN salary_grade VARCHAR(50) DEFAULT 'Grade B'",
      "ALTER TABLE EMPLOYEE ADD COLUMN salary_base DECIMAL(12,2) DEFAULT 35000.00",
      "ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_casual INT DEFAULT 12",
      "ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_sick INT DEFAULT 8",
      "ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_paid INT DEFAULT 15",
      "ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'",
      "ALTER TABLE EMPLOYEE ADD COLUMN age INT NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN gender VARCHAR(20) DEFAULT 'Male'",
      "ALTER TABLE EMPLOYEE ADD COLUMN dob DATE NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN city VARCHAR(100) NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN state VARCHAR(100) NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN address TEXT NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN aadhar_number VARCHAR(30) NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN pan_number VARCHAR(30) NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN emergency_contact VARCHAR(50) NULL",
      "ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_limit INT DEFAULT 10",
      "ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_per_day_deduction DECIMAL(12,2) DEFAULT 0.00"
    ];
    for (const colSql of safeColumns) {
      try { await db.query(colSql); } catch (_) {}
    }

    // Check duplicate emp_code or biometric_emp_code
    let checkSql = 'SELECT employee_id FROM EMPLOYEE WHERE emp_code = ?';
    let checkParams = [emp_code];
    if (biometric_emp_code && biometric_emp_code.toString().trim() !== '') {
      checkSql += ' OR biometric_emp_code = ?';
      checkParams.push(biometric_emp_code.toString().trim());
    }
    const [existing] = await db.query(checkSql, checkParams);

    if (existing.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Employee Code or Biometric Machine ID already registered!'
      });
    }

    // Resolve company_id & branch_id
    let effCompanyId = resolveCompanyId(req) || company_id;
    let effBranchId = branch_id;
    if (!effCompanyId || !effBranchId) {
      try {
        const [deptRows] = await db.query('SELECT company_id, branch_id FROM DEPARTMENT WHERE department_id = ?', [department_id]);
        if (deptRows.length > 0) {
          if (!effCompanyId && deptRows[0].company_id) effCompanyId = deptRows[0].company_id;
          if (!effBranchId && deptRows[0].branch_id) effBranchId = deptRows[0].branch_id;
        }
      } catch (_) {}
    }
    effCompanyId = effCompanyId || 1;
    effBranchId = effBranchId || 1;

    const calculatedPerDayDeduction = (unpaid_leave_per_day_deduction !== undefined && unpaid_leave_per_day_deduction !== '' && unpaid_leave_per_day_deduction !== null)
      ? parseFloat(unpaid_leave_per_day_deduction)
      : (salary_base ? (parseFloat(salary_base) / 30.0) : 0.00);

    const [result] = await db.query(
      `INSERT INTO EMPLOYEE
       (company_id, branch_id, department_id, emp_code, biometric_emp_code, full_name, designation, role, phone, email, join_date, status,
        employment_type, weekly_off, salary_grade, salary_base,
        age, gender, dob, city, state, address, aadhar_number, pan_number, emergency_contact,
        leave_balance_casual, leave_balance_sick, leave_balance_paid, unpaid_leave_limit, unpaid_leave_per_day_deduction)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        effCompanyId,
        effBranchId,
        department_id,
        emp_code,
        biometric_emp_code ? biometric_emp_code.toString().trim() : null,
        full_name,
        designation || 'Staff',
        role || 'Employee',
        phone || null,
        email || null,
        join_date || new Date(),
        employment_type || 'Permanent',
        weekly_off || 'Sunday',
        salary_grade || 'Grade B',
        salary_base ? parseFloat(salary_base) : 35000.00,
        age ? parseInt(age) : null,
        gender || 'Male',
        dob || null,
        city || null,
        state || null,
        address || null,
        aadhar_number || null,
        pan_number || null,
        emergency_contact || null,
        leave_balance_casual !== undefined && leave_balance_casual !== '' ? parseInt(leave_balance_casual) : 12,
        leave_balance_sick !== undefined && leave_balance_sick !== '' ? parseInt(leave_balance_sick) : 8,
        leave_balance_paid !== undefined && leave_balance_paid !== '' ? parseInt(leave_balance_paid) : 15,
        unpaid_leave_limit !== undefined && unpaid_leave_limit !== '' ? parseInt(unpaid_leave_limit) : 10,
        calculatedPerDayDeduction
      ]
    );

    const newEmpId = result.insertId;
    let newUserId = null;

    if (wantLogin) {
      try {
        const bcrypt = require('bcryptjs');
        const passwordHash = await bcrypt.hash(login_password.trim(), 10);
        const targetRole = login_role || role || 'Employee';

        let [roleRows] = await db.query(
          'SELECT role_id FROM ROLE WHERE company_id = ? AND name = ? LIMIT 1',
          [effCompanyId, targetRole]
        );
        if (roleRows.length === 0) {
          [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [targetRole]);
        }
        let roleId = roleRows.length > 0 ? roleRows[0].role_id : null;
        if (!roleId) {
          const [newRole] = await db.query('INSERT INTO ROLE (company_id, name) VALUES (?, ?)', [effCompanyId, targetRole]);
          roleId = newRole.insertId;
        }

        const isUserActive = (login_status === 'Active' || login_status === true || login_status === 1 || !login_status) ? 1 : 0;

        const [userResult] = await db.query(
          `INSERT INTO USER (company_id, role_id, email, password_hash, is_active)
           VALUES (?, ?, ?, ?, ?)`,
          [effCompanyId, roleId, targetLoginEmail, passwordHash, isUserActive]
        );
        newUserId = userResult.insertId;

        await db.query(
          'UPDATE EMPLOYEE SET user_id = ?, email = COALESCE(email, ?), role = ? WHERE employee_id = ?',
          [newUserId, targetLoginEmail, targetRole, newEmpId]
        );
      } catch (loginErr) {
        console.error('Failed to create login account during onboarding:', loginErr);
      }
    }

    // Auto-populate initial filtered permissions based on role & department!
    try {
      await db.query(`
        CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
          employee_id INT NOT NULL,
          permission_key VARCHAR(60) NOT NULL,
          is_granted TINYINT(1) DEFAULT 1,
          PRIMARY KEY (employee_id, permission_key),
          CONSTRAINT fk_emp_perm FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
      `);

      let deptName = '';
      try {
        const [dRows] = await db.query('SELECT name FROM DEPARTMENT WHERE department_id = ?', [department_id]);
        if (dRows.length > 0) deptName = dRows[0].name;
      } catch (_) {}

      const initialPerms = getDefaultPermissions(login_role || role || 'Employee', deptName, manager_module);
      for (const [permKey, isGranted] of Object.entries(initialPerms)) {
        await db.query(
          `INSERT INTO EMPLOYEE_PERMISSION (employee_id, permission_key, is_granted)
           VALUES (?, ?, ?)
           ON DUPLICATE KEY UPDATE is_granted = VALUES(is_granted)`,
          [newEmpId, permKey, isGranted ? 1 : 0]
        );
      }
    } catch (permErr) {
      console.error('Failed to populate initial permissions on onboarding:', permErr);
    }

    return res.status(201).json({
      success: true,
      message: wantLogin && newUserId
        ? 'Employee onboarded and ERP login account created successfully!'
        : 'Employee successfully onboarded!',
      employee_id: newEmpId,
      user_id: newUserId
    });

  } catch (error) {
    console.error('Add Employee Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};
// Ensure Super Admin & Admin user accounts have a linked record in EMPLOYEE table
async function ensureAdminEmployeeRecords() {
  try {
    const [usersWithoutEmployee] = await db.query(
      `SELECT u.user_id, u.email, u.company_id, r.name as role_name
       FROM USER u
       JOIN ROLE r ON u.role_id = r.role_id
       WHERE u.is_active = 1
       AND NOT EXISTS (
         SELECT 1 FROM EMPLOYEE e WHERE e.user_id = u.user_id OR (e.email = u.email AND e.email IS NOT NULL AND e.email != '')
       )`
    );

    for (const u of usersWithoutEmployee) {
      const rawName = u.email ? u.email.split('@')[0] : 'Admin';
      const cleanName = rawName.charAt(0).toUpperCase() + rawName.slice(1);
      const isSuper = u.role_name === 'Super Admin' || u.role_name === 'Admin';
      const codePrefix = isSuper ? 'ADM' : 'EMP';
      const empCode = `${codePrefix}-${String(u.user_id).padStart(3, '0')}`;
      const designation = isSuper ? 'System Administrator' : (u.role_name || 'Staff');

      let branchId = null;
      try {
        const [bRows] = await db.query('SELECT branch_id FROM BRANCH WHERE company_id = ? LIMIT 1', [u.company_id]);
        if (bRows.length > 0) {
          branchId = bRows[0].branch_id;
        } else if (u.company_id) {
          // EMPLOYEE.branch_id is NOT NULL; create a default branch for legacy/company-setup gaps.
          const [branchInsert] = await db.query(
            'INSERT INTO BRANCH (company_id, name, address) VALUES (?, ?, ?)',
            [u.company_id, 'Head Office', 'Main Office']
          );
          branchId = branchInsert.insertId;
        }
      } catch (_) {}

      if (!branchId) {
        console.warn(`[AutoSync] Skipping employee auto-create for user ${u.user_id}: no branch available.`);
        continue;
      }

      let deptId = null;
      try {
        const [dRows] = await db.query('SELECT department_id FROM DEPARTMENT WHERE company_id = ? LIMIT 1', [u.company_id]);
        if (dRows.length > 0) deptId = dRows[0].department_id;
      } catch (_) {}

      await db.query(
        `INSERT INTO EMPLOYEE
         (company_id, user_id, branch_id, department_id, emp_code, full_name, designation, role, email, status, join_date, employment_type)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', CURDATE(), 'Permanent')`,
        [u.company_id, u.user_id, branchId, deptId, empCode, cleanName, designation, u.role_name, u.email]
      );
    }

    // Link any employee whose email matches an active user but user_id was null
    try {
      await db.query(
        `UPDATE EMPLOYEE e
         JOIN USER u ON e.email = u.email
         SET e.user_id = u.user_id, e.company_id = u.company_id
         WHERE e.user_id IS NULL AND e.email IS NOT NULL AND e.email != ''`
      );
    } catch (_) {}

    // Synchronize company_id between USER and EMPLOYEE to guarantee multi-tenant company isolation
    try {
      await db.query(
        `UPDATE EMPLOYEE e
         JOIN USER u ON e.user_id = u.user_id
         SET e.company_id = u.company_id
         WHERE u.company_id IS NOT NULL AND (e.company_id IS NULL OR e.company_id != u.company_id)`
      );
    } catch (_) {}
  } catch (err) {
    console.warn('[AutoSync] Error ensuring admin employee records:', err.message);
  }
}

// 2. GET ALL EMPLOYEES (With Lifecycle & Phone/Email details)
exports.getEmployees = async (req, res) => {
  try {
    await ensureAdminEmployeeRecords();
    const companyId = resolveCompanyId(req);
    if (companyId) await ensureHrCategoriesSetup(companyId).catch(() => {});
    let whereClause = '';
    const params = [];
    if (companyId) {
      whereClause = 'WHERE (e.company_id = ? OR (e.company_id IS NULL AND u.company_id = ?))';
      params.push(companyId, companyId);
    } else {
      whereClause = 'WHERE 1 = 0';
    }

    let employees = [];
    try {
      const [rows] = await db.query(
        `SELECT e.employee_id, e.user_id, e.emp_code, e.biometric_emp_code, e.full_name, e.designation, e.status,
                e.phone, e.email, e.exit_date, e.exit_reason, e.department_id, e.hr_category_id, e.branch_id, e.company_id,
                e.salary_base, e.salary_grade,
                COALESCE(r.name, e.role, 'Employee') AS role_name,
                d.name as department_name, b.name as branch_name
         FROM EMPLOYEE e
         LEFT JOIN USER u ON e.user_id = u.user_id
         LEFT JOIN ROLE r ON u.role_id = r.role_id
         LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
         LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
         ${whereClause}
         ORDER BY e.employee_id DESC`,
        params
      );
      employees = rows;
    } catch (_) {
      try {
        await db.query('ALTER TABLE employee ADD COLUMN hr_category_id INT NULL');
      } catch (__) {
        try { await db.query('ALTER TABLE EMPLOYEE ADD COLUMN hr_category_id INT NULL'); } catch (___) {}
      }
      const [rows] = await db.query(
        `SELECT e.employee_id, e.user_id, e.emp_code, e.biometric_emp_code, e.full_name, e.designation, e.status,
                e.phone, e.email, e.exit_date, e.exit_reason, e.department_id, NULL AS hr_category_id, e.branch_id, e.company_id,
                e.salary_base, e.salary_grade,
                COALESCE(r.name, 'Employee') AS role_name,
                d.name as department_name, b.name as branch_name
         FROM EMPLOYEE e
         LEFT JOIN USER u ON e.user_id = u.user_id
         LEFT JOIN ROLE r ON u.role_id = r.role_id
         LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
         LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
         ${whereClause}
         ORDER BY e.employee_id DESC`,
        params
      );
      employees = rows;
    }

    return res.status(200).json({
      success: true,
      data: employees
    });
  } catch (error) {
    console.error('Get Employees Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

// 3. GET STATS

  // 2.1 UPDATE EMPLOYEE ROLE (Promote to Module Manager / Admin / Employee)
  exports.updateEmployeeRole = async (req, res) => {
    try {
      const { id } = req.params;
      const { role_name, manager_module } = req.body;

      if (!role_name) {
        return res.status(400).json({ success: false, message: 'Role name is required.' });
      }

      try {
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
      } catch (_) {}

      await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [role_name, id]);

      const [empRows] = await db.query('SELECT user_id, department_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (empRows.length > 0 && empRows[0].user_id) {
        const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role_name]);
        if (roleRows.length > 0) {
          await db.query('UPDATE USER SET role_id = ? WHERE user_id = ?', [roleRows[0].role_id, empRows[0].user_id]);
        }
      }

      // Automatically reset permissions to new role default
      try {
        let deptName = '';
        if (empRows.length > 0 && empRows[0].department_id) {
          const [dRows] = await db.query('SELECT name FROM DEPARTMENT WHERE department_id = ?', [empRows[0].department_id]);
          if (dRows.length > 0) deptName = dRows[0].name;
        }
        const updatedPerms = getDefaultPermissions(role_name, deptName, manager_module);
        for (const [permKey, isGranted] of Object.entries(updatedPerms)) {
          await db.query(
            `INSERT INTO EMPLOYEE_PERMISSION (employee_id, permission_key, is_granted)
             VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE is_granted = VALUES(is_granted)`,
            [id, permKey, isGranted ? 1 : 0]
          );
        }
      } catch (_) {}

      return res.status(200).json({
        success: true,
        message: `Employee role updated to ${role_name} successfully!`,
        role_name
      });
    } catch (error) {
      console.error('Update Employee Role Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

exports.getEmployeeStats = async (req, res) => {
  try {
    await ensureAdminEmployeeRecords().catch(err => console.warn('[Stats] ensureAdmin error:', err.message));
    const companyId = resolveCompanyId(req);
    let sql = "SELECT COUNT(*) as total FROM EMPLOYEE WHERE status = 'active'";
    const params = [];
    if (companyId) {
      sql += ' AND (company_id = ? OR (company_id IS NULL AND user_id IN (SELECT user_id FROM USER WHERE company_id = ?)))';
      params.push(companyId, companyId);
    }
    const [result] = await db.query(sql, params);
    return res.status(200).json({ success: true, total: result && result[0] ? result[0].total : 0 });
  } catch (error) {
    console.error('[Stats] Error:', error.message);
    return res.status(200).json({ success: true, total: 0 });
  }
};

// ================= 4.1 TEAM REAL-TIME PERFORMANCE SUMMARY =================
exports.getTeamPerformanceSummary = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req);
    if (!companyId) {
      return res.status(200).json({
        success: true,
        data: {
          appraisal_index: 0.0,
          attendance_rate: 0.0,
          task_rate: 0.0,
          quality_rate: 0.0,
          total_attendance_days: 0,
          present_days: 0,
          total_tasks: 0,
          completed_tasks: 0,
          total_projects: 0,
          completed_projects: 0
        }
      });
    }

    // 1. Attendance stats for this company
    const [attRows] = await db.query(`
      SELECT
        COUNT(*) as total_days,
        SUM(CASE WHEN LOWER(status) = 'present' THEN 1 ELSE 0 END) as present_days
      FROM ATTENDANCE
      WHERE (company_id = ? OR employee_id IN (SELECT employee_id FROM EMPLOYEE WHERE company_id = ?))
    `, [companyId, companyId]);

    const totalDays = Number(attRows[0]?.total_days) || 0;
    const presentDays = Number(attRows[0]?.present_days) || 0;
    const attendanceRate = totalDays > 0 ? Number(((presentDays / totalDays) * 100).toFixed(1)) : 0.0;

    // 2. Task stats for this company
    const [taskRows] = await db.query(`
      SELECT
        COUNT(*) as total_tasks,
        SUM(CASE WHEN UPPER(status) = 'DONE' THEN 1 ELSE 0 END) as completed_tasks
      FROM task
      WHERE (company_id = ? OR project_id IN (SELECT project_id FROM project WHERE company_id = ?))
    `, [companyId, companyId]);

    const totalTasks = Number(taskRows[0]?.total_tasks) || 0;
    const completedTasks = Number(taskRows[0]?.completed_tasks) || 0;
    const taskRate = totalTasks > 0 ? Number(((completedTasks / totalTasks) * 100).toFixed(1)) : 0.0;

    // 3. Project stats for this company
    const [prjRows] = await db.query(`
      SELECT
        COUNT(*) as total_projects,
        SUM(CASE WHEN LOWER(status) = 'completed' THEN 1 ELSE 0 END) as completed_projects
      FROM project
      WHERE company_id = ?
    `, [companyId]);

    const totalProjects = Number(prjRows[0]?.total_projects) || 0;
    const completedProjects = Number(prjRows[0]?.completed_projects) || 0;
    const qualityRate = totalProjects > 0 ? Number(((completedProjects / totalProjects) * 100).toFixed(1)) : (totalTasks > 0 ? taskRate : 0.0);

    // 4. Overall Appraisal Index
    let appraisalIndex = 0.0;
    const activeMetrics = [];
    if (totalDays > 0) activeMetrics.push(attendanceRate);
    if (totalTasks > 0) activeMetrics.push(taskRate);
    if (totalProjects > 0) activeMetrics.push(qualityRate);

    if (activeMetrics.length > 0) {
      const sum = activeMetrics.reduce((a, b) => a + b, 0);
      appraisalIndex = Number((sum / activeMetrics.length).toFixed(1));
    }

    return res.status(200).json({
      success: true,
      data: {
        appraisal_index: appraisalIndex,
        attendance_rate: attendanceRate,
        task_rate: taskRate,
        quality_rate: qualityRate,
        total_attendance_days: totalDays,
        present_days: presentDays,
        total_tasks: totalTasks,
        completed_tasks: completedTasks,
        total_projects: totalProjects,
        completed_projects: completedProjects
      }
    });
  } catch (error) {
    console.error('Get Team Performance Error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4.0 BIOMETRIC EXCEL LIVE PREVIEW (Excel/CSV ko open karke table data bhejna)
exports.previewBiometricSheet = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Please upload an Excel or CSV file.' });
    }

    const workbook = xlsx.read(req.file.buffer, { type: 'buffer', cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const sheet = workbook.Sheets[sheetName];
    const aoa = xlsx.utils.sheet_to_json(sheet, { header: 1, defval: '' });
    const headerIdx = findHeaderIndex(aoa);
    const { headers, rows } = unpackRows(aoa, headerIdx);

    if (headerIdx < 0 || rows.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Could not find attendance headers (Emp Code / UserID / Date / Punch1) in this file.',
      });
    }

    // Same parser as upload: local dates/times, no UTC shift or 1899 dates.
    const previewRows = rows.slice(0, 100).map((row) =>
      headers.map((header) => formatPreviewValue(row[header])),
    );

    return res.status(200).json({
      success: true,
      fileName: req.file.originalname,
      sheetName,
      totalRows: rows.length,
      headers,
      previewRows
    });
  } catch (error) {
    console.error('Preview Biometric Sheet Error:', error);
    return res.status(500).json({ success: false, message: 'Failed to read file: ' + error.message });
  }
};

// 4. BIOMETRIC EXCEL BULK ATTENDANCE UPLOAD (Clean & Working)
exports.uploadBiometricSheet = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Please upload an Excel or CSV file.' });
    }

    // A. Read Excel buffer safely
    const workbook = xlsx.read(req.file.buffer, { type: 'buffer', cellDates: true });
    const sheet = workbook.Sheets[workbook.SheetNames[0]];

    // Same header detection/unpacking as the live preview endpoint. This is
    // critical: previously preview showed one thing while upload stored another.
    const startedAt = Date.now();
    const aoa = xlsx.utils.sheet_to_json(sheet, { header: 1, defval: '' });
    const headerIndex = findHeaderIndex(aoa);
    const { headers, rows: sheetData } = unpackRows(aoa, headerIndex);

    if (headerIndex < 0 || sheetData.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Uploaded file has no recognizable attendance data. Expected columns like Emp Code / UserID, Date / ProcessDate and Punch1 / In Time.',
      });
    }

    const companyId = resolveCompanyId(req) || 1;
    const requester = await resolveRequesterInfo(req);
    const uploadedBy = requester.userId || 1;

    const terminalLogs = [
      `[INIT] File staged: ${req.file.originalname} | Sheet: ${workbook.SheetNames[0]}`,
      `[HEADER] Row ${headerIndex + 1}: ${headers.join(' | ')}`,
      `[PARSE] ${sheetData.length} data row(s) detected.`,
    ];

    // B. Save Audit Record in ATTENDANCE_IMPORT table (company-scoped)
    const [importResult] = await db.query(
      `INSERT INTO ATTENDANCE_IMPORT (company_id, uploaded_by, file_name, total_records)
       VALUES (?, ?, ?, ?)`,
      [companyId, uploadedBy, req.file.originalname, sheetData.length]
    );
    const importId = importResult.insertId;

    let successCount = 0;
    let failedCount = 0;
    const errors = [];
    let detectedMonth = null;
    let detectedYear = null;

    const toMinutes = (value) => {
      if (value === null || value === undefined) return 0;
      if (typeof value === 'number') return Number.isFinite(value) ? Math.round(value) : 0;
      const text = String(value).trim();
      const clock = text.match(/^(\d{1,2}):(\d{2})/);
      if (clock) return parseInt(clock[1], 10) * 60 + parseInt(clock[2], 10);
      const number = parseFloat(text);
      return Number.isFinite(number) ? number : 0;
    };

    const normaliseSheetStatus = (value) => {
      const text = String(value ?? '').trim().toLowerCase();
      if (['present', 'p', 'ok', 'yes'].includes(text)) return 'Present';
      if (['late', 'l'].includes(text)) return 'Late';
      if (['half-day', 'half day', 'halfday', 'hd'].includes(text)) return 'Half-Day';
      if (['absent', 'a', 'no'].includes(text)) return 'Absent';
      return null;
    };

    // C. Process each row
    for (let i = 0; i < sheetData.length; i++) {
      const rawRow = sheetData[i];
      const rowNo = headerIndex + i + 2;

      const bioCodeRaw = getNormalizedValue(rawRow, ['userid', 'empcode', 'empid', 'id', 'enrollid', 'badgenumber']);
      if (!bioCodeRaw) {
        failedCount++;
        const message = `Row ${rowNo}: missing Emp Code / UserID, skipped.`;
        errors.push(message);
        terminalLogs.push(`[SKIP] ${message}`);
        continue;
      }
      const bioCode = String(bioCodeRaw).trim();

      const userName = getNormalizedValue(rawRow, ['username', 'name', 'fullname', 'employeename']);
      const rawDate = getNormalizedValue(rawRow, ['processdate', 'date', 'workdate']);
      const dateInfo = parseDate(rawDate);
      if (!dateInfo) {
        failedCount++;
        const message = `Row ${rowNo} (${bioCode}): invalid or missing date "${String(rawDate ?? '')}", skipped.`;
        errors.push(message);
        terminalLogs.push(`[SKIP] ${message}`);
        continue;
      }
      const cleanDate = dateInfo.cleanDate;

      if (!detectedMonth) {
        detectedMonth = dateInfo.month;
        detectedYear = dateInfo.year;
      }

      const rawIn = getNormalizedValue(rawRow, ['punch1', 'intime', 'checkin', 'in']);
      const rawOut = getNormalizedValue(rawRow, ['punch2', 'outtime', 'checkout', 'out']);
      const inTime = parseTime(rawIn);
      const outTime = parseTime(rawOut);

      const lateIn = toMinutes(getNormalizedValue(rawRow, ['latein', 'late']));
      const workMinutes = toMinutes(getNormalizedValue(rawRow, ['worktime', 'workminutes', 'duration']));
      const rawOvertime = getNormalizedValue(rawRow, ['overtime', 'ot']);
      let overtimeHours = 0;
      if (rawOvertime !== null) {
        const otText = String(rawOvertime).trim();
        if (otText.includes(':')) {
          overtimeHours = toMinutes(otText) / 60;
        } else {
          const otNumber = parseFloat(otText);
          if (Number.isFinite(otNumber)) overtimeHours = otNumber > 24 ? otNumber / 60 : otNumber;
        }
      }

      // Match employee by biometric code within the same company only.
      const bioCodeNoZero = bioCode.replace(/^0+/, '');
      let empRows = [];

      const [byCode] = await db.query(
        `SELECT employee_id, full_name, biometric_emp_code FROM EMPLOYEE
         WHERE (biometric_emp_code = ? OR emp_code = ? OR biometric_emp_code = ? OR emp_code = ?)
           AND (company_id = ? OR company_id IS NULL)`,
        [bioCode, bioCode, bioCodeNoZero, bioCodeNoZero, companyId]
      );
      empRows = byCode;

      if (empRows.length === 0 && userName && String(userName).trim() !== '') {
        const trimmedName = String(userName).trim();
        const [byName] = await db.query(
          `SELECT employee_id, full_name, biometric_emp_code FROM EMPLOYEE
           WHERE (full_name LIKE ? OR full_name LIKE ?)
             AND (company_id = ? OR company_id IS NULL)`,
          [`%${trimmedName}%`, trimmedName, companyId]
        );
        const exact = byName.filter(
          (emp) => String(emp.full_name).trim().toLowerCase() === trimmedName.toLowerCase(),
        );
        empRows = exact.length > 0 ? exact : byName;
        if (empRows.length > 0) {
          await db.query(
            'UPDATE EMPLOYEE SET biometric_emp_code = ? WHERE employee_id = ? AND (biometric_emp_code IS NULL OR biometric_emp_code = "")',
            [bioCode, empRows[0].employee_id]
          );
        }
      }

      if (empRows.length === 0) {
        failedCount++;
        const message = `Row ${rowNo}: Staff '${userName || bioCode}' (Machine ID: ${bioCode}) not registered in system.`;
        errors.push(message);
        terminalLogs.push(`[SKIP] ${message}`);
        continue;
      }

      const employee = empRows[0];
      const employeeId = employee.employee_id;
      const attSettings = await getOrCreateAttendanceSettings(companyId);

      // Prefer the sheet's own status; otherwise derive it from rules & leaves.
      let status = normaliseSheetStatus(getNormalizedValue(rawRow, ['status']));
      if (!status) {
        let isApprovedLeave = false;
        if (Number(attSettings.enable_leave_integration ?? 1) === 1) {
          try {
            const [leaveRows] = await db.query(
              `SELECT leave_id FROM LEAVE_REQUEST
               WHERE employee_id = ? AND status = 'APPROVED' AND ? BETWEEN start_date AND end_date LIMIT 1`,
              [employeeId, cleanDate]
            );
            if (leaveRows.length > 0) isApprovedLeave = true;
          } catch (_) {}
        }

        const monthPrefix = cleanDate.slice(0, 7); // 'YYYY-MM'
        const [lateRows] = await db.query(
          `SELECT COUNT(*) AS cnt FROM ATTENDANCE
           WHERE employee_id = ? AND DATE_FORMAT(work_date, '%Y-%m') = ? AND status = 'Late' AND work_date != ?`,
          [employeeId, monthPrefix, cleanDate]
        );
        const priorLateCount = Number(lateRows[0]?.cnt || 0);

        const computed = computeStatusFromRules({
          inTime,
          outTime,
          workMinutes,
          lateIn,
          settings: attSettings,
          priorLateCountThisMonth: priorLateCount,
          isApprovedLeave,
          isSunday: new Date(`${cleanDate}T00:00:00`).getDay() === 0,
        });
        status = computed.status;
        if (overtimeHours === 0 && computed.overtimeHours > 0) {
          overtimeHours = computed.overtimeHours;
        }
      }

      const fullCheckIn = inTime ? `${cleanDate} ${inTime}` : null;
      const fullCheckOut = outTime ? `${cleanDate} ${outTime}` : null;

      // Upsert into ATTENDANCE
      const [existing] = await db.query(
        'SELECT attendance_id FROM ATTENDANCE WHERE employee_id = ? AND work_date = ?',
        [employeeId, cleanDate]
      );

      if (existing.length > 0) {
        await db.query(
          'UPDATE ATTENDANCE SET check_in = ?, check_out = ?, status = ?, overtime_hours = ?, import_id = ? WHERE attendance_id = ?',
          [fullCheckIn, fullCheckOut, status, overtimeHours, importId, existing[0].attendance_id]
        );
      } else {
        await db.query(
          'INSERT INTO ATTENDANCE (employee_id, work_date, check_in, check_out, status, overtime_hours, import_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [employeeId, cleanDate, fullCheckIn, fullCheckOut, status, overtimeHours, importId]
        );
      }

      successCount++;
      terminalLogs.push(
        `[OK] Row ${rowNo}: ${employee.full_name || bioCode} | ${cleanDate} | In ${inTime || '--:--'} | Out ${outTime || '--:--'} | ${status}`,
      );
      if (!inTime || !outTime) {
        terminalLogs.push(`[WARN] Row ${rowNo}: one or both punch times are missing; stored as blank.`);
      }
    }

    errors.forEach((error) => {
      if (!String(error).startsWith('Row ')) terminalLogs.push(`[WARN] ${error}`);
    });

    // Update audit using columns that exist in the committed schema.
    await db.query(
      'UPDATE ATTENDANCE_IMPORT SET success_count = ?, error_log = ? WHERE import_id = ?',
      [successCount, JSON.stringify(errors.slice(0, 50)), importId]
    );

    const executionMs = Date.now() - startedAt;
    terminalLogs.push(
      `[COMPLETE] Synchronization finished: ${successCount} Synced, ${failedCount} Skipped/Unmatched. Total: ${sheetData.length}. Time: ${executionMs}ms.`,
    );

    return res.status(200).json({
      success: true,
      message: successCount === 0
        ? `No attendance rows were synced. ${failedCount} row(s) were skipped — check the terminal log.`
        : `Processed ${sheetData.length} records: ${successCount} Success, ${failedCount} Errors.`,
      importedMonth: detectedMonth,
      importedYear: detectedYear,
      summary: { totalRows: sheetData.length, successCount, failedCount, errors, executionMs },
      logs: terminalLogs
    });

  } catch (error) {
    console.error('❌ Excel Upload Detailed Error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 5. Apply Leave with Smart Paid/Unpaid Connected Lifecycle
exports.applyLeave = async (req, res) => {
  try {
    const { company_id, employee_id, leave_type, start_date, end_date, total_days, reason } = req.body;

    if (!employee_id || !leave_type || !start_date || !end_date) {
      return res.status(400).json({ success: false, message: 'Please fill all required leave details.' });
    }

    // Ensure columns exist in tables (handling both Linux base tables and Windows tables)
    try {
      await db.query("ALTER TABLE leave_request ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
      await db.query("ALTER TABLE leave_request ADD COLUMN paid_days INT DEFAULT 1");
      await db.query("ALTER TABLE leave_request ADD COLUMN unpaid_days INT DEFAULT 0");
      await db.query("ALTER TABLE leave_request ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {
      try {
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN paid_days INT DEFAULT 1");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN unpaid_days INT DEFAULT 0");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
      } catch (_) {}
    }
    try {
      await db.query("ALTER TABLE employee ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
      await db.query("ALTER TABLE employee ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {
      try {
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
      } catch (_) {}
    }

    // Fetch employee current leave balances & per-day deduction rate
    const [empRows] = await db.query(
      `SELECT employee_id, full_name, emp_code, user_id, salary_base,
              COALESCE(leave_balance_casual, 12) AS leave_balance_casual,
              COALESCE(leave_balance_sick, 8) AS leave_balance_sick,
              COALESCE(leave_balance_paid, 15) AS leave_balance_paid,
              COALESCE(unpaid_leave_limit, 10) AS unpaid_leave_limit,
              COALESCE(unpaid_leave_per_day_deduction, 0.00) AS unpaid_leave_per_day_deduction
       FROM EMPLOYEE WHERE employee_id = ?`,
      [employee_id]
    );

    if (empRows.length === 0) {
      return res.status(404).json({ success: false, message: 'Employee not found.' });
    }

    const emp = empRows[0];
    const totalDaysNum = parseInt(total_days) || 1;

    // Calculate total available paid leaves
    const casualLeft = Math.max(0, parseInt(emp.leave_balance_casual) || 0);
    const sickLeft = Math.max(0, parseInt(emp.leave_balance_sick) || 0);
    const paidLeft = Math.max(0, parseInt(emp.leave_balance_paid) || 0);
    const totalPaidAvailable = casualLeft + sickLeft + paidLeft;

    let paidDays = 0;
    let unpaidDays = 0;
    let isPaid = 1;

    // If explicitly requested as 'Unpaid Leave', all days are unpaid
    if (leave_type.toLowerCase().includes('unpaid')) {
      paidDays = 0;
      unpaidDays = totalDaysNum;
      isPaid = 0;
    } else {
      // 1. Paid leaves cut first!
      if (totalPaidAvailable >= totalDaysNum) {
        paidDays = totalDaysNum;
        unpaidDays = 0;
        isPaid = 1;
      } else {
        // 2. Paid leaves exhausted! Remaining days become Unpaid Leave (LWP)
        paidDays = totalPaidAvailable;
        unpaidDays = totalDaysNum - totalPaidAvailable;
        isPaid = (paidDays > 0 ? 1 : 0);
      }
    }

    // Per day deduction rate
    let dailyRate = parseFloat(emp.unpaid_leave_per_day_deduction);
    if (!dailyRate || dailyRate <= 0) {
      const base = parseFloat(emp.salary_base) || 35000.0;
      dailyRate = parseFloat((base / 30.0).toFixed(2));
    }
    const deductionAmount = parseFloat((unpaidDays * dailyRate).toFixed(2));

    // Insert Leave Request with calculated paid vs unpaid breakdown
    const [result] = await db.query(
      `INSERT INTO LEAVE_REQUEST
       (company_id, employee_id, leave_type, start_date, end_date, total_days, reason, status, is_paid, paid_days, unpaid_days, deduction_amount)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDING', ?, ?, ?, ?)`,
      [company_id || 1, employee_id, leave_type, start_date, end_date, totalDaysNum, reason || 'Personal Reason', isPaid, paidDays, unpaidDays, deductionAmount]
    );

    // Notification for Managers / Admins
    try {
      await ensureNotificationTable();
      let notifMessage = `${emp.full_name} (${emp.emp_code}) applied for ${totalDaysNum} day(s) ${leave_type} (${start_date} to ${end_date}).`;
      if (unpaidDays > 0) {
        notifMessage += ` (Paid: ${paidDays}d, Unpaid LWP: ${unpaidDays}d, Salary Cut: ₹${deductionAmount})`;
      } else {
        notifMessage += ` (100% Paid Leave, ₹0 Cut)`;
      }

      await db.query(`
        INSERT INTO NOTIFICATION (company_id, title, message, type, reference_id, target_role, sender_user_id)
        VALUES (?, ?, ?, 'LEAVE_REQUEST', ?, 'ADMIN_MANAGER', ?)
      `, [
        company_id || 1,
        'New Leave Application',
        notifMessage,
        result.insertId,
        emp.user_id
      ]);
    } catch (_) {}

    return res.status(201).json({
      success: true,
      message: 'Leave application submitted successfully.',
      data: {
        leave_id: result.insertId,
        total_days: totalDaysNum,
        paid_days: paidDays,
        unpaid_days: unpaidDays,
        deduction_amount: deductionAmount,
        is_paid: isPaid
      }
    });
  } catch (error) {
    console.error('Apply Leave Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

// 6. SAARE LEAVE APPLICATIONS DEKHNA (Get All Leaves with Paid/Unpaid Breakdown)
// 6. SAARE LEAVE APPLICATIONS DEKHNA (Get All Leaves with Paid/Unpaid Breakdown)
exports.getLeaves = async (req, res) => {
  try {
    try {
      await db.query("ALTER TABLE leave_request ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
      await db.query("ALTER TABLE leave_request ADD COLUMN paid_days INT DEFAULT 1");
      await db.query("ALTER TABLE leave_request ADD COLUMN unpaid_days INT DEFAULT 0");
      await db.query("ALTER TABLE leave_request ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {
      try {
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN paid_days INT DEFAULT 1");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN unpaid_days INT DEFAULT 0");
        await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
      } catch (_) {}
    }
    try {
      await db.query("ALTER TABLE employee ADD COLUMN leave_balance_casual INT DEFAULT 12");
      await db.query("ALTER TABLE employee ADD COLUMN leave_balance_sick INT DEFAULT 8");
      await db.query("ALTER TABLE employee ADD COLUMN leave_balance_paid INT DEFAULT 15");
      await db.query("ALTER TABLE employee ADD COLUMN unpaid_leave_limit INT DEFAULT 10");
      await db.query("ALTER TABLE employee ADD COLUMN unpaid_leave_per_day_deduction DECIMAL(12,2) DEFAULT 0.00");
      await db.query("ALTER TABLE employee ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
      await db.query("ALTER TABLE employee ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {
      try {
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_casual INT DEFAULT 12");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_sick INT DEFAULT 8");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_paid INT DEFAULT 15");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_limit INT DEFAULT 10");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_per_day_deduction DECIMAL(12,2) DEFAULT 0.00");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
      } catch (_) {}
    }

    const { employee_id, user_id, month, year, start_date, end_date } = req.query;
    const companyId = resolveCompanyId(req);

    let query = `
      SELECT l.leave_id, l.employee_id, l.leave_type, l.start_date, l.end_date, l.total_days, l.reason, l.status, l.created_at,
              COALESCE(l.is_paid, 1) as is_paid,
              COALESCE(l.paid_days, l.total_days) as paid_days,
              COALESCE(l.unpaid_days, 0) as unpaid_days,
              COALESCE(l.deduction_amount, 0.00) as deduction_amount,
              e.emp_code, e.full_name, e.designation, e.user_id,
              COALESCE(e.leave_balance_casual, 12) as leave_balance_casual,
              COALESCE(e.leave_balance_sick, 8) as leave_balance_sick,
              COALESCE(e.leave_balance_paid, 15) as leave_balance_paid,
              COALESCE(e.unpaid_leave_per_day_deduction, (e.salary_base / 30.0), 0.00) as unpaid_leave_per_day_deduction,
              d.name as department_name
       FROM LEAVE_REQUEST l
       JOIN EMPLOYEE e ON l.employee_id = e.employee_id
       LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
       WHERE 1=1
    `;
    const params = [];

    if (companyId) {
      query += ` AND (l.company_id = ? OR e.company_id = ?)`;
      params.push(companyId, companyId);
    }

    if (employee_id) {
      query += ` AND l.employee_id = ?`;
      params.push(employee_id);
    } else if (user_id) {
      query += ` AND e.user_id = ?`;
      params.push(user_id);
    }

    const dateFilter = buildLeaveDateFilter({ month, year, start_date, end_date });
    query += dateFilter.clause;
    params.push(...dateFilter.params);

    query += ` ORDER BY l.leave_id DESC`;

    const [leaves] = await db.query(query, params);

    return res.status(200).json({
      success: true,
      data: leaves
    });
  } catch (error) {
    console.error('Get Leaves Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

// 7. LEAVE APPROVE YA REJECT KARNA (Connected Quota Deduction & Restore on Reject)
exports.updateLeaveStatus = async (req, res) => {
  try {
    const { leaveId } = req.params;
    const { status, approved_by } = req.body; // status: 'APPROVED' ya 'REJECTED'

    if (!['APPROVED', 'REJECTED'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Status must be APPROVED or REJECTED.' });
    }

    // 1. Fetch current leave details
    const [leaveRows] = await db.query(
      'SELECT * FROM LEAVE_REQUEST WHERE leave_id = ?',
      [leaveId]
    );

    if (leaveRows.length === 0) {
      return res.status(404).json({ success: false, message: 'Leave record not found.' });
    }

    const leave = leaveRows[0];
    const previousStatus = leave.status;

    // 2. If approving for the first time: deduct paid leave balances & increment unpaid counts
    if (status === 'APPROVED' && previousStatus !== 'APPROVED') {
      const [empRows] = await db.query(
        'SELECT * FROM EMPLOYEE WHERE employee_id = ?',
        [leave.employee_id]
      );

      if (empRows.length > 0) {
        const emp = empRows[0];
        let toDeduct = leave.paid_days !== undefined ? parseInt(leave.paid_days) : parseInt(leave.total_days);
        let casual = Math.max(0, parseInt(emp.leave_balance_casual) || 0);
        let sick = Math.max(0, parseInt(emp.leave_balance_sick) || 0);
        let paid = Math.max(0, parseInt(emp.leave_balance_paid) || 0);

        // Deduct by preferred leave type
        const typeStr = (leave.leave_type || '').toLowerCase();
        if (typeStr.includes('sick')) {
          const d = Math.min(sick, toDeduct);
          sick -= d;
          toDeduct -= d;
        } else if (typeStr.includes('casual')) {
          const d = Math.min(casual, toDeduct);
          casual -= d;
          toDeduct -= d;
        } else if (typeStr.includes('paid') || typeStr.includes('annual')) {
          const d = Math.min(paid, toDeduct);
          paid -= d;
          toDeduct -= d;
        }

        // If toDeduct still remaining, deduct from available categories: Casual -> Paid -> Sick
        if (toDeduct > 0 && casual > 0) {
          const d = Math.min(casual, toDeduct);
          casual -= d;
          toDeduct -= d;
        }
        if (toDeduct > 0 && paid > 0) {
          const d = Math.min(paid, toDeduct);
          paid -= d;
          toDeduct -= d;
        }
        if (toDeduct > 0 && sick > 0) {
          const d = Math.min(sick, toDeduct);
          sick -= d;
          toDeduct -= d;
        }

        const addUnpaidDays = parseInt(leave.unpaid_days) || 0;
        const addDeduction = parseFloat(leave.deduction_amount) || 0.00;

        await db.query(`
          UPDATE EMPLOYEE
          SET leave_balance_casual = ?,
              leave_balance_sick = ?,
              leave_balance_paid = ?,
              unpaid_leaves_taken = COALESCE(unpaid_leaves_taken, 0) + ?,
              total_leave_deduction = COALESCE(total_leave_deduction, 0) + ?
          WHERE employee_id = ?
        `, [casual, sick, paid, addUnpaidDays, addDeduction, emp.employee_id]);
      }
    }

    // 3. If rejecting a previously APPROVED leave: restore quotas!
    if (status === 'REJECTED' && previousStatus === 'APPROVED') {
      const [empRows] = await db.query(
        'SELECT * FROM EMPLOYEE WHERE employee_id = ?',
        [leave.employee_id]
      );

      if (empRows.length > 0) {
        const emp = empRows[0];
        const restoredPaidDays = parseInt(leave.paid_days) || 0;
        const subUnpaidDays = parseInt(leave.unpaid_days) || 0;
        const subDeduction = parseFloat(leave.deduction_amount) || 0.00;

        // Restore to Casual balance
        await db.query(`
          UPDATE EMPLOYEE
          SET leave_balance_casual = COALESCE(leave_balance_casual, 0) + ?,
              unpaid_leaves_taken = GREATEST(0, COALESCE(unpaid_leaves_taken, 0) - ?),
              total_leave_deduction = GREATEST(0, COALESCE(total_leave_deduction, 0) - ?)
          WHERE employee_id = ?
        `, [restoredPaidDays, subUnpaidDays, subDeduction, emp.employee_id]);
      }
    }

    // Update status in LEAVE_REQUEST
    await db.query(
      `UPDATE LEAVE_REQUEST
       SET status = ?, approved_by = ?
       WHERE leave_id = ?`,
      [status, approved_by || 1, leaveId]
    );

    // Send notification to applicant
    try {
      const [applicantRows] = await db.query(
        `SELECT l.leave_type, l.total_days, l.paid_days, l.unpaid_days, l.deduction_amount, e.user_id, e.full_name, e.company_id
         FROM LEAVE_REQUEST l
         JOIN EMPLOYEE e ON l.employee_id = e.employee_id
         WHERE l.leave_id = ?`,
        [leaveId]
      );

      if (applicantRows.length > 0 && applicantRows[0].user_id) {
        const applicant = applicantRows[0];
        const isApproved = status === 'APPROVED';
        let msg = `Your request for ${applicant.total_days} day(s) ${applicant.leave_type} has been ${status}.`;
        if (isApproved) {
          if (applicant.unpaid_days > 0) {
            msg += ` (${applicant.paid_days} Paid day(s) + ${applicant.unpaid_days} Unpaid day(s). Salary Deduction: ₹${applicant.deduction_amount})`;
          } else {
            msg += ' (100% Paid Leave, ₹0 Salary Deduction 🎉)';
          }
        }
        await ensureNotificationTable();
        await db.query(`
          INSERT INTO NOTIFICATION (company_id, title, message, type, reference_id, target_user_id)
          VALUES (?, ?, ?, 'LEAVE_STATUS', ?, ?)
        `, [
          applicant.company_id || 1,
          isApproved ? 'Leave Approved 🎉' : 'Leave Rejected ❌',
          msg,
          leaveId,
          applicant.user_id
        ]);
      }
    } catch (_) {}

    return res.status(200).json({
      success: true,
      message: `Leave request ${status.toLowerCase()} successfully.`
    });
  } catch (error) {
    console.error('Update Leave Status Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

// 7.1 DELETE LEAVE APPLICATION
exports.deleteLeave = async (req, res) => {
  try {
    const { leaveId } = req.params;

    // Check if leave was approved, so we restore quotas!
    const [leaveRows] = await db.query('SELECT * FROM LEAVE_REQUEST WHERE leave_id = ?', [leaveId]);
    if (leaveRows.length > 0) {
      const leave = leaveRows[0];
      if (leave.status === 'APPROVED') {
        const restoredPaidDays = parseInt(leave.paid_days) || 0;
        const subUnpaidDays = parseInt(leave.unpaid_days) || 0;
        const subDeduction = parseFloat(leave.deduction_amount) || 0.00;

        await db.query(`
          UPDATE EMPLOYEE
          SET leave_balance_casual = COALESCE(leave_balance_casual, 0) + ?,
              unpaid_leaves_taken = GREATEST(0, COALESCE(unpaid_leaves_taken, 0) - ?),
              total_leave_deduction = GREATEST(0, COALESCE(total_leave_deduction, 0) - ?)
          WHERE employee_id = ?
        `, [restoredPaidDays, subUnpaidDays, subDeduction, leave.employee_id]);
      }
    }

    await db.query('DELETE FROM LEAVE_REQUEST WHERE leave_id = ?', [leaveId]);
    return res.status(200).json({ success: true, message: 'Leave application deleted successfully.' });
  } catch (error) {
    console.error('Delete Leave Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

// 8. EMPLOYEE STATUS CHANGE & SYSTEM ACCESS BAN / TERMINATION
exports.updateEmployeeStatus = async (req, res) => {
    try {
      const { id } = req.params;
      let { status, exit_reason } = req.body; // status: 'active', 'suspended', 'frozen', 'banned', 'terminated'
      status = (status || '').toLowerCase().trim();

      if (!['active', 'suspended', 'frozen', 'banned', 'terminated'].includes(status)) {
        return res.status(400).json({ success: false, message: 'Status must be active, suspended, frozen, banned, or terminated.' });
      }

      // A. Check employee
      const [empRows] = await db.query('SELECT user_id, full_name FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (empRows.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not found.' });
      }

      const emp = empRows[0];

      // B. Update Employee status & exit info
      if (status === 'terminated') {
        await db.query(
          'UPDATE EMPLOYEE SET status = ?, exit_date = CURDATE(), exit_reason = ? WHERE employee_id = ?',
          [status, exit_reason || 'Employment Terminated by Super Admin', id]
        );
      } else if (status === 'suspended' || status === 'frozen' || status === 'banned') {
        await db.query(
          'UPDATE EMPLOYEE SET status = ?, exit_reason = ? WHERE employee_id = ?',
          [status, exit_reason || `System Access ${status.toUpperCase()}`, id]
        );
      } else {
        // Re-activating employee
        await db.query(
          'UPDATE EMPLOYEE SET status = "active", exit_date = NULL, exit_reason = NULL WHERE employee_id = ?',
          [id]
        );
      }

      // C. AGAR SYSTEM LOGIN HAI TO ACCESS FREEZE / UNFREEZE KARNA
      if (emp.user_id) {
        const isUserActive = status === 'active';
        await db.query('UPDATE USER SET is_active = ? WHERE user_id = ?', [isUserActive ? 1 : 0, emp.user_id]);
      }

      return res.status(200).json({
        success: true,
        message: `Employee ${emp.full_name} status updated to ${status.toUpperCase()}! System access adjusted.`
      });
    } catch (error) {
      console.error('Update Employee Status Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 9. EDIT EMPLOYEE PROFILE DETAILS
  exports.updateEmployee = async (req, res) => {
    try {
      const { id } = req.params;
      const { full_name, designation, phone, email, biometric_emp_code, role, role_name } = req.body;
      const effectiveRole = role_name || role;
      if (effectiveRole) {
        try {
          await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
        } catch (_) {}
        await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [effectiveRole, id]);
        const [empRows] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
        if (empRows.length > 0 && empRows[0].user_id) {
          const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [effectiveRole]);
          if (roleRows.length > 0) {
            await db.query('UPDATE USER SET role_id = ? WHERE user_id = ?', [roleRows[0].role_id, empRows[0].user_id]);
          }
        }
      }

      await db.query(
        `UPDATE EMPLOYEE
         SET full_name = ?, designation = ?, phone = ?, email = ?, biometric_emp_code = ?
         WHERE employee_id = ?`,
        [full_name, designation, phone || null, email || null, biometric_emp_code || null, id]
      );

      return res.status(200).json({
        success: true,
        message: 'Employee profile updated successfully!'
      });
    } catch (error) {
      console.error('Update Employee Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 10. DELETE EMPLOYEE
  exports.deleteEmployee = async (req, res) => {
    try {
      const { id } = req.params;

      // Find associated user_id if any
      const [empRows] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      const userId = empRows && empRows.length > 0 ? empRows[0].user_id : null;

      // Clean up foreign key references in projects, tasks, attendance, leaves, timesheets, permissions, etc.
      try { await db.query('UPDATE project SET project_leader_id = NULL WHERE project_leader_id = ?', [id]); } catch (_) {}
      try { await db.query('UPDATE project SET head_user_id = NULL WHERE head_user_id = ?', [id]); } catch (_) {}
      try { await db.query('UPDATE task SET assigned_to = NULL WHERE assigned_to = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM task_assignees WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM project_member WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM project_timesheet WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM EMPLOYEE_PERMISSION WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM LEAVE_REQUEST WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM ATTENDANCE WHERE employee_id = ?', [id]); } catch (_) {}
      try { await db.query('DELETE FROM EMPLOYEE_INCREMENT WHERE employee_id = ?', [id]); } catch (_) {}

      // Delete employee record
      await db.query('DELETE FROM EMPLOYEE WHERE employee_id = ?', [id]);

      // If there is an associated USER record, clean it up or deactivate it safely
      if (userId) {
        try {
          await db.query('DELETE FROM USER WHERE user_id = ?', [userId]);
        } catch (_) {
          try {
            await db.query('UPDATE USER SET is_active = 0 WHERE user_id = ?', [userId]);
          } catch (_) {}
        }
      }

      return res.status(200).json({ success: true, message: 'Employee record deleted successfully.' });
    } catch (error) {
      console.error('Delete Employee Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 11. GET LIVE EMPLOYEE PERFORMANCE & METRICS
  exports.getEmployeePerformance = async (req, res) => {
    try {
      const { id } = req.params;

      // A. Employee Info
      const [emp] = await db.query(`
        SELECT e.*, d.name as department_name, b.name as branch_name
        FROM EMPLOYEE e
        LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
        LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
        WHERE e.employee_id = ?
      `, [id]);

      if (emp.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not Found!' });
      }

      // B. Real Tasks Count from 'task' table
      const [tasks] = await db.query(`
        SELECT
          COUNT(*) as total_tasks,
          SUM(CASE WHEN status = 'DONE' THEN 1 ELSE 0 END) as completed_tasks,
          SUM(CASE WHEN status != 'DONE' THEN 1 ELSE 0 END) as pending_tasks
        FROM task
        WHERE assigned_to = ?
      `, [id]);

      const totalTasks = tasks[0].total_tasks || 0;
      const completedTasks = tasks[0].completed_tasks || 0;
      const pendingTasks = tasks[0].pending_tasks || 0;
      // Agar abhi tak koi task nahi mila toh 100%, varna actual %
      const taskRate = totalTasks > 0 ? Number(((completedTasks / totalTasks) * 100).toFixed(1)) : 100.0;

      // C. Real Attendance from 'ATTENDANCE' table
      const [att] = await db.query(`
        SELECT
          COUNT(*) as total_days,
          SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) as present_days,
          SUM(CASE WHEN status = 'late' OR status = 'half_day' THEN 1 ELSE 0 END) as late_days
        FROM ATTENDANCE
        WHERE employee_id = ?
      `, [id]);

      const totalDays = att[0].total_days || 0;
      const presentDays = att[0].present_days || 0;
      const attendanceRate = totalDays > 0 ? Number(((presentDays / totalDays) * 100).toFixed(1)) : 98.0;

      // D. Real Timesheet Work Hours
      const [timesheets] = await db.query(`
        SELECT COALESCE(SUM(hours_spent), 0) as total_hours FROM project_timesheet WHERE employee_id = ?
      `, [id]);
      const totalHours = Number(timesheets[0].total_hours) || 0;

      // E. Composite Live Performance Score (50% tasks + 50% attendance)
      const compositeScore = Number(((taskRate * 0.5) + (attendanceRate * 0.5)).toFixed(1));

      // Rating stars (Out of 5.0)
      let ratingStars = (compositeScore / 20).toFixed(1);
      if (ratingStars > 5.0) ratingStars = '5.0';

      let grade = 'Grade A+';
      if (compositeScore < 70) grade = 'Grade B';
      else if (compositeScore < 85) grade = 'Grade A';

      return res.status(200).json({
        success: true,
        data: {
          employee: emp[0],
          total_tasks: totalTasks,
          completed_tasks: completedTasks,
          pending_tasks: pendingTasks,
          task_rate: taskRate,
          total_days: totalDays,
          present_days: presentDays,
          attendance_rate: attendanceRate,
          total_hours: totalHours,
          performance_score: compositeScore,
          rating_stars: ratingStars,
          grade: grade,
          quality_score: 96.0,
          safety_score: 99.0
        }
      });
    } catch (error) {
      console.error('Get Employee Performance Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };
  // ================= 9. DEPARTMENT MANAGEMENT (GET, ADD, UPDATE, DELETE) =================
  exports.getDepartments = async (req, res) => {
    try {
      const companyId = resolveCompanyId(req);
      let whereClause = '';
      const params = [];
      if (companyId) {
        whereClause = 'WHERE d.company_id = ?';
        params.push(companyId);
      } else {
        whereClause = 'WHERE 1 = 0';
      }
      const [departments] = await db.query(`
        SELECT
          d.department_id,
          d.company_id,
          d.name,
          COUNT(e.employee_id) as member_count
        FROM DEPARTMENT d
        LEFT JOIN EMPLOYEE e ON d.department_id = e.department_id AND (e.company_id = d.company_id OR e.company_id IS NULL) AND e.status = 'active'
        ${whereClause}
        GROUP BY d.department_id, d.company_id, d.name
        ORDER BY d.department_id ASC
      `, params);

      return res.status(200).json({ success: true, data: departments });
    } catch (error) {
      console.error('Get Departments Error:', error);
      return res.status(200).json({ success: true, data: [] });
    }
  };

  exports.addDepartment = async (req, res) => {
    try {
      const { name, company_id, member_ids } = req.body;
      if (!name || !name.trim()) {
        return res.status(400).json({ success: false, message: 'Department name is required' });
      }

      // Automatically find valid company_id
      let targetCompanyId = resolveCompanyId(req) || company_id;
      if (!targetCompanyId) {
        try {
          const [companies] = await db.query('SELECT company_id FROM COMPANY LIMIT 1');
          if (companies.length > 0) {
            targetCompanyId = companies[0].company_id;
          }
        } catch (_) {}
      }
      targetCompanyId = targetCompanyId || 1;

      const [result] = await db.query(
        'INSERT INTO DEPARTMENT (company_id, name) VALUES (?, ?)',
        [targetCompanyId, name.trim()]
      );
      const newDeptId = result.insertId;

      if (Array.isArray(member_ids) && member_ids.length > 0) {
        const validIds = member_ids.map(Number).filter(id => !isNaN(id) && id > 0);
        if (validIds.length > 0) {
          await db.query(
            'UPDATE EMPLOYEE SET department_id = ? WHERE employee_id IN (?)',
            [newDeptId, validIds]
          );
        }
      }

      return res.status(201).json({
        success: true,
        message: 'Department created successfully',
        data: { department_id: newDeptId, name: name.trim(), member_count: Array.isArray(member_ids) ? member_ids.length : 0 }
      });
    } catch (error) {
      console.error('Add Department Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  exports.updateDepartment = async (req, res) => {
    try {
      const { id } = req.params;
      const { name, member_ids } = req.body;
      if (!name || !name.trim()) {
        return res.status(400).json({ success: false, message: 'Department name is required' });
      }
      await db.query('UPDATE DEPARTMENT SET name = ? WHERE department_id = ?', [name.trim(), id]);

      // If member_ids is provided, update employee assignments
      if (Array.isArray(member_ids)) {
        const validIds = member_ids.map(Number).filter(id => !isNaN(id) && id > 0);
        if (validIds.length > 0) {
          // Remove department from employees who are in this department but not in validIds
          await db.query(
            'UPDATE EMPLOYEE SET department_id = NULL WHERE department_id = ? AND employee_id NOT IN (?)',
            [id, validIds]
          );
          // Assign department to employees in validIds
          await db.query(
            'UPDATE EMPLOYEE SET department_id = ? WHERE employee_id IN (?)',
            [id, validIds]
          );
        } else {
          // Empty array: clear all employees from this department
          await db.query(
            'UPDATE EMPLOYEE SET department_id = NULL WHERE department_id = ?',
            [id]
          );
        }
      }

      return res.status(200).json({ success: true, message: 'Department and member assignments updated successfully' });
    } catch (error) {
      console.error('Update Department Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  exports.deleteDepartment = async (req, res) => {
    try {
      const { id } = req.params;
      // Check if employees are assigned to this department
      const [employees] = await db.query('SELECT COUNT(*) as count FROM EMPLOYEE WHERE department_id = ?', [id]);
      if (employees[0].count > 0) {
        return res.status(400).json({
          success: false,
          message: `Cannot delete: ${employees[0].count} employee(s) are currently assigned to this department.`
        });
      }
      await db.query('DELETE FROM DEPARTMENT WHERE department_id = ?', [id]);
      return res.status(200).json({ success: true, message: 'Department deleted successfully' });
    } catch (error) {
      console.error('Delete Department Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // ================= 10. COMPREHENSIVE EMPLOYEE FULL PROFILE & PERMISSIONS =================
  exports.getEmployeeFullProfile = async (req, res) => {
    try {
      const { id } = req.params;

      // Ensure required tables exist
      try {
        await db.query(`
          CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
            employee_id INT NOT NULL,
            permission_key VARCHAR(60) NOT NULL,
            is_granted TINYINT(1) DEFAULT 1,
            PRIMARY KEY (employee_id, permission_key),
            CONSTRAINT fk_emp_perm FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        `);
        await db.query(`
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
      } catch (tblErr) {
        console.warn('Table check warning:', tblErr.message);
      }

      // 1. Employee + Dept + Branch + User + Role
      const [empRows] = await db.query(`
        SELECT 
          e.*,
          d.name as department_name,
          b.name as branch_name,
          u.user_id,
          u.email as user_email,
          u.is_active as user_active,
          r.role_id,
          r.name as role_name
        FROM EMPLOYEE e
        LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
        LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
        LEFT JOIN USER u ON e.user_id = u.user_id
        LEFT JOIN ROLE r ON u.role_id = r.role_id
        WHERE e.employee_id = ?
      `, [id]);

      if (empRows.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not found' });
      }
      const emp = empRows[0];

      // 2. Custom Permissions
      const customPermissions = {};
      try {
        const [permRows] = await db.query(
          'SELECT permission_key, is_granted FROM EMPLOYEE_PERMISSION WHERE employee_id = ?',
          [id]
        );
        for (const p of permRows) {
          customPermissions[p.permission_key] = Boolean(p.is_granted);
        }
      } catch (_) {}

      // Default permissions based on role & department
      const defaultPermissions = getDefaultPermissions(emp.role_name || emp.role, emp.department_name || '');
      const mergedPermissions = { ...defaultPermissions, ...customPermissions };

      // 3. Recent Attendance (Last 10 records)
      let attendance = [];
      try {
        const [attRows] = await db.query(`
          SELECT attendance_id, work_date, check_in, check_out, status, overtime_hours
          FROM ATTENDANCE 
          WHERE employee_id = ? 
          ORDER BY work_date DESC 
          LIMIT 10
        `, [id]);
        attendance = attRows;
      } catch (_) {}

      // 4. Recent Leaves (Last 10 records)
      let leaves = [];
      try {
        const [leaveRows] = await db.query(`
          SELECT leave_id, leave_type, start_date, end_date, total_days, reason, status, created_at
          FROM LEAVE_REQUEST 
          WHERE employee_id = ? 
          ORDER BY leave_id DESC 
          LIMIT 10
        `, [id]);
        leaves = leaveRows;
      } catch (_) {}

      // 5. Real Performance & Operational Stats (NO MOCK DATA)
      let totalShifts = 0;
      let presentShifts = 0;
      let onTimeShifts = 0;
      let totalOvertime = 0;
      try {
        const [attStats] = await db.query(`
          SELECT 
            COUNT(*) as total_shifts,
            SUM(CASE WHEN status = 'Present' THEN 1 ELSE 0 END) as present_shifts,
            SUM(CASE WHEN TIME(check_in) <= '09:15:00' THEN 1 ELSE 0 END) as on_time_shifts,
            COALESCE(SUM(overtime_hours), 0) as total_overtime
          FROM ATTENDANCE WHERE employee_id = ?
        `, [id]);

       if (attStats.length > 0) {
         totalShifts = Number(attStats[0].total_shifts) || 0;
         presentShifts = Number(attStats[0].present_shifts) || 0;
         onTimeShifts = Number(attStats[0].on_time_shifts) || 0;
         totalOvertime = Number(attStats[0].total_overtime) || 0;
       }
      } catch (_) {}

      let approvedLeaveDays = 0;
      try {
        const [leaveStats] = await db.query(`
          SELECT 
            COUNT(*) as total_leave_requests,
            COALESCE(SUM(CASE WHEN status = 'APPROVED' THEN total_days ELSE 0 END), 0) as approved_leave_days
          FROM LEAVE_REQUEST WHERE employee_id = ?
        `, [id]);
        if (leaveStats.length > 0) {
          approvedLeaveDays = Number(leaveStats[0].approved_leave_days) || 0;
        }
      } catch (_) {}

      const punctualityRate = totalShifts > 0 ? Number(((onTimeShifts / totalShifts) * 100).toFixed(1)) : null;
      const attendanceRate = totalShifts > 0 ? Number(((presentShifts / totalShifts) * 100).toFixed(1)) : null;

      return res.status(200).json({
        success: true,
        data: {
          employee: emp,
          permissions: mergedPermissions,
          attendance,
          leaves,
          performance: {
            total_shifts: totalShifts,
            present_shifts: presentShifts,
            on_time_shifts: onTimeShifts,
            total_overtime: totalOvertime,
            punctuality_rate: punctualityRate,
            attendance_rate: attendanceRate,
            approved_leave_days: approvedLeaveDays
          }
        }
      });
    } catch (error) {
      console.error('Get Employee Full Profile Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 11. SAVE EMPLOYEE PERMISSIONS
  exports.updateEmployeePermissions = async (req, res) => {
    try {
      const { id } = req.params;
      const { permissions, role_id, role_name, user_active, caller_role } = req.body;

      // Extract requester role from req.user, JWT authorization header, or caller_role
      let effectiveRole = req.user?.role || req.user?.role_name || caller_role;
      if (!effectiveRole && req.headers && req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
        try {
          const token = req.headers.authorization.split(' ')[1];
          const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
          effectiveRole = decoded?.role || decoded?.role_name;
          if (!effectiveRole && decoded?.userId) {
            const [uRows] = await db.query(
              'SELECT r.name as role_name FROM USER u JOIN ROLE r ON u.role_id = r.role_id WHERE u.user_id = ?',
              [decoded.userId]
            );
            if (uRows.length > 0) effectiveRole = uRows[0].role_name;
          }
        } catch (_) {}
      }

      const normRole = (effectiveRole || '').trim().toLowerCase();
      const isSuperAdmin = !normRole || normRole.includes('admin') || normRole.includes('executive');
      if (!isSuperAdmin) {
        return res.status(403).json({
          success: false,
          message: 'Access Denied: Only Super Admin can modify system permissions!'
        });
      }

      if (!id) {
        return res.status(400).json({ success: false, message: 'Employee ID is required.' });
      }

      // Ensure EMPLOYEE_PERMISSION table exists
      await db.query(`
        CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
          employee_id INT NOT NULL,
          permission_key VARCHAR(60) NOT NULL,
          is_granted TINYINT(1) DEFAULT 1,
          PRIMARY KEY (employee_id, permission_key),
          CONSTRAINT fk_emp_perm FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
      `);

      // Update permissions
      if (permissions && typeof permissions === 'object') {
        for (const [key, val] of Object.entries(permissions)) {
          await db.query(`
            INSERT INTO EMPLOYEE_PERMISSION (employee_id, permission_key, is_granted)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE is_granted = VALUES(is_granted)
          `, [id, key, val ? 1 : 0]);
        }
      }

      // Update user role and status if employee has user_id
      const [emp] = await db.query('SELECT user_id, company_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (emp.length > 0 && emp[0].user_id) {
        const updates = [];
        const params = [];
        let targetRoleId = role_id;
        if (!targetRoleId && role_name) {
          const compId = emp[0].company_id || resolveCompanyId(req) || 1;
          let [rRows] = await db.query('SELECT role_id FROM ROLE WHERE company_id = ? AND name = ? LIMIT 1', [compId, role_name]);
          if (rRows.length === 0) [rRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role_name]);
          if (rRows.length > 0) targetRoleId = rRows[0].role_id;
        }
        if (targetRoleId) {
          updates.push('role_id = ?');
          params.push(targetRoleId);
        }
        if (user_active !== undefined) {
          updates.push('is_active = ?');
          params.push(user_active ? 1 : 0);
        }
        if (updates.length > 0) {
          params.push(emp[0].user_id);
          await db.query(`UPDATE USER SET ${updates.join(', ')} WHERE user_id = ?`, params);
        }
        if (role_name) {
          await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [role_name, id]);
        }
      }

      return res.status(200).json({
        success: true,
        message: 'Employee permissions and access updated successfully!'
      });
    } catch (error) {
      console.error('Update Employee Permissions Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 12. COMPLETE EMPLOYEE LIFECYCLE & IN-PLACE EDIT
  exports.updateEmployeeLifecycle = async (req, res) => {
    try {
      const { id } = req.params;
      const {
        full_name,
        biometric_emp_code,
        employment_type,
        weekly_off,
        salary_grade,
        salary_base,
        status,
        designation,
        department_id,
        phone,
        email,
        join_date,
        leave_balance_casual,
        leave_balance_sick,
        leave_balance_paid,
        age,
        gender,
        dob,
        city,
        state,
        address,
        aadhar_number,
        pan_number,
        emergency_contact,
        unpaid_leave_limit,
        unpaid_leave_per_day_deduction,
        role,
        manager_module
      } = req.body;

           await db.query(`
             UPDATE EMPLOYEE SET
               full_name = COALESCE(?, full_name),
               biometric_emp_code = COALESCE(?, biometric_emp_code),
               employment_type = COALESCE(?, employment_type),
               weekly_off = COALESCE(?, weekly_off),
               salary_grade = COALESCE(?, salary_grade),
               salary_base = COALESCE(?, salary_base),
               status = COALESCE(?, status),
               designation = COALESCE(?, designation),
               department_id = COALESCE(?, department_id),
               phone = COALESCE(?, phone),
               email = COALESCE(?, email),
               join_date = COALESCE(?, join_date),
               leave_balance_casual = COALESCE(?, leave_balance_casual),
               leave_balance_sick = COALESCE(?, leave_balance_sick),
               leave_balance_paid = COALESCE(?, leave_balance_paid),
               age = COALESCE(?, age),
               gender = COALESCE(?, gender),
               dob = COALESCE(?, dob),
               city = COALESCE(?, city),
               state = COALESCE(?, state),
               address = COALESCE(?, address),
               aadhar_number = COALESCE(?, aadhar_number),
               pan_number = COALESCE(?, pan_number),
               emergency_contact = COALESCE(?, emergency_contact),
               unpaid_leave_limit = COALESCE(?, unpaid_leave_limit),
               unpaid_leave_per_day_deduction = COALESCE(?, unpaid_leave_per_day_deduction)
             WHERE employee_id = ?
           `, [
             full_name,
             biometric_emp_code,
             employment_type,
             weekly_off,
             salary_grade,
             salary_base,
             status,
             designation,
             department_id,
             phone,
             email,
             join_date,
             leave_balance_casual,
             leave_balance_sick,
             leave_balance_paid,
             age,
             gender,
             dob,
             city,
             state,
             address,
             aadhar_number,
             pan_number,
             emergency_contact,
             unpaid_leave_limit,
             unpaid_leave_per_day_deduction,
             id
           ]);

      if (status) {
        const [emp] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
        if (emp.length > 0 && emp[0].user_id) {
          const isUserActive = status.toLowerCase() === 'active';
          await db.query('UPDATE USER SET is_active = ? WHERE user_id = ?', [isUserActive ? 1 : 0, emp[0].user_id]);
        }
      }

      if (role) {
        try {
          await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
        } catch (_) {}
        await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [role, id]);

        const [empRows] = await db.query('SELECT user_id, department_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
        if (empRows.length > 0 && empRows[0].user_id) {
          const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role]);
          if (roleRows.length > 0) {
            await db.query('UPDATE USER SET role_id = ? WHERE user_id = ?', [roleRows[0].role_id, empRows[0].user_id]);
          }
        }

        try {
          let deptName = '';
          const effDeptId = department_id || (empRows.length > 0 ? empRows[0].department_id : null);
          if (effDeptId) {
            const [dRows] = await db.query('SELECT name FROM DEPARTMENT WHERE department_id = ?', [effDeptId]);
            if (dRows.length > 0) deptName = dRows[0].name;
          }
          const updatedPerms = getDefaultPermissions(role, deptName, manager_module);
          for (const [permKey, isGranted] of Object.entries(updatedPerms)) {
            await db.query(
              `INSERT INTO EMPLOYEE_PERMISSION (employee_id, permission_key, is_granted)
               VALUES (?, ?, ?)
               ON DUPLICATE KEY UPDATE is_granted = VALUES(is_granted)`,
              [id, permKey, isGranted ? 1 : 0]
            );
          }
        } catch (_) {}
      }

      return res.status(200).json({
        success: true,
        message: 'Employee details updated successfully!'
      });
    } catch (error) {
      console.error('Update Employee Lifecycle Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 13. CREATE SYSTEM LOGIN FOR EMPLOYEE
  exports.createEmployeeLoginAccount = async (req, res) => {
    try {
      const { id } = req.params;
      const { email, password, role_name, status } = req.body;

      if (!email || !password) {
        return res.status(400).json({ success: false, message: 'Email and password are required.' });
      }

      if (password.trim().length < 6) {
        return res.status(400).json({ success: false, message: 'Password must be at least 6 characters long.' });
      }

      // A. Check if email already in use
      const [existingUser] = await db.query('SELECT user_id FROM USER WHERE email = ?', [email.trim()]);
      if (existingUser.length > 0) {
        return res.status(400).json({ success: false, message: 'This email is already in use by another user account.' });
      }

      // B. Check Employee exists
      const [empRows] = await db.query(
        'SELECT employee_id, company_id, branch_id, user_id, full_name, email FROM EMPLOYEE WHERE employee_id = ?',
        [id]
      );
      if (empRows.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not found.' });
      }
      const emp = empRows[0];

      if (emp.user_id) {
        return res.status(400).json({ success: false, message: 'This employee already has a linked login account.' });
      }

      // C. Find role_id
      const targetRoleName = role_name || 'Employee';
      const userCompanyId = emp.company_id || resolveCompanyId(req) || 1;
      let [roleRows] = await db.query(
        'SELECT role_id FROM ROLE WHERE company_id = ? AND name = ? LIMIT 1',
        [userCompanyId, targetRoleName]
      );
      if (roleRows.length === 0) {
        [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [targetRoleName]);
      }
      let roleId = roleRows.length > 0 ? roleRows[0].role_id : null;
      if (!roleId) {
        const [newRole] = await db.query('INSERT INTO ROLE (company_id, name) VALUES (?, ?)', [userCompanyId, targetRoleName]);
        roleId = newRole.insertId;
      }

      // D. Hash password & insert into USER
      const bcrypt = require('bcryptjs');
      const passwordHash = await bcrypt.hash(password.trim(), 10);
      const isUserActive = (status === undefined || status === null)
        ? 1
        : (['active', 'true', '1'].includes(status.toString().toLowerCase()) ? 1 : 0);

      const [userResult] = await db.query(
        `INSERT INTO USER (company_id, role_id, email, password_hash, is_active)
         VALUES (?, ?, ?, ?, ?)`,
        [userCompanyId, roleId, email.trim(), passwordHash, isUserActive]
      );
      const newUserId = userResult.insertId;

      // E. Link user_id to EMPLOYEE and sync role and email
      await db.query(
        'UPDATE EMPLOYEE SET user_id = ?, role = ?, email = COALESCE(email, ?) WHERE employee_id = ?',
        [newUserId, targetRoleName, email.trim(), id]
      );

      return res.status(201).json({
        success: true,
        message: 'System login account created and linked successfully!',
        data: {
          user_id: newUserId,
          email: email.trim(),
          role_name: targetRoleName,
          is_active: isUserActive
        }
      });
    } catch (error) {
      console.error('Create Employee Login Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // 13B. RESET EMPLOYEE LOGIN PASSWORD
  exports.resetEmployeePassword = async (req, res) => {
    try {
      const { id } = req.params;
      const { new_password, password } = req.body;
      const targetPassword = new_password || password;

      if (!targetPassword || targetPassword.trim().length < 6) {
        return res.status(400).json({
          success: false,
          message: 'Password must be at least 6 characters long.'
        });
      }

      // Check Employee exists & has user_id
      const [empRows] = await db.query(
        'SELECT employee_id, user_id, full_name, email FROM EMPLOYEE WHERE employee_id = ?',
        [id]
      );
      if (empRows.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not found.' });
      }
      const emp = empRows[0];

      if (!emp.user_id) {
        return res.status(400).json({
          success: false,
          message: 'This employee does not have a linked login account.'
        });
      }

      // Hash password & update USER
      const bcrypt = require('bcryptjs');
      const passwordHash = await bcrypt.hash(targetPassword.trim(), 10);

      await db.query('UPDATE USER SET password_hash = ? WHERE user_id = ?', [passwordHash, emp.user_id]);

      return res.status(200).json({
        success: true,
        message: `Password for ${emp.full_name} has been reset successfully!`
      });
    } catch (error) {
      console.error('Reset Employee Password Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // ================= 🕒 ATTENDANCE RECORDS & MANUAL OVERRIDE =================

  // 1. GET ATTENDANCE RECORDS WITH ADVANCED FILTERS (Date, Month, Year, Range, Employee)
  exports.getAttendanceRecords = async (req, res) => {
    try {
      const { employee_id, date, month, year, start_date, end_date } = req.query;
      const companyId = resolveCompanyId(req);

      let query = `
        SELECT 
          a.attendance_id,
          a.employee_id,
          e.full_name,
          e.emp_code,
          e.biometric_emp_code,
          d.name as department_name,
          DATE_FORMAT(a.work_date, '%Y-%m-%d') as work_date,
          TIME_FORMAT(a.check_in, '%H:%i:%s') as check_in_time,
          TIME_FORMAT(a.check_out, '%H:%i:%s') as check_out_time,
          a.status,
          a.overtime_hours,
          TIMESTAMPDIFF(MINUTE, a.check_in, a.check_out) as work_minutes
        FROM ATTENDANCE a
        JOIN EMPLOYEE e ON a.employee_id = e.employee_id
        LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
        WHERE 1=1
      `;
      const params = [];

      if (companyId) {
        // ATTENDANCE has no company_id column; tenant scope comes from EMPLOYEE.
        query += ` AND (e.company_id = ? OR e.company_id IS NULL)`;
        params.push(companyId);
      }

      if (employee_id) {
        query += ` AND a.employee_id = ?`;
        params.push(employee_id);
      }
      if (date) {
        query += ` AND a.work_date = ?`;
        params.push(date);
      }
      if (month && parseInt(month, 10) > 0 && year && parseInt(year, 10) > 0) {
        query += ` AND MONTH(a.work_date) = ? AND YEAR(a.work_date) = ?`;
        params.push(month, year);
      } else if (year && parseInt(year, 10) > 0) {
        query += ` AND YEAR(a.work_date) = ?`;
        params.push(year);
      }
      if (start_date && end_date) {
        query += ` AND a.work_date BETWEEN ? AND ?`;
        params.push(start_date, end_date);
      }

      query += ` ORDER BY a.work_date DESC, e.full_name ASC`;

      const [rows] = await db.query(query, params);

      return res.status(200).json({
        success: true,
        total: rows.length,
        data: rows
      });
    } catch (error) {
      console.error('Error fetching attendance records:', error);
      return res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
  };

  // 2. MANUAL ATTENDANCE OVERRIDE / EDIT
  exports.updateAttendanceRecord = async (req, res) => {
    try {
      const { id } = req.params;
      const { check_in, check_out, status, overtime_hours } = req.body;

      if (!status) {
        return res.status(400).json({ success: false, message: 'Attendance status is required.' });
      }

      const [existing] = await db.query('SELECT * FROM ATTENDANCE WHERE attendance_id = ?', [id]);
      if (existing.length === 0) {
        return res.status(404).json({ success: false, message: 'Attendance record not found.' });
      }

      const current = existing[0];
      const workDate = current.work_date instanceof Date
        ? current.work_date.toISOString().split('T')[0]
        : String(current.work_date).split('T')[0];

      let fullCheckIn = null;
      if (check_in && check_in.trim() !== '') {
        const timePart = check_in.includes(' ') ? check_in.split(' ')[1] : check_in.trim();
        fullCheckIn = `${workDate} ${timePart}`;
      }

      let fullCheckOut = null;
      if (check_out && check_out.trim() !== '') {
        const timePart = check_out.includes(' ') ? check_out.split(' ')[1] : check_out.trim();
        fullCheckOut = `${workDate} ${timePart}`;
      }

      await db.query(
        `UPDATE ATTENDANCE 
         SET check_in = ?, check_out = ?, status = ?, overtime_hours = COALESCE(?, overtime_hours)
         WHERE attendance_id = ?`,
        [fullCheckIn, fullCheckOut, status, overtime_hours, id]
      );

      return res.status(200).json({
        success: true,
        message: 'Attendance record manually updated and overridden successfully!'
      });
    } catch (error) {
      console.error('Error updating attendance record:', error);
      return res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
  };
  // ================= 🔔 NOTIFICATION SYSTEM =================

  // Table check helper (Startup par table bana dega + Missing columns add karega)
  const ensureNotificationTable = async () => {
    try {
      await db.query(`
        CREATE TABLE IF NOT EXISTS NOTIFICATION (
          notification_id INT AUTO_INCREMENT PRIMARY KEY,
          company_id INT NOT NULL DEFAULT 1,
          title VARCHAR(150) NOT NULL,
          message TEXT NOT NULL,
          type VARCHAR(50) NOT NULL DEFAULT 'LEAVE_REQUEST',
          reference_id INT DEFAULT NULL,
          target_user_id INT DEFAULT NULL,
          target_role VARCHAR(50) DEFAULT NULL,
          sender_user_id INT DEFAULT NULL,
          is_read TINYINT(1) DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
      `);

      // Backward compatibility: Agar purani table me naye targeting columns nahi hain to safely add karein
      try {
        await db.query(`ALTER TABLE NOTIFICATION ADD COLUMN target_user_id INT DEFAULT NULL;`);
      } catch (_) {}
      try {
        await db.query(`ALTER TABLE NOTIFICATION ADD COLUMN target_role VARCHAR(50) DEFAULT NULL;`);
      } catch (_) {}
      try {
        await db.query(`ALTER TABLE NOTIFICATION ADD COLUMN sender_user_id INT DEFAULT NULL;`);
      } catch (_) {}
    } catch (e) {
      console.warn('Notification table check warning:', e.message);
    }
  };
  ensureNotificationTable();

  // 1. Get Targeted Notifications (Role and User specific, strictly isolated by Company)
  exports.getNotifications = async (req, res) => {
    try {
      await ensureNotificationTable();
      const { user_id, role, can_approve_leaves } = req.query;
      let companyId = resolveCompanyId(req);
      const uid = user_id ? parseInt(user_id, 10) : null;

      if (!companyId && uid) {
        try {
          const [uRows] = await db.query('SELECT company_id FROM USER WHERE user_id = ?', [uid]);
          if (uRows.length > 0 && uRows[0].company_id) {
            companyId = uRows[0].company_id;
          }
        } catch (_) {}
      }

      let query = `
        SELECT notification_id, title, message, type, reference_id, target_user_id, target_role, sender_user_id, is_read, created_at
        FROM NOTIFICATION
        WHERE 1=1
      `;
      const params = [];

      if (companyId) {
        query += ` AND company_id = ?`;
        params.push(companyId);
      } else {
        query += ` AND 1 = 0`; // Strict company isolation: never leak cross-tenant notifications
      }

      const isAdminOrApprover = role === 'Super Admin' || can_approve_leaves === 'true' || can_approve_leaves === true;

      if (uid) {
        if (isAdminOrApprover) {
          // Admin & Approvers get:
          // 1. Leave requests to approve (excluding ones they created themselves)
          // 2. Notifications targeted to ADMIN_MANAGER role
          // 3. Notifications targeted directly to their user_id
          // 4. Global broadcast notifications
          query += ` AND (
            (type = 'LEAVE_REQUEST' AND (sender_user_id IS NULL OR sender_user_id != ?))
            OR target_role = 'ADMIN_MANAGER'
            OR target_user_id = ?
            OR (target_user_id IS NULL AND target_role IS NULL AND type NOT IN ('LEAVE_REQUEST', 'LEAVE_STATUS'))
          )`;
          params.push(uid, uid);
        } else {
          // Regular Employees (member1, etc.) get ONLY:
          // 1. Personal notifications targeted directly to their user_id (e.g. Leave Approved / Rejected)
          // 2. Global general broadcasts
          // (They NEVER see another employee's leave requests or admin manager alerts!)
          query += ` AND (
            target_user_id = ?
            OR (target_user_id IS NULL AND target_role IS NULL AND type NOT IN ('LEAVE_REQUEST', 'LEAVE_STATUS'))
          )`;
          params.push(uid);
        }
      } else {
        // Unauthenticated or query without user_id: only show general broadcast announcements
        query += ` AND target_user_id IS NULL AND target_role IS NULL AND type NOT IN ('LEAVE_REQUEST', 'LEAVE_STATUS')`;
      }

      query += ` ORDER BY notification_id DESC LIMIT 30`;

      const [rows] = await db.query(query, params);
      const unreadCount = rows.filter(n => n.is_read === 0 || n.is_read === false).length;

      return res.status(200).json({
        success: true,
        unreadCount,
        data: rows
      });
    } catch (error) {
      console.error('Get Notifications Error:', error);
      return res.status(500).json({ success: false, message: 'Server error', error: error.message });
    }
  };

  // 2. Mark Single Notification as Read
  exports.markNotificationAsRead = async (req, res) => {
    try {
      const { id } = req.params;
      const companyId = resolveCompanyId(req);
      let query = 'UPDATE NOTIFICATION SET is_read = 1 WHERE notification_id = ?';
      const params = [id];
      if (companyId) {
        query += ' AND company_id = ?';
        params.push(companyId);
      }
      await db.query(query, params);
      return res.status(200).json({ success: true, message: 'Marked as read' });
    } catch (error) {
      return res.status(500).json({ success: false, error: error.message });
    }
  };

  // 3. Mark All Notifications as Read (Targeted to the requesting user/role & company)
  exports.markAllNotificationsAsRead = async (req, res) => {
    try {
      const { user_id, role, can_approve_leaves } = req.query;
      const uid = user_id ? parseInt(user_id, 10) : null;
      let companyId = resolveCompanyId(req);

      if (!companyId && uid) {
        try {
          const [uRows] = await db.query('SELECT company_id FROM USER WHERE user_id = ?', [uid]);
          if (uRows.length > 0 && uRows[0].company_id) {
            companyId = uRows[0].company_id;
          }
        } catch (_) {}
      }

      const isAdminOrApprover = role === 'Super Admin' || can_approve_leaves === 'true' || can_approve_leaves === true;

      let query = 'UPDATE NOTIFICATION SET is_read = 1 WHERE 1=1';
      const params = [];

      if (companyId) {
        query += ' AND company_id = ?';
        params.push(companyId);
      }

      if (uid) {
        if (isAdminOrApprover) {
          query += ` AND (
            (type = 'LEAVE_REQUEST' AND (sender_user_id IS NULL OR sender_user_id != ?))
            OR target_role = 'ADMIN_MANAGER'
            OR target_user_id = ?
            OR (target_user_id IS NULL AND target_role IS NULL AND type NOT IN ('LEAVE_REQUEST', 'LEAVE_STATUS'))
          )`;
          params.push(uid, uid);
        } else {
          query += ` AND (
            target_user_id = ?
            OR (target_user_id IS NULL AND target_role IS NULL AND type NOT IN ('LEAVE_REQUEST', 'LEAVE_STATUS'))
          )`;
          params.push(uid);
        }
      }

      await db.query(query, params);
      return res.status(200).json({ success: true, message: 'All relevant notifications marked as read' });
    } catch (error) {
      return res.status(500).json({ success: false, error: error.message });
    }
  };


  // 2. UPDATE EMPLOYEE ROLE (Promote to Module Manager / Admin / Employee) - Aliased above



// ================= 12. SALARY INCREMENT & APPRAISAL =================
exports.createIncrement = async (req, res) => {
  try {
    const {
      company_id,
      employee_id,
      increment_type,
      increment_value,
      increment_amount,
      previous_salary,
      revised_salary,
      new_designation,
      new_salary_grade,
      effective_date,
      reason,
      approved_by
    } = req.body;

    if (!employee_id || !revised_salary || !effective_date) {
      return res.status(400).json({ success: false, message: 'Employee, revised salary, and effective date are required.' });
    }

    // Ensure EMPLOYEE_INCREMENT table exists
    await db.query(`
      CREATE TABLE IF NOT EXISTS EMPLOYEE_INCREMENT (
        increment_id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT DEFAULT 1,
        employee_id INT NOT NULL,
        previous_salary DECIMAL(12,2) NOT NULL,
        increment_type VARCHAR(20) NOT NULL,
        increment_value DECIMAL(12,2) NOT NULL,
        increment_amount DECIMAL(12,2) NOT NULL,
        revised_salary DECIMAL(12,2) NOT NULL,
        new_designation VARCHAR(100) NULL,
        new_salary_grade VARCHAR(50) NULL,
        effective_date DATE NOT NULL,
        reason TEXT,
        approved_by INT DEFAULT 1,
        status VARCHAR(20) DEFAULT 'APPROVED',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    const prevSal = parseFloat(previous_salary) || 0.0;
    const revSal = parseFloat(revised_salary) || 0.0;
    const incAmount = parseFloat(increment_amount) || Math.max(0, revSal - prevSal);
    const incVal = parseFloat(increment_value) || 0.0;

    // Insert increment record
    const [result] = await db.query(
      `INSERT INTO EMPLOYEE_INCREMENT
       (company_id, employee_id, previous_salary, increment_type, increment_value, increment_amount, revised_salary, new_designation, new_salary_grade, effective_date, reason, approved_by, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'APPROVED')`,
      [
        company_id || 1,
        employee_id,
        prevSal,
        increment_type || 'FIXED',
        incVal,
        incAmount,
        revSal,
        new_designation || null,
        new_salary_grade || null,
        effective_date,
        reason || 'Annual Performance Review',
        approved_by || 1
      ]
    );

    // Update EMPLOYEE: revised salary and new daily deduction (revised_salary / 30)
    const newDailyDeduction = parseFloat((revSal / 30.0).toFixed(2));
    let updateSql = 'UPDATE EMPLOYEE SET salary_base = ?, unpaid_leave_per_day_deduction = ?';
    let updateParams = [revSal, newDailyDeduction];

    if (new_designation && new_designation.trim() !== '') {
      updateSql += ', designation = ?';
      updateParams.push(new_designation.trim());
    }
    if (new_salary_grade && new_salary_grade.trim() !== '') {
      updateSql += ', salary_grade = ?';
      updateParams.push(new_salary_grade.trim());
    }
    updateSql += ' WHERE employee_id = ?';
    updateParams.push(employee_id);

    await db.query(updateSql, updateParams);
        // Sync active Salary Template / Structure with the revised salary
        try {
          const [curStructs] = await db.query(
            `SELECT s.*, t.basic_percent, t.hra_percent, t.conveyance_fixed, t.custom_allowances_json, t.template_name
             FROM employee_salary_structures s
             LEFT JOIN salary_templates t ON t.template_id = s.template_id
             WHERE s.employee_id = ? AND s.is_current = 1
             ORDER BY s.structure_id DESC LIMIT 1`,
            [employee_id]
          );

          if (curStructs.length > 0) {
            const cur = curStructs[0];
            const compId = cur.company_id || company_id || 1;
            const basicPct = cur.template_id ? (parseFloat(cur.basic_percent) || 50) : 50;
            const hraPct = cur.template_id ? (parseFloat(cur.hra_percent) || 40) : 40;
            const convFixed = cur.template_id ? (parseFloat(cur.conveyance_fixed) || 1600) : 1600;

            const newBasic = Math.round(((revSal * basicPct) / 100) * 100) / 100;
            const newHra = Math.round(((newBasic * hraPct) / 100) * 100) / 100;
            const newConv = Math.min(convFixed, Math.max(0, revSal - newBasic - newHra));
            const newSpecial = Math.max(0, Math.round((revSal - newBasic - newHra - newConv) * 100) / 100);

            await db.query(
              `UPDATE employee_salary_structures
               SET is_current = 0, effective_to = DATE_SUB(?, INTERVAL 1 DAY)
               WHERE structure_id = ?`,
              [effective_date, cur.structure_id]
            );

            const [newSt] = await db.query(
              `INSERT INTO employee_salary_structures
                (company_id, employee_id, template_id, salary_type, base_pay, gross_monthly, effective_from, is_current,
                 pf_applicable, esi_applicable, pt_applicable, tds_monthly, notes, created_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)`,
              [
                compId,
                employee_id,
                cur.template_id || null,
                cur.salary_type || 'MONTHLY',
                newBasic,
                revSal,
                effective_date,
                cur.pf_applicable ?? 1,
                cur.esi_applicable ?? 1,
                cur.pt_applicable ?? 1,
                cur.tds_monthly || 0,
                `Auto-revised via Salary Increment (${cur.template_name || 'Custom'})`,
                approved_by || 1
              ]
            );

            const [compRows] = await db.query(
              'SELECT component_id, code FROM salary_components WHERE company_id = ?',
              [compId]
            );
            const compMap = Object.fromEntries(compRows.map((c) => [c.code, c.component_id]));
            const items = [
              [compMap.BASIC, 'FIXED', newBasic, newBasic],
              [compMap.HRA, 'PERCENT_OF_BASIC', hraPct, newHra],
              [compMap.CONV, 'FIXED', newConv, newConv],
              [compMap.SPECIAL, 'FIXED', newSpecial, newSpecial]
            ];
            for (const [cid, mode, val, comp] of items) {
              if (!cid || comp <= 0) continue;
              await db.query(
                `INSERT INTO employee_salary_structure_items
                  (company_id, structure_id, component_id, calc_mode, amount_or_percent, computed_amount, created_by)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                [compId, newSt.insertId, cid, mode, val, comp, approved_by || 1]
              );
            }
          }
        } catch (syncErr) {
          console.error('Salary template sync on increment failed:', syncErr.message);
        }
    // Send notification to employee
    try {
      const [empRows] = await db.query('SELECT user_id, full_name, company_id FROM EMPLOYEE WHERE employee_id = ?', [employee_id]);
      if (empRows.length > 0 && empRows[0].user_id) {
        await ensureNotificationTable();
        await db.query(`
          INSERT INTO NOTIFICATION (company_id, title, message, type, reference_id, target_user_id)
          VALUES (?, ?, ?, 'SALARY_INCREMENT', ?, ?)
        `, [
          empRows[0].company_id || 1,
          'Salary Increment Approved 🎉',
          `Congratulations! Your monthly salary has been revised to ₹${revSal} (+₹${incAmount}) effective from ${effective_date}.`,
          result.insertId,
          empRows[0].user_id
        ]);
      }
    } catch (_) {}

    return res.status(201).json({
      success: true,
      message: 'Salary increment recorded and employee compensation updated successfully!',
      increment_id: result.insertId,
      revised_salary: revSal,
      increment_amount: incAmount
    });

  } catch (error) {
    console.error('Create Increment Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};

exports.getIncrements = async (req, res) => {
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS EMPLOYEE_INCREMENT (
        increment_id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT DEFAULT 1,
        employee_id INT NOT NULL,
        previous_salary DECIMAL(12,2) NOT NULL,
        increment_type VARCHAR(20) NOT NULL,
        increment_value DECIMAL(12,2) NOT NULL,
        increment_amount DECIMAL(12,2) NOT NULL,
        revised_salary DECIMAL(12,2) NOT NULL,
        new_designation VARCHAR(100) NULL,
        new_salary_grade VARCHAR(50) NULL,
        effective_date DATE NOT NULL,
        reason TEXT,
        approved_by INT DEFAULT 1,
        status VARCHAR(20) DEFAULT 'APPROVED',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    const companyId = resolveCompanyId(req);
    let whereClause = '';
    const params = [];
    if (companyId) {
      whereClause = 'WHERE (i.company_id = ? OR e.company_id = ?)';
      params.push(companyId, companyId);
    }

    const [rows] = await db.query(`
      SELECT i.*, e.full_name, e.emp_code, e.department_id, d.name as department_name, u.email as approved_by_email
      FROM EMPLOYEE_INCREMENT i
      JOIN EMPLOYEE e ON i.employee_id = e.employee_id
      LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
      LEFT JOIN USER u ON i.approved_by = u.user_id
      ${whereClause}
      ORDER BY i.increment_id DESC
    `, params);

    return res.status(200).json({
      success: true,
      data: rows
    });
  } catch (error) {
    console.error('Get Increments Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};
// GET ATTENDANCE IMPORT AUDIT LOGS
exports.getAttendanceImports = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req);
    const params = [];
    let where = '';

    if (companyId) {
      where = ' WHERE company_id = ?';
      params.push(companyId);
    }
    params.push(50);

    // The committed schema stores error_log / uploaded_at and derives failed
    // count from total_records - success_count (there is no failed_count column).
    const [rows] = await db.query(
      `SELECT import_id, file_name, total_records, success_count,
              GREATEST(total_records - success_count, 0) AS failed_count,
              error_log AS error_logs, uploaded_at AS created_at
       FROM ATTENDANCE_IMPORT
       ${where}
       ORDER BY import_id DESC
       LIMIT ?`,
      params
    );

    return res.status(200).json({ success: true, data: rows });
  } catch (error) {
    console.error('Get Attendance Imports Error:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};
// ============================================================================
// ATTENDANCE SETTINGS & AUTO-RECALCULATION ENGINE
// ============================================================================
async function getOrCreateAttendanceSettings(companyId) {
  const cid = companyId || 1;
  const [rows] = await db.query('SELECT * FROM attendance_settings WHERE company_id = ? LIMIT 1', [cid]);
  if (rows.length > 0) return rows[0];
  await db.query('INSERT IGNORE INTO attendance_settings (company_id) VALUES (?)', [cid]);
  const [fresh] = await db.query('SELECT * FROM attendance_settings WHERE company_id = ? LIMIT 1', [cid]);
  return fresh[0] || {
    company_id: cid,
    shift_start: '09:00',
    shift_end: '18:00',
    grace_minutes: 30,
    no_punch_default_status: 'Absent',
    enable_late_warning_quota: 1,
    late_warning_limit: 3,
    late_penalty_action: 'Half-Day',
    full_day_minutes: 480,
    half_day_minutes: 240,
    missing_out_punch_status: 'Missing',
    enable_early_going_rule: 1,
    early_going_grace_minutes: 15,
    early_going_action: 'Half-Day',
    enable_auto_overtime: 1,
    overtime_buffer_minutes: 30,
    overtime_rate_multiplier: 1.5,
    overtime_fixed_hourly_rate: 0,
    enable_leave_integration: 1,
    auto_sync_payroll_deduction: 1,
  };
}

function toMinsFromHHMM(timeStr) {
  if (!timeStr) return null;
  const parts = String(timeStr).trim().split(':');
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1] || '0', 10);
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  return h * 60 + m;
}

function computeStatusFromRules({
  inTime,
  outTime,
  workMinutes,
  lateIn,
  settings,
  priorLateCountThisMonth = 0,
  isApprovedLeave = false,
  isSunday = false,
}) {
  const shiftStartMins = toMinsFromHHMM(settings.shift_start) ?? 540; // 09:00
  const shiftEndMins = toMinsFromHHMM(settings.shift_end) ?? 1080;  // 18:00
  const graceMins = parseInt(settings.grace_minutes ?? 30, 10);
  const cutoffMins = shiftStartMins + graceMins;

  const fullDayMins = parseInt(settings.full_day_minutes ?? 480, 10);
  const halfDayMins = parseInt(settings.half_day_minutes ?? 240, 10);
  const earlyGraceMins = parseInt(settings.early_going_grace_minutes ?? 15, 10);

  const inMins = toMinsFromHHMM(inTime);
  const outMins = toMinsFromHHMM(outTime);
  const calcWorkMins = workMinutes > 0
    ? workMinutes
    : (inMins !== null && outMins !== null && outMins > inMins ? outMins - inMins : 0);

  let status = 'Present';

  // 1. Leave Integration: Approved Leave date overrides absence
  if (isApprovedLeave && !inTime && !outTime) {
    status = 'On Leave';
  }
  // 1B. Sunday (Weekly Off) check when no punches recorded
  else if (isSunday && !inTime && !outTime && calcWorkMins === 0) {
    status = 'Weekly Off';
  }
  // 2. Auto Absent / Auto Present when both punches missing
  else if (!inTime && !outTime && calcWorkMins === 0) {
    status = settings.no_punch_default_status || 'Absent';
  }
  // 3. Missing In-Punch or Out-Punch Rule
  else if ((inTime && !outTime) || (!inTime && outTime)) {
    status = settings.missing_out_punch_status || 'Missing';
  }
  // 4. Half-Day / Full-Day Working Hours Rule
  else if (calcWorkMins > 0 && calcWorkMins < halfDayMins) {
    status = 'Absent';
  } else if (calcWorkMins >= halfDayMins && calcWorkMins < fullDayMins) {
    status = 'Half-Day';
  }
  // 5. Early Going Rule
  else if (
    Number(settings.enable_early_going_rule ?? 1) === 1 &&
    outMins !== null &&
    outMins < (shiftEndMins - earlyGraceMins) &&
    (settings.early_going_action || 'Half-Day') !== 'Ignore'
  ) {
    status = settings.early_going_action || 'Half-Day';
  }
  // 6. Late Mark Rule + Warning Quota
  else if ((lateIn > 0) || (inMins !== null && inMins > cutoffMins)) {
    const quotaEnabled = Number(settings.enable_late_warning_quota ?? 1) === 1;
    const warningLimit = parseInt(settings.late_warning_limit ?? 3, 10);
    if (quotaEnabled && priorLateCountThisMonth >= warningLimit) {
      status = settings.late_penalty_action === 'Short Leave' ? 'Short Leave' : 'Half-Day';
    } else {
      status = 'Late';
    }
  }

  // 7. Auto Overtime (OT) Rule
  let overtimeHours = 0;
  if (Number(settings.enable_auto_overtime ?? 1) === 1 && outMins !== null) {
    const extra = outMins - shiftEndMins;
    const buffer = parseInt(settings.overtime_buffer_minutes ?? 30, 10);
    if (extra >= buffer) {
      overtimeHours = Number((extra / 60).toFixed(2));
    }
  }

  return { status, overtimeHours };
}

exports.getAttendanceSettings = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const settings = await getOrCreateAttendanceSettings(companyId);
    return res.status(200).json({ success: true, data: settings });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.saveAttendanceSettings = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const {
      shift_start = '09:00',
      shift_end = '18:00',
      grace_minutes = 30,
      no_punch_default_status = 'Absent',
      enable_late_warning_quota = 1,
      late_warning_limit = 3,
      late_penalty_action = 'Half-Day',
      full_day_minutes = 480,
      half_day_minutes = 240,
      missing_out_punch_status = 'Missing',
      enable_early_going_rule = 1,
      early_going_grace_minutes = 15,
      early_going_action = 'Half-Day',
      enable_auto_overtime = 1,
      overtime_buffer_minutes = 30,
      overtime_rate_multiplier = 1.5,
      overtime_fixed_hourly_rate = 0,
      enable_leave_integration = 1,
      auto_sync_payroll_deduction = 1,
      recalculate = true,
    } = req.body;

    await db.query(
      `INSERT INTO attendance_settings
       (company_id, shift_start, shift_end, grace_minutes, no_punch_default_status,
        enable_late_warning_quota, late_warning_limit, late_penalty_action,
        full_day_minutes, half_day_minutes, missing_out_punch_status,
        enable_early_going_rule, early_going_grace_minutes, early_going_action,
        enable_auto_overtime, overtime_buffer_minutes, overtime_rate_multiplier, overtime_fixed_hourly_rate,
        enable_leave_integration, auto_sync_payroll_deduction)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         shift_start = VALUES(shift_start),
         shift_end = VALUES(shift_end),
         grace_minutes = VALUES(grace_minutes),
         no_punch_default_status = VALUES(no_punch_default_status),
         enable_late_warning_quota = VALUES(enable_late_warning_quota),
         late_warning_limit = VALUES(late_warning_limit),
         late_penalty_action = VALUES(late_penalty_action),
         full_day_minutes = VALUES(full_day_minutes),
         half_day_minutes = VALUES(half_day_minutes),
         missing_out_punch_status = VALUES(missing_out_punch_status),
         enable_early_going_rule = VALUES(enable_early_going_rule),
         early_going_grace_minutes = VALUES(early_going_grace_minutes),
         early_going_action = VALUES(early_going_action),
         enable_auto_overtime = VALUES(enable_auto_overtime),
         overtime_buffer_minutes = VALUES(overtime_buffer_minutes),
         overtime_rate_multiplier = VALUES(overtime_rate_multiplier),
         overtime_fixed_hourly_rate = VALUES(overtime_fixed_hourly_rate),
         enable_leave_integration = VALUES(enable_leave_integration),
         auto_sync_payroll_deduction = VALUES(auto_sync_payroll_deduction)`,
      [
        companyId,
        shift_start,
        shift_end,
        parseInt(grace_minutes, 10) || 0,
        no_punch_default_status || 'Absent',
        enable_late_warning_quota ? 1 : 0,
        parseInt(late_warning_limit, 10) || 3,
        late_penalty_action || 'Half-Day',
        parseInt(full_day_minutes, 10) || 480,
        parseInt(half_day_minutes, 10) || 240,
        missing_out_punch_status || 'Missing',
        enable_early_going_rule ? 1 : 0,
        parseInt(early_going_grace_minutes, 10) || 0,
        early_going_action || 'Half-Day',
        enable_auto_overtime ? 1 : 0,
        parseInt(overtime_buffer_minutes, 10) || 0,
        parseFloat(overtime_rate_multiplier) || 1.5,
        parseFloat(overtime_fixed_hourly_rate) || 0,
        enable_leave_integration ? 1 : 0,
        auto_sync_payroll_deduction ? 1 : 0,
      ]
    );

    const settings = await getOrCreateAttendanceSettings(companyId);
    let recalculatedCount = 0;

    // Auto-recalculate existing Biometric Attendance logs
    if (recalculate) {
      let approvedLeaves = [];
      if (Number(settings.enable_leave_integration) === 1) {
        try {
          const [lRows] = await db.query(
            `SELECT employee_id, DATE_FORMAT(start_date, '%Y-%m-%d') AS start_d, DATE_FORMAT(end_date, '%Y-%m-%d') AS end_d
             FROM LEAVE_REQUEST WHERE status = 'APPROVED'`
          );
          approvedLeaves = lRows;
        } catch (_) {}
      }

      const [records] = await db.query(
        `SELECT a.attendance_id, a.employee_id,
                DATE_FORMAT(a.work_date, '%Y-%m-%d') AS work_d,
                DATE_FORMAT(a.work_date, '%Y-%m') AS ym,
                TIME_FORMAT(a.check_in, '%H:%i') AS in_time,
                TIME_FORMAT(a.check_out, '%H:%i') AS out_time
         FROM ATTENDANCE a
         JOIN EMPLOYEE e ON a.employee_id = e.employee_id
         WHERE e.company_id = ?
         ORDER BY a.employee_id ASC, a.work_date ASC`,
        [companyId]
      );

      const monthlyLateMap = {};
      for (const rec of records) {
        const key = `${rec.employee_id}_${rec.ym}`;
        const priorLates = monthlyLateMap[key] || 0;
        const isApprovedLeave = approvedLeaves.some(
          (l) => l.employee_id === rec.employee_id && rec.work_d >= l.start_d && rec.work_d <= l.end_d
        );
        const { status, overtimeHours } = computeStatusFromRules({
          inTime: rec.in_time,
          outTime: rec.out_time,
          workMinutes: 0,
          lateIn: 0,
          settings,
          priorLateCountThisMonth: priorLates,
          isApprovedLeave,
          isSunday: new Date(`${rec.work_d}T00:00:00`).getDay() === 0,
        });
        if (status === 'Late') monthlyLateMap[key] = priorLates + 1;

        await db.query(
          'UPDATE ATTENDANCE SET status = ?, overtime_hours = ? WHERE attendance_id = ?',
          [status, overtimeHours, rec.attendance_id]
        );
        recalculatedCount++;
      }

      // Sync Attendance Absence / Half-Day Deductions to Payroll fields if enabled
      if (Number(settings.auto_sync_payroll_deduction) === 1) {
        const now = new Date();
        const curYm = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
        const [empSummary] = await db.query(
          `SELECT e.employee_id, COALESCE(e.salary_base, 0) AS salary_base,
                  SUM(CASE WHEN a.status = 'Absent' THEN 1 ELSE 0 END) AS absent_days,
                  SUM(CASE WHEN a.status = 'Half-Day' THEN 1 ELSE 0 END) AS half_days
           FROM EMPLOYEE e
           LEFT JOIN ATTENDANCE a ON a.employee_id = e.employee_id AND DATE_FORMAT(a.work_date, '%Y-%m') = ?
           WHERE e.company_id = ?
           GROUP BY e.employee_id, e.salary_base`,
          [curYm, companyId]
        );
        for (const es of empSummary) {
          const dailyRate = (parseFloat(es.salary_base) || 0) / 30.0;
          const unpaidEquivalent = (Number(es.absent_days) || 0) + (Number(es.half_days) || 0) * 0.5;
          const deduction = Number((unpaidEquivalent * dailyRate).toFixed(2));
          try {
            await db.query(
              'UPDATE EMPLOYEE SET unpaid_leaves_taken = ?, total_leave_deduction = ? WHERE employee_id = ?',
              [Math.round(unpaidEquivalent), deduction, es.employee_id]
            );
          } catch (_) {}
        }
      }
    }

    return res.status(200).json({
      success: true,
      message: `Attendance rules saved & ${recalculatedCount} biometric records recalculated!`,
      data: settings,
      recalculatedCount,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};
// ============================================================================
// ATTENDANCE MASTER (Status, Shift, Holiday, Weekly Off, Leave Type, Device)
// ============================================================================
const MASTER_TABLES = {
  status: 'att_master_status',
  shift: 'att_master_shift',
  holiday: 'att_master_holiday',
  weekly_off: 'att_master_weekly_off',
  leave_type: 'att_master_leave_type',
  device: 'att_master_device',
};

async function seedAttendanceMastersIfEmpty(companyId) {
  const [st] = await db.query('SELECT COUNT(*) AS cnt FROM att_master_status WHERE company_id = ?', [companyId]);
  if (Number(st[0]?.cnt || 0) === 0) {
    const defaults = [
      ['P', 'Present', 1, '#059669'],
      ['A', 'Absent', 0, '#DC2626'],
      ['HD', 'Half Day', 1, '#7C3AED'],
      ['L', 'Leave', 1, '#D97706'],
      ['WO', 'Weekly Off', 1, '#0284C7'],
      ['H', 'Holiday', 1, '#0EA5E9'],
      ['OD', 'On Duty', 1, '#10B981'],
      ['SHL', 'Short Leave', 1, '#F59E0B'],
    ];
    for (const [code, name, isPaid, color] of defaults) {
      await db.query(
        'INSERT INTO att_master_status (company_id, code, name, is_paid, color_hex) VALUES (?, ?, ?, ?, ?)',
        [companyId, code, name, isPaid, color]
      );
    }
  }

  const [sh] = await db.query('SELECT COUNT(*) AS cnt FROM att_master_shift WHERE company_id = ?', [companyId]);
  if (Number(sh[0]?.cnt || 0) === 0) {
    await db.query(
      'INSERT INTO att_master_shift (company_id, shift_name, start_time, end_time, break_minutes) VALUES (?, ?, ?, ?, ?)',
      [companyId, 'General Shift', '09:00', '18:00', 60]
    );
  }

  const [wo] = await db.query('SELECT COUNT(*) AS cnt FROM att_master_weekly_off WHERE company_id = ?', [companyId]);
  if (Number(wo[0]?.cnt || 0) === 0) {
    await db.query(
      'INSERT INTO att_master_weekly_off (company_id, rule_name, off_days, saturday_rule) VALUES (?, ?, ?, ?)',
      [companyId, 'Standard Weekly Off', 'Sunday', 'Alternate (2nd & 4th Off)']
    );
  }

  const [lt] = await db.query('SELECT COUNT(*) AS cnt FROM att_master_leave_type WHERE company_id = ?', [companyId]);
  if (Number(lt[0]?.cnt || 0) === 0) {
      const leaves = [
        ['CL', 'Casual Leave', 12, 1],
        ['SL', 'Sick Leave', 8, 1],
        ['PL', 'Paid Leave', 15, 1],
        ['SHL', 'Short Leave', 12, 1],
      ];
    for (const [code, name, quota, paid] of leaves) {
      await db.query(
        'INSERT INTO att_master_leave_type (company_id, leave_code, leave_name, annual_quota, is_paid) VALUES (?, ?, ?, ?, ?)',
        [companyId, code, name, quota, paid]
      );
    }
  }
}

exports.getAttendanceMasters = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    await seedAttendanceMastersIfEmpty(companyId);

    const [statuses] = await db.query('SELECT * FROM att_master_status WHERE company_id = ? ORDER BY id ASC', [companyId]);
    const [shifts] = await db.query('SELECT * FROM att_master_shift WHERE company_id = ? ORDER BY id ASC', [companyId]);
    const [holidays] = await db.query(
      "SELECT id, company_id, holiday_name, DATE_FORMAT(holiday_date, '%Y-%m-%d') AS holiday_date, holiday_type FROM att_master_holiday WHERE company_id = ? ORDER BY holiday_date ASC",
      [companyId]
    );
    const [weeklyOffs] = await db.query('SELECT * FROM att_master_weekly_off WHERE company_id = ? ORDER BY id ASC', [companyId]);
    const [leaveTypes] = await db.query('SELECT * FROM att_master_leave_type WHERE company_id = ? ORDER BY id ASC', [companyId]);
    const [devices] = await db.query('SELECT * FROM att_master_device WHERE company_id = ? ORDER BY id ASC', [companyId]);

    return res.status(200).json({
      success: true,
      data: { statuses, shifts, holidays, weeklyOffs, leaveTypes, devices },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.addAttendanceMasterItem = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const { type } = req.params;
    const b = req.body || {};

    if (type === 'status') {
      await db.query(
        'INSERT INTO att_master_status (company_id, code, name, is_paid, color_hex) VALUES (?, ?, ?, ?, ?)',
        [companyId, String(b.code || '').toUpperCase(), b.name, b.is_paid ? 1 : 0, b.color_hex || '#059669']
      );
    } else if (type === 'shift') {
      await db.query(
        'INSERT INTO att_master_shift (company_id, shift_name, start_time, end_time, break_minutes) VALUES (?, ?, ?, ?, ?)',
        [companyId, b.shift_name, b.start_time || '09:00', b.end_time || '18:00', parseInt(b.break_minutes, 10) || 60]
      );
    } else if (type === 'holiday') {
      await db.query(
        'INSERT INTO att_master_holiday (company_id, holiday_name, holiday_date, holiday_type) VALUES (?, ?, ?, ?)',
        [companyId, b.holiday_name, b.holiday_date, b.holiday_type || 'Public Holiday']
      );
    } else if (type === 'weekly_off') {
      await db.query(
        'INSERT INTO att_master_weekly_off (company_id, rule_name, off_days, saturday_rule) VALUES (?, ?, ?, ?)',
        [companyId, b.rule_name, b.off_days || 'Sunday', b.saturday_rule || 'All Working']
      );
    } else if (type === 'leave_type') {
      await db.query(
        'INSERT INTO att_master_leave_type (company_id, leave_code, leave_name, annual_quota, is_paid) VALUES (?, ?, ?, ?, ?)',
        [companyId, String(b.leave_code || '').toUpperCase(), b.leave_name, parseInt(b.annual_quota, 10) || 12, b.is_paid ? 1 : 0]
      );
    } else if (type === 'device') {
      await db.query(
        'INSERT INTO att_master_device (company_id, device_name, device_code, device_type, ip_address, location, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [companyId, b.device_name, b.device_code, b.device_type || 'Biometric', b.ip_address || '', b.location || '', b.status || 'Active']
      );
    } else {
      return res.status(400).json({ success: false, message: 'Invalid master type.' });
    }

    return res.status(201).json({ success: true, message: 'Master record added successfully!' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.deleteAttendanceMasterItem = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const { type, id } = req.params;
    const table = MASTER_TABLES[type];
    if (!table) return res.status(400).json({ success: false, message: 'Invalid master type.' });

    await db.query(`DELETE FROM ${table} WHERE id = ? AND company_id = ?`, [id, companyId]);
    return res.status(200).json({ success: true, message: 'Deleted successfully.' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.bulkAddHolidays = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const holidays = Array.isArray(req.body?.holidays) ? req.body.holidays : [];
    if (holidays.length === 0) {
      return res.status(400).json({ success: false, message: 'No holidays provided.' });
    }

    const [existing] = await db.query(
      "SELECT DATE_FORMAT(holiday_date, '%Y-%m-%d') AS d FROM att_master_holiday WHERE company_id = ?",
      [companyId]
    );
    const existingDates = new Set(existing.map((r) => r.d));

    let inserted = 0;
    let skipped = 0;
    for (const h of holidays) {
      const name = String(h.holiday_name || '').trim();
      const dateStr = String(h.holiday_date || '').trim().slice(0, 10);
      const type = String(h.holiday_type || 'Public Holiday').trim();
      if (!name || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
        skipped++;
        continue;
      }
      if (existingDates.has(dateStr)) {
        skipped++;
        continue;
      }
      await db.query(
        'INSERT INTO att_master_holiday (company_id, holiday_name, holiday_date, holiday_type) VALUES (?, ?, ?, ?)',
        [companyId, name, dateStr, type]
      );
      existingDates.add(dateStr);
      inserted++;
    }

    return res.status(201).json({
      success: true,
      message: `${inserted} holidays imported (${skipped} duplicate/skipped).`,
      inserted,
      skipped,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.importHolidaysExcel = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Please upload an Excel or CSV file.' });
    }

    const workbook = xlsx.read(req.file.buffer, { type: 'buffer', cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const rows = xlsx.utils.sheet_to_json(workbook.Sheets[sheetName], { defval: '' });

    const [existing] = await db.query(
      "SELECT DATE_FORMAT(holiday_date, '%Y-%m-%d') AS d FROM att_master_holiday WHERE company_id = ?",
      [companyId]
    );
    const existingDates = new Set(existing.map((r) => r.d));

    let inserted = 0;
    let skipped = 0;

    for (const row of rows) {
      const norm = {};
      for (const [k, v] of Object.entries(row)) {
        norm[String(k).toLowerCase().replace(/[^a-z0-9]/g, '')] = v;
      }
      const name = String(
        norm.holidayname || norm.holiday || norm.name || norm.occasion || norm.title || ''
      ).trim();
      const rawDate = norm.holidaydate || norm.date || '';
      const type = String(norm.holidaytype || norm.type || 'Public Holiday').trim();

      let dateStr = '';
      if (rawDate instanceof Date && !Number.isNaN(rawDate.getTime())) {
        const y = rawDate.getFullYear();
        const m = String(rawDate.getMonth() + 1).padStart(2, '0');
        const d = String(rawDate.getDate()).padStart(2, '0');
        dateStr = `${y}-${m}-${d}`;
      } else {
        const txt = String(rawDate).trim();
        if (/^\d{4}-\d{2}-\d{2}/.test(txt)) {
          dateStr = txt.slice(0, 10);
        } else if (/^\d{1,2}[\/-]\d{1,2}[\/-]\d{4}$/.test(txt)) {
          const [dd, mm, yyyy] = txt.split(/[\/-]/);
          dateStr = `${yyyy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`;
        }
      }

      if (!name || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr) || existingDates.has(dateStr)) {
        skipped++;
        continue;
      }

      await db.query(
        'INSERT INTO att_master_holiday (company_id, holiday_name, holiday_date, holiday_type) VALUES (?, ?, ?, ?)',
        [companyId, name, dateStr, type || 'Public Holiday']
      );
      existingDates.add(dateStr);
      inserted++;
    }

    return res.status(201).json({
      success: true,
      message: `Excel imported: ${inserted} holidays added (${skipped} skipped/duplicates).`,
      inserted,
      skipped,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};
// ==========================================
// HR CATEGORY MASTER
// ==========================================

async function ensureHrCategoriesSetup(companyId) {
  await db.query(`
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
    await db.query('ALTER TABLE employee ADD COLUMN hr_category_id INT NULL');
  } catch (_) {
    try { await db.query('ALTER TABLE EMPLOYEE ADD COLUMN hr_category_id INT NULL'); } catch (__) {}
  }


    try { await db.query('ALTER TABLE hr_categories ADD COLUMN default_template_id INT NULL AFTER description'); } catch (_) {}
    try { await db.query('ALTER TABLE hr_categories ADD COLUMN default_gross DECIMAL(15,2) NULL AFTER default_template_id'); } catch (_) {}


  const [cnt] = await db.query('SELECT COUNT(*) AS cnt FROM hr_categories WHERE company_id = ?', [companyId]);
  if (Number(cnt[0]?.cnt || 0) === 0) {
    const defaults = [
      ['Junior Developer', 'CAT-JD', 'Entry-level software developer'],
      ['Senior Developer', 'CAT-SD', 'Experienced software developer'],
      ['Team Leader', 'CAT-TL', 'Team leadership & delivery role'],
      ['Senior Accountant', 'CAT-SA', 'Senior finance & accounting role'],
      ['Finance Manager', 'CAT-FM', 'Finance department management role']
    ];
    for (const [name, code, desc] of defaults) {
      await db.query(
        `INSERT IGNORE INTO hr_categories (company_id, category_name, category_code, description, is_active)
         VALUES (?, ?, ?, ?, 1)`,
        [companyId, name, code, desc]
      );
    }
  }
}

exports.getHrCategories = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    await ensureHrCategoriesSetup(companyId);

    const search = String(req.query.search || '').trim();
    const status = String(req.query.status || 'ALL').trim().toUpperCase();

       let sql = `
         SELECT c.category_id, c.company_id, c.category_name, c.category_code,
                c.description, c.default_template_id, c.default_gross,
                MAX(t.template_name) AS default_template_name,
                c.is_active, c.created_at, c.updated_at,
                COUNT(e.employee_id) AS employee_count
         FROM hr_categories c
         LEFT JOIN salary_templates t
           ON t.template_id = c.default_template_id AND t.company_id = c.company_id
         LEFT JOIN EMPLOYEE e
           ON e.hr_category_id = c.category_id
          AND e.company_id = c.company_id
          AND LOWER(COALESCE(e.status, 'active')) = 'active'
         WHERE c.company_id = ?`;
    const params = [companyId];

    if (status === 'ACTIVE') {
      sql += ' AND c.is_active = 1';
    } else if (status === 'INACTIVE') {
      sql += ' AND c.is_active = 0';
    }
    if (search) {
      sql += ' AND (c.category_name LIKE ? OR c.category_code LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    sql += ' GROUP BY c.category_id ORDER BY c.category_name ASC';
    try {
      const [rows] = await db.query(sql, params);
      return res.status(200).json({ success: true, data: rows });
    } catch (queryErr) {
      if (queryErr.code !== 'ER_BAD_FIELD_ERROR') throw queryErr;
      let fallbackSql = `
        SELECT c.category_id, c.company_id, c.category_name, c.category_code,
               c.description, c.default_template_id, c.default_gross,
               MAX(t.template_name) AS default_template_name,
               c.is_active, c.created_at, c.updated_at,
               0 AS employee_count
        FROM hr_categories c
        LEFT JOIN salary_templates t
          ON t.template_id = c.default_template_id AND t.company_id = c.company_id
        WHERE c.company_id = ?`;
      const fbParams = [companyId];
      if (status === 'ACTIVE') fallbackSql += ' AND c.is_active = 1';
      else if (status === 'INACTIVE') fallbackSql += ' AND c.is_active = 0';
      if (search) {
        fallbackSql += ' AND (c.category_name LIKE ? OR c.category_code LIKE ?)';
        fbParams.push(`%${search}%`, `%${search}%`);
      }
      fallbackSql += ' GROUP BY c.category_id ORDER BY c.category_name ASC';
      const [rows] = await db.query(fallbackSql, fbParams);
      return res.status(200).json({ success: true, data: rows });
    }
  } catch (err) {
    console.error('getHrCategories error:', err);
    return res.status(500).json({ success: false, message: 'Failed to load HR categories.', error: err.message });
  }
};

exports.createHrCategory = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    await ensureHrCategoriesSetup(companyId);

        const {
          category_name,
          category_code,
          description = '',
          default_template_id = null,
          default_gross = null,
          is_active = true
        } = req.body || {};
        const tplId = default_template_id ? parseInt(default_template_id, 10) || null : null;
        const defGross = (default_gross !== null && default_gross !== '' && !Number.isNaN(Number(default_gross)))
          ? Number(default_gross)
          : null;
    const cleanName = String(category_name || '').trim();
    const cleanCode = String(category_code || '').trim().toUpperCase();

    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Category Name is required.' });
    }
    if (!cleanCode) {
      return res.status(400).json({ success: false, message: 'Category Code is required.' });
    }

    const [dup] = await db.query(
      'SELECT category_id FROM hr_categories WHERE company_id = ? AND category_code = ? LIMIT 1',
      [companyId, cleanCode]
    );
    if (dup.length) {
      return res.status(409).json({ success: false, message: `Category Code "${cleanCode}" already exists.` });
    }

    const userId = req.user && req.user.userId ? req.user.userId : null;
    const [result] = await db.query(
         `INSERT INTO hr_categories (company_id, category_name, category_code, description, default_template_id, default_gross, is_active, created_by)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
         [companyId, cleanName, cleanCode, String(description || '').trim() || null, tplId, defGross, is_active ? 1 : 0, userId]
     );
    return res.status(201).json({
      success: true,
      message: 'HR Category created successfully!',
      category_id: result.insertId
    });
  } catch (err) {
    console.error('createHrCategory error:', err);
    return res.status(500).json({ success: false, message: 'Failed to create HR category.' });
  }
};

exports.updateHrCategory = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const id = parseInt(req.params.id, 10);
    const {
        category_name,
        category_code,
        description = '',
        default_template_id = null,
        default_gross = null,
        is_active = true
      } = req.body || {};
    const tplId = default_template_id ? parseInt(default_template_id, 10) || null : null;
    const defGross = (default_gross !== null && default_gross !== '' && !Number.isNaN(Number(default_gross)))
        ? Number(default_gross)
        : null;
    const cleanName = String(category_name || '').trim();
    const cleanCode = String(category_code || '').trim().toUpperCase();

    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Category Name is required.' });
    }
    if (!cleanCode) {
      return res.status(400).json({ success: false, message: 'Category Code is required.' });
    }

    const [dup] = await db.query(
      'SELECT category_id FROM hr_categories WHERE company_id = ? AND category_code = ? AND category_id != ? LIMIT 1',
      [companyId, cleanCode, id]
    );
    if (dup.length) {
      return res.status(409).json({ success: false, message: `Category Code "${cleanCode}" already exists.` });
    }

    const [result] = await db.query(
         `UPDATE hr_categories
          SET category_name = ?, category_code = ?, description = ?, default_template_id = ?, default_gross = ?, is_active = ?
          WHERE category_id = ? AND company_id = ?`,
         [cleanName, cleanCode, String(description || '').trim() || null, tplId, defGross, is_active ? 1 : 0, id, companyId]
    );
    if (!result.affectedRows) {
      return res.status(404).json({ success: false, message: 'HR Category not found.' });
    }
    return res.status(200).json({ success: true, message: 'HR Category updated successfully!' });
  } catch (err) {
    console.error('updateHrCategory error:', err);
    return res.status(500).json({ success: false, message: 'Failed to update HR category.' });
  }
};

exports.deleteHrCategory = async (req, res) => {
  try {
    const companyId = resolveCompanyId(req) || 1;
    const id = parseInt(req.params.id, 10);
    const deactivateOnly = req.query.deactivate === 'true' || (req.body && req.body.deactivate === true);

    const [existing] = await db.query(
      'SELECT category_id, category_name FROM hr_categories WHERE category_id = ? AND company_id = ? LIMIT 1',
      [id, companyId]
    );
    if (!existing.length) {
      return res.status(404).json({ success: false, message: 'HR Category not found.' });
    }

    const [activeEmps] = await db.query(
      `SELECT COUNT(*) AS cnt FROM EMPLOYEE
       WHERE company_id = ? AND hr_category_id = ? AND LOWER(COALESCE(status, 'active')) = 'active'`,
      [companyId, id]
    );
    const empCount = Number(activeEmps[0]?.cnt || 0);

    if (empCount > 0) {
      if (deactivateOnly) {
        await db.query(
          'UPDATE hr_categories SET is_active = 0 WHERE category_id = ? AND company_id = ?',
          [id, companyId]
        );
        return res.status(200).json({
          success: true,
          deactivated: true,
          message: `"${existing[0].category_name}" deactivated (${empCount} employees remain assigned).`
        });
      }
      return res.status(409).json({
        success: false,
        canDeactivate: true,
        employee_count: empCount,
        message: `Cannot delete "${existing[0].category_name}" because ${empCount} active employee(s) are assigned to it. You can deactivate it instead.`
      });
    }

    // Clear historical inactive/terminated references without deleting any employee records
    await db.query(
      'UPDATE EMPLOYEE SET hr_category_id = NULL WHERE company_id = ? AND hr_category_id = ?',
      [companyId, id]
    );
    await db.query(
      'DELETE FROM hr_categories WHERE category_id = ? AND company_id = ?',
      [id, companyId]
    );
    return res.status(200).json({
      success: true,
      deactivated: false,
      message: `"${existing[0].category_name}" deleted permanently!`
    });
  } catch (err) {
    console.error('deleteHrCategory error:', err);
    return res.status(500).json({ success: false, message: 'Failed to delete HR category.' });
  }
};

exports.assignCategoryMembers = async (req, res) => {
  const conn = await db.getConnection();
  try {
    const companyId = resolveCompanyId(req) || 1;
    await ensureHrCategoriesSetup(companyId);
    const categoryId = parseInt(req.params.id, 10);
    if (!categoryId) {
      return res.status(400).json({ success: false, message: 'Valid category ID is required.' });
    }

    const [catRows] = await conn.query(
      'SELECT category_id, category_name FROM hr_categories WHERE category_id = ? AND company_id = ? LIMIT 1',
      [categoryId, companyId]
    );
    if (!catRows.length) {
      return res.status(404).json({ success: false, message: 'HR Category not found.' });
    }

    const rawIds = Array.isArray(req.body?.employee_ids) ? req.body.employee_ids : [];
    const empIds = [...new Set(rawIds.map((id) => parseInt(id, 10)).filter((id) => Number.isInteger(id) && id > 0))];

    await conn.beginTransaction();
    await conn.query(
      'UPDATE EMPLOYEE SET hr_category_id = NULL WHERE company_id = ? AND hr_category_id = ?',
      [companyId, categoryId]
    );
    if (empIds.length > 0) {
      const placeholders = empIds.map(() => '?').join(',');
      await conn.query(
        `UPDATE EMPLOYEE SET hr_category_id = ? WHERE company_id = ? AND employee_id IN (${placeholders})`,
        [categoryId, companyId, ...empIds]
      );
    }
    await conn.commit();

    return res.status(200).json({
      success: true,
      assigned_count: empIds.length,
      message: `Assigned ${empIds.length} member(s) to "${catRows[0].category_name}"!`
    });
  } catch (err) {
    await conn.rollback();
    console.error('assignCategoryMembers error:', err);
    return res.status(500).json({ success: false, message: 'Failed to assign category members.' });
  } finally {
    conn.release();
  }
};