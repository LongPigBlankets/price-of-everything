// Carbon and Capital — telemetry endpoint (v2: single pipe-joined goods column)
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
// Updating an EXISTING deployment (keeps the same /exec URL):
//   paste the new code, save, then Deploy → Manage deployments → ✏️ →
//   Version: New version → Deploy. If the turns tab still has the old
//   per-good columns, DELETE that tab — it self-recreates with this header.
//
// The runs/turns tabs self-create with headers on the first POST. Visiting the
// /exec URL in a browser (GET) should print "alive".

const TOKEN = "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641";

const RUNS_HEADER = ["received_at", "player_id", "run_id", "session_id", "version",
                     "os", "end_reason", "run_complete", "end_turn", "raw_json"];
// One row per turn. "goods" is the sparse per-good production pipe-joined as
// name:qty (e.g. "coal:51|iron_ore:28|steel:53") — zero-production goods are
// absent by construction. tiers/victory are pipe-joined arrays.
// "received_at" is stamped server-side per POST so the turns tab can be read for
// recency on its own — the runs tab always had it, the turns tab did not, which made
// "has anything arrived lately?" unanswerable without joining the two (owner 2026-08-01).
const FIXED = ["received_at", "run_id", "session_id", "turn", "money", "revenue", "profit", "loans",
               "buildings", "power_gen", "power_use", "tiers", "victory",
               "playtime_s", "goods"];

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
  const stamped = new Date();
  const rows = (p.turns || []).map(t => FIXED.map(col => {
    if (col === "received_at") return stamped;
    if (col === "run_id") return p.run_id;
    if (col === "session_id") return p.session_id;
    if (col === "tiers" || col === "victory") return (t[col] || []).join("|");
    if (col === "goods") {
      const pr = t.produced || {};
      return Object.keys(pr).map(g => g + ":" + pr[g]).join("|");
    }
    return t[col];
  }));
  if (rows.length) {
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, FIXED.length).setValues(rows);
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
