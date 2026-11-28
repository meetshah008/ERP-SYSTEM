const jwt = require('jsonwebtoken');
const db = require('../config/db');
const { getDefaultPermissions } = require('./permissions');

/**
 * Strict JWT authentication. Unlike tenant.js helpers, this never trusts
 * client-supplied headers, query params or the request body for identity.
 */
function authenticate(req, res, next) {
  const header = req.headers && req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Authentication required.' });
  }
  try {
    const decoded = jwt.verify(header.slice(7), process.env.JWT_SECRET || 'secret');
    const companyId = parseInt(decoded.companyId || decoded.company_id, 10);
    if (!companyId || companyId <= 0) {
      return res.status(403).json({ success: false, message: 'Invalid session: company context missing.' });
    }
    req.user = {
      userId: parseInt(decoded.userId || decoded.user_id, 10) || null,
      employeeId: parseInt(decoded.employeeId || decoded.employee_id, 10) || null,
      companyId,
      role: decoded.role || decoded.role_name || ''
    };
    return next();
  } catch (err) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token.' });
  }
}

/** Map a role name to the module used by the permission presets. */
function managerModuleFromRole(role) {
  const r = String(role || '').toLowerCase();
  if (/fin|acc|bill|pay/.test(r)) return 'finance';
  if (/hr|human|personnel/.test(r)) return 'hr';
  if (/it|tech|eng|project|soft/.test(r)) return 'projects';
  if (/invent|store|ware|stock/.test(r)) return 'inventory';
  if (/manuf|prod|plant|operat/.test(r)) return 'manufacturing';
  return '';
}

/** Effective permissions = preset defaults + explicit employee overrides. */
async function effectivePermissions(req) {
  const defaults = getDefaultPermissions(req.user.role, '', managerModuleFromRole(req.user.role));
  if (!req.user.employeeId) return defaults;
  try {
    const [rows] = await db.query(
      'SELECT permission_key, is_granted FROM EMPLOYEE_PERMISSION WHERE employee_id = ?',
      [req.user.employeeId]
    );
    const overrides = {};
    for (const row of rows) overrides[row.permission_key] = Boolean(row.is_granted);
    return { ...defaults, ...overrides };
  } catch (_) {
    return defaults;
  }
}

/** Middleware factory: allow when ANY of the given keys is granted. */
function requirePermission(...keys) {
  return async (req, res, next) => {
    try {
      const perms = await effectivePermissions(req);
      if (!keys.some((key) => perms[key] === true)) {
        return res.status(403).json({ success: false, message: 'Access denied: insufficient permissions.' });
      }
      req.permissions = perms;
      return next();
    } catch (err) {
      return res.status(500).json({ success: false, message: 'Permission check failed.' });
    }
  };
}

module.exports = { authenticate, requirePermission, effectivePermissions, managerModuleFromRole };
