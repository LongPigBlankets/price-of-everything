# Green / Grey Power — Intermittent vs Firm Electricity (design spec)

Status: **design only, pending approval. No implementation yet** — this branch holds
only the two icons (`g_077_green_power`, `g_078_grey_power`) and the bake tool.

Split electricity into two goods, **`green_power`** (solar / wind …) and **`grey_power`**
(coal / gas …), for **two concrete reasons**:

1. **Intermittency.** Green power is unreliable. It applies a **tile-level penalty to the
   output of production that relies on it.** Grey power is firm — no penalty.
2. **Greenest victory track.** Green power counts toward Greenest; grey does not.

The strategic tension: green is clean and scores Greenest **but derates the output it
powers**, unless you **firm it with storage** (batteries) — at which point you keep the
clean/Greenest upside without the output hit. Grey runs flat-out but is dirty and scores
nothing. This makes the existing battery goods (sodium / lithium / iron) load-bearing.

---

## 1. How power works today (verified)

- One good `g_010 power` (`good_type=power`, `transport_class=electricity`). **Power is a
  GRID resource, not stockpiled/transported.** Plants call `Power.record_produced(tile_id,
  qty)`; consumers draw via the building's `energy_req` → `Power.record_drawn(tile_id, qty)`.
  The `Power` autoload aggregates supply/demand and settles the grid each turn. **`tile_id`
  is already threaded through** both calls, so per-tile green/grey accounting is feasible.
- Greenest already measures the green share of `power_supply_by_type` (solar `b_024`,
  onshore `b_025`, offshore `b_026`) over total supply.
- `production.gd` already has a per-building output-modifier hook (`Modifiers.apply(
  "recipe_output", …)`) and `_effective_*` helpers — the natural place to apply a derate.

---

## 2. The intermittency mechanic (the core new system)

Per tile, per turn, **deterministic** (no RNG — rule #3):

1. **Classify supply** reaching the tile as **green** (intermittent) vs **firm** (grey grid /
   coal / gas, and possibly hydro — see §4).
2. **Green-first local allocation.** A tile's local green generation powers its local demand
   first; the rest is drawn firm (grid/grey). So a building's `green_share` = the fraction of
   the power it consumed that came from (unfirmed) green.
3. **Storage firms green.** Battery capacity on the tile (or grid — §6 decision) converts
   intermittent green into firm: `firm_fraction = clamp(stored_capacity / green_supplied, 0, 1)`.
   The firmed portion behaves like grey (no penalty).
4. **Output derate.** For each consuming building:
   ```
   unfirmed_green_share = green_share * (1 - firm_fraction)
   output *= 1 - INTERMITTENCY_DERATE * unfirmed_green_share
   ```
   - `INTERMITTENCY_DERATE` is a balance constant (placeholder ~0.5 → a fully-green,
     unstored building loses ~50% output). Grey-powered (`green_share = 0`) → no change.
   - Applied as a `recipe_output` modifier in `production.gd`, so it composes with existing
     modifiers and shows up in the cost/RAG indicator.

Net effect: **green capacity is "cheap" power that quietly steals your output until you pair
it with storage.** Pure-grey is reliable but dirty.

> Per-source reliability (optional refinement): instead of one binary, give each green source
> its own capacity factor (solar < onshore wind < offshore wind), so the derate scales with
> the *kind* of green on the tile. Flag in §7.

---

## 3. Greenest interaction

- Greenest still counts **green power generated** (the green pool's supply share). Intermittency
  derates the *consumer's output*, not the green credit — so chasing Greenest and eating the
  intermittency cost is exactly the tension we want.
- `victory_state.gd` Greenest reads the typed green pool instead of the building-id heuristic
  (behaviour-preserving if the green set matches). Minor change.

---

## 4. Green vs grey classification (needs sign-off)

- **Green (intermittent):** solar_farm `b_024`, onshore_wind `b_025`, offshore_wind `b_026`.
- **Grey (firm):** coal_power `b_003`, gas CCGT, grid imports.
- **Decisions:** hydro `b_027` — green *and firm* (counts for Greenest, no intermittency)?
  Waste/biomass power (`r_109`) — green, grey, or firm-green? Batteries discharge — firm, and
  "green" if charged from green?

---

## 5. Goods & grid model

- Add `green_power` (`g_077`) + `grey_power` (`g_078`) goods rows (electricity / `good_type=power`).
  Icons already baked.
- **Typed grid:** the `Power` autoload tracks green vs firm supply **per tile** (not just two
  global pools — intermittency is tile-level), allocates green-first locally, and exposes each
  tile's green-share so production can derate.
- `g_010 power`: keep as a firm/grey alias for save-compat, or migrate away (§7).

---

## 6. Open decisions (please confirm before I implement)

1. **`INTERMITTENCY_DERATE` magnitude** (placeholder 0.5) — set now or tune in the e2e harness?
2. **Storage scope**: does storage firm green **per tile** (battery on the same tile) or
   **grid-wide**? And the firming formula (capacity vs energy-over-the-turn)?
3. **Firm-green sources**: is hydro firm-green? offshore wind partially firm? Or all green
   uniformly intermittent (one `DERATE`)?
4. **Per-source capacity factors** (solar/onshore/offshore differ) or a single binary green?
5. **Allocation rule**: strictly green-first local, or pro-rata across the tile's supply?
6. **Grey carbon tax / green premium**: keep the §0 carbon-economics lever as a secondary
   pressure, or leave power purely about intermittency + Greenest for now?
7. **`g_010 power`**: compat alias vs migrate-away (save-schema change).

---

## 7. Implementation phasing (after approval)

1. Goods rows `g_077`/`g_078`; classify plants green/firm; `g_010` alias-or-migrate.
2. `Power` autoload: per-tile green vs firm supply, green-first allocation, storage firming,
   expose per-tile green-share.
3. `production.gd`: apply the intermittency derate as a `recipe_output` modifier.
4. `victory_state.gd`: Greenest reads the typed green pool.
5. Tests (pool accounting, derate math, storage firming, Greenest parity) + an e2e balance
   pass to tune `INTERMITTENCY_DERATE` and storage.

---

## 8. Done in this branch

`g_077_green_power` + `g_078_grey_power` icons (medium + small), baked via
`tools/bake_power_icons.gd` (blue-chroma strip + connected-component recolour). **Icons only.**
