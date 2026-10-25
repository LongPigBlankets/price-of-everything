extends RefCounted
## The opening steps every new game plays before the missions take over (Tutorial.start_opener): the welcome,
## the screen tour, tiles and the recipe diagram, then the player's own buildings, their costs, a first turn
## and what to do next. Plain Dictionaries (copy, targets and predicates only, no engine logic), so the whole
## sequence reads top to bottom. Referenced via preload (no class_name).
##
## A step Dictionary:
##   id/chapter/title/body — identity + coach card copy
##   mode      : "welcome" (paragraphs + cta), "annotate" (targets with leader lines), "recipe_flow"
##   setup     : ordered driver actions run on entry (close_tile_panel)
##   spotlight : {kind: node_name|none, ref}
##   spotlight_passthrough: false highlights a control but keeps it read-only
##   lock_panel: true keeps the spotlit panel open + swallows Esc (no stuck state)
##   done      : {wake:[signals], decide:<predicate>} — empty decide = info step (Next)
##   advance   : "auto" (on decide) or "next" (info card)

## The opener step from which End Turn works. Before it a press is refused with END_TURN_LOCKED.
const OPENER_END_TURN_STEP := "opener_your_turn"
const END_TURN_LOCKED := "Please click 'Next' in the tutorial to enable this."


static func opener_steps() -> Array:
	var out: Array = _opener_intro_steps()
	out.append_array(_opener_business_steps())
	return out


## The welcome, the screen tour, tiles and the recipe diagram.
static func _opener_intro_steps() -> Array:
	return [
		{
			"id": "welcome",
			"chapter": "Welcome",
			"title": "Welcome to Carbon and Capital",
			"mode": "welcome",
			"paragraphs": [
				"Carbon and Capital is an industrial simulator where you take over a business and expand it, integrating along the way until you are the biggest company in Taralia.",
				"The first few steps will show you how to use the interface and then we'll dive into running your business.",
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
			"body": "A quick tour of the interface. Click on any of them to open up the panels. You can always hit 'Esc' to close panels or swap which panel is in focus by clicking on it.",
			# The screen tour leaves the HUD lit and live: only the map is shaded and blocked.
			"map_only": true,
			"targets": [
				{ "ref": "UpdatesDock", "label": "Updates and decisions", "side": "above" },
				{ "ref": "ConstructButton", "label": "Build (C)", "side": "above" },
				{ "ref": "ResourcesButton", "label": "Goods list (R)", "side": "above" },
				{ "ref": "BuildingsButton", "label": "Buildings (L)", "side": "above" },
				{ "ref": "MapmodesButton", "label": "Overlays (O)", "side": "above" },
				{ "ref": "MarketButton", "label": "Markets (M)", "side": "above" },
				{ "ref": "PoliticsButton", "label": "Narrative & Politics (N)", "side": "above", "lift": 1 },
				{ "ref": "TechButton", "label": "Tech & Research (T)", "side": "above" },
				{ "ref": "PeopleButton", "label": "People (P)", "side": "above" },
				{ "ref": "EmpireButton", "label": "Supply chain view (Tab)", "side": "above" },
				{ "ref": "MoneyWidget", "label": "Budgets, charts & loans", "side": "below" },
				{ "ref": "VictoryModule", "label": "Victory tracks: five ways to win", "side": "below" },
				{ "ref": "WorkforceModule", "label": "Workforce", "side": "below" },
				{ "ref": "EncyclopediaButton", "label": "Encyclopedia (X)", "side": "below", "lift": 2 },
				{ "ref": "GoodsGraphModule", "label": "Goods Graph (G)", "side": "below" },
				{ "ref": "TransportModule", "label": "Shipments and Stockpiles", "side": "below", "lift": 2 },
				{ "ref": "PowerModule", "label": "Power", "side": "below", "lift": 1 },
				{ "ref": "RankingsModule", "label": "Ranking", "side": "below", "lift": 1 },
				{ "ref": "MenuModule", "label": "Main menu", "side": "below" },
				{ "ref": "EndTurnButton", "label": "End turn", "side": "above" },
			],
			"setup": [],
			"spotlight": { "kind": "none", "ref": "" },
			"done": { "wake": [], "decide": {} },
			"advance": "next",
		},
		{
			"id": "tile_basics_select", "chapter": "Your tiles",
			"title": "Buildings belong to tiles",
			"body": "In Carbon and Capital, buildings exist on tiles. That's where your stockpile is and where buildings draw inputs from, then push outputs to. Select any tile.",
			"setup": [{"action": "close_tile_panel"}],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {"kind": "node_visible", "ref": "TileInfoPanel"}},
			"advance": "auto",
		},
		{
			"id": "tile_basics_land", "chapter": "Your tiles",
			"title": "The Land Chart",
			"body": "The hexagon shows how much land is available to build on the tile. It also shows how much land you already own in the colour of your company's livery. Above the dashed line in the hexagon there is more local opposition to construction so it will get more expensive to build. Rural tiles have more space than others. Mountain tiles have the least space.",
			"setup": [], "spotlight": {"kind": "node_name", "ref": "TileLandChart"},
			"lock_panel": true, "spotlight_passthrough": false,
			"done": {"wake": [], "decide": {}}, "advance": "next",
		},
		{
			"id": "tile_basics_features", "chapter": "Your tiles",
			"title": "Inside the tile panel",
			"body": "The tile panel is where you can see and select the buildings on that tile, as well as power generation, the goods produced on this tile by YOUR BUILDINGS ONLY, the stockpile as well as the infrastructure and transport for the tile.",
			"setup": [], "spotlight": {"kind": "node_name", "ref": "TileInfoPanel"},
			"lock_panel": true, "spotlight_passthrough": false,
			"done": {"wake": [], "decide": {}}, "advance": "next",
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
	]


## After the recipe diagram: find the company's buildings, what they cost to run, a first turn, and where the
## money is.
static func _opener_business_steps() -> Array:
	var start := str(MatchState.ruleset.get("start_id", "")).strip_edges()
	if start == "":
		start = str(MatchState.scenario_name)
	var own_inputs := "the sand" if start.contains("glass") else "the coal and iron"
	return [
		{
			"id": "opener_movement", "chapter": "Your business",
			"title": "Movement",
			"body": "Navigate around the map by clicking and panning. WASD keys also allow you to move around.\n\nFind your company's buildings. They're the ones in your company's livery.",
			"setup": [{"action": "close_tile_panel"}],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {"kind": "own_buildings_shown"}},
			"advance": "auto",
		},
		{
			"id": "opener_your_buildings", "chapter": "Your business",
			"title": "Select your buildings",
			"body": "These are your buildings. A humble start but enough to get started. Select them to see more.",
			"setup": [],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {"kind": "building_detail_open"}},
			"advance": "auto",
		},
		{
			"id": "opener_costs", "chapter": "Your business",
			"title": "What your buildings cost",
			"body": "Your buildings have four cost components: inputs, maintenance, power and labour. Additionally you may take loans, manage transport and stockpiling for your goods. You can integrate inputs, transport and power to bring more in house and control your costs.",
			"setup": [],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {}}, "advance": "next",
		},
		{
			"id": OPENER_END_TURN_STEP, "chapter": "Your business",
			"title": "Your turn",
			"body": "End your turn for your buildings to run, goods to move and sales to happen.",
			"setup": [],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {"kind": "turn_advanced"}},
			"advance": "auto",
		},
		{
			"id": "opener_next_opportunity", "chapter": "Your business",
			"title": "The next opportunity",
			"body": "You made revenue by buying from and selling to local suppliers. They'll do for now but they take a big cut. In your case, you could make more money if you used %s directly in your furnaces." % own_inputs,
			"setup": [],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"done": {"wake": [], "decide": {}}, "advance": "next",
		},
		{
			"id": "opener_own_pace", "chapter": "Your business",
			"title": "Grow at your own pace",
			"body": "Now it's all up to you. The missions in the top bar will recommend you where to go next and grant some small rewards, but how you expand from here is entirely your choice. Good luck!",
			"setup": [],
			"spotlight": {"kind": "none", "ref": ""}, "no_dim": true,
			"next_label": "Finish",
			"done": {"wake": [], "decide": {}}, "advance": "next",
		},
	]
