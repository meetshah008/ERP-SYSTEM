import 'package:erp_frontend/features/04_hr_module/attendance_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attendance missing In/Out data helpers', () {
    test('identifies missing punch values', () {
      expect(isMissingAttendanceTime(null), isTrue);
      expect(isMissingAttendanceTime(''), isTrue);
      expect(isMissingAttendanceTime('--'), isTrue);
      expect(isMissingAttendanceTime('--:--'), isTrue);
      expect(isMissingAttendanceTime('00:00:00'), isTrue);
      expect(isMissingAttendanceTime('09:15:00'), isFalse);
      expect(isMissingAttendanceTime('18:45:00'), isFalse);
    });

    test('counts only records with a missing In or Out value', () {
      final records = [
        {
          'employee_id': 1,
          'check_in_time': null,
          'check_out_time': '18:30:00',
        },
        {
          'employee_id': 1,
          'check_in_time': '09:00:00',
          'check_out_time': '--:--',
        },
        {
          'employee_id': 1,
          'check_in_time': '09:00:00',
          'check_out_time': '18:30:00',
        },
        {
          'employee_id': 2,
          'check_in_time': null,
          'check_out_time': null,
        },
      ];

      expect(countRecordsWithMissingPunchTimes(records), 3);
      expect(
        countRecordsWithMissingPunchTimes(
          records.where((record) => record['employee_id'] == 1),
        ),
        2,
      );
    });

    test('hasMissingPunchTimes checks both fields', () {
      expect(
        hasMissingPunchTimes({
          'check_in_time': '09:00:00',
          'check_out_time': '',
        }),
        isTrue,
      );
      expect(
        hasMissingPunchTimes({
          'check_in_time': '09:00:00',
          'check_out_time': '18:30:00',
        }),
        isFalse,
      );
    });

    test('Sunday rows are never reported as missing data', () {
      // 22 Nov 2026 is a Sunday, 21 Nov is a Saturday.
      final sunday = {
        'work_date': '2026-11-22',
        'check_in_time': null,
        'check_out_time': '--:--',
      };
      final saturday = {
        'work_date': '2026-11-21',
        'check_in_time': null,
        'check_out_time': '18:30:00',
      };
      final monday = {
        'work_date': '2026-11-23',
        'check_in_time': '09:00:00',
        'check_out_time': null,
      };

      expect(isSundayAttendanceRecord(sunday), isTrue);
      expect(isSundayAttendanceRecord(saturday), isFalse);
      expect(hasMissingPunchTimes(sunday), isFalse);
      expect(countRecordsWithMissingPunchTimes([sunday, saturday, monday]), 2);
    });
  });
}
