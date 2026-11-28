'use strict';

const db = require('../../../config/db');
const { num } = require('../accounting/finance.utils');
const finance = require('../accounting/finance.controller');
const { ensureDefaultComponents } = require('../salary_components/components.controller');

const { companyIdOf, fail, writeAudit } = finance._shared;

function round2(value) {
  return Math.round((num(value) + Number.EPSILON) * 100) / 100;
}

async function ensureDefaultTemplates(companyId) {
  await ensureDefaultComponents(companyId);
  await db.query(`
    CREATE TABLE IF NOT EXISTS salary_templates (
      template_id INT AUTO_INCREMENT PRIMARY KEY,
      company_id INT NOT NULL,
      template_name VARCHAR(100) NOT NULL,
      description VARCHAR(255) NULL,
      salary_type ENUM('MONTHLY', 'DAILY', 'HOURLY') NOT NULL DEFAULT 'MONTHLY',
      basic_percent DECIMAL(5,2) NOT NULL DEFAULT 50.00,
      hra_percent DECIMAL(5,2) NOT NULL DEFAULT 40.00,
      conveyance_fixed DECIMAL(15,2) NOT NULL DEFAULT 1600.00,
      custom_allowances_json TEXT NULL,
      pf_applicable TINYINT(1) NOT NULL DEFAULT 1,
      esi_applicable TINYINT(1) NOT NULL DEFAULT 1,
      pt_applicable TINYINT(1) NOT NULL DEFAULT 1,
      ot_eligible TINYINT(1) NOT NULL DEFAULT 1,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      created_by INT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uk_st_company_name (company_id, template_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  try {
    await db.query('ALTER TABLE salary_templates ADD COLUMN custom_allowances_json TEXT NULL AFTER conveyance_fixed');
  } catch (_) {}
  try {
    await db.query('ALTER TABLE salary_templates ADD COLUMN ot_eligible TINYINT(1) NOT NULL DEFAULT 1 AFTER pt_applicable');
  } catch (_) {}
  await db.query(`
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

  const [cnt] = await db.query(
    'SELECT COUNT(*) AS cnt FROM salary_templates WHERE company_id = ?',
    [companyId]
  );
  if (Number(cnt[0]?.cnt || 0) > 0) return;

  const defaults = [
    ['Standard Staff', 'Regular full-time office & engineering staff', 'MONTHLY', 50, 40, 1600, 1, 1, 1],
    ['Senior / Manager', 'Senior executives & department leads', 'MONTHLY', 50, 50, 2400, 1, 0, 1],
    ['Intern / Trainee', 'Trainees & probation staff without PF/ESI', 'MONTHLY', 100, 0, 0, 0, 0, 0]
  ];
  for (const [name, desc, sType, basicPct, hraPct, conv, pf, esi, pt] of defaults) {
    await db.query(
      `INSERT IGNORE INTO salary_templates
        (company_id, template_name, description, salary_type, basic_percent, hra_percent, conveyance_fixed, pf_applicable, esi_applicable, pt_applicable)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [companyId, name, desc, sType, basicPct, hraPct, conv, pf, esi, pt]
    );
  }
}

exports.getSalaryTemplates = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureDefaultTemplates(companyId);
    const [rows] = await db.query(
      `SELECT t.*, COUNT(s.structure_id) AS employees_count
       FROM salary_templates t
       LEFT JOIN employee_salary_structures s
         ON s.template_id = t.template_id AND s.company_id = t.company_id AND s.is_current = 1
       WHERE t.company_id = ? AND t.is_active = 1
       GROUP BY t.template_id
       ORDER BY t.template_id ASC`,
      [companyId]
    );
    const [tplItems] = await db.query(
      `SELECT sti.*, sc.code, sc.name, sc.component_type, sc.default_value
       FROM salary_template_items sti
       JOIN salary_components sc ON sc.component_id = sti.component_id
       WHERE sti.company_id = ?
       ORDER BY sc.component_type, sc.display_order, sc.component_id`,
      [companyId]
    ).catch(() => [[]]);
    const byTpl = {};
    for (const it of tplItems) {
      if (!byTpl[it.template_id]) byTpl[it.template_id] = [];
      byTpl[it.template_id].push(it);
    }

    const [catLinks] = await db.query(
      'SELECT category_id, default_template_id FROM hr_categories WHERE company_id = ? AND default_template_id IS NOT NULL',
      [companyId]
    ).catch(() => [[]]);
    const catsByTpl = {};
    for (const c of catLinks) {
      if (!catsByTpl[c.default_template_id]) catsByTpl[c.default_template_id] = [];
      catsByTpl[c.default_template_id].push(c.category_id);
    }

    const data = rows.map((r) => ({
      ...r,
      items: byTpl[r.template_id] || [],
      category_ids: catsByTpl[r.template_id] || []
    }));
    return res.status(200).json({ success: true, data });
  } catch (err) {
    return fail(res, err, 'getSalaryTemplates');
  }
};

exports.saveSalaryTemplate = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    await ensureDefaultTemplates(companyId);
    const {
      template_id,
      template_name,
      description = '',
      salary_type = 'MONTHLY',
      basic_percent = 50,
      hra_percent = 40,
      conveyance_fixed = 1600,
      custom_allowances = [],
      items = [],
      category_ids,
      pf_applicable = true,
      esi_applicable = true,
      pt_applicable = true,
      ot_eligible = true
    } = req.body || {};

    const cleanName = String(template_name || '').trim();
    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Template name is required.' });
    }
    const customJson = JSON.stringify(Array.isArray(custom_allowances) ? custom_allowances : []);

    await conn.beginTransaction();
    let targetTplId = template_id ? parseInt(template_id, 10) : null;

    if (targetTplId) {
      await conn.query(
        `UPDATE salary_templates
         SET template_name = ?, description = ?, salary_type = ?, basic_percent = ?, hra_percent = ?,
             conveyance_fixed = ?, custom_allowances_json = ?, pf_applicable = ?, esi_applicable = ?,
             pt_applicable = ?, ot_eligible = ?
         WHERE template_id = ? AND company_id = ?`,
        [
          cleanName,
          String(description || '').slice(0, 255),
          salary_type,
          num(basic_percent),
          num(hra_percent),
          round2(conveyance_fixed),
          customJson,
          pf_applicable ? 1 : 0,
          esi_applicable ? 1 : 0,
          pt_applicable ? 1 : 0,
          ot_eligible ? 1 : 0,
          targetTplId,
          companyId
        ]
      );
    } else {
      const [ins] = await conn.query(
        `INSERT INTO salary_templates
          (company_id, template_name, description, salary_type, basic_percent, hra_percent, conveyance_fixed,
           custom_allowances_json, pf_applicable, esi_applicable, pt_applicable, ot_eligible, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          companyId,
          cleanName,
          String(description || '').slice(0, 255),
          salary_type,
          num(basic_percent),
          num(hra_percent),
          round2(conveyance_fixed),
          customJson,
          pf_applicable ? 1 : 0,
          esi_applicable ? 1 : 0,
          pt_applicable ? 1 : 0,
          ot_eligible ? 1 : 0,
          req.user.userId
        ]
      );
      targetTplId = ins.insertId;
    }

    if (Array.isArray(items)) {
      await conn.query('DELETE FROM salary_template_items WHERE template_id = ? AND company_id = ?', [targetTplId, companyId]);
      for (const it of items) {
        if (!it || !it.component_id) continue;
        await conn.query(
          `INSERT INTO salary_template_items (company_id, template_id, component_id, calc_mode, value_override)
           VALUES (?, ?, ?, ?, ?)`,
          [companyId, targetTplId, it.component_id, it.calc_mode || 'FIXED', round2(it.value_override)]
        );
      }
    }

    if (Array.isArray(category_ids)) {
      await conn.query(
        'UPDATE hr_categories SET default_template_id = NULL WHERE company_id = ? AND default_template_id = ?',
        [companyId, targetTplId]
      );
      const cleanCatIds = category_ids.map((id) => parseInt(id, 10)).filter((id) => id > 0);
      if (cleanCatIds.length > 0) {
        const ph = cleanCatIds.map(() => '?').join(',');
        await conn.query(
          `UPDATE hr_categories SET default_template_id = ? WHERE company_id = ? AND category_id IN (${ph})`,
          [targetTplId, companyId, ...cleanCatIds]
        );
      }
    }

    await conn.commit();
    return res.status(template_id ? 200 : 201).json({
      success: true,
      message: template_id ? 'Salary template updated!' : 'Salary template created!',
      template_id: targetTplId
    });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'saveSalaryTemplate');
  } finally {
    conn.release();
  }
};

exports.deleteSalaryTemplate = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const [result] = await db.query(
      'UPDATE salary_templates SET is_active = 0 WHERE template_id = ? AND company_id = ?',
      [id, companyId]
    );
    if (!result.affectedRows) {
      return res.status(404).json({ success: false, message: 'Salary template not found.' });
    }
    return res.status(200).json({ success: true, message: 'Salary template removed!' });
  } catch (err) {
    return fail(res, err, 'deleteSalaryTemplate');
  }
};

exports.getSalaryStructures = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureDefaultTemplates(companyId);
    try {
      const [employees] = await db.query(
        `SELECT e.employee_id, e.emp_code, e.full_name, e.designation, e.status,
                DATE_FORMAT(e.join_date, '%Y-%m-%d') AS join_date,
                e.salary_base, e.bank_name, e.bank_account_no, e.bank_ifsc, e.pan_no, e.pf_uan, e.esi_no,
                e.hr_category_id, hc.category_name AS hr_category_name, hc.category_code AS hr_category_code,
                d.name AS department_name,
                s.structure_id, s.template_id, t.template_name, s.salary_type, s.base_pay, s.gross_monthly,
                DATE_FORMAT(s.effective_from, '%Y-%m-%d') AS effective_from,
                s.pf_applicable, s.esi_applicable, s.pt_applicable, s.tds_monthly
         FROM EMPLOYEE e
         LEFT JOIN DEPARTMENT d ON d.department_id = e.department_id
         LEFT JOIN hr_categories hc ON hc.category_id = e.hr_category_id AND hc.company_id = e.company_id
         LEFT JOIN employee_salary_structures s
           ON s.employee_id = e.employee_id AND s.company_id = e.company_id AND s.is_current = 1
         LEFT JOIN salary_templates t
           ON t.template_id = s.template_id
         WHERE e.company_id = ? AND LOWER(COALESCE(e.status, 'active')) = 'active'
         ORDER BY e.full_name ASC`,
        [companyId]
      );
      return res.status(200).json({ success: true, data: employees });
    } catch (queryErr) {
      if (queryErr.code !== 'ER_BAD_FIELD_ERROR') throw queryErr;
      const [employees] = await db.query(
        `SELECT e.employee_id, e.emp_code, e.full_name, e.designation, e.status,
                DATE_FORMAT(e.join_date, '%Y-%m-%d') AS join_date,
                e.salary_base, NULL AS bank_name, NULL AS bank_account_no, NULL AS bank_ifsc, NULL AS pan_no, NULL AS pf_uan, NULL AS esi_no,
                NULL AS hr_category_id, NULL AS hr_category_name, NULL AS hr_category_code,
                d.name AS department_name,
                s.structure_id, s.template_id, t.template_name, s.salary_type, s.base_pay, s.gross_monthly,
                DATE_FORMAT(s.effective_from, '%Y-%m-%d') AS effective_from,
                s.pf_applicable, s.esi_applicable, s.pt_applicable, s.tds_monthly
         FROM EMPLOYEE e
         LEFT JOIN DEPARTMENT d ON d.department_id = e.department_id
         LEFT JOIN employee_salary_structures s
           ON s.employee_id = e.employee_id AND s.company_id = e.company_id AND s.is_current = 1
         LEFT JOIN salary_templates t
           ON t.template_id = s.template_id
         WHERE e.company_id = ? AND LOWER(COALESCE(e.status, 'active')) = 'active'
         ORDER BY e.full_name ASC`,
        [companyId]
      );
      return res.status(200).json({ success: true, data: employees });
    }
  } catch (err) {
    console.error('getSalaryStructures error:', err);
    return res.status(500).json({ success: false, message: 'Failed to load salary structures.', error: err.message });
  }
};

exports.getEmployeeSalaryHistory = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const empId = parseInt(req.params.employeeId, 10);
    const [rows] = await db.query(
      `SELECT s.structure_id, s.template_id, t.template_name, s.salary_type,
              s.base_pay, s.gross_monthly,
              DATE_FORMAT(s.effective_from, '%Y-%m-%d') AS effective_from,
              DATE_FORMAT(s.effective_to, '%Y-%m-%d') AS effective_to,
              s.is_current, s.pf_applicable, s.esi_applicable, s.pt_applicable, s.notes,
              DATE_FORMAT(s.created_at, '%Y-%m-%d %H:%i') AS changed_at,
              COALESCE(ce.full_name, cu.email, 'System') AS changed_by_name
       FROM employee_salary_structures s
       LEFT JOIN salary_templates t ON t.template_id = s.template_id
       LEFT JOIN USER cu ON cu.user_id = s.created_by
       LEFT JOIN EMPLOYEE ce ON ce.user_id = s.created_by AND ce.company_id = s.company_id
       WHERE s.company_id = ? AND s.employee_id = ?
       ORDER BY s.effective_from DESC, s.structure_id DESC`,
      [companyId, empId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getEmployeeSalaryHistory');
  }
};

async function applySingleEmployeeTemplate(conn, companyId, tpl, empId, grossOverride, effDate, userId) {
  const [empRows] = await conn.query(
    'SELECT employee_id, salary_base FROM EMPLOYEE WHERE employee_id = ? AND company_id = ? LIMIT 1',
    [empId, companyId]
  );
  if (!empRows.length) return false;

  const gross = round2(num(grossOverride) > 0 ? grossOverride : (empRows[0].salary_base || 20000));
  const basic = round2((gross * num(tpl.basic_percent)) / 100);
  const hra = round2((basic * num(tpl.hra_percent)) / 100);
  const conv = round2(Math.min(num(tpl.conveyance_fixed), Math.max(0, gross - basic - hra)));

  let customList = [];
  try {
    customList = Array.isArray(tpl.custom_allowances_json)
      ? tpl.custom_allowances_json
      : JSON.parse(tpl.custom_allowances_json || '[]');
  } catch (_) {
    customList = [];
  }
  let customTotal = 0;
  for (const c of customList) {
    customTotal = round2(customTotal + num(c.amount));
  }
  const special = round2(Math.max(0, gross - basic - hra - conv - customTotal));

  await conn.query(
    `UPDATE employee_salary_structures
     SET is_current = 0, effective_to = DATE_SUB(?, INTERVAL 1 DAY)
     WHERE company_id = ? AND employee_id = ? AND is_current = 1`,
    [effDate, companyId, empId]
  );

  const [stRes] = await conn.query(
    `INSERT INTO employee_salary_structures
      (company_id, employee_id, template_id, salary_type, base_pay, gross_monthly, effective_from, is_current,
       pf_applicable, esi_applicable, pt_applicable, notes, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)`,
    [
      companyId,
      empId,
      tpl.template_id,
      tpl.salary_type,
      basic,
      gross,
      effDate,
      tpl.pf_applicable,
      tpl.esi_applicable,
      tpl.pt_applicable,
      `Applied template: ${tpl.template_name}`,
      userId
    ]
  );

  const [compRows] = await conn.query(
    'SELECT component_id, code, component_type, calc_mode, default_value FROM salary_components WHERE company_id = ?',
    [companyId]
  );
  const compMap = Object.fromEntries(compRows.map((c) => [c.code, c.component_id]));

  const [tplItemRows] = await conn.query(
    `SELECT sti.component_id, sti.calc_mode, sti.value_override, sc.code, sc.component_type, sc.default_value
     FROM salary_template_items sti
     JOIN salary_components sc ON sc.component_id = sti.component_id
     WHERE sti.template_id = ? AND sti.company_id = ?`,
    [tpl.template_id, companyId]
  ).catch(() => [[]]);

  const coreCodes = new Set(['BASIC', 'HRA', 'CONV', 'SPECIAL']);
  let extraEarnTotal = 0;
  const extraItems = [];
  for (const ti of tplItemRows) {
    const code = String(ti.code || '').toUpperCase();
    if (coreCodes.has(code)) continue;
    const mode = ti.calc_mode || 'FIXED';
    const rawVal = num(ti.value_override || ti.default_value);
    let computed = mode === 'PERCENT_OF_BASIC' ? round2((basic * rawVal) / 100) : round2(rawVal);
    if (code === 'PF_EE' && tpl.pf_applicable) computed = round2(Math.min(basic, 15000) * 0.12);
    if (code === 'ESI_EE' && tpl.esi_applicable && gross <= 21000) computed = round2(gross * 0.0075);
    if (code === 'PT' && tpl.pt_applicable) computed = gross > 10000 ? 200 : (gross > 7500 ? 175 : 0);
    if (ti.component_type === 'EARNING' && computed > 0) extraEarnTotal = round2(extraEarnTotal + computed);
    if (computed > 0) extraItems.push([ti.component_id, mode, rawVal, computed]);
  }

  const finalSpecial = round2(Math.max(0, special - extraEarnTotal));
  const items = [
    [compMap.BASIC, 'FIXED', basic, basic],
    [compMap.HRA, 'PERCENT_OF_BASIC', num(tpl.hra_percent), hra],
    [compMap.CONV, 'FIXED', conv, conv],
    [compMap.SPECIAL, 'FIXED', round2(finalSpecial + customTotal), round2(finalSpecial + customTotal)],
    ...extraItems
  ];
  for (const [cid, mode, val, comp] of items) {
    if (!cid || comp <= 0) continue;
    await conn.query(
      `INSERT INTO employee_salary_structure_items
        (company_id, structure_id, component_id, calc_mode, amount_or_percent, computed_amount, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [companyId, stRes.insertId, cid, mode, val, comp, userId]
    );
  }

  await conn.query(
    'UPDATE EMPLOYEE SET salary_base = ? WHERE employee_id = ? AND company_id = ?',
    [gross, empId, companyId]
  );
  return stRes.insertId;
}

exports.applyTemplateToEmployee = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    await ensureDefaultTemplates(companyId);
    const { employee_id, template_id, gross_monthly, effective_from } = req.body || {};
    if (!employee_id || !template_id) {
      return res.status(400).json({ success: false, message: 'Employee and Template are required.' });
    }
    const [tplRows] = await conn.query(
      'SELECT * FROM salary_templates WHERE template_id = ? AND company_id = ? AND is_active = 1 LIMIT 1',
      [template_id, companyId]
    );
    if (!tplRows.length) {
      return res.status(404).json({ success: false, message: 'Salary template not found.' });
    }
    const effDate = effective_from || new Date().toISOString().slice(0, 10);
    await conn.beginTransaction();
    const structId = await applySingleEmployeeTemplate(conn, companyId, tplRows[0], employee_id, gross_monthly, effDate, req.user.userId);
    if (!structId) {
      await conn.rollback();
      return res.status(404).json({ success: false, message: 'Employee not found.' });
    }
    await writeAudit(conn, companyId, {
      entity: 'SALARY_TEMPLATE_APPLY',
      entityId: structId,
      action: 'UPDATE',
      summary: `Applied "${tplRows[0].template_name}" to employee #${employee_id}`,
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(200).json({ success: true, message: `Template "${tplRows[0].template_name}" applied!` });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'applyTemplateToEmployee');
  } finally {
    conn.release();
  }
};

exports.bulkApplyTemplate = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    await ensureDefaultTemplates(companyId);
    const { template_id, employee_ids = [], category_id, department_id, gross_monthly, effective_from } = req.body || {};
    if (!template_id) {
      return res.status(400).json({ success: false, message: 'Template is required.' });
    }
    const [tplRows] = await conn.query(
      'SELECT * FROM salary_templates WHERE template_id = ? AND company_id = ? AND is_active = 1 LIMIT 1',
      [template_id, companyId]
    );
    if (!tplRows.length) {
      return res.status(404).json({ success: false, message: 'Salary template not found.' });
    }

    let targetIds = Array.isArray(employee_ids) ? employee_ids.map((id) => parseInt(id, 10)).filter((id) => id > 0) : [];
    if (category_id) {
      const [catEmps] = await conn.query(
        `SELECT employee_id FROM EMPLOYEE WHERE company_id = ? AND hr_category_id = ? AND LOWER(COALESCE(status, 'active')) = 'active'`,
        [companyId, category_id]
      );
      targetIds = catEmps.map((e) => e.employee_id);
    } else if (department_id) {
      const [deptEmps] = await conn.query(
        `SELECT employee_id FROM EMPLOYEE WHERE company_id = ? AND department_id = ? AND LOWER(COALESCE(status, 'active')) = 'active'`,
        [companyId, department_id]
      );
      targetIds = deptEmps.map((e) => e.employee_id);
    }
    if (!targetIds.length) {
      return res.status(400).json({ success: false, message: 'Select at least one employee or an HR category with active staff.' });
    }

    const effDate = effective_from || new Date().toISOString().slice(0, 10);
    await conn.beginTransaction();
    let count = 0;
    for (const empId of targetIds) {
      const ok = await applySingleEmployeeTemplate(conn, companyId, tplRows[0], empId, gross_monthly, effDate, req.user.userId);
      if (ok) count += 1;
    }
    await writeAudit(conn, companyId, {
      entity: 'SALARY_TEMPLATE_BULK',
      entityId: template_id,
      action: 'UPDATE',
      summary: `Bulk applied "${tplRows[0].template_name}" to ${count} employees`,
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(200).json({ success: true, message: `Template applied to ${count} employees!` });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'bulkApplyTemplate');
  } finally {
    conn.release();
  }
};
