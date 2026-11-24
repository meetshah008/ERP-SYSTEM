/**
 * Shared, pure helpers for the task approval workflow.
 *
 * Statuses: TODO -> IN_PROGRESS -> REVIEW -> DONE.
 * When a task has reviewers, only an approved review may set DONE.
 */
const TASK_STATUSES = ['TODO', 'IN_PROGRESS', 'REVIEW', 'DONE'];

/** Accept ids, objects with employee_id, or a single value; return unique positive ids. */
function normalizeEmployeeIds(value) {
  const raw = Array.isArray(value)
    ? value
    : (value === undefined || value === null || value === '' ? [] : [value]);
  const ids = [];
  for (const item of raw) {
    const candidate = item && typeof item === 'object'
      ? (item.employee_id ?? item.employeeId ?? item.id)
      : item;
    const id = parseInt(candidate, 10);
    if (!Number.isNaN(id) && id > 0 && !ids.includes(id)) ids.push(id);
  }
  return ids;
}

/** Return a known uppercase status, or the supplied fallback. */
function normalizeStatus(status, fallback = 'TODO') {
  const value = String(status ?? '').trim().toUpperCase();
  return TASK_STATUSES.includes(value) ? value : fallback;
}

function hasReviewers(reviewerIds) {
  return normalizeEmployeeIds(reviewerIds).length > 0;
}

/**
 * Assignees may move a task between TODO / IN_PROGRESS / REVIEW.
 * DONE is only allowed when nobody is configured to review the task.
 */
function canAssigneeSetStatus(targetStatus, reviewerIds) {
  const status = normalizeStatus(targetStatus, null);
  if (!status) return false;
  if (status === 'DONE') return !hasReviewers(reviewerIds);
  return true;
}

/** Only a selected reviewer (or an admin) may approve a task waiting in REVIEW. */
function canApproveTask({ isSuperAdmin = false, employeeId = null, reviewerIds = [], currentStatus = null } = {}) {
  if (normalizeStatus(currentStatus) !== 'REVIEW') return false;
  const ids = normalizeEmployeeIds(reviewerIds);
  if (ids.length === 0) return false;
  if (isSuperAdmin) return true;
  const id = parseInt(employeeId, 10);
  return !Number.isNaN(id) && ids.includes(id);
}

/** A newly created task with reviewers starts in REVIEW for immediate approval. */
function initialTaskStatus(status, reviewerIds = []) {
  const requested = normalizeStatus(status, 'TODO');
  return hasReviewers(reviewerIds) ? 'REVIEW' : requested;
}

function nextAssigneeStatus(currentStatus, reviewerIds = []) {
  const status = normalizeStatus(currentStatus, 'TODO');
  if (status === 'TODO') return 'IN_PROGRESS';
  if (status === 'IN_PROGRESS') return hasReviewers(reviewerIds) ? 'REVIEW' : 'DONE';
  if (status === 'REVIEW') return 'REVIEW';
  return 'TODO';
}

module.exports = {
  TASK_STATUSES,
  normalizeEmployeeIds,
  normalizeStatus,
  hasReviewers,
  canAssigneeSetStatus,
  canApproveTask,
  initialTaskStatus,
  nextAssigneeStatus,
};
