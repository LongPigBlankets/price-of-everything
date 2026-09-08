# Advisor bars and market history

Advisor skills use the victory screen’s brushed-metal bars, including the light gradient, grain and bevel. Recruitment, money breakdowns and tile meters share the same component. Fractional values remain continuous and zero has no fill.

Expanded market rows allocate one quarter of their width to actions and three quarters to the price chart. The chart ends at the current turn and labels only its final price and turn. A lone observation is a 12px-radius dot. A faint cream gradient sits below the line. A fixed 3px white historical line connects the quantity-weighted player production cost at each recorded turn. Hover never changes its geometry; an off-white readout shows the turn, price and your cost basis on separate lines. Missing costs are not drawn, and the reference is hidden entirely when the good is absent from the player’s produced-goods cost results. Axes and the hover guide use muted blue, distinct from the white cost reference. Wheel input passes through to the market scroll container.

MarketState records prices at the end of each resolved turn, plus the initial observation, together with the CostSolver average unit cost used by the market’s Cost/unit column. These are market spot prices, before buyer markup or advisor-specific sale bonuses. History is saved with save version 10. Older saves begin recording at their loaded turn; prior observations are not fabricated.

Validation covers fractional fills, observation isolation, save round trips, duplicate recording, older saves, hover mapping and the width split. Windowed screenshots verify advisor bars and expanded market rows.
