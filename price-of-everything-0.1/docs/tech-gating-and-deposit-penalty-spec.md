# Spec — Tech-Gating + Mine Deposit-Penalty

> **STATUS: BOTH IMPLEMENTED (2026-06-19).** Feature 1 — `catalog.gd` reads `required_research` + `get_recipes_for_building` filters on `MatchState.is_unlocked`. Feature 2 — `MatchState.get_deposit_yield()` (live from `unlocked_titles`, capped 1.0) + `production.gd:_produce_outputs` multiplies deposit-mined output. **Oil (crude_oil) and scarce ores (lithium) are exempt** (not in `PENALISED_EXTRACTION`). 627/627 headless tests pass. The cables power-throughput mechanic (§ below was *not* part of this — it's the still-pending 3rd feature).

Two small engine features that make the EA rebalance's tech recipes and mine balance *function*. The recipe **data** is already authored (forward-compatible); these features switch it on. Both are contained, follow existing patterns, and are independently shippable.

> Scope note: the **carbon-substitution group** (coal/pet_coke/carbonised_biomass fungible input) is a separate, third feature discussed elsewhere — not covered here.

---

## Feature 1 — Recipe → Research Gate

**Goal:** a recipe with a `required_research` title is only available/promotable once that research node is unlocked. Until then it's hidden in the build menu.

**Data — DONE.** `recipes_all.csv` now has a `required_research` column. Base recipes leave it empty (always available); ~17 tech recipes are tagged with a research node *title* (the link is by title — no extra mapping table). Tagged recipes and their nodes:

| Recipe | required_research | node status |
|---|---|---|
| Direct Reduced Iron (hydrogen) | Hydrogen Direct Reduction | **new** (Metallurgy) |
| Basic Oxygen Steelmaking | Continuous Casting | exists |
| Electric Arc Steelmaking | Electric Arc Refining | exists |
| HIsarna Steel | Alloy Heat Treatment | exists |
| SynRM Magnetless Motors | Reluctance Machines | **new** |
| Axial Flux Motors | Axial Flux Machines | **new** |
| Hairpin Stator Motors | Hairpin Windings | **new** |
| High Strength Glassmaking | High Strength Glassmaking | exists |
| Flash Copper Smelting | Copper Froth Flotation | exists |
| Water Treatment | Water Recycling | **new** (+ new "Recycling" category) |
| Lightweight Car Bodies | Vehicle Lightweighting | **new** |
| V8 Engine | Performance Engines | **new** |
| Hybrid Engine | Hybrid Powertrains | **new** |
| Heavy Electric Motor | Electric Drivetrains | **new** |
| Automated ICE Car / Heavy Vehicles Automated | Automated Assembly | **new** |
| Electric Heavy Vehicles | Electric Heavy Vehicles | **new** |

**Code (2 edits):**
1. `catalog.gd:612 _parse_recipe_row` — read the column into the recipe dict:
   `recipe["required_research"] = raw.get("required_research", "")`
2. `catalog.gd:718 get_recipes_for_building(building_id)` — filter the returned list:
   `r.required_research == "" or MatchState.is_unlocked(r.required_research)`
   (Apply the same predicate anywhere else that lists buildable recipes — e.g. `construct_panel`'s recipe list. `MatchState.is_unlocked(title)` already exists at `match_state.gd:534`.)

**Research-tree data:** add the ~11 **new** nodes above to `research_unlocks.csv` (columns: category, prereq_1..3, prereq_othercategory, rank I/II/III, Action/Object/Quantity/Unit unlock-condition, title, icon, description), plus a new **"Recycling"** category. Place them at sensible ranks behind existing prereqs (e.g. Hydrogen Direct Reduction → rank II Metallurgy behind Continuous Casting; the vehicle nodes → a Manufacturing/Vehicles category).

**Save/load:** none. `unlocked_titles` already persists; `required_research` is static catalog data.

**Effort:** ~2 lines of engine code + research-tree authoring.

---

## Feature 2 — Mine Deposit-Penalty + Research-Restores-Output

**Goal:** extraction recipes start at **×0.5 output** ("exhausted surface deposits"); mining-research nodes raise a per-good yield multiplier back toward (and past) 1.0. Diegetic depletion → tech recovery. This is what makes early mining thin and makes the **Beneficiated Iron Mining** research node meaningful (it replaces the retired r_075 recipe).

**State — `match_state.gd`:**
- Add `var deposit_yield: Dictionary = {}` (good_id → multiplier). Declare near `unlocked_titles` (line 93); clear in `reset` (751); **derive on load** from `unlocked_titles` (see below) so no new serialization is needed.
- Helper:
  ```gdscript
  const EXTRACTION_PENALTY := 0.5
  func get_deposit_yield(good_id: String) -> float:
      return deposit_yield.get(good_id, EXTRACTION_PENALTY)
  ```
  (Apply the 0.5 default only to extraction goods — coal/iron_ore/copper_ore/etc.; a `Catalog.is_extraction_good(g)` helper or the recipe's "no inputs + deposit requirement" flag identifies them. Non-extraction goods → 1.0.)

**Output application — `production.gd`** (the output-generation branch, ~line 162+, the non-power case mirroring the power case at 162–168):
```gdscript
var mult := MatchState.get_deposit_yield(good_id) if Catalog.is_extraction_recipe(recipe) else 1.0
var qty := int(round(recipe.output_qty * mult))
```
Only extraction recipes are scaled; processing recipes are untouched.

**Research effect — `match_state.gd:539 grant_unlock(title)`:** a static bonus map, applied when a mining node unlocks:
```gdscript
const RESEARCH_YIELD_BONUS := {
    "Beneficiated Iron Mining": {"iron_ore": 0.5},   # 0.5 -> 1.0 (the user's "100%")
    "Improved Coal Mining":     {"coal": 0.5},
    "Copper Froth Flotation":   {"copper_ore": 0.4},
    "Deep Seam Surveying":      {"iron_ore": 0.2, "coal": 0.2, "copper_ore": 0.2},
    # ... per design
}
# in grant_unlock, after setting unlocked_titles[title]:
for good in RESEARCH_YIELD_BONUS.get(title, {}):
    deposit_yield[good] = deposit_yield.get(good, EXTRACTION_PENALTY) + RESEARCH_YIELD_BONUS[title][good]
```

**Save/load:** derive `deposit_yield` from `unlocked_titles` on load (loop the unlocked titles through `RESEARCH_YIELD_BONUS`) — no new serialized field, version-safe.

**Design knobs:** start penalty (0.5), per-node bonus amounts, and *which* goods are penalized — recommend the infinite bulk deposits (coal, iron_ore, copper_ore, limestone, sand, basic_salt); leave scarce/strategic deposits (lithium_ore, ree_ore, bauxite) at full yield, or give them their own surveying nodes. Yields can exceed 1.0 (late mining tech beats the baseline) — intended.

**Effort:** one dict + one multiply in production + one hook in `grant_unlock`.

---

## Build order & validation
1. Feature 1 code (2 edits) + the new research nodes → verify tagged recipes hidden until their node unlocks (headless test: assert `get_recipes_for_building` excludes a locked recipe, includes it after `grant_unlock`).
2. Feature 2 state + production multiply + bonus map → verify a fresh iron mine outputs ×0.5, and outputs ×1.0 after `grant_unlock("Beneficiated Iron Mining")`.
3. Re-run `tools/balance.py` (unaffected — it ignores both fields) and the headless sim to confirm the early-game thinning matches the design.
