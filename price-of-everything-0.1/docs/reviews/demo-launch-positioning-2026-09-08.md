# Demo launch positioning review — 8 September 2026

## Recommendation

Lead with **a turn-based industrial tycoon about choosing what to buy, what to make, and when to expand**. Its tension is that your production changes market prices while freight, power, finance and carbon policy change the economics of your next investment.

Suggested short promise: **Build the supply chain. Stay ahead of the market.**

The original 3 September brief correctly identified the supply-chain/market audience and the value of explaining a mechanic. Its claims that every building loses money alone, integration is automatically the winning strategy, and this occupies a uniquely uncontested market should not be carried into launch copy. The first two conflict with current evidence; the uniqueness claim was not established by this review.

## Evidence and scope

Reviewed the current working-tree files, live runtime CSVs, new-game restrictions, tutorial content, policy and price-impact code, icon manifest and matching source-file hashes, today's tutorial/economic reviews, and the revision-7 trailer manifest and existing verified footage. Retrieved the public itch page on 8 September. No fresh packaged-build playtest or store upload was performed. Existing test results and controlled economic measurements below are attributed to their reports rather than represented as newly run here.

Key sources:

- [New-game demo restrictions](../../scripts/new_game_panel.gd): `DEMO_LOCK`, `DEMO_START_IDS`, `DEMO_SPEED_ID` and the length options.
- [Demo victory rules](../../scripts/victory_state.gd): `DEMO_TRACK_NAMES` and `DEMO_WIN_THRESHOLD`.
- [Market response](../../scripts/market_state.gd) and [economic constants](../../scripts/economy_config.gd): net market volume, impact ladder, recovery and cost parameters.
- [Policy timeline](../../scripts/policy_state.gd): `TIMELINES` and `DEMO_EFFECTIVE`.
- [Tutorial content](../../scripts/tutorial/tutorial_steps.gd) and [today's tutorial review](tutorial-demo-2026-09-08.md).
- [Aluminium economics, including successive approved fixes](tutorial-aluminium-economics-2026-09-08.md).
- [Metal Magnate buildout comparison](metal-magnate-buildout-routing-2026-09-08.md).
- [Icon provenance](../../assets/icons/goods/alternate_icons/approved_manifest.json) and [runtime icon lookup](../../scripts/good_icons.gd).
- [Trailer timing and capture evidence](../../../outputs/launch-clips-2026-09-07/manifest.json).
- [Public itch page](https://carbonandcapital.itch.io/carbon-and-capital).

## What the current game supports

**The investment decision is the strongest promise.** Market inputs let a business operate before it owns its entire chain. Integration can improve margins, but capital, freight, infrastructure, storage, salary and financing costs determine whether it is worthwhile. The current tutorial teaches precisely these decisions: buy versus construct a factory, connect power, route outputs, read the books, make glass or aluminium, and select research/advisors.

The aluminium review supplies concrete evidence for a meaningful upgrade after the fixes. Its latest controlled turns-36–45 comparison reports £30.12 retained cash per turn for Hall Heroult and £36.48 for Carbochlorination, with tutorial-origin introductory port rates. That includes taxes/dividends but excludes loans/advisors. Earlier figures in the same document are superseded by the later output and port-rate changes. These are controlled results, not a universal player return or an appropriate headline percentage.

The Metal Magnate review gives equally useful counter-evidence to “bigger always pays.” A recorded later expansion averaged £397.41 per turn before the subsequent turbine-stage window averaged £331.32. Its controlled reconstruction also reports lower operation-window profit for the turbine roster than the preceding roster. Multiple things changed; neither establishes that the turbine recipe alone caused the decline. Together they support **choose your expansion carefully**, not guaranteed profit from more buildings.

**The market reacts to volume.** The current code uses net buying/selling, a threshold ladder and a rolling recovery mechanism. The CSV's old decay field and trailer filename are not the economic explanation. Safe copy: “Sell heavily and you can push down your own selling price. Buy heavily and your inputs can become more expensive.” Avoid “prices fall every turn,” “one percent per turn,” or “you must diversify.” Different scales and thresholds produce different responses; reducing output or lowering costs are also strategic responses.

**Carbon policy gives the game its identity.** Keep it in the opening description's second sentence and one prominent feature. The demo has an announcement at turn 58, levy ramp at 65–75, and green subsidy from 80. A scheduled, announced cost change rewards preparation. “A carbon tax changes which supply chains pay” is more precise than selling a deep political simulation or claiming the tax is already charged at turn 58.

**Freight is a meaningful supporting feature.** Ports, arrival time and infrastructure affect costs and when income arrives. The tutorial now opens with motor shipments and road/rail comparisons. This differentiator is under-explained in the trailer, so it deserves one clear page bullet or its own later short post. The growth montage's roads alone do not explain its economics.

## How the trailer positions the demo

Revision 7 is 54.4 seconds; its picture is identical to approved revision 5. Later revisions changed sound levels only.

| Beat | Promise the viewer gets | Copy needed around it |
|---|---|---|
| Pick your specialty / focused goods | Plenty of industries to explore | Explain that the demo has two starting businesses with many expansion directions; it is not a free choice of every starting industry. |
| Test your mettle / actual BDP ingot | Industrial identity and a playful tone | Keep the pun; put the genre and economic decision in the post title/first sentence. |
| Steel sales 0→84 | A new line of business begins earning income | This is sales revenue. Do not call £117.84→£316.75 a profit increase. |
| Buy / Make | The central player decision | Explicitly say “buy inputs or produce them yourself.” The recipe diagram introduces the question without proving one option always wins. |
| Construction, chain, L1–L3 | Visible company development | Explain upgrades as investment choices, not assured returns. |
| Don't stand still → price movement | Success creates pressure on margins | Connect the price movement to selling volume; it is not arbitrary passive decay. |
| World changes → carbon tax/subsidy | Another reason to rethink the chain | Name the costs and opportunities rather than implying complex reactive politics. |
| Dense empire growth | The satisfying long-term result | This is staged and accelerated. Do not promise this exact empire within a normal 100-turn run. |

The trailer now has a coherent arc: opportunity, income, expansion, pressure, adaptation, scale. It is suitable to launch with. Its central limitation is explanatory: it does not prominently state “turn-based,” and it shows the existence of decisions more clearly than their comparative costs. The surrounding copy can supply that context without another trailer revision.

## Public page claim audit

The retrieved page still says “Demo coming this month (August)” and asks visitors to follow. It exposes no public download button/list or trailer embed in the served page. That is a launch conversion blocker until the actual build and trailer are published; the statement concerns the public page, not private uploaded drafts.

| Current page claim | Issue | Replacement direction |
|---|---|---|
| “Expand … over 300 turns” | Standard demo is pinned to 100 turns. | “A free 100-turn demo,” with campaign plans clearly separated. |
| Campaign's Greenest/Richest/Efficient/Widest/Autarkic tracks | Demo uses Crown/Tiers/Distance/Green/Estate and a combined 2,500-point target. | “Compete across five scoring tracks.” Explain exact demo rules lower down if needed. |
| “Every factory … can turn a profit … owning the one that feeds it roughly doubles that” | Universal profitability and doubling are not established by current evidence. | “Make your own inputs when the savings justify the investment.” |
| “There's no wrong first move” | Contradicts financing, routing and operational trade-offs. | “Start with an existing business and choose where it grows.” |
| “60+ goods, all possible to produce on turn 1” | Catalogue size is not starting affordability or immediate production; some goods/routes require research. | “Explore dozens of goods and alternative production routes.” |
| Resource icons described as entirely AI-generated | Numerous Blender replacements are now installed. | A scoped, current disclosure with verified replacement count if desired. |

The live catalogue contains 77 goods entries, 209 recipe rows and 37 building entries. These are raw catalogue counts, not promises that every item is buildable immediately or available in every demo situation. They belong in supporting information, not the lead.

The project still has `config/name="Price of Everything 0.1"`. Align the exported application's visible name with Carbon and Capital before publishing. Export presets exist for macOS, Windows and Linux; that alone does not verify actual downloadable packages for those platforms.

## Suggested page and launch copy

Short description:

> A turn-based industrial tycoon. Choose what to buy, what to make, and when to expand as your production moves markets and carbon policy changes costs.

Opening paragraph:

> Build the supply chain. Stay ahead of the market.
>
> Take over a metals or glass business and decide what to produce next. Buy inputs to get started, make them yourself when the investment pays, and connect your factories to the market. Expanding production can push down your own selling prices. A coming carbon tax and green-energy subsidies give you new reasons to rethink the chain.
>
> The free demo includes a guided tutorial and two starting businesses for 100-turn games.

Use “Download the free demo” as the launch CTA only once a working public build is available. Give platform-specific download details and a clear description of demo scope nearby.

Feature priority:

1. Buy inputs or build the suppliers yourself.
2. Expand production while watching its effect on prices.
3. Plan freight, power and construction around the full cost of operating.
4. Adapt to the announced carbon levy and green-power subsidy.
5. Watch upgraded buildings and roads transform your company on a hand-authored map.

Research, advisors, loans and the exact scoring formula are supporting depth. Do not put all of them in the first screen of copy.

Launch-post angle:

> I made a turn-based industrial tycoon where expanding production can push down your own selling prices.

Suggested body, after the download is live:

> In Carbon and Capital, you decide which inputs to buy and which to make yourself. Expanding a chain can improve your costs, but it can also flood the market for the goods you sell. Freight, power and a coming carbon tax keep changing what is worth building next.
>
> The free demo has a guided tutorial and two 100-turn starting scenarios. The trailer follows iron into steel and motors, then shows the market pushing back.
>
> [Download the demo](https://carbonandcapital.itch.io/carbon-and-capital).

A second feature-post angle is “When does making your own steel beat buying it?” Explain one concrete decision using the Buy/Make or chain footage. A freight follow-up can show the same shipment taking fewer turns after infrastructure. These are content angles, not a claim that any particular community currently permits the post; check venue rules before publishing there.

## Art disclosure

Forty distinct goods are listed in the approved alternate manifest. Thirty-three have explicitly Blender-labelled source records, and the corresponding installed file hashes matched during this review. Across 77 catalogue entries, that is about 43% with confirmed Blender provenance; the remaining seven approved alternates have other source labels and are not classified here. Runtime lookup prefers alternate icons.

Therefore “about 20%” materially understates the replacements verified in the current tree. A robust disclosure avoids a rapidly stale percentage:

> Some goods icons are AI-generated placeholders. I’m replacing them with icons created in Blender; more than 30 goods already use Blender replacements. AI-assisted code is also used in the project.

“Created in Blender” describes the verified production method. It does not imply no AI-assisted scripting was involved or that the whole game's artwork is now non-AI. If the current upload contains older assets, disclose the uploaded build rather than the newer source tree.

## Launch decision

The positioning and trailer are ready to support a demo launch. The public page and deliverable need to match that promise: current name, public working download, trailer, accurate 100-turn scope, two starts, and updated art disclosure. The tutorial is now a substantial guided experience, with reported tests covering branches and real shipment arrival; avoid calling it a five-minute introduction without measuring it.

Use the earlier mechanic-post analytics as directional evidence, not a reliable forecast of downloads. Launch learning should follow the funnel: visits, downloads, tutorial starts/completion, first independent factory, and whether players try another company. Check which of these events are actually available in current consented telemetry before promising a dashboard. The most useful feedback question is where a player stopped understanding the next investment or stopped finding it worthwhile.
