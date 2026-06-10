extends VBoxContainer
## Self-contained stockpile visualisation: a "Stored X / Y" readout, a coloured
## unit-block grid, and a per-good legend. Point it at a tile with set_tile();
## it refreshes itself whenever the global Stockpile changes. Pure display — it
## reads Stockpile/Catalog/Production and never mutates state.
##
## Extracted from the tile panel (Slice A). The stockpile *controls* (sell
## button, sell-surplus toggle, production-destination dropdown) stay in the
## panel; this widget is only the read-out.

class StockpileUnitBlock:
	extends Control
	var fill_color := Color(0.44, 0.48, 0.5, 0.22)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), fill_color, true)

const VISUAL_HEIGHT := 100.0
const VISUAL_COLUMNS := 25
const LEGEND_SWATCH_SIZE := Vector2(20, 20)
const LEGEND_MAX_HEIGHT := 48.0
const GOOD_LABEL_MAX_CHARS := 12
const UNUSED_FILL := Color(0.44, 0.48, 0.5, 0.22)
const COLOR_PALETTE := [
	Color(0.13, 0.55, 0.13, 0.92),
	Color(0.95, 0.83, 0.18, 0.92),
	Color(0.47, 0.78, 1.0, 0.92),
	Color(0.55, 0.35, 0.88, 0.92),
	Color(0.22, 0.22, 0.22, 0.92),
	Color(0.95, 0.48, 0.14, 0.92),
	Color(0.48, 0.90, 0.72, 0.92),
	Color(0.25, 0.41, 0.88, 0.92),
]

var _tile_id: String = ""
var _capacity_label: Label = null
var _visual: Panel = null
var _legend: HFlowContainer = null

func _ready() -> void:
	add_theme_constant_override("separation", 8)

	_capacity_label = Label.new()
	_capacity_label.text = "Stored 0 / %d" % Stockpile.get_capacity("")
	_capacity_label.theme_type_variation = &"Body"
	add_child(_capacity_label)

	_visual = Panel.new()
	_visual.custom_minimum_size = Vector2(0, VISUAL_HEIGHT)
	_visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_visual.clip_contents = true
	_visual.mouse_filter = Control.MOUSE_FILTER_STOP
	_visual.resized.connect(_rebuild_visual)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.09, 0.82)
	style.border_color = Color(0.7, 0.85, 1.0, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	_visual.add_theme_stylebox_override("panel", style)
	add_child(_visual)

	_legend = HFlowContainer.new()
	_legend.custom_minimum_size = Vector2(0, LEGEND_MAX_HEIGHT)
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend.clip_contents = true
	_legend.add_theme_constant_override("h_separation", 12)
	_legend.add_theme_constant_override("v_separation", 4)
	add_child(_legend)

	Stockpile.stockpile_changed.connect(_on_stockpile_changed)

func set_tile(tile_id: String) -> void:
	_tile_id = tile_id
	refresh()

func refresh() -> void:
	if _capacity_label == null:
		return
	var used: int = Stockpile.get_used_capacity(_tile_id)
	var capacity: int = Stockpile.get_capacity(_tile_id)
	_capacity_label.text = "Stored %d / %d" % [used, capacity]

	for child in _legend.get_children():
		child.queue_free()

	var committed: Dictionary = Production.compute_committed_for_tile(_tile_id)
	_visual.tooltip_text = _tooltip_text(committed)
	var rows := _sorted_rows()
	if rows.is_empty():
		_legend.add_child(_make_row("No goods stored"))
	else:
		for row in rows:
			var good_id: String = row.get("good_id", "")
			_legend.add_child(_make_row(Catalog.get_display_name(good_id), good_id))

	_rebuild_visual()

func _on_stockpile_changed() -> void:
	if is_visible_in_tree() and _tile_id != "":
		refresh()

func _rebuild_visual() -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		child.queue_free()

	var capacity := Stockpile.get_capacity(_tile_id)
	if capacity <= 0:
		return

	var visual_width := maxf(maxf(_visual.size.x, _visual.custom_minimum_size.x), 1.0)
	var visual_height := maxf(maxf(_visual.size.y, VISUAL_HEIGHT), 1.0)
	var columns := mini(VISUAL_COLUMNS, capacity)
	columns = maxi(1, columns)
	var rows := maxi(1, ceili(float(capacity) / float(columns)))
	var unit_size := Vector2(visual_width / float(columns), visual_height / float(rows))

	var block_index := 0
	for row in _sorted_rows():
		var good_id: String = row.get("good_id", "")
		var qty: int = int(row.get("qty", 0))
		var color := _color_for_good(good_id)
		for _i in range(qty):
			if block_index >= capacity:
				return
			_add_block(color, block_index, columns, unit_size)
			block_index += 1

	while block_index < capacity:
		_add_block(UNUSED_FILL, block_index, columns, unit_size)
		block_index += 1

func _add_block(color: Color, block_index: int, columns: int, unit_size: Vector2) -> void:
	var block := StockpileUnitBlock.new()
	block.fill_color = color
	block.position = Vector2(
		float(block_index % columns) * unit_size.x,
		floorf(float(block_index) / float(columns)) * unit_size.y
	)
	block.size = unit_size
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(block)

func _tooltip_text(committed: Dictionary) -> String:
	var rows := _sorted_rows()
	var lines: Array[String] = []
	if rows.is_empty():
		lines.append("No goods stored")
	else:
		lines.append("Top goods on this tile")
		var limit := mini(10, rows.size())
		for i in range(limit):
			var row: Dictionary = rows[i]
			var good_id: String = row.get("good_id", "")
			var qty := int(row.get("qty", 0))
			var committed_qty := int(committed.get(good_id, 0))
			var surplus := maxi(0, qty - committed_qty)
			lines.append("%s: %d (%d)" % [Catalog.get_display_name(good_id), qty, surplus])
	lines.append("")
	lines.append("Brackets show surplus that will not be used this turn")
	return "\n".join(lines)

func _sorted_rows() -> Array:
	var rows: Array = []
	var totals: Dictionary = Stockpile.get_tile_totals(_tile_id)
	for good_id in totals.keys():
		var qty: int = int(totals[good_id])
		if qty > 0:
			rows.append({"good_id": good_id, "qty": qty})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.qty) == int(b.qty):
			return str(a.good_id) < str(b.good_id)
		return int(a.qty) > int(b.qty)
	)
	return rows

func _make_row(text: String, good_id: String = "") -> Control:
	# Row sizes to its content so the colour swatch sits right next to the good
	# name (a fixed-width label pushed the swatch too far away to read as linked).
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, LEGEND_SWATCH_SIZE.y)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", 5)

	var label := Label.new()
	label.text = _truncate(text)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"Caption"
	label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	label.custom_minimum_size = Vector2(0, LEGEND_SWATCH_SIZE.y)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)

	if good_id != "":
		var swatch := ColorRect.new()
		swatch.color = _color_for_good(good_id)
		swatch.custom_minimum_size = LEGEND_SWATCH_SIZE
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
	return row

func _truncate(good_name: String) -> String:
	if good_name.length() > GOOD_LABEL_MAX_CHARS:
		return "%s..." % good_name.substr(0, GOOD_LABEL_MAX_CHARS - 1)
	return good_name

func _color_for_good(good_id: String) -> Color:
	var index := _color_index(good_id)
	if index >= 0 and index < COLOR_PALETTE.size():
		return COLOR_PALETTE[index]
	return _generated_color(good_id)

func _color_index(good_id: String) -> int:
	var goods := Catalog.all_goods()
	for i in goods.size():
		var good: Dictionary = goods[i]
		if good.get("id", "") == good_id:
			return i
	return -1

func _generated_color(good_id: String) -> Color:
	var color_seed := 0
	for i in good_id.length():
		color_seed += good_id.unicode_at(i) * (i + 1)
	var hue := fmod((float((color_seed * 37) % 360) / 360.0) + 0.09, 1.0)
	if hue > 0.55 and hue < 0.68:
		hue = fmod(hue + 0.18, 1.0)
	return Color.from_hsv(hue, 0.62, 0.92, 0.92)
