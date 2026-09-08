# Tutorial aluminium economics, 8 September 2026

The aluminium investment improves the business, but the upgrade barely improves it further. The scheduled port fee increase, mandatory tutorial loan, and storage of the coastal lesson shipment then consume the margin. This is an actual cash issue, not a stale forecast. No balancing constants or recipes were changed in this investigation.

## Controlled comparison

The headless harness runs the real turn pipeline on Stoneshore Fields (tile_5_9), one tile from Stoneshore Docks. It buys market inputs and grid power, sells windows and unreserved aluminium, and includes owned cable and reinforced pipe upkeep. Both Furnace recipes produce 20 aluminium, of which the window factory consumes 10. No advisors, loans, unlocked research bonuses or construction finance. The researched recipe is installed directly to isolate operating economics. Construction and retooling outlays are excluded. Six startup turns precede ten sampled turns; assertions require both buildings to produce during every sample. Prices and costs evolve normally. These are controlled comparisons, not a replay of the attached save.

| Company | Average cash per turn, turns 16 to 25 | Average cash per turn, turns 36 to 45 |
| --- | ---: | ---: |
| Windows with market aluminium | £12.20 | £0.42 |
| Windows plus Hall Heroult Furnace | £21.06 | £6.98 |
| Windows plus Carbochlorination Furnace and pipe | £21.50 | £7.71 |

The port ad valorem rate changes from 0.5% to 3% at turn 31, plus the existing annual drift. For the integrated companies, average transport charges rise from about £9 to £23 per turn between these windows. The tutorial can reach that transition while demonstrating the benefits of integration.

## Why Carbochlorination adds so little

| Cost per turn in the later sample | Hall Heroult chain | Carbochlorination chain |
| --- | ---: | ---: |
| Sales | £319.61 | £319.61 |
| Market inputs | £198.03 | £195.29 |
| Grid power | £33.60 | £26.40 |
| Labour | £40.31 | £43.27 |
| Maintenance including infrastructure | £15.00 | £19.00 |
| Transport including port charges | £23.26 | £23.55 |
| Warehousing | £2.44 | £4.38 |

The new recipe saves about £9.94 per turn in inputs and electricity. Extra labour (£2.96), reinforced pipe upkeep (£4), storage (£1.95) and net transport (£0.29) absorb about £9.20. Both recipes still make 20 units, so revenue is unchanged. The resulting upgrade is worth only £0.74 per turn in this controlled later sample.

The new recipe buys 20 bauxite, 3 graphite and 20 chlorine. At the prices in the supplied log, their costs before the market markup are £33.74, £38.06 and £27.93 respectively. Graphite is the largest individual material expense.

## What the supplied run shows

* Turn 30: Hall Heroult chain makes £16.16 after the initial surplus spike has passed.
* Turns 35 to 38: the new recipe loses roughly £6.62 to £6.78 per turn. Loan repayment is now £7.34 each turn.
* Turn 41: sales £319.61, inputs £195.27, grid £26.40, other operating costs £95.41 and loan repayment £7.34 leave a £4.80 loss.
* Turn 42: reductions in recipe power, labour and maintenance coincide with a higher aggregate operating bill. The overall result worsens to a £9.12 loss; cheaper production alone does not imply a worthwhile advisor after salary.
* Turn 48: window sales rise by £12.17, from £243.44 to £255.61. Aluminium sales remain £76.18. With inputs £195.24, power £21.92, other costs £104.95 and loan repayment £7.34, cash increases by £2.33. The log does not identify the source of that 5% window sales bonus, so it should not be attributed to a specific advisor or research reward without the save.

The supplied log groups labour, maintenance, advisor salaries, transport and storage into one costs number, so it cannot independently identify every overhead. A seventh controlled case retains the same 64 windows at Stoneshore Coast. This adds exactly £5.1749632 per turn in warehousing, reducing the upgraded chain from £7.71 to £2.54. Subtracting the logged £7.34 repayment gives a £4.80 loss, matching turn 41. This reproduces the loss without any advisor. The financial pipeline is charging real tutorial leftovers; the later advisor and sales-bonus effects are additional.

## Recommended balancing direction

1. Finish the coastal shipment lesson by teaching the player to sell or move its remaining windows. Changing the factory destination back to Market does not clear the stock already at Stoneshore Coast. Clearing it removes £5.17 of recurring storage, but that alone still leaves almost no margin after repayment.
2. Keep the early port fee for the duration of the guided tutorial, or move its increase after the player has completed the integration lesson. Otherwise the clock counteracts the lesson while the player is reading.
3. Give the researched recipe a material improvement after full infrastructure overhead. A candidate is reducing graphite from 3 to 2 while keeping output at 20. That saves about £13.32 per turn at the logged market buy price, before smaller freight/storage changes and taxes. This is an estimate, not an implemented or simulated rebalance.
4. Judge the tutorial outcome after the £7.34 repayment and advisor salary. A recipe-only cost ratio below market is insufficient evidence that the company earns an attractive return.

Reproduce: run `res://tools/tutorial_aluminium_audit.tscn` headlessly. It writes full turn-by-turn accounting to `/tmp/tutorial-aluminium-audit.json`.


## Approved follow-up: coastal cleanup and recipe improvement

The completed coastal delivery lesson now clears its delivered windows after the one-second animation hold. It also clears subsequent window arrivals there while the tutorial continues, since the factory route deliberately stays unchanged until the later Market lesson. No sale or cash reward is created by this cleanup. Other goods and the window factory stockpile are unaffected.

Carbochlorination now requires 17 bauxite instead of 20. Its 3 graphite, 20 chlorine, 20 aluminium output, electricity demand and labour are unchanged. In the later ten-turn sample, its chain cash profit rises to £13.41 per turn against Hall Heroult's £6.98: an improvement of £6.43, meeting the requested £6 to £7 target. The harness asserts that band. Early-period retained cash is £25.07 versus £21.06 (about £4.01 more after taxes and dividends); the gross operating improvement is similar, but the earlier profitable company pays more tax and dividends. After the logged £7.34 loan repayment, the later clean chain would retain about £6.07 before any advisors.

Port fee rates are unchanged. The pre-change snapshot is `data/balance_baselines/2026-09-08_pre-carbochlorination.csv`. The live `recipes_all.csv` is edited directly because `build_recipes_all.py` explicitly identifies itself as a retired bootstrap, refuses to run, and would remove this recipe and reset existing balance values.
