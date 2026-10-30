/**
 * Receives the session date, class type, lecture hours, and checked-in roll
 * numbers from the lecturer's local Python server. Writes into existing rows.
 * Set SPREADSHEET_ID in Project Settings > Script properties.
 */
function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents || '{}');
    const properties = PropertiesService.getScriptProperties();
    const spreadsheetId = properties.getProperty('SPREADSHEET_ID');
    if (!spreadsheetId) return jsonResponse({ ok: false, error: 'SPREADSHEET_ID is not configured.' });
    const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
    const sheet = spreadsheet.getSheets()[0];
    if (payload.action === 'getRoster') {
      const lastRow = sheet.getLastRow();
      const rows = lastRow >= 2 ? sheet.getRange(2, 1, lastRow - 1, 2).getDisplayValues() : [];
      const students = rows
        .map(row => ({ name: String(row[0]).trim(), rollNo: String(row[1]).trim().toUpperCase() }))
        .filter(student => student.name.length >= 2 && student.rollNo);
      return jsonResponse({ ok: true, students: students });
    }
    if (payload.action !== 'syncSession' || !payload.session) {
      return jsonResponse({ ok: false, error: 'Invalid sync request.' });
    }
    const lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try {
      syncSession(sheet, spreadsheet, payload.session, payload.attendance || []);
    } finally {
      lock.releaseLock();
    }
    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse({ ok: false, error: String(error && error.message || error) });
  }
}

function syncSession(sheet, spreadsheet, session, attendance) {
  const lastColumn = Math.max(sheet.getLastColumn(), 2);
  if (sheet.getMaxColumns() < lastColumn) sheet.insertColumnsAfter(sheet.getMaxColumns(), lastColumn - sheet.getMaxColumns());
  const headers = sheet.getRange(1, 1, 1, lastColumn).getValues()[0];
  if (String(headers[0]).trim().toLowerCase() !== 'name') sheet.getRange(1, 1).setValue('Name');
  if (String(headers[1]).trim().toLowerCase() !== 'roll no') sheet.getRange(1, 2).setValue('Roll No');

  const sessionDate = String(session.date || '').trim();
  const classType = String(session.classType || 'class');
  const eventName = sessionDate + ' ' + classType.charAt(0).toUpperCase() + classType.slice(1).toLowerCase();
  const sessionColumn = Math.max(sheet.getLastColumn() + 1, 3);
  if (sessionColumn > sheet.getMaxColumns()) sheet.insertColumnAfter(sheet.getMaxColumns());
  sheet.getRange(1, sessionColumn).setValue(eventName);

  const lastRow = sheet.getLastRow();
  const existing = lastRow >= 2 ? sheet.getRange(2, 1, lastRow - 1, 2).getValues() : [];
  const rollByRow = new Map();
  existing.forEach((row, index) => {
    const roll = String(row[1] || '').trim().toUpperCase();
    if (roll) rollByRow.set(index + 2, roll);
  });
  const attendedRolls = new Set(attendance.map(record => String(record.rollNo || '').trim().toUpperCase()));
  const rowCount = Math.max(sheet.getLastRow() - 1, 0);
  if (rowCount) {
    const sessionValues = Array.from({ length: rowCount }, (_, index) => {
      const roll = rollByRow.get(index + 2);
      return [roll && attendedRolls.has(roll) ? Number(session.durationHours) : ''];
    });
    sheet.getRange(2, sessionColumn, rowCount, 1).setValues(sessionValues);
  }
  sheet.setFrozenRows(0);
  sheet.setFrozenColumns(0);
}

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
