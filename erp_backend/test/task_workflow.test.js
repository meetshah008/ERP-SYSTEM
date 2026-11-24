const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeEmployeeIds,
  normalizeStatus,
  hasReviewers,
  canAssigneeSetStatus,
  canApproveTask,
  nextAssigneeStatus,
} = require('../src/utils/task_workflow');

test('normalizeEmployeeIds deduplicates ids from mixed input', () => {
  assert.deepEqual(normalizeEmployeeIds([3, '4', { employee_id: 3 }, null, 0]), [3, 4]);
  assert.deepEqual(normalizeEmployeeIds(null), []);
});

test('normalizeStatus accepts only known task statuses', () => {
  assert.equal(normalizeStatus(' review '), 'REVIEW');
  assert.equal(normalizeStatus('nonsense', 'TODO'), 'TODO');
});

test('DONE is blocked while reviewers are configured', () => {
  assert.equal(canAssigneeSetStatus('DONE', [7]), false);
  assert.equal(canAssigneeSetStatus('DONE', []), true);
  assert.equal(canAssigneeSetStatus('REVIEW', [7]), true);
  assert.equal(canAssigneeSetStatus('IMPOSSIBLE', []), false);
});

test('only a chosen reviewer or admin can approve from REVIEW', () => {
  assert.equal(canApproveTask({ employeeId: 7, reviewerIds: [7, 8], currentStatus: 'REVIEW' }), true);
  assert.equal(canApproveTask({ employeeId: 9, reviewerIds: [7, 8], currentStatus: 'REVIEW' }), false);
  assert.equal(canApproveTask({ isSuperAdmin: true, reviewerIds: [7], currentStatus: 'REVIEW' }), true);
  assert.equal(canApproveTask({ employeeId: 7, reviewerIds: [7], currentStatus: 'IN_PROGRESS' }), false);
  assert.equal(canApproveTask({ employeeId: 7, reviewerIds: [], currentStatus: 'REVIEW' }), false);
});

test('assignee next status stops at REVIEW when reviewers exist', () => {
  assert.equal(nextAssigneeStatus('TODO', [7]), 'IN_PROGRESS');
  assert.equal(nextAssigneeStatus('IN_PROGRESS', [7]), 'REVIEW');
  assert.equal(nextAssigneeStatus('REVIEW', [7]), 'REVIEW');
  assert.equal(nextAssigneeStatus('IN_PROGRESS', []), 'DONE');
  assert.equal(hasReviewers([7]), true);
});
