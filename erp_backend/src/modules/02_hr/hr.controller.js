const db = require('../../config/db');
const xlsx = require('xlsx');

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
      unpaid_leave_per_day_deduction
    } = req.body;

    if (!emp_code || !full_name || !department_id) {
      return res.status(400).json({
        success: false,
        message: 'Employee Code, Full Name, and Department are required.'
      });
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

    // Resolve branch_id
    let effBranchId = branch_id;
    if (!effBranchId) {
      try {
        const [deptRows] = await db.query('SELECT branch_id FROM DEPARTMENT WHERE department_id = ?', [department_id]);
        effBranchId = (deptRows.length > 0 && deptRows[0].branch_id) ? deptRows[0].branch_id : 1;
      } catch (_) {
        effBranchId = 1;
      }
    }

    const calculatedPerDayDeduction = (unpaid_leave_per_day_deduction !== undefined && unpaid_leave_per_day_deduction !== '' && unpaid_leave_per_day_deduction !== null)
      ? parseFloat(unpaid_leave_per_day_deduction)
      : (salary_base ? (parseFloat(salary_base) / 30.0) : 0.00);

    const [result] = await db.query(
      `INSERT INTO EMPLOYEE
       (branch_id, department_id, emp_code, biometric_emp_code, full_name, designation, role, phone, email, join_date, status,
        employment_type, weekly_off, salary_grade, salary_base,
        age, gender, dob, city, state, address, aadhar_number, pan_number, emergency_contact,
        leave_balance_casual, leave_balance_sick, leave_balance_paid, unpaid_leave_limit, unpaid_leave_per_day_deduction)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
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

    return res.status(201).json({
      success: true,
      message: 'Employee successfully onboarded!',
      employee_id: result.insertId
    });

  } catch (error) {
    console.error('Add Employee Error:', error);
    return res.status(500).json({ success: false, message: 'Database error', error: error.message });
  }
};
// 2. GET ALL EMPLOYEES (With Lifecycle & Phone/Email details)
exports.getEmployees = async (req, res) => {
  try {
    let employees = [];
    try {
      const [rows] = await db.query(
        `SELECT e.employee_id, e.user_id, e.emp_code, e.biometric_emp_code, e.full_name, e.designation, e.status,
                e.phone, e.email, e.exit_date, e.exit_reason, e.department_id, e.branch_id,
                e.salary_base, e.salary_grade,
                COALESCE(r.name, e.role, 'Employee') AS role_name,
                d.name as department_name, b.name as branch_name
         FROM EMPLOYEE e
         LEFT JOIN USER u ON e.user_id = u.user_id
         LEFT JOIN ROLE r ON u.role_id = r.role_id
         LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
         LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
         ORDER BY e.employee_id DESC`
      );
      employees = rows;
    } catch (_) {
      const [rows] = await db.query(
        `SELECT e.employee_id, e.user_id, e.emp_code, e.biometric_emp_code, e.full_name, e.designation, e.status,
                e.phone, e.email, e.exit_date, e.exit_reason, e.department_id, e.branch_id,
                e.salary_base, e.salary_grade,
                COALESCE(r.name, 'Employee') AS role_name,
                d.name as department_name, b.name as branch_name
         FROM EMPLOYEE e
         LEFT JOIN USER u ON e.user_id = u.user_id
         LEFT JOIN ROLE r ON u.role_id = r.role_id
         LEFT JOIN BRANCH b ON e.branch_id = b.branch_id
         LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
         ORDER BY e.employee_id DESC`
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
      const { role_name } = req.body;

      if (!role_name) {
        return res.status(400).json({ success: false, message: 'Role name is required.' });
      }

      try {
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
      } catch (_) {}

      await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [role_name, id]);

      const [empRows] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (empRows.length > 0 && empRows[0].user_id) {
        const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role_name]);
        if (roleRows.length > 0) {
          await db.query('UPDATE USER SET role_id = ? WHERE user_id = ?', [roleRows[0].role_id, empRows[0].user_id]);
        }
      }

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
    const [result] = await db.query('SELECT COUNT(*) as total FROM EMPLOYEE WHERE status = "active"');
    return res.status(200).json({ success: true, total: result[0].total });
  } catch (error) {
    return res.status(500).json({ success: false, total: 0 });
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

    // Empty rows filter out karna
    const validRows = aoa.filter(r => Array.isArray(r) && r.some(c => c !== null && c !== undefined && String(c).trim() !== ''));

    if (validRows.length === 0) {
      return res.status(400).json({ success: false, message: 'The uploaded file is empty.' });
    }

    // Auto detect Header row
    let headerIdx = 0;
    for (let i = 0; i < Math.min(validRows.length, 10); i++) {
      const rowText = validRows[i].join(',').toLowerCase();
      if (rowText.includes('emp') || rowText.includes('user') || rowText.includes('date') || rowText.includes('punch') || rowText.includes('time') || rowText.includes('status')) {
        headerIdx = i;
        break;
      }
    }

    const rawHeaders = validRows[headerIdx];
    let isSingleCol = false;
    let delim = ',';
    let headers = [];

    if (rawHeaders.length === 1 && (String(rawHeaders[0]).includes(',') || String(rawHeaders[0]).includes(';'))) {
      isSingleCol = true;
      delim = String(rawHeaders[0]).includes(',') ? ',' : ';';
      headers = String(rawHeaders[0]).split(delim).map(h => h.replace(/^\uFEFF/, '').trim());
    } else {
      headers = rawHeaders.map((h, i) => {
        const val = String(h ?? '').replace(/^\uFEFF/, '').trim();
        return val.length > 0 ? val : `Col ${i + 1}`;
      });
    }

    // Pehle 100 rows preview ke liye
    const previewRows = [];
    const maxPreview = Math.min(validRows.length, headerIdx + 1 + 100);

    for (let i = headerIdx + 1; i < maxPreview; i++) {
      const row = validRows[i];
      let cells = [];
      if (isSingleCol && row.length === 1) {
        cells = String(row[0]).split(delim).map(v => v.trim());
      } else {
        cells = headers.map((_, colIdx) => {
          const val = row[colIdx];
          if (val instanceof Date) {
            return val.toISOString().split('T')[0];
          }
          return val !== undefined && val !== null ? String(val).trim() : '';
        });
      }
      previewRows.push(cells);
    }

    return res.status(200).json({
      success: true,
      fileName: req.file.originalname,
      sheetName,
      totalRows: validRows.length - (headerIdx + 1),
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

    // Resilient parse: find header row and unpack single or multi columns
    const aoa = xlsx.utils.sheet_to_json(sheet, { header: 1, defval: '' });
    let headerIndex = -1;
    for (let i = 0; i < aoa.length; i++) {
      const rowStr = aoa[i].join(',').toLowerCase();
      if (rowStr.includes('userid') || rowStr.includes('empcode') || rowStr.includes('processdate') || rowStr.includes('punch1')) {
        headerIndex = i;
        break;
      }
    }

    let sheetData = [];
    if (headerIndex !== -1) {
      let headers = aoa[headerIndex];
      let isSingleCol = false;
      let delim = ',';
      if (headers.length === 1 && (String(headers[0]).includes(',') || String(headers[0]).includes(';'))) {
        isSingleCol = true;
        delim = String(headers[0]).includes(',') ? ',' : ';';
        headers = String(headers[0]).split(delim).map(h => h.replace(/^\uFEFF/, '').trim());
      } else {
        headers = headers.map(h => String(h).replace(/^\uFEFF/, '').trim());
      }

      for (let i = headerIndex + 1; i < aoa.length; i++) {
        const row = aoa[i];
        if (!row || row.length === 0 || (row.length === 1 && !row[0])) continue;
        let vals = row;
        if (isSingleCol && row.length === 1) {
          vals = String(row[0]).split(delim).map(v => v.trim());
        }
        const obj = {};
        headers.forEach((h, idx) => {
          obj[h] = vals[idx] !== undefined ? vals[idx] : '';
        });
        sheetData.push(obj);
      }
    } else {
      // Fallback
      sheetData = xlsx.utils.sheet_to_json(sheet, { raw: false });
    }

    console.log('📄 Uploaded Sheet Rows Found:', sheetData.length);

    if (!sheetData || sheetData.length === 0) {
      return res.status(400).json({ success: false, message: 'Uploaded file has no recognizable attendance data!' });
    }

    // B. Save Audit Record in ATTENDANCE_IMPORT table
    const [importResult] = await db.query(
      `INSERT INTO ATTENDANCE_IMPORT (company_id, uploaded_by, file_name, total_records)
       VALUES (?, ?, ?, ?)`,
      [1, 1, req.file.originalname, sheetData.length]
    );
    const importId = importResult.insertId;

    let successCount = 0;
    let failedCount = 0;
    const errors = [];
    const terminalLogs = []; // <-- YEH JODO
    let detectedMonth = null;
    let detectedYear = null;

    // Helper functions for parsing
    function parseDate(rawDate) {
      if (!rawDate) return { cleanDate: new Date().toISOString().split('T')[0], month: new Date().getMonth() + 1, year: new Date().getFullYear() };
      if (rawDate instanceof Date && !isNaN(rawDate)) {
        const y = rawDate.getFullYear();
        const m = rawDate.getMonth() + 1;
        const d = String(rawDate.getDate()).padStart(2, '0');
        return { cleanDate: `${y}-${String(m).padStart(2, '0')}-${d}`, month: m, year: y };
      }
      if (typeof rawDate === 'number') {
        const date = new Date(Math.round((rawDate - 25569) * 86400 * 1000));
        const y = date.getFullYear();
        const m = date.getMonth() + 1;
        const d = String(date.getDate()).padStart(2, '0');
        return { cleanDate: `${y}-${String(m).padStart(2, '0')}-${d}`, month: m, year: y };
      }
      const str = String(rawDate).trim();
      if (str.includes('/')) {
        const parts = str.split('/');
        if (parts.length === 3) {
          if (parts[2].length === 4) {
            const y = parseInt(parts[2], 10);
            const m = parseInt(parts[1], 10);
            const d = parts[0].padStart(2, '0');
            return { cleanDate: `${y}-${String(m).padStart(2, '0')}-${d}`, month: m, year: y };
          }
          if (parts[0].length === 4) {
            const y = parseInt(parts[0], 10);
            const m = parseInt(parts[1], 10);
            const d = parts[2].padStart(2, '0');
            return { cleanDate: `${y}-${String(m).padStart(2, '0')}-${d}`, month: m, year: y };
          }
        }
      }
      if (str.includes('-')) {
        const parts = str.split('-');
        if (parts.length === 3 && parts[0].length === 4) {
          return { cleanDate: str.split('T')[0], month: parseInt(parts[1], 10), year: parseInt(parts[0], 10) };
        }
      }
      const now = new Date();
      return { cleanDate: now.toISOString().split('T')[0], month: now.getMonth() + 1, year: now.getFullYear() };
    }

    function parseTime(rawTime) {
      if (!rawTime) return null;
      if (rawTime instanceof Date && !isNaN(rawTime)) {
        const h = String(rawTime.getHours()).padStart(2, '0');
        const m = String(rawTime.getMinutes()).padStart(2, '0');
        const s = String(rawTime.getSeconds()).padStart(2, '0');
        return `${h}:${m}:${s}`;
      }
      const str = String(rawTime).trim();
      if (str === '' || str === '0') return null;
      if (str.includes(' ')) {
        const t = str.split(' ')[1];
        return t.length === 5 ? `${t}:00` : t;
      }
      if (str.includes(':')) {
        const parts = str.split(':');
        const h = parts[0].padStart(2, '0');
        const m = (parts[1] || '00').padStart(2, '0');
        const s = (parts[2] || '00').padStart(2, '0');
        return `${h}:${m}:${s}`;
      }
      return null;
    }

    function getNormalizedValue(row, candidates) {
      for (const k of Object.keys(row)) {
        const cleanKey = k.replace(/^\uFEFF/, '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
        for (const c of candidates) {
          if (cleanKey === c.toLowerCase().replace(/[^a-z0-9]/g, '')) {
            if (row[k] !== undefined && row[k] !== null && String(row[k]).trim() !== '') {
              return row[k];
            }
          }
        }
      }
      return null;
    }

    // C. Process each row
    for (const rawRow of sheetData) {
      const bioCodeRaw = getNormalizedValue(rawRow, ['userid', 'empcode', 'empid', 'id', 'enrollid', 'badgenumber']);
      if (!bioCodeRaw) continue;
      const bioCode = String(bioCodeRaw).trim();

      const userName = getNormalizedValue(rawRow, ['username', 'name', 'fullname', 'employeename']);
      const rawDate = getNormalizedValue(rawRow, ['processdate', 'date', 'workdate']);
      const dateInfo = parseDate(rawDate);
      const cleanDate = dateInfo.cleanDate;

      if (!detectedMonth) {
        detectedMonth = dateInfo.month;
        detectedYear = dateInfo.year;
      }

      const rawIn = getNormalizedValue(rawRow, ['punch1', 'intime', 'checkin', 'in']);
      const rawOut = getNormalizedValue(rawRow, ['punch2', 'outtime', 'checkout', 'out']);
      const inTime = parseTime(rawIn);
      const outTime = parseTime(rawOut);

      const lateIn = parseInt(getNormalizedValue(rawRow, ['latein', 'late']) || '0', 10);
      const workMinutes = parseInt(getNormalizedValue(rawRow, ['worktime', 'workminutes', 'duration']) || '0', 10);
      const overtimeHours = (parseFloat(getNormalizedValue(rawRow, ['overtime', 'ot']) || '0') / 60).toFixed(2);

      // Match employee by biometric_emp_code OR emp_code OR full_name
      const bioCodeNoZero = bioCode.replace(/^0+/, '');
      let empRows = [];

      const [byCode] = await db.query(
        'SELECT employee_id, full_name, biometric_emp_code FROM EMPLOYEE WHERE biometric_emp_code = ? OR emp_code = ? OR biometric_emp_code = ? OR emp_code = ?',
        [bioCode, bioCode, bioCodeNoZero, bioCodeNoZero]
      );
      empRows = byCode;

      if (empRows.length === 0 && userName && String(userName).trim() !== '') {
        const trimmedName = String(userName).trim();
        const [byName] = await db.query(
          'SELECT employee_id, full_name, biometric_emp_code FROM EMPLOYEE WHERE full_name LIKE ? OR full_name LIKE ?',
          [`%${trimmedName}%`, trimmedName]
        );
        if (byName.length > 0) {
          empRows = byName;
          await db.query(
            'UPDATE EMPLOYEE SET biometric_emp_code = ? WHERE employee_id = ? AND (biometric_emp_code IS NULL OR biometric_emp_code = "")',
            [bioCode, byName[0].employee_id]
          );
        }
      }

      if (empRows.length === 0) {
        failedCount++;
        errors.push(`Staff '${userName || bioCode}' (Machine ID: ${bioCode}) not registered in system.`);
        continue;
      }

      const employeeId = empRows[0].employee_id;

      // Status Rule:
      let status = 'Present';
      if (!inTime && workMinutes === 0) {
        status = 'Absent';
      } else if (lateIn > 0) {
        status = 'Late';
      } else if (workMinutes > 0 && workMinutes < 240) {
        status = 'Half-Day';
      } else if (inTime) {
        const timeParts = inTime.split(':');
        const inHour = parseInt(timeParts[0] || '9', 10);
        const inMinute = parseInt(timeParts[1] || '0', 10);
        if (inHour > 9 || (inHour === 9 && inMinute > 30)) {
          status = 'Late';
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
    }

    // Update audit

       try {
      await db.query(
        'UPDATE ATTENDANCE_IMPORT SET success_count = ?, failed_count = ?, error_logs = ? WHERE import_id = ?',
        [successCount, failedCount, JSON.stringify(errors.slice(0, 50)), importId]
      );
    } catch (_) {
      try {
        await db.query(
          'UPDATE ATTENDANCE_IMPORT SET success_count = ?, failed_count = ? WHERE import_id = ?',
          [successCount, failedCount, importId]
        );
      } catch (_) {}
    }

    terminalLogs.push(`[COMPLETE] Synchronization finished: ${successCount} Synced, ${failedCount} Skipped/Unmatched. Total: ${sheetData.length}.`);

    return res.status(200).json({
      success: true,
      message: `Processed ${sheetData.length} records: ${successCount} Success, ${failedCount} Errors.`,
      importedMonth: detectedMonth,
      importedYear: detectedYear,
      summary: { totalRows: sheetData.length, successCount, failedCount, errors },
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

    // Ensure columns exist in tables
    try {
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN paid_days INT DEFAULT 1");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN unpaid_days INT DEFAULT 0");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {}

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
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN is_paid TINYINT(1) DEFAULT 1");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN paid_days INT DEFAULT 1");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN unpaid_days INT DEFAULT 0");
      await db.query("ALTER TABLE LEAVE_REQUEST ADD COLUMN deduction_amount DECIMAL(12,2) DEFAULT 0.00");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_casual INT DEFAULT 12");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_sick INT DEFAULT 8");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN leave_balance_paid INT DEFAULT 15");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_limit INT DEFAULT 10");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leave_per_day_deduction DECIMAL(12,2) DEFAULT 0.00");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN unpaid_leaves_taken INT DEFAULT 0");
      await db.query("ALTER TABLE EMPLOYEE ADD COLUMN total_leave_deduction DECIMAL(12,2) DEFAULT 0.00");
    } catch (_) {}

    const { employee_id, user_id } = req.query;

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

    if (employee_id) {
      query += ` AND l.employee_id = ?`;
      params.push(employee_id);
    } else if (user_id) {
      query += ` AND e.user_id = ?`;
      params.push(user_id);
    }

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
        `SELECT l.leave_type, l.total_days, l.paid_days, l.unpaid_days, l.deduction_amount, e.user_id, e.full_name
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
          1,
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
      const { status, exit_reason } = req.body; // status: 'active', 'suspended', 'terminated'

      if (!['active', 'suspended', 'terminated'].includes(status)) {
        return res.status(400).json({ success: false, message: 'Status must be active, suspended, or terminated.' });
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
      } else if (status === 'suspended') {
        await db.query(
          'UPDATE EMPLOYEE SET status = ?, exit_reason = ? WHERE employee_id = ?',
          [status, exit_reason || 'System Access Suspended/Banned', id]
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
        await db.query('UPDATE USER SET is_active = ? WHERE user_id = ?', [isUserActive, emp.user_id]);
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
      await db.query('DELETE FROM EMPLOYEE WHERE employee_id = ?', [id]);
      return res.status(200).json({ success: true, message: 'Employee record deleted.' });
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
      const [departments] = await db.query(`
        SELECT
          d.department_id,
          d.company_id,
          d.name,
          COUNT(e.employee_id) as member_count
        FROM DEPARTMENT d
        LEFT JOIN EMPLOYEE e ON d.department_id = e.department_id AND e.status = 'active'
        GROUP BY d.department_id, d.company_id, d.name
        ORDER BY d.department_id ASC
      `);

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
      let targetCompanyId = company_id;
      try {
        const [companies] = await db.query('SELECT company_id FROM COMPANY LIMIT 1');
        if (companies.length > 0) {
          targetCompanyId = companies[0].company_id;
        } else {
          const [compResult] = await db.query(
            "INSERT INTO COMPANY (name, code, plan, status) VALUES (?, ?, ?, ?)",
            ['Enterprise Core', 'ENT-01', 'Enterprise', 'active']
          );
          targetCompanyId = compResult.insertId;
        }
      } catch (err) {
        targetCompanyId = targetCompanyId || 1;
      }

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

      // Default permissions based on role
      const isSuperAdmin = emp.role_name === 'Super Admin';
      const isManager = isSuperAdmin || emp.role_name === 'Module Manager';

      const defaultPermissions = {
        'hr_view_directory': true,
        'hr_manage_staff': isManager,
        'hr_manage_departments': isSuperAdmin,
        'hr_view_lifecycle': isSuperAdmin,
        'attendance_view_logs': true,
        'attendance_import_excel': isManager,
        'attendance_override': isSuperAdmin,
        'attendance_biometric_manage': isManager,
        'salary_manage_increment': isSuperAdmin,
        'leaves_apply': true,
        'leaves_approve': isManager,
        'tasks_view': true,
        'tasks_create_assign': isManager,
        'tasks_log_timesheet': true,
        'inventory_view_stock': true,
        'inventory_manage_material': isManager,
        'manufacturing_view_bom': true,
        'manufacturing_work_orders': isManager,
        'finance_view_reports': isSuperAdmin,
        'system_audit_logs': isSuperAdmin
      };

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
      const { permissions, role_id, user_active } = req.body;

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
      const [emp] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (emp.length > 0 && emp[0].user_id) {
        const updates = [];
        const params = [];
        if (role_id) {
          updates.push('role_id = ?');
          params.push(role_id);
        }
        if (user_active !== undefined) {
          updates.push('is_active = ?');
          params.push(user_active ? 1 : 0);
        }
        if (updates.length > 0) {
          params.push(emp[0].user_id);
          await db.query(`UPDATE USER SET ${updates.join(', ')} WHERE user_id = ?`, params);
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
        unpaid_leave_per_day_deduction
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
      const { email, password, role_name } = req.body;

      if (!email || !password) {
        return res.status(400).json({ success: false, message: 'Email and password are required.' });
      }

      // A. Check if email already in use
      const [existingUser] = await db.query('SELECT user_id FROM USER WHERE email = ?', [email.trim()]);
      if (existingUser.length > 0) {
        return res.status(400).json({ success: false, message: 'This email is already in use by another user account.' });
      }

      // B. Check Employee exists
      const [empRows] = await db.query('SELECT employee_id, branch_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (empRows.length === 0) {
        return res.status(404).json({ success: false, message: 'Employee not found.' });
      }

      // C. Find role_id
      let roleId = 3; // Default Employee
      const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role_name || 'Employee']);
      if (roleRows.length > 0) {
        roleId = roleRows[0].role_id;
      }

      // D. Hash password & insert into USER
      const bcrypt = require('bcryptjs');
      const passwordHash = await bcrypt.hash(password.trim(), 10);

      const [userResult] = await db.query(
        `INSERT INTO USER (company_id, role_id, email, password_hash, is_active)
         VALUES (1, ?, ?, ?, 1)`,
        [roleId, email.trim(), passwordHash]
      );
      const newUserId = userResult.insertId;

      // E. Link user_id to EMPLOYEE
      await db.query('UPDATE EMPLOYEE SET user_id = ? WHERE employee_id = ?', [newUserId, id]);

      return res.status(201).json({
        success: true,
        message: 'System login account created and linked successfully!',
        data: { user_id: newUserId, email: email.trim(), role_name: role_name || 'Employee' }
      });
    } catch (error) {
      console.error('Create Employee Login Error:', error);
      return res.status(500).json({ success: false, message: 'Database error', error: error.message });
    }
  };

  // ================= 🕒 ATTENDANCE RECORDS & MANUAL OVERRIDE =================

  // 1. GET ATTENDANCE RECORDS WITH ADVANCED FILTERS (Date, Month, Year, Range, Employee)
  exports.getAttendanceRecords = async (req, res) => {
    try {
      const { employee_id, date, month, year, start_date, end_date } = req.query;

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

  // 1. Get Targeted Notifications (Role and User specific)
  exports.getNotifications = async (req, res) => {
    try {
      await ensureNotificationTable();
      const { user_id, role, can_approve_leaves } = req.query;

      let query = `
        SELECT notification_id, title, message, type, reference_id, target_user_id, target_role, sender_user_id, is_read, created_at
        FROM NOTIFICATION
        WHERE 1=1
      `;
      const params = [];

      const uid = user_id ? parseInt(user_id, 10) : null;
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
      await db.query('UPDATE NOTIFICATION SET is_read = 1 WHERE notification_id = ?', [id]);
      return res.status(200).json({ success: true, message: 'Marked as read' });
    } catch (error) {
      return res.status(500).json({ success: false, error: error.message });
    }
  };

  // 3. Mark All Notifications as Read (Targeted to the requesting user/role)
  exports.markAllNotificationsAsRead = async (req, res) => {
    try {
      const { user_id, role, can_approve_leaves } = req.query;
      const uid = user_id ? parseInt(user_id, 10) : null;
      const isAdminOrApprover = role === 'Super Admin' || can_approve_leaves === 'true' || can_approve_leaves === true;

      let query = 'UPDATE NOTIFICATION SET is_read = 1 WHERE 1=1';
      const params = [];

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


  // 2. UPDATE EMPLOYEE ROLE (Promote to Module Manager / Admin / Employee)
  exports.updateEmployeeRole = async (req, res) => {
    try {
      const { id } = req.params;
      const { role_name } = req.body;

      if (!role_name) {
        return res.status(400).json({ success: false, message: 'Role name is required.' });
      }

      try {
        await db.query("ALTER TABLE EMPLOYEE ADD COLUMN role VARCHAR(50) DEFAULT 'Employee'");
      } catch (_) {}

      await db.query('UPDATE EMPLOYEE SET role = ? WHERE employee_id = ?', [role_name, id]);

      const [empRows] = await db.query('SELECT user_id FROM EMPLOYEE WHERE employee_id = ?', [id]);
      if (empRows.length > 0 && empRows[0].user_id) {
        const [roleRows] = await db.query('SELECT role_id FROM ROLE WHERE name = ? LIMIT 1', [role_name]);
        if (roleRows.length > 0) {
          await db.query('UPDATE USER SET role_id = ? WHERE user_id = ?', [roleRows[0].role_id, empRows[0].user_id]);
        }
      }

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

    // Send notification to employee
    try {
      const [empRows] = await db.query('SELECT user_id, full_name FROM EMPLOYEE WHERE employee_id = ?', [employee_id]);
      if (empRows.length > 0 && empRows[0].user_id) {
        await ensureNotificationTable();
        await db.query(`
          INSERT INTO NOTIFICATION (company_id, title, message, type, reference_id, target_user_id)
          VALUES (?, ?, ?, 'SALARY_INCREMENT', ?, ?)
        `, [
          1,
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

    const [rows] = await db.query(`
      SELECT i.*, e.full_name, e.emp_code, e.department_id, d.name as department_name, u.email as approved_by_email
      FROM EMPLOYEE_INCREMENT i
      JOIN EMPLOYEE e ON i.employee_id = e.employee_id
      LEFT JOIN DEPARTMENT d ON e.department_id = d.department_id
      LEFT JOIN USER u ON i.approved_by = u.user_id
      ORDER BY i.increment_id DESC
    `);

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
    let rows = [];
    try {
      const [r] = await db.query(`
        SELECT import_id, file_name, total_records, success_count, failed_count, error_logs, created_at
        FROM ATTENDANCE_IMPORT
        ORDER BY import_id DESC
        LIMIT 50
      `);
      rows = r;
    } catch (_) {
      const [r] = await db.query(`
        SELECT import_id, file_name, total_records, success_count, failed_count, created_at
        FROM ATTENDANCE_IMPORT
        ORDER BY import_id DESC
        LIMIT 50
      `);
      rows = r;
    }
    return res.status(200).json({ success: true, data: rows });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};