const db = require('../../../config/db');
const XLSX = require('xlsx');
const { num, dueDateFor, docNumber, nextSequence } = require('./finance.utils');

/** Company identity comes only from the verified JWT (set by auth middleware). */
function companyIdOf(req) {
  return req.user && req.user.companyId ? req.user.companyId : null;
}

function fail(res, err, context) {
  console.error(`[finance] ${context || 'request'}:`, err && err.message ? err.message : err);
  return res.status(500).json({
    success: false,
    message: 'Finance request could not be completed. Please try again.'
  });
}

function balanceDelta(accountType, debit, credit) {
  // Assets & Expenses increase with Debit; Liabilities, Equity & Income with Credit.
  return accountType === 'Asset' || accountType === 'Expense' ? debit - credit : credit - debit;
}

function dateFilter(column, req) {
  const { from, to } = req.query || {};
  const clauses = [];
  const values = [];
  if (from) {
    clauses.push(`${column} >= ?`);
    values.push(from);
  }
  if (to) {
    clauses.push(`${column} <= ?`);
    values.push(to);
  }
  return { clause: clauses.length ? ` AND ${clauses.join(' AND ')}` : '', values };
}

async function seedDefaultAccountsIfEmpty(companyId) {
  const [fyRows] = await db.query(
    'SELECT fy_id FROM finance_financial_year WHERE company_id = ? LIMIT 1',
    [companyId]
  );
  if (fyRows.length === 0) {
    let startMonthDay = '04-01';
    try {
      const [companies] = await db.query(
        'SELECT financial_year_start FROM COMPANY WHERE company_id = ? LIMIT 1',
        [companyId]
      );
      const value = companies[0] && companies[0].financial_year_start;
      if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
        startMonthDay = value.slice(5);
      }
    } catch (_) {}
    const now = new Date();
    const todayMonthDay = now.toISOString().slice(5, 10);
    const startYear = todayMonthDay < startMonthDay ? now.getFullYear() - 1 : now.getFullYear();
    const start = `${startYear}-${startMonthDay}`;
    const end = new Date(`${start}T00:00:00Z`);
    end.setFullYear(end.getFullYear() + 1);
    end.setDate(end.getDate() - 1);
    const fyName = `FY ${startYear}-${end.getFullYear()}`;
    await db.query(
      `INSERT IGNORE INTO finance_financial_year (company_id, fy_name, start_date, end_date, is_active, is_closed)
       VALUES (?, ?, ?, ?, 1, 0)`,
      [companyId, fyName, start, end.toISOString().slice(0, 10)]
    );
  }

  const defaults = [
    ['1001', 'Cash in Hand', 'Asset', 'Cash & Bank'],
    ['1002', 'Main Bank Account', 'Asset', 'Cash & Bank'],
    ['1100', 'Accounts Receivable (Customers)', 'Asset', 'Current Assets'],
    ['1150', 'Employee Advance', 'Asset', 'Current Assets'],
    ['1200', 'Input GST Credit', 'Asset', 'Tax Assets'],
    ['2001', 'Accounts Payable (Vendors)', 'Liability', 'Current Liabilities'],
    ['2100', 'Salaries Payable', 'Liability', 'Payroll Liabilities'],
    ['2110', 'PF Payable', 'Liability', 'Statutory Liabilities'],
    ['2120', 'ESI Payable', 'Liability', 'Statutory Liabilities'],
    ['2130', 'PT Payable', 'Liability', 'Statutory Liabilities'],
    ['2140', 'TDS Payable', 'Liability', 'Statutory Liabilities'],
    ['2200', 'Output GST Payable', 'Liability', 'Tax Liabilities'],
    ['3001', 'Owner Capital', 'Equity', 'Capital'],
    ['4001', 'Sales & Service Revenue', 'Income', 'Direct Income'],
    ['5001', 'Employee Salaries Expense', 'Expense', 'Payroll Expense'],
    ['5002', 'Office Rent & Utilities', 'Expense', 'Operating Expense'],
    ['5003', 'Software, Cloud & Hardware', 'Expense', 'IT & Admin Expense'],
    ['5004', 'Employer PF & ESI Expense', 'Expense', 'Payroll Expense']
  ];
  for (const [code, name, type, subGroup] of defaults) {
    await db.query(
      `INSERT IGNORE INTO finance_account (company_id, account_code, account_name, account_type, sub_group)
       VALUES (?, ?, ?, ?, ?)`,
      [companyId, code, name, type, subGroup]
    );
  }
}

async function activeFinancialYear(companyId, voucherDate) {
  const [rows] = await db.query(
    `SELECT * FROM finance_financial_year
     WHERE company_id = ? AND is_closed = 0 AND ? BETWEEN start_date AND end_date
     ORDER BY is_active DESC, fy_id DESC LIMIT 1`,
    [companyId, voucherDate]
  );
  return rows[0] || null;
}

async function nextVoucherNo(conn, companyId, voucherType, voucherDate) {
  const prefix = String(voucherType || 'JOURNAL').slice(0, 2).toUpperCase();
  const year = String(voucherDate).slice(0, 4);
  const pattern = `${prefix}-${year}-%`;
  const [rows] = await conn.query(
    `SELECT voucher_no FROM finance_voucher WHERE company_id = ? AND voucher_no LIKE ? ORDER BY voucher_no DESC LIMIT 1`,
    [companyId, pattern]
  );
  let seq = 1;
  if (rows.length) {
    const last = String(rows[0].voucher_no || '');
    const match = last.match(/-(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `${prefix}-${year}-${String(seq).padStart(4, '0')}`;
}

const DEFAULT_SERIES = { INVOICE: 'INV', BILL: 'BILL' };

/** Writes one audit row. Pass a connection to include it in the caller's transaction. */
async function writeAudit(conn, companyId, entry) {
  const executor = conn || db;
  const asJson = (value) => (value == null ? null : JSON.stringify(value));
  await executor.query(
    `INSERT INTO finance_audit_log
      (company_id, entity, entity_id, action, summary, before_json, after_json, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      companyId,
      entry.entity,
      entry.entityId || null,
      entry.action,
      entry.summary || null,
      asJson(entry.before),
      asJson(entry.after),
      entry.userId || null
    ]
  );
}

async function partyPaymentTerms(conn, companyId, kind, partyId) {
  if (!partyId) return '';
  const table = kind === 'vendor' ? 'finance_vendor' : 'finance_customer';
  const column = kind === 'vendor' ? 'vendor_id' : 'customer_id';
  const [rows] = await conn.query(
    `SELECT payment_terms FROM ${table} WHERE ${column} = ? AND company_id = ? LIMIT 1`,
    [partyId, companyId]
  );
  return rows[0] && rows[0].payment_terms ? rows[0].payment_terms : '';
}

/** Allocates the next invoice/bill number inside an open transaction. */
async function nextDocNo(conn, companyId, docType, docDate, explicit, userId) {
  if (explicit && String(explicit).trim()) return String(explicit).trim();
  const defaultPrefix = DEFAULT_SERIES[docType] || 'DOC';
  await conn.query(
    `INSERT IGNORE INTO finance_number_series (company_id, doc_type, prefix, last_number)
     VALUES (?, ?, ?, 0)`,
    [companyId, docType, defaultPrefix]
  );
  const [series] = await conn.query(
    `SELECT prefix, last_number FROM finance_number_series
     WHERE company_id = ? AND doc_type = ? FOR UPDATE`,
    [companyId, docType]
  );
  const prefix = series[0] && series[0].prefix ? series[0].prefix : defaultPrefix;
  const isInvoice = docType === 'INVOICE';
  const table = isInvoice ? 'finance_invoice' : 'finance_bill';
  const numberColumn = isInvoice ? 'invoice_no' : 'bill_no';
  const [existing] = await conn.query(
    `SELECT ${numberColumn} AS doc_no FROM ${table}
     WHERE company_id = ? AND ${numberColumn} LIKE ?`,
    [companyId, `${prefix}-${String(docDate).slice(0, 4)}-%`]
  );
  const seq = nextSequence(
    series[0] ? series[0].last_number : 0,
    existing.map((row) => row.doc_no),
    prefix,
    docDate
  );
  await conn.query(
    `UPDATE finance_number_series SET last_number = ?, updated_by = ?
     WHERE company_id = ? AND doc_type = ?`,
    [seq, userId || null, companyId, docType]
  );
  return docNumber(prefix, docDate, seq);
}

// ---------------------------------------------------------------- Accounts

exports.getAccounts = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    const [accounts] = await db.query(
      `SELECT account_id, account_code, account_name, account_type, sub_group, opening_balance,
              current_balance, is_active, created_at
       FROM finance_account WHERE company_id = ? ORDER BY account_code ASC`,
      [companyId]
    );
    const [years] = await db.query(
      `SELECT fy_id, fy_name, DATE_FORMAT(start_date, '%Y-%m-%d') AS start_date,
              DATE_FORMAT(end_date, '%Y-%m-%d') AS end_date, is_active, is_closed
       FROM finance_financial_year WHERE company_id = ? ORDER BY fy_id DESC`,
      [companyId]
    );
    return res.status(200).json({ success: true, data: accounts, financialYears: years });
  } catch (err) {
    return fail(res, err, 'getAccounts');
  }
};

exports.createAccount = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { account_code, account_name, account_type, sub_group, opening_balance } = req.body || {};
    const allowed = ['Asset', 'Liability', 'Equity', 'Income', 'Expense'];
    if (!account_code || !account_name || !allowed.includes(account_type)) {
      return res.status(400).json({
        success: false,
        message: 'Account code, name and a valid type (Asset/Liability/Equity/Income/Expense) are required.'
      });
    }
    const opening = num(opening_balance);
    const [dup] = await db.query(
      'SELECT account_id FROM finance_account WHERE company_id = ? AND account_code = ?',
      [companyId, String(account_code).trim()]
    );
    if (dup.length) {
      return res.status(409).json({ success: false, message: 'Account code already exists.' });
    }
    const [result] = await db.query(
      `INSERT INTO finance_account
        (company_id, account_code, account_name, account_type, sub_group, opening_balance, current_balance)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        companyId,
        String(account_code).trim(),
        String(account_name).trim(),
        account_type,
        sub_group || 'General',
        opening,
        opening
      ]
    );
    await writeAudit(null, companyId, {
      entity: 'ACCOUNT',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Account ${account_code} (${account_type}) created`,
      after: { account_code, account_name, account_type, sub_group, opening_balance: opening },
      userId: req.user.userId
    });
    return res.status(201).json({ success: true, message: 'Account created!', account_id: result.insertId });
  } catch (err) {
    return fail(res, err, 'createAccount');
  }
};

exports.updateAccount = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const { account_name, sub_group, is_active } = req.body || {};
    if (!account_name) {
      return res.status(400).json({ success: false, message: 'Account name is required.' });
    }
    const [beforeRows] = await db.query(
      'SELECT * FROM finance_account WHERE account_id = ? AND company_id = ?',
      [id, companyId]
    );
    if (!beforeRows.length) return res.status(404).json({ success: false, message: 'Account not found.' });
    const [result] = await db.query(
      `UPDATE finance_account SET account_name = ?, sub_group = ?, is_active = ?
       WHERE account_id = ? AND company_id = ?`,
      [String(account_name).trim(), sub_group || 'General', is_active === 0 ? 0 : 1, id, companyId]
    );
    if (!result.affectedRows) return res.status(404).json({ success: false, message: 'Account not found.' });
    await writeAudit(null, companyId, {
      entity: 'ACCOUNT',
      entityId: id,
      action: 'UPDATE',
      summary: `Account ${beforeRows[0].account_code} updated`,
      before: beforeRows[0],
      after: { account_name, sub_group: sub_group || 'General', is_active: is_active === 0 ? 0 : 1 },
      userId: req.user.userId
    });
    return res.status(200).json({ success: true, message: 'Account updated!' });
  } catch (err) {
    return fail(res, err, 'updateAccount');
  }
};

// -------------------------------------------------------- Financial years

exports.getFinancialYears = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    const [rows] = await db.query(
      `SELECT fy_id, fy_name, DATE_FORMAT(start_date, '%Y-%m-%d') AS start_date,
              DATE_FORMAT(end_date, '%Y-%m-%d') AS end_date, is_active, is_closed
       FROM finance_financial_year WHERE company_id = ? ORDER BY fy_id DESC`,
      [companyId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getFinancialYears');
  }
};

exports.createFinancialYear = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { fy_name, start_date, end_date } = req.body || {};
    if (!fy_name || !start_date || !end_date || start_date > end_date) {
      return res.status(400).json({ success: false, message: 'Valid name, start date and end date are required.' });
    }
    const [result] = await db.query(
      `INSERT INTO finance_financial_year (company_id, fy_name, start_date, end_date, is_active, is_closed)
       VALUES (?, ?, ?, ?, 0, 0)`,
      [companyId, String(fy_name).trim(), start_date, end_date]
    );
    return res.status(201).json({ success: true, message: 'Financial year created!', fy_id: result.insertId });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ success: false, message: 'Financial year with this name already exists.' });
    }
    return fail(res, err, 'createFinancialYear');
  }
};

exports.setFinancialYearStatus = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const { is_closed, is_active } = req.body || {};
    if (is_active === 1) {
      await db.query(
        'UPDATE finance_financial_year SET is_active = 0 WHERE company_id = ?',
        [companyId]
      );
    }
    const fields = [];
    const values = [];
    if (is_closed !== undefined) {
      fields.push('is_closed = ?');
      values.push(is_closed ? 1 : 0);
    }
    if (is_active !== undefined) {
      fields.push('is_active = ?');
      values.push(is_active ? 1 : 0);
    }
    if (!fields.length) return res.status(400).json({ success: false, message: 'No status supplied.' });
    values.push(id, companyId);
    const [result] = await db.query(
      `UPDATE finance_financial_year SET ${fields.join(', ')} WHERE fy_id = ? AND company_id = ?`,
      values
    );
    if (!result.affectedRows) return res.status(404).json({ success: false, message: 'Financial year not found.' });
    return res.status(200).json({ success: true, message: 'Financial year updated!' });
  } catch (err) {
    return fail(res, err, 'setFinancialYearStatus');
  }
};

// ---------------------------------------------------------------- Vouchers

exports.createVoucher = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const { voucher_type = 'Journal', voucher_date, narration, items = [] } = req.body || {};
    const types = ['Payment', 'Receipt', 'Journal', 'Contra', 'Sales', 'Purchase'];
    if (!voucher_date || !types.includes(voucher_type) || !Array.isArray(items) || items.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Valid date, voucher type and at least 2 debit/credit lines are required.'
      });
    }
    const fy = await activeFinancialYear(companyId, voucher_date);
    if (!fy) {
      return res.status(400).json({ success: false, message: 'No open financial year covers this date.' });
    }

    let totalDebit = 0;
    let totalCredit = 0;
    const normalized = [];
    for (const item of items) {
      const debit = num(item.debit_amount);
      const credit = num(item.credit_amount);
      if (debit < 0 || credit < 0 || (debit > 0 && credit > 0)) {
        return res.status(400).json({
          success: false,
          message: 'Each line must have either a debit or a credit amount, never both.'
        });
      }
      if (!item.account_id || (debit === 0 && credit === 0)) continue;
      totalDebit += debit;
      totalCredit += credit;
      normalized.push({ ...item, debit, credit });
    }
    if (normalized.length < 2 || totalDebit <= 0 || Math.abs(totalDebit - totalCredit) > 0.01) {
      return res.status(400).json({
        success: false,
        message: `Unbalanced entry: total debit ₹${totalDebit.toFixed(2)} must equal total credit ₹${totalCredit.toFixed(2)}.`
      });
    }

    await conn.beginTransaction();
    let voucherNo = '';
    let voucherId = null;
    for (let attempt = 0; attempt < 5; attempt += 1) {
      try {
        voucherNo = await nextVoucherNo(conn, companyId, voucher_type, voucher_date);
        const [vResult] = await conn.query(
          `INSERT INTO finance_voucher
            (company_id, voucher_no, voucher_type, voucher_date, narration, total_amount, created_by, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'POSTED')`,
          [companyId, voucherNo, voucher_type, voucher_date, narration || '', totalDebit, req.user.userId || null]
        );
        voucherId = vResult.insertId;
        break;
      } catch (err) {
        if (!(err && err.code === 'ER_DUP_ENTRY')) throw err;
      }
    }
    if (!voucherId) throw new Error('Could not allocate a unique voucher number.');

    for (const item of normalized) {
      const [accounts] = await conn.query(
        'SELECT account_type, is_active FROM finance_account WHERE account_id = ? AND company_id = ? LIMIT 1',
        [item.account_id, companyId]
      );
      if (!accounts.length || !accounts[0].is_active) {
        throw new Error(`Account #${item.account_id} is unavailable for this company.`);
      }
      await conn.query(
        `INSERT INTO finance_voucher_item
          (company_id, voucher_id, account_id, debit_amount, credit_amount, description, department_id, project_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          companyId,
          voucherId,
          item.account_id,
          item.debit,
          item.credit,
          item.description || '',
          item.department_id || null,
          item.project_id || null
        ]
      );
      await conn.query(
        'UPDATE finance_account SET current_balance = current_balance + ? WHERE account_id = ?',
        [balanceDelta(accounts[0].account_type, item.debit, item.credit), item.account_id]
      );
    }
    await writeAudit(conn, companyId, {
      entity: 'VOUCHER',
      entityId: voucherId,
      action: 'CREATE',
      summary: `${voucher_type} voucher ${voucherNo} posted for ₹${totalDebit.toFixed(2)}`,
      after: {
        voucher_no: voucherNo,
        voucher_type,
        voucher_date,
        total_amount: totalDebit,
        lines: normalized.map((item) => ({
          account_id: item.account_id,
          debit: item.debit,
          credit: item.credit
        }))
      },
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(201).json({
      success: true,
      message: `Voucher ${voucherNo} posted!`,
      voucher_id: voucherId,
      voucher_no: voucherNo
    });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    return fail(res, err, 'createVoucher');
  } finally {
    conn.release();
  }
};

exports.getVouchers = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const params = [companyId];
    let sql =
      `SELECT v.voucher_id, v.voucher_no, v.voucher_type,
              DATE_FORMAT(v.voucher_date, '%Y-%m-%d') AS voucher_date,
              v.narration, v.total_amount, v.status, v.cancel_reason,
              v.created_by, DATE_FORMAT(v.created_at, '%Y-%m-%d %H:%i') AS created_at,
              u.email AS created_by_email
       FROM finance_voucher v
       LEFT JOIN USER u ON v.created_by = u.user_id
       WHERE v.company_id = ?`;
    const { voucher_type, status, search } = req.query || {};
    if (voucher_type) { sql += ' AND v.voucher_type = ?'; params.push(voucher_type); }
    if (status) { sql += ' AND v.status = ?'; params.push(status); }
    if (search) { sql += ' AND (v.voucher_no LIKE ? OR v.narration LIKE ?)'; params.push(`%${search}%`, `%${search}%`); }
    const filter = dateFilter('v.voucher_date', req);
    sql += filter.clause;
    params.push(...filter.values);
    sql += ' ORDER BY v.voucher_date DESC, v.voucher_id DESC LIMIT 200';
    const [rows] = await db.query(sql, params);
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getVouchers');
  }
};

exports.getVoucherDetails = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const [vouchers] = await db.query(
      'SELECT * FROM finance_voucher WHERE voucher_id = ? AND company_id = ?',
      [id, companyId]
    );
    if (!vouchers.length) return res.status(404).json({ success: false, message: 'Voucher not found.' });
    const [items] = await db.query(
      `SELECT i.*, a.account_code, a.account_name
       FROM finance_voucher_item i
       JOIN finance_account a ON i.account_id = a.account_id
       WHERE i.voucher_id = ? AND i.company_id = ?
       ORDER BY i.item_id ASC`,
      [id, companyId]
    );
    return res.status(200).json({ success: true, data: { ...vouchers[0], items } });
  } catch (err) {
    return fail(res, err, 'getVoucherDetails');
  }
};

exports.cancelVoucher = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const { id } = req.params;
    const { reason } = req.body || {};
    const cleanReason = String(reason || '').trim();
    if (!cleanReason) {
      return res.status(400).json({ success: false, message: 'Cancellation reason is required.' });
    }
    const [vouchers] = await conn.query(
      'SELECT * FROM finance_voucher WHERE voucher_id = ? AND company_id = ?',
      [id, companyId]
    );
    if (!vouchers.length) return res.status(404).json({ success: false, message: 'Voucher not found.' });
    if (vouchers[0].status === 'CANCELLED') {
      return res.status(400).json({ success: false, message: 'Voucher is already cancelled.' });
    }
    const fy = await activeFinancialYear(companyId, vouchers[0].voucher_date);
    if (!fy) {
      return res.status(400).json({ success: false, message: 'The financial year for this voucher is closed.' });
    }

    await conn.beginTransaction();
    const [items] = await conn.query(
      `SELECT i.*, a.account_type
       FROM finance_voucher_item i
       JOIN finance_account a ON i.account_id = a.account_id
       WHERE i.voucher_id = ? AND i.company_id = ?`,
      [id, companyId]
    );
    for (const item of items) {
      const reverse = -balanceDelta(item.account_type, num(item.debit_amount), num(item.credit_amount));
      await conn.query(
        'UPDATE finance_account SET current_balance = current_balance + ? WHERE account_id = ? AND company_id = ?',
        [reverse, item.account_id, companyId]
      );
    }
    await conn.query(
      `UPDATE finance_voucher
       SET status = 'CANCELLED', cancel_reason = ?, cancelled_by = ?, cancelled_at = NOW()
       WHERE voucher_id = ? AND company_id = ?`,
      [cleanReason.slice(0, 255), req.user.userId || null, id, companyId]
    );
    await writeAudit(conn, companyId, {
      entity: 'VOUCHER',
      entityId: id,
      action: 'CANCEL',
      summary: `Voucher ${vouchers[0].voucher_no} cancelled: ${cleanReason}`,
      before: { status: vouchers[0].status, total_amount: vouchers[0].total_amount },
      after: { status: 'CANCELLED', cancel_reason: cleanReason.slice(0, 255) },
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(200).json({ success: true, message: 'Voucher cancelled and balances reversed.' });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    return fail(res, err, 'cancelVoucher');
  } finally {
    conn.release();
  }
};

// ----------------------------------------------------------- Ledger/report

exports.getGeneralLedger = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { account_id } = req.query || {};
    if (!account_id) return res.status(400).json({ success: false, message: 'account_id is required.' });
    const [accounts] = await db.query(
      'SELECT * FROM finance_account WHERE account_id = ? AND company_id = ?',
      [account_id, companyId]
    );
    if (!accounts.length) return res.status(404).json({ success: false, message: 'Account not found.' });
    const account = accounts[0];

    const params = [account_id, companyId];
    let sql =
      `SELECT v.voucher_id, v.voucher_no, v.voucher_type,
              DATE_FORMAT(v.voucher_date, '%Y-%m-%d') AS voucher_date,
              v.narration, i.debit_amount, i.credit_amount, i.description
       FROM finance_voucher_item i
       JOIN finance_voucher v ON i.voucher_id = v.voucher_id
       WHERE i.account_id = ? AND v.company_id = ? AND v.status = 'POSTED'`;
    const filter = dateFilter('v.voucher_date', req);
    sql += filter.clause;
    params.push(...filter.values);
    sql += ' ORDER BY v.voucher_date ASC, v.voucher_id ASC';
    const [entries] = await db.query(sql, params);

    let running = num(account.opening_balance);
    const isDebitNormal = account.account_type === 'Asset' || account.account_type === 'Expense';
    const rows = entries.map((entry) => {
      running += num(entry.debit_amount) - num(entry.credit_amount);
      return {
        ...entry,
        running_balance: Math.abs(running),
        running_side: running >= 0 ? (isDebitNormal ? 'Dr' : 'Cr') : (isDebitNormal ? 'Cr' : 'Dr')
      };
    });
    return res.status(200).json({
      success: true,
      account,
      opening_balance: num(account.opening_balance),
      closing_balance: rows.length ? rows[rows.length - 1].running_balance : num(account.opening_balance),
      entries: rows
    });
  } catch (err) {
    return fail(res, err, 'getGeneralLedger');
  }
};

exports.getTrialBalance = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    const filter = dateFilter('v.voucher_date', req);
    const params = [companyId, ...filter.values, companyId];
    const [rows] = await db.query(
      `SELECT a.account_id, a.account_code, a.account_name, a.account_type,
              a.opening_balance,
              COALESCE(SUM(i.debit_amount), 0) AS period_debit,
              COALESCE(SUM(i.credit_amount), 0) AS period_credit
       FROM finance_account a
       LEFT JOIN finance_voucher_item i ON a.account_id = i.account_id
       LEFT JOIN finance_voucher v ON i.voucher_id = v.voucher_id
         AND v.company_id = ? AND v.status = 'POSTED'${filter.clause}
       WHERE a.company_id = ?
       GROUP BY a.account_id
       ORDER BY a.account_code ASC`,
      params
    );
    let totalDebit = 0;
    let totalCredit = 0;
    const data = rows.map((row) => {
      const opening = num(row.opening_balance);
      const debitNormal = row.account_type === 'Asset' || row.account_type === 'Expense';
      const openingDebit = debitNormal && opening > 0 ? opening : 0;
      const openingCredit = !debitNormal && opening > 0 ? opening : 0;
      const periodDebit = num(row.period_debit);
      const periodCredit = num(row.period_credit);
      const finalDebit = openingDebit + periodDebit;
      const finalCredit = openingCredit + periodCredit;
      totalDebit += finalDebit;
      totalCredit += finalCredit;
      return {
        ...row,
        opening_debit: openingDebit,
        opening_credit: openingCredit,
        total_debit: finalDebit,
        total_credit: finalCredit,
        closing_balance: Math.abs(finalDebit - finalCredit),
        closing_side: finalDebit >= finalCredit ? 'Dr' : 'Cr'
      };
    });
    return res.status(200).json({
      success: true,
      data,
      totals: { debit: totalDebit, credit: totalCredit, is_balanced: Math.abs(totalDebit - totalCredit) <= 0.01 }
    });
  } catch (err) {
    return fail(res, err, 'getTrialBalance');
  }
};

exports.getProfitLoss = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const filter = dateFilter('v.voucher_date', req);
    const params = [companyId, ...filter.values];
    const [rows] = await db.query(
      `SELECT a.account_id, a.account_code, a.account_name, a.account_type,
              COALESCE(SUM(i.debit_amount), 0) AS debit,
              COALESCE(SUM(i.credit_amount), 0) AS credit
       FROM finance_voucher_item i
       JOIN finance_voucher v ON i.voucher_id = v.voucher_id AND v.status = 'POSTED'
       JOIN finance_account a ON i.account_id = a.account_id AND a.company_id = v.company_id
       WHERE v.company_id = ? AND a.account_type IN ('Income', 'Expense')${filter.clause}
       GROUP BY a.account_id
       ORDER BY a.account_code ASC`,
      params
    );
    let income = 0;
    let expense = 0;
    const data = rows.map((row) => {
      const amount = row.account_type === 'Income'
        ? num(row.credit) - num(row.debit)
        : num(row.debit) - num(row.credit);
      if (row.account_type === 'Income') income += amount;
      else expense += amount;
      return { ...row, amount: Math.abs(amount) };
    });
    return res.status(200).json({
      success: true,
      income,
      expense,
      net_profit: income - expense,
      data
    });
  } catch (err) {
    return fail(res, err, 'getProfitLoss');
  }
};

exports.getBalanceSheet = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    const filter = dateFilter('v.voucher_date', req);
    const params = [companyId, ...filter.values, companyId];
    const [rows] = await db.query(
      `SELECT a.account_id, a.account_code, a.account_name, a.account_type,
              a.opening_balance,
              COALESCE(SUM(i.debit_amount), 0) AS debit,
              COALESCE(SUM(i.credit_amount), 0) AS credit
       FROM finance_account a
       LEFT JOIN finance_voucher_item i ON a.account_id = i.account_id
       LEFT JOIN finance_voucher v ON i.voucher_id = v.voucher_id
         AND v.company_id = ? AND v.status = 'POSTED'${filter.clause}
       WHERE a.company_id = ?
       GROUP BY a.account_id
       ORDER BY a.account_code ASC`,
      params
    );
    const groups = { Asset: 0, Liability: 0, Equity: 0 };
    const data = rows.map((row) => {
      const opening = num(row.opening_balance);
      const debitNormal = row.account_type === 'Asset' || row.account_type === 'Expense';
      const balance = debitNormal
        ? opening + num(row.debit) - num(row.credit)
        : opening + num(row.credit) - num(row.debit);
      if (groups[row.account_type] !== undefined) groups[row.account_type] += balance;
      return { ...row, balance: Math.abs(balance), side: balance >= 0 ? 'Dr' : 'Cr' };
    });

    // Current period profit is part of equity on the balance sheet.
    const pFilter = dateFilter('v.voucher_date', req);
    const pParams = [companyId, ...pFilter.values];
    const [plRows] = await db.query(
      `SELECT a.account_type,
              COALESCE(SUM(i.debit_amount), 0) AS debit,
              COALESCE(SUM(i.credit_amount), 0) AS credit
       FROM finance_voucher_item i
       JOIN finance_voucher v ON i.voucher_id = v.voucher_id AND v.status = 'POSTED'
       JOIN finance_account a ON i.account_id = a.account_id AND a.company_id = v.company_id
       WHERE v.company_id = ? AND a.account_type IN ('Income', 'Expense')${pFilter.clause}
       GROUP BY a.account_type`,
      pParams
    );
    let netProfit = 0;
    for (const row of plRows) {
      netProfit += row.account_type === 'Income'
        ? num(row.credit) - num(row.debit)
        : -(num(row.debit) - num(row.credit));
    }
    const totalAssets = groups.Asset;
    const totalLiabilitiesAndEquity = groups.Liability + groups.Equity + netProfit;
    return res.status(200).json({
      success: true,
      data,
      totals: {
        assets: totalAssets,
        liabilities: groups.Liability,
        equity: groups.Equity,
        net_profit: netProfit,
        liabilities_and_equity: totalLiabilitiesAndEquity,
        is_balanced: Math.abs(totalAssets - totalLiabilitiesAndEquity) <= 0.01
      }
    });
  } catch (err) {
    return fail(res, err, 'getBalanceSheet');
  }
};

exports.getDashboard = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    const [totals] = await db.query(
      `SELECT account_type, SUM(current_balance) AS total
       FROM finance_account WHERE company_id = ? AND is_active = 1
       GROUP BY account_type`,
      [companyId]
    );
    const summary = { Asset: 0, Liability: 0, Equity: 0, Income: 0, Expense: 0 };
    for (const row of totals) summary[row.account_type] = num(row.total);
    const [cashRows] = await db.query(
      `SELECT account_code, account_name, current_balance
       FROM finance_account
       WHERE company_id = ? AND sub_group = 'Cash & Bank' AND is_active = 1
       ORDER BY account_code ASC`,
      [companyId]
    );
    const [recent] = await db.query(
      `SELECT voucher_id, voucher_no, voucher_type, DATE_FORMAT(voucher_date, '%Y-%m-%d') AS voucher_date,
              total_amount, status
       FROM finance_voucher WHERE company_id = ?
       ORDER BY voucher_date DESC, voucher_id DESC LIMIT 5`,
      [companyId]
    );
    const [counts] = await db.query(
      `SELECT status, COUNT(*) AS cnt FROM finance_voucher WHERE company_id = ? GROUP BY status`,
      [companyId]
    );
    return res.status(200).json({ success: true, summary, cash_and_bank: cashRows, recent_vouchers: recent, counts });
  } catch (err) {
    return fail(res, err, 'getDashboard');
  }
};

// ------------------------------------------- Parties, bills and payments

const partyConfig = {
  vendors: { table: 'finance_vendor', id: 'vendor_id', name: 'vendor_name', label: 'Vendor' },
  customers: { table: 'finance_customer', id: 'customer_id', name: 'customer_name', label: 'Customer' },
  banks: { table: 'finance_bank_account', id: 'bank_account_id', name: 'bank_name', label: 'Bank account' }
};

async function listParties(kind, companyId) {
  const cfg = partyConfig[kind];
  const [rows] = await db.query(`SELECT * FROM ${cfg.table} WHERE company_id = ? ORDER BY ${cfg.name} ASC`, [companyId]);
  return rows;
}

exports.getParties = async (req, res) => {
  try {
    await seedDefaultAccountsIfEmpty(companyIdOf(req));
    const [vendors, customers, banks] = await Promise.all([
      listParties('vendors', companyIdOf(req)),
      listParties('customers', companyIdOf(req)),
      listParties('banks', companyIdOf(req))
    ]);
    return res.status(200).json({ success: true, vendors, customers, banks });
  } catch (err) {
    return fail(res, err, 'getParties');
  }
};

const partyFields = {
  vendors: [
    'tax_no', 'gstin', 'pan', 'contact', 'address', 'payment_terms',
    'bank_name', 'bank_account_no', 'bank_ifsc', 'credit_limit'
  ],
  customers: ['tax_no', 'gstin', 'pan', 'contact', 'address', 'credit_limit', 'payment_terms'],
  banks: ['ifsc', 'branch', 'account_type', 'contact']
};

const cleanValue = (value) => {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  return String(value).trim();
};

function partyValues(kind, body) {
  const values = {};
  for (const field of partyFields[kind] || []) {
    if (Object.prototype.hasOwnProperty.call(body, field)) values[field] = cleanValue(body[field]);
  }
  if (!values.tax_no && values.gstin) values.tax_no = values.gstin;
  return values;
}

exports.createParty = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { kind } = req.params;
    const cfg = partyConfig[kind];
    if (!cfg) return res.status(400).json({ success: false, message: 'Unknown party type.' });
    const body = req.body || {};
    const { name, account_ref } = body;
    if (!name || (kind === 'banks' && !account_ref)) {
      return res.status(400).json({ success: false, message: 'Name and account reference are required.' });
    }
    const fields = partyValues(kind, body);
    const columns = ['company_id', cfg.name, 'is_active'];
    const values = [companyId, String(name).trim(), 1];
    if (kind === 'banks') {
      columns.push('account_ref');
      values.push(String(account_ref).trim());
    }
    for (const [field, value] of Object.entries(fields)) {
      columns.push(field);
      values.push(value);
    }
    const placeholders = columns.map(() => '?').join(', ');
    const [result] = await db.query(
      `INSERT INTO ${cfg.table} (${columns.join(', ')}) VALUES (${placeholders})`,
      values
    );
    await writeAudit(null, companyId, {
      entity: kind.toUpperCase(),
      entityId: result.insertId,
      action: 'CREATE',
      summary: `${cfg.label} ${name} created`,
      after: { name, ...fields, account_ref: account_ref || null },
      userId: req.user.userId
    });
    return res.status(201).json({ success: true, message: `${cfg.label} created!`, id: result.insertId });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ success: false, message: 'This party already exists.' });
    }
    return fail(res, err, 'createParty');
  }
};

exports.updateParty = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { kind, id } = req.params;
    const cfg = partyConfig[kind];
    if (!cfg) return res.status(400).json({ success: false, message: 'Unknown party type.' });
    const body = req.body || {};
    const [beforeRows] = await db.query(
      `SELECT * FROM ${cfg.table} WHERE ${cfg.id} = ? AND company_id = ?`,
      [id, companyId]
    );
    if (!beforeRows.length) return res.status(404).json({ success: false, message: `${cfg.label} not found.` });
    const assignments = [];
    const values = [];
    if (body.name) {
      assignments.push(`${cfg.name} = ?`);
      values.push(String(body.name).trim());
    }
    if (kind === 'banks' && body.account_ref) {
      assignments.push('account_ref = ?');
      values.push(String(body.account_ref).trim());
    }
    for (const [field, value] of Object.entries(partyValues(kind, body))) {
      assignments.push(`${field} = ?`);
      values.push(value);
    }
    if (Object.prototype.hasOwnProperty.call(body, 'is_active')) {
      assignments.push('is_active = ?');
      values.push(body.is_active === 0 ? 0 : 1);
    }
    if (!assignments.length) {
      return res.status(400).json({ success: false, message: 'No fields to update.' });
    }
    values.push(id, companyId);
    await db.query(
      `UPDATE ${cfg.table} SET ${assignments.join(', ')} WHERE ${cfg.id} = ? AND company_id = ?`,
      values
    );
    await writeAudit(null, companyId, {
      entity: kind.toUpperCase(),
      entityId: id,
      action: 'UPDATE',
      summary: `${cfg.label} ${beforeRows[0][cfg.name]} updated`,
      before: beforeRows[0],
      after: body,
      userId: req.user.userId
    });
    return res.status(200).json({ success: true, message: `${cfg.label} updated!` });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ success: false, message: 'This party already exists.' });
    }
    return fail(res, err, 'updateParty');
  }
};

exports.getBills = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const [rows] = await db.query(
      `SELECT b.*, v.vendor_name,
              COALESCE((SELECT SUM(p.amount) FROM finance_payment p WHERE p.bill_id = b.bill_id), 0) AS paid_amount
       FROM finance_bill b
       JOIN finance_vendor v ON b.vendor_id = v.vendor_id
       WHERE b.company_id = ?
       ORDER BY b.bill_date DESC, b.bill_id DESC LIMIT 200`,
      [companyId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getBills');
  }
};

exports.createBill = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const {
      vendor_id, bill_no, bill_date, due_date, po_no, grn_no,
      po_amount, grn_amount, tax_amount, items = []
    } = req.body || {};
    if (!vendor_id || !bill_date || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Vendor, date and at least one line are required.'
      });
    }
    const lineTotal = items.reduce(
      (sum, item) => sum + (num(item.qty) || 1) * num(item.rate),
      0
    );
    const tax = num(tax_amount);
    const total = lineTotal + tax;
    const expectedPo = num(po_amount);
    const expectedGrn = num(grn_amount);
    let matchStatus = 'NOT_CHECKED';
    let status = 'DRAFT';
    let holdReason = null;
    if (po_no && grn_no && (expectedPo > 0 || expectedGrn > 0)) {
      const within = (a, b) => Math.abs(a - b) <= 0.01;
      if (within(total, expectedPo) && within(total, expectedGrn)) {
        matchStatus = 'MATCHED';
      } else {
        matchStatus = 'FLAGGED';
        status = 'FLAGGED';
        holdReason = `Mismatch: bill ₹${total.toFixed(2)}, PO ₹${expectedPo.toFixed(2)}, GRN ₹${expectedGrn.toFixed(2)}`;
      }
    }

    await conn.beginTransaction();
    const billNo = await nextDocNo(conn, companyId, 'BILL', bill_date, bill_no, req.user.userId);
    const vendorTerms = await partyPaymentTerms(conn, companyId, 'vendor', vendor_id);
    const dueDate = dueDateFor(bill_date, vendorTerms, due_date);
    const [result] = await conn.query(
      `INSERT INTO finance_bill
        (company_id, vendor_id, bill_no, bill_date, due_date, po_no, grn_no, po_amount, grn_amount,
         total_amount, tax_amount, match_status, status, hold_reason, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        companyId, vendor_id, billNo, bill_date, dueDate, po_no || null, grn_no || null,
        expectedPo, expectedGrn, total, tax, matchStatus, status, holdReason, req.user.userId || null
      ]
    );
    for (const item of items) {
      const qty = num(item.qty) || 1;
      const rate = num(item.rate);
      await conn.query(
        `INSERT INTO finance_bill_item (company_id, bill_id, description, qty, rate, amount)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [companyId, result.insertId, item.description || '', qty, rate, qty * rate]
      );
    }
    await writeAudit(conn, companyId, {
      entity: 'BILL',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Bill ${billNo} recorded for ₹${total.toFixed(2)} (${matchStatus})`,
      after: {
        bill_no: billNo,
        vendor_id,
        bill_date,
        due_date: dueDate,
        total_amount: total,
        match_status: matchStatus,
        status
      },
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(201).json({
      success: true,
      message: status === 'FLAGGED' ? 'Bill flagged: 3-way match failed.' : 'Bill recorded.',
      bill_id: result.insertId,
      bill_no: billNo,
      due_date: dueDate,
      match_status: matchStatus,
      hold_reason: holdReason
    });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ success: false, message: 'Bill number already exists.' });
    }
    return fail(res, err, 'createBill');
  } finally {
    conn.release();
  }
};

exports.approveBill = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const [rows] = await db.query(
      'SELECT * FROM finance_bill WHERE bill_id = ? AND company_id = ?',
      [id, companyId]
    );
    if (!rows.length) return res.status(404).json({ success: false, message: 'Bill not found.' });
    if (rows[0].match_status !== 'MATCHED') {
      return res.status(400).json({
        success: false,
        message: 'Bill cannot be approved until PO, GRN and bill amounts match.'
      });
    }
    if (!['DRAFT', 'FLAGGED'].includes(rows[0].status)) {
      return res.status(400).json({ success: false, message: 'Bill is not pending approval.' });
    }
    await db.query(
      "UPDATE finance_bill SET status = 'APPROVED', hold_reason = NULL WHERE bill_id = ? AND company_id = ?",
      [id, companyId]
    );
    await writeAudit(null, companyId, {
      entity: 'BILL',
      entityId: id,
      action: 'APPROVE',
      summary: `Bill ${rows[0].bill_no} approved for payment`,
      before: { status: rows[0].status },
      after: { status: 'APPROVED' },
      userId: req.user.userId
    });
    return res.status(200).json({ success: true, message: 'Bill approved for payment.' });
  } catch (err) {
    return fail(res, err, 'approveBill');
  }
};

exports.getInvoices = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const [rows] = await db.query(
      `SELECT i.*, c.customer_name,
              COALESCE((SELECT SUM(p.amount) FROM finance_payment p WHERE p.invoice_id = i.invoice_id), 0) AS paid_amount
       FROM finance_invoice i
       JOIN finance_customer c ON i.customer_id = c.customer_id
       WHERE i.company_id = ?
       ORDER BY i.invoice_date DESC, i.invoice_id DESC LIMIT 200`,
      [companyId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getInvoices');
  }
};

exports.createInvoice = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const { customer_id, project_id, invoice_no, invoice_date, due_date, tax_amount, items = [] } = req.body || {};
    if (!customer_id || !invoice_date || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Customer, date and at least one line are required.'
      });
    }
    const lineTotal = items.reduce((sum, item) => sum + (num(item.qty) || 1) * num(item.rate), 0);
    const total = lineTotal + num(tax_amount);
    await conn.beginTransaction();
    const invoiceNumber = await nextDocNo(conn, companyId, 'INVOICE', invoice_date, invoice_no, req.user.userId);
    const customerTerms = await partyPaymentTerms(conn, companyId, 'customer', customer_id);
    const dueDate = dueDateFor(invoice_date, customerTerms, due_date);
    const [result] = await conn.query(
      `INSERT INTO finance_invoice
        (company_id, customer_id, project_id, invoice_no, invoice_date, due_date,
         total_amount, tax_amount, status, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ISSUED', ?)`,
      [
        companyId, customer_id, project_id || null, invoiceNumber, invoice_date, dueDate,
        total, num(tax_amount), req.user.userId || null
      ]
    );
    for (const item of items) {
      const qty = num(item.qty) || 1;
      const rate = num(item.rate);
      await conn.query(
        `INSERT INTO finance_invoice_item (company_id, invoice_id, description, qty, rate, amount)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [companyId, result.insertId, item.description || '', qty, rate, qty * rate]
      );
    }
    await writeAudit(conn, companyId, {
      entity: 'INVOICE',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Invoice ${invoiceNumber} issued for ₹${total.toFixed(2)}`,
      after: {
        invoice_no: invoiceNumber,
        customer_id,
        project_id: project_id || null,
        invoice_date,
        due_date: dueDate,
        total_amount: total
      },
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(201).json({
      success: true,
      message: 'Invoice issued.',
      invoice_id: result.insertId,
      invoice_no: invoiceNumber,
      due_date: dueDate
    });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ success: false, message: 'Invoice number already exists.' });
    }
    return fail(res, err, 'createInvoice');
  } finally {
    conn.release();
  }
};

/** Posts a balanced voucher inside an existing transaction. */
async function postVoucher(conn, companyId, payload) {
  const { voucher_type, voucher_date, narration, items, userId } = payload;
  let totalDebit = 0;
  let totalCredit = 0;
  for (const item of items) {
    totalDebit += num(item.debit_amount);
    totalCredit += num(item.credit_amount);
  }
  if (Math.abs(totalDebit - totalCredit) > 0.01 || totalDebit <= 0) {
    throw new Error('Payment voucher must be balanced.');
  }
  let voucherNo = '';
  let voucherId = null;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      voucherNo = await nextVoucherNo(conn, companyId, voucher_type, voucher_date);
      const [res] = await conn.query(
        `INSERT INTO finance_voucher
          (company_id, voucher_no, voucher_type, voucher_date, narration, total_amount, created_by, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'POSTED')`,
        [companyId, voucherNo, voucher_type, voucher_date, narration || '', totalDebit, userId || null]
      );
      voucherId = res.insertId;
      break;
    } catch (err) {
      if (!(err && err.code === 'ER_DUP_ENTRY')) throw err;
    }
  }
  if (!voucherId) throw new Error('Could not allocate a unique voucher number.');
  for (const item of items) {
    const [accounts] = await conn.query(
      'SELECT account_type FROM finance_account WHERE account_id = ? AND company_id = ? LIMIT 1',
      [item.account_id, companyId]
    );
    if (!accounts.length) throw new Error(`Account #${item.account_id} not found.`);
    await conn.query(
      `INSERT INTO finance_voucher_item
        (company_id, voucher_id, account_id, debit_amount, credit_amount, description)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [companyId, voucherId, item.account_id, num(item.debit_amount), num(item.credit_amount), item.description || '']
    );
    await conn.query(
      'UPDATE finance_account SET current_balance = current_balance + ? WHERE account_id = ? AND company_id = ?',
      [balanceDelta(accounts[0].account_type, num(item.debit_amount), num(item.credit_amount)), item.account_id, companyId]
    );
  }
  return { voucherId, voucherNo };
}

async function accountIdByCode(conn, companyId, code) {
  const [rows] = await conn.query(
    'SELECT account_id FROM finance_account WHERE company_id = ? AND account_code = ? LIMIT 1',
    [companyId, code]
  );
  if (!rows.length) throw new Error(`Default account ${code} is missing.`);
  return rows[0].account_id;
}

exports.getPayments = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const [rows] = await db.query(
      `SELECT p.*, b.bill_no, i.invoice_no, ba.bank_name, ba.account_ref
       FROM finance_payment p
       LEFT JOIN finance_bill b ON p.bill_id = b.bill_id
       LEFT JOIN finance_invoice i ON p.invoice_id = i.invoice_id
       JOIN finance_bank_account ba ON p.bank_account_id = ba.bank_account_id
       WHERE p.company_id = ?
       ORDER BY p.pay_date DESC, p.payment_id DESC LIMIT 200`,
      [companyId]
    );
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getPayments');
  }
};

exports.createPayment = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const { bill_id, invoice_id, bank_account_id, pay_date, amount, mode, reference_no } = req.body || {};
    if (!bank_account_id || !pay_date || num(amount) <= 0 || (!bill_id && !invoice_id) || (bill_id && invoice_id)) {
      return res.status(400).json({
        success: false,
        message: 'A bank account, date, positive amount and exactly one bill or invoice are required.'
      });
    }
    await conn.beginTransaction();

    let counterpartCode;
    let voucherType;
    let description;
    let table;
    let idColumn;
    let docId;
    if (bill_id) {
      const [bills] = await conn.query(
        'SELECT * FROM finance_bill WHERE bill_id = ? AND company_id = ?',
        [bill_id, companyId]
      );
      if (!bills.length) throw new Error('Bill not found.');
      if (bills[0].status !== 'APPROVED') throw new Error('Only approved bills can be paid.');
      counterpartCode = '2001'; // Accounts Payable
      voucherType = 'Payment';
      description = `Payment against bill ${bills[0].bill_no}`;
      table = 'finance_bill';
      idColumn = 'bill_id';
      docId = bill_id;
    } else {
      const [invoices] = await conn.query(
        'SELECT * FROM finance_invoice WHERE invoice_id = ? AND company_id = ?',
        [invoice_id, companyId]
      );
      if (!invoices.length) throw new Error('Invoice not found.');
      if (invoices[0].status !== 'ISSUED') throw new Error('Only issued invoices can receive payment.');
      counterpartCode = '1100'; // Accounts Receivable
      voucherType = 'Receipt';
      description = `Receipt against invoice ${invoices[0].invoice_no}`;
      table = 'finance_invoice';
      idColumn = 'invoice_id';
      docId = invoice_id;
    }

    const [paidRows] = await conn.query(
      `SELECT COALESCE(SUM(amount), 0) AS paid FROM finance_payment WHERE company_id = ? AND ${idColumn} = ?`,
      [companyId, docId]
    );
    const [docRows] = await conn.query(
      `SELECT total_amount FROM ${table} WHERE ${idColumn} = ? AND company_id = ?`,
      [docId, companyId]
    );
    const outstanding = num(docRows[0].total_amount) - num(paidRows[0].paid);
    const paymentAmount = num(amount);
    if (paymentAmount > outstanding + 0.01) {
      throw new Error(`Amount exceeds outstanding balance of ₹${outstanding.toFixed(2)}.`);
    }

    const [banks] = await conn.query(
      'SELECT * FROM finance_bank_account WHERE bank_account_id = ? AND company_id = ? AND is_active = 1',
      [bank_account_id, companyId]
    );
    if (!banks.length) throw new Error('Bank account not found.');

    const payableId = await accountIdByCode(conn, companyId, counterpartCode);
    const bankLedgerId = await accountIdByCode(
      conn,
      companyId,
      (mode || 'NEFT') === 'Cash' ? '1001' : '1002'
    );
    const isPayment = Boolean(bill_id);
    const voucher = await postVoucher(conn, companyId, {
      voucher_type: voucherType,
      voucher_date: pay_date,
      narration: description,
      userId: req.user.userId,
      items: isPayment
        ? [
            { account_id: payableId, debit_amount: paymentAmount, credit_amount: 0, description },
            { account_id: bankLedgerId, debit_amount: 0, credit_amount: paymentAmount, description }
          ]
        : [
            { account_id: bankLedgerId, debit_amount: paymentAmount, credit_amount: 0, description },
            { account_id: payableId, debit_amount: 0, credit_amount: paymentAmount, description }
          ]
    });

    await conn.query(
      `INSERT INTO finance_payment
        (company_id, bill_id, invoice_id, bank_account_id, pay_date, amount, mode, reference_no, voucher_id, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        companyId, bill_id || null, invoice_id || null, bank_account_id, pay_date, paymentAmount,
        mode || 'NEFT', reference_no || null, voucher.voucherId, req.user.userId || null
      ]
    );
    await conn.query(
      'UPDATE finance_bank_account SET current_balance = current_balance + ? WHERE bank_account_id = ?',
      [isPayment ? -paymentAmount : paymentAmount, bank_account_id]
    );
    if (Math.abs(outstanding - paymentAmount) <= 0.01) {
      await conn.query(
        `UPDATE ${table} SET status = 'PAID' WHERE ${idColumn} = ? AND company_id = ?`,
        [docId, companyId]
      );
    }
    await writeAudit(conn, companyId, {
      entity: 'PAYMENT',
      entityId: docId,
      action: isPayment ? 'PAYMENT' : 'RECEIPT',
      summary: `${isPayment ? 'Payment' : 'Receipt'} of ₹${paymentAmount.toFixed(2)} posted as ${voucher.voucherNo}`,
      after: {
        bill_id: bill_id || null,
        invoice_id: invoice_id || null,
        bank_account_id,
        pay_date,
        amount: paymentAmount,
        mode: mode || 'NEFT',
        voucher_no: voucher.voucherNo
      },
      userId: req.user.userId
    });
    await conn.commit();
    return res.status(201).json({
      success: true,
      message: `${isPayment ? 'Payment' : 'Receipt'} recorded and posted as ${voucher.voucherNo}.`,
      payment_voucher: voucher.voucherNo
    });
  } catch (err) {
    try { await conn.rollback(); } catch (_) {}
    return fail(res, err, 'createPayment');
  } finally {
    conn.release();
  }
};

exports.getReceivables = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const [rows] = await db.query(
      `SELECT i.invoice_id, i.invoice_no, i.invoice_date, i.due_date, i.total_amount, i.status,
              DATEDIFF(CURDATE(), i.due_date) AS days_overdue,
              c.customer_name,
              COALESCE((SELECT SUM(p.amount) FROM finance_payment p WHERE p.invoice_id = i.invoice_id), 0) AS paid_amount,
              DATEDIFF(CURDATE(), i.invoice_date) AS age_days
       FROM finance_invoice i
       JOIN finance_customer c ON i.customer_id = c.customer_id
       WHERE i.company_id = ? AND i.status IN ('ISSUED', 'PAID')
       ORDER BY i.invoice_date ASC`,
      [companyId]
    );
    const buckets = { current: 0, days_30: 0, days_60: 0, days_90: 0, over_90: 0 };
    const data = rows.map((row) => {
      const due = num(row.total_amount) - num(row.paid_amount);
      const age = Number(row.age_days || 0);
      if (age <= 30) buckets.current += due;
      else if (age <= 60) buckets.days_30 += due;
      else if (age <= 90) buckets.days_60 += due;
      else if (age <= 120) buckets.days_90 += due;
      else buckets.over_90 += due;
      return { ...row, due_amount: due };
    });
    return res.status(200).json({ success: true, data, buckets });
  } catch (err) {
    return fail(res, err, 'getReceivables');
  }
};

// ------------------------------------------------------- Settings & audit trail

exports.getNumberSeries = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const rows = [];
    for (const [docType, prefix] of Object.entries(DEFAULT_SERIES)) {
      const [found] = await db.query(
        `SELECT doc_type, prefix, last_number,
                DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i') AS updated_at
         FROM finance_number_series WHERE company_id = ? AND doc_type = ?`,
        [companyId, docType]
      );
      rows.push(found[0] || { doc_type: docType, prefix, last_number: 0, updated_at: null });
    }
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getNumberSeries');
  }
};

exports.updateNumberSeries = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { docType } = req.params;
    const { prefix, last_number } = req.body || {};
    if (!Object.prototype.hasOwnProperty.call(DEFAULT_SERIES, docType)) {
      return res.status(400).json({ success: false, message: 'Unknown document type.' });
    }
    const cleanPrefix = String(prefix || '').trim().toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 12);
    if (!cleanPrefix) {
      return res.status(400).json({ success: false, message: 'A valid prefix is required.' });
    }
    const last = Math.max(0, Math.trunc(num(last_number)));
    await db.query(
      `INSERT INTO finance_number_series (company_id, doc_type, prefix, last_number, updated_by)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE prefix = VALUES(prefix), last_number = VALUES(last_number),
                              updated_by = VALUES(updated_by)`,
      [companyId, docType, cleanPrefix, last, req.user.userId || null]
    );
    await writeAudit(null, companyId, {
      entity: 'NUMBER_SERIES',
      entityId: null,
      action: 'UPDATE',
      summary: `${docType} series set to ${cleanPrefix} starting after ${last}`,
      after: { docType, prefix: cleanPrefix, last_number: last },
      userId: req.user.userId
    });
    return res.status(200).json({ success: true, message: 'Number series saved.' });
  } catch (err) {
    return fail(res, err, 'updateNumberSeries');
  }
};

exports.getAuditLog = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const params = [companyId];
    let sql =
      `SELECT a.log_id, a.entity, a.entity_id, a.action, a.summary,
              DATE_FORMAT(a.created_at, '%Y-%m-%d %H:%i') AS created_at,
              u.email AS created_by_email
       FROM finance_audit_log a
       LEFT JOIN USER u ON a.created_by = u.user_id
       WHERE a.company_id = ?`;
    if (req.query.entity) {
      sql += ' AND a.entity = ?';
      params.push(String(req.query.entity).toUpperCase());
    }
    if (req.query.action) {
      sql += ' AND a.action = ?';
      params.push(String(req.query.action).toUpperCase());
    }
    const filter = dateFilter('a.created_at', req);
    sql += filter.clause;
    params.push(...filter.values);
    const limit = Math.min(200, Math.max(1, num(req.query.limit) || 50));
    sql += ' ORDER BY a.log_id DESC LIMIT ?';
    params.push(limit);
    const [rows] = await db.query(sql, params);
    return res.status(200).json({ success: true, data: rows });
  } catch (err) {
    return fail(res, err, 'getAuditLog');
  }
};
// ---------------------------------------------------------------- Simple Bank & Expenses

async function ensureFinanceAttachmentTable() {
  await db.query(
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
  );
}

// 1. Fetch Cash/Bank accounts, Expense categories, Capital/Income sources, and recent transactions
exports.getBankAndExpenses = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await seedDefaultAccountsIfEmpty(companyId);
    await ensureFinanceAttachmentTable();

    const [bankAccounts] = await db.query(
      `SELECT account_id, account_code, account_name, current_balance
       FROM finance_account
       WHERE company_id = ? AND is_active = 1
         AND (sub_group = 'Cash & Bank' OR account_code IN ('1001', '1002'))
       ORDER BY account_code ASC`,
      [companyId]
    );

    const [expenseCategories] = await db.query(
      `SELECT account_id, account_code, account_name, current_balance
       FROM finance_account
       WHERE company_id = ? AND is_active = 1 AND account_type = 'Expense'
       ORDER BY account_code ASC`,
      [companyId]
    );

    const [depositSources] = await db.query(
      `SELECT account_id, account_code, account_name, account_type
       FROM finance_account
       WHERE company_id = ? AND is_active = 1 AND account_type IN ('Equity', 'Income')
       ORDER BY account_code ASC`,
      [companyId]
    );

    const [expenses] = await db.query(
      `SELECT v.voucher_id, v.voucher_no, v.voucher_type,
              DATE_FORMAT(v.voucher_date, '%Y-%m-%d') AS expense_date,
              v.narration AS title, v.total_amount AS amount, v.status,
              v.cancel_reason,
              DATE_FORMAT(v.cancelled_at, '%Y-%m-%d %H:%i') AS cancelled_at,
              COALESCE(emp.full_name, usr.email) AS cancelled_by_name,
              att.file_name AS attachment_name,
              att.mime_type AS attachment_mime,
              MAX(CASE WHEN vi.debit_amount > 0 THEN a.account_name END) AS debit_account_name,
              MAX(CASE WHEN vi.credit_amount > 0 THEN a.account_name END) AS credit_account_name
       FROM finance_voucher v
       JOIN finance_voucher_item vi ON vi.voucher_id = v.voucher_id
       JOIN finance_account a ON a.account_id = vi.account_id
       LEFT JOIN finance_voucher_attachment att ON att.voucher_id = v.voucher_id
       LEFT JOIN USER usr ON usr.user_id = v.cancelled_by
       LEFT JOIN EMPLOYEE emp ON emp.user_id = v.cancelled_by AND emp.company_id = v.company_id
       WHERE v.company_id = ? AND v.voucher_type IN ('Payment', 'Receipt', 'Contra')
       GROUP BY v.voucher_id, v.voucher_no, v.voucher_type, v.voucher_date, v.narration,
                v.total_amount, v.status, v.cancel_reason, v.cancelled_at,
                emp.full_name, usr.email, att.file_name, att.mime_type
       ORDER BY v.voucher_date DESC, v.voucher_id DESC
       LIMIT 100`,
      [companyId]
    );

    return res.status(200).json({
      success: true,
      bankAccounts,
      expenseCategories,
      depositSources,
      expenses
    });
  } catch (err) {
    return fail(res, err, 'getBankAndExpenses');
  }
};

async function ensureActiveFinancialYear(companyId, cleanDate) {
  let fy = await activeFinancialYear(companyId, cleanDate);
  if (!fy) {
    const yearNum = parseInt(cleanDate.slice(0, 4), 10);
    const fyStartYear = cleanDate.slice(5, 10) < '04-01' ? yearNum - 1 : yearNum;
    const fyStart = `${fyStartYear}-04-01`;
    const fyEnd = `${fyStartYear + 1}-03-31`;
    await db.query(
      `INSERT IGNORE INTO finance_financial_year (company_id, fy_name, start_date, end_date, is_active, is_closed)
       VALUES (?, ?, ?, ?, 1, 0)`,
      [companyId, `FY ${fyStartYear}-${fyStartYear + 1}`, fyStart, fyEnd]
    );
    fy = await activeFinancialYear(companyId, cleanDate);
  }
  return fy;
}

// 2. Save a simple expense (automatically deducts from Cash/Bank)
exports.createQuickExpense = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const {
      expense_account_id,
      paid_from_account_id,
      amount,
      expense_date,
      title
    } = req.body || {};

    const cleanAmount = num(amount);
    const cleanDate = expense_date || new Date().toISOString().slice(0, 10);
    const cleanTitle = String(title || '').trim();

    if (!expense_account_id || !paid_from_account_id || cleanAmount <= 0 || !cleanTitle) {
      return res.status(400).json({
        success: false,
        message: 'Title, Category, Paid From, and a valid Amount (> 0) are required.'
      });
    }

    const fy = await ensureActiveFinancialYear(companyId, cleanDate);
    if (!fy) {
      return res.status(400).json({
        success: false,
        message: 'No active Financial Year is open for this date.'
      });
    }

    await conn.beginTransaction();

    // Post balanced double-entry voucher: Expense Debit (+), Bank/Cash Credit (-)
    const { voucherId, voucherNo } = await postVoucher(conn, companyId, {
      voucher_type: 'Payment',
      voucher_date: cleanDate,
      narration: cleanTitle,
      userId: req.user.userId,
      items: [
        { account_id: expense_account_id, debit_amount: cleanAmount, credit_amount: 0, description: cleanTitle },
        { account_id: paid_from_account_id, debit_amount: 0, credit_amount: cleanAmount, description: cleanTitle }
      ]
    });

    await writeAudit(conn, companyId, {
      entity: 'QUICK_EXPENSE',
      entityId: voucherId,
      action: 'CREATE',
      summary: `Expense "${cleanTitle}" of ${cleanAmount} recorded (${voucherNo})`,
      after: { voucherNo, title: cleanTitle, amount: cleanAmount, expense_date: cleanDate },
      userId: req.user.userId
    });

    await conn.commit();
    return res.status(201).json({
      success: true,
      message: `Expense ${voucherNo} saved!`,
      voucher_id: voucherId,
      voucher_no: voucherNo
    });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'createQuickExpense');
  } finally {
    conn.release();
  }
};

// 3. Add money / opening balance / deposit to Cash or Bank
exports.createQuickDeposit = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const {
      to_account_id,
      source_account_id,
      amount,
      deposit_date,
      title
    } = req.body || {};

    const cleanAmount = num(amount);
    const cleanDate = deposit_date || new Date().toISOString().slice(0, 10);
    const cleanTitle = String(title || 'Cash / Bank Deposit').trim();

    if (!to_account_id || cleanAmount <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Target Cash/Bank account and a valid Amount (> 0) are required.'
      });
    }

    const fy = await ensureActiveFinancialYear(companyId, cleanDate);
    if (!fy) {
      return res.status(400).json({
        success: false,
        message: 'No active Financial Year is open for this date.'
      });
    }

    await conn.beginTransaction();
    const creditAccountId = source_account_id || await accountIdByCode(conn, companyId, '3001');

    const { voucherId, voucherNo } = await postVoucher(conn, companyId, {
      voucher_type: 'Receipt',
      voucher_date: cleanDate,
      narration: cleanTitle,
      userId: req.user.userId,
      items: [
        { account_id: to_account_id, debit_amount: cleanAmount, credit_amount: 0, description: cleanTitle },
        { account_id: creditAccountId, debit_amount: 0, credit_amount: cleanAmount, description: cleanTitle }
      ]
    });

    await writeAudit(conn, companyId, {
      entity: 'QUICK_DEPOSIT',
      entityId: voucherId,
      action: 'CREATE',
      summary: `Deposit "${cleanTitle}" of ${cleanAmount} recorded (${voucherNo})`,
      after: { voucherNo, title: cleanTitle, amount: cleanAmount, deposit_date: cleanDate },
      userId: req.user.userId
    });

    await conn.commit();
    return res.status(201).json({
      success: true,
      message: `Deposit ${voucherNo} saved!`,
      voucher_id: voucherId,
      voucher_no: voucherNo
    });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'createQuickDeposit');
  } finally {
    conn.release();
  }
};

// 4. Transfer funds between Cash and Bank accounts (Contra)
exports.createQuickTransfer = async (req, res) => {
  const companyId = companyIdOf(req);
  const conn = await db.getConnection();
  try {
    const {
      from_account_id,
      to_account_id,
      amount,
      transfer_date,
      title
    } = req.body || {};

    const cleanAmount = num(amount);
    const cleanDate = transfer_date || new Date().toISOString().slice(0, 10);
    const cleanTitle = String(title || 'Cash / Bank Transfer').trim();

    if (!from_account_id || !to_account_id || cleanAmount <= 0) {
      return res.status(400).json({
        success: false,
        message: 'From Account, To Account, and a valid Amount (> 0) are required.'
      });
    }
    if (String(from_account_id) === String(to_account_id)) {
      return res.status(400).json({
        success: false,
        message: 'From and To accounts must be different.'
      });
    }

    const fy = await ensureActiveFinancialYear(companyId, cleanDate);
    if (!fy) {
      return res.status(400).json({
        success: false,
        message: 'No active Financial Year is open for this date.'
      });
    }

    await conn.beginTransaction();

    const { voucherId, voucherNo } = await postVoucher(conn, companyId, {
      voucher_type: 'Contra',
      voucher_date: cleanDate,
      narration: cleanTitle,
      userId: req.user.userId,
      items: [
        { account_id: to_account_id, debit_amount: cleanAmount, credit_amount: 0, description: cleanTitle },
        { account_id: from_account_id, debit_amount: 0, credit_amount: cleanAmount, description: cleanTitle }
      ]
    });

    await writeAudit(conn, companyId, {
      entity: 'QUICK_TRANSFER',
      entityId: voucherId,
      action: 'CREATE',
      summary: `Transfer "${cleanTitle}" of ${cleanAmount} recorded (${voucherNo})`,
      after: { voucherNo, title: cleanTitle, amount: cleanAmount, transfer_date: cleanDate },
      userId: req.user.userId
    });

    await conn.commit();
    return res.status(201).json({
      success: true,
      message: `Transfer ${voucherNo} completed!`,
      voucher_id: voucherId,
      voucher_no: voucherNo
    });
  } catch (err) {
    await conn.rollback();
    return fail(res, err, 'createQuickTransfer');
  } finally {
    conn.release();
  }
};

// 5. Add a new Bank Account directly from Bank & Expenses
exports.createQuickBankAccount = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { account_name, opening_balance } = req.body || {};
    const cleanName = String(account_name || '').trim();
    const opening = num(opening_balance);

    if (!cleanName) {
      return res.status(400).json({
        success: false,
        message: 'Bank account name is required.'
      });
    }

    await seedDefaultAccountsIfEmpty(companyId);

    const [existingCodes] = await db.query(
      `SELECT account_code FROM finance_account
       WHERE company_id = ? AND account_code REGEXP '^10[0-9]{2}$'
       ORDER BY account_code DESC LIMIT 1`,
      [companyId]
    );
    const lastCode = existingCodes.length ? parseInt(existingCodes[0].account_code, 10) : 1002;
    const nextCode = String(Math.max(1002, lastCode) + 1);

    const [result] = await db.query(
      `INSERT INTO finance_account
        (company_id, account_code, account_name, account_type, sub_group, opening_balance, current_balance)
       VALUES (?, ?, ?, 'Asset', 'Cash & Bank', ?, ?)`,
      [companyId, nextCode, cleanName, opening, opening]
    );

    await writeAudit(null, companyId, {
      entity: 'ACCOUNT',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Bank account ${cleanName} (${nextCode}) created`,
      after: { account_code: nextCode, account_name: cleanName, opening_balance: opening },
      userId: req.user.userId
    });

    return res.status(201).json({
      success: true,
      message: 'Bank account added!',
      account_id: result.insertId,
      account_code: nextCode
    });
  } catch (err) {
    return fail(res, err, 'createQuickBankAccount');
  }
};

// 6. Add a new Expense Category
exports.createQuickExpenseCategory = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const cleanName = String((req.body && req.body.account_name) || '').trim();
    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Category name is required.' });
    }
    await seedDefaultAccountsIfEmpty(companyId);

    const [dup] = await db.query(
      `SELECT account_id FROM finance_account
       WHERE company_id = ? AND account_type = 'Expense' AND LOWER(account_name) = LOWER(?) LIMIT 1`,
      [companyId, cleanName]
    );
    if (dup.length) {
      return res.status(409).json({ success: false, message: 'This expense category already exists.' });
    }

    const [existingCodes] = await db.query(
      `SELECT account_code FROM finance_account
       WHERE company_id = ? AND account_code REGEXP '^50[0-9]{2}$'
       ORDER BY account_code DESC LIMIT 1`,
      [companyId]
    );
    const lastCode = existingCodes.length ? parseInt(existingCodes[0].account_code, 10) : 5003;
    const nextCode = String(Math.max(5003, lastCode) + 1);

    const [result] = await db.query(
      `INSERT INTO finance_account
        (company_id, account_code, account_name, account_type, sub_group, opening_balance, current_balance)
       VALUES (?, ?, ?, 'Expense', 'Operating Expense', 0, 0)`,
      [companyId, nextCode, cleanName]
    );

    await writeAudit(null, companyId, {
      entity: 'ACCOUNT',
      entityId: result.insertId,
      action: 'CREATE',
      summary: `Expense category ${cleanName} (${nextCode}) created`,
      after: { account_code: nextCode, account_name: cleanName },
      userId: req.user.userId
    });

    return res.status(201).json({
      success: true,
      message: 'Expense category added!',
      account_id: result.insertId,
      account_code: nextCode
    });
  } catch (err) {
    return fail(res, err, 'createQuickExpenseCategory');
  }
};

// 7. Edit an existing Expense Category name
exports.updateQuickExpenseCategory = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const { id } = req.params;
    const cleanName = String((req.body && req.body.account_name) || '').trim();
    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Category name is required.' });
    }
    const [result] = await db.query(
      `UPDATE finance_account SET account_name = ?
       WHERE account_id = ? AND company_id = ? AND account_type = 'Expense'`,
      [cleanName, id, companyId]
    );
    if (!result.affectedRows) {
      return res.status(404).json({ success: false, message: 'Expense category not found.' });
    }
    return res.status(200).json({ success: true, message: 'Expense category updated!' });
  } catch (err) {
    return fail(res, err, 'updateQuickExpenseCategory');
  }
};

// 8. Upload a bill photo or PDF for a voucher
exports.uploadVoucherAttachment = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureFinanceAttachmentTable();
    const voucherId = parseInt(req.params.id, 10);
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No bill file uploaded.' });
    }
    const [vouchers] = await db.query(
      'SELECT voucher_id FROM finance_voucher WHERE voucher_id = ? AND company_id = ? LIMIT 1',
      [voucherId, companyId]
    );
    if (!vouchers.length) {
      return res.status(404).json({ success: false, message: 'Voucher not found.' });
    }

    await db.query(
      `INSERT INTO finance_voucher_attachment
        (company_id, voucher_id, file_name, mime_type, file_size, file_data, uploaded_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         file_name = VALUES(file_name),
         mime_type = VALUES(mime_type),
         file_size = VALUES(file_size),
         file_data = VALUES(file_data),
         uploaded_by = VALUES(uploaded_by)`,
      [
        companyId,
        voucherId,
        req.file.originalname,
        req.file.mimetype || 'application/octet-stream',
        req.file.size || req.file.buffer.length,
        req.file.buffer,
        req.user.userId || null
      ]
    );

    return res.status(201).json({ success: true, message: 'Bill attached!' });
  } catch (err) {
    return fail(res, err, 'uploadVoucherAttachment');
  }
};

// 9. Download / view a voucher's attached bill
exports.downloadVoucherAttachment = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    await ensureFinanceAttachmentTable();
    const voucherId = parseInt(req.params.id, 10);
    const [rows] = await db.query(
      `SELECT file_name, mime_type, file_data
       FROM finance_voucher_attachment
       WHERE voucher_id = ? AND company_id = ? LIMIT 1`,
      [voucherId, companyId]
    );
    if (!rows.length) {
      return res.status(404).json({ success: false, message: 'No bill attached to this entry.' });
    }
    const file = rows[0];
    res.setHeader('Content-Type', file.mime_type || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(file.file_name)}"`);
    return res.send(file.file_data);
  } catch (err) {
    return fail(res, err, 'downloadVoucherAttachment');
  }
};

async function computeQuickReports(companyId, query) {
  const today = new Date().toISOString().slice(0, 10);
  const firstOfMonth = `${today.slice(0, 7)}-01`;
  const from = /^\d{4}-\d{2}-\d{2}$/.test(String(query.from || '')) ? query.from : firstOfMonth;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(String(query.to || '')) ? query.to : today;
  const accountId = query.account_id ? parseInt(query.account_id, 10) : null;

  const bookParams = [companyId, from, to];
  let accountFilter = '';
  if (accountId && !Number.isNaN(accountId)) {
    accountFilter = ' AND a.account_id = ?';
    bookParams.push(accountId);
  }

  const [cashBankBook] = await db.query(
    `SELECT DATE_FORMAT(v.voucher_date, '%Y-%m-%d') AS entry_date,
            v.voucher_no, v.voucher_type, v.narration AS title,
            a.account_name,
            vi.debit_amount AS money_in,
            vi.credit_amount AS money_out
     FROM finance_voucher_item vi
     JOIN finance_voucher v ON v.voucher_id = vi.voucher_id
     JOIN finance_account a ON a.account_id = vi.account_id
     WHERE v.company_id = ? AND v.status = 'POSTED'
       AND (a.sub_group = 'Cash & Bank' OR a.account_code IN ('1001', '1002'))
       AND v.voucher_date BETWEEN ? AND ?${accountFilter}
     ORDER BY v.voucher_date ASC, v.voucher_id ASC`,
    bookParams
  );

  let totalIn = 0;
  let totalOut = 0;
  for (const row of cashBankBook) {
    totalIn += num(row.money_in);
    totalOut += num(row.money_out);
  }

  const [categorySummary] = await db.query(
    `SELECT a.account_name AS category_name,
            COUNT(DISTINCT v.voucher_id) AS entries_count,
            SUM(vi.debit_amount - vi.credit_amount) AS total_amount
     FROM finance_voucher_item vi
     JOIN finance_voucher v ON v.voucher_id = vi.voucher_id
     JOIN finance_account a ON a.account_id = vi.account_id
     WHERE v.company_id = ? AND v.status = 'POSTED'
       AND a.account_type = 'Expense'
       AND v.voucher_date BETWEEN ? AND ?
     GROUP BY a.account_id, a.account_name
     HAVING total_amount > 0
     ORDER BY total_amount DESC`,
    [companyId, from, to]
  );

  const [monthSummary] = await db.query(
    `SELECT DATE_FORMAT(v.voucher_date, '%Y-%m') AS month_key,
            COUNT(DISTINCT v.voucher_id) AS entries_count,
            SUM(vi.debit_amount - vi.credit_amount) AS total_amount
     FROM finance_voucher_item vi
     JOIN finance_voucher v ON v.voucher_id = vi.voucher_id
     JOIN finance_account a ON a.account_id = vi.account_id
     WHERE v.company_id = ? AND v.status = 'POSTED'
       AND a.account_type = 'Expense'
       AND v.voucher_date BETWEEN ? AND ?
     GROUP BY month_key
     HAVING total_amount > 0
     ORDER BY month_key DESC`,
    [companyId, from, to]
  );

  return {
    from,
    to,
    totals: {
      totalIn,
      totalOut,
      netChange: totalIn - totalOut,
      totalExpense: categorySummary.reduce((s, r) => s + num(r.total_amount), 0)
    },
    cashBankBook,
    categorySummary,
    monthSummary
  };
}

// 10. Quick Reports JSON (Cash/Bank Book, Category-wise, Month-wise)
exports.getQuickReports = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const report = await computeQuickReports(companyId, req.query || {});
    return res.status(200).json({ success: true, ...report });
  } catch (err) {
    return fail(res, err, 'getQuickReports');
  }
};

// 11. Export Quick Reports as Excel (.xlsx)
exports.exportQuickReportsExcel = async (req, res) => {
  const companyId = companyIdOf(req);
  try {
    const report = await computeQuickReports(companyId, req.query || {});
    const wb = XLSX.utils.book_new();

    const bookRows = report.cashBankBook.map((r) => ({
      Date: r.entry_date,
      'Voucher No': r.voucher_no,
      Type: r.voucher_type,
      Title: r.title,
      Account: r.account_name,
      'Money In (INR)': num(r.money_in),
      'Money Out (INR)': num(r.money_out)
    }));
    XLSX.utils.book_append_sheet(
      wb,
      XLSX.utils.json_to_sheet(bookRows.length ? bookRows : [{ Message: 'No entries in selected range' }]),
      'Cash & Bank Book'
    );

    const catRows = report.categorySummary.map((r) => ({
      Category: r.category_name,
      Entries: Number(r.entries_count || 0),
      'Total Expense (INR)': num(r.total_amount)
    }));
    XLSX.utils.book_append_sheet(
      wb,
      XLSX.utils.json_to_sheet(catRows.length ? catRows : [{ Message: 'No expenses in selected range' }]),
      'Category-wise'
    );

    const monthRows = report.monthSummary.map((r) => ({
      Month: r.month_key,
      Entries: Number(r.entries_count || 0),
      'Total Expense (INR)': num(r.total_amount)
    }));
    XLSX.utils.book_append_sheet(
      wb,
      XLSX.utils.json_to_sheet(monthRows.length ? monthRows : [{ Message: 'No expenses in selected range' }]),
      'Month-wise'
    );

    const buffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="Finance_Report_${report.from}_to_${report.to}.xlsx"`
    );
    return res.send(buffer);
  } catch (err) {
    return fail(res, err, 'exportQuickReportsExcel');
  }
};

exports._shared = {
  companyIdOf,
  fail,
  seedDefaultAccountsIfEmpty,
  activeFinancialYear,
  ensureActiveFinancialYear,
  postVoucher,
  accountIdByCode,
  writeAudit
};
