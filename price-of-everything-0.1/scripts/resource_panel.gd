extends PanelContainer
## Resources panel: the economy table of every good — what you hold, what it costs you to
## make, what you made and burned last turn, and what the carbon levy takes per unit.
##
## Rows expand (owner 2026-08-24). A good's freight is the number players actually plan
## around and it lived nowhere in the UI; opening a row shows what one unit costs to move
## one tile on each mode the good is allowed to use, at each infrastructure level, plus
## what a port takes. Every figure on this panel is per unit.
##
## Every freight figure comes from TransportService, which owns the cost model — a panel
## with its own copy of the leg maths is how a UI starts quoting a price the sim will not
## charge, and the suite has a boundary test that says so.

const PipeFrame := preload("res://scripts/pipe_frame.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const HEADER_HEIGHT := 40.0
const ICON_SIZE := 44
const COL_NUM := 104          # every numeric column
const COL_NAME := 210
const MODE_LABELS := {
	"roads": "Road", "rail": "Rail", "pipes": "Pipe", "reinf_pipes": "Reinforced pipe",
}
const MODE_ORDER := ["rail", "roads", "pipes", "reinf_pipes"]

var _dragging := false
var _drag_offset := Vector2.ZERO
var _expanded: Dictionary = {}       # good_id -> bool
var _detail_boxes: Dictionary = {}   # good_id -> the detail Control under its row

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Resources"
	# The chrome every other panel wears, instead of this one's own navy box.
	add_theme_stylebox_override("panel", PipeFrame.dark_brown_stylebox(10.0))
	_add_goods_graph_button()
	_build_header_row()
	_build_panel_content()
	Stockpile.stockpile_changed.connect(_refresh_values)
	CostSolver.costs_updated.connect(_refresh_values)
	TurnManager.turn_advanced.connect(func(_t: int) -> void: _refresh_values())

## Header shortcut into the full-screen Goods Graph (the web this table is a flat
## view of). Routed through MatchState so this panel needs no reference to the view.
func _add_goods_graph_button() -> void:
	var btn := Button.new()
	btn.text = "Goods Graph"
	btn.tooltip_text = "Open the goods production web (G)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.theme_type_variation = &"Primary"
	btn.pressed.connect(func() -> void: MatchState.goods_graph_requested.emit())
	var header := close_button.get_parent()
	header.add_child(btn)
	header.move_child(btn, close_button.get_index())


## The static column headings, rebuilt in code so the columns cannot drift from the rows.
func _build_header_row() -> void:
	var old := $MarginContainer/VBoxContainer/HeaderRowStatic as HBoxContainer
	for child in old.get_children():
		child.queue_free()
	old.add_theme_constant_override("separation", 10)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(ICON_SIZE, 0)
	old.add_child(spacer)
	old.add_child(_head("Good", COL_NAME, HORIZONTAL_ALIGNMENT_LEFT, true))
	for title: String in ["Stock", "Cost/unit", "Produced", "Consumed", "Carbon tax"]:
		old.add_child(_head(title, COL_NUM, HORIZONTAL_ALIGNMENT_RIGHT, false))
	# The one caption the whole panel needs, in the corner where a table's unit note goes.
	var note := Label.new()
	note.text = "All costs are per unit"
	note.theme_type_variation = &"Caption"
	note.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.custom_minimum_size = Vector2(190, 0)
	old.add_child(note)


func _head(text: String, width: int, align: int, expand: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"Section"
	lbl.horizontal_alignment = align
	lbl.custom_minimum_size = Vector2(width, 0)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _build_panel_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	_detail_boxes.clear()
	content_vbox.add_theme_constant_override("separation", 2)
	for good_data: Variant in MatchState.visible_goods():
		_add_good(good_data as Dictionary)


func _add_good(good: Dictionary) -> void:
	var gid := str(good.get("id", ""))
	var group := VBoxContainer.new()
	group.name = "Good_%s" % gid
	group.add_theme_constant_override("separation", 0)
	content_vbox.add_child(group)

	var row := Button.new()
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.custom_minimum_size = Vector2(0, ICON_SIZE + 10)
	row.tooltip_text = "Show what it costs to move %s" % str(good.get("display_name", gid))
	row.pressed.connect(_toggle_good.bind(gid))
	group.add_child(row)

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	# The good's own chip: cream ground, rounded corners, no metal frame.
	var chip := UIHelpers.make_plain_good_icon(gid, str(good.get("internal_name", "")), ICON_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)

	var name_lbl := Label.new()
	name_lbl.text = str(good.get("display_name", gid))
	name_lbl.theme_type_variation = &"Body"
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COL_NAME, 0)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_lbl)

	for key: String in ["stock", "cost", "produced", "consumed", "carbon"]:
		var val := Label.new()
		val.name = "Val_%s" % key
		val.theme_type_variation = &"Numeric"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(COL_NUM, 0)
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(val)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(190, 0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tail)

	var detail := _build_detail(good)
	detail.visible = bool(_expanded.get(gid, false))
	group.add_child(detail)
	_detail_boxes[gid] = detail
	_refresh_row(group, gid)


func _toggle_good(gid: String) -> void:
	_expanded[gid] = not bool(_expanded.get(gid, false))
	var detail := _detail_boxes.get(gid) as Control
	if detail != null:
		detail.visible = bool(_expanded[gid])


# ── The row's five figures ───────────────────────────────────────────────────────────
func _refresh_values() -> void:
	for child in content_vbox.get_children():
		var gid := str(child.name).trim_prefix("Good_")
		if gid != "":
			_refresh_row(child as Node, gid)


func _refresh_row(group: Node, gid: String) -> void:
	var line: Node = group.get_child(0).get_child(0) if group.get_child_count() > 0 else null
	if line == null:
		return
	var summary: Dictionary = Production.last_turn_summary
	var produced := int((summary.get("produced", {}) as Dictionary).get(gid, 0))
	var consumed := int((summary.get("consumed", {}) as Dictionary).get(gid, 0))
	var uc: float = CostSolver.get_good_unit_cost(gid)
	_set_val(line, "stock", _num(Stockpile.get_total(gid)))
	_set_val(line, "cost", "--" if uc < 0.0 else "£%.2f" % uc)
	_set_val(line, "produced", _num(produced) if produced > 0 else "—")
	_set_val(line, "consumed", _num(consumed) if consumed > 0 else "—")
	var carbon := _carbon_per_unit(gid)
	_set_val(line, "carbon", "—" if carbon <= 0.0 else "£%.2f" % carbon)


func _set_val(line: Node, key: String, text: String) -> void:
	var lbl := line.get_node_or_null("Val_%s" % key) as Label
	if lbl != null:
		lbl.text = text


## The levy one unit of this good pays when a player building burns it, at today's phase.
func _carbon_per_unit(gid: String) -> float:
	var mult := float(Catalog.get_good(gid).get("co2_tax_multiplier", 0.0))
	if mult <= 0.0:
		return 0.0
	return mult * EconomyConfig.CO2_TAX_RATE * PolicyState.co2_tax_scale(int(TurnManager.current_turn))


# ── The expanded freight table ───────────────────────────────────────────────────────
func _build_detail(good: Dictionary) -> Control:
	var gid := str(good.get("id", ""))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _inset_style())
	var pad := MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	pad.add_child(box)

	# Power rides cables. It has no freight and no port, and saying so beats an empty table.
	if str(good.get("transport_class", "")) == "power" or str(good.get("internal_name", "")) == "power":
		box.add_child(_note("Power moves on cables — it pays no freight and never crosses a port."))
		return panel

	box.add_child(_note("Freight, £ per unit per tile — a level's range is how far one charged leg reaches."))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	grid.add_child(_cell("Mode", true, HORIZONTAL_ALIGNMENT_LEFT))
	for lvl: int in [1, 2, 3]:
		grid.add_child(_cell("L%d" % lvl, true, HORIZONTAL_ALIGNMENT_RIGHT))
	var allowed: Array = Catalog.modes_for_good(gid)
	var any := false
	for mode: String in MODE_ORDER:
		if not allowed.has(mode):
			continue
		any = true
		grid.add_child(_cell(str(MODE_LABELS.get(mode, mode)), false, HORIZONTAL_ALIGNMENT_LEFT))
		for lvl: int in [1, 2, 3]:
			grid.add_child(_cell("£%.3f" % TransportService.freight_per_tile(gid, mode, lvl),
				false, HORIZONTAL_ALIGNMENT_RIGHT))
	if not any:
		box.add_child(_note("No built infrastructure carries this good."))

	var port := TransportService.port_ad_valorem_per_unit(gid)
	box.add_child(_note("Port: £%.3f per unit shipped — %.2f%% of its market price. The port's
per-shipment fee is charged on top, once per good per turn." % [port.cost, port.rate * 100.0]))
	return panel


func _note(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"Caption"
	lbl.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


func _cell(text: String, head: bool, align: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"Section" if head else &"Numeric"
	lbl.horizontal_alignment = align
	lbl.custom_minimum_size = Vector2(120 if head and align == HORIZONTAL_ALIGNMENT_LEFT else 90, 0)
	return lbl


func _inset_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_INSET
	sb.set_corner_radius_all(6)
	sb.border_color = DS.PALETTE.BORDER_SOFT
	sb.set_border_width_all(1)
	return sb


func _num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
