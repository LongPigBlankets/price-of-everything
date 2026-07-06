extends Control

## The off-white goods board on the main menu. An 8x8 grid of good icons sits behind a
## window zoomed to its bottom-right 5x5: 5x5 is visible while 3 extra cells per row and
## column wait off the top/left edges. The 7x7 of cells that aren't the buffer-most row/
## column hold UNIQUE goods (no icon repeats); repeats are only allowed on the "8th" cell
## of each row and column - the top row and left column, which are the last cells to scroll
## into view. Neighbours still avoid sharing a good/category where possible.
##
## Every CYCLE_INTERVAL seconds one visible line shifts by a cell, Rubik's-cube style,
## walking columns/rows 3..7: column 3 (down), row 3 (right), column 4, row 4, ... back to 3.
## The bottom/right good slides off the edge while the off-screen buffer feeds a fresh good in
## from the top/left - so each line cycles all 8 goods (the 3 extras) before it repeats. The
## motion eases ~3/4 of the way early, creeps, then SNAPS home at ~1.4s - landing on the click
## baked into the slide cue.

const GoodIcons := preload("res://scripts/good_icons.gd")
const SLIDE_SOUND: AudioStream = preload("res://assets/audio/ui_sounds/slide_into_slot.wav")

const COLS := 8
const ROWS := 8
const VISIBLE := 5              # cells shown per axis; the board zooms to the bottom-right 5x5
const OFFSET := COLS - VISIBLE  # 3 buffer cells held off the top/left edges, so each row and
								# column cycles all 8 goods (3 extras) before it repeats
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const CELL_PADDING := 0.08     # share of each cell kept as margin (small = big icons)
# The buffer-most row/column: the last cells to scroll into the viewport (the buffer sits
# off the top/left), so any goods that must repeat (more cells than goods with art) are
# parked here. The remaining 7x7 holds only unique goods.
const REPEAT_ROW := 0
const REPEAT_COL := 0

const CYCLE_INTERVAL := 3.0    # seconds between slides
const SLIDE_DURATION := 1.63   # matches the slide cue length
const SNAP_T := 0.859          # 1.4s / 1.63s - the click (and the snap) land here

var _layout: Array = []        # one good dict (or null) per cell
var _icons: Array = []         # one TextureRect (or null) per cell

var _player: AudioStreamPlayer
var _started := false
var _anim_active := false
var _anim_elapsed := 0.0
var _anim_is_column := true     # true = column-down, false = row-right
var _next_is_column := true     # sequence: column, row, column, row, ...
var _anim_line := OFFSET        # which column/row this step moves (3..7, visible lines)
var _line_index := OFFSET       # advances over the visible lines 3..7 after each col+row pair


func _ready() -> void:
	clip_contents = true        # leaving/incoming goods clip at the panel edges
	set_process(false)
	_arrange_cells()
	resized.connect(_relayout_icons)
	call_deferred("_relayout_icons")
	_player = AudioStreamPlayer.new()
	_player.stream = SLIDE_SOUND
	_player.bus = Audio.BUS_SFX   # route through the SFX bus so the volume slider governs it
	add_child(_player)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OFF_WHITE, true)


# --- cell assignment -------------------------------------------------------

func _arrange_cells() -> void:
	_layout.resize(COLS * ROWS)
	_layout.fill(null)
	var goods := _goods_with_icons()
	if goods.is_empty():
		return
	# A single shuffled deck of distinct goods. Pass 1 draws from it (removing each
	# pick) so the 7x7 block is all-unique; pass 2 keeps drawing the leftovers, then
	# recycles a fresh shuffled deck once they run out (the only place goods repeat).
	var deck := goods.duplicate()
	deck.shuffle()

	# Pass 1 - the unique 7x7: every non-edge cell gets a distinct good, preferring
	# one that doesn't sit beside the same good/category.
	for i in COLS * ROWS:
		if _is_repeat_cell(i):
			continue
		if deck.is_empty():
			break  # fewer than 49 goods with art - leave the rest null
		_layout[i] = deck.pop_at(_pick(deck, i))

	# Pass 2 - the buffer-most row 0 and column 0: prefer any still-unused goods,
	# then recycle the full set. These cells are last into view, so repeats hide here.
	var recycle: Array = []
	for i in COLS * ROWS:
		if not _is_repeat_cell(i):
			continue
		if deck.is_empty():
			if recycle.is_empty():
				recycle = goods.duplicate()
				recycle.shuffle()
			_layout[i] = recycle.pop_at(_pick(recycle, i))
		else:
			_layout[i] = deck.pop_at(_pick(deck, i))


func _is_repeat_cell(i: int) -> bool:
	return (i / COLS) == REPEAT_ROW or (i % COLS) == REPEAT_COL


# Index in `pool` of a good that doesn't sit beside the same good/category (left/up
# neighbours already placed), or the first entry if none avoid a clash. `pool` is
# assumed non-empty.
func _pick(pool: Array, i: int) -> int:
	var col := i % COLS
	var row := i / COLS
	var left = _layout[i - 1] if col > 0 else null
	var up = _layout[i - COLS] if row > 0 else null
	for j in pool.size():
		if not _similar(pool[j], left) and not _similar(pool[j], up):
			return j
	return 0


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
		icon.position = (Vector2(i % COLS, i / COLS) - Vector2(OFFSET, OFFSET)) * cell + pad
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
	return Vector2(size.x / float(VISIBLE), size.y / float(VISIBLE))


# --- the slide animation ---------------------------------------------------

func _play_next() -> void:
	if _anim_active:
		return
	_anim_is_column = _next_is_column
	_anim_line = _line_index
	if not _anim_is_column:
		# a row completes the pair (col N, row N); advance to the next visible line (3..7)
		_line_index = OFFSET + ((_line_index - OFFSET + 1) % VISIBLE)
	_next_is_column = not _next_is_column
	_anim_elapsed = 0.0
	_anim_active = true
	_apply_slide(0.0)   # place the icons at their pre-slide offsets before this frame renders
	_player.play()
	set_process(true)


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
		# every good in the column slides down by p; the off-screen buffer above feeds the new
		# top good while the bottom good slides off the edge (all 8 cells move, 5 are visible)
		for r in ROWS:
			var icon = _icons[r * COLS + c]
			if icon != null:
				icon.position = Vector2((c - OFFSET) * cell.x, (r - OFFSET + p) * cell.y) + pad
	else:
		var rr := _anim_line
		# every good in the row slides right by p; the off-screen buffer to the left feeds in
		for c2 in COLS:
			var icon = _icons[rr * COLS + c2]
			if icon != null:
				icon.position = Vector2((c2 - OFFSET + p) * cell.x, (rr - OFFSET) * cell.y) + pad


func _finish_slide() -> void:
	_anim_active = false
	set_process(false)
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
