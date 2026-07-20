# Spec — Playtest Telemetry (per-turn capture → end-of-run upload)

Status: DESIGN — not built. Written 2026-07-20.
Scope: anonymous, consented capture of one row of economic data per turn, cached to disk
every 10 turns and on every exit path, collated into one JSON envelope per run, and
uploaded over HTTPS so the designer can analyse real playthroughs (friends demo → itch
demo). No gameplay effect whatsoever.

---

## 0. Why this exists (design intent)

The balance harness answers "what does the sim do"; telemetry answers **"what do players
actually do"** — where they stall, when they take loans, which tiers they climb, which
victory tracks they chase, and when they quit. One row per turn is enough to reconstruct
the whole arc of a run.

Design pillars:

- **Pure observer.** Telemetry reads sim state via the same signals every other
  turn-flow autoload uses. It never mutates sim state, never touches a sim RNG, never
  runs logic in `_process` (architecture contract invariants 2, 3, 5).
- **Consent first, anonymous always.** Nothing is captured — not even to local disk —
  until the player opts in. No names, no emails, no hardware IDs. One random UUID per
  install so runs from the same person can be grouped.
- **Crash-proof by spooling, not by blocking.** Rows are flushed to a local `.jsonl`
  every 10 turns; finished envelopes go to a local outbox; the outbox is retried on the
  next launch. The quit path never hangs waiting for a network call.
- **`RunMetrics` is the blueprint.** `scripts/run_metrics.gd` already snapshots a
  per-turn CSV row locally with exactly the right signal wiring. TelemetryState mirrors
  its shape; RunMetrics itself stays as-is (it is the dev/headless tool, telemetry is
  the shipped one).

---

## 1. What gets captured

### 1.1 Per-turn row (one dict per completed turn)

Snapshotted on `TurnManager.turn_resolution_completed`, using the cached
`Production.last_turn_summary`. At that point `current_turn` has already advanced, so
the row's turn is `TurnManager.current_turn - 1` (same fix as
`run_metrics.gd:346 _metrics_turn()`).

| field | type | source |
|---|---|---|
| `turn` | int | `TurnManager.current_turn - 1` |
| `money` | float | `MatchState.money` |
| `revenue` | float | `summary.goods_sales_revenue + summary.power_sales_revenue` (mirrors `production.gd:541`) |
| `profit` | float | retained post-tax profit: `(money_in − money_out) − taxes_paid − dividends_paid − profit_sharing_paid` (mirrors `SolvencyState._post_tax_profit`) |
| `loans` | float | `LoanState.total_outstanding()` (`loan_state.gd:198`) |
| `buildings` | int | count of player-owned entries in `MatchState.buildings` (see §5 note) |
| `power_gen` | int | `summary.power_supply` |
| `power_use` | int | `summary.power_demand` |
| `tiers` | Array[int], 5 | units produced this turn summed by goods tier, order `[raw, processed, intermediate, finished, apex]` (see §1.2) — derivable from `produced`, kept as a precomputed rollup for cheap sheet pivots |
| `produced` | Dictionary, **sparse** | per-good units produced this turn: shallow copy of `summary.produced` minus the `"power"` key. Only goods actually produced appear — a good's absence *means* 0; the client **never** sends ~70 zero-filled labelled fields (zeros are the server's job, see §6.1) |
| `victory` | Array[int], 5 | per-track score 0–1000, order `VictoryState.TRACK_ORDER` = `[autarkic, logistics, richest, widest, greenest]`: `round(track_best[key] * 1000)` |
| `playtime_s` | int | total wall-clock seconds this run has been played, across sessions (see §1.3) |
| `session` | int | session ordinal for this run (1 = first sitting, increments on each load) |

~120 bytes of fixed fields plus ~18 bytes per distinct good produced (a mid-game turn
produces ~10–30 distinct goods → ~0.2–0.6 KB/row). A full 300-turn run is ~100–200 KB.
Never a payload problem; capture cost of the `produced` copy is a µs-scale
`Dictionary.duplicate()` of an already-computed dict.

### 1.2 Tier tally

`summary.produced` is already a per-good units dict (`production.gd:785`). At first
snapshot, build a `good_id -> tier_index` lookup from the Catalog's
`goods_graph_tier` column (missing value → `intermediate`, matching
`goods_flow_graph.gd:166`); exclude the `"power"` key. Then each turn is a single pass:

```gdscript
var tiers := [0, 0, 0, 0, 0]
for good_id in summary.produced:
    if good_id == "power":
        continue
    tiers[_tier_index.get(good_id, 2)] += int(summary.produced[good_id])
```

### 1.3 Playtime

No playtime tracking exists today. TelemetryState keeps:

- `_session_start_msec := Time.get_ticks_msec()` set on run start / run load,
- `playtime_carried_s: int` — accumulated seconds from previous sessions, restored
  from the save (§4).

Per-row `playtime_s = playtime_carried_s + (ticks_msec − _session_start_msec) / 1000`.
Wall clock, pause menu included — good enough for playtest analysis; note as a known
simplification.

### 1.4 Run envelope (what actually gets uploaded)

One JSON object per run, built by collating the cached rows:

```json
{
  "schema": 1,
  "player_id": "a3f1…",            // random 32-hex-char UUID, per install, from PlayerProfile
  "run_id": "9c02…",               // random UUID, per playthrough, stored in the save
  "session_id": "d410…",           // random UUID, per app launch
  "sent_at": 1784591990,           // client unix time, stamped at upload; re-stamped on outbox retry
  "client": { "version": "0.1.0", "os": "macOS" },
  "run": { "start": "west_coast", "difficulty": "normal", "started_at": 1784505600 },
  "end": { "reason": "victory", "turn": 143, "run_complete": true, "ended_at": 1784591987,
            "victory": [1000, 320, 1000, 410, 180], "won_turn": 143 },
  "turns": [ { "turn": 2, "money": 214.0, "...": "…" }, "…" ]
}
```

`end.reason` ∈ `victory | turn_cap | bankruptcy | quit_to_menu | quit_to_desktop |
window_close`. `run_complete` is true only for the first three. A quit-to-menu envelope
is a *checkpoint*: the run may resume from a save later and produce another envelope
with the same `run_id` — analysis keeps the longest/latest per `run_id` (§6.4).

IDs are generated with `Crypto.generate_random_bytes(16).hex_encode()` — **not** any
sim RNG, so determinism (invariant 3) is untouched.

Three timestamps, deliberately distinct: `end.ended_at` (client clock — when the run
actually finished), `sent_at` (client clock — when this upload attempt fired), and
`received_at` (server clock, stamped by `doPost` — the only trustworthy one). Because
the outbox can hold an envelope for days before a player relaunches, "when it happened"
and "when it arrived" genuinely diverge; analysis uses `ended_at` for gameplay
chronology and `received_at` for data-quality checks (a wildly wrong client clock shows
up as `ended_at` ≫ `received_at`).

---

## 2. Consent — first-launch popup, not a quit popup

**Decision: ask once, at the main menu, before the first New Game.** A quit-time popup
is the wrong shape for three reasons: consent must *precede* collection (rows are
cached during play), the close path should stay instant (`SessionLog` already flushes
synchronously there and nothing may block it), and a crash skips any quit popup
entirely.

- **UI:** clone the `tutorial_prompt_dialog.gd` pattern (modal over the main menu,
  instantiated by `main_menu.gd` — same slot where the "proceed without the Tutorial?"
  gate lives). Shown when `PlayerProfile.telemetry_consent == "unset"` on pressing
  **New Game**, before the new-game panel. Two buttons, no default-on:
  - **"Share anonymous data"** → `granted`
  - **"No thanks"** → `declined`
- **Copy (draft):** *"Help balance Carbon and Capital? If you opt in, the game records
  anonymous gameplay statistics — per-turn economy numbers like revenue, buildings and
  score — and sends them to the developer when a run ends. No personal information,
  ever. You can change this any time on the New Game screen."*
- **Changeable later:** one `CheckBox` row on the New Game panel
  (`new_game_panel.gd` already builds checkbox rows for the tutorial toggle,
  `:389-409`) reflecting/writing the profile flag. This doubles as the "settings"
  surface until a real settings screen exists.
- **Storage:** three new `PlayerProfile` fields beside `tutorial_completed`
  (`player_profile.gd:15-25`), persisted in `profile.json` via the existing atomic
  `_save()`:

```gdscript
var telemetry_consent: String = "unset"   # "unset" | "granted" | "declined"
var telemetry_consent_version: int = 0    # bump if the consent copy materially changes
var telemetry_player_id: String = ""      # UUID minted on first grant
```

- **Gate:** every TelemetryState entry point early-returns unless consent is
  `granted`. Revoking consent stops capture immediately and deletes the local
  `telemetry/` cache and outbox.

---

## 3. TelemetryState autoload — capture and caching

New autoload `scripts/telemetry_state.gd`, registered after `SessionLog` in
`project.godot`. Wiring copies `RunMetrics`/`SolvencyState` exactly:

```gdscript
func _ready() -> void:
    enabled = DisplayServer.get_name() != "headless"       # solvency_state.gd:39 idiom
    if not enabled:
        return
    await get_tree().process_frame
    Production.turn_processed.connect(_on_turn_processed)              # cache summary
    TurnManager.turn_resolution_completed.connect(_on_turn_completed)  # snapshot row
    TurnManager.game_ended_signal.connect(_on_game_ended)              # turn_cap
    VictoryState.victory_achieved.connect(_on_victory)                 # victory
    SolvencyState.bankruptcy_declared.connect(_on_bankruptcy)          # bankruptcy
    MatchState.state_reset.connect(_on_state_reset)                    # new run / load
```

State: `_rows: Array[Dictionary]` (unflushed rows), `run_id`, `session_id`,
`playtime_carried_s`, `_session_start_msec`, `_tier_index`.

### 3.1 Disk cache — every 10 turns and on every exit

- Rows append to `<AppPaths base>/telemetry/run_<run_id>.jsonl` (one JSON object per
  line, `FileAccess` append + `flush()`), sibling of the existing `logs/` and
  `savegames/` dirs.
- **Flush triggers:** `(turn % 10) == 0` after a row is captured (same cadence as the
  autosave rotation in `save_load.gd:27`), plus every end/exit path in §3.3. Between
  flushes at most 10 rows (~1 KB) are at risk — and even those only to a crash.
- Appending line-by-line (rather than rewriting a JSON array) means a crash mid-write
  loses at most one line and never corrupts the file.

### 3.2 Performance budget (why this cannot repeat the verbose-log slowdown)

The verbose debug logs cost 100+ ms because they did O(buildings × goods) work per
turn — thousands of formatted strings, `print()` calls and per-line I/O. Telemetry is
O(1) per turn: **one** dict of ~12 numbers, almost all lifted from the
already-computed `summary`. The budget, per cost site:

| site | work | cost | when |
|---|---|---|---|
| per-turn snapshot | ~30 dict reads + one pass over `MatchState.buildings` (owner check) + one pass over `summary.produced` (tier tally) | **< 0.5 ms**, dominated by the buildings pass — which VictoryState already pays every turn for `history_buildings` | on `turn_resolution_completed` |
| 10-turn flush | stringify 10 small dicts, one ~1 KB append + `flush()` | sub-ms; **`call_deferred`** so it lands on the frame *after* resolution, off the end-turn critical path | every 10th turn |
| end-of-run collation | `JSON.stringify` the in-memory rows (300 rows incl. sparse `produced` ≈ 100–200 KB; native C++ path) | ~2–5 ms, **once**, on the end screen where nothing is time-critical | run end |
| upload | `HTTPRequest` with `use_threads = true`; network + TLS happen off the main loop | no measurable main-thread cost | run end / boot retry |

Rules that keep it that way:

- Rows live **in memory** (`_rows`; 300 dicts is well under 1 MB). The `.jsonl` is
  crash recovery only — the happy path never reads it back.
- Never `print()`, never per-building or per-good *rows*, never a nested
  buildings × goods loop. Lifting more precomputed `summary` values is ~1 µs per
  field; each *additional full pass* over all buildings costs ~0.1–0.3 ms — the row
  can grow a lot before either matters (see §10 headroom note).
- **Acceptance gate:** measured with TurnProfiler on a 50+-building save (never
  editor numbers — `cnc-performance-playbook` discipline), capture adds **< 1 ms** to
  turn resolution. If it doesn't, that's a bug in the implementation, not a cost of
  the feature.

### 3.3 End-of-run and exit hooks

| event | hook | action |
|---|---|---|
| Victory | `VictoryState.victory_achieved` (end screen mounts via `bottom_menu.gd:465`) | flush, build envelope (`victory`, complete), enqueue, upload now |
| Turn cap defeat | `TurnManager.game_ended_signal("turn_cap_reached")` | same, reason `turn_cap` |
| Bankruptcy | `SolvencyState` game-over path | same, reason `bankruptcy` |
| Exit to Main Menu | `pause_menu.gd:129` (add one call) | flush, envelope reason `quit_to_menu` (checkpoint), enqueue, upload now |
| Exit to Desktop | `pause_menu.gd:134` (beside `SessionLog.flush()`) | flush + envelope to outbox; **no network wait**, `get_tree().quit()` proceeds |
| Window X | `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` (same pattern as `session_log.gd:72`) | synchronous flush + envelope to outbox only |
| App relaunch | `_ready` | retry everything in the outbox (§6.3) |

The two hard-quit paths write to disk only. The envelope uploads on the next launch —
friends who play a demo launch it again; nothing is lost, and quitting never stalls.

---

## 4. Save integration (additive, no version bump)

A resumed save must keep its `run_id` and accumulated playtime. One new top-level
snapshot key, tolerant-reader like every other system (`save_load.gd:58-87`):

```gdscript
"telemetry": { "run_id": run_id, "playtime_s": playtime_total_s }
```

Missing key (old save) → mint a fresh `run_id`, playtime 0. Consent itself lives in
the profile (§2), **never** in the save. `SAVE_VERSION` stays 6.

Reload-and-replay means the same `(run_id, turn)` can be captured twice with different
values. That is fine: rows are append-only and the analysis dedupes per `(run_id,
turn)` keeping the latest (§6.4). Don't fight it client-side.

---

## 5. Small engine touch-ups required

- **`MatchState._player_building_count()`** (`match_state.gd:4888`) is private and
  VictoryState already duplicates the loop. Promote it to public
  `player_building_count()` and let both VictoryState and TelemetryState call it.
- **`application/config/version`** in `project.godot` — set it (e.g. `0.1.0`) so the
  envelope can report `ProjectSettings.get_setting("application/config/version",
  "dev")`. Bump it per distributed build; it is what makes cross-build comparisons
  possible.
- **Cheat** `telemetry` in the debug terminal: prints consent state, run_id, cached
  row count, outbox contents, last upload result; `telemetry send` forces an outbox
  retry. Mirrors the `win` / `skip` cheat pattern.

---

## 6. Transport and backend

### 6.1 Decision: Google Apps Script Web App → Google Sheet

**Recommended.** Free, zero infrastructure, five-minute setup, and the analysis tool
*is* the storage (pivot tables / charts in the Sheet, or export CSV into
`tools/`-style Python). Email is rejected outright: it would ship SMTP credentials in
the client, deliverability is flaky, and parsing mailboxes is miserable. A tiny PHP
endpoint on the existing Carbon-and-Capital FTPS hosting would also work (append to a
`.jsonl`), but then uptime, TLS and retrieval are yours; PostHog/GameAnalytics add
dashboards but force an events model that fits per-turn arrays badly and add a vendor.
Apps Script is the right size for a friends/itch demo. Revisit only if volume ever
exceeds ~20k uploads/day (the free execution quota) — it won't.

- Google Sheet with two tabs:
  - **`runs`** — one row per envelope: received_at, player_id, run_id, session_id,
    version, os, end_reason, run_complete, final_turn, playtime_s, victory total,
    plus the raw envelope JSON in the last column (nothing is ever thrown away).
  - **`turns`** — one row per turn: the fixed fields first, then **one column per
    good** (dense — the sparse `produced` dict is exploded here, blanks filled with
    0). The **header row is the source of truth** for good columns: `doPost` reads
    it, maps each row's `produced` onto it, and auto-appends a new header column the
    first time it sees an unknown good id — so adding goods to the game never needs a
    script redeploy.
- **Cell budget (the one real limit per-good columns introduce):** a Google
  spreadsheet caps at 10 M cells. ~12 fixed + ~76 good columns ≈ 88 cols → ~113k
  turn-rows ≈ **~380 full 300-turn runs** (over 1000 typical shorter runs) per
  spreadsheet. Plenty for the friends demo; for itch, rotate to a fresh spreadsheet
  per build version (natural anyway — just redeploy the script bound to the new
  sheet, or point the same script at a new sheet id). If volume ever makes rotation
  annoying, the fallback is collapsing `produced` into one `good:qty|good:qty` cell
  (14 cols ≈ 2400 full runs) and exploding in Python instead.
- `doPost(e)` sketch (paste into a bound Apps Script, deploy as Web App, "execute as
  me", "anyone with the link"; `turns` header row pre-seeded with the fixed columns):

```javascript
const TOKEN = "…long random string…";
const FIXED = ["run_id", "session_id", "turn", "money", "revenue", "profit", "loans",
               "buildings", "power_gen", "power_use", "tiers", "victory", "playtime_s"];
function doPost(e) {
  const p = JSON.parse(e.postData.contents);
  if (p.token !== TOKEN) return ContentService.createTextOutput("no");
  const ss = SpreadsheetApp.getActive();
  ss.getSheetByName("runs").appendRow([new Date(), p.player_id, p.run_id,
      p.session_id, p.client.version, p.client.os, p.end.reason,
      p.end.run_complete, p.end.turn, JSON.stringify(p)]);
  const sh = ss.getSheetByName("turns");
  const header = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
  const seen = new Set(header);
  p.turns.forEach(t => Object.keys(t.produced || {}).forEach(g => {
    if (!seen.has(g)) { seen.add(g); header.push(g);
        sh.getRange(1, header.length).setValue(g); }        // new good → new column
  }));
  const rows = p.turns.map(t => header.map((col, i) => {
    if (i >= FIXED.length) return (t.produced || {})[col] || 0;   // good columns
    if (col === "run_id") return p.run_id;
    if (col === "session_id") return p.session_id;
    if (col === "tiers" || col === "victory") return t[col].join("|");
    return t[col];
  }));
  if (rows.length)
    sh.getRange(sh.getLastRow() + 1, 1, rows.length, header.length).setValues(rows);
  return ContentService.createTextOutput("ok");
}
```

- The deploy URL + token are consts at the top of `telemetry_state.gd`. They are not
  secrets — the token exists only to keep drive-by junk out of the sheet. Accept that
  a motivated player can post fake data; irrelevant at this scale.

### 6.2 Client upload

First networking code in the project (nothing exists to copy). One `HTTPRequest` node
created by TelemetryState on itself:

```gdscript
func _upload(envelope: Dictionary) -> void:
    var http := HTTPRequest.new()
    add_child(http)
    http.use_threads = true
    http.timeout = 10.0
    http.max_redirects = 0        # the 302 itself is the success signal (see below)
    http.request_completed.connect(_on_upload_done.bind(http, envelope_path))
    var body := JSON.stringify(envelope)          # token injected into the dict
    http.request(ENDPOINT_URL, ["Content-Type: application/json"],
                 HTTPClient.METHOD_POST, body)
```

Async, fire-and-forget; on success the outbox file is deleted, on anything else it
stays for the next retry. No retry loops, no backoff — the outbox *is* the retry.

Exported-build gotchas — **all verified live 2026-07-20** against the real endpoint
(`tools/telemetry/poc_send.tscn`, curl cross-check):

- **Apps Script answers a POST with a 302 redirect** (to `script.googleusercontent.com`,
  where the `ContentService` response body lives). `doPost` has *already executed* by
  the time the redirect is issued, so the 302 itself is the success signal. Set
  `max_redirects = 0` and don't fetch the body — the one-time response URL is flaky
  for non-browser clients (curl following it intermittently got a Google error page
  even though the write had succeeded).
- **With `max_redirects = 0`, Godot reports the completion `result` as
  `RESULT_REDIRECT_LIMIT_REACHED` (12), NOT `RESULT_SUCCESS`** — the success check
  must key on `response_code == 302` (or a plain 200), never on the result enum.
- **TLS just works:** Godot's bundled Mozilla CA store handshakes with
  `script.google.com` with no certificate setup (verified from the headless engine on
  macOS).

### 6.3 Outbox spool

- Envelope files: `<AppPaths base>/telemetry/outbox/<run_id>_<unix>.json`, written
  atomically (temp + `DirAccess.rename_absolute`, the `player_profile.gd:101` idiom).
- On every app launch (and on return to main menu), if consent is granted and the
  outbox is non-empty: upload each file, delete on success. Offline players simply
  accumulate a few KB until they're online.
- The per-run `.jsonl` cache is deleted once its final (`run_complete`) envelope is
  confirmed uploaded; checkpoint envelopes keep it.

### 6.4 Analysis-side contract

- Dedupe on `(run_id, turn)` keeping the row from the latest `session_id` /
  received_at — handles save-reload replays and checkpoint-then-final double sends.
- For run-level stats prefer the latest envelope per `run_id` (highest `end.turn`).
- `tiers` / `victory` are pipe-joined in the sheet (`10|20|50|100|4`) — split in the
  pivot/Python layer.

---

## 7. Privacy posture

- Opt-in only, off by default, revocable; revocation deletes local caches.
- Collected: the §1 economic fields, run config (start/difficulty), game version, OS
  family string, random IDs. **Not collected:** names, emails, IPs (Apps Script does
  not expose caller IP to the script), hardware IDs, locale, save contents.
- The itch page / README gets one sentence stating the above, mirroring the consent
  copy. This posture (anonymous + opt-in + disclosed) is comfortably on the right
  side of GDPR for a playtest; revisit if telemetry ever grows identifying fields.

---

## 8. Testing

- **Headless:** TelemetryState is disabled headless (§3), so the unit suite and the
  e2e harness are untouched. The snapshot builder (`_build_row(summary) ->
  Dictionary`) and the tier tally are pure functions of a summary dict — unit-test
  them directly with a hand-built summary (assert field mapping, tier bucketing,
  turn-number off-by-one).
- **Integration:** windowed run with the `telemetry` cheat — play 12 turns, confirm
  `run_<id>.jsonl` has 12 lines and flushed at turn 10; exit to menu, confirm an
  outbox envelope with reason `quit_to_menu`; relaunch against a scratch Apps Script
  deployment and confirm the sheet rows land and the outbox empties.
- **Editor guard:** uploads are skipped when `OS.has_feature("editor")` (dev runs
  would pollute the dataset); the local cache still writes so the cheat can inspect
  it. `telemetry send` overrides the guard for the integration test.

---

## 9. Build order (re-phased 2026-07-20: transport first, capture second)

1. **Phase 0 — backend: DONE.** Live Apps Script endpoint + Sheet, verified from
   curl and the engine (`tools/telemetry/`).
2. **Phase A — close-path export skeleton: BUILT 2026-07-20.**
   `scripts/telemetry_state.gd` autoload: arm-on-`state_reset` (first-resolved-turn
   fallback), finalize-once lifecycle (window X / `quit()` teardown / re-arm =
   quit-to-menu), minimal envelope (ids, client version/os, timestamps, playtime,
   end reason, turn, empty `turns`), atomic outbox spool, boot-time retry upload,
   `application/config/version`, `TELEMETRY_DEBUG=1` override for headless
   verification, `tools/telemetry/flush_outbox.tscn` drain tool.
   **No consent gate yet — phase-A builds must not ship to players.**
3. **Phase B — per-turn capture:** the §1.1 rows (tier index, sparse `produced`,
   victory array), 10-turn jsonl cache, envelope collation from `_rows`, save-key
   `telemetry` (run_id + playtime across sessions), TurnProfiler acceptance gate.
4. **Phase C — consent + identity:** PlayerProfile fields, first-launch popup, New
   Game panel checkbox, real per-install `player_id`, editor-build upload guard +
   `telemetry` cheat. Gate every phase-A/B entry point on consent. Ship blocker.
5. **Phase D (optional):** mid-run checkpoint upload every 100 turns, settings
   surface, a Python report script reading the sheet's CSV export.

---

## 10. Open questions

- **Seed in the envelope?** Cheap and useful (`MatchState.match_rng_seed`) for
  replaying interesting runs in the harness — include unless there's a reason not to.
- **NPC-side aggregates** (NPC building count, market price snapshots) would fatten
  rows ~2× but enable "player vs economy" analysis. Deferred; additive when wanted —
  per-good `produced` (§1.1) already proved the pattern: sparse dict client-side,
  header-driven columns server-side, µs-scale capture cost. The practical ceiling on
  row growth is the sheet's 10 M-cell budget (§6.1), not processing.
- **Consent re-prompt** when `telemetry_consent_version` bumps: silently treat as
  `unset` again, or show a "what changed" dialog? Current lean: treat as unset.
