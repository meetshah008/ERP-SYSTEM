import 'package:erp_frontend/features/05_tasks/task_form_screen.dart';
import 'package:flutter_test/flutter_test.dart';

List<dynamic> _employees([int count = 5]) => List<dynamic>.generate(
      count,
      (index) => <String, dynamic>{
        'employee_id': index + 1,
        'full_name': 'Worker ${index + 1}',
        'emp_code': 'EMP${index + 1}',
      },
    );

List<int> _ids(List<dynamic> workers) => workers
    .map((worker) => int.tryParse((worker as Map)['employee_id']?.toString() ?? '') ?? 0)
    .toList();

void main() {
  group('buildAssignableWorkers', () {
    test('shows every active employee when no project is selected', () {
      final workers = buildAssignableWorkers(_employees(6));

      expect(_ids(workers), equals([1, 2, 3, 4, 5, 6]));
    });

    test('keeps project team first but still shows the remaining staff', () {
      final employees = _employees();
      final projectTeam = <dynamic>[
        employees[3],
        employees[0],
        <String, dynamic>{
          'employee_id': 99,
          'full_name': 'Project Leader',
          'emp_code': 'LEAD',
          'role_in_project': 'Lead',
        },
      ];

      final workers = buildAssignableWorkers(
        employees,
        priorityWorkers: projectTeam,
      );

      expect(_ids(workers), equals([4, 1, 99, 2, 3, 5]));
      expect(
        workers.firstWhere((worker) => worker['employee_id'] == 99)['role_in_project'],
        equals('Lead'),
      );
    });

    test('ignores duplicate and invalid employee ids', () {
      final workers = buildAssignableWorkers(
        _employees(2),
        priorityWorkers: <dynamic>[
          <String, dynamic>{'employee_id': 1, 'full_name': 'Duplicate'},
          <String, dynamic>{'full_name': 'No id'},
          <String, dynamic>{'employee_id': 0, 'full_name': 'Invalid'},
        ],
      );

      expect(_ids(workers), equals([1, 2]));
    });
  });
}
