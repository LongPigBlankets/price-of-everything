extends RefCounted
## The Shipments and Stockpiles panel in DS2, built into the transport panel (scripts/transport_panel.gd) while
## UiPrefs.use_transport_ds2 is on. With the switch off the panel builds its v2 look itself. Everything here is
## presentation: the panel keeps the rows' figures, the filters and the refresh wiring, and asks this script
## for the parts.
##
## The shell is the Building Ledger's: Building Detail's navy steel backing in its brass trim, the raised title,
## the Close key and the rubber seam. In the title row, the routing objective as three latching keys and the
## Logistics Settings key. Under the seam three columns, each a raised heading over one plastic case of raised
## modules on the steel scroll rail:
##   Stockpiles      a tile a module: its name, a lamp and how full it is in words, a mark for filling,
##                   draining or steady, the fill on an LED meter, its warehouse level, and its largest goods
##                   in their wells
##   Infrastructure  a link a module: its emblem in polished metal, its name, a lamp and its load in words, the
##                   load on an LED meter, and what congestion has cost when it has cost anything
##   In transit      a shipment a module: its cargo in wells, where it is going and when it lands. Several
##                   carrying the same goods to the same place are one module, read as what arrives a turn
## Logistics Settings is a sheet over the panel: for inputs and for outputs, three latching keys.

const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const LedMeter := preload("res://scripts/ds2/led_meter.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")

const EMBLEM_PX := 52.0
const COLUMN_GAP := 14
const ROUTING := [["Fastest", 0], ["Cheapest", 1], ["Blended", 2]]


# --- the shell ---------------------------------------------------------------------------------

## The raised title, then `extras` (the routing keys, the settings key) and the Close key. The row drags the panel.
static func title_row(text: String, extras: Array, on_close: Callable, on_drag: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TransportTitleRow"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	row.gui_input.connect(on_drag)
	var title: Control = Title.new()
	title.call("set_text", text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	for extra: Control in extras:
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(extra)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.pressed.connect(on_close)
	row.add_child(close)
	return row


## Latching keys on the tile view's key bed, one down at a time. `specs` is [[label, id], ...]; `on_pick` takes
## the id. Returns {bed, keys: {id: LatchKey}}.
static func key_bed(bed_name: String, specs: Array, current: Variant, on_pick: Callable, key_width := 0.0) -> Dictionary:
	var bed := PanelContainer.new()
	bed.name = bed_name
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 8
	pad.content_margin_right = 8
	pad.content_margin_top = 8
	pad.content_margin_bottom = 10
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, LedgerV3.KEYBED, Rect2(Vector2.ZERO, bed.size).grow(LedgerV3.KEYBED_MARGIN / LedgerV3.LAYOUT),
			(LedgerV3.KEYBED_MARGIN + LedgerV3.KEYBED_CORNER) * LedgerV3.TEXELS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	bed.add_child(line)
	var keys := {}
	for spec: Array in specs:
		var id: Variant = spec[1]
		var key: Control = LatchKey.new()
		key.name = "Key_%s" % str(id)
		key.set("text", str(spec[0]))
		key.set("latched", id == current)
		if key_width > 0.0:
			key.custom_minimum_size.x = key_width
		else:
			key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.connect("pressed", func() -> void:
			for other in keys:
				(keys[other] as Control).set("latched", other == id)
			on_pick.call(id))
		keys[id] = key
		line.add_child(key)
	return {"bed": bed, "keys": keys}


## The routing objective: a metal label and three latching keys.
static func routing(current: int, on_pick: Callable) -> Dictionary:
	var box := HBoxContainer.new()
	box.name = "Routing"
	box.add_theme_constant_override("separation", 8)
	box.add_child(Parts.caption("Routing"))
	var bed := key_bed("RoutingObjective", ROUTING, current, on_pick, 92.0)
	box.add_child(bed.bed)
	return {"box": box, "keys": bed.keys}


## A column: its raised heading with how it is sorted beside it, `extra` under that (the infrastructure's
## filter keys), then one plastic case on the steel rail. Returns {wrap, list}.
static func column(title: String, sorted_by: String, extra: Control = null) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.name = "Column_%s" % title.replace(" ", "")
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	wrap.add_child(head)
	var heading := Parts.heading(title)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	head.add_child(Parts.caption(sorted_by, Parts.CAPTION_PX - 2, HORIZONTAL_ALIGNMENT_RIGHT))
	if extra != null:
		wrap.add_child(extra)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Scroll.apply(scroll, true)
	wrap.add_child(scroll)
	var case := Parts.plastic_case("Case")
	scroll.add_child(case)
	return {"wrap": wrap, "list": case.get_child(0)}


# --- rows --------------------------------------------------------------------------------------

## A module whose content is a column of lines. Returns {module, col}.
static func _stacked(module_name: String, lead: Control = null) -> Dictionary:
	var m := Parts.module(module_name)
	var row := Parts.row_of(m)
	row.custom_minimum_size.y = 0
	if lead != null:
		lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lead)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	return {"module": m, "col": col}


## A load on the LED meter with a metal label after it.
static func _meter_line(used: float, cap: float, near: float, tone: String, label: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meter: Control = LedMeter.new()
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.call("set_load", used, cap, near, tone)
	line.add_child(meter)
	if label != "":
		line.add_child(Parts.caption(label, Parts.CAPTION_PX - 2))
	return line


## Which way a stockpile is going, drawn beside its words (a font's arrows are missing on some machines): an
## amber arrow up while it fills, a green arrow down while it drains, a thick white line while it holds steady.
class TrendMark extends Control:
	var trend := "steady"

	func _init(which: String) -> void:
		trend = which
		name = "Trend"
		set_meta("trend", which)
		custom_minimum_size = Vector2(16, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = {"up": "Filling", "down": "Draining"}.get(which, "Holding steady")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match trend:
			"up":
				draw_colored_polygon(PackedVector2Array([Vector2(1, h - 1), Vector2(w - 1, h - 1), Vector2(w * 0.5, 1)]), DS.PALETTE["WARN"])
			"down":
				draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w * 0.5, h - 1)]), DS.PALETTE["OK"])
			_:
				draw_rect(Rect2(1, h * 0.5 - 2.0, w - 2, 4.0), DS.PALETTE["TEXT"])


## A stockpile. `d`: {tile_id, name, level, used, cap, near, tone, words, trend (up, down or steady),
## goods: [{good_id, qty}]}.
static func stock_row(d: Dictionary, on_open: Callable) -> PanelContainer:
	var s := _stacked("Stock_%s" % str(d.tile_id))
	var m: PanelContainer = s.module
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "Open this tile's stockpile"
	Parts.on_click(m, on_open)
	var col: VBoxContainer = s.col
	var info := Parts.info(str(d.name), str(d.tone), str(d.words))
	var status := info.get_node_or_null("Status") as HBoxContainer
	if status != null:
		# The words keep to their own width, so the mark stands right after them.
		var said := status.get_node("Words") as Label
		said.autowrap_mode = TextServer.AUTOWRAP_OFF
		said.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		status.add_child(TrendMark.new(str(d.get("trend", "steady"))))
	col.add_child(info)
	col.add_child(_meter_line(float(d.used), float(d.cap), float(d.near), str(d.tone), "Lvl %d" % int(d.level)))
	var goods: Array = d.get("goods", [])
	if not goods.is_empty():
		var wells := HBoxContainer.new()
		wells.add_theme_constant_override("separation", 10)
		wells.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for g: Dictionary in goods:
			wells.add_child(Parts.good_in_well(str(g.good_id), int(g.qty), ""))
		col.add_child(wells)
	return m


## A link. `d`: {key, building_id, name, level, flow, cap, near, tone, words, cost_words}.
static func infra_row(d: Dictionary, on_open: Callable) -> PanelContainer:
	var s := _stacked("Link_%s" % str(d.key), Parts.emblem(str(d.building_id), EMBLEM_PX))
	var m: PanelContainer = s.module
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "Open this infrastructure to inspect or upgrade it"
	Parts.on_click(m, on_open)
	var col: VBoxContainer = s.col
	col.add_child(Parts.info(str(d.name), str(d.tone), str(d.words)))
	col.add_child(_meter_line(float(d.flow), float(d.cap), float(d.near), str(d.tone), "Lvl %d" % int(d.level)))
	if str(d.get("cost_words", "")) != "":
		var cost := Parts.body(str(d.cost_words))
		cost.name = "CongestionCost"
		cost.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		col.add_child(cost)
	return m


## A shipment. `d`: {manifest: [{good_id, qty}], where, when}.
static func transit_row(d: Dictionary, index: int) -> PanelContainer:
	var m := Parts.module("Shipment_%d" % index)
	var row := Parts.row_of(m)
	var wells := HBoxContainer.new()
	wells.add_theme_constant_override("separation", 10)
	wells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in d.manifest:
		wells.add_child(Parts.good_in_well(str(entry.good_id), int(entry.qty), ""))
	row.add_child(wells)
	row.add_child(Parts.info(str(d.where), "", str(d.when)))
	return m


## A building's logistics in an intermediary game: its name over how its inputs and outputs are handled.
static func logistics_row(iid: String, building_name: String, words: String, on_open: Callable) -> PanelContainer:
	var m := Parts.module("Logistics_%s" % iid)
	Parts.row_of(m).custom_minimum_size.y = 0
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.tooltip_text = "Open building details to change logistics."
	Parts.on_click(m, on_open)
	Parts.row_of(m).add_child(Parts.info(building_name, "", words))
	return m


## A line of words on a module of its own, for a column with nothing to list.
static func note(text: String) -> PanelContainer:
	var m := Parts.module("Note")
	var row := Parts.row_of(m)
	row.custom_minimum_size.y = 0
	var words := Parts.body(text)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	return m


## A section's raised heading inside a case (Building logistics).
static func list_heading(text: String) -> Control:
	return Parts.heading(text)


# --- Logistics Settings ------------------------------------------------------------------------

## The settings sheet's shell over the panel: a scrim and a dressed card with its raised title and Close key.
## Returns {layer, card, body}; the panel fills `body`.
static func settings_sheet(on_close: Callable) -> Dictionary:
	var layer := Control.new()
	layer.name = "LogisticsSettingsOverlay"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	layer.draw.connect(func() -> void: layer.draw_rect(Rect2(Vector2.ZERO, layer.size), Color(0, 0, 0, 0.55)))
	var card := PanelContainer.new()
	card.name = "LogisticsSettingsCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(card)
	LedgerV3.dress(card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, LedgerV3.CONTENT_MARGIN)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	body.add_child(head)
	var title: Control = Title.new()
	title.call("set_text", "Logistics Settings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "SettingsCloseKey"
	close.pressed.connect(on_close)
	head.add_child(close)
	body.add_child(LedgerV3.seam())
	return {"layer": layer, "card": card, "body": body}


## One side of the company's logistics: its heading over three latching keys, one down when every building
## takes that route. `choices`: [{id, label, tip, enabled, active}]; `on_pick` takes the id.
static func settings_side(side_title: String, choices: Array, on_pick: Callable) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "GlobalLogistics%s" % side_title
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	column.add_child(Parts.heading(side_title))
	var stack := VBoxContainer.new()
	stack.name = "Choices"
	stack.add_theme_constant_override("separation", 6)
	column.add_child(stack)
	for choice: Dictionary in choices:
		var id := str(choice.id)
		var key: Control = LatchKey.new()
		key.name = id.capitalize()
		key.set("text", str(choice.label))
		key.set("latched", bool(choice.get("active", false)))
		key.set("disabled", not bool(choice.get("enabled", true)))
		key.tooltip_text = str(choice.get("tip", ""))
		key.connect("pressed", func() -> void: on_pick.call(id))
		stack.add_child(key)
	return column
