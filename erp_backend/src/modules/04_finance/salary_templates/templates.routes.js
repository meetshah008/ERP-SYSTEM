const express = require('express');
const router = express.Router();
const { authenticate, requirePermission } = require('../../../utils/auth');
const templates = require('./templates.controller');

const canView = requirePermission('payroll_view', 'finance_view_reports', 'finance_manage_accounts');
const canManage = requirePermission('payroll_manage', 'finance_manage_accounts');

router.use(authenticate);

router.get('/templates', canView, templates.getSalaryTemplates);
router.post('/templates', canManage, templates.saveSalaryTemplate);
router.delete('/templates/:id', canManage, templates.deleteSalaryTemplate);
router.post('/templates/apply', canManage, templates.applyTemplateToEmployee);
router.post('/templates/bulk-apply', canManage, templates.bulkApplyTemplate);

router.get('/structures', canView, templates.getSalaryStructures);
router.get('/structures/:employeeId/history', canView, templates.getEmployeeSalaryHistory);

module.exports = router;
