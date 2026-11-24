import 'package:erp_frontend/features/04_hr_module/leave_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 24, 15, 30);

  group('buildLeaveQueryParams', () {
    test('default all time keeps the original request unchanged', () {
      expect(buildLeaveQueryParams(now: now), isEmpty);
      expect(
        buildLeaveQueryParams(userId: 17, now: now),
        ['user_id=17'],
      );
    });

    test('current month sends month and year', () {
      expect(
        buildLeaveQueryParams(period: 'current_month', now: now),
        ['month=11', 'year=2026'],
      );
    });

    test('last 30 days sends an inclusive date range', () {
      expect(
        buildLeaveQueryParams(period: 'last_30_days', now: now),
        ['start_date=2026-10-26', 'end_date=2026-11-24'],
      );
    });

    test('custom range keeps employee self-scope', () {
      final range = DateTimeRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );
      expect(
        buildLeaveQueryParams(
          userId: 17,
          period: 'custom',
          customRange: range,
          now: now,
        ),
        [
          'user_id=17',
          'start_date=2026-10-01',
          'end_date=2026-10-31',
        ],
      );
    });
  });

  group('filterLeavesByPeriod', () {
    final leaves = <dynamic>[
      {'start_date': '2026-11-01', 'status': 'PENDING'},
      {'start_date': '2026-11-30', 'status': 'APPROVED'},
      {'start_date': '2026-10-31', 'status': 'PENDING'},
      {'start_date': '2026-10-26', 'status': 'PENDING'},
    ];

    test('all time returns every row', () {
      expect(filterLeavesByPeriod(leaves, 'all', now: now), leaves);
    });

    test('current month keeps only this month, including month end', () {
      final result = filterLeavesByPeriod(leaves, 'current_month', now: now);
      expect(result, hasLength(2));
      expect(result[0]['start_date'], '2026-11-01');
      expect(result[1]['start_date'], '2026-11-30');
    });

    test('last 30 days respects the inclusive lower boundary', () {
      final result = filterLeavesByPeriod(leaves, 'last_30_days', now: now);
      expect(result, hasLength(3));
      expect(result.map((l) => l['start_date']), [
        '2026-11-01',
        '2026-10-31',
        '2026-10-26',
      ]);
    });

    test('custom range uses both endpoints inclusively', () {
      final range = DateTimeRange(
        start: DateTime(2026, 10, 26),
        end: DateTime(2026, 10, 31),
      );
      final result = filterLeavesByPeriod(
        leaves,
        'custom',
        customRange: range,
        now: now,
      );
      expect(result.map((l) => l['start_date']), [
        '2026-10-31',
        '2026-10-26',
      ]);
    });

    test('rows without a parseable date are excluded while filtering', () {
      final result = filterLeavesByPeriod(
        <dynamic>[
          {'start_date': null},
          {'start_date': ''},
          {'created_at': '2026-11-05 09:20:00'},
        ],
        'current_month',
        now: now,
      );
      expect(result, hasLength(1));
      expect(result.first['created_at'], '2026-11-05 09:20:00');
    });
  });
}
