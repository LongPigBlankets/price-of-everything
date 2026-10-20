extends "res://scripts/new_game_panel.gd"
## The New Game settings screen in DS2: the company registry (docs/new-game-ds2-plan.md §2, §7 and §9; the owner's
## rulings in docs/ds2-owner-decisions.md, New Game settings). Behind UiPrefs.use_new_game_ds2 and the cheat
## `toggle newgame ds2`; with the flag off the old panel stands untouched.
##
## One dark walnut desk at the panel's width. Across its head a navy steel panel with the REGISTRY nameplate and the
## Back key. Under it the card index: an oak rack of seven pigeonholes, a manila company file in each with its tab
## in the start's tier colour, the good's tile in a cut window and the name on its label; the chosen file is pulled
## out over the lip. Below, the chosen file lies open on a green leather blotter: the story and the buildings owned
## (each printed navy with the good it makes under it, a slip with its name and place on hover) on the left leaf,
## the figures as ledger lines in ink and the livery as a paint card on the right. Beside the blotter the form of
## incorporation on cream plastic: the company, the grade stamped in red ink with its words, the charter's term on
## a drum between two small keys over the era rule (its marks from the policy timeline), the tick boxes and the
## seal's circle. At the right the grade stamps, five cream keys in a dark steel rack over the red ink pad, and the
## company seal, a cast iron press whose lever carries the Start New Game key.
##
## A demo build keeps the full game shut: a steel lockbox lid with a padlock and a FULL GAME plate over the five
## pigeonholes the demo does not open and over the grade stamps; the form prints the company, the grade and the
## charter with a DEMO stamp, nothing to set.
##
## Everything the old panel decides is inherited unchanged: the signals, the starts, the demo lock, the difficulty
## lock, the livery table and the telemetry consent. This script only lays the desk and prints on it. Every size
## below is in the render's layout px (docs/ds2-theme.md §2) unless it says logical; `L` converts.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const PParts := preload("res://scripts/people_ds2/parts.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const PolicySchedule := preload("res://scripts/policy_schedule.gd")
const FONT_PLEX: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const FONT_PLEX_SEMI: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")

const L := 1.0 / 1.875
const NAVY := Color("#0b2340")
const INK_RED := Color("#8f1f19")
const INK_GREEN := Color("#1d6b3a")
const INK_DIM := Color("#3a4a5c")
const INK_FAINT := Color(0.043, 0.137, 0.251, 0.5)
const STAMP_RED := Color("#b8261c")
const INK_SHADOW := Color(1, 1, 1, 0.55)
const WHITE_SHADOW := Color(0, 0, 0, 0.9)
const CREAM_TILE := Color("#f3e7cc")
const LABEL_CREAM := Color("#f6efdf")
const GLOW := Color(1.0, 0.886, 0.588, 0.55)

## The desk and its parts, from layout.json (registry_*), in layout px.
const PANEL_W := 2617.0
const PAD := 40.0
const DESK := {"margin": 30.0, "corner": 60.0}
const HEAD := {"y": 20.0, "h": 112.0, "margin": 16.0, "corner": 30.0, "screw": 16.0, "nameplate": Rect2(52, 8, 470, 96)}
const NAMEPLATE := {"margin": 14.0, "cap": 60.0}
const RACK := {"y": 150.0, "h": 470.0, "bar": 24.0, "lip": 30.0, "margin": 24.0, "corner": 40.0}
const FILE := {"w": 290.0, "h": 372.0, "margin": 24.0, "pulled_margin": 48.0, "pull": 34.0, "window": Rect2(63, 44, 164, 164),
	"tile_inset": 14.0, "label": Rect2(24, 236, 242, 52), "name_y": 262.0, "tier_y": 320.0}
const LID := {"margin": 40.0, "corner": 28.0, "hinge_margin": 14.0, "hasp_margin": 14.0, "plate": Vector2(300, 58), "plate_margin": 12.0, "plate_corner": 26.0}
const BLOTTER := {"margin": 30.0, "corner": 40.0, "inset": 40.0}
const COVER := {"margin": 16.0, "corner": 20.0}
const LEAF := {"margin": 14.0, "corner": 16.0, "inset": 30.0, "m": 44.0}
const FORM := {"w": 720.0, "margin": 14.0, "corner": 54.0, "m": 48.0}
const STAMPS := {"col": 217.0, "margin": 16.0, "corner": 24.0, "key_w": 195.0, "key_h": 78.0, "first": 30.0, "pitch": 94.0, "foot": 10.0, "pad_h": 84.0, "pad_margin": 16.0}
const PRESS := {"h": 320.0, "margin": 30.0, "key": Rect2(15, 250, 195, 84)}
const SLIP := {"w": 330.0, "h": 96.0, "margin": 30.0, "corner": 20.0}
const STRIP := {"bld": 104.0, "good": 56.0}
const PAINT := {"sq": 96.0, "gap": 16.0, "cols": 4}
const COUNTER_GAP := 20.0
const FOOT := 120.0

const TIER_WORDS := {"green": "Beginner friendly", "amber": "Intermediate", "red": "Challenging"}
## The seal when the game starts: over STAMP_SECONDS the die lifts off the press, slides to the form's seal circle,
## comes down on it (the impression stays from then on), holds, rises, slides back and settles on the press, so the
## impression is in view as the screen fades. Seconds at which each move ends.
const STAMP_SECONDS := 2.5
const STAMP_LIFT := 0.3
const STAMP_SLIDE := 1.2
const STAMP_DOWN := 1.5
const STAMP_HOLD := 1.9
const STAMP_RISE := 2.1
const STAMP_BACK := 2.4
const DIE_LIFT_SCALE := 1.12
const SEAL_R := 72.0
## Tests and headless runs skip the sequence (the signal goes at once); a windowed run plays it.
static var animate := true
const LOCKED_GRADE_TIP := "This difficulty is unlocked once you finish one game"
const DEMO_CHARTER := "100 turns, the Itch.io demo."
const DEMO_SURVEY := "All tiles surveyed at game start."

var _chosen: Dictionary = {}
var _chosen_index := -1
var _speed_index := SPEED_DEFAULT
var _hover_cell := -1
var _rows: Array = []          # the chosen start's buildings: {bid, internal, name, place, gid, ginternal}
var _ledger: Array = []        # [label, figure, colour]
var _story_lines: Array = []
var _strip_top := 0.0          # leaf px, where the building strip starts
var _slip_at := Vector2.ZERO   # leaf px, the hovered cell's middle and the strip's foot
var _grade_keys: Array = []
var _stamp_t := -1.0          # seconds into the seal sequence, below zero before Start is pressed
var _starting := false
var _paint_buttons: Array = []
var _cell_buttons: Array = []

var _header: Control
var _rack: Control
var _rack_lid: Control
var _blotter: Control
var _left_leaf: Control
var _right_leaf: Control
var _slip: Control
var _form: Control
var _drum: Control
var _speed_back: TextureButton
var _speed_forward: TextureButton
var _metrics_box: Button
var _stamps: Control
var _stamps_over: Control
var _press: Control
var _start_key: Button
var _die: Control
var _block: Control

# Logical rects laid out from the panel's size.
var _r_head := Rect2()
var _r_rack := Rect2()
var _r_blotter := Rect2()
var _r_cover := Rect2()
var _r_leaf_l := Rect2()
var _r_leaf_r := Rect2()
var _r_form := Rect2()
var _r_stamps := Rect2()
var _r_pad := Rect2()
var _r_press := Rect2()
var _r_lid_rack := Rect2()
var _r_lid_stamps := Rect2()
var _cells: Array = []   # the seven openings, logical


# ── Build ───────────────────────────────────────────────────────────────────────

func _build() -> void:
	name = "NewGameDs2"
	_starts = _load_starts()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	clip_contents = false
	if DS != null and DS.theme != null:
		theme = DS.theme
	draw.connect(_draw_desk)
	if _demo_locked():
		_difficulty_id = DEMO_DIFFICULTY_ID
		_speed_index = SPEED_DEFAULT_DEMO
	_apply_speed()
	if TelemetryState.SHOW_CONSENT_CHECKBOX:
		_send_metrics = not PlayerProfile.telemetry_opt_out
	else:
		_send_metrics = true

	_header = _region("Header", _draw_header)
	var back := SmallKey.make("back", 40.0)
	back.name = "BackKey"
	back.pressed.connect(func() -> void: back_requested.emit())
	_header.add_child(back)
	var back_label := Kit.caption("Back", 15)
	back_label.name = "BackLabel"
	back_label.uppercase = false
	back_label.add_theme_font_override("font", FONT_PLEX_SEMI)
	_header.add_child(back_label)

	_rack = _region("Rack", _draw_rack)
	var group := ButtonGroup.new()
	_card_buttons.clear()
	for i in _starts.size():
		var start: Dictionary = _starts[i]
		var b := Button.new()
		b.name = "File%d" % i
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(start.get("title", ""))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		if _demo_locked() and not DEMO_START_IDS.has(String(start.get("id", ""))):
			b.disabled = true
			b.tooltip_text = DEMO_LOCK_TIP
		else:
			var idx := i
			b.toggled.connect(func(on: bool) -> void:
				if on:
					_chosen_index = idx
					_select_start(start))
		_rack.add_child(b)
		_card_buttons.append(b)
	_rack_lid = _region("RackLid", func() -> void: _draw_lid(_rack_lid, _r_lid_rack, false), _rack)
	_rack_lid.visible = _demo_locked()

	_blotter = _region("Blotter", _draw_blotter)
	_left_leaf = _region("LeftLeaf", _draw_left_leaf, _blotter)
	_right_leaf = _region("RightLeaf", _draw_right_leaf, _blotter)
	_slip = _region("HoverSlip", _draw_slip, _left_leaf)
	_slip.visible = false

	_form = _region("Form", _draw_form)
	if not _demo_locked():
		_speed_back = SmallKey.make("back", 32.0)
		_speed_back.name = "SpeedBack"
		_speed_back.tooltip_text = "A shorter charter"
		_speed_back.pressed.connect(func() -> void: _step_speed(-1))
		_form.add_child(_speed_back)
		_drum = Counter.new()
		_drum.name = "CharterDrum"
		_drum.configure(3, 0)
		_drum.set_value(float(_speed_turns))
		_drum.tooltip_text = "This also changes the Era pacing."
		_drum.mouse_filter = Control.MOUSE_FILTER_PASS
		_form.add_child(_drum)
		_speed_forward = SmallKey.make("forward", 32.0)
		_speed_forward.name = "SpeedForward"
		_speed_forward.tooltip_text = "A longer charter"
		_speed_forward.pressed.connect(func() -> void: _step_speed(1))
		_form.add_child(_speed_forward)
		if TelemetryState.SHOW_CONSENT_CHECKBOX:
			_metrics_box = Button.new()
			_metrics_box.name = "MetricsBox"
			_metrics_box.toggle_mode = true
			_metrics_box.button_pressed = _send_metrics
			_metrics_box.focus_mode = Control.FOCUS_NONE
			_metrics_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				_metrics_box.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			_metrics_box.toggled.connect(func(on: bool) -> void:
				_send_metrics = on
				_form.queue_redraw())
			_form.add_child(_metrics_box)

	_stamps = _region("Stamps", _draw_stamps)
	var stamps_title := Kit.caption("Stamps", 12, HORIZONTAL_ALIGNMENT_CENTER)
	stamps_title.name = "StampsTitle"
	_stamps.add_child(stamps_title)
	var unlocked := PlayerProfile.has_completed_game()
	_grade_keys.clear()
	for opt in DIFFICULTIES:
		var oid := String(opt["id"])
		var key: Button = CreamKey.make("Grade_" + oid, String(opt["label"]), "", STAMPS["key_w"] * L, false, false, 0.93)
		key.set_meta("grade", oid)
		if _demo_locked() and oid != DEMO_DIFFICULTY_ID:
			key.call("set_spent", true)
			key.tooltip_text = DEMO_LOCK_TIP
		elif bool(opt.get("locked", false)) and not unlocked:
			key.call("set_spent", true)
			key.tooltip_text = LOCKED_GRADE_TIP
		else:
			key.tooltip_text = String(opt["desc"])
			key.pressed.connect(func() -> void: _choose_grade(oid))
		_stamps.add_child(key)
		_grade_keys.append(key)
	_stamps_over = _region("StampsOver", _draw_stamps_over, _stamps)

	_press = _region("Press", _draw_press)
	_start_key = CreamKey.make("StartNewGame", "START NEW GAME", "", PRESS["key"].size.x * L, false, false, 1.0)
	_start_key.pressed.connect(_on_start_pressed)
	_press.add_child(_start_key)
	_block = Control.new()
	_block.name = "StartBlock"
	_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_block.visible = false
	add_child(_block)
	_die = _region("Die", _draw_die)

	_refresh_grades()
	resized.connect(_layout)
	_layout()
	_select_default_start()
	LampOverlay.attach(self)


## A Control drawn by `painter`, standing in the panel; its position is set by _layout.
func _region(node_name: String, painter: Callable, parent: Node = null) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	c.draw.connect(painter)
	(parent if parent != null else self).add_child(c)
	return c


# ── Layout ──────────────────────────────────────────────────────────────────────

func _layout() -> void:
	var w := size.x
	var h := size.y
	var pad := PAD * L
	var rw := w - 2.0 * pad
	_r_head = Rect2(pad, HEAD["y"] * L, rw, HEAD["h"] * L)
	_place(_header, _r_head)
	var back: Control = _header.get_node("BackKey")
	var side := back.custom_minimum_size.x
	back.position = Vector2(_r_head.size.x - 62.0 * L - side * 0.5, (_r_head.size.y - side) * 0.5)
	back.size = Vector2(side, side)
	var back_label: Control = _header.get_node("BackLabel")
	var lw := back_label.get_combined_minimum_size().x
	back_label.position = Vector2(_r_head.size.x - 118.0 * L - lw, (_r_head.size.y - back_label.get_combined_minimum_size().y) * 0.5)
	back_label.size = Vector2(lw, back_label.get_combined_minimum_size().y)

	_r_rack = Rect2(pad, RACK["y"] * L, rw, RACK["h"] * L)
	_place(_rack, _r_rack)
	var n := maxi(_starts.size(), 1)
	var bar := RACK["bar"] * L
	var lip := RACK["lip"] * L
	var ow := (_r_rack.size.x - (n + 1) * bar) / n
	var oh := _r_rack.size.y - 2.0 * lip
	_cells.clear()
	for i in n:
		var cell := Rect2(bar + i * (ow + bar), lip, ow, oh)
		_cells.append(cell)
		if i < _card_buttons.size():
			var b: Control = _card_buttons[i]
			b.position = cell.position
			b.size = cell.size
	_r_lid_rack = Rect2()
	if _demo_locked():
		var first := -1
		var last := -1
		for i in _card_buttons.size():
			if (_card_buttons[i] as Button).disabled:
				last = i
				if first < 0:
					first = i
		if first >= 0:
			var x0: float = (_cells[first] as Rect2).position.x - 12.0 * L
			var x1: float = _r_rack.size.x - 10.0 * L
			_r_lid_rack = Rect2(x0, 10.0 * L, x1 - x0, _r_rack.size.y - 20.0 * L)
	_place(_rack_lid, Rect2(Vector2.ZERO, _r_rack.size))

	var cy := (RACK["y"] + RACK["h"] + COUNTER_GAP) * L
	var pcol := STAMPS["col"] * L
	var sx := pad + rw - pcol
	var fmw := FORM["w"] * L
	var bx := pad + 30.0 * L
	var bz := cy + 30.0 * L
	var bw := rw - 60.0 * L - pcol - 40.0 * L - fmw - 40.0 * L
	var bh := maxf(h - bz - FOOT * L, 420.0)
	_r_blotter = Rect2(bx, bz, bw, bh)
	_place(_blotter, _r_blotter)
	var inset := BLOTTER["inset"] * L
	_r_cover = Rect2(inset, inset, bw - 2.0 * inset, bh - 2.0 * inset)
	var li := LEAF["inset"] * L
	var leaf_w := _r_cover.size.x * 0.5 - 2.0 * li
	var leaf_h := _r_cover.size.y - 2.0 * li
	_r_leaf_l = Rect2(_r_cover.position.x + li, _r_cover.position.y + li, leaf_w, leaf_h)
	_r_leaf_r = Rect2(_r_cover.position.x + _r_cover.size.x * 0.5 + li, _r_cover.position.y + li, leaf_w, leaf_h)
	_place(_left_leaf, _r_leaf_l)
	_place(_right_leaf, _r_leaf_r)

	_r_form = Rect2(bx + bw + 40.0 * L, bz, fmw, bh)
	_place(_form, _r_form)
	if _drum != null:
		var kz := 500.0 * L
		var dx := FORM["m"] * L + 128.0 * L
		var side_s := _speed_back.custom_minimum_size.x
		_speed_back.position = Vector2(dx + 28.0 * L - side_s * 0.5, kz - side_s * 0.5)
		_speed_back.size = Vector2(side_s, side_s)
		var dw := _drum.custom_minimum_size.x
		var dh := _drum.custom_minimum_size.y
		_drum.position = Vector2(dx + 70.0 * L, kz - dh * 0.5)
		_drum.size = Vector2(dw, dh)
		_speed_forward.position = Vector2(dx + 70.0 * L + dw + 36.0 * L - side_s * 0.5, kz - side_s * 0.5)
		_speed_forward.size = Vector2(side_s, side_s)
	if _metrics_box != null:
		_metrics_box.position = Vector2(FORM["m"] * L, (820.0 - 15.0) * L)
		_metrics_box.size = Vector2(fmw - 2.0 * FORM["m"] * L, 30.0 * L)

	var rack_h := (STAMPS["first"] + DIFFICULTIES.size() * STAMPS["pitch"] + STAMPS["foot"]) * L
	_r_stamps = Rect2(sx, bz, pcol, rack_h)
	_place(_stamps, Rect2(sx, bz, pcol, bh))
	var title: Control = _stamps.get_node("StampsTitle")
	var tw := title.get_combined_minimum_size().x
	title.position = Vector2((pcol - tw) * 0.5, 16.0 * L - title.get_combined_minimum_size().y * 0.5)
	title.size = title.get_combined_minimum_size()
	for k in _grade_keys.size():
		var key: Control = _grade_keys[k]
		var kw := STAMPS["key_w"] * L
		var kh: float = CreamKey.height_for(0.93)
		key.position = Vector2((pcol - kw) * 0.5, (STAMPS["first"] + k * STAMPS["pitch"] + STAMPS["key_h"] * 0.5) * L - kh * 0.5)
		key.size = Vector2(kw, kh)
	var pw := pcol - 20.0 * L
	_r_pad = Rect2(10.0 * L, rack_h + 20.0 * L, pw, STAMPS["pad_h"] * L)
	_r_lid_stamps = Rect2(-10.0 * L, -10.0 * L, pcol + 20.0 * L, rack_h + 20.0 * L + _r_pad.size.y + 20.0 * L)
	_place(_stamps_over, Rect2(Vector2.ZERO, Vector2(pcol, bh)))

	var ph := PRESS["h"] * L
	_r_press = Rect2(sx - 4.0 * L, bz + bh - ph, pcol + 8.0 * L, ph)
	_place(_press, _r_press)
	var kr: Rect2 = PRESS["key"]
	var skh: float = CreamKey.height_for(1.0)
	_start_key.position = Vector2(kr.position.x * L, (kr.position.y + kr.size.y * 0.5) * L - skh * 0.5)
	_start_key.size = Vector2(kr.size.x * L, skh)
	_place(_block, Rect2(Vector2.ZERO, size))
	_place_die()
	queue_redraw()
	for c in get_children():
		if c is Control:
			(c as Control).queue_redraw()


static func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size
	c.queue_redraw()


# ── Selection and state ─────────────────────────────────────────────────────────

func _select_start(start: Dictionary) -> void:
	_start_id = String(start.get("id", ""))
	_start_path = String(start.get("file", DEFAULT_START))
	_chosen = start
	if _chosen_index < 0 or _chosen_index >= _starts.size() or _starts[_chosen_index] != start:
		_chosen_index = _starts.find(start)
	_hover_cell = -1
	_slip.visible = false
	_read_file(start)
	_place_cells()
	_place_paint()
	_rack.queue_redraw()
	_left_leaf.queue_redraw()
	_right_leaf.queue_redraw()
	_form.queue_redraw()


## Reads the chosen start's config into what the leaves print: the buildings with the good each makes and its
## place, and the ledger lines (Cash, Debt, then Net while there is debt, else Profit each turn).
func _read_file(start: Dictionary) -> void:
	var cfg := _read_config(String(start.get("file", "")))
	_rows.clear()
	for entry in (cfg.get("buildings", []) as Array):
		var e := entry as Dictionary
		var bid := String(e.get("building_id", ""))
		var bd := Catalog.get_building(bid)
		var recipe := Catalog.get_recipe(String(e.get("recipe_id", "")))
		var gid := String(recipe.get("output_good_id", ""))
		_rows.append({"bid": bid, "internal": String(bd.get("internal_name", "")),
			"name": String(bd.get("display_name", bd.get("name", bid))), "place": place_for(String(e.get("tile_id", ""))),
			"gid": gid, "ginternal": Catalog.get_internal_name(gid) if gid != "" else ""})
	var cash := float(cfg.get("money", EconomyConfig.STARTING_MONEY))
	var debt := 0.0
	for l in (cfg.get("loans", []) as Array):
		debt += float((l as Dictionary).get("principal", 0.0))
	_ledger = [["Cash", _pounds(cash), NAVY], ["Debt", "none" if debt <= 0.0 else _pounds(debt), NAVY]]
	if debt > 0.0:
		var net := cash - debt
		_ledger.append(["Net", _pounds(net), INK_RED if net < 0.0 else NAVY])
	else:
		var profit := float(cfg.get("steady_profit_per_turn", _profit_estimate(cfg)))
		_ledger.append(["Profit each turn", _pounds(profit), INK_RED if profit < 0.0 else (INK_GREEN if profit > 0.0 else NAVY)])


## A figure in whole pounds as the panel prints them, the minus before the £.
func _pounds(v: float) -> String:
	return ("-£%s" % _fmt_money(absf(v))) if roundf(v) < 0.0 else ("£%s" % _fmt_money(v))


## The ledger as printed, label to figure, for tests and the hover.
func ledger_lines() -> Array:
	return _ledger.duplicate(true)


## The buildings owned as printed: {bid, name, place, gid}.
func building_rows() -> Array:
	return _rows.duplicate(true)


## A tile's name as the file prints it: the tile's own, or "Near" the nearest named tile for a tile with none.
static func place_for(tile_id: String) -> String:
	var own := Catalog.tile_name(tile_id)
	if own != "":
		return own
	var parts := tile_id.split("_")
	if parts.size() < 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return tile_id
	var at := Vector2(float(parts[1].to_int()), float(parts[2].to_int()))
	var best := ""
	var best_d := INF
	for t in Catalog.named_tiles():
		var tp := String((t as Dictionary).get("id", "")).split("_")
		if tp.size() < 3 or not tp[1].is_valid_int() or not tp[2].is_valid_int():
			continue
		var d := at.distance_squared_to(Vector2(float(tp[1].to_int()), float(tp[2].to_int())))
		if d < best_d:
			best_d = d
			best = String((t as Dictionary).get("name", ""))
	return ("Near " + best) if best != "" else tile_id


func _choose_grade(oid: String) -> void:
	_difficulty_id = oid
	_refresh_grades()
	_form.queue_redraw()


func _refresh_grades() -> void:
	for key in _grade_keys:
		(key as Button).set("chosen", String((key as Button).get_meta("grade")) == _difficulty_id)


func _apply_speed() -> void:
	var opt: Dictionary = SPEEDS[clampi(_speed_index, 0, SPEEDS.size() - 1)]
	_speed_turns = int(opt["turns"])
	_policy_timeline = String(opt.get("policy_timeline", ""))
	_victory_set = String(opt.get("victory_set", ""))


func _step_speed(by: int) -> void:
	if _demo_locked():
		return
	var from := _speed_turns
	_speed_index = wrapi(_speed_index + by, 0, SPEEDS.size())
	_apply_speed()
	if _drum != null:
		_drum.set_value(float(_speed_turns), float(from))
	_form.queue_redraw()


## The charter's length in turns, as the drum reads.
func charter_turns() -> int:
	return _speed_turns


## The era rule's marks for the chosen charter: [{turn, label}] in turn order, from the policy timeline the length
## runs under (PolicyState.TIMELINES) and the levy phases after it (PolicySchedule.SCHEDULE), those within the term.
static func era_marks(turns: int, timeline: String) -> Array:
	var tid: String = PolicyState.TIMELINE_DEMO if timeline == PolicyState.TIMELINE_DEMO else PolicyState.TIMELINE_CAMPAIGN
	var beats: Dictionary = PolicyState.TIMELINES.get(tid, PolicyState.TIMELINES.get(PolicyState.TIMELINE_DEMO, {}))
	var out: Array = []
	for pair in [["election_news", "Election"], ["p1", "Carbon levy"], ["subsidy", "Green subsidy"], ["subsidy_end", "Subsidy ends"]]:
		var t := int(beats.get(String(pair[0]), 0))
		if t > 0 and t <= turns:
			out.append({"turn": t, "label": String(pair[1])})
	for row in PolicySchedule.SCHEDULE:
		var r := row as Dictionary
		if String(r.get("policy", "")) != "co2_tax" or int(r.get("level", 0)) < 2:
			continue
		var t := int(r.get("effective_turn", 0))
		if t > 0 and t <= turns:
			out.append({"turn": t, "label": "Levy phase %d" % int(r.get("level", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["turn"]) < int(b["turn"]))
	return out


# ── The leaves' live parts: the building cells and the paint squares ────────────

func _story_font_px() -> int:
	return 14


## Measures the story and places a hover target over each building cell.
func _place_cells() -> void:
	for b in _cell_buttons:
		(b as Node).queue_free()
	_cell_buttons.clear()
	var m := LEAF["m"] * L
	var inner := _r_leaf_l.size.x - 2.0 * m
	var tp := TextParagraph.new()
	tp.width = inner
	tp.add_string(String(_chosen.get("description", _chosen.get("blurb", ""))), FONT_PLEX, _story_font_px())
	_story_lines = []
	for i in tp.get_line_count():
		_story_lines.append(tp.get_line_range(i))
	var y := 194.0 * L + tp.get_line_count() * 36.0 * L
	y += 34.0 * L + 24.0 * L + 22.0 * L
	_strip_top = y
	var n := maxi(_rows.size(), 1)
	var cell_w := inner / n
	var bld := minf(STRIP["bld"] * L, cell_w - 10.0)
	for k in _rows.size():
		var b := Button.new()
		b.name = "Cell%d" % k
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var hit_w := minf(cell_w, 150.0 * L)
		b.position = Vector2(m + cell_w * (k + 0.5) - hit_w * 0.5 + 6.0 * L, _strip_top - 8.0 * L)
		b.size = Vector2(hit_w - 12.0 * L, bld + STRIP["good"] * L + 36.0 * L)
		var idx := k
		b.mouse_entered.connect(func() -> void: _hover(idx))
		b.mouse_exited.connect(func() -> void:
			if _hover_cell == idx:
				_hover(-1))
		_left_leaf.add_child(b)
		_cell_buttons.append(b)
	_left_leaf.move_child(_slip, _left_leaf.get_child_count() - 1)


func _hover(k: int) -> void:
	_hover_cell = k
	if k < 0 or k >= _rows.size():
		_slip.visible = false
	else:
		var m := LEAF["m"] * L
		var inner := _r_leaf_l.size.x - 2.0 * m
		var cell_w := inner / maxi(_rows.size(), 1)
		var bld := minf(STRIP["bld"] * L, cell_w - 10.0)
		var cx := m + cell_w * (k + 0.5)
		var foot := _strip_top + bld + STRIP["good"] * L + 44.0 * L
		var sw := SLIP["w"] * L
		var sh := SLIP["h"] * L
		var sx := clampf(cx + 40.0 * L, m + sw * 0.5, _r_leaf_l.size.x - m - sw * 0.5)
		_slip.position = Vector2(sx - sw * 0.5, foot)
		_slip.size = Vector2(sw, sh)
		_slip.visible = true
		_slip.queue_redraw()
	_left_leaf.queue_redraw()


## The building the slip names, or -1.
func hovered_cell() -> int:
	return _hover_cell


func _paint_origin() -> Vector2:
	var m := LEAF["m"] * L
	var y := 122.0 * L + _ledger.size() * 54.0 * L + 30.0 * L + 24.0 * L + 30.0 * L
	var card_w := (PAINT["cols"] * PAINT["sq"] + (PAINT["cols"] - 1) * PAINT["gap"]) * L
	return Vector2(m + ((_r_leaf_r.size.x - 2.0 * m) - card_w) * 0.5, y)


func _place_paint() -> void:
	for b in _paint_buttons:
		(b as Node).queue_free()
	_paint_buttons.clear()
	var o := _paint_origin()
	var sq := PAINT["sq"] * L
	var gap := PAINT["gap"] * L
	var colours := PlayerColours.all()
	for k in colours.size():
		var entry: Dictionary = colours[k]
		var b := Button.new()
		b.name = "Paint_" + str(entry["key"])
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = str(entry["label"])
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.position = o + Vector2((k % PAINT["cols"]) * (sq + gap), (k / PAINT["cols"]) * (sq + gap))
		b.size = Vector2(sq, sq)
		var key := str(entry["key"])
		b.pressed.connect(func() -> void:
			_colour_key = key
			_right_leaf.queue_redraw())
		_right_leaf.add_child(b)
		_paint_buttons.append(b)


## The livery chosen on the paint card.
func colour_key() -> String:
	return _colour_key


# ── Drawing ─────────────────────────────────────────────────────────────────────

func _draw_desk() -> void:
	PParts.draw_nine(self, PParts.tex("registry_desk"), Rect2(Vector2.ZERO, size), DESK["margin"], DESK["corner"])


func _draw_header() -> void:
	var c := _header
	var r := Rect2(Vector2.ZERO, c.size)
	PParts.draw_nine(c, PParts.tex("registry_header"), r, HEAD["margin"], HEAD["corner"])
	var screw: Texture2D = PParts.tex("screw_silver")
	var s := screw.get_size() * 0.5
	var si := HEAD["screw"] * L
	for p in [Vector2(si, si), Vector2(r.size.x - si, si), Vector2(si, r.size.y - si), Vector2(r.size.x - si, r.size.y - si)]:
		c.draw_texture_rect(screw, Rect2(p - s * 0.5, s), false)
	var np: Rect2 = HEAD["nameplate"]
	var plate := Rect2(np.position * L, np.size * L)
	PParts.draw_h3(c, PParts.tex("tile_nameplate"), plate, NAMEPLATE["margin"], NAMEPLATE["cap"] - NAMEPLATE["margin"])
	var fs := 30
	var font: Font = BEBAS
	var tw := font.get_string_size("REGISTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(plate.get_center().x - tw * 0.5, plate.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	c.draw_string(font, at + Vector2(1, 1), "REGISTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE_SHADOW)
	c.draw_string(font, at, "REGISTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE["TEXT"])


func _draw_rack() -> void:
	var c := _rack
	var felt: Texture2D = PParts.tex("registry_felt")
	var frame: Texture2D = PParts.tex("registry_pigeonhole")
	var bar := RACK["bar"] * L
	var lip := RACK["lip"] * L
	var fw := FILE["w"] * L
	var fh := FILE["h"] * L
	for i in _cells.size():
		var cell: Rect2 = _cells[i]
		PParts.draw_nine(c, felt, cell, 0.0, 20.0)
		if i != _chosen_index and i < _starts.size():
			var at := cell.get_center() - Vector2(fw, fh) * 0.5
			_draw_file(c, _starts[i], at, false)
	for i in _cells.size():
		var cell: Rect2 = _cells[i]
		PParts.draw_nine(c, frame, cell.grow_individual(bar, lip, bar, lip), RACK["margin"], RACK["corner"])
	if _chosen_index >= 0 and _chosen_index < _cells.size():
		var cell: Rect2 = _cells[_chosen_index]
		var at := cell.get_center() - Vector2(fw, fh) * 0.5 + Vector2(0, FILE["pull"] * L)
		_draw_file(c, _starts[_chosen_index], at, true)
		var glow := Rect2(at, Vector2(fw, fh)).grow(6.0 * L)
		_round_stroke(c, glow.grow(2.0), 7.0 * L, 5.0, Color(GLOW, 0.22))
		_round_stroke(c, glow, 6.0 * L, 2.2, GLOW)


## A company file at `at` (its top left): the blank render in its tier's colour, then the good's tile in the window,
## the name on the label and the tier's words.
func _draw_file(c: CanvasItem, start: Dictionary, at: Vector2, pulled: bool) -> void:
	var tier := String(start.get("tier", "amber"))
	if not TIER_WORDS.has(tier):
		tier = "amber"
	var tex: Texture2D = PParts.tex("registry_file_%s%s" % [tier, "_pulled" if pulled else ""])
	PParts.draw_fixed(c, tex, at, FILE["pulled_margin"] if pulled else FILE["margin"])
	var win: Rect2 = FILE["window"]
	var inset := FILE["tile_inset"] * L
	var tile := Rect2(at + win.position * L + Vector2(inset, inset), win.size * L - Vector2(inset, inset) * 2.0)
	var icon: Texture2D = GoodIcons.texture_for_size(String(start.get("good_id", "")), String(start.get("good_internal", "")), tile.size.x)
	_good_tile(c, icon, tile)
	var label: Rect2 = FILE["label"]
	_ink(c, Plate.FONT_BOLD, 14, String(start.get("title", "")).to_upper(), at + Vector2(FILE["w"] * 0.5, FILE["name_y"]) * L, NAVY,
		HORIZONTAL_ALIGNMENT_CENTER, (label.size.x - 28.0) * L)
	_ink(c, FONT_PLEX, 12, String(TIER_WORDS[tier]), at + Vector2(FILE["w"] * 0.5, FILE["tier_y"]) * L, Color("#4a3818"),
		HORIZONTAL_ALIGNMENT_CENTER, (FILE["w"] - 40.0) * L)


## A lockbox over `r` in `c`: the lid, its hinges, the hasp with the padlock, the FULL GAME plate and the words under it.
func _draw_lid(c: CanvasItem, r: Rect2, narrow: bool) -> void:
	if r.size.x <= 0.0:
		return
	PParts.draw_nine(c, PParts.tex("registry_lid"), r, LID["margin"], LID["corner"])
	var hinge: Texture2D = PParts.tex("registry_hinge")
	for f in [0.18, 0.5, 0.82]:
		PParts.draw_fixed(c, hinge, Vector2(r.position.x + 8.0 * L - hinge.get_width() * 0.25 + LID["hinge_margin"] * L,
			r.position.y + r.size.y * f - hinge.get_height() * 0.25 + LID["hinge_margin"] * L), LID["hinge_margin"])
	var hasp: Texture2D = PParts.tex("registry_hasp")
	var hx := r.get_center().x if narrow else r.end.x - 44.0 * L
	var hz := (r.end.y - 70.0 * L) if narrow else (r.get_center().y - 8.0 * L)
	PParts.draw_fixed(c, hasp, Vector2(hx, hz) - hasp.get_size() * 0.25 + Vector2(LID["hasp_margin"], LID["hasp_margin"]) * L, LID["hasp_margin"])
	var lock: Texture2D = PParts.tex("registry_padlock")
	c.draw_texture_rect(lock, Rect2(Vector2(hx, hz + 38.0 * L + 6.0 * L) - lock.get_size() * 0.25, lock.get_size() * 0.5), false)
	var pw := (r.size.x - 60.0 * L) if narrow else LID["plate"].x * L
	var ph := LID["plate"].y * L
	var pc := Vector2(r.get_center().x, r.get_center().y - 40.0 * L) if narrow else Vector2(r.get_center().x - 30.0 * L, r.get_center().y)
	var plate := Rect2(pc - Vector2(pw, ph) * 0.5, Vector2(pw, ph))
	PParts.draw_nine(c, PParts.tex("registry_lid_plate"), plate, LID["plate_margin"], LID["plate_corner"])
	_ink(c, Plate.FONT_BOLD, 18, "FULL GAME", pc + Vector2(0, 1), NAVY, HORIZONTAL_ALIGNMENT_CENTER, pw - 60.0 * L)
	var room := r.size.x - 24.0 * L
	if FONT_PLEX.get_string_size("Opens with the full game.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= room:
		_white(c, FONT_PLEX, 13, "Opens with the full game.", pc + Vector2(0, 58.0 * L), HORIZONTAL_ALIGNMENT_CENTER, room)
	else:
		_white(c, FONT_PLEX, 13, "Opens with", pc + Vector2(0, 58.0 * L), HORIZONTAL_ALIGNMENT_CENTER, room)
		_white(c, FONT_PLEX, 13, "the full game.", pc + Vector2(0, 58.0 * L + 17.0), HORIZONTAL_ALIGNMENT_CENTER, room)


func _draw_blotter() -> void:
	var c := _blotter
	PParts.draw_nine(c, PParts.tex("registry_blotter"), Rect2(Vector2.ZERO, c.size), BLOTTER["margin"], BLOTTER["corner"])
	PParts.draw_nine(c, PParts.tex("registry_cover"), _r_cover, COVER["margin"], COVER["corner"])
	c.draw_rect(Rect2(_r_cover.get_center().x - 2.0 * L, _r_cover.position.y, 4.0 * L, _r_cover.size.y), Color(0, 0, 0, 0.18))


func _draw_left_leaf() -> void:
	var c := _left_leaf
	var w := c.size.x
	PParts.draw_nine(c, PParts.tex("registry_leaf"), Rect2(Vector2.ZERO, c.size), LEAF["margin"], LEAF["corner"])
	if _chosen.is_empty():
		return
	var m := LEAF["m"] * L
	var inner := w - 2.0 * m
	_ink(c, Plate.FONT_BOLD, 13, "COMPANY FILE", Vector2(m, 62.0 * L))
	_ink(c, Plate.FONT_SEMI, 13, "FILE %d OF %d" % [_chosen_index + 1, _starts.size()], Vector2(w - m, 62.0 * L), NAVY, HORIZONTAL_ALIGNMENT_RIGHT)
	_ink(c, Plate.FONT_BOLD, 26, String(_chosen.get("title", "")), Vector2(m, 116.0 * L), NAVY, HORIZONTAL_ALIGNMENT_LEFT, inner)
	c.draw_rect(Rect2(m, 148.0 * L, inner, 2.0 * L), INK_FAINT)
	var story := String(_chosen.get("description", _chosen.get("blurb", "")))
	var y := 194.0 * L
	for rng in _story_lines:
		var line := story.substr(int((rng as Vector2i).x), int((rng as Vector2i).y - (rng as Vector2i).x)).strip_edges()
		_ink(c, FONT_PLEX, _story_font_px(), line, Vector2(m, y))
		y += 36.0 * L
	y += 34.0 * L
	_ink(c, Plate.FONT_BOLD, 14, "BUILDINGS OWNED", Vector2(m, y))
	y += 24.0 * L
	c.draw_rect(Rect2(m, y, inner, 1.5 * L), Color(NAVY, 0.35))
	y = _strip_top
	if _rows.is_empty():
		_ink(c, FONT_PLEX, 14, "None", Vector2(m, y + 20.0 * L), INK_DIM)
		return
	var cell_w := inner / _rows.size()
	var bld := minf(STRIP["bld"] * L, cell_w - 10.0)
	var good := STRIP["good"] * L
	for k in _rows.size():
		var row: Dictionary = _rows[k]
		var cx := m + cell_w * (k + 0.5)
		if k == _hover_cell:
			var hit_w := minf(cell_w, 150.0 * L)
			_dashed_round(c, Rect2(cx - hit_w * 0.5 + 6.0 * L, y - 8.0 * L, hit_w - 12.0 * L, bld + good + 36.0 * L), 8.0 * L, Color(NAVY, 0.55))
		var art: Texture2D = BuildingIcon.clean_texture(String(row["bid"]), String(row["internal"]))
		if art != null:
			var box := Rect2(cx - bld * 0.5, y, bld, bld)
			var k2 := minf(box.size.x / art.get_width(), box.size.y / art.get_height())
			var ds := Vector2(art.get_width(), art.get_height()) * k2
			c.draw_texture_rect(art, Rect2(box.get_center() - ds * 0.5, ds), false, NAVY)
		c.draw_line(Vector2(cx, y + bld + 4.0 * L), Vector2(cx, y + bld + 16.0 * L), Color(NAVY, 0.5), 2.0 * L, true)
		var gid := String(row["gid"])
		if gid != "":
			_good_tile(c, GoodIcons.texture_for_size(gid, String(row["ginternal"]), good), Rect2(cx - good * 0.5, y + bld + 20.0 * L, good, good))


func _draw_right_leaf() -> void:
	var c := _right_leaf
	var w := c.size.x
	PParts.draw_nine(c, PParts.tex("registry_leaf"), Rect2(Vector2.ZERO, c.size), LEAF["margin"], LEAF["corner"])
	if _chosen.is_empty():
		return
	var m := LEAF["m"] * L
	var inner := w - 2.0 * m
	_ink(c, Plate.FONT_BOLD, 14, "FINANCIALS", Vector2(m, 62.0 * L))
	c.draw_rect(Rect2(m, 86.0 * L, inner, 2.0 * L), INK_FAINT)
	var y := 122.0 * L
	for k in _ledger.size():
		var line: Array = _ledger[k]
		_ink(c, FONT_PLEX, 14, String(line[0]), Vector2(m + 6.0 * L, y))
		_ink(c, FONT_PLEX_SEMI, 15, String(line[1]), Vector2(w - m - 6.0 * L, y), line[2] as Color, HORIZONTAL_ALIGNMENT_RIGHT)
		c.draw_rect(Rect2(m, y + 26.0 * L, inner, 1.2 * L), Color(NAVY, 0.28))
		if k == _ledger.size() - 1:
			c.draw_rect(Rect2(m, y + 30.0 * L, inner, 1.2 * L), Color(NAVY, 0.28))
		y += 54.0 * L
	y += 30.0 * L
	_ink(c, Plate.FONT_BOLD, 14, "COMPANY COLOUR", Vector2(m, y))
	y += 24.0 * L
	c.draw_rect(Rect2(m, y, inner, 1.5 * L), Color(NAVY, 0.35))
	var o := _paint_origin()
	var sq := PAINT["sq"] * L
	var gap := PAINT["gap"] * L
	var colours := PlayerColours.all()
	var chosen_label := ""
	for k in colours.size():
		var entry: Dictionary = colours[k]
		var r := Rect2(o + Vector2((k % PAINT["cols"]) * (sq + gap), (k / PAINT["cols"]) * (sq + gap)), Vector2(sq, sq))
		var chosen := str(entry["key"]) == _colour_key
		_round_fill(c, Rect2(r.position + Vector2(0, 1.5 * L), r.size).grow(1.0), 8.0 * L, Color(0, 0, 0, 0.3))
		_round_fill(c, r, 8.0 * L, entry["color"] as Color)
		_round_stroke(c, r, 8.0 * L, 2.2 if chosen else 0.8, NAVY if chosen else Color(NAVY, 0.4))
		if chosen:
			chosen_label = str(entry["label"])
			var cc := r.position + Vector2(sq - 18.0 * L, 18.0 * L)
			c.draw_circle(cc, 13.0 * L, LABEL_CREAM)
			c.draw_polyline(PackedVector2Array([cc + Vector2(-7, 0) * L, cc + Vector2(-2, 6) * L, cc + Vector2(7, -6) * L]), NAVY, 3.0 * L, true)
	y = o.y + 2.0 * sq + gap + 36.0 * L
	_ink(c, FONT_PLEX_SEMI, 15, chosen_label, Vector2(m + 6.0 * L, y))
	_ink(c, FONT_PLEX, 12, "Press a square to repaint.", Vector2(w - m - 6.0 * L, y), INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_slip() -> void:
	var c := _slip
	PParts.draw_nine(c, PParts.tex("registry_slip"), Rect2(Vector2.ZERO, c.size), SLIP["margin"], SLIP["corner"])
	if _hover_cell < 0 or _hover_cell >= _rows.size():
		return
	var row: Dictionary = _rows[_hover_cell]
	_ink(c, FONT_PLEX_SEMI, 14, String(row["name"]), Vector2(22.0 * L, 34.0 * L), NAVY, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 44.0 * L)
	_ink(c, FONT_PLEX, 12, String(row["place"]), Vector2(22.0 * L, 66.0 * L), INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 44.0 * L)


func _draw_form() -> void:
	var c := _form
	var w := c.size.x
	var h := c.size.y
	PParts.draw_nine(c, PParts.tex("sheet_white"), Rect2(Vector2.ZERO, c.size), FORM["margin"], FORM["corner"])
	var m := FORM["m"] * L
	var inner := w - 2.0 * m
	_ink(c, Plate.FONT_BOLD, 17, "FORM OF INCORPORATION", Vector2(w * 0.5, 62.0 * L), NAVY, HORIZONTAL_ALIGNMENT_CENTER)
	_ink(c, FONT_PLEX, 12, "The Registry of Companies", Vector2(w * 0.5, 98.0 * L), INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	c.draw_rect(Rect2(m, 126.0 * L, inner, 2.0 * L), INK_FAINT)
	_field(c, 168.0 * L, "COMPANY", m, inner)
	_ink(c, FONT_PLEX_SEMI, 16, String(_chosen.get("title", "")), Vector2(m, 204.0 * L), NAVY, HORIZONTAL_ALIGNMENT_LEFT, inner)
	_field(c, 262.0 * L, "GRADE", m, inner)
	var grade := _grade()
	_impression(c, String(grade.get("label", "")).to_upper(), Vector2(m + 250.0 * L, 306.0 * L), 236.0 * L)
	var y := 364.0 * L
	var tp := TextParagraph.new()
	tp.width = inner
	var words := grade_words(String(grade.get("desc", "")))
	tp.add_string(words, FONT_PLEX, 12)
	for i in tp.get_line_count():
		var rng := tp.get_line_range(i)
		_ink(c, FONT_PLEX, 12, words.substr(rng.x, rng.y - rng.x).strip_edges(), Vector2(m, y))
		y += 32.0 * L
	_field(c, 452.0 * L, "CHARTER", m, inner)
	if _demo_locked():
		_ink(c, FONT_PLEX, 14, DEMO_CHARTER, Vector2(m, 500.0 * L))
		_ink(c, FONT_PLEX, 12, DEMO_SURVEY, Vector2(m, 540.0 * L), INK_DIM)
		_impression(c, "DEMO", Vector2(w - m - 130.0 * L, 500.0 * L), 200.0 * L)
	else:
		_ink(c, FONT_PLEX, 14, "Charter of", Vector2(m, 500.0 * L))
		var opt: Dictionary = SPEEDS[clampi(_speed_index, 0, SPEEDS.size() - 1)]
		var after := "turns" if String(opt.get("policy_timeline", "")) == "" else "turns, the Itch.io demo"
		_ink(c, FONT_PLEX, 14, after, Vector2(m + 420.0 * L, 500.0 * L))
		_era_rule(c, Rect2(m, 614.0 * L, inner, 0), _speed_turns)
		_ink(c, FONT_PLEX, 12, "This also changes the Era pacing.", Vector2(m, 674.0 * L), INK_DIM)
		_field(c, 724.0 * L, "OPTIONS", m, inner)
		_tick(c, Vector2(m, 772.0 * L), true, "All tiles surveyed at game start", inner)
		if _metrics_box != null:
			_tick(c, Vector2(m, 820.0 * L), _send_metrics, "Send anonymous metrics", inner)
	var sc := _seal_centre()
	if _stamp_t >= STAMP_DOWN:
		_draw_seal_impression(c, sc, SEAL_R * L)
	else:
		_dashed_circle(c, sc, SEAL_R * L, Color(NAVY, 0.55))
		_ink(c, Plate.FONT_SEMI, 12, "SEAL", sc, Color(NAVY, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	_ink(c, FONT_PLEX, 12, "Registrar", Vector2(m, h - 60.0 * L), INK_DIM)
	c.draw_rect(Rect2(m, h - 40.0 * L, 260.0 * L, 1.5 * L), Color(NAVY, 0.4))


## A grade's words as the form prints them: the deposits part only. The sentence about how much is surveyed is
## left out while the All tiles surveyed option is on (which it always is today, and in the demo every tile is
## surveyed), since it would contradict the option printed under it.
func grade_words(desc: String) -> String:
	if not _survey_all:
		return desc
	var kept: Array = []
	for sentence in desc.split(". "):
		var t := String(sentence).strip_edges()
		if t == "" or "surveyed" in t:
			continue
		kept.append(t.trim_suffix("."))
	return ". ".join(kept) + ("." if not kept.is_empty() else "")


func _grade() -> Dictionary:
	for opt in DIFFICULTIES:
		if String(opt["id"]) == _difficulty_id:
			return opt
	return DIFFICULTIES[DIFFICULTY_DEFAULT]


## A field of the form: its printed name and the rule under it.
func _field(c: CanvasItem, y: float, label: String, m: float, inner: float) -> void:
	_ink(c, Plate.FONT_SEMI, 12, label, Vector2(m, y), INK_DIM)
	c.draw_rect(Rect2(m, y + 56.0 * L, inner, 1.5 * L), Color(NAVY, 0.3))


## The era rule: a line from turn 0 to the charter's end, a tick every ten turns with the hundreds printed, and a red
## mark with its name at each beat of the policy timeline the charter runs under. Names of marks close together
## step up a row each, so they never print over one another.
func _era_rule(c: CanvasItem, r: Rect2, turns: int) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var ry := r.position.y
	c.draw_line(Vector2(x0, ry), Vector2(x1, ry), NAVY, 2.0 * L, true)
	var step := 10
	var big := 100 if turns > 150 else 50
	for t in range(0, turns + 1, step):
		var x := x0 + (x1 - x0) * float(t) / float(turns)
		var is_big := t % big == 0
		c.draw_line(Vector2(x, ry), Vector2(x, ry + (14.0 if is_big else 7.0) * L), NAVY, 1.0, true)
		if is_big:
			_ink(c, FONT_PLEX, 12, str(t), Vector2(x, ry + 30.0 * L), NAVY, HORIZONTAL_ALIGNMENT_CENTER)
	var marks := era_marks(turns, _policy_timeline)
	var row_x: Array = []   # the right end of the last name printed on each row
	for mk in marks:
		var x := x0 + (x1 - x0) * float(int(mk["turn"])) / float(turns)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, ry - 3.0 * L), Vector2(x - 6.0 * L, ry - 14.0 * L), Vector2(x + 6.0 * L, ry - 14.0 * L)]), STAMP_RED)
		var label := String(mk["label"])
		var lw := Plate.FONT_SEMI.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var flip := x + 8.0 + lw > x1
		var left := (x - 8.0 - lw) if flip else (x + 8.0)
		var row := 0
		while row < row_x.size() and float(row_x[row]) > left - 6.0:
			row += 1
		if row == row_x.size():
			row_x.append(-INF)
		row_x[row] = left + lw
		_ink(c, Plate.FONT_SEMI, 12, label, Vector2(left, ry - (9.0 + 13.0 * row)), STAMP_RED, HORIZONTAL_ALIGNMENT_LEFT)


func _tick(c: CanvasItem, at: Vector2, on: bool, label: String, inner: float) -> void:
	var box := Rect2(at.x, at.y - 15.0 * L, 30.0 * L, 30.0 * L)
	_round_stroke(c, box, 4.0 * L, 2.2 * L, NAVY)
	if on:
		c.draw_polyline(PackedVector2Array([at + Vector2(7, 0) * L, at + Vector2(13, 8) * L, at + Vector2(25, -10) * L]), NAVY, 3.4 * L, true)
	_ink(c, FONT_PLEX, 13, label, at + Vector2(46.0 * L, 0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, inner - 50.0 * L)


## The red stamp's impression at `centre`, set at a slant, its ink a little uneven.
func _impression(c: CanvasItem, label: String, centre: Vector2, w: float) -> void:
	var h := 64.0 * L
	for layer in [[Vector2(1.5, 1.0) * L, 0.3], [Vector2(-1.0, 1.5) * L, 0.26], [Vector2.ZERO, 0.86]]:
		c.draw_set_transform(centre + (layer[0] as Vector2), -0.07, Vector2.ONE)
		var col := Color(STAMP_RED, float(layer[1]))
		_round_stroke(c, Rect2(-w * 0.5, -h * 0.5, w, h), 6.0 * L, 3.0 * L, col)
		_plain(c, Plate.FONT_BOLD, 23, label, Vector2(0, 1), col, HORIZONTAL_ALIGNMENT_CENTER, w - 36.0 * L)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stamps() -> void:
	var c := _stamps
	PParts.draw_nine(c, PParts.tex("registry_stamp_rack"), Rect2(Vector2.ZERO, _r_stamps.size), STAMPS["margin"], STAMPS["corner"])
	PParts.draw_fixed(c, PParts.tex("registry_ink_pad"), _r_pad.position, STAMPS["pad_margin"])


## Over the stamp keys: a padlock on each locked grade, or in a demo build the lockbox over the rack and the pad.
func _draw_stamps_over() -> void:
	var c := _stamps_over
	if _demo_locked():
		_draw_lid(c, _r_lid_stamps, true)
		return
	var lock: Texture2D = PParts.tex("registry_padlock")
	var s := lock.get_size() * 0.5 * 0.65
	for key in _grade_keys:
		if bool((key as Button).get("spent")):
			var kr := Rect2((key as Control).position, (key as Control).size)
			c.draw_texture_rect(lock, Rect2(Vector2(kr.end.x - 1.0 * L, kr.get_center().y + 4.0 * L) - s * 0.5, s), false)


func _draw_press() -> void:
	PParts.draw_fixed(_press, PParts.tex("registry_press"), Vector2.ZERO, PRESS["margin"])


## The die, drawn at its own size, larger while it is lifted (nearer the lamp).
func _draw_die() -> void:
	var tex: Texture2D = PParts.tex("registry_die")
	var k := DIE_SCALE_AT(_stamp_t)
	var s := tex.get_size() * 0.5 * k
	_die.draw_texture_rect(tex, Rect2((_die.size - s) * 0.5, s), false)


## The die's size at `t` seconds into the sequence: lifted between the lift and the drop and again as it rises.
static func DIE_SCALE_AT(t: float) -> float:
	if t < 0.0:
		return 1.0
	if t < STAMP_LIFT:
		return lerpf(1.0, DIE_LIFT_SCALE, t / STAMP_LIFT)
	if t < STAMP_SLIDE:
		return DIE_LIFT_SCALE
	if t < STAMP_DOWN:
		return lerpf(DIE_LIFT_SCALE, 1.0, (t - STAMP_SLIDE) / (STAMP_DOWN - STAMP_SLIDE))
	if t < STAMP_HOLD:
		return 1.0
	if t < STAMP_RISE:
		return lerpf(1.0, DIE_LIFT_SCALE, (t - STAMP_HOLD) / (STAMP_RISE - STAMP_HOLD))
	if t < STAMP_BACK:
		return DIE_LIFT_SCALE
	return lerpf(DIE_LIFT_SCALE, 1.0, minf(1.0, (t - STAMP_BACK) / (STAMP_SECONDS - STAMP_BACK)))


## Where the die rests on the press (its centre, in the panel), and the seal circle's centre on the form.
func _die_home() -> Vector2:
	var d: Array = [112.5, 92.0]
	return _r_press.position + Vector2(d[0], d[1]) * L


func _seal_centre() -> Vector2:
	return Vector2(_r_form.size.x - FORM["m"] * L - 80.0 * L, _r_form.size.y - 112.0 * L)


## The die's centre at `t`: on the press, sliding to the circle, over it while it stamps, sliding back and on the
## press again. Pure, so tests and the shot tool can set a moment.
func die_centre_at(t: float) -> Vector2:
	var home := _die_home()
	var there := _r_form.position + _seal_centre()
	if t < STAMP_LIFT:
		return home
	if t < STAMP_SLIDE:
		return home.lerp(there, ease((t - STAMP_LIFT) / (STAMP_SLIDE - STAMP_LIFT), -1.8))
	if t < STAMP_RISE:
		return there
	if t < STAMP_BACK:
		return there.lerp(home, ease((t - STAMP_RISE) / (STAMP_BACK - STAMP_RISE), -1.8))
	return home


func _place_die() -> void:
	if _die == null:
		return
	var tex: Texture2D = PParts.tex("registry_die")
	var side := tex.get_size() * 0.5 * DIE_LIFT_SCALE
	_die.position = die_centre_at(_stamp_t) - side * 0.5
	_die.size = side
	_die.queue_redraw()


## Sets the sequence to `t` seconds: the die's place and size, and the impression once it has come down.
func _set_stamp_time(t: float) -> void:
	var was_down := _stamp_t >= STAMP_DOWN
	_stamp_t = t
	_place_die()
	if (t >= STAMP_DOWN) != was_down:
		_form.queue_redraw()


## Seconds into the seal sequence, below zero before Start is pressed.
func stamp_time() -> float:
	return _stamp_t


## Whether the seal has been stamped on the form.
func is_sealed() -> bool:
	return _stamp_t >= STAMP_DOWN


## The seal's impression: the registry's mark embossed into the cream, two rings and its words, in a darker cream
## with a light edge up and to the left and a shadow down and to the right.
func _draw_seal_impression(c: CanvasItem, centre: Vector2, r: float) -> void:
	var deep := Color(0.55, 0.47, 0.34, 0.55)
	var light := Color(1, 1, 1, 0.7)
	var dark := Color(0.2, 0.15, 0.08, 0.35)
	for ring in [r, r - 5.0, r * 0.62, r * 0.56]:
		c.draw_arc(centre + Vector2(-1, -1), ring, 0.0, TAU, 72, light, 1.6, true)
		c.draw_arc(centre + Vector2(1, 1), ring, 0.0, TAU, 72, dark, 1.6, true)
		c.draw_arc(centre, ring, 0.0, TAU, 72, deep, 1.4, true)
	var font: Font = Plate.FONT_BOLD
	var fs := 9
	_arc_text(c, font, fs, "REGISTRY OF COMPANIES", centre, r * 0.84, -PI * 0.5, deep, light, dark)
	_arc_text(c, font, fs, "CARBON AND CAPITAL", centre, r * 0.84, PI * 0.5, deep, light, dark, true)
	for off in [[Vector2(-1, -1), light], [Vector2(1, 1), dark], [Vector2.ZERO, deep]]:
		var at: Vector2 = centre + (off[0] as Vector2)
		var tw := font.get_string_size("SEALED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		c.draw_string(font, Vector2(at.x - tw * 0.5, at.y + 5.0), "SEALED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, off[1] as Color)


## Letters laid round an arc, centred on `mid` (an angle), reading clockwise above the centre or, `under`, counter
## clockwise below it so they stay upright.
static func _arc_text(c: CanvasItem, font: Font, fs: int, text: String, centre: Vector2, radius: float, mid: float,
		ink: Color, light: Color, dark: Color, under := false) -> void:
	var total := 0.0
	var widths: Array = []
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w
	var span := total / radius
	var a := mid - span * 0.5 if not under else mid + span * 0.5
	for i in text.length():
		var w: float = widths[i]
		var half := w * 0.5 / radius
		a += half if not under else -half
		var pos := centre + Vector2(cos(a), sin(a)) * radius
		var rot := a + PI * 0.5 if not under else a - PI * 0.5
		for off in [[Vector2(-1, -1), light], [Vector2(1, 1), dark], [Vector2.ZERO, ink]]:
			c.draw_set_transform(pos + (off[0] as Vector2), rot, Vector2.ONE)
			c.draw_string(font, Vector2(-w * 0.5, fs * 0.35), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, off[1] as Color)
		a += half if not under else -half
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Start New Game: the seal comes down on the form over STAMP_SECONDS, inputs held off and Esc ignored, then the
## old panel's start_requested goes out as before. Headless (tests, the balance runs) or with `animate` off the
## signal goes at once.
func _on_start_pressed() -> void:
	if _starting:
		return
	if not animate or DisplayServer.get_name() == "headless":
		super._on_start_pressed()
		return
	_starting = true
	_block.visible = true
	_start_key.disabled = true
	_start_key.call("set_busy", true)
	var tw := create_tween()
	tw.tween_method(_set_stamp_time, 0.0, STAMP_SECONDS, STAMP_SECONDS)
	tw.tween_callback(_emit_start)


func _emit_start() -> void:
	super._on_start_pressed()


## Whether the seal sequence is running or done, so the menu's Esc and clicks are held off.
func is_starting() -> bool:
	return _starting


func _input(event: InputEvent) -> void:
	if _starting:
		if visible and event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
		return
	super._input(event)


# ── Print helpers ───────────────────────────────────────────────────────────────

## Navy ink on a light face: the text with a faint light shadow; `at.y` is the line's middle.
func _ink(c: CanvasItem, font: Font, px: int, text: String, at: Vector2, colour: Color = NAVY,
		align := HORIZONTAL_ALIGNMENT_LEFT, max_w := -1.0) -> void:
	if text == "":
		return
	var fs := px if max_w < 0.0 else maxi(10, Plate._fit(font, text, px, max_w))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x - (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	var baseline := Vector2(x, at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	c.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK_SHADOW)
	c.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


## Print without a shadow (the stamp's ink).
func _plain(c: CanvasItem, font: Font, px: int, text: String, at: Vector2, colour: Color, align: int, max_w: float) -> void:
	var fs := maxi(10, Plate._fit(font, text, px, max_w))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x - (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	c.draw_string(font, Vector2(x, at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


## White print on anything dark, with its dark shadow down and to the right.
func _white(c: CanvasItem, font: Font, px: int, text: String, at: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT, max_w := -1.0) -> void:
	var fs := px if max_w < 0.0 else maxi(12, Plate._fit(font, text, px, max_w))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x - (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	var baseline := Vector2(x, at.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	c.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE_SHADOW)
	c.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE["TEXT"])


## A good's cream tile with its icon at 84 percent, a soft shadow under it.
static func _good_tile(c: CanvasItem, icon: Texture2D, r: Rect2) -> void:
	var rad := r.size.x * 0.12
	_round_fill(c, Rect2(r.position + Vector2(1.5, 2.0), r.size), rad, Color(0, 0, 0, 0.3))
	_round_fill(c, r, rad, CREAM_TILE)
	if icon == null:
		return
	var s := r.size * 0.84
	c.draw_texture_rect(icon, Rect2(r.get_center() - s * 0.5, s), false)


static func _round_fill(c: CanvasItem, r: Rect2, radius: float, colour: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(int(roundf(radius)))
	c.draw_style_box(sb, r)


static func _round_stroke(c: CanvasItem, r: Rect2, radius: float, width: float, colour: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = colour
	sb.set_border_width_all(maxi(1, int(roundf(width))))
	sb.set_corner_radius_all(int(roundf(radius)))
	c.draw_style_box(sb, r)


## A dashed rounded outline (the pointed at building's), drawn as short runs along each side.
static func _dashed_round(c: CanvasItem, r: Rect2, radius: float, colour: Color) -> void:
	var dash := 6.0
	var gap := 5.0
	var sides := [[r.position + Vector2(radius, 0), Vector2(r.end.x - radius, r.position.y)],
		[Vector2(r.end.x, r.position.y + radius), r.end - Vector2(0, radius)],
		[r.end - Vector2(radius, 0), Vector2(r.position.x + radius, r.end.y)],
		[Vector2(r.position.x, r.end.y - radius), r.position + Vector2(0, radius)]]
	for s in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var len := a.distance_to(b)
		var d := (b - a).normalized()
		var t := 0.0
		while t < len:
			c.draw_line(a + d * t, a + d * minf(t + dash, len), colour, 2.0, true)
			t += dash + gap
	for corner in [[Vector2(r.position.x + radius, r.position.y + radius), PI, 1.5 * PI],
			[Vector2(r.end.x - radius, r.position.y + radius), 1.5 * PI, TAU],
			[Vector2(r.end.x - radius, r.end.y - radius), 0.0, 0.5 * PI],
			[Vector2(r.position.x + radius, r.end.y - radius), 0.5 * PI, PI]]:
		c.draw_arc(corner[0], radius, corner[1], corner[2], 6, colour, 2.0, true)


static func _dashed_circle(c: CanvasItem, centre: Vector2, radius: float, colour: Color) -> void:
	var n := 26
	for i in n:
		var a0 := TAU * float(i) / n
		c.draw_arc(centre, radius, a0, a0 + TAU / n * 0.55, 4, colour, 2.0, true)
