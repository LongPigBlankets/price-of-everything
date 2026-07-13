# Spec — Tech-Gating + Mine Deposit-Penalty

> **STATUS: BOTH IMPLEMENTED.** Feature 1 — `catalog.gd` reads `required_research` and filters locked recipes. Feature 2 — permanent per-good `recipe_output` modifiers in `modifier_state.gd` apply the standing deposit penalty and additive mining-recovery research. **Oil and lithium remain exempt.**

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

**Goal:** common extraction recipes start at **×0.70 output** ("exhausted surface deposits"), while bauxite and sulphur start at **×0.85**. Mining-research nodes restore output in additive +15% steps: two steps for common deposits and one for bauxite/sulphur. Diegetic depletion → staged tech recovery.

**State — `modifier_state.gd`:** `EXTRACTION_PENALTY_PCT` registers permanent per-good `recipe_output` modifiers on reset. Common deposits use −30%; bauxite and sulphur use −15%. Research modifiers use the same target and stack additively.

**Output application — `production.gd`:** `_produce_outputs` resolves `recipe_output` modifiers with a `good_internal` context before building-level and workforce multipliers.

**Research effect — `modifier_state.gd`:** unlock titles map to +15% per-good modifiers:
```gdscript
"Improved Coal Mining": {"good_internal": "coal", "pct": 15.0}
"Automated Mine Dispatch": [# second +15% step for common deposits]
"Composite Drill Bits": [# second rare/alloy step; sole bauxite/sulphur step]
```

**Save/load:** modifiers are serialized, and standing penalties are re-seeded after reset/import so older saves cannot lose the baseline rule.

**Design knobs:** start penalties, the +15% recovery step, and which goods are penalized. Dedicated recovery nodes stop at exactly 100%; separate general mining-productivity research can still raise late-game output above baseline.

**Effort:** one dict + one multiply in production + one hook in `grant_unlock`.

---

## Build order & validation
1. Feature 1 code (2 edits) + the new research nodes → verify tagged recipes hidden until their node unlocks (headless test: assert `get_recipes_for_building` excludes a locked recipe, includes it after `grant_unlock`).
2. Feature 2 modifiers → verify every −30% good has two +15% recovery unlocks, every −15% good has one, and each path ends at exactly 100%.
3. Re-run `tools/balance.py` (unaffected — it ignores both fields) and the headless sim to confirm the early-game thinning matches the design.
