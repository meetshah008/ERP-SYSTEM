/**
 * Shared parsing helpers for biometric attendance dumps.
 *
 * Preview and upload MUST use the same header detection/formatting rules,
 * otherwise the console shows one thing while the database stores another.
 */
const xlsx = require('xlsx');

const pad = (value, length = 2) => String(value).padStart(length, '0');

function isBlank(value) {
  return value === null || value === undefined || String(value).trim() === '';
}

function normalizeKey(value) {
  return String(value ?? '')
    .replace(/^\uFEFF/, '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function headerLabel(value, index) {
  const text = String(value ?? '').replace(/^\uFEFF/, '').trim();
  return text.length > 0 ? text : `Col ${index + 1}`;
}

/**
 * Finds the real header row. Strong biometric headers win; generic words are
 * only used as a fallback so a title row like "Attendance Report" cannot take
 * precedence over "Emp Code | Date | Punch1".
 */
function findHeaderIndex(aoa) {
  const strong = [
    'userid', 'empcode', 'empid', 'enrollid', 'badgenumber',
    'processdate', 'punch1', 'punch2', 'intime', 'outtime', 'checkin', 'checkout',
  ];
  const fallback = ['emp', 'user', 'date', 'time', 'status', 'name'];

  // Strong biometric headers need just one match. Generic words need at least
  // two matches so a title like "Attendance Status Report" is not mistaken for
  // the real header row.
  for (const hints of [strong, fallback]) {
    const minimumMatches = hints === fallback ? 2 : 1;
    for (let i = 0; i < Math.min(aoa.length, 20); i++) {
      const row = aoa[i];
      if (!Array.isArray(row)) continue;
      const keys = row.map(normalizeKey).filter(Boolean);
      const matches = new Set();
      for (const key of keys) {
        for (const hint of hints) {
          if (key === hint || key.includes(hint)) matches.add(hint);
        }
      }
      if (matches.size >= minimumMatches && (minimumMatches === 1 || keys.length >= 2)) return i;
    }
  }
  return -1;
}

/**
 * Converts an AOA sheet into header-keyed objects. Fully empty rows are
 * dropped so totals match what was actually processed.
 */
function unpackRows(aoa, headerIndex) {
  if (headerIndex < 0) return { headers: [], rows: [] };

  const rawHeaders = Array.isArray(aoa[headerIndex]) ? aoa[headerIndex] : [];
  let isSingleCol = false;
  let delim = ',';
  let headers;

  if (
    rawHeaders.length === 1 &&
    (String(rawHeaders[0]).includes(',') || String(rawHeaders[0]).includes(';'))
  ) {
    isSingleCol = true;
    delim = String(rawHeaders[0]).includes(',') ? ',' : ';';
    headers = String(rawHeaders[0])
      .replace(/^\uFEFF/, '')
      .split(delim)
      .map((h, i) => headerLabel(h, i));
  } else {
    headers = rawHeaders.map(headerLabel);
  }

  const rows = [];
  for (let i = headerIndex + 1; i < aoa.length; i++) {
    const raw = aoa[i];
    if (!Array.isArray(raw) || raw.every(isBlank)) continue;

    let values = raw;
    if (isSingleCol && raw.length === 1) {
      values = String(raw[0]).split(delim).map((v) => v.trim());
    }

    const row = {};
    headers.forEach((header, idx) => {
      row[header] = values[idx] !== undefined ? values[idx] : '';
    });
    rows.push(row);
  }

  return { headers, rows, isSingleCol, delim };
}

function isTimeOnlyDate(date) {
  return date.getFullYear() === 1899 || date.getFullYear() === 1900;
}

function formatTime(hour, minute, second = 0) {
  return `${pad(hour)}:${pad(minute)}:${pad(Math.round(second) || 0)}`;
}

function formatDate(year, month, day) {
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
}

/** Human-readable cell value for the live preview grid (local time, not UTC). */
function formatPreviewValue(value) {
  if (value === null || value === undefined) return '';

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    if (isTimeOnlyDate(value)) {
      return formatTime(value.getHours(), value.getMinutes(), value.getSeconds());
    }
    const date = formatDate(value.getFullYear(), value.getMonth() + 1, value.getDate());
    const hasTime = value.getHours() || value.getMinutes() || value.getSeconds();
    return hasTime
      ? `${date} ${formatTime(value.getHours(), value.getMinutes(), value.getSeconds())}`
      : date;
  }

  // Unformatted time serials (0 < value < 1) stay numbers otherwise.
  if (typeof value === 'number' && value > 0 && value < 1) {
    const parts = xlsx.SSF.parse_date_code(value);
    if (parts) return formatTime(parts.H, parts.M, parts.S);
  }

  return String(value).trim();
}

/** Returns { cleanDate, month, year } or null when the value is unusable. */
function parseDate(raw) {
  if (isBlank(raw)) return null;

  if (raw instanceof Date && !Number.isNaN(raw.getTime())) {
    if (isTimeOnlyDate(raw)) return null;
    const year = raw.getFullYear();
    const month = raw.getMonth() + 1;
    return { cleanDate: formatDate(year, month, raw.getDate()), month, year };
  }

  if (typeof raw === 'number' && raw >= 20000 && raw < 100000) {
    const parts = xlsx.SSF.parse_date_code(raw);
    if (parts && parts.y) {
      return {
        cleanDate: formatDate(parts.y, parts.m, parts.d),
        month: parts.m,
        year: parts.y,
      };
    }
    return null;
  }

  const str = String(raw).trim();
  let match = str.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (match) {
    const year = parseInt(match[1], 10);
    const month = parseInt(match[2], 10);
    const day = parseInt(match[3], 10);
    return { cleanDate: formatDate(year, month, day), month, year };
  }

  // dd/mm/yyyy is the default for Indian biometric dumps; if the first part
  // cannot be a day but the second can, treat it as mm/dd/yyyy.
  match = str.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{4})$/);
  if (match) {
    let day = parseInt(match[1], 10);
    let month = parseInt(match[2], 10);
    const year = parseInt(match[3], 10);
    // 31/12/yyyy is dd/mm; 12/31/yyyy is mm/dd.
    if (month > 12 && day <= 12) [day, month] = [month, day];
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return { cleanDate: formatDate(year, month, day), month, year };
    }
  }

  return null;
}

/** Returns HH:mm:ss or null for placeholders such as --:-- / null / 00:00. */
function parseTime(raw) {
  if (isBlank(raw)) return null;

  if (raw instanceof Date && !Number.isNaN(raw.getTime())) {
    return formatTime(raw.getHours(), raw.getMinutes(), raw.getSeconds());
  }

  if (typeof raw === 'number') {
    if (raw <= 0 || raw >= 1) return null;
    const parts = xlsx.SSF.parse_date_code(raw);
    return parts ? formatTime(parts.H, parts.M, parts.S) : null;
  }

  const str = String(raw).trim();
  if (
    str === '0' ||
    str.toLowerCase() === 'null' ||
    /^[-–—:]+$/.test(str) ||
    /^0{1,2}:0{2}(?::0{2})?$/.test(str)
  ) {
    return null;
  }

  const ampm = str.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$/i);
  if (ampm) {
    let hour = parseInt(ampm[1], 10) % 12;
    if (ampm[4].toUpperCase() === 'PM') hour += 12;
    return formatTime(hour, parseInt(ampm[2], 10), parseInt(ampm[3] || '0', 10));
  }

  // Matches the first clock-looking fragment, e.g. "2026-11-21 09:05:00".
  const clock = str.match(/(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (clock) {
    const hour = parseInt(clock[1], 10);
    const minute = parseInt(clock[2], 10);
    if (hour <= 23 && minute <= 59) {
      return formatTime(hour, minute, parseInt(clock[3] || '0', 10));
    }
  }

  return null;
}

function getNormalizedValue(row, candidates) {
  for (const key of Object.keys(row || {})) {
    const cleanKey = normalizeKey(key);
    for (const candidate of candidates) {
      if (cleanKey === normalizeKey(candidate) && !isBlank(row[key])) {
        return row[key];
      }
    }
  }
  return null;
}

module.exports = {
  findHeaderIndex,
  unpackRows,
  formatPreviewValue,
  parseDate,
  parseTime,
  getNormalizedValue,
  normalizeKey,
};
