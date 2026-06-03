extends Control

## The off-white goods board on the main menu: a faint 7x7 grid filled with good
## icons. Goods are shuffled into the cells with a light touch to keep an icon
## from sitting next to the same good or another of its category, and the deck is
## reshuffled/cycled whenever there are fewer goods than cells.

const GoodIcons := preload("res://scripts/good_icons.gd")

const COLS := 7
const ROWS := 7
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const GRID_LINE := Color(0.945, 0.876, 0.715)   # barely darker than the off-white
const CELL_PADDING := 0.16                        # share of each cell kept as margin

var _layout: Array = []   # one good dict (or null) per cell


func _ready() -> void:
	_arrange_cells()
	resized.connect(_relayout_icons)
	call_deferred("_relayout_icons")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OFF_WHITE, true)
	var cw := size.x / float(COLS)
	var ch := size.y / float(ROWS)
	for c in COLS + 1:
		draw_line(Vector2(c * cw, 0.0), Vector2(c * cw, size.y), GRID_LINE, 2.0)
	for r in ROWS + 1:
		draw_line(Vector2(0.0, r * ch), Vector2(size.x, r * ch), GRID_LINE, 2.0)


# --- cell assignment -------------------------------------------------------

func _arrange_cells() -> void:
	_layout.resize(COLS * ROWS)
	var goods := _goods_with_icons()
	if goods.is_empty():
		_layout.fill(null)
		return
	var deck: Array = []
	for i in COLS * ROWS:
		if deck.is_empty():
			deck = goods.duplicate()
			deck.shuffle()
		var col := i % COLS
		var row := i / COLS
		var left = _layout[i - 1] if col > 0 else null
		var up = _layout[i - COLS] if row > 0 else null
		# Prefer the first deck good that isn't the same good / category as its
		# left or top neighbour; fall back to whatever's left if none qualifies.
		var pick := 0
		for j in deck.size():
			if not _similar(deck[j], left) and not _similar(deck[j], up):
				pick = j
				break
		_layout[i] = deck[pick]
		deck.remove_at(pick)


func _goods_with_icons() -> Array:
	var result: Array = []
	for good in Catalog.all_goods():
		if GoodIcons.texture_for(good.get("id", ""), good.get("internal_name", ""), true) != null:
			result.append(good)
	return result


func _similar(a, b) -> bool:
	if a == null or b == null:
		return false
	return a.get("id", "") == b.get("id", "") \
		or a.get("category", "x") == b.get("category", "y")


# --- icon placement --------------------------------------------------------

func _relayout_icons() -> void:
	for child in get_children():
		child.free()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cell := Vector2(size.x / float(COLS), size.y / float(ROWS))
	var pad := cell * CELL_PADDING
	for i in _layout.size():
		var good = _layout[i]
		if good == null:
			continue
		var tex: Texture2D = GoodIcons.texture_for(good.get("id", ""), good.get("internal_name", ""), true)
		if tex == null:
			continue
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(i % COLS, i / COLS) * cell + pad
		icon.size = cell - pad * 2.0
		add_child(icon)
