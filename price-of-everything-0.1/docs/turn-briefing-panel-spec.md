# Turn Briefing panel — design spec

Status: DRAFT for owner review · 2026-07-08
Related: `docs/decision-events-spec.md` (reworks its presentation surface, §7),
`scripts/event_scheduler.gd`, `scripts/notification_bell.gd`, `scripts/decision_state.gd`,
`scripts/solvency_state.gd`, `scripts/production.gd`
Supersedes as the *primary* surface: the standalone decision modal
(`decision_dialog.gd`), the bridge-loan popup (`bridge_loan_popup.gd`), and the
research-unlocked toast — all become items inside this one panel.

---

## 1. What it is

One **mid-screen, large panel** that is the single place the player looks at the start
of a turn to see *everything that needs their attention or a decision this turn*:

- **Decisions** — one or several (with a mini-menu to move between them).
- **Narrative events** — the carbon-tax three-act beats (new government, tax announced,
  implemented, green subsidy, wind-down), and any other scheduled announcements.
- **Research unlocked** — what you can now build/produce.
- **Other popups** — the auto-bridge loan notice, buildings completed, the rolled-up
  sales summary, deposit exhausted, etc.
- **Critical states** — bankruptcy looming, N buildings starved, tiles at capacity —
  the live warnings the player must act on.

It is a **hybrid of the decision modal and the notification bell**: the bell stays as
the always-available ambient *log*; the Briefing is the turn-scoped, prioritized,
*actionable* digest that auto-opens when the turn begins. Everything the player must
decide or acknowledge this turn is merged here instead of arriving as a stack of
separate modals and toasts.

### Goals
- Replace the "modal, then popup, then toast, then another modal" pile-up with one
  coherent surface.
- Support **more than one decision at once** (today the pulse presents exactly one; the
  Briefing is the reason to allow a small queue).
- Fold the critical-status readouts (bankruptcy runway, starvation) into the same place,
  so "what's wrong" and "what to decide" live together.
- Close off the modal-soft-lock class (see the July incident) — the Briefing is
  responsive and, once decisions are answered, dismissible/re-openable.

### Non-goals (v1)
- It does not replace the **notification bell** (the ambient log) or the **game-over
  screen** (terminal, stays separate and full-screen).
- No new *content* — it re-hosts existing events/decisions. The carbon-tax mechanic
  itself is still PENDING; the Briefing is just its future delivery surface.

---

## 2. Layout

A centred panel, roughly 70% width × 70% height, DS-themed (navy card, cream outline;
match the research panel), responsive (clamp to viewport − margin; the content column
scrolls). Three regions:

Collapsed (default on non-critical turns) — a strip under the top bar:
```
        ┌───────────────────────────────────────────┐
        │  ⚖ ⚖   ● 1 crit   ▲ 1 warn            ▾    │   ~300 × 50, centred
        └───────────────────────────────────────────┘
```
Expanded (auto on critical turns, or on click):
```
┌───────────────────────────────────────────────────────────────────────┐
│  THIS TURN — Turn 51                                    Cash £1,240  ▾  │  header (▾ = collapse)
├───────────────┬───────────────────────────────────────────────────────┤
│ DECISIONS (2) │                                                         │
│  ▸ Union pay… │   [ detail of the selected item fills this area ]       │
│  ▸ Broker off │                                                         │
│ ALERTS        │   • a decision → its choice columns (advocate cards)    │
│  ⚠ Bankruptcy │   • an event   → title, body, a Go-to deep-link         │
│  ⚠ 12 starved✕│   • research   → what unlocked + "Open research"  ✕      │
│ NEWS          │   • a critical → readout + "View" deep-link  ✕           │
│  ◔ Carbon tax │     (✕ = Dismiss — on everything EXCEPT decisions)       │
│ INFO          │                                                         │
│  ✓ Bridge loan✕                                                         │
├───────────────┴───────────────────────────────────────────────────────┤
│  “2 decisions must be answered before you can end the turn.”  [ ▾ Collapse ] │
└───────────────────────────────────────────────────────────────────────┘
```

- **Header**: title + turn number + live cash + a **collapse caret ▾** (always
  available — shrinks to the strip; there is no scrim, §4.1).
- **Left mini-menu**: sectioned list. Each row: a type icon, a one-line title, a status
  glyph (● unresolved decision · ⚠ active alert · ◔ needs ack · ✓ seen), and — on every
  row **except decisions** — a small **✕ Dismiss** (§4.2). Decisions pinned at the top.
  Selected row highlighted; keyboard ↑/↓ navigates.
- **Main detail**: the selected item's full content (§5); dismissible items carry a
  Dismiss button here too.
- **Footer**: a context line (e.g. "2 decisions must be answered before you can end the
  turn", or "All caught up") + a **Collapse ▾** button. Ending the turn is the normal
  End-Turn button, which stays blocked until decisions are resolved (§4.3) — there is no
  separate "Continue" that closes; closing = collapsing.

The mini-menu is the "select the different decisions" surface the brief asks for, and it
generalises to every item type.

---

## 3. The item model

Every entry is a `BriefingItem` view-object assembled fresh when the panel opens:

```
{
  id: String,               # stable per source (decision uid, event id, "alert:starved")
  kind: "decision" | "event" | "research" | "critical" | "info",
  section: "decisions" | "alerts" | "news" | "info",
  severity: "info" | "warning" | "critical",
  title: String,            # mini-menu row label
  blocking: bool,           # true only for decisions (gate commit_turn)
  resolved: bool,           # decisions: answered · events: acknowledged
  deeplink: Dictionary,     # {panel, tile_id, building_id} — reuse EventScheduler's shape
  source_ref: Variant,      # the pending decision / event dict / live accessor
}
```

The panel renders the mini-menu from the item list and the main area from
`source_ref` + `kind`. Items are **not** a new persisted store — they are a *view* over
the existing sources (§5), rebuilt on open and on any source change (coalesced refresh,
per the UI doctrine).

---

## 4. Collapse / expand and dismissal model (owner rulings, 2026-07-08)

### 4.1 Two states: expanded panel ↔ collapsed strip
The Briefing has two forms, not a hard modal:
- **Expanded** — the full mid-screen panel (§2).
- **Collapsed** — a compact **~300 × 50 px strip**, horizontally centred, docked as a
  row directly beneath the top bar (the top bar's middle is otherwise empty — money sits
  left, encyclopedia/turn-counter right). The strip shows icons/badges for what remains
  outstanding (§4.5). Clicking it (or its expand caret) re-opens the full panel.

The panel is **not** a scrim-locked modal. Collapsing is always available (a caret in the
header), which is also why this design cannot reproduce the July soft-lock — there is
always an escape to the strip, and an empty briefing collapses to nothing.

### 4.2 Per-item dismissal (owner ruling)
- **Decision items — NOT dismissible.** No per-item close; the only way to clear a
  decision is to **resolve** it (pick a choice). They persist in the panel and in the
  collapsed strip until answered.
- **Everything else — dismissible.** Research, starved-building alerts, bridge-loan
  notices, completions, sales, capacity/deposit warnings each get a **Dismiss** control
  in their detail (and the mini-menu row). Dismiss = "acknowledge / clear from the
  briefing." For live-state alerts (starvation, bankruptcy runway) dismiss clears it for
  now; it **re-surfaces only if the condition newly worsens** (e.g. more buildings starve,
  or runway drops another band) — so chronic conditions don't nag every turn. The
  notification bell keeps the underlying event regardless (single source of truth).

### 4.3 Turn-blocking (unchanged guarantee)
Unresolved decisions still block **ending the turn**: `TurnManager.commit_turn()` refuses
while any decision is pending (today's `DecisionState.has_pending()` guard, generalised to
the queue). If the player tries to end the turn with decisions outstanding, the Briefing
auto-expands to them. So you can defer a decision *within* the turn (collapse, do other
things) but you **cannot end the turn until every decision is answered**.

> Change from decision-events-spec §13: the earlier ruling was "answer now, no acting
> first" (a hard inescapable modal). Allowing collapse relaxes that to "answer before
> turn-end" — a player can now act before answering, which reopens a mild gaming window
> (raise cash, then answer). This is a deliberate UX trade the owner is choosing; noting
> it so the two specs don't silently disagree.

### 4.4 Auto-expand only on "critical" turns
On DECIDE start the Briefing **auto-expands only on a critical turn**; otherwise it stays
**collapsed** as the strip. A turn is critical when it contains either:
- at least one **unresolved decision** (they block the turn, so the player must see them), or
- a **new or newly-worsened critical-severity alert** (bankruptcy looming crosses the
  runway threshold; buildings starve that weren't starved last turn).

Pure info/warning turns (research unlocked, sales, a completion, unchanged chronic
starvation) do **not** auto-expand — they just update the collapsed strip's badges, and
the player opens the panel when they choose. This keeps the panel from nagging while
still forcing attention when it matters.

### 4.5 The collapsed strip (contents)
Left-to-right within the ~300 × 50 strip:
- one **decision icon per outstanding decision** (up to ~4, then "+k"), tinted by the
  decision's category; a filled dot marks unanswered — this is the persistent reminder
  that the turn is blocked;
- a **criticality cluster**: a red badge with a count for critical alerts, an amber badge
  for warnings (bankruptcy/starvation/capacity), each opening the panel on that item;
- the strip's border pulses once when a new critical item arrives while collapsed.
Empty briefing → the strip is hidden entirely.

---

## 5. Item types and their data sources

### 5.1 Decisions (`section: decisions`, blocking)
- Source: `DecisionState`. **Change required**: today it holds a single `pending`; the
  Briefing wants a small queue. Introduce `DecisionState.pending_queue: Array` (cap ~4)
  fed by the pulse and by forced/story draws, so several can coexist (e.g. a pulse
  decision plus a story beat, or the distressed-asset offer stacking on an ambient one).
  `pending_view()`/`resolve()` become keyed by decision uid.
- Detail area: the existing choice-column layout (advocate portrait, stance, loyalty
  stakes, consequence, lock/loan notes) — lift the builders out of `decision_dialog.gd`
  into a shared `decision_choice_cards.gd` the Briefing embeds.
- On resolve: mark the item ✓, auto-advance the selection to the next unresolved
  decision; when the last one resolves the footer's blocking hint clears.
- The pulse *reveal* fires the Briefing to **auto-expand** (a decision makes the turn
  critical, §4.4): `DecisionState._maybe_present` requests expand instead of mounting the
  old modal.

### 5.2 Narrative events / announcements (`section: news`)
- Source: `EventScheduler` scheduled events (the carbon arc registers these). Events may
  be **pure announcements** (acknowledge to mark ✓) or **carry a decision** (then they
  are authored as a DecisionState story beat and appear in the Decisions section
  instead). The Briefing shows the announcement body + any `deeplink` (e.g. "Open
  Politics") and an **Acknowledge** action.
- Carbon-tax beats (govt turn 80, announce 85, implement 90, subsidy 95, wind-down 175)
  are the flagship consumers — see §11.

### 5.3 Research unlocked (`section: info`)
- Source: the existing `research_unlocked` EventScheduler events
  (`_on_unlock_granted`, via `MatchState.unlock_granted`). Detail: what unlocked +
  a "Open research" deep-link. Auto-marks ✓ when seen; low priority.

### 5.4 Critical states (`section: alerts`, live, non-dismissible)
These reflect **live conditions**, not one-off events — they persist while the condition
holds and clear themselves when it resolves. They cannot be "resolved" from the panel,
only addressed by play; they carry deep-links.
- **Bankruptcy looming**: `MatchState.money + LoanState.available_capacity() <
  BANKRUPTCY_IMMINENT_RUNWAY` (the same runway the top-bar strip uses). Detail: runway
  breakdown (cash, borrowing room), "you cannot bridge a shortfall past this."
- **Buildings starved**: count from `Production.blocked_reason_by_building` /
  `missing_by_building`, split power vs inputs (mirrors the bell's
  `grouped_active()` "N Buildings Starved of …"). Detail: the list, each row deep-linking
  to the building (`MatchState.focus_building_requested`).
- **Tiles at capacity**, **deposit exhausted**: from their EventScheduler events.

### 5.5 Other popups / info (`section: info`)
- **Auto-bridge loan** (`SolvencyState._show_bridge_popup`): becomes an info item —
  "Bridge loan of £X taken · capacity left £Y" — instead of its own popup.
- **Buildings completed**, **sales arrived** (rolled-up): from their EventScheduler
  aggregate events; info, auto-✓.

---

## 6. Assembly and ordering

When the panel opens (or a source changes), it builds the item list deterministically:

1. **Decisions** — in draw order (the pulse/queue order). Always first; blocking.
2. **Alerts** (critical live states) — by severity: bankruptcy > power-starvation >
   input-starvation > capacity > deposit-exhausted.
3. **News** (announcements needing acknowledgement).
4. **Info** (research, bridge loan, completions, sales) — newest first.

The initially-selected item is the first unresolved decision, else the highest-severity
alert, else the first news item. Section headers show counts ("DECISIONS (2)",
"ALERTS (2)"). Empty sections are hidden. If the whole list is empty, the panel does not
open at all.

Dedup with the bell: Briefing items that come from EventScheduler share the event id, so
dismissing in the Briefing calls `EventScheduler.dismiss(id)` and the bell updates too
(single source of truth). Live-state alerts (starvation, bankruptcy runway) **are**
dismissible from the Briefing per §4.2 — dismiss clears them from the briefing until the
condition worsens; the bell still reflects the raw state. Only **decisions** cannot be
dismissed (resolve-only).

---

## 7. Relationship to existing surfaces

| Surface | Role after this ships |
|---|---|
| **Turn Briefing** (new) | Lives as the collapsed strip under the top bar; auto-**expands** only on critical turns (§4.4). The actionable, prioritized, turn-scoped digest. Hosts decisions + alerts + news + info. |
| **Notification bell** (`notification_bell.gd`) | Unchanged role: the always-available ambient **log** of active events, reachable any time. The Briefing and bell read the same EventScheduler state; the Briefing adds decisions + live critical states on top. |
| **Decision modal** (`decision_dialog.gd`) | Retired as a standalone surface; its choice-card builders move into the Briefing. |
| **Bridge popup** (`bridge_loan_popup.gd`) | Retired; becomes an info item. |
| **Game-over** (`game_over_panel.gd`) | Unchanged — terminal, separate full-screen. |
| **Top-bar "Bankruptcy imminent" strip** (under the money widget) | Kept as the at-a-glance flag; clicking it expands the Briefing on the bankruptcy alert. It sits left (under money); the Briefing strip is centred — they coexist. |

**HUD entry point**: the **collapsed strip itself is the persistent entry point** — it's
always there (centred, under the top bar) whenever the briefing is non-empty, so the
player re-opens by clicking it. No separate button needed; the strip's decision icons
double as the unresolved-count badge.

---

## 8. Architecture

- New autoload **`TurnBriefing`** (`scripts/turn_briefing.gd`), sim-adjacent but
  view-only: it assembles the item list from `DecisionState`, `EventScheduler`,
  `SolvencyState`, `Production`, and mounts the panel. It owns no persisted state of its
  own beyond a per-turn "acknowledged event ids" set (small; may piggyback on
  EventScheduler's dismissed state instead — see §9).
- New panel **`scripts/turn_briefing_panel.gd`** — DS-themed, responsive (the July
  lesson: clamp to viewport, scroll content, never a fixed oversized card), mounted on a
  CanvasLayer (~layer 135, below game-over 200).
- **`DecisionState`** gains the `pending_queue` (§5.1); `_maybe_present` opens the
  Briefing instead of the modal; `resolve(uid, choice)` keyed by uid.
- Reuse the deep-link contract: rows emit `MatchState.focus_building_requested` /
  `focus_tile_requested` (already wired) and panel-open requests for research/politics.
- Coalesced refresh (UI doctrine): rebuild once per frame on any of
  `DecisionState.pending_changed`, `EventScheduler.active_events_changed`,
  `MatchState.money_changed`, `LoanState.loans_updated`, `Production.turn_processed`.

Opens on `TurnManager.turn_advanced` (DECIDE start), like the decision modal does today.

---

## 9. Persistence

Mostly a **view** — little new saved state:
- Decisions already persist (`DecisionState`, now a queue instead of one `pending`;
  additive save change — bump only if the shape can't be tolerantly defaulted).
- Event ack/dismiss state already persists in `EventScheduler`.
- Live critical states are derived (never saved).
- If we track "acknowledged this turn" separately, it's an additive set; prefer reusing
  EventScheduler's `dismissed` state so there's one source of truth.

A save taken mid-DECIDE with unresolved decisions reloads with them intact and re-opens
the Briefing (same as the current modal behaviour on load).

---

## 10. Legibility & theming

Serves the project's "legibility is first-class" stance directly — one surface that
*explains the turn*. DS theme only (Title/Section/Body/Caption/Numeric, `DS.PALETTE`,
`DS.SP`), WPA/mid-century treatment matched to the research panel. Severity colour-codes
the mini-menu (critical = `DANGER`, warning = `WARN`, info = muted). Ships with a
screenshot tool (`tools/briefing_shot.tscn`) exercising: 2 decisions + a bankruptcy alert
+ a starvation alert + a carbon-tax news item + a research info item, at both a wide and
a 1024-wide window (regression guard for the soft-lock).

---

## 11. Carbon-arc integration

The Briefing is the delivery surface for the carbon three-act squeeze:
- **Announcements** (new government turn 80, tax announced 85, implemented 90, green
  subsidy 95, wind-down 175) are EventScheduler scheduled events → **news** items with an
  "Open Politics" deep-link and an Acknowledge.
- **Choices** the arc offers (e.g. "accept the transition grant with strings") are
  DecisionState story beats → **decision** items (blocking), reserved on their turn via
  `DecisionState.reserve()`.
- The **live carbon-tax burden** (once the mechanic ships) surfaces as an **alert**
  ("Carbon tax: £X/turn on coal & crude") with a deep-link to the market.
So the whole arc — warnings, decisions, and ongoing cost — reads from one place.

---

## 12. Migration

1. Extract decision choice-card builders from `decision_dialog.gd` into a shared module.
2. Add `DecisionState.pending_queue` + uid-keyed `pending_view`/`resolve`; keep the
   single-decision path working (a queue of one).
3. Build `TurnBriefing` + panel; route `_maybe_present` and the bridge/research surfaces
   into it behind a `swap briefing` cheat (the project's standard A/B pattern, like
   `swap bdp`) so it can be trialled against the current modals before cutover.
4. Cut over; retire the standalone modal + bridge popup; keep the bell.

---

## 13. Owner rulings (2026-07-08) and remaining questions

**Ruled:**
1. **Dismissal** — decisions are **not** dismissible (resolve-only); research, starved
   buildings and other info/alerts **are** dismissible in the panel (§4.2).
2. **Collapse** — the panel collapses to a **~300 × 50 strip, centred under the top bar**,
   showing outstanding-decision icons + criticality badges (§4.1, §4.5).
3. **Auto-expand only on critical turns** (an unresolved decision, or a new/worsened
   critical alert); otherwise stay collapsed (§4.4).

**Consequence to confirm:**
4. Allowing collapse **softens the earlier "answer now, no acting first" ruling** to
   "answer before ending the turn" (§4.3) — a player can act before answering, a mild
   gaming window. Confirm this trade is intended (it follows from wanting a collapsible
   hub). If not, the alternative is: collapse allowed, but the map/HUD stays input-locked
   while a decision is outstanding (collapse becomes "peek," not "act").

**Still open:**
5. **Max simultaneous decisions** — cap the queue at ~4? If the pulse would exceed it,
   hold the extra for a later turn (the pulse already spaces draws, so this is an edge
   case).
6. **What counts as "worsened"** for a live alert to re-surface after dismissal —
   starvation count increases by any amount, or by a band? Runway dropping one severity
   band? (Pick thresholds during build.)
