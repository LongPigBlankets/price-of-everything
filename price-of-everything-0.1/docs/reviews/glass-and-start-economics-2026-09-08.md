# Glass tutorial and shipped-start economics audit

Compared current commit 81203e4b with ff8fe682 (before the Aluminium recipe
rebalance, coastal tutorial stock clearing and permanent introductory port rate).
The baseline used isolated copies of scripts and data; the working checkout was
not reverted.

## Glass tutorial

Real turn-resolution comparison at Stoneshore Fields, with the window factory,
market inputs, grid power, on-tile glass supply and automatic surplus sales.
Owned cable and reinforced pipe upkeep are included. No loans, advisors, research
bonuses or missions. Six warmup turns followed by ten measured turns. The advanced
recipe is installed directly to isolate its running economics; construction and
retool costs are excluded. The same setup as tutorial_aluminium_audit was used,
substituting r_053/r_054 and glass routing, with pipe upkeep for both glass recipes.

| Chain | Old fees, turns 36–45 | Current fees, turns 36–45 | Change |
|---|---:|---:|---:|
| Windows only | £0.42 | £11.50 | +£11.08 |
| Windows + Industrial Glassmaking | £11.82 | £21.20 | +£9.38 |
| Windows + High Strength Glassmaking | £21.30 | £29.13 | +£7.83 |

The glass recipe upgrade adds £7.93 per turn under current tutorial rules.
Early samples (turns 16–25) are unchanged: £12.20 windows only, £21.79 with
Industrial Glassmaking, £29.68 with High Strength Glassmaking. Later results
remain a little lower because gradual operating-cost and fee drift still apply.
These controlled values are not promises about a player's cash after their loans
or chosen advisor salary.

The glass tutorial currently waits three turns before its first profit review.
After switching to High Strength Glassmaking it moves directly to the advisors
chapter; unlike Aluminium, it has no separate post-upgrade profit review.
No tutorial-flow or balance changes were made in this audit.

## First ten turns of shipped starts

Ran each start through SaveLoad.prepare_new_game and the real main scene using
`tools/start_probe.tscn -- <start> 10`, with its authored inventory, infrastructure,
labour policy, start modifiers and loans. No new buildings or advisor selections.
Normal automatic research remains enabled. All ten reported economic rows match
between baseline and current, including cash, revenue, net profit, transport,
market inputs, labour, maintenance, power and building count (printed to pennies).

| Resolved turn | Glass Merchant net | Metal Magnate net |
|---|---:|---:|
| 1 | £43.00 | £56.21 |
| 2 | £50.73 | £58.62 |
| 3 | £50.43 | £58.82 |
| 4 | £50.13 | £51.92 |
| 5 | £49.82 | £47.01 |
| 6 | £49.52 | £44.53 |
| 7 | £49.22 | £44.52 |
| 8 | £48.91 | £44.34 |
| 9 | £66.07 | £44.16 |
| 10 | £65.65 | £43.98 |

Glass Merchant: cash £200 → £723.48, mean net £52.35 per turn; existing loan
balance ends at £556.11. Metal Magnate: cash £300 → £794.11, mean net £49.41
per turn, no loan. Both remain profitable on every measured turn. Opening
inventory and automatic progression mean this ten-turn average is not a pure
steady-state margin.

The changed recipes are r_050, r_232, r_083 and r_084. Glass Merchant produces
sand, glass and windows; Metal Magnate produces ore, coal, pig iron and power.
Neither runs a changed Aluminium recipe. The port-rate exception is confined
to tutorial-origin games, and even standard games pay the early rate in turns
1–10. The tutorial stock clearing and step timing do not run in these starts.

Raw logs: /tmp/demo-economics-glass-merchant.log,
/tmp/demo-economics-metal-magnate.log and corresponding
/tmp/demo-economics-baseline-<start_name>.log. Controlled chain details:
/tmp/tutorial-glass-audit-current.json and /tmp/tutorial-glass-audit-baseline.json.
