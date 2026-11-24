import 'package:erp_frontend/core/utils/task_status_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('task status flow', () {
    test('normalizes unknown status to TODO', () {
      expect(normalizeTaskStatus(' review '), 'REVIEW');
      expect(normalizeTaskStatus('nonsense'), 'TODO');
    });

    test('tasks with reviewers stop at REVIEW', () {
      final task = {
        'status': 'IN_PROGRESS',
        'reviewers': [
          {'employee_id': 7, 'full_name': 'Reviewer'},
        ],
      };
      expect(taskHasReviewers(task), isTrue);
      expect(nextTaskStatus(task), 'REVIEW');
      expect(nextTaskStatus({'status': 'REVIEW', 'reviewers': task['reviewers']}), 'REVIEW');
      expect(canAssigneeMarkDone(task), isFalse);
    });

    test('tasks without reviewers keep the old completion path', () {
      final task = {'status': 'IN_PROGRESS', 'reviewers': []};
      expect(taskHasReviewers(task), isFalse);
      expect(nextTaskStatus(task), 'DONE');
      expect(nextTaskStatus({'status': 'DONE', 'reviewers': []}), 'TODO');
      expect(canAssigneeMarkDone(task), isTrue);
    });
  });
}
