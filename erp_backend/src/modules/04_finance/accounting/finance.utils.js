'use strict';

/** Small, database-free helpers used by the finance module (and its unit tests). */

function num(value) {
  const n = parseFloat(value);
  return Number.isFinite(n) ? n : 0;
}

function addDays(dateStr, days) {
  const date = String(dateStr || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const result = new Date(`${date}T00:00:00Z`);
  result.setUTCDate(result.getUTCDate() + Math.max(0, Math.trunc(num(days))));
  return result.toISOString().slice(0, 10);
}

/** Understands "Net 30", "30 days", "15", "Cash", "Immediate". */
function parseTermsDays(terms) {
  const text = String(terms || '').trim();
  if (/immediate|cash|advance|on receipt/i.test(text)) return 0;
  const match = text.match(/(\d+)\s*(?:days?|d)\b/i) || text.match(/\b(\d+)\b/);
  return match ? parseInt(match[1], 10) : null;
}

/** An explicit due date always wins; otherwise derive one from payment terms. */
function dueDateFor(docDate, terms, explicit) {
  if (explicit && /^\d{4}-\d{2}-\d{2}$/.test(String(explicit))) return String(explicit);
  const days = parseTermsDays(terms);
  return days === null ? null : addDays(docDate, days);
}

function docNumber(prefix, date, sequence) {
  const cleanPrefix = String(prefix || 'DOC').trim().toUpperCase() || 'DOC';
  return `${cleanPrefix}-${String(date || '').slice(0, 4)}-${String(Math.max(1, Math.trunc(num(sequence)))).padStart(4, '0')}`;
}

/** Keeps the series in sync with documents that may already exist in the table. */
function nextSequence(lastNumber, existingNumbers, prefix, date) {
  const year = String(date || '').slice(0, 4);
  const safePrefix = String(prefix || 'DOC').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^${safePrefix}-${year}-(\\d+)$`, 'i');
  let highest = 0;
  for (const value of existingNumbers || []) {
    const match = pattern.exec(String(value || ''));
    if (match) highest = Math.max(highest, parseInt(match[1], 10));
  }
  return Math.max(num(lastNumber), highest) + 1;
}

module.exports = { num, addDays, parseTermsDays, dueDateFor, docNumber, nextSequence };
