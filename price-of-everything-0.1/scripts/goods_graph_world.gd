extends Control
## Goods Graph — drawing layer.
##
## Draws the goods web (tier columns of good cards + orthogonal flow edges) entirely in
## _draw() under a manual camera (`_view_offset` + `_view_zoom`). Unlike the empire
## view's zoom-invariant fixed-pixel panels, EVERYTHING here scales with zoom (the
## chart behaves like a zoomable document): the layout is static tier columns, so
## cards can never jostle and no separation pass is needed. Drag / two-finger pan,
## scroll / pinch to zoom, WASD to pan. Hovering a good highlights its direct flows;
## clicking selects it and lights its whole upstream supply cone plus the goods it
## feeds (click empty space or the good again to clear). No sim logic (CLAUDE.md #2/#5).

signal good_selected(internal_name: String)   # phase 2 hook (focus / recipe-swap mode)

const LaneOrder := preload("res://scripts/lane_order.gd")
const GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const InfraIcons := preload("res://scripts/infra_icons.gd")

const _GOLD := Color(0.995, 0.931, 0.763, 1.0)
const _CREAM := Color(0.995234, 0.930806, 0.763265)
const _TEXT := Color(0.88, 0.92, 0.97, 1.0)
const _MUTED := Color(0.384, 0.471, 0.561, 1.0)          # tier headers (#62788f)
const _CARD_BG := Color(0.055, 0.125, 0.204, 0.92)
const _CARD_BG_GATED := Color(0.045, 0.095, 0.15, 0.85)
const _PILL_NAVY := Color(0.0, 0.119856, 0.243095)
# Recipe-route palette (owner 2026-07-18): yellow = the base recipe's inputs, then
# blue/green/purple for up to three alternate routes; research-gated routes dash.
const _ROUTE_COLORS: Array[Color] = [
	Color("#f2c14e"),   # 0 · base
	Color("#6f9fd8"),   # 1 · first alternate
	Color("#7ec98a"),   # 2 · second alternate
	Color("#b48ad9"),   # 3 · third alternate
]
# Resting/unrelated web alpha (owner 2026-07-21): the always-on web at 0.6 alpha
# was the screen's dominant noise, and nobody traces a line through 638 crossings
# without selecting anyway. At rest the web is a faint ghost (0.0 = none at all);
# hover lights a card's direct edges, click lights the full chain.
const _REST_GHOST_ALPHA := 0.10
# Legacy resting web, retained behind the `swap goods_graph` cheat for screenshots
# and A/B comparison with the pre-ghost implementation.
const _LEGACY_REST_ALPHA_BASE := 0.60
const _LEGACY_REST_ALPHA_ALT := 0.48
const _LEGACY_EDGE_DIM := Color(0.995, 0.931, 0.763, 0.08)

const _EDGE_WIDTH := 2.5                                  # world units (scales with zoom)
const _ZOOM_MIN := 0.07                                   # absolute fallback; the live floor is _zoom_floor (swimlane chart is tall)
const _LANE_GUTTER := 840.0                               # left room for swimlane labels (2-line names)
const _ZOOM_MAX := 1.0                                    # icon chips are 100 world units -> 100 px at max zoom-in
const _ZOOM_STEP := 1.12
const _PAN_SPEED := 900.0
const _CLICK_SLOP := 6.0                                  # px of drag that still counts as a click
const _CORNER_R := 10.0
const _FILLET_R := 10.0                                   # max corner rounding on edge waypoints
const _FILLET_STEPS := 4                                  # arc samples per corner (steps+1 points)

# Tier-header plates: Bebas Neue on an octagonal brushed-metal plate (the end-turn
# dock's machined-silver family, lit top-left like the research-panel plates).
const _BEBAS := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const _PLATE_LT := Color("#b3bcc6")
const _PLATE_DK := Color("#5b636e")
const _PLATE_TEXT := Color(0.035, 0.085, 0.15, 1.0)       # embossed navy
const _HEADER_GAP := 52.0                                 # clearance between plate and first card row
const _PLATE_H := 124.0                                   # tier-header plate at 2x (owner 2026-07-21)

var _nodes: Array = []
var _by_id: Dictionary = {}
var _edges: Array = []
var _tier_count: int = 0
var _bands: Array = []   # [{label, first, count}] — one header plate per band region
var _lanes: Array = []   # [{label, top, height, color}] — category swimlane bands

var _view_zoom: float = 1.0
var _view_offset: Vector2 = Vector2.ZERO
var _zoom_floor: float = _ZOOM_MIN   # fit-whole-graph zoom; you cannot zoom out past it
var _dragging := false
var _drag_travel := 0.0

var _hover_id := ""
var _selected_id := ""
var _upstream: Dictionary = {}     # internal -> true, transitive input cone of the selection
var _feeds: Dictionary = {}        # internal -> true, direct consumers of the selection
var _legacy_presentation := false  # session-only; false keeps the current presentation default

# --- alternate-recipes focus grid (owner UX 2026-07-19) ------------------------------
# WEB shows the base chain; selecting a good expands its card with its supported
# transport infrastructure plus two actions (alternate recipes -> GRID of per-recipe
# minigraph islands, Encyclopedia -> deep-link). GRID keeps the same pan/zoom camera.
enum _Mode { WEB, GRID, FOCUS }
var _mode := _Mode.WEB

# --- focus reorg (owner UX 2026-07-21) ----------------------------------------------
# Clicking a good REORGANISES the view around it: the selection + its upstream cone
# + direct feeds tween from their web positions into a compact relative-depth
# arrangement; everything else fades out in place. Click empty space to tween back.
# Focus-view routing (owner 2026-07-22): no run may cross a card, passing runs
# keep >= _F_CLEAR from cards, and no two edges share a collinear run — ports
# fan along card edges, verticals take per-channel lanes, column-skipping edges
# cross through card-free corridors.
const _FCOL_W := 720.0
const _FROW_H := 200.0
const _F_PORT_STEP := 24.0
const _F_LANE_PAD := 24.0
const _F_LANE_STEP := 14.0
const _F_CLEAR := 10.0
const _F_CORRIDOR_SEP := 28.0   # min gap between parallel long corridors
const _F_PORT_AVOID := 16.0     # corridors keep this far from port-stub runs
var _fpos: Dictionary = {}        # id -> focus position (world)
var _focus_edges: Array = []      # [{from,to,route,gated,dir,wp}]
var _focus_t := 0.0               # 0 = web, 1 = focus arrangement (animated)
var _focus_target := 0.0
var _focus_bbox := Rect2()
var _focus_saved_zoom := 1.0      # web camera restored on exit (GRID has its own save)
var _focus_saved_offset := Vector2.ZERO
var _grid_islands: Array = []      # [{recipe, gated, rect, header, inputs:[{...}], out_rect}]
var _grid_bbox := Rect2()
var _saved_zoom := 1.0
var _saved_offset := Vector2.ZERO
var _tray_buttons: Array = []      # [{rect (world), label, action}] for the expanded card
var _hover_tray := -1
var _grid_hover := -1              # island whose building icon is hovered (name tooltip)
var _back_btn: Button
var _search_box: LineEdit          # WEB-mode good search (min 3 letters, substring)
var _search_panel: PanelContainer  # dropdown holding up to 3 result buttons
var _search_hits: Array = []       # full match list (Enter auto-picks when exactly 1)


func _ready() -> void:
	set_process(true)
	resized.connect(_on_resized)
	# A drag interrupted by the view closing never receives its mouse-up; without
	# this reset the next open pans on bare mouse motion.
	visibility_changed.connect(func() -> void: _dragging = false)
	# The grid mode's exit — a real Control (screen-space, above the drawn canvas).
	_back_btn = Button.new()
	_back_btn.text = "Back to Goods Graph"
	_back_btn.theme_type_variation = &"Primary"
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.custom_minimum_size = Vector2(280.0, 54.0)
	_back_btn.add_theme_font_size_override("font_size", 20)
	# Top-LEFT: the top-centre slot belongs to the briefing notch. This control's
	# rect starts under HUDContent (screen y ~36) while the top bar is ~78 px tall,
	# so clear the remaining ~42 px of bar plus the owner's 20 px of air.
	_back_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_back_btn.offset_left = 24.0
	_back_btn.offset_right = 304.0
	_back_btn.offset_top = 62.0
	_back_btn.offset_bottom = 116.0
	_back_btn.visible = false
	_back_btn.pressed.connect(_exit_grid)
	add_child(_back_btn)
	# WEB-mode good search, sharing the grid Back button's top-left slot (the two
	# are never visible together). Min 3 letters, plain substring match, top 3
	# names; Enter auto-picks when exactly one good matches.
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search goods…"
	_search_box.custom_minimum_size = Vector2(300.0, 44.0)
	# Visible input chrome (the inherited theme is nearly transparent on the navy
	# canvas): navy field, gold rim brightening on focus, cream text.
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.03, 0.09, 0.16, 0.96)
	sb_normal.border_color = Color(_GOLD, 0.55)
	sb_normal.set_border_width_all(1)
	sb_normal.set_corner_radius_all(8)
	sb_normal.set_content_margin_all(10)
	var sb_focus := sb_normal.duplicate() as StyleBoxFlat
	sb_focus.border_color = _GOLD
	sb_focus.set_border_width_all(2)
	_search_box.add_theme_stylebox_override("normal", sb_normal)
	_search_box.add_theme_stylebox_override("focus", sb_focus)
	_search_box.add_theme_color_override("font_color", _CREAM)
	_search_box.add_theme_color_override("font_placeholder_color", Color(_CREAM, 0.45))
	_search_box.add_theme_font_size_override("font_size", 17)
	_search_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_search_box.offset_left = 24.0
	_search_box.offset_right = 324.0
	_search_box.offset_top = 62.0
	_search_box.offset_bottom = 106.0
	_search_box.text_changed.connect(_refresh_search)
	_search_box.text_submitted.connect(_submit_search)
	add_child(_search_box)
	_search_panel = PanelContainer.new()
	_search_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_search_panel.offset_left = 24.0
	_search_panel.offset_right = 324.0
	_search_panel.offset_top = 112.0
	_search_panel.visible = false
	var results := VBoxContainer.new()
	results.name = "Results"
	results.add_theme_constant_override("separation", 4)
	_search_panel.add_child(results)
	add_child(_search_panel)


func _on_resized() -> void:
	# The zoom-out cap is the fit zoom, which depends on the viewport size.
	_zoom_floor = _fit_zoom()
	_view_zoom = maxf(_view_zoom, _zoom_floor)
	queue_redraw()


func set_graph(graph: Dictionary) -> void:
	_nodes = graph.get("nodes", [])
	_by_id = graph.get("by_id", {})
	_edges = graph.get("edges", [])
	_tier_count = int(graph.get("tier_count", 0))
	_bands = graph.get("bands", [])
	_lanes = graph.get("lanes", [])
	_legacy_presentation = bool(graph.get("legacy_layout", false))
	_hover_id = ""
	_selected_id = ""
	_upstream.clear()
	_feeds.clear()
	_mode = _Mode.WEB
	_grid_islands.clear()
	_tray_buttons.clear()
	if _back_btn != null:
		_back_btn.visible = false
	if _search_box != null:
		_search_box.visible = true
		_search_box.text = ""
		_search_panel.visible = false
		_search_hits.clear()
	_reset_view()
	queue_redraw()


## Current screen-space card centres — the hex-field background ripples its
## origin pulses (anim 1) out of these, same contract as the empire view.
func building_screen_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _mode == _Mode.GRID:
		for isl in _grid_islands:
			out.append(_world_to_screen((isl["out_rect"] as Rect2).get_center()))
		return out
	for n in _nodes:
		out.append(_world_to_screen(n["pos"] as Vector2))
	return out


## The zoom at which the whole graph (whichever dimension binds) fits the viewport —
## this is also the zoom-OUT cap (owner: "can't zoom out more than that").
func _fit_zoom() -> float:
	var bb := _layout_bbox()
	var view := get_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1920.0, 1080.0)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return _ZOOM_MIN
	var pad := 150.0
	var fit := minf((view.x - pad) / bb.size.x, (view.y - pad) / bb.size.y)
	return clampf(fit, _ZOOM_MIN, _ZOOM_MAX)


func _reset_view() -> void:
	var bb := _layout_bbox()
	var view := get_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1920.0, 1080.0)
	_zoom_floor = _fit_zoom()
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		_view_zoom = 1.0
		_view_offset = view * 0.5
		return
	_view_zoom = _zoom_floor
	_view_offset = view * 0.5 - bb.get_center() * _view_zoom


func _layout_bbox() -> Rect2:
	if _mode == _Mode.FOCUS:
		return _focus_bbox
	if _mode == _Mode.GRID:
		# Headroom above the islands for the screen-space Back button.
		var gb := _grid_bbox
		gb.position.y -= 110.0
		gb.size.y += 110.0
		return gb
	var bb := Rect2()
	var first := true
	for n in _nodes:
		var r := Rect2((n["pos"] as Vector2) - (n["half"] as Vector2), (n["half"] as Vector2) * 2.0)
		if first:
			bb = r
			first = false
		else:
			bb = bb.merge(r)
	# Edge corridors extend past the cards (cycle back-edges dive below the deepest
	# row); include every waypoint so the fitted view doesn't clip them.
	for e in _edges:
		var wp: PackedVector2Array = (e as Dictionary).get("waypoints", PackedVector2Array())
		for p: Vector2 in wp:
			if first:
				bb = Rect2(p, Vector2.ZERO)
				first = false
			else:
				bb = bb.expand(p)
	# Headroom for the tier-header plates and the gap beneath them.
	bb.position.y -= _HEADER_GAP + _PLATE_H + 40.0
	bb.size.y += _HEADER_GAP + _PLATE_H + 40.0
	# Left gutter for the swimlane category labels.
	if not _lanes.is_empty():
		bb.position.x -= _LANE_GUTTER
		bb.size.x += _LANE_GUTTER
	return bb


func _world_to_screen(p: Vector2) -> Vector2:
	return p * _view_zoom + _view_offset


func _screen_to_world(p: Vector2) -> Vector2:
	return (p - _view_offset) / _view_zoom


# --- interaction -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, _ZOOM_STEP)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / _ZOOM_STEP)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _search_box != null and _search_box.has_focus():
					_search_box.release_focus()
					_search_panel.visible = false
				_dragging = true
				_drag_travel = 0.0
			else:
				if _dragging and _drag_travel <= _CLICK_SLOP:
					_click_at(event.position)
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			_view_offset += event.relative
			_drag_travel += event.relative.length()
			queue_redraw()
		else:
			_update_hover(event.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		_view_offset -= event.delta * 22.0
		queue_redraw()
		accept_event()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, _zoom_floor, _ZOOM_MAX)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	var f := new_zoom / _view_zoom
	_view_offset = screen_pos - (screen_pos - _view_offset) * f
	_view_zoom = new_zoom
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _focus_t != _focus_target:
		_focus_t = move_toward(_focus_t, _focus_target, delta / 0.28)
		if _focus_target <= 0.0 and _focus_t <= 0.0:
			_fpos.clear()
			_focus_edges.clear()
		queue_redraw()
	if _search_box != null and _search_box.has_focus():
		return   # typing in the search bar must not WASD-pan the camera
	var dir := Vector2.ZERO
	if Input.is_action_pressed("camera_right"):
		dir.x -= 1.0
	if Input.is_action_pressed("camera_left"):
		dir.x += 1.0
	if Input.is_action_pressed("camera_down"):
		dir.y -= 1.0
	if Input.is_action_pressed("camera_up"):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		_view_offset += dir.normalized() * _PAN_SPEED * delta
		queue_redraw()


func _node_at(screen_pos: Vector2) -> String:
	var w := _screen_to_world(screen_pos)
	if _mode == _Mode.FOCUS:
		# Only the focus members are visible/clickable, at their focus positions.
		for id in _fpos:
			var half2: Vector2 = (_by_id.get(str(id), {}) as Dictionary).get("half", Vector2.ZERO)
			if Rect2((_fpos[id] as Vector2) - half2, half2 * 2.0).has_point(w):
				return str(id)
		return ""
	for n in _nodes:
		var half: Vector2 = n["half"]
		if Rect2((n["pos"] as Vector2) - half, half * 2.0).has_point(w):
			return str(n["id"])
	return ""


func _update_hover(screen_pos: Vector2) -> void:
	if _mode == _Mode.GRID:
		var w2 := _screen_to_world(screen_pos)
		var gh := -1
		for i in range(_grid_islands.size()):
			if ((_grid_islands[i] as Dictionary)["bicon_rect"] as Rect2).has_point(w2):
				gh = i
				break
		if gh != _grid_hover:
			_grid_hover = gh
			queue_redraw()
		return
	var w := _screen_to_world(screen_pos)
	var tray := _tray_button_at(w)
	var id := "" if tray >= 0 else _node_at(screen_pos)
	if id != _hover_id or tray != _hover_tray:
		_hover_id = id
		_hover_tray = tray
		var clickable := id != "" or tray >= 0
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
		queue_redraw()


func _tray_button_at(world_pos: Vector2) -> int:
	for i in range(_tray_buttons.size()):
		if ((_tray_buttons[i] as Dictionary)["rect"] as Rect2).has_point(world_pos):
			return i
	return -1


func _click_at(screen_pos: Vector2) -> void:
	if _mode == _Mode.GRID:
		return   # grid clicks: only the Back button (a real Control) acts
	var tray := _tray_button_at(_screen_to_world(screen_pos))
	if tray >= 0:
		var action := str((_tray_buttons[tray] as Dictionary)["action"])
		if action == "alternates":
			_enter_grid(_selected_id)
		elif action == "encyclopedia":
			var gid := str((_by_id.get(_selected_id, {}) as Dictionary).get("good_id", ""))
			if gid != "":
				MatchState.encyclopedia_good_requested.emit(gid)
		return
	var id := _node_at(screen_pos)
	if id == "" or id == _selected_id:
		_clear_selection()
		return
	select_good(id)


## Select a good by internal name and light its trace. Public for the screenshot
## tool and the phase-2 deep links (e.g. "show me steel" from the encyclopedia).
func select_good(id: String) -> void:
	if (_mode != _Mode.WEB and _mode != _Mode.FOCUS) or not _by_id.has(id):
		return
	_selected_id = id
	_upstream = _collect_upstream(id)
	_feeds.clear()
	for f in (_by_id.get(id, {}) as Dictionary).get("feeds", []):
		_feeds[f] = true
	if not _legacy_presentation:
		_enter_focus()
	good_selected.emit(id)
	queue_redraw()


func _clear_selection() -> void:
	if _selected_id == "":
		return
	_exit_focus()
	_selected_id = ""
	_upstream.clear()
	_feeds.clear()
	_tray_buttons.clear()
	_hover_tray = -1
	queue_redraw()


## Enter (or re-target) the focus arrangement for the current selection. The web
## camera is saved only on the WEB -> FOCUS transition; refocusing keeps it.
func _enter_focus() -> void:
	if _mode == _Mode.WEB:
		_focus_saved_zoom = _view_zoom
		_focus_saved_offset = _view_offset
	_build_focus_layout()
	_mode = _Mode.FOCUS
	_focus_target = 1.0
	_hover_id = ""
	_reset_view()   # fit the camera to the focus arrangement (_layout_bbox branches)


func _exit_focus() -> void:
	if _mode != _Mode.FOCUS:
		return
	_mode = _Mode.WEB
	_focus_target = 0.0
	_view_zoom = _focus_saved_zoom
	_view_offset = _focus_saved_offset
	_zoom_floor = _fit_zoom()
	queue_redraw()


## Relative-depth arrangement: selection at the origin, its upstream cone in
## columns to the left (by tier distance), direct feeds one column right; each
## column stacked and centred. Focus edges follow the trace rules (base cone +
## every route into the selection + selection -> feeds).
func _build_focus_layout() -> void:
	_fpos.clear()
	_focus_edges.clear()
	var sel := _selected_id
	# 1 · Kept edges first (trace rules) — the column logic below needs them to
	# detect within-band chains.
	for e in _edges:
		var ef := str(e["from"])
		var et := str(e["to"])
		var route := int(e.get("route", 0))
		var member_f := ef == sel or _upstream.has(ef) or _feeds.has(ef)
		var member_t := et == sel or _upstream.has(et) or _feeds.has(et)
		if not (member_f and member_t and _by_id.has(ef) and _by_id.has(et)):
			continue
		var keep := (route == 0 and (_upstream.has(et) or et == sel) and _upstream.has(ef)) \
			or et == sel or (ef == sel and _feeds.has(et))
		if not keep:
			continue
		_focus_edges.append({"from": ef, "to": et, "route": route,
			"gated": bool(e.get("route_gated", false))})
	# 2 · Focus columns by TIER BAND (owner 2026-07-22): same-band members share
	# one column and stack vertically — iron ore + coal sit up-down, not in a
	# row — UNLESS a kept edge links two members of the band (a within-band
	# chain), which splits that band into web-order sub-columns.
	var col_band: Dictionary = {}
	for bi: int in range(_bands.size()):
		var bnd: Dictionary = _bands[bi]
		var b0 := int(bnd.get("first", 0))
		for c: int in range(b0, b0 + int(bnd.get("count", 1))):
			col_band[c] = bi
	var sel_band := int(col_band.get(_col_of(sel), 0))
	var members: Dictionary = {sel: 0.0}   # id -> sortable column key (band*100+sub)
	for id in _upstream:
		if _by_id.has(str(id)):
			var bd := int(col_band.get(_col_of(str(id)), 0)) - sel_band
			members[str(id)] = float(mini(-1, bd)) * 100.0
	for id in _feeds:
		if _by_id.has(str(id)):
			# +1 shift keeps same-band feeds (e.g. motor for steel) clear of the
			# selection column while later bands stay separated.
			var bd := int(col_band.get(_col_of(str(id)), 0)) - sel_band
			members[str(id)] = float(maxi(1, bd + 1)) * 100.0
	var groups: Dictionary = {}
	for id: String in members:
		var gk: float = members[id]
		if not groups.has(gk):
			groups[gk] = []
		(groups[gk] as Array).append(id)
	for gk in groups:
		var garr: Array = groups[gk]
		if garr.size() < 2 or float(gk) == 0.0:
			continue
		var internal := false
		for fe in _focus_edges:
			if garr.has(str(fe["from"])) and garr.has(str(fe["to"])):
				internal = true
				break
		if not internal:
			continue
		var wcols: Array = []
		for id: String in garr:
			var wc := _col_of(id)
			if not wcols.has(wc):
				wcols.append(wc)
		wcols.sort()
		for id: String in garr:
			members[id] = float(gk) + float(wcols.find(_col_of(id)))
	# 3 · Compress the keys to consecutive integer columns (order preserved).
	var neg: Array = []
	var pos_cols: Array = []
	for id: String in members:
		var ck: float = members[id]
		if ck < 0.0 and not neg.has(ck):
			neg.append(ck)
		elif ck > 0.0 and not pos_cols.has(ck):
			pos_cols.append(ck)
	neg.sort()
	pos_cols.sort()
	var remap: Dictionary = {0.0: 0}
	for i: int in range(neg.size()):
		remap[neg[i]] = -(neg.size() - i)
	for i: int in range(pos_cols.size()):
		remap[pos_cols[i]] = i + 1
	var buckets: Dictionary = {}
	for id: String in members:
		var c: int = int(remap[members[id]])
		members[id] = c
		if not buckets.has(c):
			buckets[c] = []
		(buckets[c] as Array).append(id)
	var first := true
	for c: int in buckets:
		var arr: Array = buckets[c]
		# Stable, familiar order: keep the web's vertical order within a column.
		arr.sort_custom(func(a: String, b: String) -> bool:
			return ((_by_id[a] as Dictionary)["pos"] as Vector2).y \
				< ((_by_id[b] as Dictionary)["pos"] as Vector2).y)
		for i: int in range(arr.size()):
			var p := Vector2(float(c) * _FCOL_W,
				(float(i) - float(arr.size() - 1) * 0.5) * _FROW_H)
			_fpos[arr[i]] = p
			var half: Vector2 = (_by_id[arr[i]] as Dictionary)["half"]
			var r := Rect2(p - half, half * 2.0)
			_focus_bbox = r if first else _focus_bbox.merge(r)
			first = false
	_route_focus_edges(members)
	_focus_bbox = _focus_bbox.grow(220.0)


## Orthogonal routes for the focus edges (owner 2026-07-22): no run crosses a
## card rect; runs that don't touch a card keep >= _F_CLEAR of clearance; no two
## edges share a collinear run (distinct ports, lanes and corridors).
func _route_focus_edges(members: Dictionary) -> void:
	var half_w := GoodsFlowGraph.CARD_W * 0.5
	# 1 · Directions and channels.
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		var cf := int(members[str(fe["from"])])
		var ct := int(members[str(fe["to"])])
		var dirn := 1 if ct >= cf else -1
		fe["dir"] = dirn
		fe["cf"] = cf
		fe["ct"] = ct
		fe["exit_ch"] = cf if dirn == 1 else cf - 1
		fe["entry_ch"] = ct - 1 if dirn == 1 else ct
	# 2 · PASS-1 ports anchored by the far card's centre, to seed corridor picks.
	var anchors: Dictionary = {}
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		anchors["%d:o" % ei] = (_fpos[str(fe["to"])] as Vector2).y
		anchors["%d:i" % ei] = (_fpos[str(fe["from"])] as Vector2).y
	var port_y := _assign_focus_ports(anchors)
	# 3 · Corridors for column-skipping edges, chosen by MINIMUM TOTAL VERTICAL
	# TRAVEL (owner 2026-07-22: coal->steel must go over the top of iron ingots,
	# not dive below — the general rule, not a special case). Corridors also keep
	# clear of each other and of every port-stub run.
	var used_transit: Array = []
	var all_port_ys: Array = port_y.values()
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		if int(fe["exit_ch"]) != int(fe["entry_ch"]):
			var cf := int(fe["cf"])
			var ct := int(fe["ct"])
			var tyy := _f_transit_y(mini(cf, ct) + 1, maxi(cf, ct) - 1,
				float(port_y["%d:o" % ei]), float(port_y["%d:i" % ei]),
				used_transit, all_port_ys)
			used_transit.append(tyy)
			fe["ty"] = tyy
	# 4 · PASS-2 ports: a skip edge's real departure direction is its CORRIDOR,
	# so both of its ports re-anchor to the corridor y — the topmost port leads
	# to the top corridor and stubs never cross leaving the card.
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		if fe.has("ty"):
			anchors["%d:o" % ei] = float(fe["ty"])
			anchors["%d:i" % ei] = float(fe["ty"])
	port_y = _assign_focus_ports(anchors)
	# 5 · Lane ordering per channel by MINIMUM PAIRWISE CROSSINGS (owner
	# 2026-07-22b: coal->ingots cut through coal->steel's corridor run —
	# shortest-span nesting only prevents riser braiding and is blind to the
	# horizontal runs that continue past a lane). Each leg in a channel is a Z:
	# entry stub at ys, vertical to ye, exit run at ye, with both horizontals
	# reaching past every other lane. For any two legs the crossing count
	# depends ONLY on which lane sits left of the other, so the best order is a
	# linear-arrangement problem — solved exactly (subset DP) per channel.
	var chan_reqs: Dictionary = {}   # channel -> [[ei, leg, ys, ye, dir]]
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		var oy: float = port_y["%d:o" % ei]
		var iy: float = port_y["%d:i" % ei]
		var midy: float = float(fe["ty"]) if fe.has("ty") else iy
		var dirn := int(fe["dir"])
		var xch := int(fe["exit_ch"])
		if not chan_reqs.has(xch):
			chan_reqs[xch] = []
		(chan_reqs[xch] as Array).append([ei, 0, oy, midy, dirn])
		if fe.has("ty"):
			var ech := int(fe["entry_ch"])
			if not chan_reqs.has(ech):
				chan_reqs[ech] = []
			(chan_reqs[ech] as Array).append([ei, 1, float(fe["ty"]), iy, dirn])
	var lane_x: Dictionary = {}   # "ei:leg" -> world x
	for ch in chan_reqs:
		var order := _f_lane_order(chan_reqs[ch] as Array)
		for li: int in range(order.size()):
			var rq: Array = order[li]
			lane_x["%d:%d" % [int(rq[0]), int(rq[1])]] = \
				float(ch) * _FCOL_W + GoodsFlowGraph.CARD_W * 0.5 + _F_LANE_PAD \
				+ float(li) * _F_LANE_STEP
	# 6 · Waypoints.
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		var f := str(fe["from"])
		var t := str(fe["to"])
		var dirn := int(fe["dir"])
		var oy: float = port_y["%d:o" % ei]
		var iy: float = port_y["%d:i" % ei]
		var p0 := Vector2((_fpos[f] as Vector2).x + half_w * float(dirn), oy)
		var p3 := Vector2((_fpos[t] as Vector2).x - half_w * float(dirn), iy)
		var lx_exit := float(lane_x["%d:0" % ei])
		var wp := PackedVector2Array()
		wp.append(p0)
		if not fe.has("ty"):
			wp.append(Vector2(lx_exit, oy))
			wp.append(Vector2(lx_exit, iy))
		else:
			var lx_entry := float(lane_x["%d:1" % ei])
			var tyy := float(fe["ty"])
			wp.append(Vector2(lx_exit, oy))
			wp.append(Vector2(lx_exit, tyy))
			wp.append(Vector2(lx_entry, tyy))
			wp.append(Vector2(lx_entry, iy))
		wp.append(p3)
		fe["wp"] = wp


## A corridor y crossing focus columns lo..hi clear of every card there by
## >= _F_CLEAR, as close as possible to want_y, and >= 12u from prior corridors.
## Port assignment: each edge end gets its own y on its card edge, ordered by
## its anchor (the far card's centre, or the corridor y for skip edges) so the
## stubs fan without crossing as they leave the card.
func _assign_focus_ports(anchors: Dictionary) -> Dictionary:
	var side_edges: Dictionary = {}   # "id|R"/"id|L" -> [[anchor_y, ei, is_out]]
	for ei: int in range(_focus_edges.size()):
		var fe: Dictionary = _focus_edges[ei]
		var dirn := int(fe["dir"])
		var fkey := str(fe["from"]) + ("|R" if dirn == 1 else "|L")
		var tkey := str(fe["to"]) + ("|L" if dirn == 1 else "|R")
		if not side_edges.has(fkey):
			side_edges[fkey] = []
		if not side_edges.has(tkey):
			side_edges[tkey] = []
		(side_edges[fkey] as Array).append([float(anchors["%d:o" % ei]), ei, true])
		(side_edges[tkey] as Array).append([float(anchors["%d:i" % ei]), ei, false])
	var port_y: Dictionary = {}   # "ei:o"/"ei:i" -> world y
	for key: String in side_edges:
		var arr: Array = side_edges[key]
		arr.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) \
				or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
		var cy := (_fpos[key.split("|")[0]] as Vector2).y
		var n := arr.size()
		var step := 0.0
		if n > 1:
			step = minf(_F_PORT_STEP, (GoodsFlowGraph.CARD_H - 28.0) / float(n - 1))
		for i: int in range(n):
			var rec: Array = arr[i]
			port_y["%d:%s" % [int(rec[1]), "o" if bool(rec[2]) else "i"]] = \
				cy + (float(i) - float(n - 1) * 0.5) * step
	return port_y


## A corridor y crossing focus columns lo..hi, clear of every card there by
## >= _F_CLEAR, chosen by MINIMUM TOTAL VERTICAL TRAVEL (|oy-y| + |iy-y|) so the
## route goes over/under obstacles on whichever side is genuinely shorter, and
## kept >= _F_CORRIDOR_SEP from other corridors / >= _F_PORT_AVOID from every
## port-stub run so long horizontals never read as one line.
func _f_transit_y(lo: int, hi: int, oy: float, iy: float, used: Array, port_ys: Array) -> float:
	var blocked: Array = []   # [y0, y1] per card, grown by the clearance
	for id: String in _fpos:
		var p: Vector2 = _fpos[id]
		var c := int(roundf(p.x / _FCOL_W))
		if c < lo or c > hi:
			continue
		var half: Vector2 = (_by_id[id] as Dictionary)["half"]
		blocked.append([p.y - half.y - _F_CLEAR, p.y + half.y + _F_CLEAR])
	blocked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var merged: Array = []
	for b: Array in blocked:
		if merged.is_empty() or float(b[0]) > float((merged[-1] as Array)[1]):
			merged.append([float(b[0]), float(b[1])])
		else:
			(merged[-1] as Array)[1] = maxf(float((merged[-1] as Array)[1]), float(b[1]))
	var y_lo := minf(oy, iy)
	var y_hi := maxf(oy, iy)
	var best := (oy + iy) * 0.5
	var best_cost := INF
	for gi: int in range(merged.size() + 1):
		var g0 := -1.0e9 if gi == 0 else float((merged[gi - 1] as Array)[1])
		var g1 := 1.0e9 if gi == merged.size() else float((merged[gi] as Array)[0])
		if g1 - g0 < 4.0:
			continue
		# Travel-optimal y in this gap: anywhere inside [y_lo, y_hi] costs the
		# minimum; outside, cost grows with distance from that interval.
		var seed := clampf(clampf((y_lo + y_hi) * 0.5, y_lo, y_hi), g0 + 2.0, g1 - 2.0)
		for dir_step: int in [0, 1, -1]:
			var y := seed
			var guard := 0
			while guard < 8 and not _f_run_clear(y, used, port_ys):
				if dir_step == 0:
					break   # the un-nudged seed only counts if already clear
				y = clampf(y + float(dir_step) * _F_CORRIDOR_SEP, g0 + 2.0, g1 - 2.0)
				guard += 1
				if y <= g0 + 2.0 or y >= g1 - 2.0:
					break
			if not _f_run_clear(y, used, port_ys):
				continue
			var cost := absf(oy - y) + absf(iy - y)
			if cost < best_cost:
				best_cost = cost
				best = y
	return best


func _f_run_clear(y: float, used: Array, port_ys: Array) -> bool:
	for u in used:
		if absf(float(u) - y) < _F_CORRIDOR_SEP:
			return false
	for p in port_ys:
		if absf(float(p) - y) < _F_PORT_AVOID:
			return false
	return true


## Lane ordering now lives in `lane_order.gd` so the empire view can use the same solver —
## both charts route orthogonal edges through vertical channels and the problem is identical.
func _f_lane_order(reqs: Array) -> Array:
	return LaneOrder.solve(reqs)


## Nearest tier column for a good's web position (columns are non-uniform; see
## GoodsFlowGraph.col_x).
func _col_of(id: String) -> int:
	var x := (((_by_id.get(id, {}) as Dictionary).get("pos", Vector2.ZERO)) as Vector2).x
	var best := 0
	var bestd := INF
	for c in range(_tier_count):
		var d := absf(GoodsFlowGraph.col_x(c) - x)
		if d < bestd:
			bestd = d
			best = c
	return best


## Transitive closure of the selection's BASE-recipe inputs (its canonical supply
## cone). Walking every route's inputs instead exploded the cone through alternate
## and gated recipes — selecting iron ingots lit ammonia and waste water via the
## hydrogen-DRI route. The selected good's own alternate edges still light (they
## touch the selection directly); the cone beyond it is the base chain. Iterative
## BFS; the visited set doubles as the cycle guard.
func _collect_upstream(id: String) -> Dictionary:
	var cone: Dictionary = {}
	var queue: Array = [(id)]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for src in (_by_id.get(cur, {}) as Dictionary).get("base_inputs", []):
			if not cone.has(src):
				cone[src] = true
				queue.append(src)
	return cone


# --- drawing -----------------------------------------------------------------------

func _draw() -> void:
	if _nodes.is_empty():
		return
	# Everything below is drawn in WORLD coordinates under the camera transform;
	# glyphs, icons and line widths all scale with zoom.
	draw_set_transform(_view_offset, 0.0, Vector2(_view_zoom, _view_zoom))
	var font := get_theme_default_font()
	if _mode == _Mode.GRID:
		_draw_grid(font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Focus reorg: while focused (or animating in/out), members tween between web
	# and focus positions, everything else cross-fades, and edges swap between the
	# ghost web and the on-demand focus routing.
	var ft := _focus_t
	if _mode == _Mode.FOCUS or ft > 0.001:
		if ft < 0.6:
			# Web chrome (tier plates, lane labels) belongs to the resting view —
			# drop it early in the tween instead of leaving it full-strength.
			_draw_tier_headers(font)
			if not _legacy_presentation:
				_draw_lanes()
		if ft < 0.999:
			for e in _edges:
				_draw_edge(e, false, 1.0 - ft)
		for fe in _focus_edges:
			_draw_focus_edge(fe, ft)
		var fsel: Dictionary = {}
		for n in _nodes:
			var id := str(n["id"])
			if _fpos.has(id):
				if id == _selected_id:
					fsel = n
					continue
				_draw_card(n, font, false, 1.0, (n["pos"] as Vector2).lerp(_fpos[id], ft))
			elif ft < 0.999:
				_draw_card(n, font, false, 1.0 - ft)
		_tray_buttons.clear()
		if not fsel.is_empty():
			var spos := (fsel["pos"] as Vector2).lerp(_fpos[str(fsel["id"])], ft)
			_draw_card(fsel, font, false, 1.0, spos)
			if ft > 0.999:
				var copy: Dictionary = fsel.duplicate()
				copy["pos"] = spos
				_draw_card_tray(copy, font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_tier_headers(font)
	if not _legacy_presentation:
		_draw_lanes()
	var tracing := _selected_id != ""
	for e in _edges:
		_draw_edge(e, tracing)
	var selected: Dictionary = {}
	for n in _nodes:
		if str(n["id"]) == _selected_id:
			selected = n
			continue
		_draw_card(n, font, tracing)
	_tray_buttons.clear()
	if not selected.is_empty():
		# The selected card draws LAST (its action tray overlaps the row below).
		_draw_card(selected, font, tracing)
		_draw_card_tray(selected, font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Band headers (RAW / PROCESSED / INTERMEDIATE / FINISHED / APEX) as octagonal
## brushed-metal plates with embossed Bebas Neue titles — ONE plate per authored
## band, centred over its invisible sub-columns (owner 2026-07-19).
func _draw_tier_headers(_font: Font) -> void:
	var top := INF
	for n in _nodes:
		top = minf(top, (n["pos"] as Vector2).y - (n["half"] as Vector2).y)
	const FS := 76   # tier labels at 2x (owner 2026-07-21)
	for band in _bands:
		var label := str((band as Dictionary).get("label", ""))
		var first := float(int((band as Dictionary).get("first", 0)))
		var count := float(int((band as Dictionary).get("count", 1)))
		var cx := (GoodsFlowGraph.col_x(int(first)) + GoodsFlowGraph.col_x(int(first + count - 1.0))) * 0.5
		var text_w := _BEBAS.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, FS).x
		var plate := Rect2(Vector2(cx - text_w * 0.5 - 68.0, top - _HEADER_GAP - _PLATE_H),
			Vector2(text_w + 136.0, _PLATE_H))
		_draw_metal_plate(plate)
		var baseline := plate.get_center().y + FS * 0.34
		# Engraved text: light catch below-right, navy on top.
		draw_string(_BEBAS, Vector2(plate.position.x + 1.0, baseline + 1.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, FS, Color(1, 1, 1, 0.30))
		draw_string(_BEBAS, Vector2(plate.position.x, baseline), label,
			HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, FS, _PLATE_TEXT)


## Category swimlanes (owner 2026-07-21): each lane gets a left-gutter label in
## its category colour and a faint separator hairline in the gap below it, so
## the vertical axis reads as taxonomy without competing with the cards.
func _draw_lanes() -> void:
	if _lanes.is_empty():
		return
	var left := GoodsFlowGraph.col_x(0) - GoodsFlowGraph.CARD_W * 0.5
	var right := GoodsFlowGraph.col_x(_tier_count - 1) + GoodsFlowGraph.CARD_W * 0.5
	const LFS := 120   # sized to stay legible at the (tall chart's) fit zoom
	for i in range(_lanes.size()):
		var lane: Dictionary = _lanes[i]
		var top := float(lane.get("top", 0.0))
		var height := float(lane.get("height", 0.0))
		var tint: Color = lane.get("color", _MUTED)
		# Long lane names split on " & " into stacked right-aligned lines.
		var lines := str(lane.get("label", "")).split(" & ")
		var fs := LFS if lines.size() == 1 else 84
		var line_h := fs * 1.06
		var block_top := top + height * 0.5 - line_h * float(lines.size() - 1) * 0.5
		for li in range(lines.size()):
			var text := lines[li] if li == 0 else "& " + lines[li]
			var text_w := _BEBAS.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs).x
			draw_string(_BEBAS, Vector2(left - text_w - 72.0,
				block_top + line_h * float(li) + fs * 0.34),
				text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color(tint, 0.85))
		# Faint lane rule through the middle of the gap below (not after the last lane).
		if i < _lanes.size() - 1:
			var next_top := float((_lanes[i + 1] as Dictionary).get("top", 0.0))
			var gap_y := (top + height + next_top) * 0.5
			draw_line(Vector2(left - 40.0, gap_y), Vector2(right + 40.0, gap_y),
				Color(_CREAM, 0.10), 1.5)


## Octagon (rect with 45-degree cut corners) filled with a top-left-lit silver
## gradient, brushed with faint horizontal streaks, edges bevelled light/shadow.
func _draw_metal_plate(rect: Rect2) -> void:
	var c := 13.0
	var pts := PackedVector2Array([
		rect.position + Vector2(c, 0.0), Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c), Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y), Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x, rect.position.y + c),
	])
	draw_polygon(pts, _grad_colors(pts, _PLATE_LT, _PLATE_DK))
	# Brushed-metal streaks: faint horizontal hairlines across the plate.
	var streak_y := rect.position.y + 7.0
	var si := 0
	while streak_y < rect.end.y - 5.0:
		var inset := c * 0.7 if (streak_y - rect.position.y < c or rect.end.y - streak_y < c) else 4.0
		var tone := Color(1, 1, 1, 0.10) if si % 2 == 0 else Color(0, 0, 0, 0.08)
		draw_line(Vector2(rect.position.x + inset, streak_y), Vector2(rect.end.x - inset, streak_y), tone, 1.0)
		streak_y += 5.0
		si += 1
	# Bevel: edges facing top-left lit, bottom-right shadowed (port-hex treatment).
	var diag := rect.get_center().x + rect.get_center().y
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var mid := (a + b) * 0.5
		draw_line(a, b, Color(1, 1, 1, 0.40) if (mid.x + mid.y <= diag) else Color(0, 0, 0, 0.34), 2.0, true)


## Flow line stroked along the edge's precomputed orthogonal waypoints (world-space,
## axis-aligned and lane-separated by the builder), corners rounded with quarter-arc
## fillets, tinted by the trace state. Back-edges are NOT x-monotonic: cycle edges
## dive below the deepest row and run right-to-left, so cull on the waypoint bbox.
func _draw_edge(e: Dictionary, tracing: bool, alpha_mul: float = 1.0) -> void:
	if alpha_mul <= 0.003:
		return
	var wp: PackedVector2Array = e["waypoints"]
	if wp.size() < 2:
		return
	var bb := Rect2(wp[0], Vector2.ZERO)
	for i in range(1, wp.size()):
		bb = bb.expand(wp[i])
	var visible_world := Rect2(_screen_to_world(Vector2.ZERO), get_rect().size / _view_zoom)
	if not visible_world.intersects(bb.grow(60.0)):
		return

	var route := clampi(int(e.get("route", 0)), 0, _ROUTE_COLORS.size() - 1)
	var route_c: Color = _ROUTE_COLORS[route]
	var from_id := str(e["from"])
	var to_id := str(e["to"])
	var lit := false
	if tracing:
		# The lit chain beyond the selection is the BASE chain (route-0 edges over the
		# base cone); at the selection itself every route lights, colour-coded.
		var in_cone: bool = route == 0 \
			and (_upstream.has(to_id) or to_id == _selected_id) and _upstream.has(from_id)
		var out_of_sel: bool = from_id == _selected_id and _feeds.has(to_id)
		lit = in_cone or to_id == _selected_id or out_of_sel
	var color := route_c
	var width := _EDGE_WIDTH
	if _legacy_presentation:
		# This is the pre-8d8a7be8 implementation: all resting arrows remain
		# visible, with base and alternate routes using separate alpha values.
		color = Color(route_c, _LEGACY_REST_ALPHA_BASE if route == 0 else _LEGACY_REST_ALPHA_ALT)
		if tracing:
			if lit:
				# Related edges keep their ROUTE colour, just lit and heavier.
				color = route_c
				width = _EDGE_WIDTH * 1.3
			else:
				color = _LEGACY_EDGE_DIM
		elif not tracing and _hover_id != "" and (from_id == _hover_id or to_id == _hover_id):
			color = Color(route_c, 0.9)
			width = _EDGE_WIDTH * 1.2
	else:
		if lit:
			# Related edges keep their ROUTE colour (the up/down reading comes from
			# which side of the selection they sit), just lit and heavier.
			width = _EDGE_WIDTH * 1.3
		elif not tracing and _hover_id != "" and (from_id == _hover_id or to_id == _hover_id):
			color = Color(route_c, 0.9)
			width = _EDGE_WIDTH * 1.2
		else:
			# Resting web, or unrelated to the active trace: ghost or nothing.
			if _REST_GHOST_ALPHA <= 0.001:
				return
			color = Color(route_c, _REST_GHOST_ALPHA if route == 0 else _REST_GHOST_ALPHA * 0.8)
	color.a *= alpha_mul

	var pts := _fillet_polyline(wp)
	if bool(e.get("route_gated", false)):
		# Research-gated route: dashed — "this way of making it exists, but is locked".
		_draw_dashed_polyline(pts, color, width)
	else:
		draw_polyline(pts, color, width, true)
	# Arrowhead at the target's left edge; the final waypoint segment is always
	# horizontal into the card, so the head points along +x.
	var end := wp[wp.size() - 1]
	var tip_dir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var n := Vector2(-tip_dir.y, tip_dir.x)
	var ah := 9.0
	draw_colored_polygon(PackedVector2Array([
		end, end - tip_dir * ah + n * ah * 0.6, end - tip_dir * ah - n * ah * 0.6]), color)


## Draw a polyline as dashes (10 on / 7 off world units), continuous across corners
## (the empire view's sell-edge treatment, scaled for the thinner web strokes).
func _draw_dashed_polyline(pts: PackedVector2Array, color: Color, width: float) -> void:
	const DASH := 10.0
	const GAP := 7.0
	var carry := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.001:
			continue
		var dir := (b - a) / seg_len
		var t := 0.0
		while t < seg_len:
			var cycle_pos := fmod(carry + t, DASH + GAP)
			if cycle_pos < DASH:
				var run := minf(DASH - cycle_pos, seg_len - t)
				draw_line(a + dir * t, a + dir * (t + run), color, width, true)
				t += run
			else:
				t += minf((DASH + GAP) - cycle_pos, seg_len - t)
		carry = fmod(carry + seg_len, DASH + GAP)


## Axis-aligned waypoint run with every interior 90-degree corner replaced by a
## quarter-arc fillet (same corner-arc sampling as _rounded_rect_points). The arc is
## tangent to both segments at radius r from the corner, r capped so tangent points
## never pass a segment's midpoint (adjacent fillets can share a segment).
func _fillet_polyline(wp: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(wp[0])
	for i in range(1, wp.size() - 1):
		var p := wp[i]
		var d_in := (p - wp[i - 1]).normalized()
		var d_out := (wp[i + 1] - p).normalized()
		var r := minf(_FILLET_R,
			0.5 * minf((p - wp[i - 1]).length(), (wp[i + 1] - p).length()))
		if r <= 0.01:
			out.append(p)
			continue
		# Tangent points P - d_in*r and P + d_out*r; arc centre sits perpendicular
		# to both, one radius inside the corner.
		var centre := p - d_in * r + d_out * r
		var a0 := (-d_out).angle()
		var a1 := d_in.angle()
		for s in range(_FILLET_STEPS + 1):
			var ang := lerp_angle(a0, a1, float(s) / float(_FILLET_STEPS))
			out.append(centre + Vector2(cos(ang), sin(ang)) * r)
	out.append(wp[wp.size() - 1])
	return out


## Straight elbow route for one focus edge (few edges, generous spacing — no lane
## machinery needed): out of the source's right edge, elbow between the columns
## (fanned per channel so parallels never overdraw), into the target's left edge.
func _draw_focus_edge(fe: Dictionary, alpha_mul: float) -> void:
	if alpha_mul <= 0.003:
		return
	var wp: PackedVector2Array = fe.get("wp", PackedVector2Array())
	if wp.size() < 2:
		return
	var route := clampi(int(fe.get("route", 0)), 0, _ROUTE_COLORS.size() - 1)
	var color := Color(_ROUTE_COLORS[route], alpha_mul)
	var pts := _fillet_polyline(wp)
	if bool(fe.get("gated", false)):
		_draw_dashed_polyline(pts, color, _EDGE_WIDTH * 1.3)
	else:
		draw_polyline(pts, color, _EDGE_WIDTH * 1.3, true)
	var tip := wp[wp.size() - 1]
	var tip_dir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var nrm := Vector2(-tip_dir.y, tip_dir.x)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - tip_dir * 9.0 + nrm * 5.4, tip - tip_dir * 9.0 - nrm * 5.4]), color)


func _draw_card(node: Dictionary, font: Font, tracing: bool, alpha_mul: float = 1.0,
		pos_override: Vector2 = Vector2.INF) -> void:
	if alpha_mul <= 0.01:
		return
	var pos: Vector2 = node["pos"] if pos_override == Vector2.INF else pos_override
	var half: Vector2 = node["half"]
	var rect := Rect2(pos - half, half * 2.0)
	# Cull cards outside the viewport (world-space test against the visible window).
	var visible_world := Rect2(_screen_to_world(Vector2.ZERO), get_rect().size / _view_zoom).grow(120.0)
	if not visible_world.intersects(rect):
		return

	var id := str(node["id"])
	var accent: Color = GoodsFlowGraph.accent_for(node)
	var gated: bool = node.get("gated", false)
	var related := not tracing \
		or id == _selected_id or _upstream.has(id) or _feeds.has(id)
	var alpha := (1.0 if related else 0.38) * alpha_mul
	# Research-gated goods rest dimmed, but a gated good that is PART of the active
	# trace stays fully lit — the lock tag (below) carries the "gated" signal instead,
	# so transparency never has two meanings at once.
	if gated and not (tracing and related):
		alpha *= 0.6

	var outline := _rounded_rect_points(rect, _CORNER_R)
	var bg := _CARD_BG_GATED if gated else _CARD_BG
	draw_colored_polygon(outline, Color(bg, bg.a * alpha))
	var rim_c := _GOLD if id == _selected_id else (Color(accent, accent.a * alpha))
	var rim_w := 3.0 if (id == _selected_id or id == _hover_id) else 1.8
	var rim := PackedVector2Array(outline)
	rim.append(outline[0])
	draw_polyline(rim, Color(rim_c, rim_c.a * alpha), rim_w, true)
	# Category accent stripe down the left edge.
	draw_rect(Rect2(rect.position + Vector2(2.0, 4.0), Vector2(5.0, rect.size.y - 8.0)),
		Color(accent, accent.a * alpha))

	# Good icon on a cream chip — 100x100 world units, so it reads 100 px at max
	# zoom-in (_ZOOM_MAX 1.0). Medium art: these chips are far above thumbnail size.
	var pad := 6.0
	var isz := rect.size.y - pad * 2.0
	var chip := Rect2(rect.position + Vector2(13.0, pad), Vector2(isz, isz))
	var icon: Texture2D = GoodIcons.texture_for(str(node.get("good_id", "")), id)
	draw_colored_polygon(_rounded_rect_points(chip, 8.0), Color(_CREAM, alpha))
	if icon != null:
		var tex_size := icon.get_size()
		var fit := minf((chip.size.x - 8.0) / tex_size.x, (chip.size.y - 8.0) / tex_size.y)
		var draw_size := tex_size * fit
		draw_texture_rect(icon, Rect2(chip.get_center() - draw_size * 0.5, draw_size),
			false, Color(1, 1, 1, alpha))

	# Name, vertically centred beside the chip; alt-recipe pill on the right when the
	# good has other routes (the phase-2 zoom targets).
	# Right-hand column: the lock (research-gated) sits at the card's right edge,
	# vertically centred; the alt-recipe pill sits just left of it.
	var alt_count: int = (node.get("alt_recipe_ids", []) as Array).size()
	var right_x := rect.end.x - 14.0
	if gated:
		_draw_lock_tag(Vector2(rect.end.x - 26.0, rect.get_center().y - 2.0), alpha)
		right_x = rect.end.x - 48.0
	var pill_w := 34.0
	if alt_count > 0:
		var pill := Rect2(Vector2(right_x - pill_w, rect.get_center().y - 13.0), Vector2(pill_w, 26.0))
		draw_colored_polygon(_rounded_rect_points(pill, 12.0), Color(_PILL_NAVY, alpha))
		var pr := _rounded_rect_points(pill, 12.0)
		pr.append(pr[0])
		draw_polyline(pr, Color(_CREAM, 0.8 * alpha), 1.4, true)
		draw_string(font, Vector2(pill.position.x, pill.get_center().y + 5.0), "+%d" % alt_count,
			HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 14, Color(_CREAM, alpha))
		right_x = pill.position.x
	var text_x := chip.end.x + 14.0
	var text_w := right_x - 10.0 - text_x
	var fs := 20 if str(node["display"]).length() <= 24 else 17
	draw_string(font, Vector2(text_x, rect.get_center().y + fs * 0.36), str(node["display"]),
		HORIZONTAL_ALIGNMENT_LEFT, text_w, fs, Color(_TEXT, alpha))


## Small padlock tag: "this good's every producer is research-gated at game start".
func _draw_lock_tag(at: Vector2, alpha: float) -> void:
	var gold := Color(_GOLD, alpha)
	# Shackle: upper half-circle arc.
	draw_arc(at + Vector2(0.0, -2.0), 6.0, PI, TAU, 10, gold, 2.0, true)
	# Body: filled rounded rect below the shackle.
	var body := Rect2(at + Vector2(-8.0, -2.0), Vector2(16.0, 12.0))
	draw_colored_polygon(_rounded_rect_points(body, 3.0), gold)
	draw_circle(body.get_center() + Vector2(0.0, 1.0), 2.0, Color(_PILL_NAVY, alpha))


## Per-vertex colours for a top-left (light) -> bottom-right (dark) gradient
## (the research-panel metal-lighting math, as in empire_graph_world.gd).
func _grad_colors(pts: PackedVector2Array, light: Color, dark: Color) -> PackedColorArray:
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	var denom := maxf(bounds.size.x + bounds.size.y, 1.0)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf(((p.x - bounds.position.x) + (p.y - bounds.position.y)) / denom, 0.0, 1.0)
		cols.append(light.lerp(dark, t))
	return cols


## Rounded-rect outline as a point loop (research-panel style corner arcs).
func _rounded_rect_points(rect: Rect2, radius: float, steps: int = 4) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var out := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(r, r), PI, PI * 1.5],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5, PI * 2.0],
		[rect.end - Vector2(r, r), 0.0, PI * 0.5],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5, PI],
	]
	for c in corners:
		var center: Vector2 = c[0]
		for s in range(steps + 1):
			var ang: float = lerpf(c[1], c[2], float(s) / float(steps))
			out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


# --- expanded-card action tray ------------------------------------------------------

## The selected card's dropdown: supported transport infrastructure on the first row,
## then the two action pills side by side. Safe fluids show ordinary Pipework rather
## than also repeating Reinforced Pipework, keeping the row to the intended maximum of
## road + rail + one pipe type. Power is the exception and shows only Cables.
func _draw_card_tray(node: Dictionary, font: Font) -> void:
	var pos: Vector2 = node["pos"]
	var half: Vector2 = node["half"]
	var alt_count: int = (node.get("alt_recipe_ids", []) as Array).size()
	var entries: Array = []
	if alt_count > 0:
		entries.append({"label": "See alternate recipes", "action": "alternates"})
	entries.append({"label": "Encyclopedia entry", "action": "encyclopedia"})

	# The tray must stay CLICKABLE at any zoom: below ~0.77 zoom the world-unit
	# button height is scaled up so it never renders under ~34 px on screen. The
	# same scaled rects are stored for hit-testing, and any zoom change redraws,
	# so draw and hit-test can never disagree.
	var s := clampf(34.0 / (44.0 * _view_zoom), 1.0, 3.0)
	var btn_h := 44.0 * s
	var m := 10.0 * s
	var gap := 8.0 * s
	var transport_keys := focused_transport_infrastructure_keys(
		str(node.get("good_id", "")), str(node.get("good_type", "")))
	# Infrastructure icons remain approximately 40 screen pixels while zooming, up
	# to the same 3x safety cap as the rest of the tray.
	var icon_s := clampf(1.0 / maxf(_view_zoom, 0.001), 1.0, 3.0)
	var icon_size := 40.0 * icon_s
	var icon_gap := 6.0 * icon_s
	var transport_h := icon_size + 12.0 * s
	# The old card-width tray forced the actions into a vertical stack. A wider
	# surface gives the three-icon row air and keeps both actions on one line.
	var icon_run_w := float(transport_keys.size()) * icon_size \
		+ float(maxi(0, transport_keys.size() - 1)) * icon_gap
	var tray_w := maxf(520.0 * s, icon_run_w + m * 2.0)
	var tray := Rect2(pos.x - tray_w * 0.5, pos.y + half.y + 8.0,
		tray_w, m * 2.0 + transport_h + gap + btn_h)
	draw_colored_polygon(_rounded_rect_points(tray, 10.0 * s), Color(_CARD_BG.r, _CARD_BG.g, _CARD_BG.b, 0.97))
	var rim := _rounded_rect_points(tray, 10.0 * s)
	rim.append(rim[0])
	draw_polyline(rim, _GOLD, 1.8 * s, true)

	# Transport row — icons only, matching the infrastructure art already used by
	# the build/map panels. It is informative rather than clickable.
	var icon_x := tray.get_center().x - icon_run_w * 0.5
	var icon_y := tray.position.y + m + (transport_h - icon_size) * 0.5
	for key_value in transport_keys:
		var key := str(key_value)
		var icon_rect := Rect2(Vector2(icon_x, icon_y), Vector2(icon_size, icon_size))
		var building: Dictionary = Catalog.get_building_by_internal_name(key)
		var texture := InfraIcons.texture_for(str(building.get("id", "")), key)
		if texture != null:
			draw_texture_rect(texture, icon_rect, false)
		else:
			draw_colored_polygon(_rounded_rect_points(icon_rect, 6.0 * s), Color(_PILL_NAVY, 0.96))
			draw_string(font, Vector2(icon_rect.position.x, icon_rect.get_center().y + 6.0 * s),
				key.left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, icon_rect.size.x,
				int(round(17.0 * s)), _CREAM)
		icon_x += icon_size + icon_gap

	var action_y := tray.position.y + m + transport_h + gap
	var inner_w := tray.size.x - m * 2.0
	var action_w := (inner_w - gap * float(maxi(0, entries.size() - 1))) / float(maxi(1, entries.size()))
	for i in range(entries.size()):
		var btn := Rect2(Vector2(tray.position.x + m + float(i) * (action_w + gap), action_y),
			Vector2(action_w, btn_h))
		var hovered := _hover_tray == i
		var bg := Color("#15304a") if hovered else _PILL_NAVY
		draw_colored_polygon(_rounded_rect_points(btn, 8.0 * s), bg)
		var br := _rounded_rect_points(btn, 8.0 * s)
		br.append(br[0])
		draw_polyline(br, Color(_CREAM, 1.0 if hovered else 0.7), 1.4 * s, true)
		draw_string(font, Vector2(btn.position.x, btn.get_center().y + 6.0 * s),
			str((entries[i] as Dictionary)["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, int(round(17.0 * s)),
			Color("#f3f8fd") if hovered else _CREAM)
		_tray_buttons.append({"rect": btn, "action": str((entries[i] as Dictionary)["action"])})


## Canonical display keys for the selected good's transport row. Routing uses
## singular `rail`; infrastructure art/buildings use plural `rails`.
static func focused_transport_infrastructure_keys(good_id: String, good_type: String = "") -> Array[String]:
	if good_type == "power" or str(Catalog.get_good(good_id).get("good_type", "")) == "power":
		return ["cables"]
	var supported: Array = Catalog.route_infra_for_good(good_id).get("modes", [])
	var keys: Array[String] = []
	if supported.has("roads"):
		keys.append("roads")
	if supported.has("rail"):
		keys.append("rails")
	if supported.has("pipes"):
		keys.append("pipes")
	elif supported.has("reinf_pipes"):
		keys.append("reinf_pipes")
	return keys


# --- alternate-recipes minigraph grid -----------------------------------------------

const _MINI_W := 300.0        # input mini-card size
const _MINI_H := 84.0
const _MINI_GAP := 14.0
const _ISL_ARROW_W := 190.0   # inputs -> output arrow band (carries the power draw)
const _ISL_HEAD_H := 64.0     # island header (recipe name + gate caption)
const _ISL_GAP_X := 280.0
const _ISL_GAP_Y := 170.0
const _GRID_MAX_ISLANDS := 5
const _OUT_EXTRA_H := 30.0    # output card is taller: it carries the building too
const _OUT_W := 533.0         # (CARD_W + 30) * 1.3 — room for both icons + the name
const _BuildingIcon := preload("res://scripts/building_icon.gd")

## Enter the per-recipe minigraph grid for a good: one island per producing recipe
## (defining first, then alternates, ungated before gated), no separators, just space.
func _enter_grid(internal: String) -> void:
	if internal == "" or not _by_id.has(internal):
		return
	var routes: Array = GoodsFlowGraph.routes_for_good(internal)
	if routes.is_empty():
		return
	_saved_zoom = _view_zoom
	_saved_offset = _view_offset
	_mode = _Mode.GRID
	_back_btn.visible = true
	_search_box.visible = false
	_search_panel.visible = false
	_grid_hover = -1
	_tray_buttons.clear()
	_hover_tray = -1
	_hover_id = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_layout_grid(internal, routes)
	_reset_view()
	queue_redraw()


## Rebuild the dropdown for the current query: top 3 matching good names (no icons).
func _refresh_search(text: String) -> void:
	_search_hits = GoodsFlowGraph.search_goods(text, _nodes)
	var results := _search_panel.get_node("Results") as VBoxContainer
	for child in results.get_children():
		child.queue_free()
	if _search_hits.is_empty():
		_search_panel.visible = false
		return
	for i in range(mini(3, _search_hits.size())):
		var node: Dictionary = _search_hits[i]
		var btn := Button.new()
		btn.text = str(node.get("display", ""))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0.0, 38.0)
		var id := str(node.get("id", ""))
		btn.pressed.connect(func() -> void: _search_pick(id))
		results.add_child(btn)
	_search_panel.visible = true


## Enter: when exactly ONE good matches the query, select it as if clicked.
func _submit_search(_text: String) -> void:
	if _search_hits.size() == 1:
		_search_pick(str((_search_hits[0] as Dictionary).get("id", "")))


## Zoom to the picked good and select it (opens its trace + action tray).
func _search_pick(internal: String) -> void:
	if not _by_id.has(internal):
		return
	_search_panel.visible = false
	_search_box.release_focus()
	var node: Dictionary = _by_id[internal]
	_view_zoom = maxf(_view_zoom, 0.75)
	_view_offset = get_rect().size * 0.5 - (node["pos"] as Vector2) * _view_zoom
	select_good(internal)
	queue_redraw()


func _exit_grid() -> void:
	if _mode != _Mode.GRID:
		return
	# A live selection means the grid was entered FROM the focus arrangement —
	# return there (its layout and _focus_t survived the grid detour).
	_mode = _Mode.FOCUS if _selected_id != "" and not _fpos.is_empty() else _Mode.WEB
	_back_btn.visible = false
	_search_box.visible = true
	_grid_islands.clear()
	_view_zoom = _saved_zoom
	_view_offset = _saved_offset
	_zoom_floor = _fit_zoom()
	queue_redraw()


## Pack up to 5 islands: a single column for <=3 recipes, two columns for 4-5.
## Row-major with UNIFORM row heights (the tallest island in the row), so the
## recipe titles of a row always sit on the same level.
func _layout_grid(internal: String, routes: Array) -> void:
	_grid_islands.clear()
	var node: Dictionary = _by_id.get(internal, {})
	var count := mini(routes.size(), _GRID_MAX_ISLANDS)
	var cols := 1 if count <= 3 else 2
	var island_w := _MINI_W + _ISL_ARROW_W + _OUT_W
	var out_h := GoodsFlowGraph.CARD_H + _OUT_EXTRA_H
	var heights := PackedFloat64Array()
	for i in range(count):
		var inputs_n: int = (((routes[i] as Dictionary)["recipe"] as Dictionary).get("inputs", []) as Array).size()
		heights.append(_ISL_HEAD_H + maxf(out_h,
			maxf(1.0, float(inputs_n)) * (_MINI_H + _MINI_GAP) - _MINI_GAP))
	var row_y := 0.0
	_grid_bbox = Rect2()
	for i in range(count):
		var route: Dictionary = routes[i]
		var recipe: Dictionary = route["recipe"]
		var inputs: Array = recipe.get("inputs", [])
		var inputs_h := maxf(out_h,
			maxf(1.0, float(inputs.size())) * (_MINI_H + _MINI_GAP) - _MINI_GAP)
		var island_h := _ISL_HEAD_H + inputs_h
		var c := i % cols
		if c == 0 and i > 0:
			var prev_row_h := 0.0
			for j in range(maxi(0, i - cols), i):
				prev_row_h = maxf(prev_row_h, heights[j])
			row_y += prev_row_h + _ISL_GAP_Y
		var rect := Rect2(Vector2(c * (island_w + _ISL_GAP_X), row_y), Vector2(island_w, island_h))
		var body_y := rect.position.y + _ISL_HEAD_H
		var in_rects: Array = []
		for j in range(inputs.size()):
			var inp: Dictionary = inputs[j]
			in_rects.append({
				"rect": Rect2(Vector2(rect.position.x, body_y + j * (_MINI_H + _MINI_GAP)),
					Vector2(_MINI_W, _MINI_H)),
				"good_id": str(inp.get("good_id", "")),
				"internal": str(inp.get("internal_name", "")),
				"qty": int(inp.get("qty", 0)),
			})
		var out_rect := Rect2(
			Vector2(rect.position.x + _MINI_W + _ISL_ARROW_W,
				body_y + inputs_h * 0.5 - out_h * 0.5),
			Vector2(_OUT_W, out_h))
		var bld: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
		var bpad := 6.0
		var bisz := out_rect.size.y - bpad * 2.0
		_grid_islands.append({
			"recipe": recipe,
			"gated": bool(route["gated"]),
			"rect": rect,
			"inputs": in_rects,
			"out_rect": out_rect,
			"out_qty": Catalog.recipe_output_qty(recipe, str(node.get("good_id", ""))),
			"internal": internal,
			"building_name": str(bld.get("display_name", "")),
			"bicon_rect": Rect2(Vector2(out_rect.end.x - 12.0 - bisz, out_rect.position.y + bpad),
				Vector2(bisz, bisz)),
		})
		_grid_bbox = rect if i == 0 else _grid_bbox.merge(rect)


func _draw_grid(font: Font) -> void:
	var node: Dictionary = _by_id.get(str((_grid_islands[0] as Dictionary).get("internal", "")), {}) \
		if not _grid_islands.is_empty() else {}
	for isl in _grid_islands:
		var island: Dictionary = isl
		var rect: Rect2 = island["rect"]
		var recipe: Dictionary = island["recipe"]
		var gated: bool = island["gated"]
		# Header: recipe name (Bebas, gold) + research gate caption when locked.
		var name := str(recipe.get("display_name", ""))
		draw_string(_BEBAS, rect.position + Vector2(2.0, 34.0), name,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 30, _GOLD)
		if gated:
			var name_w := _BEBAS.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			_draw_lock_tag(rect.position + Vector2(name_w + 26.0, 24.0), 1.0)
			# tech_unlock_req stores a research_node_id — show the node's TITLE, or the
			# raw value when it has no node (bare cheat tokens like "hydro").
			var gate_raw := str(recipe.get("tech_unlock_req", ""))
			var gate_name := MatchState.research_title_for_node_id(gate_raw)
			draw_string(font, rect.position + Vector2(2.0, 54.0),
				"requires research: %s" % (gate_name if gate_name != "" else gate_raw),
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 14, Color("#f3f8fd"))
		# Inputs (or a note when the recipe takes none — wind, solar, hydro).
		var inputs: Array = island["inputs"]
		if inputs.is_empty():
			draw_string(font, Vector2(rect.position.x, rect.position.y + _ISL_HEAD_H + _MINI_H * 0.6),
				"no inputs", HORIZONTAL_ALIGNMENT_LEFT, _MINI_W, 16, _MUTED)
		for inp in inputs:
			var entry: Dictionary = inp
			_draw_grid_good(entry["rect"] as Rect2, str(entry["good_id"]), str(entry["internal"]),
				Catalog.get_display_name(str(entry["good_id"])), int(entry["qty"]), font, false)
		# Arrow: a thick body that CARRIES the power draw (bolt + MW, 5-unit padding
		# above and below the content — the recipe-diagram treatment), pointing into
		# the output card. Fuel-less recipes (wind, solar) keep a slim arrow.
		var out_rect: Rect2 = island["out_rect"]
		var a := Vector2(rect.position.x + _MINI_W + 12.0, out_rect.get_center().y)
		var b := Vector2(out_rect.position.x - 10.0, out_rect.get_center().y)
		var energy := int(recipe.get("energy_req", 0))
		if energy > 0:
			var label := "%d MW" % energy
			const LFS := 14
			const BOLT_S := 22.0
			var content_h := maxf(BOLT_S, float(LFS) + 4.0)
			var band_h := content_h + 10.0            # 5 padding top + bottom
			const HEAD := 30.0
			var band := Rect2(a.x, a.y - band_h * 0.5, (b.x - HEAD) - a.x, band_h)
			draw_colored_polygon(_rounded_rect_points(band, 6.0), _PILL_NAVY)
			var br := _rounded_rect_points(band, 6.0)
			br.append(br[0])
			draw_polyline(br, Color(_GOLD, 0.85), 1.6, true)
			draw_colored_polygon(PackedVector2Array([
				b, Vector2(b.x - HEAD, a.y - band_h * 0.8),
				Vector2(b.x - HEAD, a.y + band_h * 0.8)]), Color(_GOLD, 0.9))
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LFS).x
			var cx := band.get_center().x - (BOLT_S + 6.0 + lw) * 0.5
			var bolt: Texture2D = GoodIcons.texture_for("g_010", "power")
			if bolt != null:
				draw_texture_rect(bolt, Rect2(Vector2(cx, a.y - BOLT_S * 0.5), Vector2(BOLT_S, BOLT_S)), false)
			draw_string(font, Vector2(cx + BOLT_S + 6.0, a.y + LFS * 0.36), label,
				HORIZONTAL_ALIGNMENT_LEFT, lw + 8.0, LFS, _CREAM)
		else:
			draw_line(a, b + Vector2(-12.0, 0.0), Color(_GOLD, 0.85), 3.0, true)
			draw_colored_polygon(PackedVector2Array([
				b, b + Vector2(-12.0, -7.0), b + Vector2(-12.0, 7.0)]), Color(_GOLD, 0.85))
		# The good itself: taller, wider card carrying the output qty and the
		# recipe's building icon (its NAME shows on hover only).
		var bld: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
		_draw_grid_good(out_rect, str(node.get("good_id", "")), str(island["internal"]),
			str(node.get("display", "")), int(island["out_qty"]), font, true,
			str(recipe.get("building_id", "")), str(bld.get("internal_name", "")))
	# Hovered building icon: the building's name in a floating navy pill.
	if _grid_hover >= 0 and _grid_hover < _grid_islands.size():
		var isl: Dictionary = _grid_islands[_grid_hover]
		var brect: Rect2 = isl["bicon_rect"]
		var bname := str(isl["building_name"])
		const TFS := 15
		var tw := font.get_string_size(bname, HORIZONTAL_ALIGNMENT_LEFT, -1, TFS).x
		var tip := Rect2(Vector2(brect.get_center().x - tw * 0.5 - 12.0, brect.position.y - 40.0),
			Vector2(tw + 24.0, 32.0))
		draw_colored_polygon(_rounded_rect_points(tip, 8.0), _PILL_NAVY)
		var tr2 := _rounded_rect_points(tip, 8.0)
		tr2.append(tr2[0])
		draw_polyline(tr2, Color(_CREAM, 0.85), 1.4, true)
		draw_string(font, Vector2(tip.position.x + 12.0, tip.get_center().y + TFS * 0.36), bname,
			HORIZONTAL_ALIGNMENT_LEFT, tw + 6.0, TFS, _CREAM)


## A good card inside a grid island: cream chip icon with the qty pill overlapping
## the chip's bottom-right corner (the recipe-diagram / building-detail treatment),
## name beside it using the full remaining width. The big (output) variant also
## carries the recipe's BUILDING: its name under the good's, and its icon on the
## right edge mirroring the goods chip's offsets.
func _draw_grid_good(rect: Rect2, good_id: String, internal: String, display: String,
		qty: int, font: Font, big: bool, building_id := "", building_internal := "") -> void:
	var outline := _rounded_rect_points(rect, _CORNER_R)
	draw_colored_polygon(outline, _CARD_BG)
	var rim := PackedVector2Array(outline)
	rim.append(outline[0])
	draw_polyline(rim, Color(_CREAM, 0.75), 1.8, true)
	var pad := 6.0 if big else 8.0
	var isz := rect.size.y - pad * 2.0
	var chip := Rect2(rect.position + Vector2(12.0, pad), Vector2(isz, isz))
	draw_colored_polygon(_rounded_rect_points(chip, 8.0), _CREAM)
	var icon: Texture2D = GoodIcons.texture_for_size(good_id, internal, isz)
	if icon != null:
		var tex_size := icon.get_size()
		var fit := minf((chip.size.x - 8.0) / tex_size.x, (chip.size.y - 8.0) / tex_size.y)
		var draw_size := tex_size * fit
		draw_texture_rect(icon, Rect2(chip.get_center() - draw_size * 0.5, draw_size), false)
	if qty > 0:
		# Recipe-card style: navy pill with cream border riding the chip's
		# bottom-right corner (overlapping ~4 units past the chip edge).
		var text := "x%d" % qty
		var ph := 26.0
		var pw := maxf(ph, 14.0 + 9.0 * float(text.length()))
		var pill := Rect2(chip.end - Vector2(pw - 4.0, ph - 4.0), Vector2(pw, ph))
		draw_colored_polygon(_rounded_rect_points(pill, ph * 0.5), _PILL_NAVY)
		var pr := _rounded_rect_points(pill, ph * 0.5)
		pr.append(pr[0])
		draw_polyline(pr, _CREAM, 1.6, true)
		draw_string(font, Vector2(pill.position.x, pill.get_center().y + 5.0), text,
			HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 14, _CREAM)
	var fs := 20 if big else 16
	var text_right := rect.end.x - 26.0
	if big and building_id != "":
		# Building icon on the right edge: same square size and top/bottom/right
		# offsets as the goods chip has on the left (off-white line art, no chip).
		var bicon: Texture2D = _BuildingIcon.clean_texture(building_id, building_internal)
		var brect := Rect2(Vector2(rect.end.x - 12.0 - isz, pad), Vector2(isz, isz))
		brect.position.y = rect.position.y + pad
		if bicon != null:
			draw_texture_rect(bicon, brect, false, Color(1, 1, 1, 0.95))
		text_right = brect.position.x - 12.0
		# Good name (up to two wrapped lines, clipped before the building icon);
		# the building's name lives in the hover tooltip, not on the card.
		var name_w := text_right - chip.end.x - 14.0
		draw_multiline_string(font, Vector2(chip.end.x + 14.0, rect.get_center().y - fs * 0.5 + 8.0),
			display, HORIZONTAL_ALIGNMENT_LEFT, name_w, fs, 2, _TEXT)
	else:
		draw_string(font, Vector2(chip.end.x + 14.0, rect.get_center().y + fs * 0.36), display,
			HORIZONTAL_ALIGNMENT_LEFT, text_right - chip.end.x - 14.0, fs, _TEXT)
