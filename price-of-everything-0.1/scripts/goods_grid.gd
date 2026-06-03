extends Control

## The off-white goods board on the main menu: a 5x5 board filled with good icons.
## Goods are shuffled into the cells with a light touch so the same good / category
## doesn't sit beside itself, and the deck reshuffles/cycles to fill all cells from
## the goods that have art.
##
## Every CYCLE_INTERVAL seconds one line shifts by a cell, Rubik's-cube style,
## walking the grid: column 0 (down), row 0 (right), column 1, row 1, ... wrapping
## back to 0 after 4. The leaving good slides all the way off the edge while a copy
## wraps in from the opposite side. The motion eases ~3/4 of the way early, creeps,
## then SNAPS home at ~1.4s - landing on the click baked into the slide cue.

const GoodIcons := preload("res://scripts/good_icons.gd")
const SLIDE_SOUND: AudioStream = preload("res://assets/audio/ui_sounds/slide_into_slot.wav")

const COLS := 5
const ROWS := 5
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const CELL_PADDING := 0.08     # share of each cell kept as margin (small = big icons)

const CYCLE_INTERVAL := 3.0    # seconds between slides
const SLIDE_DURATION := 1.63   # matches the slide cue length
const SNAP_T := 0.859          # 1.4s / 1.63s - the click (and the snap) land here

var _layout: Array = []        # one good dict (or null) per cell
var _icons: Array = []         # one TextureRect (or null) per cell
var _ghost: TextureRect = null  # copy of the leaving good, wrapping in from the far side

var _player: AudioStreamPlayer
var _started := false
var _anim_active := false
var _anim_elapsed := 0.0
var _anim_is_column := true     # true = column-down, false = row-right
var _next_is_column := true     # sequence: column, row, column, row, ...
var _anim_line := 0             # which column/row this step moves
var _line_index := 0            # advances 0..4 after each column+row pair


func _ready() -> void:
	clip_contents = true        # leaving/incoming goods clip at the panel edges
	set_process(false)
	_arrange_cells()
	resized.connect(_relayout_icons)
	call_deferred("_relayout_icons")
	_player = AudioStreamPlayer.new()
	_player.stream = SLIDE_SOUND
	add_child(_player)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OFF_WHITE, true)


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
	for ic in _icons:
		if is_instance_valid(ic):
			ic.free()
	_icons.clear()
	_icons.resize(COLS * ROWS)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cell := _cell_size()
	var pad := cell * CELL_PADDING
	for i in _layout.size():
		var good = _layout[i]
		if good == null:
			continue
		var tex: Texture2D = GoodIcons.texture_for(good.get("id", ""), good.get("internal_name", ""), true)
		if tex == null:
			continue
		var icon := _new_icon(tex, cell - pad * 2.0)
		icon.position = Vector2(i % COLS, i / COLS) * cell + pad
		add_child(icon)
		_icons[i] = icon
	# kick off the slide loop once the board is actually laid out
	if not _started and size.x > 0.0:
		_started = true
		var timer := Timer.new()
		timer.wait_time = CYCLE_INTERVAL
		timer.autostart = true
		add_child(timer)
		timer.timeout.connect(_play_next)
		_play_next()


func _new_icon(tex: Texture2D, icon_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = icon_size
	return icon


func _cell_size() -> Vector2:
	return Vector2(size.x / float(COLS), size.y / float(ROWS))


# --- the slide animation ---------------------------------------------------

func _play_next() -> void:
	if _anim_active:
		return
	_anim_is_column = _next_is_column
	_anim_line = _line_index
	if not _anim_is_column:
		# a row completes the pair (col N, row N); advance to the next index
		_line_index = (_line_index + 1) % COLS
	_next_is_column = not _next_is_column
	_make_ghost()
	_anim_elapsed = 0.0
	_anim_active = true
	_apply_slide(0.0)   # place the icons + ghost off-edge before this frame renders
	_player.play()      # (otherwise the ghost flashes at 0,0 for one frame)
	set_process(true)


## A copy of the good that's about to slide off the far edge, so it can wrap in
## from the opposite side while the original is still visibly leaving.
func _make_ghost() -> void:
	var wrap_index := (ROWS - 1) * COLS + _anim_line if _anim_is_column \
		else _anim_line * COLS + (COLS - 1)
	var src: TextureRect = _icons[wrap_index]
	if src == null:
		return
	_ghost = _new_icon(src.texture, src.size)
	add_child(_ghost)


func _process(delta: float) -> void:
	if not _anim_active:
		return
	_anim_elapsed += delta
	var t := _anim_elapsed / SLIDE_DURATION
	if t >= 1.0:
		_finish_slide()
		return
	_apply_slide(_slide_progress(t))


## Distance covered (0..1) at animation-time fraction t (0..1): ease three
## quarters of the way in the first half, creep through 0.5-SNAP_T, then jump the
## remainder at SNAP_T and settle with a tiny magnet overshoot.
func _slide_progress(t: float) -> float:
	if t <= 0.5:
		var x := t / 0.5
		return 0.75 * (1.0 - pow(1.0 - x, 2.0))
	elif t <= 0.75:
		return 0.75 + 0.10 * ((t - 0.5) / 0.25)
	elif t < SNAP_T:
		return 0.85 + 0.05 * ((t - 0.75) / (SNAP_T - 0.75))
	var x2 := (t - SNAP_T) / (1.0 - SNAP_T)
	return 1.0 + 0.05 * sin(x2 * PI) * (1.0 - x2)


func _apply_slide(p: float) -> void:
	var cell := _cell_size()
	var pad := cell * CELL_PADDING
	if _anim_is_column:
		var c := _anim_line
		# every good in the column slides down by p; the bottom one slides off
		for r in ROWS:
			var icon = _icons[r * COLS + c]
			if icon != null:
				icon.position = Vector2(c * cell.x, (r + p) * cell.y) + pad
		if _ghost != null:
			_ghost.position = Vector2(c * cell.x, (p - 1.0) * cell.y) + pad
	else:
		var rr := _anim_line
		# every good in the row slides right by p; the rightmost one slides off
		for c2 in COLS:
			var icon = _icons[rr * COLS + c2]
			if icon != null:
				icon.position = Vector2((c2 + p) * cell.x, rr * cell.y) + pad
		if _ghost != null:
			_ghost.position = Vector2((p - 1.0) * cell.x, rr * cell.y) + pad


func _finish_slide() -> void:
	_anim_active = false
	set_process(false)
	if is_instance_valid(_ghost):
		_ghost.free()
	_ghost = null
	if _anim_is_column:
		_shift_column_down(_anim_line)
	else:
		_shift_row_right(_anim_line)
	_relayout_icons()  # rebuild at the new static positions (seamless with the snap)


func _shift_column_down(c: int) -> void:
	var col := []
	for r in ROWS:
		col.append(_layout[r * COLS + c])
	for r in ROWS:
		_layout[r * COLS + c] = col[(r - 1 + ROWS) % ROWS]


func _shift_row_right(rr: int) -> void:
	var row := []
	for c in COLS:
		row.append(_layout[rr * COLS + c])
	for c in COLS:
		_layout[rr * COLS + c] = row[(c - 1 + COLS) % COLS]
