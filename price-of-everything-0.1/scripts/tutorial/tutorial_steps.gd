extends RefCounted
## Tutorial content — the authoring unit. `steps()` returns the ordered tutorial as
## plain Dictionaries (copy/targets/predicates only, no engine logic), so a designer
## can read the whole tutorial top-to-bottom and reorder beats by moving entries.
## Chosen over a .tres Resource because Callable/predicate fields serialize poorly and
## Dictionaries diff cleanly in git. Referenced via preload (no class_name).
##
## The confined tutorial board: a real west-coast pocket of the fixed map (no bespoke
## map — the world is one fixed tile_properties.csv). Centre tile_6_7 + its ring; the
## NPC window factory (b_007/r_056) is seeded on the centre by data/starts/tutorial.json.
##
## ARC: First Factory (buy → understand → diagnose) → Power (one cable powers it from the
## grid — dead simple) → Integration (it's profitable but thin, and prices drift down; to
## expand you bring costs IN-HOUSE). Integration branches on a player CHOICE: bring POWER
## in-house (own plant) or INPUTS in-house (own glass). Labour + maintenance can't be
## integrated away — only modifiers (research/advisors/policies) trim those.

const BOARD_TILES: Array = [
	"tile_6_7", "tile_6_6", "tile_7_7", "tile_7_8", "tile_6_8", "tile_5_8", "tile_5_7", "tile_5_9",
]
const PORT_TILE := "tile_5_10"    # Stoneshore Docks — inputs ship in from here (view-only). Pre-seeded with a
                                  # reinf_pipes terminal (data/starts/tutorial.json) so a single player pipe on
                                  # the factory tile connects the glass furnace's sodium_hydroxide feed to it.
# Camera framing (not the interaction whitelist): includes the port so the player can
# zoom out and see the port -> factory shipment route in the Logistics view.
const CAMERA_TILES: Array = [
	"tile_6_7", "tile_6_6", "tile_7_7", "tile_7_8", "tile_6_8", "tile_5_8", "tile_5_7", "tile_5_9", "tile_5_10",
]
# The factory tile: tile_5_9, hex-adjacent (north) of the port. The NPC window factory sits here and the
# player builds their glass furnace / aluminium furnace ON THE SAME TILE — co-location, so the in-house
# glass/aluminium is consumed same-tile (no shipping, no oscillating market top-up, flat input bill). Its
# cables are stripped in data/tile_properties.csv so the "lay a cable for power" lesson still lands here.
const WINDOW_TILE := "tile_5_9"   # NPC Industrial Goods Factory (windows) — bought + co-located producers
const GLASS_TILE := WINDOW_TILE   # glass furnace built on the factory tile (needs a reinf pipe for NaOH)
const ALU_TILE := WINDOW_TILE     # aluminium furnace built on the factory tile (all-solid inputs, no pipe)
const INPUT_TILE := "tile_5_7"    # rural + sand(3000) deposit — the sand on the board (Encyclopedia reference)
const POWER_TILE := "tile_6_6"    # rural, adjacent — build your own power plant (deeper integration)
const WATER_TILE := "tile_7_8"    # deposit:water + river (deeper integration)
const STUB_TILE := "tile_6_8"     # hill, unsurveyed coal deposit (deeper integration)

# Building / recipe ids (verified against the catalog):
#   b_007/r_056 window factory (28 glass + 10 aluminium -> 15 windows) · b_002 furnace runs r_053 glassmaking
#   (sand+NaOH+limestone -> 28 glass), r_054 High Strength Glassmaking (silica+alumina+sulphur -> 48 glass,
#   research-gated, no NaOH), AND r_050 aluminium Hall-Heroult (alumina+graphite+chem_salts -> 20 aluminium)
#   b_018 reinf_pipes (£50, 1 turn — the only mode that carries NaOH) · b_003/r_004 coal power plant (deferred)

## Balance-sensitive numbers in the copy (kit costs, market prices, recipe
## quantities, land targets) are COMPUTED from the live Catalog/EconomyConfig at
## steps() time, so a rebalance never leaves the tutorial quoting stale figures.
## steps() runs at tutorial start (and in tests) — the autoloads are loaded by then.

## A step Dictionary:
##   id/chapter/title/body — identity + coach card copy
##   setup     : ordered driver actions run on entry
##   spotlight : {kind: node_path|node_name|tile|none, ref}
##   lock_panel: true keeps the spotlit panel open + swallows Esc (no stuck state)
##   choices   : [{label, goto}] — renders branch buttons; selecting one jumps to `goto`
##   goto      : on advance, jump to this step id instead of the next (branch reconverge)
##   done      : {wake:[signals], decide:<predicate>} — empty decide = info step (Next)
##   advance   : "auto" (on decide) or "next" (info card)
static func steps() -> Array:
	return [
		{
			"id": "welcome",
			"chapter": "Welcome",
			"title": "Welcome to Carbon and Capital",
			"mode": "welcome",
			"paragraphs": [
				"This is a game where you build out your industrial empire over 25 years across a country known as Taralia.",
				"You will buy, build and branch out one good at a time — from coal and steel to computers and electric cars. You may begin in any industry: a power plant, a wind farm, a coal mine, a glass factory, a chemical plant or car assembly. It's your choice.",
				"As you expand, remember the chains are interconnected, and there's more than one way to win — but all of them involve expanding out of whatever niche you start with to dominate your industry. Or, if you're truly bold... all industries. Good luck, and let the carbon flow.",
				"This tutorial covers the basics: buying a building, making it run, building your second, and integrating them to sell a vertically integrated good to the global market. These skills will help you get started no matter where you choose to begin in your next game.",
			],
			"cta": "Begin",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "ui_primer",
			"chapter": "Welcome",
			"title": "Your control panel",
			"mode": "annotate",
			"body": "A quick tour of the screen. The bar along the bottom is your toolkit — each tool has a keyboard shortcut (the letter in brackets). The top bar is your dashboard: money, victory tracks, the briefing with updates and decisions, your advisors and the menu. You end each turn from the bottom-right. Have a look, then press Next.",
			"targets": [
				{ "ref": "ConstructButton", "label": "Build (C)", "side": "above" },
				{ "ref": "ResourcesButton", "label": "Goods (G)", "side": "above" },
				{ "ref": "BuildingsButton", "label": "Buildings (L)", "side": "above" },
				{ "ref": "MapmodesButton", "label": "Overlays (O)", "side": "above" },
				{ "ref": "MarketButton", "label": "Markets (M)", "side": "above" },
				{ "ref": "PoliticsButton", "label": "Narrative & Politics (N)", "side": "above", "lift": 1 },
				{ "ref": "TechButton", "label": "Research (R)", "side": "above" },
				{ "ref": "PeopleButton", "label": "People (P)", "side": "above" },
				{ "ref": "MoneyWidget", "label": "Budgets, charts & loans", "side": "below" },
				{ "ref": "VictoryModule", "label": "Victory tracks — five ways to win", "side": "below" },
				{ "ref": "BriefingModule", "label": "Briefing — updates & decisions", "side": "below" },
				{ "ref": "CouncilModule", "label": "Advisors", "side": "below" },
				{ "ref": "EncyclopediaButton", "label": "Encyclopedia (X)", "side": "below" },
				{ "ref": "MenuModule", "label": "Main menu", "side": "below" },
				{ "ref": "EndTurnButton", "label": "End turn", "side": "above" },
			],
			"hints": [
				"Press X to open the Encyclopedia search bar",
				"Press Tab to view your empire at a glance",
			],
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "goto_tile",
			"chapter": "First Factory",
			"title": "Find the factory inland",
			"body": "Let's begin with your first building. Pan (drag) and zoom (scroll) inland a little to find it — look for the white building; white means an NPC owns it, and this one is up for sale. Click it (the Industrial Goods Factory, the one Vandel Glassworks is selling) to open its tile.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": [],
				"decide": { "kind": "tile_panel_open", "tile": WINDOW_TILE },
			},
			"advance": "auto",
		},
		{
			"id": "build_open",
			"chapter": "First Factory",
			"title": "What would it cost to build one?",
			"body": "Before you buy, look at the alternative — building a window factory here from scratch. Open the tile's Build menu.",
			"setup": [ { "action": "focus_tile", "tile": WINDOW_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "BLBuildButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "ConstructPanelV2" },
			},
			"advance": "auto",
		},
		{
			"id": "build_pick_recipe",
			"chapter": "First Factory",
			"title": "Pick what it will build",
			"body": "This is the Build menu. Every building you construct also runs a recipe — you choose it now, and can always change it later. Here's the Industrial Goods Factory: glass + aluminium in, windows out. Click its recipe to price up a build.",
			"setup": [ { "action": "expand_construct_building", "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "RecipeRow_r_056" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "BuildConfirmButton" },
			},
			"advance": "auto",
		},
		{
			"id": "build_cost",
			"chapter": "First Factory",
			"title": "Building costs more than buying — for now",
			"body": "Here's the build bill. Constructing this factory from scratch needs roughly £%d of materials — see the construction cost estimate. Buying the one Vandel already built is cheaper today, so we'll do that instead. (Later, once you make these materials yourself, building your own can win.) Press Next — don't confirm the build." % _build_kit_cost("b_007"),
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "BuildCostValue" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "build_close_buy",
			"chapter": "First Factory",
			"title": "Buy it instead",
			"body": "Close the build panel — we won't build one from scratch. Now open this tile's Buildings for sale yourself, where Vandel's factory is up for grabs.",
			"setup": [
				{ "action": "close_sourcing" },
				{ "action": "close_construct" },
				{ "action": "focus_tile", "tile": WINDOW_TILE },
			],
			"spotlight": { "kind": "node_name", "ref": "BLBuyBuildingsButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "MarketPanel" },
			},
			"advance": "auto",
		},
		{
			"id": "buy_factory",
			"chapter": "First Factory",
			"title": "Buy the window factory",
			"body": "Vandel Glassworks is selling the Industrial Goods Factory on the coast. Open its buildings market and buy it — this factory is where your first supply chain begins.",
			"setup": [
				{ "action": "close_construct" },
				{ "action": "focus_tile", "tile": WINDOW_TILE },
				{ "action": "open_buildings_market", "tile": WINDOW_TILE },
			],
			"spotlight": { "kind": "node_path", "ref": "UILayer/HUD/HUDContent/MarketPanel" },
			"lock_panel": true,
			"done": {
				"wake": ["building_owner_changed"],
				"decide": { "kind": "building_owned_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			},
			"advance": "auto",
		},
		{
			"id": "recipes_intro",
			"chapter": "First Factory",
			"title": "Every building runs a recipe",
			"body": "Here's your factory. It runs one recipe: glass + aluminium in, windows out. That's the whole game in miniature — buildings turn inputs into outputs. But it can't make a thing yet.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "diagnose_factory",
			"chapter": "First Factory",
			"title": "Why isn't it running?",
			"body": "Read the Diagnostics. The red Power row is the blocker: the factory has no electricity, so it's switched off. That's the first fault to clear — and it's an easy one.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "DiagnosticsCard" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "lay_cable_factory",
			"chapter": "Power",
			"title": "Lay a cable to power it",
			"body": "Power reaches a building over a physical cable network. In the tile panel's Infrastructure row, click the Cables “+” to lay a cable on this tile.",
			"setup": [
				{ "action": "focus_tile", "tile": WINDOW_TILE },
			],
			"spotlight": { "kind": "node_name", "ref": "InfraDial_cables" },
			"lock_panel": true,
			"done": {
				"wake": ["construction_started", "infrastructure_attempted"],
				"decide": { "kind": "node_visible", "ref": "SourcingBuyButton" },
			},
			"advance": "auto",
		},
		{
			"id": "lay_cable_source",
			"chapter": "Power",
			"title": "Buy the cable materials",
			"body": "Laying a cable needs a few construction materials you don't have on this tile yet. Choose Buy from market to order them and start the cable — that's all it takes to switch the tile on.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "SourcingBuyButton" },
			"done": {
				"wake": ["construction_started", "infrastructure_attempted", "materials_ordered"],
				"decide": { "kind": "tile_cabled_or_ordered", "tile": WINDOW_TILE },
			},
			"advance": "auto",
		},
		{
			"id": "run_until_running",
			"chapter": "Power",
			"title": "End turns until it runs",
			"body": "The cable takes a turn to build, and your glass and aluminium have to ship in from the port — a couple of turns away. Keep pressing End Turn until the factory reads Running.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "building_running_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			},
			"advance": "auto",
		},
		{
			"id": "open_mapmodes",
			"chapter": "Power",
			"title": "Where do the inputs come from?",
			"body": "Those inputs don't teleport — they ship in from your port. Open the Map Modes menu on the bottom bar to see how.",
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "MapmodesButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "MapModesPanel" },
			},
			"advance": "auto",
		},
		{
			"id": "select_logistics",
			"chapter": "Power",
			"title": "Switch to Logistics",
			"body": "Pick Logistics. The map redraws to show every shipment in transit — routes, cargo and turns-to-arrival.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "MapModeRow_logistics" },
			"done": {
				"wake": [],
				"decide": { "kind": "in_mapmode", "mode": "logistics" },
			},
			"advance": "auto",
		},
		{
			"id": "view_shipment",
			"chapter": "Power",
			"title": "Follow the shipment",
			"body": "The view has pulled back to Stoneshore Docks — the port just south of your factory, where your inputs come ashore. The coloured line running inland is your glass and aluminium in transit; the pentagon on it shows turns to arrival. Zoom in (scroll) and hover it to see what's aboard. (No shipment? End a turn and it reappears.)",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"camera": { "grow": 280.0 },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "transport_ports",
			"chapter": "Transport",
			"title": "Everything moves through a port",
			"body": "Here's the rule behind that shipment: everything you BUY from the market comes ashore at your nearest port, and everything you SELL leaves through it. Press Tab to see your empire at a glance — the thick gold line runs from your factory to Stoneshore Docks, the hexagon below it. Every leg of that journey costs money per unit moved. Press Tab again to come back, then press Next.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"card_side": "top_right",
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "transport_redirect_open",
			"chapter": "Transport",
			"title": "You choose where output goes",
			"body": "Selling to the market is only the default. A building can ship its output anywhere you own a stockpile — that's how you'll feed factories from your own mines later. Open your factory's Output destination.",
			"setup": [
				{ "action": "close_empire_view" },
				{ "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			],
			"spotlight": { "kind": "node_name", "ref": "OutputDestCard" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "ActionSheet" },
			},
			"advance": "auto",
		},
		{
			"id": "transport_redirect_pick",
			"chapter": "Transport",
			"title": "Ship the windows overland",
			"body": "Choose 'Ship to another tile', then click a nearby tile on the map — say the sand flats just north-west of your factory. From next turn your windows truck overland to that tile's stockpile instead of sailing out of the docks.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": [],
				"decide": { "kind": "output_routed_offtile", "tile": WINDOW_TILE, "building_id": "b_007" },
			},
			"advance": "auto",
		},
		{
			"id": "transport_pentagon_revert",
			"chapter": "Transport",
			"title": "Watch it move — then put it back",
			"body": "End Turn and watch the map: a pentagon sets off from your factory, hauling windows overland — and every unit aboard pays for the trip. Distance and transport mode set the price; market trades pay the same way on the port run, priced into every sale. Seen it move? Those windows just pile up over there, so put it back: open the factory's Output destination again and choose Global market.",
			"setup": [ { "action": "open_logistics" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": [],
				"decide": { "kind": "output_routed_market", "tile": WINDOW_TILE, "building_id": "b_007" },
			},
			"advance": "auto",
		},
		{
			"id": "margin_motivation",
			"chapter": "Integration",
			"title": "A wafer-thin margin",
			"body": "Open Cost to Produce. Making windows from bought-in glass and aluminium costs you close to the £%s the market pays per window — a wafer-thin margin, about as good as if you'd simply bought the finished windows instead. That won't outrun the loan sharks. Integration — making your own inputs so your cost per window drops well BELOW £%s — is how you turn that sliver into a real profit and expand." % [_good_price_text("windows"), _good_price_text("windows")],
			"setup": [
				{ "action": "clear_mapmode" },
				{ "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "cost_lesson",
			"chapter": "Integration",
			"title": "Where the cost goes",
			"body": "Your cost per unit has a few parts: materials, power, labour, maintenance, transport. Two of them you can INTEGRATE — make your own materials and your own power instead of buying them. Labour and maintenance are fixed per building; only modifiers (research, advisors, labour policies) trim those — you can't build them away.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "analyse_supply",
			"chapter": "Integration",
			"title": "Know your supply chain",
			"body": "Before you build, understand the chain. This factory needs GLASS and ALUMINIUM. To integrate, you'll make one of those yourself — but first, let's look up how they're made.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "explore_encyclopedia",
			"chapter": "Integration",
			"title": "Look it up in the Encyclopedia",
			"body": "This is the Encyclopedia — press X any time to open it. Search 'glass' (made in a Furnace from sand, and there's sand on your board) and 'aluminium' (smelted in a Chemical Plant from alumina). Have a look, then press Next.",
			"setup": [ { "action": "open_encyclopedia" } ],
			"spotlight": { "kind": "node_name", "ref": "SearchOverlay" },
			"no_dim": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "close_encyclopedia",
			"chapter": "Integration",
			"title": "Close the Encyclopedia",
			"body": "Press Esc to close any panel — like the Encyclopedia. That clears the map so you can build.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "SearchOverlay" },
			"no_dim": true,
			"done": {
				"wake": [],
				"decide": { "kind": "node_hidden", "ref": "SearchOverlay" },
			},
			"advance": "auto",
		},
		{
			"id": "buy_land",
			"chapter": "Integration",
			"title": "Buy the land to build on",
			"body": "One more thing before you build: every building needs land YOU own. Your factory came with its own plot, but a furnace or smelter needs room of its own. On the factory tile's land rail, click Buy Land and buy at least %d — land is cheap (£%d per %d units), and the bracket on the size chart shows what you own." % [
				_land_lesson_shortfall(), int(MatchState.LAND_PATCH_COST), MatchState.LAND_PATCH_SIZE],
			"setup": [
				{ "action": "close_building_detail" },
				{ "action": "focus_tile", "tile": WINDOW_TILE },
			],
			"spotlight": { "kind": "node_name", "ref": "BLBuyLandButton" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "tile_land_at_least", "tile": WINDOW_TILE, "amount": _land_lesson_target() },
			},
			"advance": "auto",
		},
		{
			"id": "choose_integration",
			"chapter": "Integration",
			"title": "Two ways integration pays",
			"body": "Pick one to make yourself. GLASS is your biggest input — %d units per window run — and cheaper to make than to buy, so integrating it flips you into profit. That's the play, and research can push it further. Or ALUMINIUM, the smaller input: a smelter makes more than you need and the surplus sells each turn — a taste of a new revenue line, though glass is where the real money is." % _recipe_input_qty("r_056", "glass"),
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"choices": [
				{ "label": "Cut costs: make glass", "goto": "build_glass_open" },
				{ "label": "New income: make aluminium", "goto": "build_alu_open" },
			],
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "build_glass_open",
			"chapter": "Integration · Margin",
			"title": "Build a glass furnace",
			"body": "Build the furnace right here, on your factory's own tile. Making glass on-site means it's consumed where it's made — no shipping, no wobbling market top-up, a flat input bill. One catch: glassmaking needs a hazardous liquid the docks pipe in — we'll sort that out. Open the build tile and click Build.",
			"setup": [
				{ "action": "close_building_detail" },
				{ "action": "focus_tile", "tile": GLASS_TILE },
			],
			"spotlight": { "kind": "node_name", "ref": "BLBuildButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "ConstructPanelV2" },
			},
			"advance": "auto",
		},
		{
			"id": "build_glass_recipe",
			"chapter": "Integration · Margin",
			"title": "Pick Industrial Glassmaking",
			"body": "A Furnace can make lots of things — click the highlighted Industrial Glassmaking recipe.",
			"setup": [ { "action": "expand_construct_building", "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "RecipeRow_r_053" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "BuildConfirmButton" },
			},
			"advance": "auto",
		},
		{
			"id": "build_glass_confirm",
			"chapter": "Integration · Margin",
			"title": "Confirm the build",
			"body": "The panel prices the furnace up on this tile. Press Confirm to start construction right here.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "BuildConfirmButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "SourcingBuyButton" },
			},
			"advance": "auto",
		},
		{
			"id": "build_glass_source",
			"chapter": "Integration · Margin",
			"title": "Buy the build materials",
			"body": "You don't have the furnace's build kit on this tile yet. Choose Buy from market and construct — later, you could produce these materials yourself too.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "SourcingBuyButton" },
			"done": {
				"wake": ["construction_started", "materials_ordered"],
				"decide": { "kind": "building_or_project_on_tile", "tile": GLASS_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_sell",
			"chapter": "Integration · Margin",
			"title": "Turn windows into cash",
			"body": "Your furnace takes a couple of turns to build, and until it feeds the factory your margin stays wafer-thin. Don't let finished windows pile up — switch on 'Sell all Surplus every turn' on the factory tile. Each turn it ships them to market for cash while you integrate.",
			"setup": [ { "action": "focus_tile_stock", "tile": WINDOW_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "SellSurplusToggle" },
			"lock_panel": true,
			"done": {
				"wake": ["sell_surplus_changed"],
				"decide": { "kind": "sell_surplus_on_tile", "tile": WINDOW_TILE },
			},
			"advance": "auto",
		},
		{
			"id": "glass_wait_built",
			"chapter": "Integration · Margin",
			"title": "End turns until the furnace is built",
			"body": "Keep pressing End Turn while the furnace goes up — a couple of turns. Once it's finished, we'll see why it still can't make a single sheet of glass.",
			"setup": [ { "action": "focus_tile", "tile": GLASS_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["construction_completed", "turn_processed", "turn_advanced"],
				"decide": { "kind": "building_owned_on_tile", "tile": GLASS_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_diagnose_pipe",
			"chapter": "Integration · Margin",
			"title": "Built — but starved",
			"body": "The furnace is up and wired for power, and its sand and limestone come in from the docks. But read Diagnostics: 'No input Reinforced Pipeline'. Glassmaking also needs sodium hydroxide — a hazardous liquid that can't travel by road or rail. It moves ONLY through a reinforced pipe, and nothing yet connects the furnace to the docks.",
			"setup": [ { "action": "focus_building_on_tile", "tile": GLASS_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "DiagnosticsCard" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "glass_lay_pipe",
			"chapter": "Integration · Margin",
			"title": "Lay a reinforced pipe",
			"body": "Stoneshore Docks already has a reinforced-pipe terminal where hazardous liquids come ashore. Connect your furnace to it: in the tile panel's Infrastructure row, click the Reinf. pipes \"+\" to lay a reinforced pipe on this tile.",
			"setup": [ { "action": "focus_tile", "tile": GLASS_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "InfraDial_reinf_pipes" },
			"lock_panel": true,
			"done": {
				"wake": ["construction_started", "infrastructure_attempted"],
				"decide": { "kind": "tile_infra_or_ordered", "tile": GLASS_TILE, "infra": "reinf_pipes", "building_id": "b_018" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_run",
			"chapter": "Integration · Margin",
			"title": "End turns until the glass flows",
			"body": "The pipe takes a turn to lay; then the sodium hydroxide flows in and the furnace fires up. Keep pressing End Turn until it reads Running. Your glass is now being made on-site.",
			"setup": [ { "action": "focus_building_on_tile", "tile": GLASS_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "building_running_on_tile", "tile": GLASS_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_output_check",
			"chapter": "Integration · Margin",
			"title": "Send the glass to the factory, not the market",
			"body": "One catch with the build menu: it routes a new building's output to the Market by default — so right now the furnace would sell its glass instead of feeding the factory beside it. In the furnace panel, open Output destination and switch it to Tile stockpile. Then the window factory next door consumes the glass on-site — no shipping, no market spread — and the wafer-thin margin widens into real profit.",
			"setup": [ { "action": "clear_mapmode" }, { "action": "focus_building_on_tile", "tile": GLASS_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "output_routed_same_tile", "tile": GLASS_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_economics",
			"chapter": "Integration · Margin",
			"title": "See the difference",
			"body": "Open your window factory and read its economics. With glass now made in-house, the cost per window has dropped further below the market price — the wafer-thin margin you started with is now a solid profit, every turn.",
			"setup": [ { "action": "clear_mapmode" }, { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "glass_better",
			"chapter": "Integration · Research",
			"title": "We can do better",
			"body": "A small profit is a fine start — but we can do far better. New recipes are waiting to be unlocked: cleaner, more efficient ways to make the same goods. Let's research a better way to make glass.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "glass_research",
			"chapter": "Integration · Research",
			"title": "Unlock High Strength Glassmaking",
			"body": "Open Research (the microscope on the bottom bar — shortcut R), click 'Choose Free Unlocks', then find and unlock 'High Strength Glassmaking' (under Inorganic Chemistry — it has no prerequisites).",
			"setup": [ { "action": "clear_mapmode" }, { "action": "open_research" } ],
			"spotlight": { "kind": "node_name", "ref": "ResearchPanel" },
			"done": {
				"wake": [],
				"decide": { "kind": "research_unlocked", "title": "High Strength Glassmaking" },
			},
			"advance": "auto",
		},
		{
			"id": "glass_upgrade",
			"chapter": "Integration · Research",
			"title": "Switch recipes — your turn",
			"body": "Unlocked! Now do it yourself, no hand-holding. Close the Research panel (press R again, or Esc), then find your factory tile and click it, select the Furnace, press 'Change recipe' and pick High Strength Glassmaking. Confirm the retool — it pauses the furnace a few turns — then End Turn until it's running the new recipe. Watch the profit jump.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"goto": "integration_done",
			"done": {
				"wake": ["turn_processed", "turn_advanced", "building_added"],
				"decide": { "kind": "building_recipe_on_tile", "tile": GLASS_TILE, "recipe_id": "r_054" },
			},
			"advance": "auto",
		},
		{
			"id": "build_alu_open",
			"chapter": "Integration · Revenue",
			"title": "Build an aluminium smelter",
			"body": "A smelter makes %d aluminium a turn — your factory needs %d, and the surplus %d sells each turn. Build it right here on your factory's tile: co-located, its output feeds the factory on-site with no shipping. All its inputs are solids, so no pipe is needed. Open the build tile and click Build." % [
				_recipe_output_qty("r_050"),
				_recipe_input_qty("r_056", "aluminium"),
				maxi(0, _recipe_output_qty("r_050") - _recipe_input_qty("r_056", "aluminium")),
			],
			"setup": [
				{ "action": "close_building_detail" },
				{ "action": "focus_tile", "tile": ALU_TILE },
			],
			"spotlight": { "kind": "node_name", "ref": "BLBuildButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "ConstructPanelV2" },
			},
			"advance": "auto",
		},
		{
			"id": "build_alu_recipe",
			"chapter": "Integration · Revenue",
			"title": "Pick Aluminium Smelting",
			"body": "Click the highlighted Aluminium (Hall Heroult) Smelting recipe.",
			"setup": [ { "action": "expand_construct_building", "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "RecipeRow_r_050" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "BuildConfirmButton" },
			},
			"advance": "auto",
		},
		{
			"id": "build_alu_confirm",
			"chapter": "Integration · Revenue",
			"title": "Confirm the build",
			"body": "Press Confirm to start the smelter on this tile.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "BuildConfirmButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "SourcingBuyButton" },
			},
			"advance": "auto",
		},
		{
			"id": "build_alu_source",
			"chapter": "Integration · Revenue",
			"title": "Buy the build materials",
			"body": "Choose Buy from market and construct. Once it runs, it smelts more aluminium than the factory needs — the surplus sells each turn. (Aluminium's the smaller input, though: glass is where the real profit lives.)",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "SourcingBuyButton" },
			"done": {
				"wake": ["construction_started", "materials_ordered"],
				"decide": { "kind": "building_or_project_on_tile", "tile": ALU_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "sell_windows",
			"chapter": "Integration · Margin",
			"title": "Turn windows into cash",
			"body": "Your new building takes a few turns to construct, and until it helps your margin stays wafer-thin. Don't let finished windows pile up — switch on 'Sell all Surplus every turn' on the factory tile. Each turn it ships them to market, turning them into cash while you integrate.",
			"setup": [ { "action": "focus_tile_stock", "tile": WINDOW_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "SellSurplusToggle" },
			"lock_panel": true,
			"done": {
				"wake": ["sell_surplus_changed"],
				"decide": { "kind": "sell_surplus_on_tile", "tile": WINDOW_TILE },
			},
			"advance": "auto",
		},
		{
			"id": "integration_done",
			"chapter": "Integration",
			"title": "That's integration",
			"body": "You brought a cost in-house — and, on the glass path, let research unlock a far better recipe — the moves that turn a wafer-thin margin into real profit. Keep going: integrate your other inputs, generate your own power, and use research, advisors and labour policies to trim what's left. That's the whole game. This tutorial's done — press Skip to play freely.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
	]


# ── Live-value helpers (balance-proof copy) ──────────────────────────────────────
# The tutorial quotes prices/quantities from the SAME data the sim runs on, so a
# rebalance updates the copy automatically. All read the Catalog autoload.

## Market value of a building's construction kit at base prices ("roughly £N").
static func _build_kit_cost(building_id: String) -> int:
	var total := 0.0
	for mat in Catalog.get_building(building_id).get("materials", []):
		var good: Dictionary = Catalog.get_good_by_internal_name(str(mat.get("name", "")))
		total += float(good.get("base_price", 0.0)) * float(mat.get("qty", 0))
	return int(round(total))

## Base market price of a good, trimmed for prose ("10.22", "12.5", "8").
static func _good_price_text(internal: String) -> String:
	var price := float(Catalog.get_good_by_internal_name(internal).get("base_price", 0.0))
	var text := "%.2f" % price
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text

## Input quantity of `internal` in a recipe (0 if the recipe doesn't use it).
static func _recipe_input_qty(recipe_id: String, internal: String) -> int:
	for inp in Catalog.get_recipe(recipe_id).get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		var name := str(inp.get("internal_name", Catalog.get_internal_name(gid)))
		if name == internal:
			return int(inp.get("qty", 0))
	return 0

## Primary output quantity of a recipe.
static func _recipe_output_qty(recipe_id: String) -> int:
	return int(Catalog.get_recipe(recipe_id).get("output_qty", 0))

## Land footprint of a building (level 1).
static func _footprint(building_id: String) -> int:
	return int(round(maxf(0.0, float(Catalog.get_building(building_id).get("tile_size_used", 1.0)))))

## The buy_land step's owned-land target: everything the tutorial ever puts on the
## factory tile (window factory + cable + furnace/smelter + reinforced pipe),
## rounded up to whole patches. Footprint rebalances move the wall automatically.
static func _land_lesson_target() -> int:
	var patch := MatchState.LAND_PATCH_SIZE
	var needed := _footprint("b_007") + _footprint("b_006") + _footprint("b_002") + _footprint("b_018")
	return ceili(float(needed) / float(patch)) * patch

## How much the player still has to buy at the buy_land step: the target minus the
## seeded plot (data/starts/tutorial.json) minus the factory footprint granted by
## the purchase — rounded up to a whole patch (the shop sells in patches).
static func _land_lesson_shortfall() -> int:
	var patch := MatchState.LAND_PATCH_SIZE
	var owned_by_then := TUTORIAL_SEED_LAND + _footprint("b_007")
	var shortfall := maxi(0, _land_lesson_target() - owned_by_then)
	return maxi(patch, ceili(float(shortfall) / float(patch)) * patch)

# Must match data/starts/tutorial.json "land" for the factory tile (JSON can't
# compute; keep the two in sync — the unit test cross-checks them).
const TUTORIAL_SEED_LAND := 20


## DEEPER INTEGRATION — deferred. Mining your own coal + pumping your own water to feed
## the power plant (so even the plant's fuel is in-house), and reading the falling cost/unit.
## Authored and kept ready but NOT yet returned by steps(); when added they slot after
## build_own_power and get reworked to the tile-Build + search + sourcing-dialog flow.
static func _integration_steps() -> Array:
	return [
		{
			"id": "build_own_power",
			"chapter": "Integration · Power",
			"title": "Build your own power plant",
			"body": "Renting grid power costs money every turn. Build a Coal Power Plant on the highlighted tile and generate your own — flipping the factory from grid power to your own supply. (Deeper still: mine your own coal + pump your own water below so even the plant's fuel is in-house.)",
			"setup": [
				{ "action": "enter_build", "building_id": "b_003", "recipe_id": "r_004" },
				{ "action": "focus_tile", "tile": POWER_TILE },
			],
			"spotlight": { "kind": "tile", "ref": POWER_TILE },
			"done": {
				"wake": ["construction_started", "materials_ordered"],
				"decide": { "kind": "building_or_project_on_tile", "tile": POWER_TILE, "building_id": "b_003" },
			},
			"advance": "auto",
		},
		{
			"id": "survey_stub",
			"chapter": "Integration · Fuel",
			"title": "Survey for coal",
			"body": "That hill is unsurveyed — you can't see what's under it. Enter Surveying and survey it. (A survey takes 2 turns.)",
			"setup": [
				{ "action": "open_survey" },
				{ "action": "focus_tile", "tile": STUB_TILE },
			],
			"spotlight": { "kind": "tile", "ref": STUB_TILE },
			"done": {
				"wake": ["tile_survey_completed"],
				"decide": { "kind": "tile_surveyed", "tile": STUB_TILE },
			},
			"advance": "auto",
		},
		{
			"id": "build_coal_mine",
			"chapter": "Integration · Fuel",
			"title": "Mine your own coal",
			"body": "Coal! Build a Mine on the hill to dig your own fuel for the power plant — cheaper than buying it off the market every turn.",
			"setup": [
				{ "action": "enter_build", "building_id": "b_001", "recipe_id": "r_001" },
				{ "action": "focus_tile", "tile": STUB_TILE },
			],
			"spotlight": { "kind": "tile", "ref": STUB_TILE },
			"done": {
				"wake": ["construction_started"],
				"decide": { "kind": "building_or_project_on_tile", "tile": STUB_TILE, "building_id": "b_001" },
			},
			"advance": "auto",
		},
	]
