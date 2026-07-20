// Carbon and Capital — telemetry endpoint (proof of concept)
// See docs/telemetry-spec.md §6.
//
// Setup (once, signed in as carbon.capital.data@gmail.com):
//   1. sheets.new  → name the spreadsheet (e.g. "CnC Telemetry v0.1")
//   2. Extensions → Apps Script → delete the stub, paste this whole file, save
//   3. Deploy → New deployment → type: Web app
//        Execute as: Me   ·   Who has access: Anyone
//   4. Authorize when prompted (it's your own script — Advanced → Go to project)
//   5. Copy the Web app URL ending in /exec
//
// The runs/turns tabs self-create with headers on the first POST — no manual
// seeding. Visiting the /exec URL in a browser (GET) should print "alive".

const TOKEN = "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641";

const RUNS_HEADER = ["received_at", "player_id", "run_id", "session_id", "version",
                     "os", "end_reason", "run_complete", "end_turn", "raw_json"];
// Fixed columns of the turns tab; per-good columns auto-append to the right of
// these the first time a good id is seen (header row = source of truth).
const FIXED = ["run_id", "session_id", "turn", "money", "revenue", "profit", "loans",
               "buildings", "power_gen", "power_use", "tiers", "victory", "playtime_s"];

function doGet() {
  return ContentService.createTextOutput("alive");
}

function doPost(e) {
  let p;
  try { p = JSON.parse(e.postData.contents); }
  catch (err) { return ContentService.createTextOutput("bad json"); }
  if (p.token !== TOKEN) return ContentService.createTextOutput("no");

  const ss = SpreadsheetApp.getActive();

  const runs = sheetWithHeader_(ss, "runs", RUNS_HEADER);
  runs.appendRow([new Date(), p.player_id, p.run_id, p.session_id,
      p.client.version, p.client.os, p.end.reason, p.end.run_complete,
      p.end.turn, JSON.stringify(p)]);

  const sh = sheetWithHeader_(ss, "turns", FIXED);
  const header = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
  const seen = new Set(header);
  (p.turns || []).forEach(t => Object.keys(t.produced || {}).forEach(g => {
    if (!seen.has(g)) {
      seen.add(g);
      header.push(g);
      sh.getRange(1, header.length).setValue(g);   // new good → new column
    }
  }));

  const rows = (p.turns || []).map(t => header.map((col, i) => {
    if (i >= FIXED.length) return (t.produced || {})[col] || 0;  // good columns
    if (col === "run_id") return p.run_id;
    if (col === "session_id") return p.session_id;
    if (col === "tiers" || col === "victory") return (t[col] || []).join("|");
    return t[col];
  }));
  if (rows.length) {
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, header.length).setValues(rows);
  }
  return ContentService.createTextOutput("ok");
}

function sheetWithHeader_(ss, name, header) {
  let sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.getRange(1, 1, 1, header.length).setValues([header]);
    sh.setFrozenRows(1);
  }
  return sh;
}
