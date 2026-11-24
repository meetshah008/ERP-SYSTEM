const test = require('node:test');
const assert = require('node:assert/strict');
const { buildLeaveDateFilter } = require('../src/utils/leave_filter');

test('no date params produces no extra SQL clause', () => {
  assert.deepEqual(buildLeaveDateFilter({}), { clause: '', params: [] });
});

test('month and year filter on leave start date', () => {
  assert.deepEqual(buildLeaveDateFilter({ month: '11', year: '2026' }), {
    clause: ' AND MONTH(l.start_date) = ? AND YEAR(l.start_date) = ?',
    params: [11, 2026],
  });
});

test('year alone filters just the year', () => {
  assert.deepEqual(buildLeaveDateFilter({ year: 2026 }), {
    clause: ' AND YEAR(l.start_date) = ?',
    params: [2026],
  });
});

test('custom range uses an inclusive BETWEEN', () => {
  assert.deepEqual(
    buildLeaveDateFilter({
      start_date: '2026-10-26',
      end_date: '2026-11-24',
    }),
    {
      clause: ' AND l.start_date BETWEEN ? AND ?',
      params: ['2026-10-26', '2026-11-24'],
    },
  );
});

test('invalid month/year values are ignored', () => {
  assert.deepEqual(buildLeaveDateFilter({ month: 'abc', year: '' }), {
    clause: '',
    params: [],
  });
});
