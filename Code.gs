/**
 * Pulse Powerhub — RSVP receiver
 *
 * Setup:
 * 1. Buka Google Sheet baru, rename tab pertama jadi "RSVP"
 * 2. Extensions > Apps Script, paste file ini
 * 3. Jalankan setupSheet() sekali (buat header row)
 * 4. Deploy > New deployment > Web app
 *      Execute as       : Me
 *      Who has access   : Anyone
 * 5. Copy URL /exec ke VITE_SHEETS_ENDPOINT di frontend
 *
 * Catatan: setiap kali kamu ubah kode, harus Deploy > Manage deployments >
 * edit > version "New version". Kalau tidak, URL lama tetap jalankan kode lama.
 */

var SHEET_NAME = 'RSVP';

function setupSheet() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  sheet.getRange(1, 1, 1, 10).setValues([[
    'Timestamp', 'Name', 'WhatsApp', 'Email', 'Guests', 'Member', 'Source', 'Duplicate', 'Status', 'Comment'
  ]]);
  sheet.getRange(1, 1, 1, 10).setFontWeight('bold');
  sheet.setFrozenRows(1);
}

function doPost(e) {
  var lock = LockService.getScriptLock();

  // tanpa lock, dua submit bersamaan bisa nulis ke baris yang sama
  try {
    lock.waitLock(30000);
  } catch (err) {
    return json({ status: 'error', message: 'Server busy, please retry.' });
  }

  try {
    var body = JSON.parse(e.postData.contents);

    var name = String(body.name || '').trim();
    var phone = normalisePhone(body.phone);
    var email = String(body.email || '').trim().toLowerCase();

    if (!name || !phone || !email) {
      return json({ status: 'error', message: 'Missing required fields.' });
    }

    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);

    // tandai duplikat, jangan tolak — biar tim gym yang putuskan
    var duplicate = isDuplicate(sheet, phone, email) ? 'YES' : '';

    sheet.appendRow([
      new Date(),
      name,
      phone,
      email,
      Number(body.guests) || 1,
      String(body.member || ''),
      String(body.source || 'direct'),
      duplicate,
      String(body.status || 'going'),
      String(body.comment || '')
    ]);

    return json({ status: 'success' });

  } catch (err) {
    return json({ status: 'error', message: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/** Buka URL /exec di browser untuk cek deployment sudah hidup, juga dipakai frontend buat "spots left" */
function doGet() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  var last = sheet.getLastRow();
  var count = 0;

  if (last > 1) {
    var rows = sheet.getRange(2, 5, last - 1, 5).getValues(); // kolom E..I = Guests..Status
    for (var i = 0; i < rows.length; i++) {
      var rsvpStatus = String(rows[i][4] || 'going'); // kolom I
      if (rsvpStatus === 'cant') continue; // "Can't Go" tidak makan kuota
      count += Number(rows[i][0]) || 0; // kolom E
    }
  }

  return json({ status: 'ok', service: 'pulse-rsvp', count: count });
}

/** 08123... dan 8123... dinormalkan ke +62 supaya dedup akurat */
function normalisePhone(raw) {
  var digits = String(raw || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.indexOf('62') === 0) return '+' + digits;
  if (digits.indexOf('0') === 0) return '+62' + digits.substring(1);
  if (digits.indexOf('8') === 0) return '+62' + digits;
  return '+' + digits;
}

function isDuplicate(sheet, phone, email) {
  var last = sheet.getLastRow();
  if (last < 2) return false;

  var rows = sheet.getRange(2, 3, last - 1, 2).getValues(); // kolom C & D
  for (var i = 0; i < rows.length; i++) {
    if (rows[i][0] === phone || String(rows[i][1]).toLowerCase() === email) {
      return true;
    }
  }
  return false;
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
