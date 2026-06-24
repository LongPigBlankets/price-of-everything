# Green / Grey Power — Intermittent vs Steady Electricity (design spec)

Status: **design only, pending final go-ahead.** This branch holds only the two icons
(`g_077_green_power`, `g_078_grey_power`) + the bake tool. Most design decisions are now
locked (§6); a few balance/grid details remain.

Split electricity into two goods — **`green_power`** (solar / wind / hydro / waste-biomass)
and **`grey_power`** (coal / gas) — and **retire the single `g_010 power` good** (migrate
away). The split exists for **two mechanics**:

1. **Intermittency.** Green power can be *intermittent* (solar / wind) or *steady*
   (hydro, waste/biomass, or intermittent green that storage has firmed). Intermittent
   green applies a **tile-level penalty to the output of recipes that rely on it.** Grey is
   always steady — no penalty. **Storage removes intermittency** (per tile, up to capacity).
2. **Greenest victory track.** All green power (intermittent + steady) counts toward
   Greenest; grey does not.

Power is **not** carbon-taxed — the carbon cost lives upstream on coal/crude oil
purchase/production (and coal is slated to be banned outright later). So power is purely
about reliability + the green track.

---

## 1. The per-tile state: intermittent vs steady green

Track, **per tile**, three power qualities:

| quality | sources | output penalty? | Greenest? |
|---|---|---|---|
| `grey_power` | coal_power `b_003`, gas | no | no |
| green — **steady** | hydro `b_027` (firm; see §5), waste/biomass (`r_109`), **+ storage-firmed intermittent** | no | yes |
| green — **intermittent** | solar `b_024`, onshore `b_025`, offshore `b_026` | **yes** | yes |

`green_power_intermittent` and `green_power_steady` are tracked separately so the engine
knows which consumed power triggers the derate.

---

## 2. Storage firms intermittent → steady (per tile)

Storage (battery buildings) on a tile converts up to **X** units of intermittent green into
steady, where X = the tile's effective storage capacity:

- **On a producing tile** — firms the green it generates *before it leaves*: that green flows
  out as steady.
- **On a consuming tile** — firms the green its *recipes consume*: those recipes escape the
  penalty.

Either placement works; storage is the deliberate counter to intermittency (makes the
sodium / lithium / iron battery goods load-bearing). `firmed = min(storage_capacity,
intermittent_green_on_tile)`.

---

## 3. The intermittency penalty (deterministic — rule #3)

Per consuming building, per turn:

```
unfirmed_intermittent_share = (intermittent green it consumed, net of tile storage)
                              / (total power it consumed)
output *= 1 - INTERMITTENCY_DERATE * unfirmed_intermittent_share
```

- `INTERMITTENCY_DERATE`: balance constant (placeholder ~0.5 → a building running entirely on
  unfirmed intermittent green loses ~50% output). Steady-green- or grey-powered → no change.
- Applied as a `recipe_output` modifier in `production.gd`, so it composes with existing
  modifiers and surfaces in the cost / RAG indicator.

---

## 4. Greenest interaction

Greenest counts **all green generated** (steady + intermittent) as the green share — the
intermittency derate hits the *consumer's output*, not the green credit. `victory_state.gd`
reads the typed green pool instead of the building-id heuristic (behaviour-preserving; add a
parity test).

---

## 5. Classification (locked)

- **Green intermittent:** solar `b_024`, onshore wind `b_025`, offshore wind `b_026`.
- **Green steady:** waste/biomass power (`r_109`). **Hydro `b_027` = green + steady** for now;
  a later free update may make hydro intermittent only under river drought (out of scope here).
- **Grey (steady):** coal_power `b_003`, gas CCGT, grid imports.

---

## 6. Decisions — locked vs open

**Locked (per your direction):**
- Two goods `green_power` (g_077) + `grey_power` (g_078); **migrate `g_010 power` away**
  (save migration, not an alias).
- Intermittency = tile-level output derate; **storage firms it per tile** (producer or
  consumer side).
- Per-tile `green_power_intermittent` / `green_power_steady` accounting.
- **No carbon tax on power** (upstream on coal/crude only; coal ban later).
- Waste/biomass = green steady; hydro = green steady (for now).

**Still open (small):**
1. `INTERMITTENCY_DERATE` value → **placeholder, tune in the e2e harness** unless you have a number.
2. **Storage capacity → X mapping**: what battery stat sets X (stored energy per turn? a
   building stat)? And does grid-imported intermittent green count against the *importing*
   tile's storage?
3. **Cross-tile grid flow**: when unfirmed intermittent green flows producer→consumer via the
   grid, the quality travels (consumer derates) unless either tile firms it. Confirm the
   allocation order (firm producer-side first, then consumer-side, then derate the remainder).

---

## 7. Implementation phasing (after go-ahead)

1. Goods rows `g_077`/`g_078`; **retire `g_010`** + save migration; classify plants
   green-intermittent / green-steady / grey.
2. `Power` autoload: per-tile supply by quality (grey / green-steady / green-intermittent);
   storage firming (producer + consumer); grid allocation; expose each tile's
   unfirmed-intermittent share.
3. `production.gd`: apply the intermittency derate as a `recipe_output` modifier; route plant
   output to the right quality.
4. `victory_state.gd`: Greenest reads the typed green pool (+ parity test).
5. Tests (per-tile quality accounting, storage firming, derate math, Greenest parity, save
   migration round-trip) + an e2e balance pass to tune `INTERMITTENCY_DERATE` + storage.

---

## 8. Done in this branch

`g_077_green_power` + `g_078_grey_power` icons (medium + small) via `tools/bake_power_icons.gd`
(blue-chroma strip + connected-component recolour). **Icons only — no goods/grid changes.**
