'use strict';

const db = require('../config/db');
const finance = require('../modules/04_finance/accounting/finance.controller');

async function seedPayrollDemo() {
  const conn = await db.getConnection();
  try {
    const [companies] = await conn.query('SELECT company_id FROM COMPANY ORDER BY company_id ASC LIMIT 1');
    if (!companies.length) {
      console.log('No company found. Register a company first.');
      return;
    }
    const companyId = companies[0].company_id;
    await finance._shared.seedDefaultAccountsIfEmpty(companyId);

    const components = [
      ['BASIC', 'Basic Salary', 'EARNING', 'FIXED', 0, 1, 0, 1],
      ['HRA', 'House Rent Allowance (HRA)', 'EARNING', 'PERCENT_OF_BASIC', 40, 1, 0, 2],
      ['CONV', 'Conveyance Allowance', 'EARNING', 'FIXED', 1600, 0, 0, 3],
      ['SPECIAL', 'Special Allowance', 'EARNING', 'FIXED', 2000, 1, 0, 4],
      ['PF_EE', 'Provident Fund (Employee)', 'DEDUCTION', 'PERCENT_OF_BASIC', 12, 0, 1, 11],
      ['ESI_EE', 'ESI (Employee)', 'DEDUCTION', 'FIXED', 0, 0, 1, 12],
      ['PT', 'Professional Tax', 'DEDUCTION', 'FIXED', 200, 0, 1, 13],
      ['TDS', 'TDS (Income Tax)', 'DEDUCTION', 'FIXED', 0, 0, 1, 14]
    ];
    for (const [code, name, type, mode, val, tax, stat, order] of components) {
      await conn.query(
        `INSERT IGNORE INTO salary_components
          (company_id, code, name, component_type, calc_mode, default_value, is_taxable, is_statutory, display_order)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [companyId, code, name, type, mode, val, tax, stat, order]
      );
    }

    await conn.query('INSERT IGNORE INTO payroll_settings (company_id) VALUES (?)', [companyId]);
    const defaultSlabs = JSON.stringify([
      { min: 0, max: 7500, tax: 0 },
      { min: 7501, max: 10000, tax: 175 },
      { min: 10001, max: 9999999, tax: 200 }
    ]);
    await conn.query(
      'INSERT IGNORE INTO statutory_settings (company_id, pt_slabs_json) VALUES (?, ?)',
      [companyId, defaultSlabs]
    );

    const sampleStaff = [
      ['EMP-101', 'Aarav Sharma', 'Production Supervisor', 32000, 'HDFC0001201', '501001122334'],
      ['EMP-102', 'Priya Patel', 'HR Executive', 26000, 'ICIC0000452', '004501556677'],
      ['EMP-103', 'Rohan Verma', 'CNC Operator', 18000, 'SBIN0003311', '331100998811'],
      ['EMP-104', 'Neha Gupta', 'Accounts Officer', 28000, 'HDFC0001201', '501009988776'],
      ['EMP-105', 'Vikram Singh', 'Quality Inspector', 22000, 'AXIS0000812', '912010033445'],
      ['EMP-106', 'Kiran Joshi', 'Assembly Technician', 16500, 'SBIN0003311', '331100445566'],
      ['EMP-107', 'Sneha Nair', 'Design Engineer', 38000, 'ICIC0000452', '004501992233'],
      ['EMP-108', 'Arjun Mehta', 'Store Keeper', 19500, 'HDFC0001201', '501007766554'],
      ['EMP-109', 'Pooja Desai', 'Dispatch Coordinator', 21000, 'AXIS0000812', '912010077889'],
      ['EMP-110', 'Deepak Yadav', 'Machine Operator', 17000, 'SBIN0003311', '331100223344'],
      ['EMP-111', 'Ritu Malhotra', 'Senior Engineer', 45000, 'HDFC0001201', '501005544332'],
      ['EMP-112', 'Suresh Kumar', 'Maintenance Lead', 24000, 'ICIC0000452', '004501667788']
    ];
    for (const [code, name, desig, sal, ifsc, acc] of sampleStaff) {
      const [found] = await conn.query(
        'SELECT employee_id FROM EMPLOYEE WHERE company_id = ? AND emp_code = ? LIMIT 1',
        [companyId, code]
      );
      if (!found.length) {
        await conn.query(
          `INSERT INTO EMPLOYEE
            (company_id, emp_code, full_name, designation, role, status, join_date, salary_base, bank_name, bank_ifsc, bank_account_no)
           VALUES (?, ?, ?, ?, 'Employee', 'active', '2026-01-15', ?, 'Demo Bank', ?, ?)`,
          [companyId, code, name, desig, sal, ifsc, acc]
        );
      }
    }

    const [emps] = await conn.query(
      `SELECT employee_id, full_name, salary_base FROM EMPLOYEE WHERE company_id = ? AND status = 'active' LIMIT 15`,
      [companyId]
    );
    const [compRows] = await conn.query(
      'SELECT component_id, code FROM salary_components WHERE company_id = ?',
      [companyId]
    );
    const compMap = Object.fromEntries(compRows.map((c) => [c.code, c.component_id]));

    for (let i = 0; i < emps.length; i += 1) {
      const emp = emps[i];
      const base = Number(emp.salary_base || 20000);
      const basic = Math.round(base * 0.50);
      const hra = Math.round(basic * 0.40);
      const conv = 1600;
      const special = Math.max(0, base - basic - hra - conv);

      const [hasStruct] = await conn.query(
        'SELECT structure_id FROM employee_salary_structures WHERE company_id = ? AND employee_id = ? AND is_current = 1 LIMIT 1',
        [companyId, emp.employee_id]
      );
      if (!hasStruct.length) {
        const [st] = await conn.query(
          `INSERT INTO employee_salary_structures
            (company_id, employee_id, salary_type, base_pay, gross_monthly, effective_from, is_current, pf_applicable, esi_applicable, pt_applicable)
           VALUES (?, ?, 'MONTHLY', ?, ?, '2026-04-01', 1, 1, ?, 1)`,
          [companyId, emp.employee_id, basic, basic + hra + conv + special, base <= 21000 ? 1 : 0]
        );
        const items = [
          [compMap.BASIC, 'FIXED', basic, basic],
          [compMap.HRA, 'PERCENT_OF_BASIC', 40, hra],
          [compMap.CONV, 'FIXED', conv, conv],
          [compMap.SPECIAL, 'FIXED', special, special]
        ];
        for (const [cid, mode, val, comp] of items) {
          if (!cid) continue;
          await conn.query(
            `INSERT INTO employee_salary_structure_items
              (company_id, structure_id, component_id, calc_mode, amount_or_percent, computed_amount)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [companyId, st.insertId, cid, mode, val, comp]
          );
        }
      }

      for (let d = 1; d <= 31; d += 1) {
        const dateStr = `2026-10-${String(d).padStart(2, '0')}`;
        const dayOfWeek = new Date(`${dateStr}T00:00:00Z`).getUTCDay();
        let status = 'Present';
        let ot = 0;
        if (dayOfWeek === 0) status = 'Weekly Off';
        else if (d === 2) status = 'Holiday';
        else if (d === 10 && i % 3 === 0) status = 'Absent';
        else if (d === 14 && i % 2 === 0) status = 'Late';
        else if (d === 19 && i % 4 === 0) status = 'Half-Day';
        else if (d === 22 && i % 2 === 1) ot = 3;

        const [attExists] = await conn.query(
          'SELECT attendance_id FROM ATTENDANCE WHERE employee_id = ? AND work_date = ? LIMIT 1',
          [emp.employee_id, dateStr]
        );
        if (!attExists.length) {
          await conn.query(
            `INSERT INTO ATTENDANCE (employee_id, work_date, check_in, check_out, status, overtime_hours)
             VALUES (?, ?, '09:05:00', '18:05:00', ?, ?)`,
            [emp.employee_id, dateStr, status, ot]
          );
        }
      }
    }

    const [bankRows] = await conn.query(
      `SELECT account_id FROM finance_account WHERE company_id = ? AND account_code = '1002' LIMIT 1`,
      [companyId]
    );
    const bankId = bankRows[0] ? bankRows[0].account_id : 1;
    if (emps.length >= 2) {
      const [advExists] = await conn.query(
        'SELECT advance_id FROM employee_advances WHERE company_id = ? LIMIT 1',
        [companyId]
      );
      if (!advExists.length) {
        await conn.query(
          `INSERT INTO employee_advances
            (company_id, employee_id, advance_date, principal_amount, emi_count, emi_amount, balance_amount, bank_account_id, reason, status)
           VALUES (?, ?, '2026-10-05', 6000.00, 3, 2000.00, 6000.00, ?, 'Festival Advance', 'ACTIVE')`,
          [companyId, emps[0].employee_id, bankId]
        );
      }
      const [bonExists] = await conn.query(
        'SELECT bonus_id FROM bonuses WHERE company_id = ? LIMIT 1',
        [companyId]
      );
      if (!bonExists.length) {
        await conn.query(
          `INSERT INTO bonuses
            (company_id, employee_id, entry_type, title, amount, pay_year, pay_month, status)
           VALUES (?, ?, 'BONUS', 'Production Target Bonus', 2500.00, 2026, 10, 'PENDING')`,
          [companyId, emps[1].employee_id]
        );
      }
    }

    console.log('Payroll demo seed completed! Employees ready:', emps.length);
  } finally {
    conn.release();
    process.exit(0);
  }
}

seedPayrollDemo().catch((err) => {
  console.error('Seed error:', err);
  process.exit(1);
});
