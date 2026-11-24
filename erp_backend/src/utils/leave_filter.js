/**
 * Shared date-window filter for leave lists.
 *
 * Mirrors the attendance filter pattern: month+year takes precedence, and
 * start_date/end_date can be used for a custom window. Dates are matched
 * against the leave start date, which is what admins scan when reviewing a
 * period.
 */
function buildLeaveDateFilter(query = {}) {
  let clause = '';
  const params = [];

  const month = parseInt(query.month, 10);
  const year = parseInt(query.year, 10);

  if (Number.isFinite(month) && month > 0 && Number.isFinite(year) && year > 0) {
    clause += ` AND MONTH(l.start_date) = ? AND YEAR(l.start_date) = ?`;
    params.push(month, year);
  } else if (Number.isFinite(year) && year > 0) {
    clause += ` AND YEAR(l.start_date) = ?`;
    params.push(year);
  }

  if (query.start_date && query.end_date) {
    clause += ` AND l.start_date BETWEEN ? AND ?`;
    params.push(query.start_date, query.end_date);
  }

  return { clause, params };
}

module.exports = { buildLeaveDateFilter };
