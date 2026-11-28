const test = require('node:test');
const assert = require('node:assert/strict');
const { getDefaultPermissions } = require('../src/utils/permissions');

const financeKeys = [
  'finance_view_reports',
  'finance_manage_accounts',
  'finance_create_voucher',
  'finance_manage_bills',
  'finance_manage_invoices',
  'finance_record_payment',
  'finance_close_fy'
];

test('super admin has every finance permission', () => {
  const perms = getDefaultPermissions('Super Admin', '', '');
  for (const key of financeKeys) assert.equal(perms[key], true, key);
});

test('finance manager can maintain books but cannot close a year', () => {
  const perms = getDefaultPermissions('Finance Manager', '', 'finance');
  for (const key of financeKeys.filter((key) => key !== 'finance_close_fy')) {
    assert.equal(perms[key], true, key);
  }
  assert.equal(perms.finance_close_fy, false);
});

test('plain employee has no finance permissions', () => {
  const perms = getDefaultPermissions('Employee', '', '');
  for (const key of financeKeys) assert.equal(perms[key], false, key);
});

test('finance department derives finance module for a generic manager', () => {
  const perms = getDefaultPermissions('Module Manager', 'Accounts', '');
  assert.equal(perms.finance_view_reports, true);
  assert.equal(perms.hr_manage_staff, false);
});
