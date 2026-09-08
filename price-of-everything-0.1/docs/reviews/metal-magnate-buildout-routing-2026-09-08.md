# Metal Magnate buildout and routing comparison — 2026-09-08

## Scope and limits

The supplied 100-turn log records production, per-building costs and cash summaries, but not a complete action history or snapshots. The available named save (`Test 1`, September 6, turn 85) is a different run. An exact replay of the player's decisions is therefore not established.

Two measurements are kept separate below: profits actually recorded in the log, and a controlled reconstruction to isolate commit c823f4e2 against b2b36117. Do not add the controlled difference to the logged profit and call that an exact forecast.

## Observed company profit in the supplied log

`reported_net` includes taxes, dividends and repayments. These windows avoid obvious purchases/startup spikes, but short windows and changes in policies or bonuses prevent attributing every difference solely to the latest building.

| Stage | Logged turns | Average net £/turn |
|---|---:|---:|
| Starting company | 2–3 | 58.72 |
| Steel | 10–12 | 83.21 |
| Copper | 19–22 | 126.06 |
| Wiring | 26–29 | 145.68 |
| Construction equipment (short window) | 33–34 | 152.12 |
| Motors; coal mine exhausted | 43–49 | 212.14 |
| Automated motors and rail | 61–65 | -131.09 |
| Rare earths/electric steel, before further changes | 72–73 | 294.59 |
| Later expanded company | 82–87 | 397.41 |
| Wind turbines, first settled-looking window | 94–98 | 331.32 |
| Final two turns (another increase) | 99–100 | 343.06 |

The final addition did **not** show a higher company profit: £397.41 at turns 82–87 versus £331.32 at 94–98 and £343.07 at 99–100. The last two turns differ from the earlier window, so the log does not establish one final steady-state value. This is a real observation, not proof that the turbine recipe alone caused the entire reduction.

## Controlled routing comparison

Each stage starts independently with the shipped Metal Magnate configuration, installs the observed production roster, warms up for 10 turns, and averages the following 10 real production/transport/accounting turns. Both versions use identical setups and sampling ages. These are averages over operating windows, not mathematical equilibria: prices and policy continue changing.

| Reconstructed stage | Before £/turn | After £/turn | Routing gain £/turn |
|---|---:|---:|---:|
| Starting company | 44.14 | 44.14 | +0.00 |
| Steel | 69.12 | 69.12 | +0.00 |
| Copper | 85.07 | 85.07 | +0.00 |
| Wiring | 98.60 | 98.60 | +0.00 |
| Construction equipment | 92.51 | 92.51 | +0.00 |
| Motors; coal mine exhausted | 117.24 | 117.24 | +0.00 |
| Automated motors | 114.07 | 114.07 | +0.00 |
| Rail connection | 112.98 | 115.39 | +2.41 |
| Rare earths and electric steel; pipes | 167.47 | 170.96 | +3.49 |
| Wind turbines | 141.66 | 146.10 | +4.44 |

The display/snapshot changes are economically neutral. The positive difference comes from choosing installed rail instead of bare-ground transport on equal-time routes. Gross transport savings at the rail, rare-earth/electric-steel and turbine stages are £3.77, £5.45 and £6.94 per turn respectively; 20% tax followed by 20% dividends leaves 64%, giving £2.41, £3.49 and £4.44.

### Reconstruction assumptions

- No advisors, discretionary research bonuses, loans or construction debt. Shipped start labour policy and start output bonuses are retained. Large starting cash prevents liquidity failures; construction outlays are excluded because this measures operation after completion.
- Player buildings are level 1. Copper uses Copper Blistering; automated motors use Hairpin Stator Motors (consistent with late-log input leaves, but recipe ID is not explicitly recorded).
- Most factories are at Docks (5,10), as logged. Automated motors, rare-earth electrolysis, electric steel and wind turbine assembly are at Old Quarter (4,10). The coal mine is removed from the motors stage onward.
- Rail at both tiles begins with the rail stage. Pipes and reinforced pipes follow the logged later additions. Required cables are installed. Other links use the map's default infrastructure; discretionary upgrades and the complete public-road timeline are not replayed.
- Local intermediates feed tile inventory; surplus and finished goods sell to market. Missing inputs are bought automatically. Exact manual cross-tile output/stockpile instructions were not logged and are not reconstructed.
- Each independent stage restarts inventory and market history. Later samples therefore extend past the player's milestone and, for the last stage, past turn 100. Their absolute profits must not be compared directly with logged values or treated as a fresh-start balance verdict.

## Reproduction and validation

Tool: `tools/buildout_routing_audit.gd` and `.tscn`.

Run from the Godot project root:

```
Godot --headless --path . res://tools/buildout_routing_audit.tscn -- /tmp/buildout-current.json
```

For the before run, use an isolated copy with scripts from b2b36117 and the same audit tool/data. Runtime files are isolated under the output filename; autosaving and metrics are disabled. No player save is changed.

Results: `/tmp/buildout-before.json`, `/tmp/buildout-current.json`. Every staged building ran on all ten sampled turns in every stage. The tool checks that invariant and absence of advisors. No gameplay or balance code was modified for this analysis.
