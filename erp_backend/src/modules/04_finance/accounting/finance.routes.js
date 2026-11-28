const express = require('express');
const router = express.Router();
const multer = require('multer');
const { authenticate, requirePermission } = require('../../../utils/auth');
const finance = require('./finance.controller');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }
});

const canView = requirePermission(
  'finance_view_reports',
  'finance_manage_accounts',
  'finance_create_voucher'
);
const canManageAccounts = requirePermission('finance_manage_accounts');
const canPostVoucher = requirePermission('finance_create_voucher');
const canCloseFY = requirePermission('finance_close_fy');

router.use(authenticate);

// Dashboard & reports
router.get('/dashboard', canView, finance.getDashboard);
router.get('/trial-balance', canView, finance.getTrialBalance);
router.get('/profit-loss', canView, finance.getProfitLoss);
router.get('/balance-sheet', canView, finance.getBalanceSheet);
router.get('/ledger', canView, finance.getGeneralLedger);

// Chart of accounts
router.get('/accounts', canView, finance.getAccounts);
router.post('/accounts', canManageAccounts, finance.createAccount);
router.put('/accounts/:id', canManageAccounts, finance.updateAccount);

// Financial years
router.get('/financial-years', canView, finance.getFinancialYears);
router.post('/financial-years', canCloseFY, finance.createFinancialYear);
router.post('/financial-years/:id/status', canCloseFY, finance.setFinancialYearStatus);

// Vouchers
router.get('/vouchers', canView, finance.getVouchers);
router.post('/vouchers', canPostVoucher, finance.createVoucher);
router.get('/vouchers/:id', canView, finance.getVoucherDetails);
router.post('/vouchers/:id/cancel', canPostVoucher, finance.cancelVoucher);

// Parties (vendors, customers, bank accounts)
router.get('/parties', canView, finance.getParties);
router.post('/parties/:kind', canManageAccounts, finance.createParty);
router.put('/parties/:kind/:id', canManageAccounts, finance.updateParty);

// Numbering series and automatic audit trail
router.get('/number-series', canView, finance.getNumberSeries);
router.put('/number-series/:docType', canManageAccounts, finance.updateNumberSeries);
router.get('/audit-log', canView, finance.getAuditLog);

// Payables with manual PO/GRN/bill 3-way match
router.get('/bills', canView, finance.getBills);
router.post('/bills', requirePermission('finance_manage_bills'), finance.createBill);
router.post('/bills/:id/approve', requirePermission('finance_manage_bills'), finance.approveBill);

// Receivables
router.get('/invoices', canView, finance.getInvoices);
router.post('/invoices', requirePermission('finance_manage_invoices'), finance.createInvoice);
router.get('/receivables', canView, finance.getReceivables);

// Payments & receipts (post balanced vouchers automatically)
router.get('/payments', canView, finance.getPayments);
router.post('/payments', requirePermission('finance_record_payment'), finance.createPayment);

// Simple Bank & Expenses
router.get('/quick-expenses', canView, finance.getBankAndExpenses);
router.post('/quick-expenses', canPostVoucher, finance.createQuickExpense);
router.post('/quick-deposit', canPostVoucher, finance.createQuickDeposit);
router.post('/quick-transfer', canPostVoucher, finance.createQuickTransfer);
router.post('/quick-bank-account', canManageAccounts, finance.createQuickBankAccount);
router.post('/quick-expense-categories', canPostVoucher, finance.createQuickExpenseCategory);
router.put('/quick-expense-categories/:id', canPostVoucher, finance.updateQuickExpenseCategory);
router.post('/vouchers/:id/attachment', canPostVoucher, upload.single('file'), finance.uploadVoucherAttachment);
router.get('/vouchers/:id/attachment', canView, finance.downloadVoucherAttachment);
router.get('/quick-reports', canView, finance.getQuickReports);
router.get('/quick-reports/export', canView, finance.exportQuickReportsExcel);

module.exports = router;
