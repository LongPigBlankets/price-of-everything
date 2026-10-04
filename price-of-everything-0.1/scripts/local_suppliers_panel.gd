extends Control
## The Local Suppliers panel, opened by clicking a Local Suppliers depot on the map (local_suppliers_depots.gd).
## A DS2 cabinet on Building Detail's navy steel backing: the raised title and the Close key, a pair of cream
## keys switching between Outputs (the buildings that send their outputs to Local Suppliers, the default) and
## Inputs (the buildings that still take inputs from them, as their route or as a fallback), and the list.
## Every building of the company is listed, the clicked tile's first; a row opens that building.
## Read only: what each building uses comes from middleman_service.gd.

const Service := preload("res://scripts/middleman_service.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

const BACKING_CORNER := 64.0
const CONTENT_MARGIN := 26
const DIM := Color(0.0, 0.0, 0.0, 0.45)
const LIST_W := 520.0
const LIST_H := 380.0
const KEY_W := 150.0

var _tile_id := ""
var _side := "output"
var _outputs_key: Button
var _inputs_key: Button
var _list: VBoxContainer


static func open(parent: Node, tile_id: String) -> Control:
	var panel: Control = load("res://scripts/local_suppliers_panel.gd").new()
	panel.set("_tile_id", tile_id)
	parent.add_child(panel)
	return panel


func _ready() -> void:
	name = "LocalSuppliersPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed: hide())
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var cabinet := PanelContainer.new()
	cabinet.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	cabinet.add_child(Nine.make("panel_backing", BACKING_CORNER))
	centre.add_child(cabinet)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)
	cabinet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var title: Control = Title.new()
	title.call("set_text", "Local Suppliers")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(hide)
	head.add_child(close)
	col.add_child(head)

	var switch := HBoxContainer.new()
	switch.add_theme_constant_override("separation", 10)
	_outputs_key = CreamKey.make("OutputsKey", "Outputs", "", KEY_W)
	_inputs_key = CreamKey.make("InputsKey", "Inputs", "", KEY_W)
	_outputs_key.pressed.connect(func() -> void: _show("output"))
	_inputs_key.pressed.connect(func() -> void: _show("input"))
	switch.add_child(_outputs_key)
	switch.add_child(_inputs_key)
	col.add_child(switch)

	var section: Control = Section.new()
	section.set("style", "dark")
	col.add_child(section)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	(section.get("content") as VBoxContainer).add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_show(_side)
	PanelStack.push(self)
	visibility_changed.connect(func() -> void:
		if not visible:
			PanelStack.remove(self)
			queue_free())


## Outputs ("output") or inputs ("input"): latch its key and list the buildings.
func _show(side: String) -> void:
	_side = side
	_outputs_key.set("chosen", side == "output")
	_inputs_key.set("chosen", side == "input")
	for child in _list.get_children():
		child.queue_free()
	var rows := rows_for(side, _tile_id)
	if rows.is_empty():
		var none := Label.new()
		none.text = "No building sends its outputs to Local Suppliers." if side == "output" \
			else "No building takes its inputs from Local Suppliers."
		none.theme_type_variation = &"Body"
		none.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		_list.add_child(none)
		return
	for row: Dictionary in rows:
		_list.add_child(_row_button(row))


## A building's row: its name and tile over the goods it trades with Local Suppliers. Opens the building.
func _row_button(row: Dictionary) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.text = "%s, %s\n%s" % [row.name, row.place, row.goods]
	b.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	b.add_theme_color_override("font_hover_color", DS.PALETTE.ACCENT)
	b.add_theme_font_size_override("font_size", 14)
	var iid := str(row.iid)
	b.pressed.connect(func() -> void:
		hide()
		MatchState.focus_building_requested.emit(iid))
	return b


## The company's buildings that trade `side` goods with Local Suppliers, the buildings on `first_tile` first:
## [{iid, name, place, goods}]. Inputs count a fallback as dependence too, marked as such.
static func rows_for(side: String, first_tile: String = "") -> Array:
	var rows: Array = []
	for iid in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[iid]
		if not BuildingState.is_player_owned(b) or not Service.enabled(str(iid)):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		var goods: PackedStringArray = []
		for item: Dictionary in recipe.get("outputs" if side == "output" else "inputs", []):
			var gid := str(item.get("good_id", ""))
			if side == "output" and Service.buys_output(str(iid), gid):
				goods.append(Catalog.get_display_name(gid))
			elif side == "input" and Service.supplies_good(str(iid), gid):
				goods.append(Catalog.get_display_name(gid))
			elif side == "input" and Service.bridges_good(str(iid), gid):
				goods.append("%s (fallback)" % Catalog.get_display_name(gid))
		if goods.is_empty():
			continue
		var tile := str(b.get("tile_id", ""))
		rows.append({"iid": str(iid), "name": BuildingNaming.of(b), "tile": tile, "place": TurnBriefing.place_name(tile),
			"goods": ", ".join(goods)})
	rows.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		if (str(a.tile) == first_tile) != (str(c.tile) == first_tile):
			return str(a.tile) == first_tile
		if str(a.place) != str(c.place):
			return str(a.place) < str(c.place)
		return str(a.name) < str(c.name))
	return rows
