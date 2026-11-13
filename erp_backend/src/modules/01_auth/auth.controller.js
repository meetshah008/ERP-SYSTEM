const db = require('../../config/db');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

// 1. REGISTER COMPANY (First-Time Setup Wizard)
exports.registerCompany = async (req, res) => {
  const connection = await db.getConnection();
  try {
    const {
      company_name,
      company_code,
      tax_id,
      currency,
      financial_year_start,
      admin_name,
      admin_email,
      admin_password,
      first_branch_name
    } = req.body;

    // Validation
    if (!company_name || !company_code || !admin_email || !admin_password) {
      return res.status(400).json({ success: false, message: 'Please fill all required fields.' });
    }

    await connection.beginTransaction();

    // A. Check if company or email already exists
    const [existingUser] = await connection.query('SELECT user_id FROM USER WHERE email = ?', [admin_email]);
    if (existingUser.length > 0) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: 'Email is already registered.' });
    }

    // B. Insert Company
    const [compResult] = await connection.query(
      `INSERT INTO COMPANY (company_code, name, tax_id, currency, financial_year_start)
       VALUES (?, ?, ?, ?, ?)`,
      [company_code, company_name, tax_id || null, currency || 'INR', financial_year_start || '2026-04-01']
    );
    const companyId = compResult.insertId;

    // C. Create Default Roles for Company (3-Tier)
    const [superAdminRole] = await connection.query(
      'INSERT INTO ROLE (company_id, name) VALUES (?, ?)',
      [companyId, 'Super Admin']
    );
    await connection.query('INSERT INTO ROLE (company_id, name) VALUES (?, ?)', [companyId, 'Module Manager']);
    await connection.query('INSERT INTO ROLE (company_id, name) VALUES (?, ?)', [companyId, 'Employee']);

    // D. Hash Admin Password & Create Super Admin User
    const hashedPassword = await bcrypt.hash(admin_password, 10);
    const [userResult] = await connection.query(
      `INSERT INTO USER (company_id, role_id, email, password_hash, is_active)
       VALUES (?, ?, ?, ?, ?)`,
      [companyId, superAdminRole.insertId, admin_email, hashedPassword, true]
    );

    // E. Create First Branch
    await connection.query(
      'INSERT INTO BRANCH (company_id, name, address) VALUES (?, ?, ?)',
      [companyId, first_branch_name || 'Main Headquarter', 'Default Location']
    );

    // Commit Transaction
    await connection.commit();

    // Generate JWT Token
    const token = jwt.sign(
      { userId: userResult.insertId, companyId, role: 'Super Admin' },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );

    return res.status(201).json({
      success: true,
      message: 'Company workspace successfully initialized!',
      data: {
        token,
        company: { id: companyId, name: company_name, code: company_code },
        user: { id: userResult.insertId, email: admin_email, role: 'Super Admin' }
      }
    });

  } catch (error) {
    await connection.rollback();
    console.error('Registration Error:', error);
    return res.status(500).json({ success: false, message: 'Internal Server Error', error: error.message });
  } finally {
    connection.release();
  }
};

// 2. USER LOGIN
exports.login = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email and password are required.' });
    }

    // Query user and their role
    const [rows] = await db.query(
      `SELECT u.user_id, u.company_id, u.email, u.password_hash, u.is_active, r.name as role_name, c.name as company_name
       FROM USER u
       JOIN ROLE r ON u.role_id = r.role_id
       JOIN COMPANY c ON u.company_id = c.company_id
       WHERE u.email = ?`,
      [email]
    );

    if (rows.length === 0) {
      return res.status(401).json({ success: false, message: 'Invalid email or password.' });
    }

    const user = rows[0];

    if (!user.is_active) {
      return res.status(403).json({ success: false, message: 'This account has been deactivated.' });
    }

    // Verify Password
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid email or password.' });
    }

    // Update last login
    await db.query('UPDATE USER SET last_login = NOW() WHERE user_id = ?', [user.user_id]);

    // Issue Token
    const token = jwt.sign(
      { userId: user.user_id, companyId: user.company_id, role: user.role_name },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );
        // ================= FETCH USER PERMISSIONS =================
        let permissions = {};
        if (user.role_name === 'Super Admin') {
          // Super Admin ke paas har chiz ka full access hota hai
          permissions = {
            hr_view_directory: true,
            hr_manage_staff: true,
            hr_manage_departments: true,
            attendance_view_logs: true,
            attendance_import_excel: true,
            attendance_override: true,
            leaves_apply: true,
            leaves_approve: true,
            tasks_view: true,
            tasks_create_assign: true,
            tasks_log_timesheet: true,
            inventory_view_stock: true,
            inventory_manage_material: true,
            manufacturing_view_bom: true,
            manufacturing_work_orders: true,
            finance_view_reports: true,
            system_audit_logs: true
          };
        } else {
          // Non-admin ke default permissions
          const isManager = user.role_name === 'Module Manager';
          const defaultPermissions = {
            hr_view_directory: true,
            hr_manage_staff: isManager,
            hr_manage_departments: false,
            attendance_view_logs: true,
            attendance_import_excel: isManager,
            attendance_override: false,
            leaves_apply: true,
            leaves_approve: isManager,
            tasks_view: true,
            tasks_create_assign: isManager,
            tasks_log_timesheet: true,
            inventory_view_stock: true,
            inventory_manage_material: isManager,
            manufacturing_view_bom: true,
            manufacturing_work_orders: isManager,
            finance_view_reports: false,
            system_audit_logs: false
          };

          try {
            // Dekho ki kya is user ka koi employee record linked hai
            const [empRows] = await db.query(
              'SELECT employee_id FROM EMPLOYEE WHERE user_id = ?',
              [user.user_id]
            );

            if (empRows.length > 0) {
              const empId = empRows[0].employee_id;
              // EMPLOYEE_PERMISSION table se saved toggles uthao
              const [permRows] = await db.query(
                'SELECT permission_key, is_granted FROM EMPLOYEE_PERMISSION WHERE employee_id = ?',
                [empId]
              );

              const custom = {};
              for (const p of permRows) {
                custom[p.permission_key] = Boolean(p.is_granted);
              }
              permissions = { ...defaultPermissions, ...custom };
            } else {
              permissions = defaultPermissions;
            }
          } catch (permErr) {
            console.warn('Warning fetching employee permissions:', permErr.message);
            permissions = defaultPermissions;
          }
        }

    return res.status(200).json({
      success: true,
      message: 'Login successful!',
      data: {
        token,
        user: {
          id: user.user_id,
          email: user.email,
          role: user.role_name,
          companyId: user.company_id,
          companyName: user.company_name
        },
        permissions
      }
    });

  } catch (error) {
    console.error('Login Error:', error);
    return res.status(500).json({ success: false, message: 'Internal Server Error', error: error.message });
  }
};
