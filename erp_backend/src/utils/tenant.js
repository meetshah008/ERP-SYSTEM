const jwt = require('jsonwebtoken');

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

module.exports = { resolveCompanyId };
