# Balance baselines

A frozen snapshot of the whole economy taken **before** each large balance pass, so any
change can be diffed against, argued with, or reverted to. One row per recipe, with
quantities, prices, energy, labour and maintenance side by side, plus the global rate
constants repeated on every row so the file stays readable when those constants move.

Regenerate a fresh snapshot with:

    python3 -B tools/snapshot_balancing.py data/balance_baselines/<YYYY-MM-DD>_<what>.csv

## Why these are kept

The 2026-07-28 pass moved 68 good prices, 173 input quantities and 59 output quantities
in one go. Several individual decisions inside it were later reversed on the evidence
(bio ethylene, SynRM motors, hydrogen power, bio-graphitisation), and each reversal
needed the ORIGINAL number, not the number two edits ago. Git history holds the diffs,
but a single flat file is what you actually want in front of you when deciding whether a
recipe's new quantity is defensible.

## Snapshots

| file | taken before |
|---|---|
| `2026-07-28_pre-rebalance.csv` | the full economy solve: ratio ladder, price solve, labour 0.40-1.00x, maintenance x2, carbon-tax propagation |
