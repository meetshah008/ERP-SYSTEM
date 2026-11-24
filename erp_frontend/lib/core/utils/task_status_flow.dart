/// Shared task status rules used by board quick actions and details screens.
///
/// A task with reviewers can never jump straight to DONE from an assignee
/// action; it must pass through REVIEW and be approved there.
const Set<String> taskStatuses = {'TODO', 'IN_PROGRESS', 'REVIEW', 'DONE'};

String normalizeTaskStatus(dynamic status) {
  final value = status?.toString().trim().toUpperCase() ?? '';
  return taskStatuses.contains(value) ? value : 'TODO';
}

bool taskHasReviewers(dynamic task) {
  final reviewers = task is Map ? task['reviewers'] : null;
  if (reviewers is! List || reviewers.isEmpty) return false;
  return reviewers.any((r) => (r is Map ? r['employee_id'] : r) != null);
}

String nextTaskStatus(dynamic task) {
  final status = normalizeTaskStatus(task is Map ? task['status'] : null);
  if (status == 'TODO') return 'IN_PROGRESS';
  if (status == 'IN_PROGRESS') {
    return taskHasReviewers(task) ? 'REVIEW' : 'DONE';
  }
  if (status == 'REVIEW') return 'REVIEW';
  return 'TODO';
}

bool canAssigneeMarkDone(dynamic task) => !taskHasReviewers(task);
