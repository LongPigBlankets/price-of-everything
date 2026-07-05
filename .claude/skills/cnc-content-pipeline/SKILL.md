---
name: cnc-content-pipeline
description: Load this to add or edit a good, recipe, building, research node, deposit, or icon in price-of-everything - or when content mysteriously doesn't appear in-game (buildable building with no recipes, recipe missing from menus, research that never unlocks). Covers CSV schemas, the silent promotion gate, tech-gating, the destructive-generator warning, and the validation checklist.
---

# Content pipeline — adding goods, recipes, buildings

## ⚠️ FIRST, THE ONE THAT DESTROYS WORK

**NEVER run `scripts/build_recipes_all.py`.** Its input,
`data/recipes_master_source.csv`, is a **stale earlier generation**: the same
`recipe_id`s denote *different recipes* (173/199 rows differ), and it has **no
`required_research` column**. One run would wipe the EA economy rebalance and all ~58
tech gates. `data/recipes_all.csv` is **hand-edited ground truth**.
CLAUDE.md's line "edit the source, not the generated file" is **stale and wrong** on
this point — this skill is the correction (verified 2026-07). The same applies to the
other dead files in `data/` (`recipesMVP.csv`, `goods.csv`, `recipes.csv`,
`goods_flow.json`): loaded by nothing, ids collide across generations — never edit or
script against them.

## The live data files (price-of-everything-0.1/data/, all CRLF)

| File | Rows (2026-07-05) | Loaded by |
|---|---|---|
| `Goods - goodsMVP.csv` | 76 goods | `catalog.gd _load_goods` |
| `recipes_all.csv` | 199 recipes (136 active) | `_load_recipes` + promotion gate |
| `Buildings - buildingsMVP.csv` | 37 buildings | `_load_buildings` |
| `research_unlocks.csv` | 231 nodes | `MatchState._load_unlock_defs` |
| `ports.csv` / `tile_properties.csv` / `infrastructure.csv` | 4 / 600 / 6 | catalog |
| `starts/*.json`, `start_buildings.json` | 7 starts / 472 NPC buildings | world seeding |

Edit CSVs with the python-csv procedure in `cnc-godot-discipline` (CRLF!) and verify the
diff touches only your rows.

## The promotion gate — why your recipe may silently not exist

`scripts/catalog.gd` (~line 650) drops a recipe **with zero logging** when:
- its `building_id` doesn't resolve (directly or via the `BUILDING_ALIAS` table), or
- ANY input/output good is missing from the goods CSV.

63 of 199 recipes are dormant this way today (deliberately — the recipe pool is
maximalist). The failure smell: *content you added just doesn't appear*. The historic
"farm unbuildable" bug was exactly this, and it is **live right now** for
`consumer_factory`, `old_forest`, `landfill`, `ruins` (buildable, zero active recipes).

**After any recipe edit, verify survival:**
```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
python3 - <<'EOF'
import csv
goods = {r['internal_name'] for r in csv.DictReader(open('data/Goods - goodsMVP.csv'))}
r = next(x for x in csv.DictReader(open('data/recipes_all.csv')) if x['recipe_id']=='r_XXX')
refs = [r[f'input_{i}'] for i in range(1,7)] + [r[f'output_{i}'] for i in range(1,6)]
missing = [g for g in refs if g and g not in goods]
print('MISSING GOODS:', missing or 'none — will promote if building resolves')
EOF
```
Half-filled pairs are also eaten silently (a real bug: `r_109` has `output_1` with an
empty `output_qty_1` — the output vanishes). Always fill name+qty together.

## Recipe schema essentials (`recipes_all.csv` header order matters)

`recipe_id, display_name, building_id(internal name), input_1..6 + qty_1..6,
energy_req, output_1..5 + output_qty_1..5, requirements, pollution_output,
pollution_sensitivity, category, terminal_turns, required_research`

- `category` is Title-Case and doubles as `recipe_type` (lowercased) for modifier
  matching — an empty category makes the recipe modifier-blind.
- `requirements` tokens — know which are REAL:
  - **Enforced:** `deposit:<good_internal>` (production halts on missing/depleted
    deposit; the construct panel filters by it, survey-gated since 2026-07 so
    unsurveyed tiles don't leak), `potential:wind` / `potential:solar`.
  - **NOT enforced (parse to type "other", ignored everywhere):** `river`,
    `deep_sea`, `2 farms`, `urban AND waste_water`, etc. Don't rely on them.
  - Gating a mining recipe needs a matching deposit ON THE MAP:
    `tile_properties.csv` `deposits` column (`coal(2000)|water` format). Lithium is
    the cautionary tale: `deposit:lithium_ore` gate exists, **no tile has one**
    (as of 2026-07-05) → market-only good.

## Tech-gating (`required_research`)

- The value must EXACTLY match a `title` in `research_unlocks.csv`
  (`MatchState.is_unlocked` is a plain title lookup). A missing title = permanently
  locked content (the `hydro` gate is the live example — possibly intentional).
- KNOWN (2026-07-05): **95/231 research nodes have auto-unlock conditions that can
  never fire** — `Run`/`Own`/`Sell`/`Sustain` actions are unhandled, and ~55 rows use
  Title-Case display names where internal_name matching is required. Such nodes are
  reachable only via free-pick unlocks. If your content gates on one of these, players
  may never see it by playing. Check your node:
  the condition's action must be one of `Produce`, `Build`, `Run Profitable`,
  `Run L1`, `Run Profitable L2` (see `MatchState._live_condition_met`), and its object
  must be a building `internal_name` or good id.
- Gating is enforced in the construct panel AND the search overlay (fixed 2026-07 —
  search used to be a bypass).

## Goods and buildings

- New good: id `g_0xx` (next free), `internal_name` snake_case unique, `transport_class`
  ∈ {solid_light, solid_heavy, ultra_heavy, safe_liquid, hazard_liquid, liquid, gas} —
  fluids move ONLY by pipes (reinforced for hazard_liquid); class rates live in
  `economy_config.gd TRANSPORT_RATES`. `base_price`/`decay_rate` are balance columns →
  `cnc-balance-change-control`.
- Icon: `assets/icons/goods/` — `{good_id}_{internal_name}.png` (+ medium/small
  variants; see the good-icon pipeline note in docs). Missing icon = blank slot +
  console warning; callers tolerate null by contract.
- New building: `Buildings - buildingsMVP.csv` — `base_price` (money leg), `materials`
  (build kit, internal names), `tile_size_used`, `category`
  (`production`/`infrastructure`/...), optional `required_research`. Every
  non-infrastructure building should end up with ≥1 ACTIVE, reachable recipe or it
  becomes a farm-bug clone.

## Validation checklist (run all after content changes)

```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
python3 tools/run_tests.py            # incl. catalog-count asserts — they are HARDCODED
```
1. Unit suite green. Note: `_test_catalog_loaded` hardcodes 76 goods / 37 buildings —
   adding content means updating those asserts in `tests/test_runner.gd` (expected,
   documented failure mode).
2. Promotion-survival check (script above) for every touched recipe.
3. In-game spot check via a shot tool or the encyclopedia (X-search) — the content is
   listed and, if gated, shows locked until its research.
4. E2E run unchanged (`cnc-validation-and-qa` Leg 2).
5. If you touched a tuning column → `cnc-balance-change-control`.

## When NOT to use this skill
- Tuning the numbers on existing content → `cnc-balance-change-control` + `cnc-economy-reference`
- CSV editing mechanics / CRLF → `cnc-godot-discipline`
- Why content is designed this way (routes, tiers, apex goods) → `cnc-design-intent`

## Provenance and maintenance
Compiled 2026-07-05 from catalog.gd reads + the July 2026 data audit. Re-verify:
- Counts: `python3 - <<'EOF'` (csv.DictReader len over each file) or run the unit suite.
- Gate location: `grep -n "BUILDING_ALIAS\|return {}" price-of-everything-0.1/scripts/catalog.gd | head`
- Dead-condition count: see `docs/mechanics_audit_2026-07.md` §Research.
- Generator still dangerous: `git log --oneline -1 -- price-of-everything-0.1/data/recipes_master_source.csv` (untouched = still stale).
