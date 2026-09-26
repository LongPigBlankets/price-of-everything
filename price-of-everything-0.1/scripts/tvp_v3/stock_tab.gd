extends RefCounted
## Tile view v3: the Stock tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The yard, top to bottom, each part in Building Detail v3's kit:
##   Warehouse (a dark plate in a steel frame). Its capacity line: what is stored on an LED screen against
##     the one capacity (amber when nearly full, red when full, as the fill), and Expand beside it saying
##     what the tile will hold. Under it, the fill as a level bar on the screens' glass (stock_gauge.gd): a
##     slice a good, the biggest tagged with their icons, each on a short line to its slice or, when they
##     had to spread to fit, together on a shelf whose legs stand on the stretch of fill they name; a
##     dashed mark with PEAK lit beside it when last turn's peak stood above today's level; and under it
##     the scale of what the capacity is made of ("800 warehouse L1", "+600 port"). A tag or a slice picks
##     its good as the bay does. Under the bar, in one text column, each a raised icon and a lamp: last
##     turn's peak (or, when it ran out of room, that line and the way out), the shipments waiting to
##     unload under it, when it will be full, where the surplus goes, and goods that went building to
##     building. Beside the bar and its lines, the surplus knob exactly as built, the warehouse's outlet.
##   Stored goods (a dark plate): Building Detail's shipments bay, four to a row, most first, each good in
##     its well with its quantity pill inside and its name under it, under the rolled up door; the door is
##     down over an empty bay. Picking a good opens the Move or sell sheet; pointing at one lights its
##     slice and its tag in the warehouse's bar. More than eight: a wide key opens the rest.
##   Logistics (the diagnostics' black plastic), in intermediary games only: a knob for the inputs and one
##     for the outputs of every building here, and a readout for the option under the pointer.
## Warehouse expansion and Move or sell are sheets that slide in over the body (stock_sheets.gd). The
## controls show only where you own land or have goods (TileInfoPanel.player_present_on_tile); elsewhere
## the warehouse is a shut door, one bay row high, under a heading that says what it would hold.
##
## Lamps and their words come from one rule each: the fill and last turn's peak from the stockpile
## summary's thresholds (fill_tone), the forecast from the transport panel's (eta).

const Parts := preload("res://scripts/tvp_v3/stock_parts.gd")
const Sheets := preload("res://scripts/tvp_v3/stock_sheets.gd")
const Gauge := preload("res://scripts/tvp_v3/stock_gauge.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Door := preload("res://scripts/bdp_v3_door.gd")
const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Readout := preload("res://scripts/bdp_v3_readout.gd")
const CabinetKey := preload("res://scripts/tile_cabinet_key.gd")
const RotarySelector := preload("res://scripts/rotary_selector.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")
const MiddlemanService := preload("res://scripts/middleman_service.gd")
const ROUTE_STOCKPILE_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_stockpile.png")
const ROUTE_MARKET_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_port.png")
const ROUTE_MIDDLEMAN_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_lorry.png")

## The bay: goods to a row, the rows shown before the wide key opens the rest, a good's icon, its name's
## line and the gap between rows and cells.
const BAY_COLS := 4
const BAY_ROWS := 2
const CELL_ICON := 64
const NAME_H := 20.0
const CELL_GAP := 10
const CELL_H := CELL_ICON + 4.0 + NAME_H
## The raised icons beside the warehouse's lines (Building Detail's diagnostics icons), sized by their art,
## and the one by a good in the bay that leaves every turn.
const ROW_ICON_PX := 24.0
const EVERY_TURN_PX := 20.0
## A waiting shipment's good, in a well a line high.
const SHIPMENT_ICON_PX := 28
const NBSP := "\u00a0"
const ICON_PATH := "res://assets/ui/bdp_v3/diag_icon_%s.png"
## The room between the tab's sections, between the warehouse's readings and its knob, between an icon,
## its lamp and its words, and between one line and the next.
const SECTION_GAP := 14
const KNOB_GAP := 14
const ROW_SEP := 8
const LINE_GAP := 4
## Every line keeps one row's height (the surplus line whatever the pointer shows in it).
const SURPLUS_LINE_H := 28.0
## The turns the fill's trend is taken over (Stockpile.turns_until_full's own default, and the transport
## panel's TREND_TURNS).
const TREND_TURNS := 3
## The stockpile summary's amber threshold (TileViewData.stockpile_summary), for figures it doesn't judge.
const FILL_WARN := 0.9
## The transport panel's rule for the same forecast: red at this many turns or fewer, amber beyond, and a
## change smaller than this share of the capacity (at least one unit) reads as steady.
const ETA_RED_TURNS := 3
const TREND_DEAD_BAND := 0.01
## Under a red line about room: what makes room, each beside it (the bay below, the knob, Expand above).
const WAY_OUT := "Sell, move or expand to make room"
## The logistics knobs are a little smaller than the surplus knob.
const LOGISTICS_KNOB := 100.0
## Where the surplus goes, by route: the raised icon, and the line under the bar.
const SURPLUS_LINES := {
	"none": ["warehouse", "Surplus stays in this stockpile"],
	"middleman": ["freight", "Surplus goes to the intermediary each turn"],
	"market": ["port", "Surplus is sold at the port each turn"],
}
## What each logistics setting does for every building on the tile, by side.
const LOGISTICS_ROUTES := {
	"input": {
		"managed": ["Per building", "Each building keeps its own input routes."],
		"middleman": ["Intermediary", "The Logistics Intermediary supplies every building's inputs."],
		"market": ["Global market", "Every building buys its inputs on the market, the intermediary as fallback."],
		"stockpile": ["Tile stockpile", "Every building draws its inputs from this tile's stockpile, the intermediary as fallback."],
	},
	"output": {
		"managed": ["Per building", "Each building keeps its own output routes."],
		"middleman": ["Intermediary", "The Logistics Intermediary buys every building's outputs."],
		"market": ["Global market", "Every building sells its outputs through the nearest port."],
		"stockpile": ["Tile stockpile", "Every building stores its outputs in this tile's stockpile."],
	},
}


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile := str(panel.get("_current_tile_id"))
	pane.add_theme_constant_override("separation", SECTION_GAP)
	if tile == "":
		return
	var present := bool(panel.call("player_present_on_tile", tile))
	# Another tile starts at the top of the body.
	if str(panel.get_meta("tvp_stock_tile", "")) != tile:
		panel.set_meta("tvp_stock_tile", tile)
		var scroll := panel.get("_body_scroll") as ScrollContainer
		if scroll != null:
			scroll.set_deferred("scroll_vertical", 0)
	# A sheet over the body: Move or sell for a picked good, or the warehouse's expansion.
	if not (panel.get("_stock_sel") as Dictionary).is_empty() and Sheets.move_or_sell(panel, pane, tile):
		return
	var quote: Dictionary = MatchState.warehouse_upgrade_quote(tile)
	if bool(panel.get("_warehouse_expand")):
		if present and not bool(quote.get("maxed", false)):
			Sheets.expand(panel, pane, tile)
			return
		panel.set("_warehouse_expand", false)
	panel.set_meta("tvp_stock_sheet", "")
	var stock := TileViewData.stockpile_summary(tile)
	# Nothing can be stored where you have neither land nor goods: the warehouse says what it would hold.
	if not present:
		pane.add_child(_idle(tile, stock))
		return
	var gauge: Control = Gauge.new()
	pane.add_child(_warehouse(panel, tile, stock, quote, gauge))
	pane.add_child(_bay(panel, tile, stock, gauge))
	var logistics: Dictionary = MiddlemanService.tile_sides(tile)
	if _has_logistics(logistics):
		pane.add_child(_logistics(panel, logistics))


static func _refresh(panel: Control) -> void:
	panel.call_deferred("_refresh_pane", "stock")


# --- Warehouse ----------------------------------------------------------------------------------------

static func _warehouse(panel: Control, tile: String, stock: Dictionary, quote: Dictionary, gauge: Control) -> Control:
	var sec: Control = Section.new()
	sec.name = "WarehouseSection"
	sec.style = "dark"
	var c: VBoxContainer = sec.content
	c.add_theme_constant_override("separation", 10)
	var used := int(stock.used)
	var cap := int(stock.capacity)
	var tone := _summary_tone(stock)
	var parts := _capacity_parts(tile, cap)

	# The capacity line: what is stored against the one capacity, and Expand beside it saying what it buys.
	var head := HBoxContainer.new()
	head.name = "WarehouseHead"
	head.add_theme_constant_override("separation", 8)
	head.add_child(Parts.heading("Warehouse"))
	head.add_child(Parts.spacer())
	var stored := Parts.led(str(used), tone_colour(tone), str(cap).length())
	stored.name = "StoredLed"
	stored.tooltip_text = "Stored on this tile now"
	stored.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(stored)
	var of := Parts.metal("of %d" % cap)
	of.name = "CapacityLabel"
	var tips := PackedStringArray()
	for p: Dictionary in parts:
		tips.append(str(p.tip).to_lower())
	of.tooltip_text = "This tile holds %d: %s" % [cap, ", ".join(tips)]
	of.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(of)
	if bool(quote.get("maxed", false)):
		# Expand's key stays in its place, greyed, saying why there is nothing to press.
		var done: Control = CabinetKey.new()
		done.name = "WarehouseMaxed"
		done.text = "Fully expanded"
		done.disabled = true
		done.custom_minimum_size.x = 150.0
		done.size_flags_horizontal = Control.SIZE_SHRINK_END
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		done.tooltip_text = "The warehouse is at level %d, its highest" % int(quote.get("level", 1))
		head.add_child(done)
	else:
		head.add_child(_expand_key(panel, cap, quote, parts))
	c.add_child(head)

	# On the left the fill (a slice a good, the biggest tagged, over what the capacity is made of) and its
	# readings under it in one text column; on the right the surplus knob, the warehouse's outlet.
	var body := HBoxContainer.new()
	body.name = "WarehouseBody"
	body.add_theme_constant_override("separation", KNOB_GAP)
	var left := VBoxContainer.new()
	left.name = "WarehouseFill"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	gauge.set_fill(stock.goods, used, cap, Stockpile.get_peak_used(tile), parts, tone)
	gauge.connect("picked", func(gid: String) -> void: panel.call_deferred("select_stock_good", gid))
	left.add_child(gauge)
	var lines := VBoxContainer.new()
	lines.name = "WarehouseReadings"
	lines.add_theme_constant_override("separation", LINE_GAP)
	left.add_child(lines)
	lines.add_child(_fill_line(tile, stock))
	# Shipments that reached the tile but can't unload, straight under the fill's line they follow from.
	_backlog(lines, tile, stock)
	var ahead := eta(tile, stock)
	if not ahead.is_empty():
		# About to fill, it says the way out under it, as the full line does (once: not under both).
		var way := WAY_OUT if str(ahead.tone) == "bad" and lines.find_child("FullRow", false, false) == null else ""
		var trend := _row("transit", str(ahead.tone), str(ahead.text), false, way)
		trend.name = "TrendRow"
		trend.tooltip_text = str(ahead.tip)
		lines.add_child(trend)
	var knob_box: Control = panel.call("_make_surplus_knob")
	knob_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.add_child(_surplus_row(tile, knob_box))
	var jit := Production.get_jit_fed_for_tile(tile)
	if jit > 0:
		var fed := _row("route", "ok", "%d units went straight from building to building this turn, using no storage" % jit)
		fed.name = "JitRow"
		lines.add_child(fed)
	body.add_child(knob_box)
	c.add_child(body)
	return sec


## Shipments that reached the tile but can't unload until there is room: one line for them all, then each
## shipment in the lines' text column.
static func _backlog(lines: VBoxContainer, tile: String, stock: Dictionary) -> void:
	var overflow := TransportState.get_overflow_shipments_for_tile(tile)
	if overflow.is_empty():
		return
	var units := 0
	for r: Dictionary in overflow:
		units += int(r.get("qty", 0))
	var said := ("%d units waiting to unload" % units) if overflow.size() == 1 \
		else ("%d units in %d shipments waiting to unload" % [units, overflow.size()])
	var waiting := _row("source", "bad" if bool(stock.is_full) else "warn", said)
	waiting.name = "OverflowHead"
	waiting.tooltip_text = "Shipments that reached this tile but wait to unload until there is room"
	lines.add_child(waiting)
	for r: Dictionary in overflow:
		lines.add_child(_overflow_row(r))


## Expand, on the capacity line, saying what the tile will hold once the warehouse is a level up. With a
## capacity modifier in play the new total isn't simply the sum, so it says what the level adds instead.
static func _expand_key(panel: Control, cap: int, quote: Dictionary, parts: Array) -> Control:
	var now_level := int(quote.get("current_cap", 0))
	var next_level := int(quote.get("next_cap", 0))
	var gain := next_level - now_level
	var exact := true
	for p: Dictionary in parts:
		if bool(p.get("modifier", false)):
			exact = false
	var units := 0
	for p: Dictionary in parts:
		units += int(p.units)
	exact = exact and units == cap
	var key: Control = CabinetKey.new()
	key.name = "ExpandWarehouse"
	key.text = ("Expand to %d" % (cap + gain)) if exact else ("Expand +%d" % gain)
	key.custom_minimum_size.x = 150.0
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.tooltip_text = "Warehouse level %d holds %d, %d more than level %d. See what it takes." % [
		int(quote.get("next_level", 2)), next_level, gain, int(quote.get("level", 1))]
	key.pressed.connect(func() -> void:
		panel.set("_warehouse_expand", true)
		_refresh(panel))
	return key


## How full the warehouse got: last turn's peak, judged by the same rule as the fill itself (fill_tone).
## When it ran out of room, or is out of room now, that is the line instead, one line with the way out
## under its words.
static func _fill_line(tile: String, stock: Dictionary) -> Control:
	var cap := int(stock.capacity)
	var refused := Stockpile.get_refused(tile)
	if refused > 0 or bool(stock.is_full):
		var fact := ("Full last turn, %d units turned away" % refused) if refused > 0 \
			else "Full now, more goods will be turned away"
		var full := _row("stock", "bad", fact, true, WAY_OUT)
		full.name = "FullRow"
		full.tooltip_text = "Sell or move goods from the bay below, sell the surplus with the knob, or expand the warehouse"
		return full
	var peak := Stockpile.get_peak_used(tile)
	var row := _row("unsold", fill_tone(peak, cap), "Last turn's peak %d%%" % roundi(float(peak) / float(maxi(cap, 1)) * 100.0))
	row.name = "PeakRow"
	row.tooltip_text = "The most stored at any point last turn: %d of %d" % [peak, cap]
	return row


## A fill's tone by the stockpile summary's own rule (TileViewData.stockpile_summary: red when full, amber
## from 90%), for a figure the summary doesn't judge, such as last turn's peak. "off" when nothing is stored.
static func fill_tone(units: int, cap: int) -> String:
	if units > 0 and units >= cap:
		return "bad"
	if cap > 0 and float(units) / float(cap) >= FILL_WARN:
		return "warn"
	return "ok" if units > 0 else "off"


## Where the fill is heading, in the transport panel's words and colours for the same figure (its
## _full_eta_text, _eta_color and trend dead band), so the two panels never disagree: full next turn or in
## N turns at this rate (red at 3 turns or fewer, amber beyond); not filling, emptying (green) past the
## dead band, else steady (lamp off). {tone, text, tip}, or {} while full now (the fill line says so) or
## before there are two turns to compare.
static func eta(tile: String, stock: Dictionary) -> Dictionary:
	if bool(stock.is_full):
		return {}
	var samples := Stockpile.get_fill_history(tile).size()
	if samples < 2:
		return {}
	var over := mini(TREND_TURNS, samples - 1)
	var span := "over the last %d turn%s" % [over, "" if over == 1 else "s"]
	var rate := Stockpile.fill_trend_per_turn(tile, TREND_TURNS)
	var turns := Stockpile.turns_until_full(tile, TREND_TURNS)
	var tip := "Up about %d a turn %s" % [maxi(1, roundi(rate)), span]
	if turns == 0:
		return {"tone": "bad", "text": "Full next turn at this rate", "tip": tip}
	if turns > 0:
		return {"tone": "bad" if turns <= ETA_RED_TURNS else "warn",
			"text": "Full in %d turn%s at this rate" % [turns, "" if turns == 1 else "s"], "tip": tip}
	if rate < -maxf(1.0, float(stock.capacity) * TREND_DEAD_BAND):
		return {"tone": "ok", "text": "Emptying, down about %d a turn" % maxi(1, roundi(-rate)), "tip": "Measured %s" % span}
	return {"tone": "off", "text": "Steady %s" % span, "tip": "Not filling"}


## Where the surplus goes, in words beside the knob that sets it; pointing at one of the knob's options
## shows what that one would do, or what it is waiting on. It judges nothing, so its lamp's place is empty.
static func _surplus_row(tile: String, knob_box: Control) -> Control:
	var row := HBoxContainer.new()
	row.name = "SurplusRow"
	row.add_theme_constant_override("separation", ROW_SEP)
	row.custom_minimum_size.y = SURPLUS_LINE_H
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = "Surplus is whatever no building on this tile needs. Turn the knob to keep it or sell it."
	var icons := {}
	for id: String in SURPLUS_LINES:
		var icon := Parts.raised_icon(ICON_PATH % str(SURPLUS_LINES[id][0]), ROW_ICON_PX)
		icon.name = "SurplusIcon_%s" % id
		icons[id] = icon
		row.add_child(icon)
	row.add_child(_lamp_slot(""))
	var words := Parts.para("")
	words.name = "SurplusWords"
	row.add_child(words)
	var put := func(id: String, text: String) -> void:
		for k: String in icons:
			(icons[k] as Control).visible = k == id
		words.text = text
	var chosen := MatchState.get_sell_surplus_destination(tile)
	if not SURPLUS_LINES.has(chosen):
		chosen = "none"
	var back := func() -> void: put.call(chosen, str(SURPLUS_LINES[chosen][1]))
	back.call()
	var knob := knob_box.find_child("SurplusKnob", true, false)
	if knob != null:
		var options: Array = knob.get("options")
		var buttons: Array = knob.get("option_buttons")
		for i in mini(options.size(), buttons.size()):
			var o: Dictionary = options[i]
			var id := str(o.get("id", ""))
			if not SURPLUS_LINES.has(id):
				continue
			var text := str(SURPLUS_LINES[id][1])
			if not bool(o.get("enabled", true)):
				text = ("Needs %s" % ResearchState.OPEN_LOGISTICS_CONTRACTS_TITLE) if id == "middleman" \
					else ("Needs the %s" % ResearchState.GLOBAL_TRADE_LICENSE_TITLE)
			(buttons[i] as Control).mouse_entered.connect(func() -> void: put.call(id, text))
			(buttons[i] as Control).mouse_exited.connect(back)
	return row


## A tone's figure colour on an LED: amber when nearly full, red when full, else white as the keys' LEDs.
static func tone_colour(tone: String) -> Color:
	match tone:
		"bad": return DS.PALETTE.DANGER
		"warn": return DS.PALETTE.WARN
	return DS.PALETTE.TEXT


## The fill's tone from the stockpile summary's own status (the Stock key's lamp reads the same).
static func _summary_tone(stock: Dictionary) -> String:
	match str(stock.status):
		"problem": return "bad"
		"warn": return "warn"
	return "ok"


## What the capacity is made of, in the order it adds up (Stockpile.get_capacity): the warehouse's level,
## each building's added storage (the port's 600), then whatever modifiers add.
static func _capacity_parts(tile: String, cap: int) -> Array:
	var level := Stockpile.get_warehouse_level(tile)
	var base := int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(level, Stockpile.TILE_CAPACITY))
	var parts: Array = [{"label": "%d WAREHOUSE L%d" % [base, level], "short": str(base), "units": base,
		"tip": "The warehouse, level %d, holds %d" % [level, base]}]
	var boosts := {}
	var order: Array = []
	for iid in BuildingState.tile_buildings.get(tile, []):
		var bd: Dictionary = Catalog.get_building(str(BuildingState.get_building(str(iid)).get("building_id", "")))
		var boost := int(bd.get("storage_boost", 0))
		if boost <= 0:
			continue
		var bname := str(bd.get("display_name", "Building"))
		if not boosts.has(bname):
			order.append(bname)
		boosts[bname] = int(boosts.get(bname, 0)) + boost
	var added := 0
	for bname: String in order:
		var units := int(boosts[bname])
		added += units
		parts.append({"label": "+%d %s" % [units, bname.to_upper()], "short": "+%d" % units, "units": units,
			"tip": "The %s adds %d" % [bname.to_lower(), units]})
	var rest := cap - base - added
	if rest > 0:
		parts.append({"label": "+%d MODIFIERS" % rest, "short": "+%d" % rest, "units": rest, "modifier": true,
			"tip": "Modifiers add %d" % rest})
	return parts


## A lamp for a line that judges something, or its empty place for one that doesn't, so every line's
## words start in the same column.
static func _lamp_slot(tone: String) -> Control:
	if tone != "":
		return Parts.lamp(tone)
	var slot := Control.new()
	slot.name = "LampSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(_lamp_w(), _lamp_w())
	return slot


static func _lamp_w() -> float:
	return roundf(Parts.Lamp.BEZEL / Parts.Lamp.CAPTURE_SCALE * Parts.ROW_LAMP)


## Where every line's words start: past its raised icon and its lamp.
static func _text_x() -> float:
	return ROW_ICON_PX + ROW_SEP + _lamp_w() + ROW_SEP


## One of the warehouse's lines: its raised icon, a lamp for its tone ("" leaves the lamp's place empty)
## and what it says, in red when `danger`; with `then`, a second sentence under it in white (the way out).
static func _row(icon: String, tone: String, text: String, danger := false, then := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size.y = SURPLUS_LINE_H
	var mark := Parts.raised_icon(ICON_PATH % icon, ROW_ICON_PX)
	row.add_child(mark)
	row.add_child(_lamp_slot(tone))
	var words := Parts.para(text)
	words.name = "LineWords"
	if danger:
		words.add_theme_color_override("font_color", DS.PALETTE.DANGER)
	if then == "":
		row.add_child(words)
		return row
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.add_child(words)
	var out := Parts.para(then)
	out.name = "LineWayOut"
	col.add_child(out)
	row.add_child(col)
	return row


## A shipment that reached this tile but can't unload while it is full, under the line that counts them,
## in the lines' text column: the good in its well, then one sentence, how much and where from by name
## (the coordinates on hover) and how long it has waited, the wait in amber.
static func _overflow_row(r: Dictionary) -> Control:
	var indent := MarginContainer.new()
	indent.name = "OverflowShipment"
	indent.mouse_filter = Control.MOUSE_FILTER_PASS
	indent.add_theme_constant_override("margin_left", roundi(_text_x()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size.y = SURPLUS_LINE_H
	indent.add_child(row)
	var gid := str(r.get("good_id", ""))
	row.add_child(Parts.good_in_well(gid, SHIPMENT_ICON_PX))
	var src := str(r.get("source_tile", ""))
	var from := (" from %s" % Parts.tile_words(src)) if src != "" else ""
	var turns := int(r.get("turns_waiting", 0))
	var what := "%d %s%s" % [int(r.get("qty", 0)), Catalog.get_display_name(gid), from]
	var wait := "waiting %d turn%s" % [turns, "" if turns == 1 else "s"]
	# The wait is kept whole (no break spaces) so a narrow column wraps before it, never inside it.
	var words := _sentence("%s, [color=#%s]%s[/color]" % [what.replace("[", "[lb]"), DS.PALETTE.WARN.to_html(false),
		wait.replace(" ", NBSP)])
	words.name = "ShipmentWords"
	row.add_child(words)
	var tip := "%s, %s to unload" % [what, wait]
	if src != "":
		tip += "\nFrom %s" % Parts.coords(src)
	indent.tooltip_text = tip
	words.tooltip_text = tip
	return indent


## Body text as one wrapping sentence that may carry colour ([color] tags), embossed as Parts.body is.
static func _sentence(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.custom_minimum_size.x = 120.0
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_override("normal_font", Parts.UIFonts.PLEX_MED)
	r.add_theme_font_size_override("normal_font_size", Parts.BODY_PX)
	r.add_theme_color_override("default_color", DS.PALETTE.TEXT)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	r.add_theme_constant_override("shadow_offset_x", 1)
	r.add_theme_constant_override("shadow_offset_y", 1)
	r.text = bbcode
	return r


# --- A warehouse that isn't yours: a shut door ------------------------------------------------------------

## Where you have neither land nor goods: the heading says what the warehouse would hold, its door is down
## over one row of the bay (as Building Detail's shut bay), and what the capacity is made of is under it
## when it is more than the warehouse.
static func _idle(tile: String, stock: Dictionary) -> Control:
	var cap := int(stock.capacity)
	var sec: Control = Section.new()
	sec.name = "WarehouseSection"
	sec.style = "dark"
	var c: VBoxContainer = sec.content
	c.add_theme_constant_override("separation", CELL_GAP)
	var head := HBoxContainer.new()
	head.name = "WarehouseHead"
	head.add_theme_constant_override("separation", 8)
	head.add_child(Parts.heading("Warehouse"))
	head.add_child(Parts.spacer())
	var holds := Parts.metal("Holds %d" % cap, HORIZONTAL_ALIGNMENT_RIGHT)
	holds.name = "IdleCapacity"
	holds.add_theme_font_size_override("font_size", 18)
	head.add_child(holds)
	c.add_child(head)
	var door: Control = Door.new()
	door.name = "IdleDoor"
	door.reach = Section.PADDING
	door.custom_minimum_size.y = Door.rolled_up_height() + CELL_H
	var notice := VBoxContainer.new()
	notice.name = "IdleSign"
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notice.offset_top = Door.TOP / Door.CAPTURE_SCALE
	notice.alignment = BoxContainer.ALIGNMENT_CENTER
	notice.add_theme_constant_override("separation", 2)
	var shut := Parts.metal("Closed", HORIZONTAL_ALIGNMENT_CENTER)
	shut.add_theme_font_size_override("font_size", 20)
	notice.add_child(shut)
	var why := Parts.metal("Yours to use once you own land or keep goods here", HORIZONTAL_ALIGNMENT_CENTER)
	why.name = "IdleNote"
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_child(why)
	door.add_child(notice)
	c.add_child(door)
	var parts := _capacity_parts(tile, cap)
	if parts.size() > 1:
		var labels := PackedStringArray()
		for p: Dictionary in parts:
			labels.append(str(p.label))
		var made := Parts.metal("   ".join(labels), HORIZONTAL_ALIGNMENT_CENTER)
		made.name = "IdleParts"
		c.add_child(made)
	return sec


# --- Stored goods: the bay ------------------------------------------------------------------------------

static func _bay(panel: Control, tile: String, stock: Dictionary, gauge: Control) -> Control:
	var goods: Array = stock.goods
	var sec: Control = Section.new()
	sec.name = "GoodsBay"
	sec.style = "dark"
	var c: VBoxContainer = sec.content
	c.add_theme_constant_override("separation", CELL_GAP)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(Parts.heading("Stored goods"))
	head.add_child(Parts.spacer())
	if not goods.is_empty():
		head.add_child(Parts.metal("Pick one to move or sell", HORIZONTAL_ALIGNMENT_RIGHT))
	c.add_child(head)

	# The door is up over a bay in use, its housing across the top; down over an empty one.
	var door: Control = Door.new()
	door.name = "BayDoor"
	door.reach = Section.PADDING
	door.custom_minimum_size.y = Door.rolled_up_height()
	c.add_child(door)
	if goods.is_empty():
		door.custom_minimum_size.y += CELL_H
		var shut := Parts.metal("Nothing stored", HORIZONTAL_ALIGNMENT_CENTER)
		shut.name = "BayEmpty"
		shut.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shut.offset_top = Door.TOP / Door.CAPTURE_SCALE
		shut.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shut.add_theme_font_size_override("font_size", 18)
		door.add_child(shut)
		return sec

	var slots := BAY_COLS * BAY_ROWS
	var open := str(panel.get_meta("tvp_stock_all_goods", "")) == tile
	var shown: Array = goods if open or goods.size() <= slots else goods.slice(0, slots)
	var rack := VBoxContainer.new()
	rack.name = "StockpileAllGoods" if shown.size() == goods.size() else "StockpileGoods"
	rack.add_theme_constant_override("separation", CELL_GAP)
	c.add_child(rack)
	for i in range(0, shown.size(), BAY_COLS):
		var row := HBoxContainer.new()
		row.name = "BayRow"
		row.add_theme_constant_override("separation", CELL_GAP)
		for j in BAY_COLS:
			if i + j < shown.size():
				row.add_child(_cell(panel, tile, shown[i + j], gauge))
			else:
				var gap := Control.new()
				gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(gap)
		rack.add_child(row)

	if goods.size() > slots:
		var more: Control = ModKey.new()
		more.name = "OtherGoodsBar"
		more.summary = "All %d goods" % goods.size()
		more.tooltip_text = "Show every good on this tile"
		more.set_open(open)
		more.toggled.connect(func(o: bool) -> void:
			panel.set_meta("tvp_stock_all_goods", tile if o else "")
			_refresh(panel))
		c.add_child(more)
	return sec


## A good in the bay: its icon in a well with its quantity pill inside, its name under it, and a small
## raised arrow by the well when some of it leaves every turn (a standing order, a recurring sale or move;
## the hover says which). The whole cell is a button that opens its Move or sell sheet; pointing at it
## lights its slice in the warehouse's bar.
static func _cell(panel: Control, tile: String, g: Dictionary, gauge: Control) -> Control:
	var gid := str(g.good_id)
	var qty := int(g.qty)
	var b := Button.new()
	b.name = "StoredGood_" + gid
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, CELL_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bare := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, bare)
	var tip := PackedStringArray(["%s: %d here" % [str(g.display_name), qty]])
	var every: Array = Sheets.standing(tile, gid)
	for r: Dictionary in every:
		tip.append("Every turn: %s" % str(r.text).to_lower())
	tip.append("Click to move or sell")
	b.tooltip_text = "\n".join(tip)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	col.add_child(Parts.good_in_well(gid, CELL_ICON, qty))
	var title := Parts.body(str(g.display_name))
	title.name = "GoodName"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.custom_minimum_size.y = NAME_H
	title.size_flags_horizontal = Control.SIZE_FILL
	col.add_child(title)
	b.add_child(col)
	if not every.is_empty():
		var mark := Parts.raised_icon(ICON_PATH % "route", EVERY_TURN_PX)
		mark.name = "EveryTurnMark"
		mark.position = Vector2(2.0, 2.0)
		mark.size = Vector2(EVERY_TURN_PX, EVERY_TURN_PX)
		b.add_child(mark)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func() -> void:
		col.modulate = Color(1.14, 1.14, 1.14)
		gauge.call("set_hot", gid))
	b.mouse_exited.connect(func() -> void:
		col.modulate = Color.WHITE
		if is_instance_valid(gauge):
			gauge.call("set_hot", ""))
	b.pressed.connect(func() -> void: panel.call_deferred("select_stock_good", gid))
	# And pointing at its tile or slice in the warehouse's bar lights the cell.
	gauge.connect("pointed", func(id: String) -> void:
		if is_instance_valid(col):
			col.modulate = Color(1.14, 1.14, 1.14) if id == gid else Color.WHITE)
	return b


# --- Logistics, in intermediary games ---------------------------------------------------------------------

static func _has_logistics(logistics: Dictionary) -> bool:
	return str(MatchState.ruleset.get("logistics_model", "")) == "middleman_v1" \
		and (not (logistics.input as Array).is_empty() or not (logistics.output as Array).is_empty()) \
		and ResearchState.open_logistics_contracts_available()


static func _logistics(panel: Control, logistics: Dictionary) -> Control:
	var sec: Control = Section.new()
	sec.name = "LogisticsSection"
	sec.style = "plastic"
	var c: VBoxContainer = sec.content
	c.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(Parts.heading("Logistics"))
	head.add_child(Parts.spacer())
	head.add_child(Parts.metal("For every building here", HORIZONTAL_ALIGNMENT_RIGHT))
	c.add_child(head)

	var readout: Control = Readout.new()
	readout.name = "LogisticsReadout"
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var now: Array = []
	var knobs := HBoxContainer.new()
	knobs.name = "RoutingKnobs"
	knobs.alignment = BoxContainer.ALIGNMENT_CENTER
	knobs.add_theme_constant_override("separation", 40)
	var knob_list: Array = []
	for side: String in ["input", "output"]:
		if not (logistics.get(side, []) as Array).is_empty():
			var built := _logistics_knob(panel, side, logistics, readout)
			knob_list.append(built)
			knobs.add_child(built.knob)
			now.append("%s %s" % ["inputs" if side == "input" else "outputs", str(built.current_name).to_lower()])
	var show_now := func() -> void:
		readout.call("show_check", "", "Now: %s" % ", ".join(now), "Point at an icon to see what it does. Turning a knob asks first.", "")
	show_now.call()
	for built: Dictionary in knob_list:
		for b: Button in built.buttons:
			b.mouse_exited.connect(show_now)
	c.add_child(knobs)
	c.add_child(readout)
	return sec


## Every building's inputs, or outputs, on this tile on one knob: per building, the intermediary, the
## global market or this tile's stockpile (the v2 logistics buttons' four choices). Turning it asks for
## confirmation, as the buttons did (_apply_tile_logistics_policy); cancelled, the rebuild turns it back.
static func _logistics_knob(panel: Control, side: String, logistics: Dictionary, readout: Control) -> Dictionary:
	var ids: Array = logistics.get(side, [])
	var licensed := ResearchState.global_trade_license_available()
	var choices := [
		{"id": "managed", "icon": panel.call("_off_white_route_icon", BuildingIcon.clean_texture("b_007", "industrial_factory")),
			"name": "Per building"},
		{"id": "middleman", "icon": ROUTE_MIDDLEMAN_ICON, "name": "Logistics Intermediary"},
		{"id": "market", "icon": ROUTE_MARKET_ICON, "enabled": licensed,
			"name": "Global Market" if licensed else "Global Market: needs the %s" % ResearchState.GLOBAL_TRADE_LICENSE_TITLE},
		{"id": "stockpile", "icon": ROUTE_STOCKPILE_ICON, "name": "Tile Stockpile"},
	]
	var current := 0
	for i in [1, 2, 3]:
		if bool(panel.call("_tile_logistics_choice_active", str(choices[i].id), side, ids)):
			current = i
			break
	var knob: Control = RotarySelector.new()
	knob.name = "%sLogisticsKnob" % side.capitalize()
	knob.knob_size = LOGISTICS_KNOB
	knob.set("label", "INPUTS" if side == "input" else "OUTPUTS")
	knob.set("label_colour", DS.PALETTE.TEXT)
	knob.call("set_options", choices)
	knob.call("set_value_no_signal", current + 1)
	knob.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	knob.size_flags_vertical = Control.SIZE_SHRINK_END
	var buttons: Array = knob.get("option_buttons")
	var stage := "Inputs" if side == "input" else "Outputs"
	for i in buttons.size():
		var id := str(choices[i].id)
		(buttons[i] as Button).name = "%s_%s" % [side.capitalize(), id.capitalize()]
		var line: Array = LOGISTICS_ROUTES[side][id]
		var detail := str(line[1]) if bool(choices[i].get("enabled", true)) else str(choices[i].name)
		(buttons[i] as Button).mouse_entered.connect(func() -> void:
			readout.call("show_check", stage, str(line[0]), detail, ""))
	knob.value_changed.connect(func(v: int) -> void:
		panel.call("_apply_tile_logistics_policy", side, str(choices[v - 1].id), logistics))
	return {"knob": knob, "buttons": buttons, "current_name": str(LOGISTICS_ROUTES[side][str(choices[current].id)][0])}
