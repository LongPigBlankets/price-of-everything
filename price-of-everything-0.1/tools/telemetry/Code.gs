// Carbon and Capital — telemetry endpoint (v5: tutorial progress in runs)
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
//   legacy headers, migrate them explicitly; do not delete your historical data.
//   Schema 4 automatically appends interaction columns to the current turns header.
//
// The runs/turns tabs self-create with headers on the first POST. Visiting the
// /exec URL in a browser (GET) should print "alive".

const TOKEN = "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641";

// v3 adds `start` (which start config the run began from — the field balance analysis
// wants most, previously only recoverable by fingerprinting turn-1 production),
// `cheats_used` (sticky taint: unflagged cheat runs poison aggregates) and `rescues`
// (tutorial top-ups used, 0-3). All three are latched during the run, not read at
// finalize, because a quit-to-menu envelope is built after the match is torn down.
const RUNS_HEADER = ["received_at", "player_id", "run_id", "session_id", "version",
                     "os", "start", "end_reason", "run_complete", "end_turn",
                     "cheats_used", "rescues", "raw_json",
                     "tutorial_step", "tutorial_visited"];
// One row per turn. "goods" is the sparse per-good production pipe-joined as
// name:qty (e.g. "coal:51|iron_ore:28|steel:53") — zero-production goods are
// absent by construction. tiers/victory are pipe-joined arrays.
// "received_at" is stamped server-side per POST so the turns tab can be read for
// recency on its own — the runs tab always had it, the turns tab did not, which made
// "has anything arrived lately?" unanswerable without joining the two (owner 2026-08-01).
// v3 adds three diagnosis columns, all pipe-joined like `goods`:
//   costs           — this turn's money_out split as name:value (inputs:120|labour:40|…).
//                     These SUM INTO money_out; they are not extra charges on top of it.
//   buildings_list  — the player's roster as internal_name(level): mine(l1)|furnace(l2)
//   building_states — index-aligned with buildings_list: running, or why it didn't run
//                     (missing_inputs, no_power, starting, market_input_cash, …)
const FIXED = ["received_at", "run_id", "session_id", "turn", "money", "revenue", "profit", "loans",
               "buildings", "power_gen", "power_use", "tiers", "victory",
//   transport       — this turn's freight split, six pipe-joined values in FIXED order:
//                     port_inbound|port_outbound|roads|rail|pipes|reinf_pipes
//                     They sum to the `transport` entry inside `costs`.
               "playtime_s", "goods", "costs", "transport", "buildings_list", "building_states"];

// Schema 4: append-only columns; existing economic data stays in place.
const INTERACTIONS = ["encyclopedia_opened", "good_encyclopedia_opened", "goods_graph_opened",
  "goods_graph_good_selected", "money_panel_opened", "balance_panel_opened",
  "supply_chain_opened", "supply_chain_building_selected", "research_panel_opened", "search_used"];
FIXED.push(...INTERACTIONS);
const EVENTS_HEADER = ["received_at", "player_id", "run_id", "session_id", "event_id",
  "turn", "playtime_s", "action", "interface", "target_id", "version"];
// One row per app start, sent before any run exists. This is the only signal that counts
// players who open the game and never finish a run — they produce no envelope at all, and
// they are exactly the population worth measuring. `os` carries Web vs desktop, so browser
// launches share this tab rather than splitting off like WB Runs / WB Turns.
const LAUNCHES_HEADER = ["received_at", "launch_id", "player_id", "session_id",
  "version", "os", "launched_at"];


function doGet() {
  return ContentService.createTextOutput("alive");
}

function doPost(e) {
  let p;
  try { p = JSON.parse(e.postData.contents); }
  catch (err) { return ContentService.createTextOutput("bad json"); }
  if (p.token !== TOKEN) return ContentService.createTextOutput("no");

  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
  const ss = SpreadsheetApp.getActive();

  if (p.kind === "launch") {
    const sheet = sheetWithHeader_(ss, "launches", LAUNCHES_HEADER);
    // launched_at is the CLIENT's clock: an offline launch uploads on a later boot, so
    // received_at can trail it by days. Compare launched_at, not received_at, for activity.
    sheet.appendRow([new Date(), p.launch_id || "", p.player_id || "", p.session_id || "",
      (p.client || {}).version || "", (p.client || {}).os || "",
      p.launched_at ? new Date(p.launched_at * 1000) : ""]);
    return ContentService.createTextOutput("launch_ok");
  }
  if (p.kind === "feedback") {
    const ratings = ["Great", "Good", "Average", "Bad", "Terrible"];
    if (!p.feedback_id || !ratings.includes(p.rating)) return ContentService.createTextOutput("bad feedback");
    const sheet = sheetWithHeader_(ss, "feedback", ["received_at", "feedback_id", "player_id", "version", "os", "start", "turn", "rating", "comment"]);
    const ids = sheet.getLastRow() > 1 ? sheet.getRange(2, 2, sheet.getLastRow() - 1, 1).getValues().flat() : [];
    if (!ids.includes(p.feedback_id)) {
      // Store user text literally so leading '=' cannot become a spreadsheet formula.
      const comment = String(p.comment || "").slice(0, 4000);
      sheet.appendRow([new Date(), p.feedback_id, p.player_id || "", (p.client || {}).version || "", (p.client || {}).os || "", p.start || "", p.turn || 0, p.rating, comment ? "'" + comment : ""]);
    }
    return ContentService.createTextOutput("feedback_ok");
  }
  const run = p.run || {};
  // Web (itch.io browser) builds report OS.get_name() == "Web"; keep their rows on their
  // own tabs so desktop and browser play can be read side by side.
  const isWeb = String((p.client || {}).os || "") === "Web";
  const runs = sheetWithHeader_(ss, isWeb ? "WB Runs" : "runs", RUNS_HEADER);
  runs.appendRow([new Date(), p.player_id, p.run_id, p.session_id,
      p.client.version, p.client.os, run.start || "", p.end.reason, p.end.run_complete,
      p.end.turn, run.cheats_used === true, p.end.rescues || 0, JSON.stringify(p),
      run.tutorial_step || "", run.tutorial_visited || 0]);

  const sh = sheetWithHeader_(ss, isWeb ? "WB Turns" : "turns", FIXED);
  const stamped = new Date();
  const turnKeys = new Set(sh.getLastRow() > 1
    ? sh.getRange(2, 2, sh.getLastRow() - 1, 3).getValues().map(r => r[0] + ":" + r[2]) : []);
  const rows = (p.turns || []).filter(t => {
    const key = p.run_id + ":" + t.turn;
    if (turnKeys.has(key)) return false;
    turnKeys.add(key);
    return true;
  }).map(t => FIXED.map(col => {
    if (INTERACTIONS.includes(col)) return t.interactions ? Number(t.interactions[col] || 0) : "";
    if (col === "received_at") return stamped;
    if (col === "run_id") return p.run_id;
    if (col === "session_id") return p.session_id;
    if (col === "tiers" || col === "victory") return (t[col] || []).join("|");
    if (col === "buildings_list" || col === "building_states" || col === "transport")
      return (t[col] || []).join("|");
    if (col === "goods" || col === "costs") {
      const src = col === "goods" ? (t.produced || {}) : (t.costs || {});
      return Object.keys(src).map(k => k + ":" + src[k]).join("|");
    }
    return t[col];
  }));
  if (rows.length) {
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, FIXED.length).setValues(rows);
  }
  const events = sheetWithHeader_(ss, "events", EVENTS_HEADER);
  const known = new Set(events.getLastRow() > 1
    ? events.getRange(2, 5, events.getLastRow() - 1, 1).getValues().flat() : []);
  const eventRows = [];
  for (const event of (p.events || [])) {
    if (!event.event_id || known.has(event.event_id)) continue;
    known.add(event.event_id);
    eventRows.push([stamped, p.player_id, p.run_id, event.session_id, event.event_id,
      event.turn, event.playtime_s, event.action, event.interface, event.target_id || "", p.client.version]);
  }
  if (eventRows.length) events.getRange(events.getLastRow() + 1, 1, eventRows.length, EVENTS_HEADER.length).setValues(eventRows);
  return ContentService.createTextOutput("ok");
  } finally { lock.releaseLock(); }
}

function sheetWithHeader_(ss, name, header) {
  let sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    if (sh.getMaxColumns() < header.length) sh.insertColumnsAfter(sh.getMaxColumns(), header.length - sh.getMaxColumns());
    sh.getRange(1, 1, 1, header.length).setValues([header]);
    sh.setFrozenRows(1);
  }
  if (sh.getMaxColumns() < header.length) sh.insertColumnsAfter(sh.getMaxColumns(), header.length - sh.getMaxColumns());
  // Extend a matching old header without deleting any rows or existing columns.
  const actual = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
  if (actual.length > header.length || actual.some((name, i) => name !== header[i]))
    throw new Error("Unexpected header in " + name + "; preserve data and check column order before updating.");
  if (actual.length < header.length)
    sh.getRange(1, actual.length + 1, 1, header.length - actual.length).setValues([header.slice(actual.length)]);
  return sh;
}
