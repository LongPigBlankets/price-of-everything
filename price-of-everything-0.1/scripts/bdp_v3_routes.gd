extends RefCounted
## Building Detail v3's Input sources and Output destination sheets in DS2 (docs/bdp-routes-ds2-plan.md),
## built into the sheet's rows while UiPrefs.use_routes_ds2 is on. With the switch off the panel builds the
## v2 sheets itself. `panel` is Building Detail (scripts/building_detail_panel_v2.gd): its sheet, its
## refresh and the logistics requests the v2 sheets make, so the two can't disagree about what a choice does.
##
## On the sheet's steel plate, under Back and the title:
##   the readout   the diagnostics' dark glass screen, fixed under the title (it never scrolls away): the
##                 option under the pointer, its name and what it does; otherwise what the sheet changes and
##                 how the market and the intermediaries pay
##   the plates    a plate of the diagnostics' black plastic a good, screwed round its edge, straight on
##                 the sheet's steel:
##                   the good in its well, its quantity a turn on its pill; its name; a lamp and what the
##                   tile holds of it (inputs) or where it goes (outputs); where it comes from or goes, in
##                   words; under Per turn, what it costs (goods and transport, or its value and transport)
##                   on LED screens, the screens one width down the sheet; at the module's right, beside the
##                   words, the knob that chooses (Source, and Fallback under it where the Logistics
##                   Intermediary works), its options icons on its arc; under them, your buildings that make
##                   or use it, each with a Go to key
##                 in intermediary games, first a plate with one knob for every good on the side at once
##   split output  where the output is split between tiles, a line a tile with its units a turn typed onto
##                 an LED screen's glass (0 shares what is left evenly)
## Turning a knob asks for the change; the knob stays where it was until the sheet is rebuilt with the
## change made, so a change refused or cancelled never leaves it pointing at something untrue.

const Parts := preload("res://scripts/ds2/sheet_parts.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Readout := preload("res://scripts/bdp_v3_readout.gd")
const Rotary := preload("res://scripts/rotary_selector.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const BoltIcon := preload("res://scripts/ds2/bolt_icon.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")
const Service := preload("res://scripts/middleman_service.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
const ICON_TILE: Texture2D = preload("res://assets/icons/ui_icons/route_stockpile.png")
const ICON_MARKET: Texture2D = preload("res://assets/icons/ui_icons/route_port.png")
const ICON_INTERMEDIARY: Texture2D = preload("res://assets/icons/ui_icons/route_lorry.png")
const ICON_OTHER_TILE: Texture2D = preload("res://assets/icons/ui_icons/ds2/source_other_tiles.png")
const SIDE_ICON := "res://assets/ui/bdp_v3/econ_icon_%s.png"

## The knobs, a little smaller than the tile view's logistics knobs (they stand beside the words); the room
## between two knobs stacked one over the other.
const KNOB_PX := 80.0
const KNOB_GAP := 6
## Between modules, between a module's rows, between its lines of words.
const MODULE_GAP := 10
const ROW_GAP := 10
const LINE_GAP := 4
const WORDS_GAP := 12
## The raised icon heading the All inputs / All outputs module, and the Go to key's size.
const SIDE_ICON_PX := 48.0
const GO_TO_SCALE := 0.8
## Between the case and the scroll rail.
const RAIL_GAP := 4.0
## A split destination's units screen.
const SPLIT_ENTRY_W := 56.0
const SPLIT_MAX := 999

## What the readout says with the pointer on no option: the sheet's name line over how its choices buy or sell.
const HINT_INPUTS := "Change the Input source for goods."
const HINT_INPUTS_DETAIL := "The market sells only what you ship in from a port but grants more control, while Local Suppliers deliver right away but take a bigger slice."
const HINT_OUTPUTS := "Change the Output destination for goods."
const HINT_OUTPUTS_DETAIL := "The market pays only if you ship it to a port but grants more control, while Local Suppliers pay right away but take a bigger slice."
## The readout's height with three lines of detail (the hint needs three at this width), and those lines.
const READOUT_H := 92.0
const READOUT_LINES := 3
const LICENCE_NOTE := "Needs the %s." % ResearchState.GLOBAL_TRADE_LICENSE_TITLE
const CONTRACTS_NOTE := "Needs %s." % ResearchState.OPEN_LOGISTICS_CONTRACTS_TITLE


# --- the sheets ---------------------------------------------------------------------------------

static func inputs(panel: Control, vb: VBoxContainer, building: Dictionary, recipe: Dictionary) -> void:
	var readout := _readout(vb, HINT_INPUTS, HINT_INPUTS_DETAIL)
	var econ: Dictionary = BuildingEconomics.per_turn(building)
	var lines := _by_good(econ.get("inputs", []))
	var digits := _digits(econ.get("inputs", []), ["value", "cost"])
	var ships := {}
	for s: Dictionary in BuildingReadout.shipments(building, recipe):
		ships[str(s.get("good_id", ""))] = s
	var producers := {}
	for s: Dictionary in BuildingReadout.input_sources(building, recipe):
		var g := str(s.get("good_id", ""))
		if not producers.has(g):
			producers[g] = []
		(producers[g] as Array).append(s)
	var c := _plates(vb, "InputPlates")
	if Service.eligible(building) and Service.recipe_side(recipe, "input"):
		c.add_child(_all_module(panel, building, recipe, "input", readout))
	for inp: Dictionary in recipe.get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		if gid == "":
			continue
		c.add_child(_input_module(panel, building, recipe, inp, lines.get(gid, {}), ships.get(gid, {}),
			producers.get(gid, []), digits, readout))


static func outputs(panel: Control, vb: VBoxContainer, building: Dictionary, recipe: Dictionary) -> void:
	var c := _plates(vb, "OutputPlates")
	if str(recipe.get("output_name", "")) == "power":
		c.add_child(_power_module(panel))
		return
	var readout := _readout(vb, HINT_OUTPUTS, HINT_OUTPUTS_DETAIL)
	var econ: Dictionary = BuildingEconomics.per_turn(building)
	var lines := _by_good(econ.get("outputs", []))
	var digits := _digits(econ.get("outputs", []), ["value", "cost"])
	if Service.eligible(building) and Service.recipe_side(recipe, "output"):
		c.add_child(_all_module(panel, building, recipe, "output", readout))
	var primary := BuildingStatus.primary_output_good_id(recipe)
	for o: Dictionary in recipe.get("outputs", []):
		var gid := str(o.get("good_id", ""))
		if gid == "" or not Service.material_tradeable(gid, "output"):
			continue
		c.add_child(_output_module(panel, building, recipe, o, lines.get(gid, {}), digits, readout, gid == primary))


# --- inputs -------------------------------------------------------------------------------------

## A good the building takes: its well, name, stock, source in words, what it costs, your buildings that
## make it, and its Source knob (and Fallback, where the intermediary works).
static func _input_module(panel: Control, building: Dictionary, recipe: Dictionary, inp: Dictionary, line: Dictionary,
		ship: Dictionary, producers: Array, digits: int, readout: Control) -> Control:
	var iid := str(building.get("instance_id", ""))
	var gid := str(inp.get("good_id", ""))
	var qty := int(line.get("qty", inp.get("qty", 0)))
	var route: Dictionary = Service.input_source_route(iid, gid)
	var service_game := Service.eligible(building)
	var module := _module(panel, "Input_%s" % gid)
	var col: VBoxContainer = module.get("content")
	var words := _top_row(col, Parts.good_in_well(gid, Metrics.GOOD_ICON, qty, true), Catalog.get_display_name(gid))
	var stored := int(ship.get("stored", 0))
	var inbound := int(ship.get("inbound", 0))
	var tone: String = panel.call("v3_stock_tone", stored, qty, inbound, Service.supplies_good(iid, gid))
	words.add_child(_lamp_line(tone, _stock_words(stored, inbound, int(ship.get("eta_turns", -1))), "StockLine"))
	words.add_child(_words(_input_source_words(building, route, service_game), "SourceWords"))
	if Service.in_handover(iid, gid):
		var turns: int = Service.handover_turns(iid, gid)
		words.add_child(_lamp_line("warn", "Switching suppliers. The first market delivery is %s." % _in_turns(turns), "SupplierHandover"))
	var is_cost := func(v: float) -> Color: return DS.PALETTE.DANGER if v > 0.0 else DS.PALETTE.TEXT
	words.add_child(_per_turn_caption())
	words.add_child(_money_line("Goods", float(line.get("value", 0.0)), is_cost.call(float(line.get("value", 0.0))), digits))
	words.add_child(_money_line("Transport", float(line.get("cost", 0.0)), is_cost.call(float(line.get("cost", 0.0))), digits))
	for p: Dictionary in producers:
		col.add_child(_building_line(panel, "Made by your %s" % str(p.get("building_name", "")), str(p.get("instance_id", ""))))
	var knobs := _knob_column(words)
	var market_available := _market_available()
	knobs.add_child(_input_knob(panel, building, recipe, gid, route, "primary", market_available, readout))
	if service_game and str(route.get("primary", "")) != "middleman":
		knobs.add_child(_input_knob(panel, building, recipe, gid, route, "fallback", market_available, readout))
	elif service_game:
		words.add_child(_words("No fallback needed. Local Suppliers buy all of it.", "FallbackNotNeeded"))
	return module


## The input's Source (or Fallback) knob: this tile's stockpile, the global market, and the intermediary
## where it works. Without the intermediary, the market means the tile's stock first and the market for the
## rest; the stockpile means the tile's stock only. A fallback can't be the primary's own source.
static func _input_knob(panel: Control, building: Dictionary, recipe: Dictionary, gid: String, route: Dictionary,
		slot: String, market_available: bool, readout: Control) -> Control:
	var iid := str(building.get("instance_id", ""))
	var service_game := Service.eligible(building)
	var fallback := slot == "fallback"
	var primary := str(route.get("primary", ""))
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	var choices: Array = [
		{"id": "stockpile", "icon": ICON_TILE, "name": "Tile stockpile", "enabled": stockpile_available,
			"detail": (("Uses what is in this tile's stockpile." if service_game else "Uses only what is in this tile's stockpile. Nothing is bought.")
				if stockpile_available else CONTRACTS_NOTE)},
		{"id": "market", "icon": ICON_MARKET, "name": "Global market", "enabled": market_available,
			"detail": (("Buys any shortfall at market through the nearest port." if fallback else
				("Buys it at market through the nearest port." if service_game else
				"Uses this tile's stockpile first and buys the rest at market through the nearest port."))
				if market_available else LICENCE_NOTE)},
	]
	if service_game:
		var tradeable := Service.material_tradeable(gid, "input")
		choices.append({"id": "middleman", "icon": ICON_INTERMEDIARY, "name": "Local Suppliers", "enabled": tradeable,
			"detail": (("Buys only what this tile's stock does not cover. Its fee applies to those units." if fallback
				else "Buys this input for the building each turn. Transport and storage are in its fee.")
				if tradeable else "Local Suppliers do not trade this good.")})
	if fallback:
		for ch: Dictionary in choices:
			var same := str(ch.id) == primary or (str(ch.id) == "stockpile" and primary.begins_with("tile:"))
			if same:
				ch.enabled = false
				ch.detail = "The primary source already. A fallback must differ."
	var selected := str(route.get(slot, ""))
	if not service_game and not fallback and str(route.get("fallback", "")) == "market":
		selected = "market"
	var current := 0
	for i in choices.size():
		var id := str(choices[i].id)
		if id == selected or (id == "stockpile" and selected.begins_with("tile:")):
			current = i
	var name := Catalog.get_display_name(gid)
	return _knob("%sKnob_%s" % [slot.capitalize(), gid], "FALLBACK" if fallback else "SOURCE", choices, current, readout,
		"%s %s" % [name, "fallback" if fallback else "source"], func(source: String) -> void:
			var result: Dictionary = Service.set_input_route(iid, gid, slot, source)
			if bool(result.get("ok", false)) and not service_game and slot == "primary" and source == "stockpile":
				result = Service.set_input_route(iid, gid, "fallback", "")
			if not bool(result.get("ok", false)):
				MatchState.request_toast(str(result.get("reason", "Unable to change input source.")), "warning")
			panel.call("_queue_refresh")
			panel.call("_open_input_sources_sheet", building, recipe))


## Where an input comes from, in words: its source, then who covers a shortfall.
static func _input_source_words(building: Dictionary, route: Dictionary, service_game: bool) -> String:
	var primary := str(route.get("primary", ""))
	var fallback := str(route.get("fallback", ""))
	if primary == "middleman":
		return "Local Suppliers supply it."
	if not service_game:
		if primary == "market" or fallback == "market":
			return "From this tile's stockpile first. The rest is bought at market through %s." % _port_words(building)
		if primary.begins_with("tile:"):
			return "From the stockpile at %s." % _tile(primary.trim_prefix("tile:"))
		return "From this tile's stockpile only. Nothing is bought."
	var said := "From %s." % _source_words(building, primary)
	if fallback != "" and fallback != primary:
		said += " Any shortfall from %s." % _source_words(building, fallback)
	return said


static func _source_words(building: Dictionary, source: String) -> String:
	match source:
		"stockpile": return "this tile's stockpile"
		"market": return "the market through %s" % _port_words(building)
		"middleman": return "Local Suppliers"
	if source.begins_with("tile:"):
		return "the stockpile at %s" % _tile(source.trim_prefix("tile:"))
	return source


static func _stock_words(stored: int, inbound: int, eta: int) -> String:
	var said := "%d on the tile." % stored
	if inbound > 0:
		said += " %d arriving %s." % [inbound, "next turn" if eta <= 1 else "in %d turns" % eta]
	return said


# --- outputs ------------------------------------------------------------------------------------

## A good the building makes: its well, name, where it goes (a lamp and words), its value and transport,
## the split between tiles and your buildings that use it (the main output only), and its Destination knob.
static func _output_module(panel: Control, building: Dictionary, recipe: Dictionary, o: Dictionary, line: Dictionary,
		digits: int, readout: Control, primary: bool) -> Control:
	var iid := str(building.get("instance_id", ""))
	var tile := str(building.get("tile_id", ""))
	var gid := str(o.get("good_id", ""))
	var qty := int(line.get("qty", o.get("qty", 0)))
	var state := _output_state(building, gid)
	var module := _module(panel, "Output_%s" % gid)
	var col: VBoxContainer = module.get("content")
	var words := _top_row(col, Parts.good_in_well(gid, Metrics.GOOD_ICON, qty, true), Catalog.get_display_name(gid))
	var split := MatchState.get_output_split_destinations(iid, gid)
	var splitting := primary and split.size() >= 2 and not Service.uses_outputs(iid)
	var dest := _output_destination_words(building, recipe, gid, state, split.size() if splitting else 0)
	words.add_child(_lamp_line(str(dest.tone), str(dest.text), "DestinationLine"))
	words.add_child(_per_turn_caption())
	words.add_child(_money_line("Value", float(line.get("value", 0.0)), DS.PALETTE.OK if float(line.get("value", 0.0)) > 0.0 else DS.PALETTE.TEXT, digits))
	words.add_child(_money_line("Transport", float(line.get("cost", 0.0)), DS.PALETTE.DANGER if float(line.get("cost", 0.0)) > 0.0 else DS.PALETTE.TEXT, digits))
	if splitting:
		col.add_child(_split_rows(recipe, iid, gid, split))
	if primary:
		for c: Dictionary in BuildingReadout.output_consumers(building, recipe):
			col.add_child(_building_line(panel, "Used by your %s" % str(c.get("name", "")), str(c.get("instance_id", ""))))
	var knobs := _knob_column(words)
	knobs.add_child(_output_knob(panel, building, recipe, gid, tile, state, readout))
	return module


## Where an output goes now: the intermediary, the market, this tile's stockpile, or other tiles.
static func _output_state(building: Dictionary, gid: String) -> String:
	var iid := str(building.get("instance_id", ""))
	var tile := str(building.get("tile_id", ""))
	if Service.buys_output(iid, gid):
		return "middleman"
	var cur_dest := MatchState.get_output_stockpile_destination(iid, gid)
	if MatchState.is_output_market(iid, gid):
		return "market"
	if MatchState.get_output_split_destinations(iid, gid).size() >= 2 or (cur_dest != "" and cur_dest != tile):
		return "other"
	if cur_dest != "" and cur_dest == tile:
		return "stockpile"
	return "stockpile" if MatchState.sell_mode == MatchState.SellMode.STOCKPILE_ALL else "market"


## The destination line: {tone, text}. Red where the goods can't reach where they are sent.
static func _output_destination_words(building: Dictionary, recipe: Dictionary, gid: String, state: String, split_tiles: int) -> Dictionary:
	var route := BuildingReadout.output_route(building, recipe, gid)
	var reachable := bool(route.get("reachable", true))
	var turns := int(route.get("turns", 0))
	var target := str(route.get("target", ""))
	match state:
		"middleman":
			return {"tone": "ok", "text": "Local Suppliers buy it."}
		"market":
			if not reachable:
				return {"tone": "bad", "text": "No route to the port. It can't be sold."}
			var to := "a special order" if str(route.get("destination", "")).begins_with("Special Order") else "market"
			var said := "Sold at %s through %s." % [to, Parts.tile_words(target, "the nearest port")]
			if turns > 0:
				said += " %s to the port." % _turns_words(turns)
			return {"tone": "ok", "text": said}
		"other":
			if split_tiles >= 2:
				return {"tone": "ok", "text": "Split between %d tiles." % split_tiles}
			if not reachable:
				return {"tone": "bad", "text": "No route to %s. It can't be shipped." % _tile(target)}
			return {"tone": "ok", "text": "Shipped to %s, %s away." % [_tile(target), _turns_words(turns)]}
	return {"tone": "ok", "text": "Kept in this tile's stockpile."}


## The output's Destination knob: the intermediary where it works, the global market, this tile's stockpile,
## or another tile (picked on the shipping map). Leaving the intermediary asks first, as the v2 sheet did.
static func _output_knob(panel: Control, building: Dictionary, recipe: Dictionary, gid: String, tile: String, state: String,
		readout: Control) -> Control:
	var iid := str(building.get("instance_id", ""))
	var market_available := _market_available()
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	var choices: Array = []
	if Service.eligible(building):
		choices.append({"id": "middleman", "icon": ICON_INTERMEDIARY, "name": "Local Suppliers",
			"detail": "Sells this output privately. Transport and storage are included."})
	choices.append({"id": "market", "icon": ICON_MARKET, "name": "Global market", "enabled": market_available,
		"detail": "Sells it at market price through the nearest port." if market_available else LICENCE_NOTE})
	choices.append({"id": "stockpile", "icon": ICON_TILE, "name": "Tile stockpile", "enabled": stockpile_available,
		"detail": "Keeps it in this tile's stockpile for later use." if stockpile_available else CONTRACTS_NOTE})
	choices.append({"id": "other", "icon": ICON_OTHER_TILE, "name": "Ship to another tile", "enabled": stockpile_available,
		"detail": "Pick a tile on the shipping map to feed a building you own there." if stockpile_available else CONTRACTS_NOTE})
	var current := 0
	for i in choices.size():
		if str(choices[i].id) == state:
			current = i
	var reopen := func() -> void:
		panel.call("_queue_refresh")
		panel.call("_open_output_sheet", building, recipe)
	var knob := _knob("DestinationKnob_%s" % gid, "DESTINATION", choices, current, readout,
		"%s destination" % Catalog.get_display_name(gid), func(choice: String) -> void:
			var go := func() -> void:
				if choice == "market":
					MatchState.route_output_to_market(iid, gid)
					reopen.call()
				elif choice == "stockpile":
					MatchState.set_output_stockpile_destination(iid, tile, gid)
					reopen.call()
					preload("res://scripts/stockpile_route_prompt.gd").offer(panel.get_parent(), tile, gid)
				elif choice == "other":
					MatchState.begin_output_stockpile_selection(iid, gid, true)
					panel.call("_close_sheet")
			if choice == "middleman":
				var result := Service.set_good_mode(iid, "output", gid, "middleman")
				if not bool(result.get("ok", false)):
					MatchState.request_toast(str(result.get("reason", "Unable to change output destination.")), "warning")
				reopen.call()
			elif state == "middleman":
				panel.call("_request_logistics_mode", building, "output", "managed", go, gid, choice)
			else:
				go.call())
	return knob


## A line a tile the output is split between: its name, its units a turn on an LED screen's glass (0 shares
## what the fixed ones leave evenly, the share printed beside it).
static func _split_rows(recipe: Dictionary, iid: String, gid: String, split: Array) -> Control:
	var box := VBoxContainer.new()
	box.name = "SplitRows"
	box.add_theme_constant_override("separation", LINE_GAP)
	var head := HBoxContainer.new()
	head.add_child(Parts.metal("Split output"))
	head.add_child(Parts.spacer())
	head.add_child(Parts.metal("Units/turn", HORIZONTAL_ALIGNMENT_RIGHT))
	box.add_child(head)
	var produced := BuildingStatus.primary_output_qty(recipe)
	var auto_count := 0
	var fixed := 0
	for d: Dictionary in split:
		var q := int(d.get("qty", 0))
		if q > 0:
			fixed += mini(q, produced)
		else:
			auto_count += 1
	var share := ceili(float(maxi(0, produced - fixed)) / float(maxi(1, auto_count)))
	for d: Dictionary in split:
		var dest := str(d.get("tile_id", ""))
		var q := int(d.get("qty", 0))
		var row := HBoxContainer.new()
		row.name = "Split_%s" % dest
		row.add_theme_constant_override("separation", 8)
		var name := Parts.body(_tile(dest))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.tooltip_text = Parts.coords(dest)
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name)
		if q <= 0:
			row.add_child(Parts.metal("Even share %d" % share, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(Parts.entry(q, 0, SPLIT_MAX, SPLIT_ENTRY_W, func(v: int) -> void:
			MatchState.set_output_split_quantity(iid, gid, dest, v)))
		box.add_child(row)
	return box


## Power leaves by cable: nothing to choose here, one module saying where it goes.
static func _power_module(panel: Control) -> Control:
	var module := _module(panel, "Output_power")
	var col: VBoxContainer = module.get("content")
	var words := _top_row(col, BoltIcon.new(Metrics.GOOD_ICON), "Electricity")
	words.add_child(_words("It goes to your power network and the national grid. It is never stored or traded through Local Suppliers.", "PowerWords"))
	words.add_child(_words("Your power priority settings decide what is used here and what is sold.", "PowerPriority"))
	return module


# --- every good at once -------------------------------------------------------------------------

## In intermediary games, one knob for every good on the side: each good its own source, the intermediary,
## the global market or this tile's stockpile. The v2 sheet's All inputs / All outputs row, as a knob.
static func _all_module(panel: Control, building: Dictionary, recipe: Dictionary, side: String, readout: Control) -> Control:
	var iid := str(building.get("instance_id", ""))
	var inputs := side == "input"
	var module := _module(panel, "AllInputs" if inputs else "AllOutputs")
	var col: VBoxContainer = module.get("content")
	var icon := Parts.raised_icon(SIDE_ICON % ("inputs" if inputs else "outputs"), SIDE_ICON_PX)
	icon.custom_minimum_size = Vector2(Metrics.GOOD_ICON, SIDE_ICON_PX)
	var words := _top_row(col, icon, "All inputs" if inputs else "All outputs")
	var market_available := _market_available()
	var stockpile_available := ResearchState.open_logistics_contracts_available()
	var goods := "input" if inputs else "output"
	var choices: Array = [
		{"id": "each", "icon": _cream(BuildingIcon.clean_texture("b_007", "industrial_factory")), "name": "Each good its own",
			"enabled": Service.route_lock("managed") == "" or not Service.side_all_middleman(iid, side),
			"detail": ("Each %s keeps the route set on its own knob below." % goods) if Service.route_lock("managed") == "" else Service.route_lock("managed")},
		{"id": "middleman", "icon": ICON_INTERMEDIARY, "name": "Local Suppliers",
			"detail": "Buys every input privately for this building." if inputs else "Buys all of this building's production. Transport and storage are included."},
		{"id": "market", "icon": ICON_MARKET, "name": "Global market", "enabled": market_available,
			"detail": ("All %ss go to the global market via a port." % goods) if market_available else LICENCE_NOTE},
		{"id": "tile", "icon": ICON_TILE, "name": "Tile stockpile", "enabled": stockpile_available,
			"detail": ("Every %s uses this tile's stockpile." % goods) if stockpile_available else CONTRACTS_NOTE},
	]
	var current := 0
	if Service.side_all_middleman(iid, side):
		current = 1
	elif bool(panel.call("_all_managed_source", building, side, "market")):
		current = 2
	elif bool(panel.call("_all_managed_source", building, side, "tile")):
		current = 3
	var now := ["Each %s keeps its own route." % goods, "Local Suppliers handle every %s." % goods,
		"All %ss go to the global market via a port." % goods, "Every %s uses this tile's stockpile." % goods]
	words.add_child(_words(str(now[current]), "AllWords"))
	var knobs := _knob_column(words)
	knobs.add_child(_knob("All%sKnob" % ("Inputs" if inputs else "Outputs"), "ALL INPUTS" if inputs else "ALL OUTPUTS", choices,
		current, readout, "All %ss" % goods, func(choice: String) -> void:
			if choice == "middleman":
				panel.call("_request_logistics_mode", building, side, "middleman")
			elif choice == "market" or choice == "tile":
				panel.call("_request_all_managed_source", building, side, choice)
			elif Service.side_all_middleman(iid, side):
				panel.call("_request_logistics_mode", building, side, "managed")))
	return module


# --- parts --------------------------------------------------------------------------------------

## The readout, fixed under the sheet's title (between it and the rows' scroll), so it stays in sight.
static func _readout(vb: VBoxContainer, hint: String, detail: String) -> Control:
	var readout: Control = Readout.new()
	readout.name = "RoutesReadout"
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.custom_minimum_size.y = READOUT_H
	(readout.find_child("ReadoutDetail", true, false) as Label).max_lines_visible = READOUT_LINES
	readout.set_meta("hint", [hint, detail])
	var scroll := vb.get_parent()
	var host := scroll.get_parent() if scroll != null else null
	if host != null:
		host.add_child(readout)
		host.move_child(readout, scroll.get_index())
	else:
		vb.add_child(readout)
	_hint(readout)
	return readout


static func _hint(readout: Control) -> void:
	var hint: Array = readout.get_meta("hint", ["", ""])
	readout.call("show_check", "", str(hint[0]), str(hint[1]), "")


## The column the goods' plates stand in, straight on the sheet's steel, in a margin that keeps the scroll
## rail's room at its right whether the rail shows or not, so nothing reflows when a sheet grows long enough
## to scroll.
static func _plates(vb: VBoxContainer, node_name: String) -> VBoxContainer:
	var plates := VBoxContainer.new()
	plates.name = node_name
	plates.add_theme_constant_override("separation", MODULE_GAP)
	var room := MarginContainer.new()
	room.name = "RailRoom"
	var rail := 0.0
	var scroll := vb.get_parent() as ScrollContainer
	if scroll != null:
		rail = scroll.get_v_scroll_bar().get_combined_minimum_size().x + RAIL_GAP
	for side in ["margin_left", "margin_top", "margin_bottom"]:
		room.add_theme_constant_override(side, 0)
	room.add_theme_constant_override("margin_right", roundi(rail))
	room.add_child(plates)
	vb.add_child(room)
	return plates


## A good's own plate: the diagnostics' black plastic, screwed round its edge, straight on the sheet's steel.
## Its rows go in its `content` column.
static func _module(_panel: Control, node_name: String) -> Control:
	var plate: MarginContainer = Section.new()
	plate.name = node_name
	plate.set("style", "plastic")
	var col: VBoxContainer = plate.get("content")
	col.add_theme_constant_override("separation", ROW_GAP)
	return plate


## The module's top row: its icon, and beside it the name over the words column, which it returns.
static func _top_row(col: VBoxContainer, icon: Control, title: String) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", WORDS_GAP)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.name = "Words"
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", LINE_GAP)
	var name := Parts.body(title, true)
	name.name = "GoodName"
	words.add_child(name)
	row.add_child(words)
	col.add_child(row)
	return words


## The column of knobs at the right of a module's top row, beside its words: one knob, or Source over
## Fallback.
static func _knob_column(words: VBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Knobs"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", KNOB_GAP)
	words.get_parent().add_child(column)
	return column


## A knob of `choices` ({id, icon, name, detail, enabled}), set to `current`. Its option buttons are named
## RouteOption_<Name> (as the v2 sheet's cards were, for tutorial spotlights and harnesses); pointing at one
## shows its name and what it does on the readout. Turning it calls `apply` with the option's id and leaves the
## knob where it was: the sheet is rebuilt with the change made.
static func _knob(node_name: String, label: String, choices: Array, current: int, readout: Control, stage: String,
		apply: Callable) -> Control:
	var knob: Control = Rotary.new()
	knob.name = node_name
	knob.set("knob_size", KNOB_PX)
	knob.set("label", label)
	knob.set("label_colour", DS.PALETTE.TEXT)
	knob.call("set_options", choices)
	knob.call("set_value_no_signal", current + 1)
	knob.size_flags_vertical = Control.SIZE_SHRINK_END
	var buttons: Array = knob.get("option_buttons")
	for i in buttons.size():
		var b := buttons[i] as Button
		var ch: Dictionary = choices[i]
		b.name = ("RouteOption_" + str(ch.name).to_pascal_case()).validate_node_name()
		b.mouse_entered.connect(func() -> void:
			readout.call("show_check", stage, str(ch.name), str(ch.get("detail", "")), ""))
		b.mouse_exited.connect(func() -> void: _hint(readout))
	knob.connect("value_changed", func(v: int) -> void:
		knob.call("set_value_no_signal", current + 1)
		if v - 1 != current:
			apply.call(str(choices[v - 1].id)))
	return knob


static func _lamp_line(tone: String, text: String, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 8)
	var lamp := Parts.lamp(tone)
	lamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(lamp)
	var l := Parts.para(text)
	l.custom_minimum_size.x = 0
	row.add_child(l)
	return row


static func _words(text: String, node_name: String) -> Label:
	var l := Parts.para(text)
	l.name = node_name
	l.custom_minimum_size.x = 0
	return l


## The heading over a module's figures: they are a turn's, so the lines under it carry no "/turn".
static func _per_turn_caption() -> Label:
	var l := Parts.metal("Per turn")
	l.name = "PerTurn"
	return l


## A figure a turn: its name in metal capitals, and at the column's right the printed £ and its LED screen, the
## screens one width, so the £ signs line up down the sheet.
static func _money_line(label: String, figure: float, colour: Color, digits: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label.to_pascal_case() + "PerTurn"
	row.add_theme_constant_override("separation", 4)
	row.add_child(Parts.metal(label))
	row.add_child(Parts.spacer())
	row.add_child(Parts.money(figure, colour, digits))
	return row


## One of your buildings that makes or uses the good, and a key that takes you to it.
static func _building_line(panel: Control, text: String, target_iid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "BuildingLine"
	row.add_theme_constant_override("separation", 8)
	var l := Parts.para(text)
	l.custom_minimum_size.x = 0
	row.add_child(l)
	if target_iid != "":
		var key: Button = CreamKey.make("GoTo", "Go to", "", CreamKey.width_for("Go to", "", false, false, GO_TO_SCALE),
			false, false, GO_TO_SCALE)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.pressed.connect(func() -> void:
			panel.call("_close_sheet")
			MatchState.focus_building_requested.emit(target_iid))
		row.add_child(key)
	return row


static func _by_good(lines: Array) -> Dictionary:
	var out := {}
	for l: Dictionary in lines:
		out[str(l.get("good_id", ""))] = l
	return out


## The most LED cells any of the sheet's figures needs, so every screen is one width.
static func _digits(lines: Array, keys: Array) -> int:
	var most := 0
	for l: Dictionary in lines:
		for k: String in keys:
			most = maxi(most, Led.cells_for("%.2f" % float(l.get(k, 0.0))).size())
	return most


static func _market_available() -> bool:
	return Service.global_market_open()


static func _port_words(building: Dictionary) -> String:
	return Parts.tile_words(TransportService.nearest_port_tile(str(building.get("tile_id", ""))), "the nearest port")


## A tile by its name; one with no name by its label.
static func _tile(tile_id: String) -> String:
	return Parts.tile_words(tile_id, Catalog.tile_label(tile_id))


static func _turns_words(n: int) -> String:
	return "%d turn%s" % [n, "" if n == 1 else "s"]


static func _in_turns(n: int) -> String:
	return "next turn" if n <= 1 else "in %d turns" % n


## A building icon's art in the good tiles' cream, for a knob's option (the tile view's Per building option).
static var _cream_cache := {}
static func _cream(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key := texture.get_rid()
	if _cream_cache.has(key):
		return _cream_cache[key]
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var cream := Color(0.995, 0.931, 0.763)
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a
			if a > 0.0:
				image.set_pixel(x, y, Color(cream, a))
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_cream_cache[key] = tex
	return tex
