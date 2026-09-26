extends RefCounted
## The Building Ledger in DS2 (docs/building-ledger-ds2-plan.md), built into the ledger panel
## (scripts/building_ledger_panel.gd) while UiPrefs.use_ledger_ds2 is on. With the switch off the panel builds
## its v2 look itself. Everything here is presentation: the panel keeps the rows' figures (its row models),
## the filters, the sort and the refresh wiring, and asks this script for the parts.
##
## The panel is Building Detail's: its navy steel backing in its brass trim, the raised title and the Close
## key. Under the title, a strip: the count on a dot-matrix display and the search on a screen. Then the filters as latching keys on a key bed, the tile view's, one row
## for what a building is doing and one for what kind it is. Under the seam, the column headings as metal
## labels (click one to sort by it, again to turn the order round; the sorted column's heading is cream with
## a mark pointing the way it runs) over one plastic case of raised modules, a building a module:
##   its emblem in polished metal; its name over its tile's name; what it makes in a well with its quantity on
##   the pill; its inputs' and outputs' routes; its power (a lamp, the MW, and where the power comes from);
##   its status (a lamp and a word); what a unit costs to make and what it nets a turn, on LED screens after
##   a printed £; its land; and an Upgrade key whose card is Building Detail's (the dot card).
## Clicking a module opens the building, as the v2 row does.

const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const DotCard := preload("res://scripts/ds2/dot_card.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Seam := preload("res://scripts/bdp_v3_seam.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const RoutesView := preload("res://scripts/logistics_routes_view.gd")

## Building Detail's backing: its 9-slice corner in texels, the content's margin inside the brass trim and
## the trim's width (building_detail_panel_v2.gd BACKING_TRIM, CONTENT_MARGIN).
const BACKING_CORNER := 64.0
const CONTENT_MARGIN := 26
const BACKING_TRIM := 14.0
## The tile view's key bed (its render and 9-slice), round the filter keys.
const KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
const LAYOUT := 1.875
const TEXELS := 2.0 / 1.875
## The gap between a module's columns, and each column's width, left to right, the headings over them.
const COL_GAP := 8
const COLUMNS := [
	{"key": "emblem", "label": "", "w": 60.0, "sort": false},
	{"key": "name", "label": "Building", "w": 172.0, "sort": true},
	{"key": "output", "label": "Makes", "w": 80.0, "sort": true},
	{"key": "logistics_inputs", "label": "Source", "w": 80.0, "sort": false},
	{"key": "logistics_outputs", "label": "Destination", "w": 88.0, "sort": false},
	{"key": "power", "label": "Power", "w": 104.0, "sort": true},
	{"key": "status", "label": "Status", "w": 92.0, "sort": true},
	{"key": "cost", "label": "Cost/unit", "w": 98.0, "sort": true},
	{"key": "net", "label": "Net/turn", "w": 100.0, "sort": true},
	{"key": "land", "label": "Land", "w": 44.0, "sort": true},
	{"key": "upgrade", "label": "", "w": 150.0, "sort": false},
]
## The emblem's side and a good's well in the Makes column: the tile view's building cards', so every DS2
## building card is one height (scripts/ds2/metrics.gd CARD_H).
const EMBLEM_PX := Parts.EMBLEM_PX
const WELL_PX := Parts.WELL_PX
## Where a building's goods come from and go to, by kind (logistics_routes_view.gd endpoints): each kind's
## raised icon, or the producing building's emblem. One kind fills the card's height; two or three stand
## smaller, two to a line, each with how many places of its kind when more than one. No more than three
## kinds show; the hover lists every place.
const ROUTE_ICONS := {"grid": "bar_icon_power", "middleman": "diag_icon_freight", "stockpile": "bar_icon_warehouse",
	"port": "bar_icon_port"}
const ROUTE_SMALL := 34.0
const ROUTE_KINDS := 3
## The filter keys, a row each: what a building is doing, then what kind it is.
const FILTER_ROWS := [
	[["running", "Running"], ["starved", "Starved"], ["unpowered", "Unpowered"], ["loss", "Loss making"],
		["profitable", "Profitable"], ["upgradable", "Upgradable"]],
	[["cat_production", "Production"], ["cat_power", "Power"], ["cat_infrastructure", "Infrastructure"],
		["green_intermittent", "Intermittent green"], ["green_steady", "Steady green"]],
]
## The search screen's height, and the dot display's pitch.
const SEARCH_H := 34.0
const COUNT_PITCH := 2.0
## A status word's lamp tone.
const STATUS_TONES := {"Running": "ok", "Idle": "warn", "Starved": "bad"}


# --- the shell ---------------------------------------------------------------------------------

## Building Detail's backing behind the panel, sized to it; the panel's own stylebox bare.
static func dress(panel: PanelContainer) -> Control:
	var bg := StyleBoxFlat.new()
	bg.bg_color = DS.PALETTE["BG_PANEL"]
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg)
	var backing: Control = Nine.make("panel_backing", BACKING_CORNER)
	backing.name = "LedgerBacking"
	panel.add_child(backing)
	panel.move_child(backing, 0)
	return backing


## The raised title and the Close key; the row drags the panel as the v2 header does.
static func title_row(on_close: Callable, on_drag: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "LedgerTitleRow"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	row.gui_input.connect(on_drag)
	var title: Control = Title.new()
	title.call("set_text", "Buildings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.pressed.connect(on_close)
	row.add_child(close)
	return row


## The strip under the title: the count on a dot display and the search on a screen (the routing objective
## is the Shipments and Stockpiles panel's). Returns {row, count, search}.
static func toolbar(on_search: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "LedgerToolbar"
	row.add_theme_constant_override("separation", 14)
	var count: Control = DotMatrix.new()
	count.name = "CountDisplay"
	count.set("pitch", COUNT_PITCH)
	count.set("align", HORIZONTAL_ALIGNMENT_LEFT)
	count.custom_minimum_size.x = 170.0
	row.add_child(count)
	var screen := _search_screen(on_search)
	row.add_child(screen)
	return {"row": row, "count": count, "search": screen.get_meta("edit")}


## The search field on one of Building Detail's mini screens: white print on the dark glass.
static func _search_screen(on_search: Callable) -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "SearchScreen"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 3.0)
	inset.content_margin_left += 6.0
	screen.add_theme_stylebox_override("panel", inset)
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE
	screen.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, screen.size)
		Nine.paint(screen, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)
		screen.draw_rect(r.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE))
	screen.resized.connect(screen.queue_redraw)
	var edit := LineEdit.new()
	edit.name = "Search"
	edit.placeholder_text = "Search name or output"
	edit.clear_button_enabled = true
	edit.custom_minimum_size = Vector2(200, SEARCH_H - 2.0 * (DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 3.0))
	edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	edit.add_theme_font_override("font", UIFonts.PLEX_MED)
	edit.add_theme_font_size_override("font_size", Parts.BODY_PX)
	edit.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	edit.add_theme_color_override("font_placeholder_color", Color(DS.PALETTE["TEXT"], 0.72))
	edit.add_theme_color_override("caret_color", DS.PALETTE["ACCENT"])
	edit.text_changed.connect(on_search)
	screen.add_child(edit)
	screen.set_meta("edit", edit)
	return screen


## The filter keys on the tile view's key bed, a row each. Returns {bed, keys: {filter key: LatchKey}}.
static func filters(on_filter: Callable) -> Dictionary:
	var bed := PanelContainer.new()
	bed.name = "FilterBed"
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_right = 10
	pad.content_margin_top = 10
	pad.content_margin_bottom = 12
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / LAYOUT), (KEYBED_MARGIN + KEYBED_CORNER) * TEXELS))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	bed.add_child(stack)
	var keys := {}
	for specs: Array in FILTER_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		stack.add_child(line)
		for spec: Array in specs:
			var id := str(spec[0])
			var key: Control = LatchKey.new()
			key.name = "Filter_%s" % id
			key.set("text", str(spec[1]))
			key.connect("pressed", func() -> void: on_filter.call(id))
			keys[id] = key
			line.add_child(key)
	return {"bed": bed, "keys": keys}


## The rubber seam where the fixed part meets the scrolling table, out to the backing's trim.
static func seam() -> Control:
	var s: Control = Seam.new()
	s.name = "LedgerSeam"
	s.custom_minimum_size.y = Seam.strip_height()
	s.set("outset", CONTENT_MARGIN - (4.0 + BACKING_TRIM) / Seam.CAPTURE_SCALE - 0.5)
	return s


## The column headings, inset as the modules' columns are so each stands over its column. A sortable
## heading takes clicks (`on_sort` with its key). Returns {row, cells: {key: Label}, marks: {key: Control}}.
static func heading_row(on_sort: Callable) -> Dictionary:
	var wrap := MarginContainer.new()
	wrap.name = "LedgerHeadings"
	var left := roundi(Parts.case_margin() + Parts.PAD.x)
	wrap.add_theme_constant_override("margin_left", left)
	wrap.add_theme_constant_override("margin_right", left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	wrap.add_child(row)
	var cells := {}
	var marks := {}
	for col: Dictionary in COLUMNS:
		var key := str(col.key)
		var cell := HBoxContainer.new()
		cell.custom_minimum_size.x = float(col.w)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 5)
		var l := Parts.caption(str(col.label), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(l)
		var mark := SortMark.new()
		mark.visible = false
		cell.add_child(mark)
		cells[key] = l
		marks[key] = mark
		if bool(col.sort):
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			cell.gui_input.connect(func(e: InputEvent) -> void:
				var mb := e as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					on_sort.call(key))
		row.add_child(cell)
	return {"row": wrap, "cells": cells, "marks": marks}


## The sorted column's heading in cream with its mark pointing the way the order runs; the others white.
static func show_sort(cells: Dictionary, marks: Dictionary, sort_key: String, ascending: bool) -> void:
	for key in cells:
		var active: bool = key == sort_key
		(cells[key] as Label).add_theme_color_override("font_color", DS.PALETTE["ACCENT"] if active else DS.PALETTE["TEXT"])
		var mark: Control = marks[key]
		mark.visible = active
		mark.set("up", ascending)


## The table: one plastic case in a scroll on Building Detail's steel rail. Returns {scroll, rows}.
static func table() -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.name = "LedgerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Scroll.apply(scroll, true)
	var case := Parts.plastic_case("LedgerCase")
	scroll.add_child(case)
	return {"scroll": scroll, "rows": case.get_child(0)}


# --- a row -------------------------------------------------------------------------------------

## A building's module. `vm` is the panel's row model; `on_logistics` opens the building's logistics (a
## Source or Destination pressed); `digits` the cells every money screen in the table takes; `on_open`
## opens the building.
static func row(vm: Dictionary, on_logistics: Callable, digits: int, on_open: Callable, on_upgrade: Callable) -> PanelContainer:
	var m := Parts.module("LedgerRow_%s" % str(vm.instance_id))
	m.custom_minimum_size.y = Metrics.CARD_H
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	Parts.on_click(m, on_open)
	var line := Parts.row_of(m)
	line.add_theme_constant_override("separation", COL_GAP)
	for col: Dictionary in COLUMNS:
		line.add_child(_cell(str(col.key), float(col.w), vm, on_logistics, digits, on_upgrade))
	return m


static func _cell(key: String, w: float, vm: Dictionary, on_logistics: Callable, digits: int, on_upgrade: Callable) -> Control:
	match key:
		"emblem":
			return _boxed(Parts.emblem(str(vm.building_id), EMBLEM_PX), w)
		"name":
			return _name_cell(vm, w)
		"output":
			var gid := str(vm.out_good_id)
			if gid == "":
				return Parts.spacer(w, 0)
			return _boxed(Parts.good_in_well(gid, int(vm.out_qty), Parts.output_tip(gid, int(vm.out_qty)), true, WELL_PX), w)
		"logistics_inputs", "logistics_outputs":
			return route_cell(vm, "input" if key == "logistics_inputs" else "output", w, on_logistics)
		"power":
			return _lamp_cell(str(vm.power.get("tone", "")), str(vm.power.get("figure", "")), str(vm.power.get("words", "")), w)
		"status":
			var word := str(vm.status.text)
			return _lamp_cell(str(STATUS_TONES.get(word, "")), word if word != "—" else "", "", w)
		"cost":
			if float(vm.cost_value) < 0.0:
				return Parts.spacer(w, 0)
			return _boxed(Parts.money("%.2f" % float(vm.cost_value), vm.cost_color, digits), w)
		"net":
			if is_nan(float(vm.net_value)):
				return Parts.spacer(w, 0)
			return _boxed(Parts.money("%.0f" % float(vm.net_value), vm.net_color, digits), w)
		"land":
			var l := Parts.body(str(vm.land))
			l.custom_minimum_size.x = w
			l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return l
		"upgrade":
			return _upgrade_key(vm, w, on_upgrade)
	return Parts.spacer(w, 0)


## The Source or Destination column (`side` input or output): the kinds of place, grouped (ROUTE_ICONS).
static func route_cell(vm: Dictionary, side: String, w: float, on_logistics: Callable) -> Control:
	var routes: Array = RoutesView.endpoints(BuildingState.get_building(str(vm.instance_id)), side)
	if routes.is_empty():
		return Parts.spacer(w, 0)
	var groups := {}
	var order: Array = []
	for r: Dictionary in routes:
		var kind := str(r.icon)
		if not groups.has(kind):
			groups[kind] = []
			order.append(kind)
		(groups[kind] as Array).append(str(r.label))
	var ranked := order.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var na: int = (groups[a] as Array).size()
		var nb: int = (groups[b] as Array).size()
		return na > nb if na != nb else order.find(a) < order.find(b))
	var shown := ranked.slice(0, ROUTE_KINDS)
	var px := float(Metrics.GOOD_ICON) if shown.size() == 1 else ROUTE_SMALL
	var cell := VBoxContainer.new()
	cell.name = "Source" if side == "input" else "Destination"
	cell.custom_minimum_size.x = w
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 4)
	var tip: PackedStringArray = []
	for kind in order:
		for label in groups[kind]:
			tip.append(str(label))
	cell.tooltip_text = "\n".join(tip)
	Parts.on_click(cell, on_logistics)
	var line: HBoxContainer = null
	for i in shown.size():
		if i % 2 == 0:
			line = HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			line.add_theme_constant_override("separation", 4)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(line)
		line.add_child(_route_icon(str(shown[i]), (groups[shown[i]] as Array).size(), px))
	return cell


## A kind of place `px` square: its raised icon, or the building's emblem, with how many when more than one.
static func _route_icon(kind: String, count: int, px: float) -> Control:
	var holder := Control.new()
	holder.name = "Route_%s" % kind
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art: Control = Parts.raised(str(ROUTE_ICONS[kind]), px) if ROUTE_ICONS.has(kind) else Parts.emblem(kind, px)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(art)
	if count > 1:
		holder.add_child(Parts.pill(count, px < float(Metrics.GOOD_ICON)))
	return holder


## `child` centred in a column `w` wide.
static func _boxed(child: Control, w: float) -> CenterContainer:
	var box := CenterContainer.new()
	box.custom_minimum_size.x = w
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(child)
	return box


## The building's name (semibold) over its tile's name.
static func _name_cell(vm: Dictionary, w: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = w
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Parts.body(str(vm.name))
	name.name = "Name"
	name.add_theme_font_override("font", Parts.FONT_TITLE)
	name.custom_minimum_size.x = w
	col.add_child(name)
	var tile := Parts.body(str(vm.tile_name))
	tile.name = "Tile"
	tile.custom_minimum_size.x = w
	col.add_child(tile)
	return col


## A lamp in `tone`, then a figure and, under it, a word. Blank with no figure.
static func _lamp_cell(tone: String, figure: String, words: String, w: float) -> Control:
	if figure == "":
		return Parts.spacer(w, 0)
	var line := HBoxContainer.new()
	line.custom_minimum_size.x = w
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_constant_override("separation", Parts.LAMP_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tone != "":
		var lamp: Control = Lamp.new()
		lamp.name = "Lamp"
		lamp.set("lamp_scale", Parts.LAMP_SCALE)
		lamp.call("set_tone", tone)
		lamp.set_meta("tone", tone)
		line.add_child(lamp)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var f := Parts.body(figure)
	f.name = "Figure"
	f.add_theme_font_override("font", Parts.FONT_TITLE)
	f.autowrap_mode = TextServer.AUTOWRAP_OFF
	f.custom_minimum_size.x = 0
	text.add_child(f)
	if words != "":
		var said := Parts.body(words)
		said.name = "Words"
		said.autowrap_mode = TextServer.AUTOWRAP_OFF
		said.custom_minimum_size.x = 0
		text.add_child(said)
	return line


## The Upgrade key, naming the level it raises the building to ("Upgrade to Lvl 2"): its card is Building
## Detail's Upgrade key's (the dot card: what the next level brings and what it takes). Spent at the top
## level, and for infrastructure, which the Transport tab raises.
static func _upgrade_key(vm: Dictionary, w: float, on_upgrade: Callable) -> Control:
	var level := int(vm.level)
	var top := level >= BuildingLevels.MAX_LEVEL
	var words := "Max level" if top else "Upgrade to Lvl %d" % (level + 1)
	# One print size down the column: the longest words a key there says.
	var k := minf(1.0, w / maxf(1.0, CreamKey.width_for("Upgrade to Lvl %d" % BuildingLevels.MAX_LEVEL, "", false, false)))
	var key: Button = CreamKey.make("Upgrade_%s" % str(vm.instance_id), words, "", w, false, false, k)
	key.mouse_filter = Control.MOUSE_FILTER_STOP
	var building := BuildingState.get_building(str(vm.instance_id))
	var card: Dictionary = load("res://scripts/building_detail_panel_v2.gd").v3_upgrade_tip(building)
	if not card.is_empty():
		DotCard.attach(key, card)
	if top or str(vm.category) == "infrastructure":
		key.call("set_spent", true)
	else:
		key.pressed.connect(func() -> void: on_upgrade.call(str(vm.instance_id)))
	return _boxed(key, w)


## The cells the widest money figure among `vms` takes, so every screen in the table is one width.
static func money_digits(vms: Array) -> int:
	var d := 4
	for vm: Dictionary in vms:
		if float(vm.cost_value) >= 0.0:
			d = maxi(d, Led.cells_for("%.2f" % float(vm.cost_value)).size())
		if not is_nan(float(vm.net_value)):
			d = maxi(d, Led.cells_for("%.0f" % float(vm.net_value)).size())
	return d


## The count on the display: every building, or how many of them the filters show.
static func count_text(shown: int, total: int) -> String:
	if shown == total:
		return "%d BUILDING%s" % [total, "" if total == 1 else "S"]
	return "%d/%d SHOWN" % [shown, total]


## A small cream triangle beside the sorted column's heading, pointing up while the order runs up.
class SortMark extends Control:
	var up := true:
		set(v):
			up = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(9, 9)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(w * 0.5, 0)]) if up \
			else PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, h)])
		draw_colored_polygon(pts, DS.PALETTE["ACCENT"])
