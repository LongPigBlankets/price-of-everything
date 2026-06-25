# Battery Storage — design spec (decided)

Status: **DESIGN AGREED, not yet implemented.** Supersedes the interim "battery consumes
1 lithium battery/turn" recipe (r_225) added to make the building buildable.

## Concept — deposit / locked capital

A battery building is **housing**. The player **loads battery goods** into it; the loaded
cells are **locked capital — not consumed each turn, and refunded** (returned to the tile
stockpile) when unloaded or when the building is demolished. The loaded cells are what
provide intermittency firming.

This replaces the current category+level firming (`_tile_storage_cap` =
`BATTERY_STORAGE_CAP[level]`). The level now sets a **cell-slot capacity**; firming comes from
the cells loaded into those slots.

- Housing slot capacity by level: **L1 = 100, L2 = 200, L3 = 320 slots** (reuse the existing
  `BATTERY_STORAGE_CAP` numbers as *slot counts*).
- Tile firming capacity = `Σ (loaded cells of type × CELL_DENSITY[type])`, capped by the tile's
  total housing slots. **CELL_DENSITY starts uniform at 1.0** (1 cell = 1 firming, so a full L1
  housing = 100 firming — matches today's behaviour). Density is a future differentiation lever
  if needed; the agreed differentiation is tech-tier + supply chain, not density.
- Firming feeds the existing intermittency allocation unchanged (it only reads
  `_tile_storage_cap`).

## The three battery types

The types differ by **tech tier** (when you can load them) and **supply chain** (what it costs
*you* to obtain the good). Because you load goods you produce or buy, the per-tile cost is
naturally your own supply-chain cost — no artificial cost/land knob is imposed.

| Type | Good | Tier | Role | Supply chain |
|---|---|---|---|---|
| **Lithium Ion** | `lithium_battery` (g_059, £60) | **T1** (quick, not turn-0) | All-rounder starter; priciest, longest chain | lithium ore → carbonate → battery (r_032 / r_099) |
| **Sodium Ion** | `sodium_battery` (g_060, £45) | **T2** power/storage | Lithium/REE-light alternative; best when REE/lithium-poor | salt + aluminium + graphite (r_102, exists) |
| **Iron Air** | `iron_battery` (g_061, £40) | **T3** power/storage | Mid-late; cheapest to manufacture; endgame bulk | **needs a production recipe (buy-only today)** |

The deposit UI only offers battery types the player has unlocked. Lithium is loadable once the
T1 node is taken (accessible early but not at game start); Sodium at T2; Iron Air at T3.

## Tech wiring (build-by-doing, `research_unlocks.csv`)

Tech tree already has a `Renewable Power` branch with battery nodes (Battery Balancing, L2/L3
unlocks) and a spare placeholder ("Containerised Battery Racks … available to repurpose").

- **T1 — Lithium storage**: low-bar gate so it's reachable quickly (e.g. `Run` a battery a few
  turns, or `Build` the first battery). Unlocks loading `lithium_battery` cells.
- **T2 — Sodium Ion storage**: e.g. `Produce sodium_battery N units` or off the existing T2
  renewable prereq. Unlocks loading `sodium_battery` cells.
- **T3 — Iron Air storage**: repurpose the "Containerised Battery Racks" placeholder; gate off a
  T3 prereq (e.g. Battery Balancing + a mid-late marker). Unlocks loading `iron_battery` cells.

(Exact trigger verbs/quantities are data — tune in `research_unlocks.csv`.)

## Implementation work (when greenlit)

1. **Per-tile loaded-cells state** — `MatchState.tile_battery_cells : {tile_id → {good_id → qty}}`.
   Saved → **bump `SAVE_VERSION` + migration** (rule #4). Old saves: batteries provide their
   old level-based firming until cells are loaded (or migrate to a default load).
2. **`Production._tile_storage_cap`** → cell-based: `min(total_slots, Σ cells × density)`.
3. **Load/unload UI** in the tile-view Power section (the new Prod/Cons/Max-Storage table is the
   anchor): pick an unlocked type + qty, lock goods from the tile stockpile; unload/demolish
   refunds them. Disable types not yet unlocked.
4. **Iron Air production recipe** (data) — e.g. `iron_ingots`/`scrap_metal` + `oxygen` →
   `iron_battery`, cheap; or leave buy-only initially.
5. **Tech nodes** T1/T2/T3 in `research_unlocks.csv` gating each type's loadability.
6. **Demolish refund** of loaded cells (extend the existing refund path).
7. **`economy_config`** — `BATTERY_CELL_DENSITY` per type (flagged balance data, rule #7);
   housing slot caps (reuse `BATTERY_STORAGE_CAP`).
8. Retire / repurpose interim recipe **r_225** (the 1-lithium/turn drain) — the building no
   longer needs a consuming recipe once the deposit model lands.
9. Tests (cell-based `_tile_storage_cap`, tech-gated loadability, refund) + e2e + screenshot.

## Open items to confirm before/at build
- Exact T1/T2/T3 trigger verbs + quantities.
- Whether Iron Air ships with a production recipe now or stays buy-only at first.
- Old-save migration policy for existing batteries (default-load vs empty).
