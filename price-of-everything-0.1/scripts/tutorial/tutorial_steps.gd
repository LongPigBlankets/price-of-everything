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

## The loan the Money chapter asks the player to take. Small on purpose: the lesson is the
## grace period and the repayment tail, not the sum.
const TUTORIAL_LOAN_AMOUNT := 100
const WEST_COAST_HANDOFF_CASH := 99999

# Opening transport lesson in Capital City. The motor factory is exactly five
# adjacent land tiles from Capital Port; the same ordered route is used by the
# seeded shipment, automatic road reveal and the rail-completion gate.
const CAPITAL_PORT_TILE := "tile_24_7"
const CAPITAL_PORT_NORTH_TILE := "tile_24_6"
const MOTOR_TILE := "tile_25_12"
const STEEL_TILE := "tile_26_12"
const CAPITAL_ROUTE_TILES: Array = [
	"tile_25_12", "tile_25_11", "tile_25_10", "tile_25_9", "tile_24_8", "tile_24_7",
]
# The port terminal is supplied, but the player lays rail on the motor-factory tile
# and the four sections between it and the port. The lesson holds this set in amber
# instead of relying on every buildable tile exposed by Rail mode.
const CAPITAL_RAIL_BUILD_TILES: Array = [
	"tile_25_12", "tile_25_11", "tile_25_10", "tile_25_9", "tile_24_8",
]
const CAPITAL_BOARD_TILES: Array = [
	"tile_25_12", "tile_25_11", "tile_25_10", "tile_25_9", "tile_24_8", "tile_24_7", "tile_26_12",
]

const BOARD_TILES: Array = [
	"tile_6_7", "tile_6_6", "tile_7_7", "tile_7_8", "tile_6_8", "tile_5_8", "tile_5_7", "tile_5_9",
]
const PORT_TILE := "tile_5_10"    # Stoneshore Docks — inputs ship in from here (view-only). Pre-seeded with a
								  # reinf_pipes terminal (data/starts/tutorial.json) so a single player pipe on
								  # the factory tile makes the glass furnace's sodium_hydroxide feed much cheaper.
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
const WINDOW_REDIRECT_TILE := "tile_6_9" # Stoneshore Coast — east of the factory, coastal but not a port
const GLASS_TILE := WINDOW_TILE   # glass furnace built on the factory tile (reinf pipe is cheapest for NaOH)
const ALU_TILE := WINDOW_TILE     # aluminium furnace built on the factory tile (chlorine needs a reinf pipe)
const INPUT_TILE := "tile_5_7"    # rural + sand(3000) deposit — the sand on the board (Encyclopedia reference)
const POWER_TILE := "tile_6_6"    # rural, adjacent — build your own power plant (deeper integration)
const WATER_TILE := "tile_7_8"    # deposit:water + river (deeper integration)
const STUB_TILE := "tile_6_8"     # hill, unsurveyed coal deposit (deeper integration)

# Building / recipe ids (verified against the catalog):
#   b_007/r_056 window factory (28 glass + 10 aluminium -> 15 windows) · b_002 furnace runs r_053 glassmaking
#   (sand+NaOH+limestone -> 28 glass), r_054 High Strength Glassmaking (silica+alumina+sulphur -> 48 glass,
#   research-gated, no NaOH), AND r_232 Bauxite Carbochlorination
#   (bauxite+graphite+chlorine -> 20 aluminium; Tier-I Metallurgy unlock; chlorine needs reinforced pipes)
#   b_018 reinf_pipes (£50, 1 turn — the cheapest mode for NaOH) · b_003/r_004 coal power plant (deferred)

## Balance-sensitive numbers in the copy (kit costs, market prices, recipe
## quantities, land targets) are COMPUTED from the live Catalog/EconomyConfig at
## steps() time, so a rebalance never leaves the tutorial quoting stale figures.
## steps() runs at tutorial start (and in tests) — the autoloads are loaded by then.

## A step Dictionary:
##   id/chapter/title/body — identity + coach card copy
##   setup     : ordered driver actions run on entry
##   spotlight : {kind: node_path|node_name|tile|none, ref}
##   spotlight_passthrough: false highlights a control but keeps it read-only
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
				"Carbon and Capital is an industrial simulator where you take over a business and expand it, integrating along the way until you are the biggest company in Taralia.",
				"This tutorial will take you through the basics of buying and constructing buildings, how to feed your furnaces and factories and get your company up and running. It also covers how loans work, how to unlock research, hire advisors and more.",
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
			"card_side": "left",
			"body": "A quick tour of the screen. The bar along the bottom is your toolkit — each tool has a keyboard shortcut (the letter in brackets). The top bar is your dashboard: money, victory tracks, the briefing with updates and decisions, your advisors and the menu. You end each turn from the bottom-right. Have a look, then press Next.",
			"targets": [
				{ "ref": "ConstructButton", "label": "Build (C)", "side": "above" },
				{ "ref": "ResourcesButton", "label": "Goods list (R)", "side": "above" },
				{ "ref": "BuildingsButton", "label": "Buildings (L)", "side": "above" },
				{ "ref": "MapmodesButton", "label": "Overlays (O)", "side": "above" },
				{ "ref": "MarketButton", "label": "Markets (M)", "side": "above" },
				{ "ref": "PoliticsButton", "label": "Narrative & Politics (N)", "side": "above", "lift": 1 },
				{ "ref": "TechButton", "label": "Tech & Research (T)", "side": "above" },
				{ "ref": "PeopleButton", "label": "People (P)", "side": "above" },
				{ "ref": "EmpireButton", "label": "Empire view (Tab)", "side": "above" },
				{ "ref": "MoneyWidget", "label": "Budgets, charts & loans", "side": "below" },
				{ "ref": "VictoryModule", "label": "Victory tracks — five ways to win", "side": "below" },
				{ "ref": "BriefingModule", "label": "Briefing — updates & decisions", "side": "below" },
				{ "ref": "CouncilModule", "label": "Advisors", "side": "below" },
				{ "ref": "EncyclopediaButton", "label": "Encyclopedia (X)", "side": "below" },
				{ "ref": "GoodsGraphModule", "label": "Goods Graph (G)", "side": "below" },
				{ "ref": "MenuModule", "label": "Main menu", "side": "below" },
				{ "ref": "EndTurnButton", "label": "End turn", "side": "above" },
			],
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "recipe_inputs_intro",
			"chapter": "Production",
			"title": "Buildings run recipes",
			"mode": "recipe_flow",
			"diagram_phase": 1,
			"body": "Buildings run recipes to produce outputs, like rubber. Each recipe requires inputs: power to run and also goods like oxygen and ethylene.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "recipe_outputs_intro",
			"chapter": "Production",
			"title": "Where the output goes",
			"mode": "recipe_flow",
			"diagram_phase": 2,
			"body": "The resulting goods can then be used in construction, sold to the market or used to feed into something else.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "capital_motor_open",
			"chapter": "Moving Goods",
			"title": "Open your motor factory",
			"body": "This Industrial Goods Factory belongs to you and makes motors. Click the factory card to open it.",
			"setup": [ { "action": "focus_tile", "tile": MOTOR_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingCard_b_007_r_009" },
			"done": {
				"wake": [],
				"decide": { "kind": "building_detail_open", "tile": MOTOR_TILE, "building_id": "b_007", "recipe_id": "r_009" },
			},
			"advance": "auto",
		},
		{
			"id": "capital_motor_route",
			"chapter": "Moving Goods",
			"title": "Choose where output goes",
			"body": "You can send output to a stockpile, where other buildings may use it, to other tiles, or to the market for sale. Press Next.",
			"setup": [ { "action": "focus_building_on_tile", "tile": MOTOR_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "OutputDestCard" },
			"spotlight_passthrough": false,
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "capital_motor_watch",
			"chapter": "Moving Goods",
			"title": "Watch the first shipment",
			"body": "There is no road or rail on this route yet. End Turn up to five times and watch the motor pentagon move one tile at a time toward Capital Port. Your first profit arrives only when it reaches the port.",
			"setup": [ { "action": "close_building_detail" }, { "action": "open_logistics" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"camera": { "tiles": CAPITAL_BOARD_TILES + [CAPITAL_PORT_NORTH_TILE], "grow": 300.0 },
			"done": {
				"wake": ["turn_advanced", "stockpile_market_sale_completed"],
				"decide": { "kind": "filtered_market_sale_since_entry", "tile": MOTOR_TILE, "good": "motor", "turns": 5 },
			},
			"advance": "auto",
		},
		{
			"id": "capital_money_transport",
			"chapter": "Moving Goods",
			"title": "Transporting without roads is slow and inefficient",
			"body": "Transporting offroad/using unpaved roads is brutal in terms of time and money. This transport section explains how that cost breaks down. Click next when you're ready to see what roads can do.",
			"setup": [ { "action": "clear_mapmode" }, { "action": "open_money_transport" } ],
			"spotlight": { "kind": "node_name", "ref": "TransportCostGroup" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "capital_road_install",
			"chapter": "Moving Goods",
			"title": "Roads speed up deliveries",
			"body": "Roads and rail ship goods overland faster and cheaper. A road has been automatically built between the factory and the port. Roads allow shipments to go 2 tiles each turn instead of the default 1 tile per turn. The 5 tile journey now completes in just 3 turns. Press Next.",
			"setup": [
				{ "action": "close_money_panel" },
				{ "action": "clear_capital_motor_shipments" },
				{ "action": "restock_motor_inputs", "turns": 4 },
				{ "action": "install_tutorial_roads" },
				{ "action": "seed_motor_shipment", "id": "road", "turns": 3 },
				{ "action": "flash_capital_route" },
			],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "capital_road_watch",
			"chapter": "Moving Goods",
			"title": "Factory to port in 3 turns",
			"body": "Click End Turn until the shipment reaches the port via roads.",
			"count_step": false,
			"setup": [ { "action": "open_logistics" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["turn_advanced", "stockpile_market_sale_completed"],
				"decide": { "kind": "filtered_market_sale_since_entry", "tile": MOTOR_TILE, "good": "motor", "turns": 3 },
			},
			"advance": "auto",
		},
		{
			"id": "capital_rail_build",
			"chapter": "Moving Goods",
			"title": "Build rail along the route",
			"body": "Rail is faster and cheaper for heavy solid goods such as motors. The port terminal is ready. Build Rail on the factory tile and the four amber tiles between it and the port, then End Turn to complete the route.",
			"setup": [
				{ "action": "close_tile_panel" },
				{ "action": "clear_mapmode" },
				{ "action": "install_tutorial_rail_port_terminal" },
				{ "action": "enter_infra", "infra": "rails" },
				{ "action": "hold_capital_rail_tiles" },
			],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["construction_completed"],
				"decide": { "kind": "route_has_infra", "tiles": CAPITAL_ROUTE_TILES, "infra": "rails" },
			},
			"advance": "auto",
		},
		{
			"id": "capital_rail_watch",
			"chapter": "Moving Goods",
			"title": "Rail cuts it to two turns",
			"body": "The rail route is complete. End Turn up to two times and watch: rail covers four tiles per turn, so the five-tile journey now takes only two turns. Its per-unit transport price is lower than the road shipment too.",
			"count_step": false,
			"setup": [ { "action": "exit_build_mode" }, { "action": "transfer_capital_transport_infrastructure" }, { "action": "clear_capital_motor_shipments" }, { "action": "restock_motor_inputs", "turns": 3 }, { "action": "open_logistics" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["turn_advanced", "stockpile_market_sale_completed"],
				"decide": { "kind": "filtered_market_sale_since_entry", "tile": MOTOR_TILE, "good": "motor", "turns": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "capital_fluids",
			"chapter": "Moving Goods",
			"title": "Some goods can use pipework",
			"body": "Some goods can travel by Pipework or Reinforced Pipework as well as by road or rail. Hydrogen, for example, can use Reinforced Pipework. It is cheaper and keeps traffic off your roads and rail. Press Next.",
			"setup": [ { "action": "clear_mapmode" }, { "action": "spawn_steel_demo" }, { "action": "focus_building_on_tile", "tile": STEEL_TILE, "building_id": "b_008" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "capital_port_open",
			"chapter": "Moving Goods",
			"title": "Open Capital Port",
			"body": "Every market export and import also crosses a port. Open Capital Port to inspect the trade charges added there.",
			"count_step": false,
			"setup": [ { "action": "close_building_detail" }, { "action": "focus_tile", "tile": CAPITAL_PORT_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "PortBuildingCard" },
			"done": {
				"wake": [],
				"decide": { "kind": "building_detail_open", "tile": CAPITAL_PORT_TILE, "building_id": "b_004" },
			},
			"advance": "auto",
		},
		{
			"id": "capital_port_costs",
			"chapter": "Moving Goods",
			"title": "Read the port terms",
			"body": "Port charges are based on the market value of what crosses the docks. Throughput congestion can double them, the fee drifts upward each turn, and the standard ad valorem rate rises in the later era. Owning a port halves that rate, but brings upkeep and labour. Always check the live terms rather than assuming yesterday's export or import cost. Press Next.",
			"count_step": false,
			"setup": [ { "action": "focus_any_building_on_tile", "tile": CAPITAL_PORT_TILE, "building_id": "b_004" } ],
			"spotlight": { "kind": "node_name", "ref": "PortTermsCard" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "goto_tile",
			"chapter": "First Factory",
			"title": "Find the factory inland",
			"body": "Let's begin with your first building. Pan (drag) and zoom (scroll) inland a little to find it — look for the white building; white means an NPC owns it, and this one is up for sale. Click it (the Industrial Goods Factory, the one Vandel Glassworks is selling) to open its tile.",
			"board_tiles": BOARD_TILES,
			"setup": [
				{ "action": "handoff_from_capital_lesson" },
				{ "action": "close_building_detail" },
			],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"camera": { "tiles": _factory_explore_tiles(), "grow": 160.0 },
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
			"card_side": "center_top",
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
			"body": "Constructing the factory costs more because we would have to import materials and pay for their transport.\n\nBut purchasing it might be cheaper at the start. If you produce the steel, concrete and frames you need you can make construction dramatically cheaper.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "BuildCostValue" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "build_close_buy",
			"chapter": "First Factory",
			"title": "Let's buy it instead",
			"body": "Now open this tile's Buildings for sale yourself, where Vandel's factory is up for grabs.",
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
			"body": "The £%d cost to buy it looks like more than to build it, right?\n\nBut within that price comes the first 2 turns of supplies to run the building.\n\nThat means no more transport cost from the port and the building runs the turn after you buy it (assuming power)." % _window_factory_purchase_price(),
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
			"title": "This factory runs a window making recipe",
			"body": "Window factories consume aluminium for the window frames and glass for the panes. But as you can tell from the two red diagnostic lines, the building can't run. Click next to begin fixing it.",
			"setup": [
				{ "action": "close_market_panel" },
				{ "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "diagnose_factory",
			"chapter": "First Factory",
			"title": "Why isn't it running?",
			"body": "The red Power row is the blocker: the factory has no electricity, so it's switched off.",
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
			"spotlight": { "kind": "node_name", "ref": "InfraCell_cables" },
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
			"body": "Laying a cable needs a few construction materials you don't have on this tile yet. Choose Buy from market to order them and start the cable.",
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
			"body": "It takes 2 turns for the construction materials to arrive and a 3rd turn to complete. And then the building will make windows. Click 'End turn' a few times until the building runs.",
			"setup": [ { "action": "focus_building_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "building_running_on_tile", "tile": WINDOW_TILE, "building_id": "b_007" },
			},
			"advance": "auto",
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
			"body": "Choose 'Ship to another tile', then click Stoneshore Coast, the non-port tile immediately east of the factory.",
			"board_tiles": BOARD_TILES + [WINDOW_REDIRECT_TILE],
			"setup": [
				{
					"action": "flash_tiles", "tiles": [WINDOW_REDIRECT_TILE],
					"color": "white", "pulse_count": 10, "pulse_seconds": 0.7,
				},
			],
			# Updating board_tiles reapplies the tight interaction-board clamp. Restore the
			# broader viewing envelope here; it then persists through the glass/metal lessons.
			"camera": { "tiles": _factory_explore_tiles(), "grow": 160.0 },
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": [],
				"decide": {
					"kind": "output_routed_to_tile", "tile": WINDOW_TILE,
					"building_id": "b_007", "destination": WINDOW_REDIRECT_TILE,
				},
			},
			"advance": "auto",
		},
		{
			"id": "transport_pentagon_revert",
			"chapter": "Transport",
			"title": "Watch the windows arrive",
			"body": "Click End Turn until the windows reach the coastal tile east of the factory. This step will continue when the shipment arrives.",
			"setup": [ { "action": "open_logistics" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["turn_advanced", "turn_processed", "transport_shipments_changed", "stockpile_changed"],
				"decide": {
					"kind": "stockpile_good_at_least", "tile": WINDOW_REDIRECT_TILE,
					"good": "windows", "amount": 1,
				},
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
				{ "action": "route_building_outputs_to_market", "tile": WINDOW_TILE, "building_id": "b_007" },
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
			"body": "This is the Encyclopedia — press X any time to open it. Search 'glass' (made in a Furnace from sand, and there's sand on your board) and 'aluminium' (smelted in a Furnace). Have a look, then press Next.",
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
			"id": "revenue_settle",
			"chapter": "Money",
			"title": "Watch the shipment sell",
			"body": "Your output is on its way to market, but revenue only lands when it arrives. Keep pressing End Turn and watch the shipment travel; this step will continue as soon as the sale goes through.",
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"no_dim": true,
			"done": {
				"wake": ["turn_advanced", "turn_processed", "stockpile_market_sale_completed"],
				"decide": { "kind": "market_sale_completed_since_entry" },
			},
			"advance": "auto",
		},
		{
			"id": "money_open",
			"chapter": "Money",
			"title": "Where the money actually goes",
			"body": "Your factory is earning. Before you spend any of it, learn to read the books — every decision from here is really a question about this panel. Click your balance in the top-left corner to open it.",
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "MoneyWidget" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "Flyout_treasury" },
			},
			"advance": "auto",
		},
		{
			"id": "money_primer",
			"chapter": "Money",
			"title": "Reading the books",
			"mode": "annotate",
			"body": "Every pound in and out, each turn. Revenue is what your goods sold for. OPERATING COSTS is your maintenance plus wages — the standing cost of simply owning the place, which you pay whether it produces or not. Everything below that is itemised: power bought, transport, goods purchased, warehousing, interest, tax and dividends. Net last turn is the whole lot netted off. For the full ledger, open Balance.",
			"targets": [
				{ "ref": "FlyRowCash", "label": "Everything you have to spend right now", "side": "left" },
				{ "ref": "FlyRowNet", "label": "Last turn's profit — revenue minus every cost below", "side": "left" },
				{ "ref": "FlyBalanceButton", "label": "Full itemised ledger, if you want the detail", "side": "left" },
				{ "ref": "FlyTakeLoanButton", "label": "Borrow against future earnings", "side": "left" },
			],
			"hints": [
				"Revenue minus costs is the number that decides whether you're winning",
				"Press Esc to close any panel",
			],
			"setup": [ { "action": "open_money_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "Flyout_treasury" },
			# This is an explanation-only card.  Re-locking its flyout from the poll can
			# rebuild the money panel under the Next click, so leave the already-open
			# panel alone while the player reads it.
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "money_take_loan",
			"chapter": "Money",
			"title": "Borrow to grow",
			"body": "Waiting to save up is the slowest way to play. Borrow £%d for the integration you are about to build. Press Take loan — that opens the Loans tab — then set the amount to £%d and confirm. Nothing is locked while you do it, so take your time." % [TUTORIAL_LOAN_AMOUNT, TUTORIAL_LOAN_AMOUNT],
			"setup": [ { "action": "open_money_panel" } ],
			# The previous annotated step has already shown the Take loan button.  Do
			# not retain a spotlight here: once the button opens the Loans tab, the old
			# spotlight would intercept the confirmation controls behind it.
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["money_changed"],
				"decide": { "kind": "loan_taken", "amount": TUTORIAL_LOAN_AMOUNT },
			},
			"advance": "auto",
		},
		{
			"id": "money_loan_terms",
			"chapter": "Money",
			"title": "The terms of the loan",
			"body": "Nothing is due for the first %d turns — that's your grace period, and it's the window to turn the money into something that earns. After it, the loan converts and you repay over %d turns, with interest of %d%% across the term. Plan for the repayment landing before it starts, not after." % [
				EconomyConfig.LOAN_GRACE_TURNS, EconomyConfig.LOAN_TERM_TURNS,
				int(round(EconomyConfig.LOAN_INTEREST_RATE * 100.0))],
			"setup": [ { "action": "open_money_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "Flyout_treasury" },
			# As with the preceding primer, this is a read-and-continue step.  The
			# flyout is already opened on entry; polling must not rebuild it beneath
			# the Next button while the player dismisses this explanation.
			"done": { "wake": [], "decide": {} },
			"advance": "next",
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
			"card_side": "center_top",
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
			"title": "Inputs are on their way",
			"body": "The building shows red because it lacks inputs. Don't worry — they're on their way from the port. Click End Turn a couple of times. In future, consider building a reinforced pipeline: sodium hydroxide is a hazardous liquid, and it travels more cheaply that way.",
			"setup": [ { "action": "focus_building_on_tile", "tile": GLASS_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"lock_panel": true,
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "turns_advanced", "count": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "glass_lay_pipe",
			"chapter": "Integration · Margin",
			"title": "Lay a reinforced pipe",
			"body": "Stoneshore Docks already has a reinforced-pipe terminal where hazardous liquids come ashore. Connect your furnace to it: in the tile panel's Infrastructure row, click the Reinf. pipes \"+\" to lay a reinforced pipe on this tile.",
			"setup": [ { "action": "focus_tile", "tile": GLASS_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "InfraCell_reinf_pipes" },
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
			"title": "Let the profit settle",
			"body": "The pipe is being laid, and the furnace will now send its glass to the tile stockpile for the window factory. Press End Turn twice so the new supply chain has two full turns to settle.",
			"setup": [
				{ "action": "close_building_detail" },
				{
					"action": "route_building_outputs_to_tile", "tile": GLASS_TILE,
					"building_id": "b_002", "destination": WINDOW_TILE,
				},
			],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "turns_advanced", "count": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "glass_profit",
			"chapter": "Integration · Margin",
			"title": "Profit after integration: {profit}",
			"body": "Your last settled turn made {profit}. Bringing glass in-house improved the margin, but we can do better. Next, unlock a more efficient glass recipe.",
			"body_dynamic": "last_turn_profit",
			# This is the result phase of Step 46, after its two required turns. Keeping it
			# unnumbered makes the following Research instruction Step 47.
			"count_step": false,
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "MoneyWidget" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "glass_research",
			"chapter": "Integration · Research",
			"title": "Unlock High Strength Glassmaking",
			"body": "Open Tech & Research (the microscope on the bottom bar — shortcut T), click 'Choose Free Unlocks', then find and unlock 'High Strength Glassmaking' (under Inorganic Chemistry — it has no prerequisites).",
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
			"body": "Unlocked! Now do it yourself, no hand-holding. Close the Tech & Research panel (press T again, or Esc), then find your factory tile and click it, select the Furnace, press 'Change recipe' and pick High Strength Glassmaking. Confirm the retool — it pauses the furnace a few turns — then End Turn until it's running the new recipe. Watch the profit jump.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			# Rejoin at the Advisors chapter, not the finale — jumping straight to
			# integration_done skipped the whole advisor arc on the glass path.
			"goto": "advisors_intro",
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
			"body": "A smelter makes %d aluminium a turn — your factory needs %d, and the surplus %d sells each turn. Build it right here on your factory's tile: co-located, its output feeds the factory on-site with no shipping. We will improve this base process once it is running. Open the build tile and click Build." % [
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
			"title": "Pick Aluminium (Hall Heroult) Smelting",
			"body": "Start with the highlighted Aluminium (Hall Heroult) Smelting recipe. It will get aluminium flowing; later we will unlock a better Furnace process and switch this same building over.",
			"card_side": "center_top",
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
			"id": "alu_wait_built",
			"chapter": "Integration · Revenue",
			"title": "End turns until the smelter is built",
			"body": "Keep pressing End Turn while the smelter goes up. Once it is finished, we can get its base process running and feed the factory.",
			"setup": [ { "action": "focus_tile", "tile": ALU_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["construction_completed", "turn_processed", "turn_advanced"],
				"decide": { "kind": "building_owned_on_tile", "tile": ALU_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_run_base",
			"chapter": "Integration · Revenue",
			"title": "Let the base smelter run",
			"body": "Keep pressing End Turn until the smelter reads Running. The Hall Heroult process can now feed the factory and sell its surplus.",
			"setup": [ { "action": "focus_building_on_tile", "tile": ALU_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "building_running_on_tile", "tile": ALU_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_output_check",
			"chapter": "Integration · Revenue",
			"title": "Feed the factory before selling the surplus",
			"body": "New buildings send output to the Market by default. In the smelter panel, open Output destination and switch it to Tile stockpile. The window factory can then take its aluminium on-site; only the excess becomes surplus for sale. Once it is routed, we'll give the chain two turns to settle.",
			"setup": [ { "action": "clear_mapmode" }, { "action": "focus_building_on_tile", "tile": ALU_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "BuildingDetailPanelV2" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "output_routed_same_tile", "tile": ALU_TILE, "building_id": "b_002" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_base_settle",
			"chapter": "Integration · Revenue",
			"title": "Let the supply chain settle",
			"body": "Press End Turn twice so the smelter can feed the window factory and the new margin can stabilise. Then we'll look at Research.",
			# This is the second phase of Step 45. It begins only after the player routes
			# aluminium locally and stays unnumbered so Research remains Step 46.
			"count_step": false,
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "turns_advanced", "count": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "alu_research",
			"chapter": "Integration · Research",
			"title": "We can improve our margins",
			"body": "Let's improve our margins. Open the Research panel. There has to be a better way to make Aluminium.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "node_name", "ref": "TechButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "ResearchPanel" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_research_search",
			"chapter": "Integration · Research",
			"title": "Search for aluminium",
			"body": "Use the Research search box and type aluminium. The highlighted Bauxite Carbochlorination process is the lower-temperature Furnace route we want.",
			"setup": [],
			"spotlight": { "kind": "node_name", "ref": "ResearchSearchInput" },
			"release_overlay_when": { "kind": "research_search_nonempty" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "research_search_contains", "text": "aluminium" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_research_condition",
			"chapter": "Integration · Research",
			"title": "Read the condition",
			"body": "The normal unlock condition is Produce 300 Chlorine and 400 Aluminium. It replaces some of the Hall Heroult inputs with bauxite, graphite and chlorine, using less energy.",
			"setup": [],
			"spotlight": { "kind": "research_unlock", "ref": "Bauxite Carbochlorination" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "alu_research_unlock",
			"chapter": "Integration · Research",
			"title": "Use your free unlock",
			"body": "But we have a free unlock from our brilliant researchers. Go ahead and unlock the highlighted Bauxite Carbochlorination research.",
			"setup": [ { "action": "research_choose_free_unlock" } ],
			"spotlight": { "kind": "research_unlock", "ref": "Bauxite Carbochlorination" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "research_unlocked", "title": "Bauxite Carbochlorination" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_upgrade",
			"chapter": "Integration · Research",
			"title": "Switch recipes — your turn",
			"body": "Unlocked! Close the Tech & Research panel (press T again, or Esc), find your smelter and press Change recipe. Pick Bauxite Carbochlorination, confirm the retool, then End Turn until the change completes. We will connect its chlorine supply next.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": {
				"wake": ["turn_processed", "turn_advanced", "building_added"],
				"decide": { "kind": "building_recipe_on_tile", "tile": ALU_TILE, "recipe_id": "r_232" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_diagnose_pipe",
			"chapter": "Integration · Revenue",
			"title": "Pipes",
			"body": "Pipelines can transport gases and liquids easier and cheaper than road or rail. It also decongests your roads and rail. The retool is complete. Press End Turn twice more so the new recipe can run and its costs can settle.",
			"setup": [ { "action": "focus_building_on_tile", "tile": ALU_TILE, "building_id": "b_002" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "turns_advanced", "count": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "alu_lay_pipe",
			"chapter": "Integration · Revenue",
			"title": "Lay the reinforced pipe",
			"body": "Connect the smelter to Stoneshore Docks: in the tile panel's Infrastructure row, click the Reinf. pipes \"+\" to lay a reinforced pipe on this tile.",
			"setup": [ { "action": "focus_tile", "tile": ALU_TILE } ],
			"spotlight": { "kind": "node_name", "ref": "InfraCell_reinf_pipes" },
			"lock_panel": true,
			"done": {
				"wake": ["construction_started", "infrastructure_attempted"],
				"decide": { "kind": "tile_infra_or_ordered", "tile": ALU_TILE, "infra": "reinf_pipes", "building_id": "b_018" },
			},
			"advance": "auto",
		},
		{
			"id": "alu_final_run",
			"chapter": "Integration · Revenue",
			"title": "Let the lower cost feed through",
			"body": "Press End Turn twice. The first turn finishes the pipe and starts the new recipe; the second lets its lower cost feed through the chain.",
			"count_step": false,
			"setup": [ { "action": "close_building_detail" } ],
			"spotlight": { "kind": "node_name", "ref": "EndTurnButton" },
			"done": {
				"wake": ["turn_processed", "turn_advanced"],
				"decide": { "kind": "turns_advanced", "count": 2 },
			},
			"advance": "auto",
		},
		{
			"id": "alu_profit",
			"chapter": "Integration · Revenue",
			"title": "Profit after the new recipe: {profit}",
			"body": "Your last settled turn made {profit}. The cheaper recipe has now fed through the chain. Compare Net last turn with the costs beneath it, then click Next.",
			"body_dynamic": "last_turn_profit",
			"mode": "annotate",
			"targets": [
				{ "ref": "FlyRowNet", "label": "Profit after every cost", "side": "left" },
			],
			"setup": [
				{ "action": "close_building_detail" },
				{ "action": "open_money_panel" },
			],
			"spotlight": { "kind": "node_name", "ref": "Flyout_treasury" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "advisors_intro",
			"chapter": "Advisors",
			"title": "You can't run all of it yourself",
			"body": "One last lever, and it's the one players forget. Open People on the bottom bar (shortcut P). Advisors is the first tab. (The Council badge in the top bar only lists advisors you have already hired, so it's empty until you do.)",
			"setup": [ { "action": "close_building_detail" }, { "action": "close_money_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "PeopleButton" },
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "PeoplePanel" },
			},
			"advance": "auto",
		},
		{
			"id": "advisors_explain",
			"chapter": "Advisors",
			"title": "These are the positions, not the people",
			"body": "Every row here is a SEAT you can fill, and each seat pulls on a different part of the business. A CFO wants someone good with numbers — they manage your loans and your tax bill better than you will. A COO wants someone process-driven — they bring down labour and maintenance, the two costs you cannot integrate away. The same person is rarely right for both, so read the seat first and the candidate second. Look through the rest of the positions after the tutorial to see what each one governs.",
			"setup": [ { "action": "open_people_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "PeoplePanel" },
			"lock_panel": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "advisors_inspect",
			"chapter": "Advisors",
			"title": "Inspect what a candidate brings",
			"body": "Click + Add new advisor, then open a candidate's profile and choose a position. Read the WHAT THEY BRING bonuses — they change with the position you select, so this is where you decide which lever to improve.",
			"setup": [ { "action": "open_people_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "AdvisorAddNewButton" },
			"lock_panel": true,
			"done": {
				"wake": [],
				"decide": { "kind": "node_visible", "ref": "AdvisorBonusSection" },
			},
			"advance": "auto",
		},
		{
			"id": "advisors_hire",
			"chapter": "Advisors",
			"title": "Choose any seat and hire them",
			"body": "Now choose whichever available seat you want in the Assign to row, then Hire & assign. There is no prescribed answer: the seat determines the bonus, and the candidate determines how strongly they deliver it. Their effect starts next turn.",
			"setup": [ { "action": "open_people_panel" } ],
			"spotlight": { "kind": "node_name", "ref": "PeoplePanel" },
			"lock_panel": true,
			"done": {
				# No seat-change signal exists; the engine's 0.25s poll re-evaluates the
				# state anyway, and every available seat is a valid tutorial outcome.
				"wake": ["money_changed"],
				"decide": { "kind": "advisor_seated", "count": 1 },
			},
			"advance": "auto",
		},
		{
			"id": "advisors_effect",
			"chapter": "Advisors",
			"title": "Watch what it moves",
			"body": "Seated. End a turn and open the money panel again — the line their seat governs will have shifted. That's the whole game in one habit: change something, then go and read the number it was supposed to move. You know how to buy, build, connect, integrate, research, borrow and staff. The rest is yours.",
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"no_dim": true,
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "integration_done",
			"chapter": "Tutorial",
			"title": "Tutorial complete",
			"body": "This tutorial has give you all the basic tools to get on in Carbon and Capital. You can continue playing this tutorial. The victory conditions will now be reenabled after bringing you to a more... reasonable bank balance.",
			"setup": [ { "action": "clear_mapmode" } ],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
			"next_label": "End tutorial",
			"hide_skip": true,
		},
	]


# ── Live-value helpers (balance-proof copy) ──────────────────────────────────────
# The tutorial quotes prices/quantities from the SAME data the sim runs on, so a
# rebalance updates the copy automatically. All read the Catalog autoload.

## The west-coast camera may roam five hexes from the factory: an eleven-tile-wide
## neighbourhood. Keep this separate from BOARD_TILES, which remains the tutorial's
## interaction whitelist; the player can look around without building on every tile.
static func _factory_explore_tiles() -> Array:
	const RADIUS := 5
	var tiles: Array = [WINDOW_TILE]
	var seen: Dictionary = {WINDOW_TILE: true}
	var frontier: Array = [WINDOW_TILE]
	for _ring in RADIUS:
		var next_frontier: Array = []
		for tile_id in frontier:
			for neighbour in Catalog.tile_neighbours(str(tile_id)):
				var neighbour_id := str(neighbour)
				if seen.has(neighbour_id):
					continue
				seen[neighbour_id] = true
				tiles.append(neighbour_id)
				next_frontier.append(neighbour_id)
		frontier = next_frontier
	return tiles

## Market value of a building's construction kit at base prices ("roughly £N").
## The figure the Build CONFIRM screen actually prints, so the copy can't misquote it:
## the same sum as construct_panel_v2._construction_display_cost — the building's cash leg
## plus its resolved material kit valued at MARKET BUY prices. The previous version summed
## the raw materials list at BASE price with no cash leg, which quoted £177 for the window
## factory where the panel showed £196.20 (and £129 vs £155 for the furnace).
static func _build_confirm_cost(building_id: String) -> int:
	var cash := maxf(0.0, float(Catalog.get_building(building_id).get("base_price", 0.0)))
	return int(round(cash + Construction.market_purchase_value(building_id)))

## The live asking price shown beside the tutorial's NPC window factory. The price includes
## two turns of recipe inputs, so Step 17 must quote the same helper as the market's Buy button.
static func _window_factory_purchase_price() -> int:
	for instance_id in MatchState.tile_buildings.get(WINDOW_TILE, []):
		var building: Dictionary = MatchState.get_building(str(instance_id))
		if str(building.get("building_id", "")) == "b_007" \
				and str(building.get("recipe_id", "")) == "r_056" \
				and not MatchState.is_player_owned(building):
			return MatchState.building_purchase_price(building)
	# Headless authoring/tests may inspect steps without loading the tutorial start. Keep a
	# deterministic fallback; the real tutorial always resolves the placed instance above.
	return MatchState.building_purchase_price({
		"instance_id": "tutorial_window_factory",
		"building_id": "b_007",
		"recipe_id": "r_056",
		"tile_id": WINDOW_TILE,
		"level": 1,
	})

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
#
# 20 until the 2026-08-17 building resize. The buy_land lesson only teaches anything if the
# seed CANNOT cover the cable run plus the furnace, and those became 2 + 18 = exactly 20 —
# the wall vanished by one unit, silently, with the tutorial still "passing" its own steps.
# 15 is the factory's own footprint: you start with room for exactly what you were given.
# RETUNE WITH tile_size_used; the unit test asserts both halves of the wall.
const TUTORIAL_SEED_LAND := 15


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
