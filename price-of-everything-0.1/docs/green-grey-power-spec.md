# Green / Grey Power — Intermittent vs Steady Electricity (design spec)

Status: **design complete — ready to implement on sign-off.** This branch currently holds
only the icons (`g_077_green_power`, `g_078_grey_power`) + the bake tool; no engine changes
yet.

Split electricity into **`green_power`** (solar / wind / hydro / waste-biomass) and
**`grey_power`** (coal / gas), and **retire the single `g_010 power` good** (migrate away).
The split drives two mechanics:

1. **Intermittency** — intermittent green (solar / wind) derates the output of recipes that
   rely on it; steady green and grey do not. **Storage removes it, per tile.**
2. **Greenest victory track** — all green (intermittent + steady) counts; grey does not.

Power carries **no carbon tax** — carbon cost stays upstream on coal/crude purchase &
production (coal is slated to be banned outright later).

---

## 1. Per-tile power qualities

| quality | sources | derates output? | Greenest? |
|---|---|---|---|
| `grey_power` | coal_power `b_003`, gas, **grid imports** | no | no |
| green **steady** | hydro `b_027`, waste/biomass (`r_109`), **+ storage-firmed intermittent** | no | yes |
| green **intermittent** | solar `b_024`, onshore `b_025`, offshore `b_026` | **yes (0.4)** | yes |

Track `green_power_intermittent` and `green_power_steady` per tile so the engine knows which
consumed power triggers the derate. (Hydro is steady for now; a later free update may make it
drought-sensitive — out of scope.)

---

## 2. Intermittency derate (deterministic — rule #3)

`INTERMITTENCY_DERATE = 0.4`. Per consuming building, per turn:

```
unfirmed_share = (unfirmed intermittent green it consumed) / (total power it consumed)
output *= 1 - 0.4 * unfirmed_share          # all unfirmed intermittent -> 60% output
```

Applied as a `recipe_output` modifier in `production.gd` (composes with existing modifiers,
shows in the cost / RAG indicator). Grey- or steady-green-powered building → no change.

---

## 3. Storage — abstracted per-tile firming cap

Storage is **not** charge/discharge — it's a per-tile cap that firms intermittent → steady:

```
tile_cap   = sum of battery caps on the tile   (L1 = 100, L2 = 200, L3 = 320 power)
firmed     = min(tile_cap, intermittent green on the tile)
```

- **Producer-side**: a battery on a generating tile firms up to `tile_cap` of the green it
  *produces*, so that power leaves as steady.
- **Consumer-side**: a battery on a consuming tile firms up to `tile_cap` of the intermittent
  green its *recipes draw*, so those recipes escape the derate.

(`100 / 200 / 320` are balance constants in `economy_config.gd`.)

---

## 4. Cross-tile allocation (who gets your green)

Each turn the `Power` autoload matches generation to demand, then the leftover demand is grid
(grey) import:

1. **Producer-side firming** first: on each generating tile, convert up to `tile_cap`
   intermittent → steady.
2. **Allocate own generation, nearest-first.** Consumers pull power from the **closest**
   generating tiles first: own tile (distance 0) → next ring out → outward. Within the same
   distance, priority is **building level L3 → L2 → L1**, ties broken by **most profitable
   first**. A consumer takes whatever quality reaches it (steady or intermittent green).
3. **Grid fills the rest as grey** — any demand not met by your own generation imports grey
   power (always counts grey, never derates).
4. **Consumer-side firming**: on each consuming tile, firm up to `tile_cap` of the intermittent
   green it ended up drawing.
5. **Derate** each consumer per §2 on its remaining unfirmed-intermittent share.

> Open implementation detail (not a design blocker): exact contention handling when several
> equal-priority consumers compete for the same nearby generation — settle during build
> (consumer-pull in global priority order is the working model).

---

## 5. Greenest interaction

Greenest counts **all green generated** (steady + intermittent); the derate hits the
consumer's output, not the green credit. `victory_state.gd` reads the typed green pool instead
of the building-id heuristic (behaviour-preserving + a parity test).

---

## 6. Goods & migration (locked)

- Add `green_power` (`g_077`) + `grey_power` (`g_078`), `good_type=power`,
  `transport_class=electricity`, `is_fossil_fuel=no`, `co2_tax_multiplier=0`,
  `green_sales_premium=0`. Icons already baked.
- **Retire `g_010 power`**: route plant outputs + `energy_req` accounting to green/grey;
  save migration maps old `power` state → grey (firm) and bumps `SAVE_VERSION`.

---

## 7. Implementation phasing (after go-ahead)

1. Goods rows `g_077`/`g_078`; retire `g_010` + save migration; classify plants
   intermittent-green / steady-green / grey.
2. `Power` autoload: per-tile supply by quality; producer + consumer storage firming
   (caps 100/200/320); nearest-first allocation with the L3→L2→L1 / profit priority; expose
   each consumer's unfirmed-intermittent share.
3. `production.gd`: route plant output to the right quality; apply the 0.4 derate modifier.
4. `victory_state.gd`: Greenest reads the typed green pool (+ parity test).
5. Tests: per-tile quality accounting, storage firming caps, derate math (60% unfirmed),
   allocation priority, Greenest parity, save-migration round-trip. Then an e2e balance pass.

---

## 8. Done in this branch

`g_077_green_power` + `g_078_grey_power` icons (medium + small) via `tools/bake_power_icons.gd`
(blue-chroma strip + connected-component recolour). **Icons only — no engine changes.**
