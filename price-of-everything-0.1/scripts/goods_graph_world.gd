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

const GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")

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
const _EDGE_DIM := Color(0.995, 0.931, 0.763, 0.08)      # unrelated line while tracing
const _REST_ALPHA_BASE := 0.60
const _REST_ALPHA_ALT := 0.48

const _EDGE_WIDTH := 2.5                                  # world units (scales with zoom)
const _ZOOM_MIN := 0.18                                   # absolute fallback; the live floor is _zoom_floor
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

var _view_zoom: float = 1.0
var _view_offset: Vector2 = Vector2.ZERO
var _zoom_floor: float = _ZOOM_MIN   # fit-whole-graph zoom; you cannot zoom out past it
var _dragging := false
var _drag_travel := 0.0

var _hover_id := ""
var _selected_id := ""
var _upstream: Dictionary = {}     # internal -> true, transitive input cone of the selection
var _feeds: Dictionary = {}        # internal -> true, direct consumers of the selection

# --- alternate-recipes focus grid (owner UX 2026-07-19) ------------------------------
# WEB shows the base chain; selecting a good expands its card with two buttons
# ("See alternate recipes" -> GRID of per-recipe minigraph islands, "Encyclopedia
# entry" -> deep-link). GRID keeps the same pan/zoom camera and a big Back button.
enum _Mode { WEB, GRID }
var _mode := _Mode.WEB
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
	if _mode != _Mode.WEB or not _by_id.has(id):
		return
	_selected_id = id
	_upstream = _collect_upstream(id)
	_feeds.clear()
	for f in (_by_id.get(id, {}) as Dictionary).get("feeds", []):
		_feeds[f] = true
	good_selected.emit(id)
	queue_redraw()


func _clear_selection() -> void:
	if _selected_id == "":
		return
	_selected_id = ""
	_upstream.clear()
	_feeds.clear()
	_tray_buttons.clear()
	_hover_tray = -1
	queue_redraw()


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
	_draw_tier_headers(font)
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
func _draw_edge(e: Dictionary, tracing: bool) -> void:
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
	var color := Color(route_c, _REST_ALPHA_BASE if route == 0 else _REST_ALPHA_ALT)
	var width := _EDGE_WIDTH
	if tracing:
		var from_id := str(e["from"])
		var to_id := str(e["to"])
		# The lit chain beyond the selection is the BASE chain (route-0 edges over the
		# base cone); at the selection itself every route lights, colour-coded.
		var in_cone: bool = route == 0 \
			and (_upstream.has(to_id) or to_id == _selected_id) and _upstream.has(from_id)
		var out_of_sel: bool = from_id == _selected_id and _feeds.has(to_id)
		if in_cone or to_id == _selected_id or out_of_sel:
			# Related edges keep their ROUTE colour (the up/down reading comes from
			# which side of the selection they sit), just lit and heavier.
			color = route_c
			width = _EDGE_WIDTH * 1.3
		else:
			color = _EDGE_DIM
	elif _hover_id != "" and (str(e["from"]) == _hover_id or str(e["to"]) == _hover_id):
		color = Color(route_c, 0.9)
		width = _EDGE_WIDTH * 1.2

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


func _draw_card(node: Dictionary, font: Font, tracing: bool) -> void:
	var pos: Vector2 = node["pos"]
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
	var alpha := 1.0 if related else 0.38
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
	var icon: Texture2D = GoodIcons.texture_for(str(node.get("good_id", "")), id, false)
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

## The selected card's actions (owner UX 2026-07-19): "See alternate recipes" (when
## the good has any) opens the minigraph grid; "Encyclopedia entry" deep-links to the
## good's encyclopedia page. Drawn in world space attached under the card; hit-rects
## stored in _tray_buttons for _click_at / _update_hover.
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
	# Width grows (capped) with the same factor so the labels stay whole, centred
	# on the card.
	var tray_w := half.x * 2.0 * clampf(s, 1.0, 1.7)
	var tray := Rect2(pos.x - tray_w * 0.5, pos.y + half.y + 8.0,
		tray_w, m * 2.0 + entries.size() * btn_h + (entries.size() - 1) * gap)
	draw_colored_polygon(_rounded_rect_points(tray, 10.0 * s), Color(_CARD_BG.r, _CARD_BG.g, _CARD_BG.b, 0.97))
	var rim := _rounded_rect_points(tray, 10.0 * s)
	rim.append(rim[0])
	draw_polyline(rim, _GOLD, 1.8 * s, true)

	for i in range(entries.size()):
		var btn := Rect2(tray.position + Vector2(m, m + i * (btn_h + gap)),
			Vector2(tray.size.x - m * 2.0, btn_h))
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
	_mode = _Mode.WEB
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
			draw_string(font, rect.position + Vector2(2.0, 54.0),
				"requires research: %s" % str(recipe.get("required_research", "")),
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
	var icon: Texture2D = GoodIcons.texture_for(good_id, internal, not big)
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
