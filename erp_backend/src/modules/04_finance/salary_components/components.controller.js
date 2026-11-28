'use strict';

const db = require('../../../config/db');
const { num } = require('../accounting/finance.utils');
const finance = require('../accounting/finance.controller');

const { companyIdOf, fail, writeAudit } = finance._shared;

function round2(value) {
  return Math.round((num(value) + Number.EPSILON) * 100) / 100;
}

async function ensureDefaultComponents(companyId) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS salary_components (
      component_id INT AUTO_INCREMENT PRIMARY KEY,
      company_id INT NOT NULL,
      code VARCHAR(30) NOT NULL,
      name VARCHAR(100) NOT NULL,
      component_type ENUM('EARNING', 'DEDUCTION', 'EMPLOYER_CONTRIB') NOT NULL,
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  const [cnt] = await db.query(
    'SELECT COUNT(*) AS cnt FROM salary_components WHERE company_id = ?',
    [companyId]
  );
  if (Number(cnt[0]?.cnt || 0) > 0) return;

  const defaults = [
    ['BASIC', 'Basic Salary', 'EARNING', 'FIXED', 0, 1, 0, 1],
    ['HRA', 'House Rent Allowance (HRA)', 'EARNING', 'PERCENT_OF_BASIC', 40, 1, 0, 2],
    ['CONV', 'Conveyance Allowance', 'EARNING', 'FIXED', 1600, 0, 0, 3],
    ['SPECIAL', 'Special Allowance', 'EARNING', 'FIXED', 2000, 1, 0, 4],
    ['PF_EE', 'Provident Fund (Employee)', 'DEDUCTION', 'PERCENT_OF_BASIC', 12, 0, 1, 11],
    ['ESI_EE', 'ESI (Employee)', 'DEDUCTION', 'FIXED', 0, 0, 1, 12],
    ['PT', 'Professional Tax', 'DEDUCTION', 'FIXED', 200, 0, 1, 13],
    ['TDS', 'TDS (Income Tax)', 'DEDUCTION', 'FIXED', 0, 0, 1, 14]
  ];
  for (const [code, name, type, mode, val, tax, stat, order] of defaults) {
    await db.query(
      `INSERT IGNORE INTO salary_components
        (company_id, code, name, component_type, calc_mode, default_value, is_taxable, is_statutory, display_order)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [companyId, code, name, type, mode, val, tax, stat, order]
    );
  }
}

exports.ensureDefaultComponents = ensureDefaultComponents;

exports.getComponents = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureDefaultComponents(companyId);
    const [rows] = await db.query(
      'SELECT * FROM salary_components WHERE company_id = ? ORDER BY component_type, display_order, component_id',
      [companyId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getComponents');
  }
};

exports.saveComponent = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureDefaultComponents(companyId);
    const {
      component_id,
      code,
      name,
      component_type,
      calc_mode,
      default_value,
      is_taxable,
      is_active
    } = req.body || {};

    const cleanName = String(name || '').trim();
    const cleanCode = String(code || '').trim().toUpperCase();
    const cleanVal = num(default_value);

    if (!cleanName || !cleanCode || !['EARNING', 'DEDUCTION', 'EMPLOYER_CONTRIB'].includes(component_type)) {
      return res.status(400).json({
        success: false,
        message: 'Component Name, Code, and a valid Type are required.'
      });
    }
    if (cleanVal < 0) {
      return res.status(400).json({
        success: false,
        message: 'Amount or percentage cannot be negative.'
      });
    }

    if (component_id) {
      await db.query(
        `UPDATE salary_components
         SET name = ?, component_type = ?, calc_mode = ?, default_value = ?, is_taxable = ?, is_active = ?
         WHERE component_id = ? AND company_id = ?`,
        [
          cleanName,
          component_type,
          calc_mode || 'FIXED',
          round2(cleanVal),
          is_taxable ? 1 : 0,
          is_active === false ? 0 : 1,
          component_id,
          companyId
        ]
      );
      await writeAudit(null, companyId, {
        entity: 'SALARY_COMPONENT',
        entityId: component_id,
        action: 'UPDATE',
        summary: `Updated salary component ${cleanCode} (${cleanName})`,
        userId: req.user.userId
      });
      return res.status(200).json({ success: true, message: 'Component updated!' });
    }

    const [dup] = await db.query(
      'SELECT component_id FROM salary_components WHERE company_id = ? AND code = ? LIMIT 1',
      [companyId, cleanCode]
    );
    if (dup.length) {
      return res.status(409).json({
        success: false,
        message: `Component Code "${cleanCode}" already exists. Please use a unique code.`
      });
    }

    const [result] = await db.query(
      `INSERT INTO salary_components
        (company_id, code, name, component_type, calc_mode, default_value, is_taxable, is_active, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        companyId,
        cleanCode,
        cleanName,
        component_type,
        calc_mode || 'FIXED',
        round2(cleanVal),
        is_taxable ? 1 : 0,
        is_active === false ? 0 : 1,
        req.user.userId
      ]
    );
    await writeAudit(null, companyId, {
      entity: 'SALARY_COMPONENT',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Created salary component ${cleanCode} (${cleanName})`,
      userId: req.user.userId
    });
    return res.status(201).json({
      success: true,
      message: 'Component created!',
      component_id: result.insertId
    });
  } catch (err) {
    return fail(res, err, 'saveComponent');
  }
};

exports.deleteComponent = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const [compRows] = await db.query(
      'SELECT component_id, code, name, is_statutory FROM salary_components WHERE component_id = ? AND company_id = ? LIMIT 1',
      [id, companyId]
    );
    if (!compRows.length) {
      return res.status(404).json({ success: false, message: 'Salary component not found.' });
    }
    const comp = compRows[0];

    const [usedInStruct] = await db.query(
      'SELECT item_id FROM employee_salary_structure_items WHERE company_id = ? AND component_id = ? LIMIT 1',
      [companyId, id]
    );
    const [usedInTpl] = await db.query(
      'SELECT item_id FROM salary_template_items WHERE company_id = ? AND component_id = ? LIMIT 1',
      [companyId, id]
    ).catch(() => [[]]);

    if (comp.is_statutory === 1 || usedInStruct.length > 0 || usedInTpl.length > 0) {
      await db.query(
        'UPDATE salary_components SET is_active = 0 WHERE component_id = ? AND company_id = ?',
        [id, companyId]
      );
      await writeAudit(null, companyId, {
        entity: 'SALARY_COMPONENT',
        entityId: id,
        action: 'DEACTIVATE',
        summary: `Deactivated salary component ${comp.code} (in use or statutory)`,
        userId: req.user.userId
      });
      return res.status(200).json({
        success: true,
        deactivated: true,
        message: `"${comp.name}" is used in salary templates or payroll, so it was deactivated instead of deleted.`
      });
    }

    await db.query(
      'DELETE FROM salary_components WHERE component_id = ? AND company_id = ?',
      [id, companyId]
    );
    await writeAudit(null, companyId, {
      entity: 'SALARY_COMPONENT',
      entityId: id,
      action: 'DELETE',
      summary: `Deleted salary component ${comp.code}`,
      userId: req.user.userId
    });
    return res.status(200).json({
      success: true,
      deactivated: false,
      message: `"${comp.name}" deleted permanently!`
    });
  } catch (err) {
    return fail(res, err, 'deleteComponent');
  }
};
