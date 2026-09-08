# Faster market impact

The supplied turn-98–100 logs show sales of 517 iron ingots and 63 steel per turn. Iron-ingot revenue falls from £716.88 to £715.37 across those two intervals, or about £0.00146 per unit per turn. This is slow price pressure, rather than a frozen price.

At turn 100, threshold inflation is 2x. Iron ingots have base output 70: 517 is above 420 (>3x inflated) but below 700 (>5x inflated), giving the previous 0.1 percentage-point rate. Steel has base output 44: 63 is below its first inflated threshold of 88, so it does not accrue a glut. The engine nets market purchases against sales and gates accrual on its rolling volume window.

All ten rates are doubled, from 0.05–1.0 to 0.1–2.0 percentage points per turn. At the same iron volume this becomes 0.2 points/turn. Below-threshold volume still has no effect. Threshold inflation, recovery, caps and buying/selling logic are unchanged. Existing accumulated impact is preserved; the new speed applies to future turns.
