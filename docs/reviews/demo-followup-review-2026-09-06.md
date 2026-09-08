# Demo follow-up review — 6 September 2026

Advisor loyalty displays are hidden until `unlock demo`, including decision stakes,
council meters, portrait tooltips, agendas and missions. Decision loyalty arrows are
removed. Loyalty simulation is unchanged. The council lamp is always hidden; the
rankings lamp is amber when the next rival's latest revenue trend predicts an overtake.

The remaining Vandel overlap was a generated port wing, not a separate NPC business.
The port now claims reserved authored footprint `s:vandel:130` and generates no annexes.
The complete starting layout and Vandel's fabric/roads were rebaked. Geometry checks
confirm seven distinct claimed footprints and no port subcomponents; screenshots were
checked at two zoom levels.

Cash diagnostics now distinguish loan payments, operational credit, carbon tax, green
subsidy, tab repayments, reported net and actual cash change. Observed cash changes
reconciled with the components within display rounding. CostSolver receives each
consumer's share of settled grid imports, including carbon charges; owned power uses
the export revenue forgone. Disconnected networks and grid-priority generation retain
their settlement rules. Repeated input purchasing and selling is unchanged.

The tutorial audit found and fixed obsolete sourcing-dialog waits in both factory
branches, research search that could not find the aluminium-producing recipe, and
deferred hover callbacks referencing freed controls. Automatic public roads now skip
tutorial matches to preserve the scripted transport lessons. Advisor inspection copy
matches the current panel.

Validation:

- Parse sweep: 551 scripts, zero failures; 40 existing exclusions.
- Unit suite: 3,701 passed, zero failed.
- 100-turn regression: 723 passed, zero failed.
- Map and construction UI audit: 2,346 checks, zero failures.
- Tutorial UI regression: 44 checks, zero failures, with screenshot review.

The tutorial harness exercises construction branches, research search, advisor hiring,
decision displays and completion using staged match fixtures. It is not a full manual
playthrough. Existing renderer/resource cleanup warnings remain on test shutdown.
