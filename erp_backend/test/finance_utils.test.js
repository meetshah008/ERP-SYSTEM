const test = require('node:test');
const assert = require('node:assert/strict');
const {
  addDays,
  parseTermsDays,
  dueDateFor,
  docNumber,
  nextSequence
} = require('../src/modules/04_finance/accounting/finance.utils');

test('addDays rolls over month and year boundaries in UTC', () => {
  assert.equal(addDays('2026-03-30', 5), '2026-04-04');
  assert.equal(addDays('2026-12-20', 15), '2027-01-04');
  assert.equal(addDays('2026-01-01', 0), '2026-01-01');
  assert.equal(addDays('not-a-date', 10), null);
});

test('parseTermsDays understands common payment term wording', () => {
  assert.equal(parseTermsDays('Net 30'), 30);
  assert.equal(parseTermsDays('30 days'), 30);
  assert.equal(parseTermsDays('15'), 15);
  assert.equal(parseTermsDays('Cash'), 0);
  assert.equal(parseTermsDays(''), null);
});

test('dueDateFor prefers an explicit date over payment terms', () => {
  assert.equal(dueDateFor('2026-04-01', 'Net 30', '2026-05-10'), '2026-05-10');
  assert.equal(dueDateFor('2026-04-01', 'Net 30', ''), '2026-05-01');
  assert.equal(dueDateFor('2026-04-01', 'unknown', ''), null);
});

test('docNumber and nextSequence keep series unique across years', () => {
  assert.equal(docNumber('INV', '2026-04-01', 7), 'INV-2026-0007');
  const existing = ['INV-2026-0001', 'INV-2026-0004', 'INV-2025-0099'];
  assert.equal(nextSequence(2, existing, 'INV', '2026-04-01'), 5);
  assert.equal(nextSequence(9, existing, 'INV', '2027-04-01'), 10);
  assert.equal(nextSequence(0, [], 'BILL', '2026-04-01'), 1);
});
