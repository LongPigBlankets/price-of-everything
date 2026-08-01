# Spec — Tile Pollution (Air & Water)

Status: DESIGN — not built. Written 2026-07-19.
Scope: "primary" pollution only — **air** and **water**. Sound/light ("secondary pollution")
comes later; the architecture below is channel-driven so they can be added without rework.

---

## 0. Why this exists (design intent)

Industry should have a *spatial* externality, not just a global one. The CO2 tax
(PolicyState) prices carbon wherever it burns; pollution instead makes **where you build
matter**: a smelter cluster fouls its own valley, spills into the tiles around it, and
pushes out the farms, parks and clean industry that used to live there. The player
gets a zoning problem — separate the dirty district from the clean one, or pay to scrub.

Three player-visible rules (the whole mechanic in one breath):

1. **Every recipe run emits pollution onto its tile** (air and/or water, per recipe).
2. **Pollution accumulates per tile and decays slowly; above a threshold it spills
   into neighbouring tiles** — one dirty building is a local problem, a dirty
   *district* is a regional one.
3. **Some recipes refuse to run on polluted tiles** (farms, parks, water pumping,
   chip fabs) — pollution is a soft land-use tax, not a health bar.

Design pillars:
- **Deterministic** — pure function of game state, headless-safe, no RNG.
- **Data-driven** — all emissions/sensitivities live in `recipes_all.csv` columns that
  already exist (currently empty, ignored by the parser).
- **Symmetric** — NPC buildings emit and get blocked by the same rules.
- **Channel-generic** — `air` and `water` are entries in a channel table, not
  hardcoded twins. Secondary pollution later = new table entries (with their own
  spread rules; sound is radius-static, not accumulating — the table allows that).

---

## 1. Player-facing arc

- Turn 1–20: nothing visible. Early buildings are few and small; pollution stays
  under every threshold. No tutorialising needed.
- First heavy build (coal power, steelworks, refinery): the tile panel starts
  showing `Pollution — Air 34 (rising)`. A lone plant never spills (see §9 math).
- The player stacks a district: 3–4 heavy buildings on/around one tile. The tile
  crosses the spill threshold → one-time bell event: *"Smog is spreading from
  <tile nickname>"* → neighbouring tiles start accumulating.
- A farm / park / water pump on a neighbouring tile stalls with a BDP diagnostic:
  **"Blocked: pollution too high — Air 38 on this tile, needs under 35."** Bell event
  on the first turn a player building becomes pollution-blocked.
- Player responses (all already-shaped systems): move the clean building, stop
  stacking, research scrubbers (−% emission modifiers), run remediation recipes
  (Water Treatment, forestry/parks absorb), or eat the loss.

---

## 2. The model

### 2.1 State

One new per-tile dict on `MatchState` (dynamic, saved):

```gdscript
# match_state.gd  (near deposit_remaining / surveyed_tiles, ~line 340)
var tile_pollution := {}   # tile_id -> {"air": float, "water": float}
```

Missing tile or missing key = 0.0. Sea/deep-sea tiles participate (they are sinks —
high decay — but visible: a slick near the coast reads great on the overlay).

### 2.2 Channel table

```gdscript
# pollution constants — EconomyConfig or a small PollutionConfig section
const CHANNELS := {
    "air": {
        "decay": 0.10,          # fraction of pool removed per turn (land)
        "sea_decay": 0.50,      # wind over open water clears fast
        "spill_threshold": 50.0,
        "spill_rate": 0.25,     # fraction of the EXCESS over threshold moved per turn
        "spread": "all_neighbours",   # all 6 hex neighbours
    },
    "water": {
        "decay": 0.05,
        "sea_decay": 0.50,
        "spill_threshold": 40.0,
        "spill_rate": 0.25,
        "spread": "water_neighbours", # river-linked neighbours + adjacent sea tiles
    },
}
```

### 2.3 Per-turn settle (new `pollution_settle` sub-phase)

Runs once per turn inside `Production._process_production()`, after
`maintenance_labour` and before `carbon_tax` (grouped with the other externalities;
nothing downstream reads the pools except the summary). Steps, per channel:

1. **Emit.** For every *successful recipe run this turn* (player and NPC), add the
   recipe's emission to its tile's pool. Emission was accumulated during
   `production_passes` into a scratch dict `_pollution_emitted_by_tile`
   (same pattern as `_carbon_consumed_by_building`, cleared at the top of the turn).
   Negative emissions (remediation recipes, §3.4) subtract, clamped at pool ≥ 0.
2. **Decay.** `pool *= (1 - decay)` — `sea_decay` on sea/deep_sea tiles.
3. **Spill.** Compute on a **snapshot** of post-decay pools (double-buffer — spill
   must not depend on tile iteration order, determinism):
   - For each tile with `pool > spill_threshold`:
     `overflow = spill_rate * (pool - spill_threshold)`.
   - Eligible receivers per `spread`:
     - `all_neighbours`: all 6 `Catalog.tile_neighbours(tile_id)` (in-bounds).
     - `water_neighbours`: neighbours where **both** tiles have `has_river == true`
       (pollution runs along the river), **plus** any adjacent sea/deep_sea tile
       (river mouth / coastal discharge).
   - Split `overflow` equally among receivers; subtract from source, add to each.
   - **No receivers** (e.g. water pollution on a dry inland tile): remove
     `overflow / 2` from the source and discard it (ground seepage), keep the rest.
     This caps dry-tile water pollution higher than river tiles — mines on dry land
     poison their *own* tile hardest, which is the right incentive.
4. Round pools below `0.05` to 0 (keeps the dict sparse and the save small).

Conservation note for tests: per channel per turn,
`Σ emitted − Σ decayed − Σ seepage = Δ(Σ pools)`. Spill itself is conservative.

River direction (source→mouth) is derivable from `river_type`
(`river_source_* / river_single_* / river_joint_* / river_merge_*`) but fragile —
**v1 water spread is bidirectional along the river**; directional flow is a v2 knob.

### 2.4 Emission scaling

- Emission is **per successful run**, so a factory that runs every other turn emits
  half as much. Stalled/blocked buildings emit nothing.
- Scale by building level: `emission *= BuildingLevels.mult("OUTPUT", level)` — an
  L3 plant makes 2× the goods and 2× the mess. Scrubber research then cuts it (§7).
- Modifier hook: resolve through a new `"pollution_output"` domain in
  `modifier_state.gd` (the file's header comment at line 5 already names pollution
  as a planned modifier source). Percentages in a domain add, matching existing
  domains (`recipe_output`, `maintenance`, …). Context keys: `building_id`,
  `recipe_type` (category, lowercased — same matching as other domains).

---

## 3. Data — the CSV columns

Both columns already exist in `data/recipes_all.csv` (positions 28/29, after
`requirements`) and in `recipes_master_source.csv`; every cell is currently empty
and `catalog._parse_recipe_row()` ignores them. Edit `recipes_all.csv` directly
(the generator is stale — established convention).

### 3.1 Encoding

Same `key:value` style as the `requirements` cell (`deposit:coal`), semicolon-
separated pairs, matching the existing multi-value separator used by requirements:

```
pollution_output       air:8;water:3        (empty = emits nothing)
pollution_sensitivity  air:35;water:30      (empty = never blocked)
```

Negative outputs are legal and mean **remediation**: `water:-8` on Water Treatment.

Parser change: two lines in `_parse_recipe_row` (`catalog.gd:713`) adding
`pollution_output: {channel: float}` and `pollution_sensitivity: {channel: float}`
to the recipe dict (parsed with the same helper shape as `_parse_requirements`).

### 3.2 Authoring by class (emission)

Don't hand-tune 203 rows; assign per **category** from this table, then apply the
named overrides. Values are per-run at L1.

| Category | Air | Water | Notes / overrides |
|---|---|---|---|
| Power (fossil) | 9 | 2 | Coal `Power Production` 9/2; Gas CCGT 4/0; OCGT 5/0; Waste-to-Power 6/1 |
| Power (clean) | 0 | 0 | wind/solar/offshore/hydrogen |
| Steel Production | 8 | 3 | EAF 3/1; HIsarna 5/2 (that's its point) |
| Iron Smelting | 8 | 2 | DRI 4/1 |
| Carbon (coking) | 7 | 2 | biomass variants 3/1 |
| Refining | 6 | 4 | Crude Distillation 7/4; SMR 5/1; Silica Washing 1/4 |
| Building Materials | 6 | 2 | Concrete Firing only; Electric Concrete 2/1; windows/frames 1/1 |
| Copper Smelting | 6 | 4 | |
| Aluminium Smelting | 5 | 2 | Bayer 2/7 (red mud); ELYSIS 1/1; Electric Calcination 2/2 |
| Silicon Smelting / Glassmaking | 5 | 1 | |
| Chemistry | 4 | 5 | Fertilisers 3/7; Haber-Bosch 5/2; Air Separation 1/0 |
| Oil Extraction | 3 | 7 | **Shale Fracking 3/10**; offshore variants 2/6 (on sea tiles) |
| Industrial Acids | 3 | 7 | |
| Mineral Mining | 2 | 6 | dust + tailings/leachate; Sand Excavation 1/3 |
| Pulp & paper (blank cat) | 2 | 5 | Chemical Wood Bleaching 3/8; Paper Goods 1/2; toys 1/1 |
| Recycling | 3 | 4 | **Water Treatment 0/−8**; Biowaste 2/1 |
| Batteries (manufacture) | 2 | 4 | Battery Storage 0/0 |
| Vehicle Comp. / Cars / Equipment | 2 | 2 | Rubber Vulcanisation 4/2 |
| Manufacturing | 3 | 1 | Medical Goods 0/1 |
| Solar Panels / Wind Turbines | 2 | 1 | |
| Electronics | 1 | 3 | fab effluent — but see sensitivity below |
| Electrochemistry | 1 | 2 | Chlor-Alkali 2/5; water electrolysis 0/0 |
| Biofuels | 2 | 2 | Basic Fermentation 1/1 |
| Farming | 0 | 1 | Livestock 1/2; Sustainable variants 0/0 |
| Forestry | 1 | 2 | Aggressive Logging only (erosion). **Sustainable −1/0, Gentle Pruning −2/0, National Park −3/−1** |
| Water | 0 | 0 | Desalination 0/1 (brine) |

### 3.3 Authoring sensitivity (the blockers)

Sensitivity is deliberately sparse — only recipes where "this can't operate in
filth" is intuitive. Dirty recipes get **no** sensitivity (they can never poison
themselves shut; the pressure lands on land-use, not on a death spiral).

| Recipe(s) | Sensitivity | Fiction |
|---|---|---|
| All Farming | air:35; water:30 | crops + livestock |
| National Park Tourism (+Biomass) | air:15; water:15 | most fragile thing on the map |
| Gentle Pruning | air:25 | |
| Water Pumping | water:20 | it's drinking water |
| Desalination | water:35 | intake fouling |
| Medical Goods Production | air:25; water:25 | |
| Semiconductor Fabbing / Fabless / 3D / Monocrystal CPU | air:30 | cleanroom air intake |
| Inert-Atmosphere Precision Components | air:25 | |
| Basic Fermentation / Micro Algae Digestion | water:25 | |

Everything else: empty (immune).

### 3.4 Remediation recipes

Negative `pollution_output` applies in the Emit step to the building's own tile
(clamped ≥ 0), *before* decay/spill. This activates existing recipes as tools:
Water Treatment becomes "place downstream of the chemical district"; a National
Park is both a victim and a slow air scrubber. No new content needed for v1.

---

## 4. Blocking

### 4.1 Rule

A recipe **cannot run** on a tile where, for **any** channel listed in its
`pollution_sensitivity`, `tile pool ≥ threshold`. Checked in
`Production._can_run_recipe()` (`production.gd:1874`) — a new branch mirroring the
mined-out-deposit branch at 1893, producing `blocked_reason = {code: "pollution",
message: "Air 38 on this tile — needs under 35"}` via `_blocked_reason_for()`.

The check reads the pool as of the **last settle** (pools don't move during
`production_passes`), so cascade order can't affect it. Applies to NPC buildings
identically. The AI does not reason about pollution in v1 — an NPC building
stalling in the player's smog is acceptable (and narratively useful for the era-1
scripted rival later).

### 4.2 Hysteresis (anti-flap)

Without it, a farm at the boundary runs/stalls on alternate turns as the pool
oscillates around the threshold. Rule: once a building is pollution-blocked, it
stays blocked until the pool drops below **85% of the threshold**. State: one
additive key on the building instance dict, `"pollution_blocked": true`
(buildings are plain dicts on MatchState; saved for free with the building).

### 4.3 Interaction with the economy

Blocked producers → supply falls → the deficit price model (2x/3x/4x thresholds)
raises the good's price → remaining clean-sited producers earn more. The market
partially self-corrects; no special handling needed. Watch item for balancing:
food, since all Farming recipes share one sensitivity band.

---

## 5. Engine integration (exact hooks)

| Concern | Site |
|---|---|
| Parse CSV columns | `catalog.gd:713` (`_parse_recipe_row`) |
| Pool store + save | `match_state.gd` — new `tile_pollution` dict; export/import (~2775/2796) |
| Emit accumulation | `production.gd` production_passes, next to `_capture_turn_report` (~330) |
| Settle sub-phase | `production.gd` new `pollution_settle` TurnProfiler section (~545, before `carbon_tax`) |
| Neighbours | `Catalog.tile_neighbours()` (`catalog.gd:342`) — odd-q offset hex, already clamped |
| Block check | `production.gd:1874` `_can_run_recipe` + `_blocked_reason_for` (1936) |
| Modifier domain | `modifier_state.gd` registry — new `pollution_output` domain |
| Level scaling | `building_levels.gd` `mult("OUTPUT", level)` |
| Summary | add `pollution` block to the turn summary dict for briefing/bell events |

Save: **additive keys only, no SAVE_VERSION bump** — old saves `.get()` an empty
dict and start clean, matching the `surveyed_tiles`/`deposit_remaining` pattern.

Headless/e2e: fully active (deterministic, no UI dependency) — unlike DecisionState
which is headless-disabled. Tests rely on it (§8).

Perf: ~600 tiles × 2 channels × O(6) — negligible; no spatial index needed.

---

## 6. UI

1. **Map mode** — new `Mode.POLLUTION` in `map_mode.gd` (+ sentinel), button row in
   `mapmodes_panel.gd:15`, renderer patterned on `power_hex_overlay.gd` (per-hex
   fill) with Air/Water toggle chips. Suggested wash (ink-plate palette): air =
   smoky sepia-grey fill scaling 0→100, water = teal hatch; tiles currently
   blocking something get a small warn glyph. Rebuild on `turn_processed`.
2. **Tile panel** — new static in `tile_view_data.gd` → fact row in
   `tile_info_panel_v2.gd`: `Pollution — Air 62 (rising) · Water 8 (falling)`
   (trend = sign of last turn's delta, from the summary). If any pool exceeds any
   catalog sensitivity: `Too polluted for: Farming, Water Pumping`.
3. **BDP diagnostics** — new row in `building_readout.gd` fault ladder (293–307):
   `Blocked: pollution too high — Air 38 on this tile, needs under 35` (tone
   "bad"), driven by the `pollution` blocked_reason. Emitters additionally get a
   passive line in the Modifiers accordion: `Emits: 8 air / 3 water per run`.
4. **Bell events** (turn briefing): (a) first turn a tile crosses a spill
   threshold — *"Smog is spreading from <nickname>"* / *"<nickname>'s river is
   fouled"*; (b) first turn a player building becomes pollution-blocked. Both
   one-shot per tile/building until the condition clears.
5. **Encyclopedia** — recipe cards (RecipeDiagram/DS facade) show emission and
   sensitivity lines when non-empty.
6. **Cheat** — `pollute <n>` adds n air+water to the selected/inspected tile
   (mirrors `skip <n>` / `win`), for testing and screenshots.

---

## 7. Mitigation (research)

Two nodes in `research_unlocks.csv` + `modifier_state.gd` research-node entries,
unlock-by-doing like the rest:

| Node | Effect (`pollution_output` domain) | Unlock condition (shape) |
|---|---|---|
| Flue Gas Scrubbing | −30% **air**, categories: power, steel production, iron smelting, refining, building materials | e.g. "emit N total air pollution" |
| Effluent Treatment | −30% **water**, categories: chemistry, mineral mining, oil extraction, industrial acids, recycling | e.g. "emit N total water pollution" |

Deliberately not free/instant — the early game should feel the constraint first.
Later eras can add paid per-building filter retrofits (out of scope, fits the
existing retrofit machinery).

---

## 8. Testing plan

Unit (headless, `python3 tools/run_tests.py`):
- **Determinism**: same state → identical pools after N settles (double-buffer works).
- **Conservation**: emitted − decayed − seepage == Δpools, per channel.
- **Spill topology**: air reaches all 6 neighbours; water only crosses
  river↔river and land→sea edges; dry-tile seepage halves overflow.
- **Blocking + hysteresis**: farm blocks at ≥35, stays blocked at 32, unblocks at <29.75.
- **Negative emission** clamps at 0; **save roundtrip** preserves pools and
  `pollution_blocked`; old save (no key) loads clean.
- **Modifier/level**: L3 emits 2×; scrubber node −30% applies to matched categories only.

e2e: coal plant ×4 on one tile, farm adjacent → farm blocked within ~15 turns,
BDP row present; demolish plants → farm resumes after decay (hysteresis respected).

---

## 9. Tuning & worked equilibria (why these constants)

Steady state with spill active: `E = decay·P + spill_rate·(P − T)`.

**Air** (decay .10, T 50, rate .25):
| Emitters on one tile | Tile eq. | Spill/turn | Per-neighbour eq. |
|---|---|---|---|
| 1× coal plant (E=9) | ~61 | 2.9 | ~5 — harmless |
| 2× (E=18) | ~87 | 9.3 | ~15 |
| 3× (E=27) | ~113 | 15.7 | ~26 — parks (15) dead, farms (35) survive |
| 4× (E=36) | ~139 | 22.1 | ~37 — **farms on all 6 neighbours blocked** |

So: one plant is free, a district is a decision — the knob is "4 heavy stacks kill
neighbouring farmland". Adjacent dirty tiles compound (second-order spill).

**Water** (decay .05, T 40, rate .25): one mine (E=6) on a dry tile equilibrates
~63 (seepage-limited) — blocks Water Pumping (20) and farming (30) *on its own
tile* but nothing else; the same mine on a river carries ~2–3/turn downstream.
Fracking (E=10) on a river is a genuine downstream event. Sea tiles at 50% decay
absorb any realistic discharge (visible slick, no accumulation).

Tuning knobs, all in the channel table: decay (how long scars last), threshold
(how much stacking is free), spill rate (sharpness of the regional effect).
Deliberate v2 candidates, off in v1: terrain-scaled air decay (mountains trap,
`wind_potential` clears), directional river flow, urban-tile population effects.

---

## 10. Out of scope (later)

- **Secondary pollution** (sound, light): new channel-table entries with a
  `radius_static` spread kind (no accumulation, recomputed from live emitters) —
  the reason `spread` is a string, not a bool.
- Pollution fines / regulation events (era-2 market disruptions, era-3
  public-goods obligations both fit; also a natural DecisionState card: "Locals
  complain about the smog").
- AI siting awareness; paid filter retrofits; land-value/tile-price coupling;
  CO2-tax interaction stays **none** by design (carbon is global money, pollution
  is local land-use — no double charge).

## 11. Build checklist (phases)

- **P0 — data**: fill both CSV columns per §3 tables (script the category pass,
  hand-apply overrides); parser reads them; recipe dict exposes them. No behaviour.
- **P1 — sim**: MatchState pool + save; emit/decay/spill settle sub-phase;
  blocking + hysteresis + blocked_reason; unit tests. Game is playable-complete here.
- **P2 — surfaces**: map mode overlay, tile-panel fact, BDP rows, bell events,
  encyclopedia lines, `pollute` cheat.
- **P3 — mitigation**: `pollution_output` modifier domain, 2 research nodes,
  level scaling, e2e test.
