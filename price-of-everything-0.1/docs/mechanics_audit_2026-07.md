# Price of Everything — Mechanics & Code Audit

**Date:** July 2026 · **Scope:** full repo — turn loop, production, energy, labour, markets, price movement, special orders, loans, buildings, advisors, research, victory, transport, map/roads, overlays, empire view, save/load, data layer, tests, performance.

**Method:** eight parallel deep-read audits over `scripts/`, `data/`, `tests/`, and the Python side, with scripted CSV cross-checks. Headline claims were independently re-verified against source before inclusion; two initially-reported "critical" findings (an input-scaling exploit and a market top-up under-order) were **falsified on verification** — `_can_run_recipe`, `_consume_inputs`, and `_buy_market_inputs` all correctly use `_scaled_input_qty` — and are excluded.

**Severity legend:**
- **CRITICAL** — breaks the economy or corrupts state; fix before wider EA exposure.
- **HIGH** — visible wrong behaviour, a real player exploit, or a major performance cliff.
- **MEDIUM** — fragile or misleading; will bite during future changes.
- **LOW** — polish / hygiene.

---

## Top priorities (ranked)

| # | Severity | Finding | Feature |
|---|---|---|---|
| 1 | CRITICAL | Upgrade-rebate + cancel is an infinite money pump (verified) | Buildings |
| 2 | CRITICAL | The glut/price-impact model is never applied to any price — selling has no cost (verified) | Markets |
| 3 | CRITICAL | Loading a save mid-turn-resolution lets the zombie resolution coroutine corrupt the loaded state | Save/load |
| 4 | CRITICAL | Running the documented recipe generator would wipe the entire EA rebalance and all tech gates | Data layer |
| 5 | HIGH | Search overlay bypasses all research gating — any gated recipe buildable turn 1 | Research |
| 6 | HIGH | Labour slider 0.8× is a free permanent −20% cost; the advertised output penalty doesn't exist (verified) | Labour |
| 7 | HIGH | Special-order arbitrage: buy from market, deliver to order, pocket 25–40% risk-free | Special orders |
| 8 | HIGH | Loan principal repayment is booked as interest and shields taxable profit (verified) | Loans |
| 9 | HIGH | Manual sells pay zero freight; auto-sells pay full freight — manual clicking strictly dominates | Markets |
| 10 | HIGH | Demolish is promised by three UIs but is a no-op; blind-build mistakes are permanent traps | Buildings |
| 11 | HIGH | 95 of 231 research nodes have conditions that can never fire; hydro is permanently unbuildable | Research/data |
| 12 | HIGH | Fluids bypass the pipe-only rule on every tile-to-tile move; unreachable routes fall back to a haul that's *cheaper* than real routes | Transport |
| 13 | HIGH | Load-game runs two full synchronous layout passes with no yields; new-game places NPC buildings at 1/frame (~8 s floor) | Performance |
| 14 | HIGH | Empire view does O(samples × buildings) background sampling and O(n²) panel separation every frame | Empire view |
| 15 | HIGH | MapMode is never reset on load/new game — stale Surveying mode hijacks every left-click with no visual cue | Overlays |
| 16 | HIGH | Ledger lets you pay real materials + research to "upgrade" infrastructure instances with zero gameplay effect | Buildings |

---

## 1. Turn manager & core simulation loop

### Working well
- Explicit, fixed phase pipeline with first-class observability: every phase and 14 PROCESS sub-steps are profiled to console + CSV with stable column contracts (`turn_manager.gd:92-128`, `turn_profiler.gd:29-47`).
- Same-turn output buffering: 0-turn outputs are merged after all production passes, so iteration order between co-located buildings can never confer advantage (`production.gd:17-18, 329-331`).
- Deterministic intermittency allocator — a pure function with a documented total order for tie-breaking (`production.gd:1315-1405`).
- No economic logic in `_process`/`_physics_process` anywhere in the sim — turn logic is fully event-driven.
- The ~470 inert NPC buildings are pre-filtered once per turn so sim cost tracks the player's empire only (`production.gd:169-177`).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **No bankruptcy enforcement.** `add_money` has no floor (`match_state.gd:461-463`); `BANKRUPTCY_FLOOR` only triggers a warning event, and only if the player has loans. Grid buys, maintenance, labour, transport, and transfers all drive money arbitrarily negative — there is no economic fail state at all. Found independently by three audits. |
| MEDIUM | **PROCESS/NARRATIVE listener order is a connection race.** Production, MatchState, Modifiers, and EventScheduler all connect to `phase_started` via `await process_frame` / `call_deferred` (`production.gd:72-75`, `match_state.gd:436-441`, `modifier_state.gd:279-285`). Turn semantics (battery firming before/after the production cascade, modifier pruning vs unlock evaluation) depend on autoload registration order, not anything explicit. |
| MEDIUM | **Modifier duration off-by-one depends on acquisition path** (`modifier_state.gd:354-357, 450-460`): a timed modifier granted in DECIDE lives `dur+1` PROCESS phases; one granted in NARRATIVE lives exactly `dur`. |
| MEDIUM | **RunMetrics final-turn ordering:** `game_ended_signal` fires before `turn_resolution_completed` (`turn_manager.gd:120-124`), so the run summary JSON is written before the final turn's row and never updated; `building_count` also counts ~470 NPC scenery buildings (`run_metrics.gd:206`). |
| MEDIUM | **Tax has no loss carry-forward and mis-times deferred revenue** (`production.gd:484-513`): lumpy/long-haul empires alternate untaxed-loss and fully-taxed-profit turns, paying materially more tax than smooth empires with identical totals. |
| LOW | Merge scar: mangled comment `# === LOAN INTEREST PAYMENTS ==+var loan_payment...` and a mis-indented phase banner at `production.gd:406-419` — the exact spot where a future edit reintroduces per-building loan processing. |
| LOW | `summary.consumed["power"]` mixes power units into goods totals, inflating RunMetrics `units_consumed`. |

---

## 2. Production & energy

### Working well
- Tile-aggregated market ordering with per-turn quote memoisation, fixing a documented starved-duplicate bug (`production.gd:1598-1634`).
- CostSolver does market-value byproduct allocation, a topological sweep over the recipe DAG, and mirrors production's level/modifier/workforce scaling in report capture, with the prevented bug documented (`cost_solver.gd:104-161`, `production.gd:958-999`).
- Goods are never silently lost: overflow at full tiles is held and retried; genuine capacity losses are metered as a "silent leak" metric (`stockpile.gd:13-16, 202-208`).
- Input gating, consumption, and market top-up all consistently use `_scaled_input_qty` (verified — an earlier claim to the contrary was wrong).

### Issues
| Severity | Finding |
|---|---|
| MEDIUM | **CostSolver never costs cycle members** (`cost_solver.gd:167-177`): after 20 sweeps the guard seeds goods at market price but buildings in the loop get no `per_building` entry — the known computer→fab→computer loop blanks the RAG indicator for the whole chain the moment it closes. |
| MEDIUM | **Power cap fallback is stale after the ×10 rescale** (`power.gd:29-35` vs `economy_config.gd:165`): comments say 200/400/700, actual caps are 2000/4000/7000, and the `get(level, 200)` fallback would hard-cap a future L4 cable at 200 — a 35× regression. |
| MEDIUM | **Intermittency derate is a 1-turn-lagged output tax that still consumes full inputs** (`production.gd:20-25, 578-584`): wind-heavy tiles quietly destroy up to 40% of inputs, and load-shuffling can dodge the derate entirely. |
| MEDIUM | **Imputed power cost ignores reality** (`production.gd:1004-1005`): every consumer is costed at `GRID_BUY_PRICE` regardless of self-generation or advisor discounts — self-powered empires show red RAG on cash-profitable buildings (matches the known engine-vs-balance.py divergence). |
| MEDIUM | **Derates are neither saved nor cleared on import** (`production.gd:25, 61-70`): first post-load turn runs intermittent buildings at full output; in-session loads can apply a dead match's derate to colliding instance ids. |
| LOW | Stockpile accepts two tile-key formats (`stockpile.gd:218-225`) — the first caller to pass a `Vector2i` splits a tile's stock into two invisible buckets. |
| LOW | Covered seaport sales defer revenue a turn even at distance 0, and port coverage is computed in two places that can diverge (`transport_service.gd:138`, `production.gd:828-830`). |

---

## 3. Labour & people

### Working well
- Additive labour deltas off a 100% base with a hard floor prevent free-labour stacking (`production.gd:1104-1110`, `EconomyConfig.LABOUR_FACTOR_MIN`).
- The People panel's projections reuse the exact accrual function the live tick uses, so UI and sim can't drift (`match_state.gd:3457+`).
- Workforce policies are real, varied, and correctly cadenced (10-turn blocks, HR-gated with revocation when the seat empties).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **The labour slider's advertised output penalty does not exist** (verified). `people_panel.gd:295-315` promises "0.8×: output pressure −2%/turn up to −30%"; `workforce_output_multiplier()` (`match_state.gd:3455-3478`) reads only workforce policies — the slider enters cost only (`production.gd:1104`). Setting 0.8× on turn 1 is a free permanent −20% labour cost. Dominant strategy + UI that lies. |

---

## 4. Markets & price movement

### Working well
- **One unified sell primitive**: all four sell paths converge on `execute_sale` (`market_state.gd:70-224`), which owns routing, pricing, settlement, ledger, and special-order commitment — the correct seam for the missing price-impact hook, and commented as such.
- Anti-arbitrage clamp by construction: sale price ≤ buy price, documented (`market_state.gd:33-40`) — same-turn buy-low/sell-high on the ordinary market is structurally impossible.
- Deferred settlement locks in the quoted price at consume time (`production.gd:633-685`); partial market buys avoid the all-or-nothing starvation cliff (`match_state.gd:2591-2604`).
- Market panel is fully lazy (shell on first open, tabs on first select) and ledger refreshers early-out when hidden.

### Issues
| Severity | Finding |
|---|---|
| CRITICAL | **The glut/price-impact model is never applied** (verified: `price_impact_pct_for`'s only callers are tests). No sale moves any price; players can dump unlimited volume at full price forever. Worse: the auto-sell "impact tolerance" throttles the player's *own* volume against an impact that doesn't exist, and the in-game encyclopedia tells players prices "react to how much you sell" (`search_overlay.gd:103-110`). Fix at the `execute_sale` seam. |
| HIGH | **Manual sells pay zero freight; auto-sells pay full freight** (`market_state.gd:148-153` default `pay_transport_from_seller=false` vs `production.gd:842-859`): clicking "sell from all tiles" every turn strictly dominates the standing-order QoL feature. |
| HIGH | **Price dynamics are monotonic decay with perfect-information forecasts** (`market_state.gd:63-68`): no floor, no recovery, no demand response; over 300 turns prices fall to 22–74% of base while wages compound upward. Correct math, degenerate mechanic — the other half of the missing feedback loop. |
| MEDIUM | **Two sell paths price the same good differently**: `execute_sale` applies `market_price` modifiers via `get_sale_price`; the PROCESS sell phase uses raw `get_price` (`production.gd:837`) — paid-for research silently doesn't apply to the highest-volume path. |
| LOW | Market rows show raw `get_price` while manual sales realise `get_sale_price`; the "+10t" buy forecast ignores the `market_spread` modifier the "Buy now" column includes (`market_row.gd:186-190`). |
| LOW | Unknown good ids silently monetise at the £1.0 default (`market_state.gd:24`). |
| LOW | Building-market rows charge the price captured at row-build time; staleness is unbounded while the panel stays open (direction always favours the market). |

---

## 5. Special orders

### Working well
- Robust lifecycle: own seeded RNG saved with state, re-entry watermarks, warning dedupe, premium computed only on required units (`special_order_state.gd`). Mid-order save/load is genuinely covered, including in-transit tagged shipments and the expiry → resolution-dialog handoff with capacity pre-checks.
- Expiry ordering verified correct: arrivals during PROCESS of the deadline turn still count.

### Issues
| Severity | Finding |
|---|---|
| HIGH | **Market-buy → special-order arbitrage**: deliveries bypass the buy-price clamp and pay a 25–40% premium with no provenance check (`market_state.gd:130-134`, `special_order_state.gd:23-26`; all 16 order goods are buyable). Buy at ×1.05, deliver, collect base + 40% ⇒ riskless ~33% margin every order spawn. Stacked `market_price` modifiers widen it. |
| MEDIUM | **Over-commitment is unbounded on the production-routed path** (`special_order_state.gd:343-362`): a routed factory keeps committing full output past `qty_required`, triggering the overflow dialog every turn and corrupting `qty_committed/delivered` for UI. |
| LOW | Overflow shipments are paid at the recorded (uplifted, stale) order price while the dialog claims "normal market price" (`match_state.gd:2839-2859`). |
| LOW | `committed_shipments` is created, saved, and never read — dead state implying tracking that doesn't exist. |

---

## 6. Loans & money integrity

### Working well
- Per-loan baked rate/term so mixed-term loans amortise correctly; borrowing capacity has an explicit, well-commented profit gate so revenue alone can't unlock credit (`loan_state.gd:175-203`).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **Principal repayment is booked as interest and shields tax** (verified): `summary.interest_paid = loan_payment` — the full amortised payment — lands in `money_out`, and tax is `money_in − money_out` (`production.gd:416-418, 505`). Borrowing systematically reduces lifetime tax; the money panel and RunMetrics `cost_interest` are wrong by the same amount. LoanState already computes the interest split (`loan_state.gd:115-118`) — production just doesn't use it. |
| MEDIUM | **Early repayment charges all future interest** (`loan_state.gd:56-67, 79-98`): repay next turn, pay the full baked 10% — perverse alongside the `AGENDA_EARLY_LOAN_PAYOFF` reward, and `total_outstanding()` overstates debt in metrics. |
| MEDIUM | Capacity is sized for 36-turn/10% debt service, but construction loans repay at 3.4× that rate (`loan_state.gd:201`) — a fully drawn facility of construction loans forces negative cash. |
| MEDIUM | Interest (~0.28%/turn) is far below building returns: permanently maxed debt is always correct; the loan system has no decision after ~turn 10. |
| LOW | Loan-failure toast missing: a failed `take_loan` prints to console and opens the Loans tab as if it succeeded (`bottom_menu.gd:428-431`). |

---

## 7. Construction, buildings & upgrades

### Working well
- Clean lifecycle isolation: projects never live in `MatchState.buildings`; stable `instance_id` reserved pre-build and carried through promotion (`construction.gd:1-12`).
- Material-race prevention with documented rationale: awaiting builds and upgrades reserve on-tile kit immediately; awaiting builds self-heal by re-ordering missing materials net of inbound (`construction.gd:144-152, 249-265`, `match_state.gd:868-873`).
- Atomic upgrade validation — research, footprint, affordability, and routes all checked before anything is consumed (`match_state.gd:845-866`).
- Correct turn ordering: arrivals → construction tick → claims → reorders → upgrades → production, so completions produce the same turn.
- The refund model refunds what was actually paid (density-adjusted, rebate-net cost stamped at promotion; capacity-aware material/cash split) — well built, currently unreachable (see below).

### Issues
| Severity | Finding |
|---|---|
| CRITICAL | **Upgrade-rebate cancel pump** (verified): Chief-Investment's rebate is paid as cash at `start_upgrade` (`match_state.gd:898-900`) and `cancel_upgrade` (`match_state.gd:948-977`) returns the full banked kit with no clawback. Start/cancel in a loop nets 10% of the kit's market value per click, unbounded, within one turn. The *build* path nets the rebate off the price correctly — only upgrades leak. |
| HIGH | **Demolish doesn't exist but three UIs promise it**: deposit dialogs offer Demolish/Change Recipe wired to `pass` (`world_map.gd:1611-1619`), the tile-full error says "Demolish buildings to make room", and the whole refund system has zero callers. A blind-built mine on a barren tile is a permanent, maintenance-draining trap. |
| HIGH | **Infrastructure "upgrades" take money, materials, and research for zero effect**: the ledger's upgrade button works on infra instances and bumps instance `level`, but all gameplay reads the tile's `infrastructure_levels` dict, written only by the hardcoded demo table (`building_ledger_panel.gd:657-678` vs `match_state.gd:3069`, `power.gd:74`, `world_map.gd:1793-1818`). |
| HIGH | **Capacity dialog's "Expand storage +500" and "Stop production" are `pass` no-ops** with a real-looking cost card and a "don't ask again" latch (`capacity_dialog.gd:102-105, 142-155`) — overflow then looks like an engine bug. |
| MEDIUM | **Latent demolish money traps, armed for the day demolish ships**: (a) NPC-bought buildings have no stamped `build_cost`, so `refund_cost` falls back to full `base_price` + full kit at market value — buy at 0.70× variation, demolish for guaranteed profit plus granted land (`building_price.gd:21-34`, `match_state.gd:1000-1048`, `demolish_refund_share = 1.0`); (b) cancelling construction at T-1 refunds 100% while demolish would refund a share — free option value. Stamp purchase price on ownership change *before* wiring demolish. |
| MEDIUM | `start_upgrade` doesn't check `is_retooling` (guard asymmetry with `start_retrofit`) — level bumps mid-retool against the wrong recipe (`match_state.gd:813-830` vs `599-605`). |
| MEDIUM | The construct panel's affordability gate reads a `"cost"` key that doesn't exist (catalog uses `base_price`), so the whole unaffordable-red-flash UI is dead; money is only checked at final deduct (`construct_panel.gd:469-470`). |
| MEDIUM | Four more buildings have the farm bug today: `consumer_factory`, `old_forest`, `landfill`, `ruins` are listed/buildable with zero active recipes — clicking silently no-ops (`catalog.gd:650-666` + `construct_panel.gd:255-263`). |

---

## 8. Advisors

### Working well
- Where wired, advisor effects are real: seat modifiers for 7 of 10 seats resolve through domains the sim genuinely consumes (labour, tax, dividends, maintenance, power prices, spreads, loan interest, transport, purchase cost, rebates), the reconciler is idempotent with stable ids, and master-builder's build-turn discount works (`match_state.gd:3734-3759, 1859-1871`).
- Save/load hygiene: sanitizers drop unknown advisors, enforce employed ⊆ recruited, and permanent mission modifiers re-apply with stable ids after registry import so they replace rather than duplicate.
- Salaries, loyalty→walk churn, fire cooldowns, slot unlocks, and free research grants all function.

### Issues
| Severity | Finding |
|---|---|
| MEDIUM | **Three seats emit zero modifiers**: `technical_director`, `sustainability`, and `research_director` (which also has no roster advisor or mission template — a fully dead seat that `assign_advisor_to_seat` happily fills). Seat slots are capped at 2–5, so filling one with a dead seat has real cost (`match_state.gd:3532-3569`). |
| MEDIUM | **All advisor trait "specialties" except Gerald's are decorative text** — churn-slowing, extra labour cuts, silo malus, sale-price boosts, debt-risk all appear in bios but not code, while salaries (1.0–4.0/turn) are very real. Players pay for effects that don't apply (`match_state.gd:3512-3525, 4193-4206`). |
| LOW | `_update_advisor_slots` re-grants seat unlocks every turn, relying solely on `grant_unlock`'s idempotence guard. |

---

## 9. Research & tech gating

### Working well
- The unlock engine itself is solid: prereq checking, live conditions, NARRATIVE-phase re-evaluation after production settles, idempotent grants (`match_state.gd:1396-1466`).
- All 42 upgrade-gate titles and all 106 code-side `UNLOCK_MODIFIERS` keys resolve to real CSV titles — the code↔CSV contract is well maintained where exercised.

### Issues
| Severity | Finding |
|---|---|
| HIGH | **Research gating is UI-cosmetic only**: only the construct panel filters gated recipes; the search overlay indexes `Catalog.all_recipes()` unfiltered and its Build button goes straight to placement — neither `world_map._on_build_attempted` nor `Construction.start_on_tile` checks `required_research`. Any of the ~47 gated recipes is buildable on turn 1 (`search_overlay.gd:263, 486-496`, `world_map.gd:1295-1366`). |
| HIGH | **95 of 231 research nodes can never auto-fire**: `_live_condition_met()` handles only 5 action types — all 41 `Run`, 16 `Own`, 15 `Sell`, 1 `Sustain` rows are dead — and `_count_buildings()` compares against `internal_name` while ~55 rows use Title-Case display names (`Mine`, `Furnace`, `Oil Refinery`…). 16 gated recipes (incl. all offshore oil and water recycling) are reachable only via free picks (`match_state.gd:1448-1487`). |
| HIGH | **Hydro is permanently unreachable**: building b_027 and recipe r_224 gate on title `hydro`, which doesn't exist in `research_unlocks.csv` (noted as possibly intentional cheat-gating — if so, hide the building; today the player sees a dead entry). r_166/r_167 gate on nonexistent `consumer`. |
| MEDIUM | **Free research unlocks are a session-local UI variable**: not saved, reset to 2 on every panel construction, decremented even when clicking an already-unlocked node, and never prereq-checked — bankable/farmable across reloads and spendable on rank-4 nodes directly (`research_panel.gd:67, 98, 611-622`). |
| MEDIUM | "Run Profitable" conditions compare unit cost to `base_price` while the ledger shows Net/t against live prices — unlocks appear stuck for no visible reason (`match_state.gd:1499-1511` vs `building_ledger_panel.gd:447`). |
| LOW | The research tree re-parses the CSV with its own column handling instead of reading `_unlock_defs` — silent drift risk. |

---

## 10. Victory

### Working well
- Read-only observer, win latched once (cannot double-fire), no re-emit on load, scored-turn captured during PROCESS to dodge the increment off-by-one, monotonic `track_best` per design (`victory_state.gd:175-223`). **No false-trigger, never-trigger, or double-fire paths found.**

### Issues
| Severity | Finding |
|---|---|
| LOW | Richest track reuses `_last_summary` if `turn_processed` ever fails to fire; `_scored_turn` isn't saved, so the first post-load breakdown renders against stale context. Display-only. |
| LOW | By-design but worth confirming: market buys count in the Logistics track's numerator and denominator, so port-adjacent buying inflates Logistics efficiency. |

---

## 11. Transport & logistics

### Working well
- Transport cost is real economics: moves consume stock, quote manifests, debit money; congestion surcharges feed back from last turn's flow (stable, not self-referential) (`match_state.gd:2371-2378, 3163-3198`).
- Routing solver rewritten O(V²)→O(V+E) with a documented correctness argument, memoised per (src, dst, modes), invalidated exactly on route-affecting infra changes (`catalog.gd:414-460, 260-262`).
- In-place shipment countdown replaced a documented deep-copy hotspot (`match_state.gd:2987-3003`).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **Fluids bypass the pipe-only rule on all tile-to-tile moves**: `quote_manifest` routes with `route_good_id=""` and `_modes_for_good("")` tolerates all modes — gas hauls overland at solid rates with zero pipes; the rule only binds market buy/sell quotes (`transport_service.gd:71-74`, `catalog.gd:365-374`). |
| HIGH | **Unreachable routes silently fall back to a straight-line haul that can beat real routes**: no path → `ceil(distance/2)` turns, empty legs, flat rate, zero congestion — an island with *no* connection quotes fewer turns and less money than the same distance overland (1 tile/turn). Pathfinding failure is surfaced nowhere (`transport_service.gd:36-38`, `economy_config.gd:211-238`). |
| MEDIUM | Transfers drive money negative with no check — inconsistent with `deduct_money` gating everywhere else (`match_state.gd:2377-2378`). |
| MEDIUM | **Demo infrastructure leaks into live balance**: `_apply_demo_infra_levels` injects hardcoded pipes/rails onto 8 tiles in every match via the real routing map — free 0.5×-cost rail legs through tiles 7_1–7_4 (`world_map.gd:1793-1818`). |
| MEDIUM | Free `"roads"` infrastructure on every enclosed urban tile at match start — urban starts get zero-cost road routing from turn 0 while rural players pay per tile (`road_works.gd:282-288`). |
| LOW | Malformed tile ids quote 0-distance, £0 transport (`catalog.gd:162-171`) — a data typo becomes free logistics. |

---

## 12. Map, roads & terrain

### Working well
- Bake-once terrain pipeline with MD5 staleness checks and cross-checked bakes (`hill_baked.gd:37-39`, `roads_baked.gd:29-31`); hybrid vector/texture LOD hill rendering with deferred GPU bake is textbook (`hill_visuals.gd`).
- Resumable, corridor-local A* road router with reusable scratch buffers, coarse-first hierarchical routing, and a 6 ms/frame budgeted planning pipeline with telemetry (`road_realizer.gd`, `road_works.gd:474-506`).
- Determinism discipline: explicit FNV-1a for all persisted seeds, sorted iteration where order matters, `ForestFootprint` as single source of truth for visuals and routing obstacles.
- Survey/deposit flow verified sound: double-survey blocked twice, depletion emits exactly once, blind builds reveal-or-warn correctly.
- Road save/load round-trip verified: geometry, resumed orders, idempotency markers all persist; no double-linking on reload.

### Issues
| Severity | Finding |
|---|---|
| HIGH | **RoadOffshoots does a full-map synchronous rebuild on every building event** (`road_offshoots.gd:44-52, 89-116, 404-493`): flattens every geometry point of every edge, then per candidate stub scans all segments — a multi-ms-to-100 ms+ hitch per placement late-game. The likeliest source of late-game placement stutter. |
| HIGH | **Attachment search and degree counting scan the whole network inside one unbudgeted planning unit** (`road_works.gd:426-470, 1047-1063`): once the network is big, a single `_begin_next` blows the 6 ms budget by itself, and a 100-order mass build rescans the growing network 100 times. |
| MEDIUM | **Failed road-connect orders are invisible**: the order fails to `failure_log` only; the tile's routing flag was already applied at construction, so the player paid, gets routing, but never sees a road and gets no toast/refund/retry (`road_works.gd:534-546`). |
| MEDIUM | **Nothing in the transport graph can ever be removed**: no `remove_edge`, `remove_tile_infrastructure` has zero callers, stale enclosure rings documented as kept — any future demolish/disaster desyncs visuals, occupancy, and routing. |
| MEDIUM | Road/forest occupancy is feature-flagged off (`OCCUPANCY_ROADS_ENABLED := false`), so buildings can straddle drawn roads and sit under forests; the visual world and buildability substrate disagree until the Phase-5 cutover flips. |
| MEDIUM | RoadNetworkVisuals: per-frame edge polling for change detection (despite `order_settled` existing as the real signal), and full static redraws per settle that walk all 600 tiles + hulls + per-vertex clipping (`road_network_visuals.gd:31-126`). |
| MEDIUM | Route-cache invalidation is global per network change; the following turn's re-quote burst (recurring moves, port quotes, tile-panel labels) lands inside PROCESS (`catalog.gd:260-262`). |
| LOW | `roads_visible` is a static that survives scene changes — toggle the debug cheat, start a new game, roads render hidden (`road_network.gd:34`). |

---

## 13. Overlays & map modes

### Working well
- `MapMode` is a genuine single source of truth: all overlay state in one autoload with a small signal API; two-overlays-at-once is structurally impossible (`map_mode.gd:51-106`).
- `survey_overlay.gd` is a model citizen: no `_process`, signal-driven redraws, meshes merged into a handful of draws with RID-lifetime comments; `deposits_overlay.gd` needs no redraw on pan and caches all textures.
- `toast_manager.gd` and `notification_bell.gd` show real defensive craft: deferred-free loops avoided, refresh coalescing, re-entrancy guards, capped rows.

### Issues
| Severity | Finding |
|---|---|
| HIGH | **MapMode never resets on load/new game**: scene reloads rebuild overlays but the autoload keeps `current_mode` — stale Surveying mode routes every left-click to survey dialogs with zero visual cue, the mode button appears latched/dead, and deposit filters carry into a different game. One `MapMode.clear_all()` in the load path fixes it (`map_mode.gd:35-42`). |
| HIGH | **Logistics overlay rebuilds all route data every frame**, deep-duplicating the entire shipments array 2–3× per frame via `get_pending_transport_shipments()` (`logistics_overlay.gd:391, 461-658`; `match_state.gd:2823-2824`) — sustained allocation churn on the one map mode players leave open. |
| MEDIUM | Logistics legend only rebuilds on `selections_changed` while route colours re-assign every turn — legend and map lines desync until the mode is toggled (`overlay_legend.gd:96-107`). |
| MEDIUM | Power overlay checks raw `has("cables")` while the infra overlay normalises entries — a levelled/renamed entry format silently classifies powered tiles as `cables_missing` (`map_overlay.gd:804`). |
| MEDIUM | PanelStack's focus-watcher recursively connects `gui_input` on every Control of every pushed panel forever, with no unwatch — hidden O(subtree) cost on every dynamic row insertion in the churniest panels (`panel_stack.gd:53-76`). |
| LOW | Build mode doesn't clear an active map mode — two ~90%-alpha dims stack into a near-black map; right-click-exit is implemented twice; water mode ignores survey status (information-policy inconsistency); a stray `print` fires every turn (`map_overlay.gd:108`). |

---

## 14. Empire view

### Working well
- Clean lifecycle: enter/leave side-effects hang entirely off `visibility_changed`, so Tab and Esc share one path; hidden world layers are recorded and exactly restored (`empire_view.gd:78-135`).
- `empire_layout.gd` is pure, deterministic, seeded via RoadHash, cycle-guarded, and exposes its invariant for tests.

### Issues
| Severity | Finding |
|---|---|
| HIGH | **The animated hex background is O(samples × buildings) per frame**: ~18k brightness samples/frame, one anim scanning every building origin per sample (100 buildings ≈ ~1.5M distance calls/frame), plus ~600 polyline draws — the empire view becomes the most expensive screen in the game exactly as the empire grows (`empire_hex_bg.gd:110-225`). |
| HIGH | **O(n²) panel separation + full edge re-routing every frame with no dirty check** (`empire_graph_world.gd:96-122, 261-281`): 100 buildings ≈ 140k pair-iterations/frame plus fresh polyline arrays per edge, stacked on the background above. Gate on view-change. |
| MEDIUM | **The graph goes stale while open**: it rebuilds only on `_enter`, but the click-through path (node → detail panel → demolish/level/turn resolution) can mutate state behind it — stale nodes, dead instance ids on re-click (`empire_view.gd:85-104`). |
| MEDIUM | Tab isn't gated on modal state (interleaves the panel stack with open dialogs), and an interrupted drag leaves `_dragging = true` so the next open pans on bare mouse motion (`world_map.gd:1900-1905`, `empire_graph_world.gd`). |
| LOW-MEDIUM | Sell-edge heuristic: any consumer of a good anywhere suppresses market-sale edges for *all* its producers — wrong exactly for the common mixed use-and-sell economy (`empire_graph.gd:133-149`). |

---

## 15. Save/load

### Working well
- Versioned saves with stepwise one-rung migrations, readable rejection of newer saves, tolerant-reader imports everywhere (old saves missing whole subsystems load as fresh-zero without a version bump), and market re-seeding so goods added since the save get base prices (`save_load.gd:14, 447-499`, `market_state.gd:53-63`).
- One orchestrated snapshot path shared by new game, load, and scenarios; imports are silent with refresh signals re-emitted once at the end; the historic audio-on-load bug class is genuinely fixed by design (`save_load.gd:55-132`).
- RNG state round-trips (match RNG + special-order RNG) — determinism survives save/load; the only unseeded RNGs are visual-only.
- Macro load order verified correct: infrastructure applied to routing before snapshot import, so shipment re-quotes see the loaded network.

### Issues
| Severity | Finding |
|---|---|
| CRITICAL | **Loading mid-turn-resolution corrupts the loaded state**: `save_slot` refuses to save outside DECIDE, but `load_slot` is reachable mid-resolution via Esc → Pause → Load; TurnManager's suspended resolution coroutine survives the scene change and resumes over the freshly imported snapshot — phantom phase emissions, an extra `current_turn += 1`, extra price decay and order spawns. One `is_resolving` guard fixes it (`save_load.gd:152-179`, `turn_manager.gd:92-129`). |
| MEDIUM | **Non-atomic writes**: saves overwrite the slot in place with no temp-file + rename — a crash mid-write destroys both old and new copies of the slot (`save_load.gd:144-149`). |
| MEDIUM | **Valid-JSON-but-wrong-shape saves crash mid-import** after MatchState is already reset — worse than a load failure. Only "is a Dictionary" is validated (`save_load.gd:165-172`). |
| MEDIUM | **Autosave stringifies the whole pretty-printed state synchronously on the main thread** every 10th end-turn — a hitch that grows with road mileage and ledgers (`save_load.gd:43-51, 148`). Thread the stringify+write; drop the `"\t"`. |
| LOW | Autosave rotation index isn't persisted (freshest autosave is destroyed first after a restart); the save screen silently overwrites existing slots including `autosave_1`; `list_slots` fully parses every save to show 4 meta fields; chart history and camera/map-mode session state silently reset on load; version-history comment is stale. |

---

## 16. Data layer

### Working well
- Zero duplicate IDs anywhere; unique internal names; clean research prereq graph; all code-side modifier/battery/hardcoded titles resolve. `start_buildings.json` (472 entries) and all 7 starts are fully referentially valid — the newest generated data is the cleanest.
- The catalog's promotion gate is a deliberate, documented design that makes the game robust to the maximalist recipe pool; `BUILDING_ALIAS` is mirrored exactly in `tools/balance.py`.
- Defensive parsing throughout: header-order independence, graceful missing-file/font fallbacks, route-cache invalidation with rationale comments.

### Issues
| Severity | Finding |
|---|---|
| CRITICAL | **The recipe generator would destroy the live data**: `recipes_master_source.csv` is a different data generation — same recipe_ids denote different recipes (173/199 rows differ per-field), and it has no `required_research` column. One documented `python scripts/build_recipes_all.py` run wipes the entire turn-1 rebalance and all 58 tech gates. Quarantine or delete the generator + master source. |
| HIGH | **63 of 199 recipes are silently dropped by the promotion gate with zero logging** (26 phantom goods, 3 unresolvable buildings) — the only symptom is content that never appears. Includes a genuine data-entry bug: r_109 has an output with an empty qty, silently eaten. |
| HIGH | **The Python validator validates the wrong dataset**: repo-root `data/` is a stale, differently-named generation (24 goods exist only there, under different naming conventions), `pytest` isn't installed, and the validator CLI itself exits 1 on its own data. The right validator pointed at the wrong files. |
| MEDIUM | 10 recipe `requirements` tokens (`river`, `deep_sea`, `2 farms`, `urban AND waste_water`…) parse to `type:"other"` and are enforced by nothing — designer-written placement restrictions simply don't apply (`catalog.gd:687-715`, `construct_panel.gd:413-427`). |
| MEDIUM | `deposit:brine` exists on no map tile; 18 recipes have empty categories (modifier-blind if ever promoted); dead data files with colliding recipe_ids sit in `data/` (`recipesMVP.csv`, `goods.csv`, `recipes.csv`, master source, 69 KB `goods_flow.json` read by nothing). |
| MEDIUM | `tools/balance.py` cost constants are a hand-maintained copy of `economy_config.gd` values (the known ~3× divergence) with no sync check. |
| LOW | 8 goods lack icons; 4 orphan icon files; 15/76 goods have empty categories; `high_grade_silicon` is neither produced nor consumed by any active recipe; rows shorter than the header are discarded with no log. |

---

## 17. Tests

### Working well
- Genuinely strong for a solo EA project: 183 GDScript test funcs / ~544 headless checks with correct exit codes, a 137-check UI-driven E2E with a benchmark baseline, regression tests written for past data bugs (farm buildability, research promotion, save migration).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **No test validates the datasets the game actually loads.** Nothing asserts recipes↔goods↔buildings↔research referential integrity — every data finding above (hydro gate, 95 dead conditions, Title-Case object typos, r_109's lost output, consumer_factory) shipped silently. A ~50-line integrity test closes most of section 16. |
| MEDIUM | Hardcoded catalog counts (76/37) break the suite on every legitimate data addition — the known recurring failure. |
| MEDIUM | The E2E isn't run by `tools/run_tests.py` (separate scene), so the richest integration test can rot unnoticed; Python tests are unrunnable (`pytest` missing) and target stale data. |
| Gap | No test that research conditions are satisfiable, that every non-infra building has ≥1 active un-gated recipe, no generator round-trip check, no balance.py↔economy_config sync check. |

---

## 18. Performance & load times (cross-cutting)

### Already done well (credit where due)
- LoadPacing gate + threaded scene load + split `world_map._ready` work as designed; tests stay synchronous.
- Hill pipeline is exemplary (baked, sliced triangulation, cached meshes, deferred 4096-px texture bake); roads baked; route/port caches kill route-count growth; MarketPanel fully lazy; NPC pool excluded from the sim; shipment handling de-hotspotted; ~30 `_draw` widgets all correctly signal-gated; all checked histories are capped (ledgers 500, charts 10 turns, victory windows popped, toasts freed).

### Issues
| Severity | Finding |
|---|---|
| HIGH | **Load Game does two full synchronous layout passes with zero yields**: `_rebuild_after_load` replays every placement, then `finish_build` → `relayout()` clears and replays them all *again* — the code's own comment prices a full layout at ~7 s. The exact freeze class the new-game path already fixed (`world_map.gd:305-348`, `building_visuals.gd:609-622`). |
| HIGH | **New-game placement is frame-quantised at 1 building/frame**: 472 NPC entries × `await process_frame` ≈ 7.9 s at 60 Hz regardless of CPU — now the dominant floor on time-to-Begin. A 25–35 ms time-budget batcher (the hill-warming pattern) cuts it several-fold (`world_map.gd:1520-1538`). |
| HIGH | **Money panel rebuilds the loan list on every `money_changed`** — which fires per building payment during PROCESS — with no visibility guard: 200+ teardown/instantiate cycles per turn while hidden (`money_panel.gd:135, 167-203`). Found independently by two audits. |
| MEDIUM-HIGH | **Tile info panel rebuilds its entire pane per stockpile mutation** (15 signal hookups, no coalescing, unlike the ledger's deferred pattern): hundreds of full rebuilds in one resolution burst with the panel open; each rebuilt child also gets PanelStack watch connections (`tile_info_panel_v2.gd:82-101, 486-491, 659-667`). |
| MEDIUM | Market panel refreshes all ~130 rows + rebuilds special orders per turn once built, even hidden (`market_panel.gd:831-837`); each row also self-refreshes twice per turn forever; special-order rows fully rebuild on every `orders_changed` (several per producing building per turn). |
| MEDIUM | Money-panel projection runs pathfinding per building output on every price tick / building change while hidden (`money_panel.gd:384-465`). |
| MEDIUM | Market-input top-up scans all pending shipments (with a dict duplicate per match) once per demanding (tile, good) pair — an index by destination tile makes it linear (`production.gd:1593-1657`, `match_state.gd:2974-2985`). |
| LOW-MEDIUM | `Modifiers.apply` linearly scans the whole registry per call, and it's called per building per cascade pass across ~6 domains — late-game this is the sim's biggest hidden multiplier; a domain index cuts ~90% (`modifier_state.gd:396-432`). Power reads the scene tree (`get_first_node_in_group`) per building per pass in the hottest loop (`power.gd:64-74`). |
| LOW-MEDIUM | The cascade is worst-case O(passes × buildings) with starved buildings fully re-checked every pass — bounded (cap 30) and profiled, but the first thing to feel superlinear (`production.gd:182-261`). Stockpile capacity math recomputes per mutation. |
| LOW | TurnProfiler + RunMetrics do synchronous per-turn file I/O in shipped builds with unbounded, never-rotated CSVs; the 8.5 MB hills JSON parses in one frame and its raw Variant tree lives forever in a static; `.godot` is 611 MB / `assets/` 337 MB (editor/CI weight only); loading screen's own hex background competes for the frames LoadPacing rations. |
| Note | The dedicated memory sweep was cut short: instantiate-churn sites and long-session node counts were spot-checked (all clean), but no runtime heap profiling was done. |

---

## Cross-cutting themes

1. **"Wired but dead" UI is the biggest trust risk.** Demolish, Change Recipe, Expand Storage, Stop Production, infra upgrades, advisor specialties, three advisor seats, the labour slider's output penalty, the affordability flash, and the auto-sell impact tolerance all *look* functional and do nothing (or in the infra case, take real resources). Each is individually small; together they teach players the UI can't be trusted. Recommend a sweep: every control either works or is visibly disabled with a "coming soon" tag.
2. **The economy has no negative feedback anywhere.** No price impact from selling, no bankruptcy, monotonic price decay with perfect forecasts, loans strictly dominant, manual-sell freight-free. Each alone is a balance knob; together they mean optimal play is degenerate ("build max, sell all, borrow max, never repay early"). The `execute_sale` seam + an `add_money` floor + the interest split are three small changes that restore most of the tension.
3. **Silent failure is the house style, and it's costing content.** The promotion gate, requirement parsing, road-order failures, unknown goods, and short CSV rows all fail silent-by-design. The mechanism is fine; the observability isn't. A debug-build validation report (and one data-integrity test) converts weeks of future mystery bugs into a checklist.
4. **The rebuild-the-world-per-signal UI pattern needs one shared fix.** money_panel, tile_info_panel_v2, market_panel, construct_panel, and stockpile_view all rebuild fully per `money_changed`/`stockpile_changed` emission. The codebase already contains the right pattern twice (`notification_bell.gd`'s deferred coalescing, `building_ledger_panel.gd`'s `_request_refresh`) — apply it to the other five.
5. **Save/load and determinism discipline are genuinely excellent** — versioning, migrations, RNG round-trips, seeded visuals, signal-silence on import. The one CRITICAL hole (mid-resolution load) is a one-line guard.
