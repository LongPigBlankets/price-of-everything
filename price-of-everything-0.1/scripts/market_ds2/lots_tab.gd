extends VBoxContainer
## DS2 market, Buildings: the lots for sale, sorted by the building's name by default (decision 14), sortable by
## building, owner or price from the headings, and a Sort by owner key over the list. Sorted by owner, each
## company's name stands as a raised heading over its lots (as studied) and the rows leave the owner out; with
## any other sort there are no headings and the Owner column names each lot's owner. A lot is a module: the building's emblem in polished metal, its name
## over its place, its owner, what it makes in a well with the quantity on its pill, its price on a red LED
## (whole pounds, as charged) and a guarded Buy key (decision 13): the first click lifts the cover, the second
## buys, at the price shown (building_market_panel.gd buy_lot, the Buildings tab's own buy). Clicking a lot
## opens the building. Over the list, the search on a screen and, when opened from a tile's Buy Buildings, a tag
## naming the tile with a key that clears it. The list shows PAGE lots at a time, Show more under it.

signal lot_opened(instance_id: String)

const BuildingMarketTab := preload("res://scripts/building_market_panel.gd")
const MarketRules := preload("res://scripts/market_rules.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")

const COL_GAP := 8
const GUARD_PX := 40.0
const PAGE := 40
const COLUMNS := [
	["emblem", "", 58.0, false],
	["name", "Building", 196.0, true],
	["owner", "Owner", 150.0, true],
	["output", "Makes", float(Metrics.GOOD_ICON), false],
	["price", "Price", 0.0, true],
	["buy", "", 52.0, false],
]
const RED := Color("#ff4d3d")

var _search := ""
var _tile := ""
var _sort_key := "name"
var _ascending := true
var _cells: Dictionary = {}
var _marks: Dictionary = {}
var _rows: VBoxContainer
var _lots: Array = []
var _limit := PAGE
var _tag: HBoxContainer
var _tag_label: Label
var _owner_key: Control


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var screen: Control = LedgerV3._search_screen(func(t: String) -> void:
		_search = t.strip_edges().to_lower()
		_limit = PAGE
		render())
	(screen.get_meta("edit") as LineEdit).placeholder_text = "Search building, place, output or owner"
	bar.add_child(screen)
	_tag = HBoxContainer.new()
	_tag.name = "TileTag"
	_tag.add_theme_constant_override("separation", 8)
	_tag_label = Parts.body("")
	_tag_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tag_label.custom_minimum_size.x = 0
	_tag.add_child(_tag_label)
	var clear := Parts.key_button("Show all", "ClearTile", 0.8)
	clear.custom_minimum_size.x = 110
	clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	clear.pressed.connect(func() -> void: set_tile_filter(""))
	_tag.add_child(clear)
	_tag.visible = false
	bar.add_child(_tag)
	bar.add_child(_owner_bed())
	add_child(bar)
	add_child(_headings())
	var t := LedgerV3.table()
	t.scroll.name = "LotsScroll"
	_rows = t.rows
	add_child(t.scroll)


static func column_width(col: Array) -> float:
	return float(col[2]) if float(col[2]) > 0.0 else MParts.money_width(MParts.MONEY_CELLS)


## How many lots are for sale (the key strip's figure): other companies' buildings that aren't infrastructure.
static func lot_count() -> int:
	var n := 0
	for b: Variant in BuildingState.buildings.values():
		var building: Dictionary = b
		if not BuildingState.is_player_owned(building) and not BuildingMarketTab._is_infrastructure(building):
			n += 1
	return n


## The Sort by owner key on its key bed: down while the lots are grouped under their owners.
func _owner_bed() -> PanelContainer:
	var bed := PanelContainer.new()
	bed.name = "OwnerBed"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(8)
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, LedgerV3.KEYBED, Rect2(Vector2.ZERO, bed.size).grow(LedgerV3.KEYBED_MARGIN / LedgerV3.LAYOUT),
			(LedgerV3.KEYBED_MARGIN + LedgerV3.KEYBED_CORNER) * LedgerV3.TEXELS))
	_owner_key = LatchKey.new()
	_owner_key.name = "SortByOwner"
	_owner_key.set("text", "Sort by owner")
	_owner_key.custom_minimum_size.x = 150.0
	_owner_key.connect("pressed", func() -> void: set_by_owner(_sort_key != "owner"))
	bed.add_child(_owner_key)
	return bed


## Groups the lots under their owners (sorted by owner), or back to the default, by the building's name.
func set_by_owner(on: bool) -> void:
	_sort_key = "owner" if on else "name"
	_ascending = true
	render()


func sort_key() -> String:
	return _sort_key


func grouped() -> bool:
	return _sort_key == "owner"


func set_tile_filter(tile_id: String) -> void:
	_tile = tile_id
	_tag.visible = tile_id != ""
	_tag_label.text = "On %s" % MarketRules.place_name(tile_id) if tile_id != "" else ""
	_limit = PAGE
	refresh()


func tile_filter() -> String:
	return _tile


func _headings() -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.name = "LotsHeadings"
	var left := roundi(Parts.case_margin() + Parts.PAD.x)
	wrap.add_theme_constant_override("margin_left", left)
	wrap.add_theme_constant_override("margin_right", left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	wrap.add_child(row)
	for col: Array in COLUMNS:
		var key := str(col[0])
		var cell := HBoxContainer.new()
		cell.custom_minimum_size.x = column_width(col)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 4)
		var l := Parts.caption(str(col[1]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(l)
		var mark: Control = LedgerV3.SortMark.new()
		mark.visible = false
		cell.add_child(mark)
		_cells[key] = l
		_marks[key] = mark
		if bool(col[3]):
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			cell.gui_input.connect(func(e: InputEvent) -> void:
				var mb := e as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					sort_by(key))
		row.add_child(cell)
	return wrap


func sort_by(key: String) -> void:
	if key == _sort_key:
		_ascending = not _ascending
	else:
		_sort_key = key
		_ascending = true
	render()


func refresh() -> void:
	_lots = BuildingMarketTab.lots(_tile)
	render()


func shown_lots() -> Array:
	var out: Array = _lots.filter(func(vm: Dictionary) -> bool: return _search == "" or str(vm.blob).contains(_search))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: Variant = int(a.price) if _sort_key == "price" else str(a.get(_sort_key, "")).to_lower()
		var vb: Variant = int(b.price) if _sort_key == "price" else str(b.get(_sort_key, "")).to_lower()
		if va == vb:
			return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
		return va < vb if _ascending else va > vb)
	return out


func render() -> void:
	LedgerV3.show_sort(_cells, _marks, _sort_key, _ascending)
	if _owner_key != null:
		_owner_key.set("latched", grouped())
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var shown := shown_lots()
	var owner := ""
	for i in mini(_limit, shown.size()):
		if grouped() and str(shown[i].owner) != owner:
			owner = str(shown[i].owner)
			_rows.add_child(_owner_heading(owner))
		_rows.add_child(_lot(shown[i]))
	if shown.is_empty():
		var none := Parts.body("No buildings for sale here." if _tile != "" else "No buildings for sale.")
		none.name = "NoLots"
		_rows.add_child(none)
	elif shown.size() > _limit:
		var more := Parts.key_button("Show %d more of %d" % [mini(PAGE, shown.size() - _limit), shown.size() - _limit], "ShowMore", 0.8)
		more.pressed.connect(func() -> void:
			_limit += PAGE
			render())
		_rows.add_child(more)


## A company's name raised as a heading over its lots.
func _owner_heading(owner: String) -> Control:
	var wrap := MarginContainer.new()
	wrap.name = "OwnerHeading"
	wrap.add_theme_constant_override("margin_top", 6)
	wrap.add_theme_constant_override("margin_left", 4)
	wrap.set_meta("owner", owner)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(Parts.heading(owner.to_upper()))
	return wrap


func _lot(vm: Dictionary) -> PanelContainer:
	var iid := str(vm.instance_id)
	var m := Parts.module("Lot_%s" % iid)
	m.custom_minimum_size.y = Metrics.CARD_H
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	Parts.on_click(m, func() -> void: lot_opened.emit(iid))
	var line := Parts.row_of(m)
	line.add_theme_constant_override("separation", COL_GAP)
	for col: Array in COLUMNS:
		line.add_child(_cell(str(col[0]), column_width(col), vm))
	return m


func _cell(key: String, w: float, vm: Dictionary) -> Control:
	match key:
		"emblem":
			return LedgerV3._boxed(Parts.emblem(str(vm.building_id), Parts.EMBLEM_PX), w)
		"name":
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
			var place := Parts.body(MarketRules.place_name(str(vm.tile_id)))
			place.name = "Place"
			place.custom_minimum_size.x = w
			col.add_child(place)
			return col
		"owner":
			var o := Parts.body("" if grouped() else str(vm.owner))
			o.name = "Owner"
			o.custom_minimum_size.x = w
			o.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return o
		"output":
			if str(vm.out_good_id) == "":
				return Parts.spacer(w, 0)
			return LedgerV3._boxed(Parts.good_in_well(str(vm.out_good_id), int(vm.out_qty), Parts.output_tip(str(vm.out_good_id), int(vm.out_qty)), true, Metrics.GOOD_ICON), w)
		"price":
			var box := LedgerV3._boxed(MParts.money(float(vm.price), RED, MParts.MONEY_CELLS, false, true), w)
			box.name = "Price"
			return box
		"buy":
			var guard: Control = GuardKey.new(GUARD_PX)
			guard.name = "BuyLot"
			guard.set("tip", {"stage": "Buy", "name": str(vm.name), "detail": "Lift the cover, then press to buy for %s." % MParts.MoneyFigure.display_text(float(vm.price)), "tone": ""})
			guard.set_meta("instance_id", str(vm.instance_id))
			guard.connect("pressed", func() -> void: buy(str(vm.instance_id)))
			var holder := MarginContainer.new()
			holder.custom_minimum_size.x = w
			holder.add_theme_constant_override("margin_top", ceili(GuardKey.overhang(GUARD_PX)))
			holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var c := CenterContainer.new()
			c.add_child(guard)
			holder.add_child(c)
			return holder
	return Parts.spacer(w, 0)


## Buys a lot at the price its row shows; the list drops it.
func buy(instance_id: String) -> bool:
	for vm: Dictionary in _lots:
		if str(vm.instance_id) == instance_id:
			var ok := BuildingMarketTab.buy_lot(instance_id, str(vm.name), int(vm.price))
			if ok:
				refresh()
			return ok
	return false
