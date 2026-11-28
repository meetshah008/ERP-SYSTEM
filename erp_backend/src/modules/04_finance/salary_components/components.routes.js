const express = require('express');
const router = express.Router();
const { authenticate, requirePermission } = require('../../../utils/auth');
const components = require('./components.controller');

const canView = requirePermission('payroll_view', 'finance_view_reports', 'finance_manage_accounts');
const canManage = requirePermission('payroll_manage', 'finance_manage_accounts');

router.use(authenticate);

router.get('/', canView, components.getComponents);
router.post('/', canManage, components.saveComponent);
router.delete('/:id', canManage, components.deleteComponent);

module.exports = router;
