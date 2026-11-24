const test = require('node:test');
const assert = require('node:assert/strict');

const {
  findHeaderIndex,
  unpackRows,
  formatPreviewValue,
  parseDate,
  parseTime,
  getNormalizedValue,
} = require('../src/utils/attendance_parser');

test('finds the real header row below a report title', () => {
  const aoa = [
    ['Employee Attendance Status Report - November 2026'],
    [],
    ['Emp Code', 'Employee Name', 'Process Date', 'Punch1', 'Punch2'],
    ['00123', 'Asha', '2026-11-21', '09:05:00', '18:30:00'],
  ];

  assert.equal(findHeaderIndex(aoa), 2);
  const { headers, rows } = unpackRows(aoa, findHeaderIndex(aoa));
  assert.deepEqual(headers, ['Emp Code', 'Employee Name', 'Process Date', 'Punch1', 'Punch2']);
  assert.equal(rows.length, 1);
  assert.equal(rows[0]['Emp Code'], '00123');
});

test('preview uses local dates and renders time-only cells as clock values', () => {
  // Dates are built with local constructors so this test is timezone-independent.
  assert.equal(formatPreviewValue(new Date(2026, 0, 15, 9, 5)), '2026-01-15 09:05:00');
  assert.equal(formatPreviewValue(new Date(1899, 11, 30, 9, 5)), '09:05:00');
  assert.equal(formatPreviewValue(0.376), '09:01:26');
  assert.equal(formatPreviewValue('--:--'), '--:--');
});

test('parseDate never silently falls back to today', () => {
  assert.deepEqual(parseDate(null), null);
  assert.deepEqual(parseDate('not a date'), null);
  assert.deepEqual(parseDate('2026-11-22'), {
    cleanDate: '2026-11-22', month: 11, year: 2026,
  });
  assert.deepEqual(parseDate('31/12/2024'), {
    cleanDate: '2024-12-31', month: 12, year: 2024,
  });
  assert.deepEqual(parseDate('12/31/2024'), {
    cleanDate: '2024-12-31', month: 12, year: 2024,
  });
  assert.deepEqual(parseDate(45678), {
    cleanDate: '2025-01-21', month: 1, year: 2025,
  });
});

test('parseTime handles numeric serials, AM/PM and placeholders', () => {
  assert.equal(parseTime(null), null);
  assert.equal(parseTime('--:--'), null);
  assert.equal(parseTime('00:00'), null);
  assert.equal(parseTime(0.376), '09:01:26');
  assert.equal(parseTime('09:00 AM'), '09:00:00');
  assert.equal(parseTime('09:05:00 PM'), '21:05:00');
  assert.equal(parseTime('2026-11-21 09:05:00'), '09:05:00');
  assert.equal(parseTime(new Date(1899, 11, 30, 18, 45)), '18:45:00');
});

test('normalized values ignore BOM and spacing differences', () => {
  const row = { '\uFEFF Emp Code ': '00123', ' Punch 1 ': '09:05:00' };
  assert.equal(getNormalizedValue(row, ['empcode', 'userid']), '00123');
  assert.equal(getNormalizedValue(row, ['punch1', 'intime']), '09:05:00');
  assert.equal(getNormalizedValue(row, ['outtime']), null);
});

test('unpackRows drops blank rows so totals match processed rows', () => {
  const aoa = [
    ['UserID', 'Date', 'Punch1'],
    ['001', '2026-11-21', '09:00'],
    ['', '', ''],
    ['002', '2026-11-21', '10:00'],
  ];
  const { rows } = unpackRows(aoa, findHeaderIndex(aoa));
  assert.equal(rows.length, 2);
});
