const jwt = require('jsonwebtoken');
const db = require('../config/db');

/**
 * Resolves the target company_id from the incoming Express request.
 * Checks in priority order:
 * 1. Header: 'x-company-id'
 * 2. Query param: 'company_id'
 * 3. Request body: 'company_id'
 * 4. Authorization Bearer JWT Token ('companyId')
 * 5. req.user object (if set by auth middleware)
 */
function resolveCompanyId(req) {
  // 1. Header
  if (req.headers && req.headers['x-company-id']) {
    const cid = parseInt(req.headers['x-company-id'], 10);
    if (!isNaN(cid) && cid > 0) return cid;
  }

  // 2. Query
  if (req.query && req.query.company_id) {
    const cid = parseInt(req.query.company_id, 10);
    if (!isNaN(cid) && cid > 0) return cid;
  }

  // 3. Body
  if (req.body && req.body.company_id) {
    const cid = parseInt(req.body.company_id, 10);
    if (!isNaN(cid) && cid > 0) return cid;
  }

  // 4. JWT Authorization Header
  if (req.headers && req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
    try {
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
      if (decoded && (decoded.companyId || decoded.company_id)) {
        const cid = parseInt(decoded.companyId || decoded.company_id, 10);
        if (!isNaN(cid) && cid > 0) return cid;
      }
    } catch (_) {}
  }

  // 5. req.user
  if (req.user && (req.user.companyId || req.user.company_id)) {
    const cid = parseInt(req.user.companyId || req.user.company_id, 10);
    if (!isNaN(cid) && cid > 0) return cid;
  }

  return null;
}

/**
 * Resolves requester employeeId, userId, role, and isSuperAdmin flag.
 */
async function resolveRequesterInfo(req) {
  let employeeId = null;
  let userId = null;
  let role = null;

  // 1. req.user
  if (req.user) {
    employeeId = req.user.employeeId || req.user.employee_id || null;
    userId = req.user.id || req.user.userId || null;
    role = req.user.role || req.user.role_name || null;
  }

  // 2. JWT Authorization Token
  if (req.headers && req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
    try {
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
      if (decoded) {
        if (!employeeId && (decoded.employeeId || decoded.employee_id)) {
          employeeId = parseInt(decoded.employeeId || decoded.employee_id, 10);
        }
        if (!userId && (decoded.userId || decoded.user_id)) {
          userId = parseInt(decoded.userId || decoded.user_id, 10);
        }
        if (!role && decoded.role) {
          role = decoded.role;
        }
      }
    } catch (_) {}
  }

  // 3. Headers
  if (!employeeId && req.headers && req.headers['x-employee-id']) {
    const eid = parseInt(req.headers['x-employee-id'], 10);
    if (!isNaN(eid)) employeeId = eid;
  }
  if (!userId && req.headers && req.headers['x-user-id']) {
    const uid = parseInt(req.headers['x-user-id'], 10);
    if (!isNaN(uid)) userId = uid;
  }
  if (!role && req.headers && req.headers['x-role']) {
    role = req.headers['x-role'];
  }

  // 4. Body / Query
  const rawEmpId = req.body?.employee_id || req.query?.employee_id;
  if (!employeeId && rawEmpId) {
    const eid = parseInt(rawEmpId, 10);
    if (!isNaN(eid)) employeeId = eid;
  }
  const rawUserId = req.body?.user_id || req.query?.user_id;
  if (!userId && rawUserId) {
    const uid = parseInt(rawUserId, 10);
    if (!isNaN(uid)) userId = uid;
  }
  if (!role && (req.body?.role || req.query?.role)) {
    role = req.body?.role || req.query?.role;
  }

  // 5. Query Database if userId present but missing employeeId or role
  if (userId && (!employeeId || !role)) {
    try {
      const [uRows] = await db.query(
        `SELECT u.user_id, r.name as role_name, e.employee_id, e.role as emp_role
         FROM USER u
         LEFT JOIN ROLE r ON u.role_id = r.role_id
         LEFT JOIN EMPLOYEE e ON u.user_id = e.user_id
         WHERE u.user_id = ? LIMIT 1`,
        [userId]
      );
      if (uRows.length > 0) {
        if (!employeeId && uRows[0].employee_id) employeeId = uRows[0].employee_id;
        if (!role) role = uRows[0].role_name || uRows[0].emp_role;
      }
    } catch (_) {}
  } else if (employeeId && !role) {
    try {
      const [eRows] = await db.query('SELECT role, user_id FROM EMPLOYEE WHERE employee_id = ? LIMIT 1', [employeeId]);
      if (eRows.length > 0) {
        role = eRows[0].role;
        if (!userId && eRows[0].user_id) userId = eRows[0].user_id;
      }
    } catch (_) {}
  }

  const normalizedRole = String(role || '').trim().toLowerCase();
  const isSuperAdmin = normalizedRole.includes('admin');

  return {
    employeeId: employeeId ? parseInt(employeeId, 10) : null,
    userId: userId ? parseInt(userId, 10) : null,
    role,
    isSuperAdmin
  };
}

module.exports = { resolveCompanyId, resolveRequesterInfo };
