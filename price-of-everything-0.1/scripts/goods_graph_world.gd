extends Control
const GoodHover := preload("res://scripts/good_icon_hover.gd")
const EffectEmblem := preload("res://scripts/effect_emblem.gd")
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

signal research_requested(title: String)

signal good_selected(internal_name: String)   # focus / recipe-swap mode

const LaneOrder := preload("res://scripts/lane_order.gd")
const GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const InfraIcons := preload("res://scripts/infra_icons.gd")

const _GOLD := Color(0.995, 0.931, 0.763, 1.0)
const _CREAM := Color(0.995234, 0.930806, 0.763265)
const _TEXT := Color(0.88, 0.92, 0.97, 1.0)
const _MUTED := Color(0.384, 0.471, 0.561, 1.0)          # tier headers (#62788f)
const _CARD_BG := Color(0.055, 0.125, 0.204, 0.92)
const _CARD_BG_GATED := Color(0.045, 0.095, 0.15, 0.85)
const _PILL_NAVY := Color(0.0, 0.119856, 0.243095)
# Recipe-route palette: yellow = the base recipe's inputs, then
# blue/green/purple for up to three alternate routes; research-gated routes dash.
const _ROUTE_COLORS: Array[Color] = [
	Color("#f2c14e"),   # 0 · base
	Color("#6f9fd8"),   # 1 · first alternate
	Color("#7ec98a"),   # 2 · second alternate
	Color("#b48ad9"),   # 3 · third alternate
]
## Resting edges are NOT DRAWN. The web at rest is a table of goods, and 600-odd ghost
## lines behind it read as noise rather than as information nobody asked for yet. Select,
## click, hover or search a good and its chain lights up — which is the moment the lines
## are an answer to something. 0.0 takes the early-out in _draw_edge; the lit and hovered
## branches above it are untouched.
##
## This is also what allows the tighter columns in goods_flow_graph: a full web of risers
## is never drawn, so the column gap need not keep one readable.
const _REST_GHOST_ALPHA := 0.0
# Legacy always-on resting web (_legacy_presentation), kept for A/B comparison.
const _LEGACY_REST_ALPHA_BASE := 0.60
const _LEGACY_REST_ALPHA_ALT := 0.48
const _LEGACY_EDGE_DIM := Color(0.995, 0.931, 0.763, 0.08)

const _EDGE_WIDTH := 2.5                                  # world units (scales with zoom)
const _ZOOM_MIN := 0.07                                   # absolute fallback; the live floor is _zoom_floor (swimlane chart is tall)
const _LANE_GUTTER := 840.0                               # left room for swimlane labels (2-line names)
const _ZOOM_MAX := 1.5                                    # shared by focused and full views
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
const _PLATE_H := 124.0                                   # tier-header plate at 2x

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
## LIVE unlock state: a good whose every producer is research-gated in the
## catalog is UNLOCKED once any of those researches is done — its card drops the lock (an open
## padlock marks it), its edges draw solid. Recomputed on every open (set_graph).
var _unlocked: Dictionary = {}     # internal -> true
## Non-base recipes the player's estate is RUNNING for the selected good:
## [{recipe, count}] — shown on focus as blue in-use edges from that recipe's inputs and a
## caption on the selected card.
var _in_use: Array = []

# --- alternate-recipes focus grid ----------------------------------------------------
# WEB shows the base chain; selecting a good expands its card with its supported
# transport infrastructure plus two actions (alternate recipes -> GRID of per-recipe
# minigraph islands, Encyclopedia -> deep-link). GRID keeps the same pan/zoom camera.
enum _Mode { WEB, GRID, FOCUS }
var _mode := _Mode.WEB

# --- focus reorg --------------------------------------------------------------------
# Clicking a good REORGANISES the view around it: the selection + its upstream cone
# + direct feeds tween from their web positions into a compact relative-depth
# arrangement; everything else fades out in place. Click empty space to tween back.
# Focus-view routing: no run may cross a card, passing runs
# keep >= _F_CLEAR from cards, and no two edges share a collinear run — ports
# fan along card edges, verticals take per-channel lanes, column-skipping edges
# cross through card-free corridors.
const _FCOL_W := 640.0            # CARD_W 300 + a 340 channel
const _FROW_H := 386.0            # CARD_H 350 + air
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
var _grid_key_hover := -1          # island whose See Research key is hovered
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
	_back_btn = preload("res://scripts/ds2/cream_key.gd").make("BackToGoodsGraph", "Back to Goods Graph", "", 280.0)
	# Top-LEFT: the top-centre slot belongs to the briefing notch. This control's
	# rect starts under HUDContent (screen y ~36) while the top bar is ~78 px tall,
	# so clear the remaining ~42 px of bar plus 20 px of air.
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
	_refresh_unlocked()
	_in_use.clear()
	_hover_id = ""
	_selected_id = ""
	_upstream.clear()
	_feeds.clear()
	_mode = _Mode.WEB
	# The focus reorg is an ANIMATED state (_focus_t) that is separate from _mode, so
	# resetting _mode alone is not enough: a stale _focus_t of 1 draws every card at its
	# focus position while _reset_view frames the camera on the WEB bbox, and a stale
	# _focus_target gives _process no delta to animate, so its _fpos cleanup never runs.
	_focus_t = 0.0
	_focus_target = 0.0
	_fpos.clear()
	_focus_edges.clear()
	_focus_bbox = Rect2()
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


## Which catalog-gated goods are unlocked NOW: any producing recipe whose research is done.
func _refresh_unlocked() -> void:
	_unlocked.clear()
	for n in _nodes:
		if not bool(n.get("gated", false)):
			continue
		var id := str(n["id"])
		for route in GoodsFlowGraph.routes_for_good(id):
			var recipe: Dictionary = (route as Dictionary).get("recipe", {})
			if _recipe_unlocked(recipe):
				_unlocked[id] = true
				break


## A recipe the player may build today: ungated, or its research is done.
func _recipe_unlocked(recipe: Dictionary) -> bool:
	var raw := str(recipe.get("tech_unlock_req", ""))
	if raw == "":
		return true
	var title := ResearchState.research_title_for_node_id(raw)
	return ResearchState.is_unlocked(title if title != "" else raw)


## Locked as the player sees it: gated in the catalog and not yet unlocked by research.
func _gated_now(id: String) -> bool:
	var n: Dictionary = _by_id.get(id, {})
	return bool(n.get("gated", false)) and not _unlocked.has(id)


## The estate's non-base recipes for a good: every player building whose recipe outputs
## it with a recipe other than the graph's defining one, grouped by recipe with a count.
func _in_use_alternates(id: String) -> Array:
	var node: Dictionary = _by_id.get(id, {})
	if node.is_empty():
		return []
	var base_rid := str(node.get("recipe_id", ""))
	var counts: Dictionary = {}
	var recipes: Dictionary = {}
	for b in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b) or bool(b.get("under_construction", false)):
			continue
		var rid := str(b.get("recipe_id", ""))
		if rid == "" or rid == base_rid:
			continue
		var recipe: Dictionary = Catalog.get_recipe(rid)
		var makes := false
		for o in recipe.get("outputs", []):
			if str((o as Dictionary).get("internal_name", "")) == id:
				makes = true
				break
		if not makes:
			continue
		counts[rid] = int(counts.get(rid, 0)) + 1
		recipes[rid] = recipe
	var out: Array = []
	var rids: Array = counts.keys()
	rids.sort()
	for rid2 in rids:
		out.append({"recipe": recipes[rid2], "count": int(counts[rid2])})
	return out


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
## this is also the zoom-OUT cap.
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


## How much closer than fit-the-whole-graph the view OPENS at. The floor stays the
## whole-graph fit — you can still pull all the way back — but landing on it made the
## cards unreadably small on arrival, so the chart opened as a texture rather than as a
## table you could read. Opening in and letting the player zoom out is the better default.
const _OPEN_ZOOM_MUL := 1.9

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
	# Open closer than the floor, centred on the same point, and never past the max. The alternate recipes grid
	# opens fitted: it is a handful of islands, and opening closer cut them off at the edges.
	var mul := 1.0 if _mode == _Mode.GRID else _OPEN_ZOOM_MUL
	_view_zoom = clampf(_zoom_floor * mul, _zoom_floor, _ZOOM_MAX)
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
	if _mode == _Mode.GRID:
		queue_redraw()   # the steam rises
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
		var link := _grid_research_at(w2)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if link != "" else Control.CURSOR_ARROW
		tooltip_text = "Open %s in Research" % link if link != "" else ""
		var gh := -1
		for i in range(_grid_islands.size()):
			if ((_grid_islands[i] as Dictionary)["bicon_rect"] as Rect2).has_point(w2):
				gh = i
				break
		var kh := -1
		for i in range(_grid_islands.size()):
			var key := _see_research_rect(_grid_islands[i] as Dictionary)
			if key.has_area() and key.has_point(w2):
				kh = i
				break
		if gh != _grid_hover or kh != _grid_key_hover:
			_grid_hover = gh
			_grid_key_hover = kh
			queue_redraw()
		return
	var w := _screen_to_world(screen_pos)
	var tray := _tray_button_at(w)
	var id := "" if tray >= 0 else _node_at(screen_pos)
	tooltip_text = _tier_tooltip(id, w)
	if id != _hover_id or tray != _hover_tray:
		_hover_id = id
		_hover_tray = tray
		var clickable := id != "" or tray >= 0
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
		queue_redraw()


## "Tier I (Raw)" when `world_pos` is over the tier plate of card `id`, else "".
func _tier_tooltip(id: String, world_pos: Vector2) -> String:
	if id == "" or not _by_id.has(id):
		return ""
	var node: Dictionary = _by_id[id]
	var pos: Vector2 = _fpos[id] if _mode == _Mode.FOCUS and _fpos.has(id) else node["pos"]
	var half: Vector2 = node["half"]
	if not _tier_plate_rect(Rect2(pos - half, half * 2.0)).has_point(world_pos):
		return ""
	var tier := _tier_of(node)
	return "Tier %s (%s)" % [_TIER_NUMERALS[tier], _TIER_NAMES[tier]]


func _tray_button_at(world_pos: Vector2) -> int:
	for i in range(_tray_buttons.size()):
		if ((_tray_buttons[i] as Dictionary)["rect"] as Rect2).has_point(world_pos):
			return i
	return -1


func _click_at(screen_pos: Vector2) -> void:
	if _mode == _Mode.GRID:
		var link := _grid_research_at(_screen_to_world(screen_pos))
		if link != "": research_requested.emit(link)
		return
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
	TelemetryState.track_interaction("goods_graph_good_selected", "goods_graph", id)
	_selected_id = id
	_upstream = _collect_upstream(id)
	_in_use = _in_use_alternates(id)
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
			"gated": bool(e.get("route_gated", false)) and _gated_now(et)})
	# The estate's in-use alternate(s): their inputs join the chart one column left of the
	# selection and feed it with blue IN-USE edges.
	var in_use_inputs: Dictionary = {}
	for iu in _in_use:
		for inp in ((iu as Dictionary)["recipe"] as Dictionary).get("inputs", []):
			var src := str((inp as Dictionary).get("internal_name", ""))
			if src == "" or src == sel or not _by_id.has(src) or in_use_inputs.has(src):
				continue
			in_use_inputs[src] = true
			_focus_edges.append({"from": src, "to": sel, "route": 1, "gated": false, "in_use": true})
	# 2 · Focus columns by TIER BAND: same-band members share
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
	for id in in_use_inputs:
		if not members.has(str(id)):
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


## Orthogonal routes for the focus edges: no run crosses a
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
	# TRAVEL (coal->steel goes over the top of iron ingots, not below — the
	# general rule, not a special case). Corridors also keep
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
	# 5 · Lane ordering per channel by MINIMUM PAIRWISE CROSSINGS (shortest-span
	# nesting only prevents riser braiding and is blind to the horizontal runs
	# that continue past a lane, so coal->ingots would cut through coal->steel's
	# corridor run). Each leg in a channel is a Z:
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
	GoodHover.begin_draw(self)
	if _nodes.is_empty():
		return
	# Everything below is drawn in WORLD coordinates under the camera transform (the grid's steam, behind it, in
	# screen space); glyphs, icons and line widths all scale with zoom.
	var font := get_theme_default_font()
	if _mode == _Mode.GRID:
		_draw_steam()
		draw_set_transform(_view_offset, 0.0, Vector2(_view_zoom, _view_zoom))
		_draw_grid(font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_set_transform(_view_offset, 0.0, Vector2(_view_zoom, _view_zoom))
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
## band, centred over its invisible sub-columns.
func _draw_tier_headers(_font: Font) -> void:
	var top := INF
	for n in _nodes:
		top = minf(top, (n["pos"] as Vector2).y - (n["half"] as Vector2).y)
	const FS := 76   # tier labels at 2x
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


## Category swimlanes: each lane gets a left-gutter label in
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
	if bool(e.get("route_gated", false)) and _gated_now(str(e["to"])):
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
	var pts := _fillet_polyline(wp)
	# A research-locked route is the same run as a faint ghost: there, but not laid.
	var a := alpha_mul * (0.38 if bool(fe.get("gated", false)) else 1.0)
	var good_id := str((_by_id.get(str(fe["from"]), {}) as Dictionary).get("good_id", str(fe["from"])))
	var carrier := _carrier_for(good_id)
	var w := _CARRIER_W * (1.25 if bool(fe.get("in_use", false)) else 1.0)
	match carrier:
		"pipe":
			_draw_pipe_run(pts, w, a)
		"cable":
			draw_polyline(pts, Color(_CABLE_INK, a), 3.0, true)
		_:
			_draw_conveyor_run(pts, w, a)
	# An alternate route keeps its colour as a thin core line, so the routes into the selection still read apart.
	if route > 0 and carrier != "cable":
		draw_polyline(pts, Color(_ROUTE_COLORS[route], 0.9 * a), 2.0, true)
	var tip := wp[wp.size() - 1]
	var tip_dir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var nrm := Vector2(-tip_dir.y, tip_dir.x)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - tip_dir * 12.0 + nrm * 8.0, tip - tip_dir * 12.0 - nrm * 8.0]), Color(_BRASS_DARK, a))


## The focused chain's runs in DS2: a good that needs pipework rides a brass pipe, a solid a brass-railed
## conveyor, power a cable. Which a good takes follows its transport class (Catalog.requires_pipeline).
const _CARRIER_W := 9.0
const _BRASS := Color("c9a24a")
const _BRASS_DARK := Color("6e5420")
const _BRASS_LIGHT := Color("f2dc95")
const _BELT := Color("2b2c30")
const _SLAT := Color("4a4c52")
const _CABLE_INK := Color("1b1d22")
const _SLAT_STEP := 11.0
const _FLANGE_STEP := 150.0


static func _carrier_for(good_id: String) -> String:
	if good_id == "power" or str(Catalog.get_good(good_id).get("good_type", "")) == "power":
		return "cable"
	return "pipe" if Catalog.requires_pipeline(good_id) else "conveyor"


## A brass pipe along `pts`: a dark edge, the brass body, a highlight along its upper left, and a flange at each
## end and every _FLANGE_STEP along it.
func _draw_pipe_run(pts: PackedVector2Array, w: float, a: float) -> void:
	draw_polyline(pts, Color(_BRASS_DARK, a), w + 3.0, true)
	draw_polyline(pts, Color(_BRASS, a), w, true)
	var lift := Vector2(-w * 0.2, -w * 0.2)
	var shine := PackedVector2Array()
	for pt in pts:
		shine.append(pt + lift)
	draw_polyline(shine, Color(_BRASS_LIGHT, 0.85 * a), maxf(1.5, w * 0.28), true)
	_along(pts, _FLANGE_STEP, true, func(at: Vector2, dir: Vector2) -> void:
		var n := Vector2(-dir.y, dir.x)
		var half := n * (w * 0.5 + 3.0)
		var d := dir * 2.5
		draw_colored_polygon(PackedVector2Array([at - half - d, at + half - d, at + half + d, at - half + d]), Color(_BRASS_DARK, a)))


## A conveyor along `pts`: brass rails either side of a dark belt, its slats across it.
func _draw_conveyor_run(pts: PackedVector2Array, w: float, a: float) -> void:
	draw_polyline(pts, Color(_BRASS_DARK, a), w + 5.0, true)
	draw_polyline(pts, Color(_BRASS, a), w + 3.0, true)
	draw_polyline(pts, Color(_BELT, a), w - 1.0, true)
	_along(pts, _SLAT_STEP, false, func(at: Vector2, dir: Vector2) -> void:
		var n := Vector2(-dir.y, dir.x) * (w * 0.5 - 1.0)
		draw_line(at - n, at + n, Color(_SLAT, a), 1.6, true))


## Calls `mark(point, direction)` every `step` along `pts` (and at both ends when `ends`).
func _along(pts: PackedVector2Array, step: float, ends: bool, mark: Callable) -> void:
	if pts.size() < 2:
		return
	if ends:
		mark.call(pts[0], (pts[1] - pts[0]).normalized())
		mark.call(pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized())
	var carry := step * 0.5
	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := p0.distance_to(p1)
		if seg <= 0.001:
			continue
		var dir := (p1 - p0) / seg
		var t := carry
		while t < seg:
			mark.call(p0 + dir * t, dir)
			t += step
		carry = t - seg


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
	var gated: bool = _gated_now(id)
	var unlocked_now: bool = bool(node.get("gated", false)) and not gated
	var related := not tracing \
		or id == _selected_id or _upstream.has(id) or _feeds.has(id)
	var alpha := (1.0 if related else 0.38) * alpha_mul
	# Research-gated goods rest dimmed, but a gated good that is PART of the active
	# trace stays fully lit — the lock tag (below) carries the "gated" signal instead,
	# so transparency never has two meanings at once.
	if gated and not (tracing and related):
		alpha *= 0.6

	# A glow behind the plate: gold round the selected card, cream round a hovered one (none in the recipes grid,
	# where every output card is the selected good).
	if _mode == _Mode.GRID:
		pass
	elif id == _selected_id:
		_draw_glow(rect, _GOLD, alpha)
	elif id == _hover_id:
		_draw_glow(rect, _CREAM, alpha * 0.8)
	var plate := _PLATE_DIM if gated else Color.WHITE
	_paint_plate(rect, Color(plate, alpha), false)
	# The good on an enamel tile across the top, a band of the category's colour under it.
	var side := rect.size.x - 2.0 * _TILE_SIDE_PAD
	var tile := Rect2(Vector2(rect.get_center().x - side * 0.5, rect.position.y + _TILE_TOP_PAD), Vector2(side, side))
	_draw_enamel_icon(tile, str(node.get("good_id", "")), id, alpha)
	# The +N pill and the lock in the tile's top right corner.
	var corner := Vector2(tile.end.x - 10.0, tile.position.y + 26.0)
	if gated or unlocked_now:
		_draw_lock_tag(corner + Vector2(-14.0, 0.0), alpha, 1.7, unlocked_now)
		corner.x -= 46.0
	var alt_count: int = (node.get("alt_recipe_ids", []) as Array).size()
	if alt_count > 0:
		var pill := Rect2(Vector2(corner.x - 52.0, corner.y - 18.0), Vector2(52.0, 36.0))
		draw_colored_polygon(_rounded_rect_points(pill, 18.0), Color(_PILL_NAVY, alpha))
		var pr := _rounded_rect_points(pill, 18.0)
		pr.append(pr[0])
		draw_polyline(pr, Color(_CREAM, 0.8 * alpha), 1.6, true)
		draw_string(font, Vector2(pill.position.x, pill.get_center().y + 7.0), "+%d" % alt_count,
			HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 20, Color(_CREAM, alpha))
	# The name engraved on the plate under the tile, up to two lines; on the selected card the recipe in
	# use runs under it.
	var name := str(node["display"])
	# The tier on a small silver plate at the left of the name row, the name engraved beside it.
	var plate_r := _tier_plate_rect(rect)
	_draw_tier_plate(plate_r, _tier_of(node), font, alpha)
	var row := _name_row(rect)
	var area := Rect2(Vector2(plate_r.end.x + 6.0, row.position.y), Vector2(row.end.x - plate_r.end.x - 6.0, row.size.y))
	# One line at 28; a name that needs two drops to 22 so both clear the band.
	var fs := 28 if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x <= area.size.x else 22
	var caption := ""
	if id == _selected_id and not _in_use.is_empty():
		var iu: Dictionary = _in_use[0]
		caption = "USING %s" % str((iu["recipe"] as Dictionary).get("display_name", "")).to_upper()
		if int(iu["count"]) > 1:
			caption += " x%d" % int(iu["count"])
	var name_h := font.get_multiline_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, 2, TextServer.BREAK_WORD_BOUND).y
	var cap_fs := 14
	var cap_h := (font.get_multiline_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, cap_fs, 1).y + 4.0) if caption != "" else 0.0
	var top := area.get_center().y - (name_h + cap_h) * 0.5
	var at := Vector2(area.position.x, top + font.get_ascent(fs))
	draw_multiline_string(font, at + Vector2(1.5, 1.5), name, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, 2, Color(0, 0, 0, 0.8 * alpha))
	draw_multiline_string(font, at, name, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, 2, Color(_TEXT, alpha))
	if caption != "":
		draw_string(font, Vector2(area.position.x, top + name_h + 4.0 + font.get_ascent(cap_fs)), caption,
			HORIZONTAL_ALIGNMENT_CENTER, area.size.x, cap_fs, Color(_ROUTE_COLORS[1], alpha))


## A good's card (CARD_W x CARD_H): a dark metal plate (dark_metal_plate.png, blackened gunmetal edge to edge, as
## the Victory panel's dials stand on) carrying the good on an enamel tile (recipe_enamel.png, Building Detail's
## vitreous enamel sign: cream enamel in a steel cut) with a gloss across it, and the name engraved under it.
## Both renders are 9-slices drawn at _PLATE_K times their panel size, so their edges keep the panel's proportions
## on a card this size.
const _DARK_PLATE: Texture2D = preload("res://assets/ui/bdp_v3/dark_metal_plate.png")
const _ENAMEL: Texture2D = preload("res://assets/ui/bdp_v3/recipe_enamel.png")
const _PLATE_K := 1.4
const _PLATE_CORNER := (10.0 + 44.0) * 2.0 / 1.875
const _PLATE_OUTSET := 10.0 / 1.875
const _ENAMEL_CORNER := 44.0 * 2.0 / 1.875
const _ENAMEL_MARGIN := 3.0 / 1.875
## A gated good's plate, a shade darker.
const _PLATE_DIM := Color(0.72, 0.72, 0.72)
const _TILE_SIDE_PAD := 28.0
## The tier plate: its size, its silver from top to foot, and the tiers' numerals and names (GoodsFlowGraph.TIER_BANDS).
const _TIER_PLATE := Vector2(56.0, 42.0)
const _SILVER_TOP := Color("e4e8ed")
const _SILVER_FOOT := Color("9aa3ad")
const _TIER_NUMERALS := ["I", "II", "III", "IV", "V"]
const _TIER_NAMES := ["Raw", "Processed", "Intermediate", "Finished", "Apex"]


## The good's tier, 0 (raw) to 4 (apex), from its goods_graph_tier band.
static func _tier_of(node: Dictionary) -> int:
	var band := str(Catalog.get_good(str(node.get("good_id", node.get("id", "")))).get("goods_graph_tier", ""))
	return maxi(0, GoodsFlowGraph.TIER_BANDS.find(band))


## The row under the enamel tile that holds the tier plate and the name, for a card at `rect`.
func _name_row(rect: Rect2) -> Rect2:
	var side := rect.size.x - 2.0 * _TILE_SIDE_PAD
	var tile_end := rect.position.y + _TILE_TOP_PAD + side
	return Rect2(Vector2(rect.position.x + _TILE_SIDE_PAD - 6.0, tile_end + 8.0),
		Vector2(side + 12.0, rect.end.y - tile_end - 16.0))


func _tier_plate_rect(rect: Rect2) -> Rect2:
	var row := _name_row(rect)
	return Rect2(Vector2(row.position.x, row.get_center().y - _TIER_PLATE.y * 0.5), _TIER_PLATE)


## A small silver plate, lit from the top, its edge in shadow, the tier's numeral on it in navy.
func _draw_tier_plate(r: Rect2, tier: int, font: Font, alpha: float) -> void:
	var pts := _rounded_rect_points(r, 4.0)
	draw_colored_polygon(_rounded_rect_points(Rect2(r.position + Vector2(1.5, 2.0), r.size), 4.0), Color(0, 0, 0, 0.5 * alpha))
	var cols := PackedColorArray()
	for pt in pts:
		var t := clampf((pt.y - r.position.y) / r.size.y, 0.0, 1.0)
		cols.append(Color(_SILVER_TOP.lerp(_SILVER_FOOT, t), alpha))
	draw_polygon(pts, cols)
	var edge := PackedVector2Array(pts)
	edge.append(pts[0])
	draw_polyline(edge, Color(0.25, 0.28, 0.33, alpha), 1.4, true)
	var numeral: String = _TIER_NUMERALS[clampi(tier, 0, 4)]
	draw_string(_BEBAS, Vector2(r.position.x, r.get_center().y + 13.0), numeral, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36,
		Color(DS.PALETTE.BG_PANEL, alpha))
const _TILE_TOP_PAD := 18.0


## The dark metal plate over `rect`; with `screws`, silver screws set over its own four (the render's are dark). The
## tray under the selected good has them; the cards do not.
const _SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
## The render's screws: their centres this many texels in from its corners, this many texels across.
const _PLATE_SCREW_AT := 34.0
const _PLATE_SCREW_SIDE := 30.0


func _paint_plate(rect: Rect2, tint: Color = Color.WHITE, screws: bool = true) -> void:
	var dest := rect.grow(_PLATE_OUTSET * _PLATE_K)
	_paint_scaled(_DARK_PLATE, dest, _PLATE_CORNER, _PLATE_K, tint)
	if not screws:
		return
	var inset := _PLATE_SCREW_AT * 0.5 * _PLATE_K
	var side := _PLATE_SCREW_SIDE * 0.5 * _PLATE_K
	for c: Vector2 in [dest.position + Vector2(inset, inset), Vector2(dest.end.x - inset, dest.position.y + inset),
			Vector2(dest.position.x + inset, dest.end.y - inset), dest.end - Vector2(inset, inset)]:
		draw_texture_rect(_SCREW, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false, Color(1, 1, 1, tint.a))


## A soft glow round `rect`: rings of `col` fading out as they widen.
func _draw_glow(rect: Rect2, col: Color, alpha: float) -> void:
	for i in _GLOW_RINGS:
		var t := float(i) / float(_GLOW_RINGS)
		var grow := 2.0 + float(i) * _GLOW_STEP
		var ring := _rounded_rect_points(rect.grow(grow), _CORNER_R + grow)
		ring.append(ring[0])
		draw_polyline(ring, Color(col, alpha * _GLOW_ALPHA * (1.0 - t) * (1.0 - t)), _GLOW_STEP * 1.6, true)


const _GLOW_RINGS := 16
const _GLOW_STEP := 2.0
const _GLOW_ALPHA := 0.2


## `tex` as a 9-slice over `dest` (world units), drawn at `k` times the panel's scale.
func _paint_scaled(tex: Texture2D, dest: Rect2, corner: float, k: float, tint: Color = Color.WHITE) -> void:
	# The edges and middle stretch a short sample from the render's centre rather than squeezing its whole length:
	# squeezing a wide render into a small rect minified it so hard the filtering smeared the rim across the
	# middle as grey bands.
	var ts := tex.get_size()
	var c := minf(corner, minf(ts.x, ts.y) * 0.5)
	var size := dest.size / k
	var d := minf(c / 2.0, minf(size.x, size.y) * 0.5)
	var mid := Vector2(minf(_SLICE_SAMPLE, ts.x - 2.0 * c), minf(_SLICE_SAMPLE, ts.y - 2.0 * c))
	var sx := [0.0, c, (ts.x - mid.x) * 0.5, (ts.x + mid.x) * 0.5, ts.x - c, ts.x]
	var sy := [0.0, c, (ts.y - mid.y) * 0.5, (ts.y + mid.y) * 0.5, ts.y - c, ts.y]
	var dx := [0.0, d, size.x - d, size.x]
	var dy := [0.0, d, size.y - d, size.y]
	draw_set_transform(_view_offset + dest.position * _view_zoom, 0.0, Vector2.ONE * _view_zoom * k)
	for i in 3:
		for j in 3:
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			var ux: float = [sx[0], sx[2], sx[4]][i]
			var uw: float = [sx[1] - sx[0], sx[3] - sx[2], sx[5] - sx[4]][i]
			var uy: float = [sy[0], sy[2], sy[4]][j]
			var uh: float = [sy[1] - sy[0], sy[3] - sy[2], sy[5] - sy[4]][j]
			draw_texture_rect_region(tex, dst, Rect2(ux, uy, uw, uh), tint)
	draw_set_transform(_view_offset, 0.0, Vector2(_view_zoom, _view_zoom))


## How many texels of a render's edge the 9-slice stretches along its middle.
const _SLICE_SAMPLE := 24.0


## The good on its enamel tile: the enamel sign as the tile, the icon on its cream field.
func _draw_enamel_icon(tile: Rect2, good_id: String, id: String, alpha: float) -> void:
	_paint_scaled(_ENAMEL, tile.grow(_ENAMEL_MARGIN * _PLATE_K), _ENAMEL_CORNER, _PLATE_K, Color(1, 1, 1, alpha))
	GoodHover.drawn(self, Rect2(tile.position * _view_zoom + _view_offset, tile.size * _view_zoom), good_id)
	var icon: Texture2D = GoodIcons.texture_for(good_id, id)
	if icon != null:
		var ts := icon.get_size()
		var fit := minf(tile.size.x * 0.78 / ts.x, tile.size.y * 0.78 / ts.y)
		draw_texture_rect(icon, Rect2(tile.get_center() - ts * fit * 0.5, ts * fit), false, Color(1, 1, 1, alpha))


## Small padlock tag: "this good's every producer is research-gated at game start". `open`
## draws the shackle swung aside in the OK green: gated in the catalog, unlocked by research.
func _draw_lock_tag(at: Vector2, alpha: float, k: float = 1.0, open: bool = false) -> void:
	var gold := Color(DS.PALETTE.OK if open else _GOLD, alpha)
	# Shackle: upper half-circle arc (shifted and lifted when open).
	var sh := at + (Vector2(6.0, -6.0) * k if open else Vector2(0.0, -2.0 * k))
	draw_arc(sh, 6.0 * k, PI, TAU, 10, gold, 2.0 * k, true)
	# Body: filled rounded rect below the shackle.
	var body := Rect2(at + Vector2(-8.0, -2.0) * k, Vector2(16.0, 12.0) * k)
	draw_colored_polygon(_rounded_rect_points(body, 3.0 * k), gold)
	draw_circle(body.get_center() + Vector2(0.0, 1.0) * k, 2.0 * k, Color(_PILL_NAVY, alpha))


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

## The selected card's tray, a DS2 plate under it: the dark metal plate the cards stand on, carrying the
## ways the good can travel along its top as a chain, best first (rail > road), then the actions
## as square cream keys holding only their icon, each named underneath. Safe fluids show ordinary Pipework rather
## than also repeating Reinforced Pipework; power shows only Cables.
##
## The tray must stay usable at any zoom: below ~0.77 zoom its world size is scaled up (s) so the keys never render
## under ~34 px on screen. The same scaled rects are stored for hit-testing, so draw and hit-test always agree.
func _draw_card_tray(node: Dictionary, font: Font) -> void:
	var pos: Vector2 = node["pos"]
	var half: Vector2 = node["half"]
	var alt_count: int = (node.get("alt_recipe_ids", []) as Array).size()
	var entries: Array = []
	if alt_count > 0:
		entries.append({"label": "Alternate recipes", "action": "alternates", "symbol": "merge"})
	entries.append({"label": "Encyclopedia", "action": "encyclopedia", "symbol": "encyclopedia"})
	var s := clampf(34.0 / (44.0 * _view_zoom), 1.0, 3.0)
	var m := 16.0 * s
	var gap := 10.0 * s
	var label_px := int(round(15.0 * s))
	var key_side := 56.0 * s
	var good_id := str(node.get("good_id", ""))
	var transport_keys := _transport_chain(good_id, focused_transport_infrastructure_keys(good_id, str(node.get("good_type", ""))))
	var icon_size := 40.0 * s
	var icon_gap := 30.0 * s
	var transport_w := float(transport_keys.size()) * icon_size + float(maxi(0, transport_keys.size() - 1)) * icon_gap
	var transport_h := icon_size
	# Each action is a column: its key, its name under it.
	var col_w: Array = []
	var actions_w := 0.0
	for e: Dictionary in entries:
		var w := maxf(key_side, font.get_string_size(str(e["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_px).x)
		col_w.append(w)
		actions_w += w
	actions_w += gap * 2.0 * float(maxi(0, entries.size() - 1))
	var actions_h := key_side + 6.0 * s + float(label_px)
	var tray_w := maxf(half.x * 2.0, maxf(transport_w, actions_w) + m * 2.0)
	var tray := Rect2(pos.x - tray_w * 0.5, pos.y + half.y + 10.0, tray_w, m * 2.0 + transport_h + gap * 1.6 + actions_h)
	_paint_plate(tray)

	# Transport: the ways the good can travel, best first, ">" between them.
	var icon_x := tray.get_center().x - transport_w * 0.5
	var icon_y := tray.position.y + m
	for n in transport_keys.size():
		var key: String = transport_keys[n]
		var icon_rect := Rect2(Vector2(icon_x, icon_y), Vector2(icon_size, icon_size))
		var building: Dictionary = Catalog.get_building_by_internal_name(key)
		var texture := InfraIcons.texture_for(str(building.get("id", "")), key)
		if texture != null:
			draw_texture_rect(texture, icon_rect, false)
		if n < transport_keys.size() - 1:
			var chev_px := int(round(26.0 * s))
			_engrave(font, Vector2(icon_rect.end.x, icon_rect.get_center().y + chev_px * 0.36), ">", chev_px, icon_gap)
		icon_x += icon_size + icon_gap

	# Actions: a square cream key holding only its icon, its name engraved under it.
	var x := tray.get_center().x - actions_w * 0.5
	var key_y := icon_y + transport_h + gap * 1.6
	for i in range(entries.size()):
		var w: float = col_w[i]
		var key_rect := Rect2(Vector2(x + (w - key_side) * 0.5, key_y), Vector2(key_side, key_side))
		var hovered := _hover_tray == i
		_draw_key(key_rect, hovered)
		var art := EffectEmblem.texture(str(entries[i]["symbol"]))
		if art != null:
			draw_texture_rect(art, key_rect.grow(-key_side * 0.24), false, _KEY_INK)
		var label := str(entries[i]["label"])
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_px).x
		_engrave(font, Vector2(x + (w - lw) * 0.5, key_rect.end.y + 4.0 * s + float(label_px) * 0.82), label, label_px)
		_tray_buttons.append({"rect": Rect2(Vector2(x, key_y), Vector2(w, actions_h)), "action": str(entries[i]["action"])})
		x += w + gap * 2.0


## The ways `good_id` can travel among `keys`, best first: a liquid by pipe, then rail, then road (overland
## a fluid costs 3x the pipe by rail, 6x by road); a solid by rail, then road (rail is half road's cost and
## goes further a turn); power by cables.
static func _transport_chain(good_id: String, keys: Array[String]) -> Array[String]:
	var order: Array = ["cables", "pipes", "reinf_pipes", "rails", "roads"] if Catalog.requires_pipeline(good_id) \
		else ["cables", "rails", "roads", "pipes", "reinf_pipes"]
	var out: Array[String] = []
	for k in order:
		if keys.has(k):
			out.append(k)
	return out


const _KEY_INK := Color("#0b2340")
## The cream keycap (latch_key.gd's render, tile_key.png, a horizontal 3-slice) drawn in `r`: its face at the
## render's own height, scaled to `r`'s height and stretched to its width.
const _LatchKey := preload("res://scripts/ds2/latch_key.gd")


func _draw_key(r: Rect2, hovered: bool) -> void:
	var face := (_LatchKey.HEIGHT - 2.0 * _LatchKey.KEY_INSET) / _LatchKey.CAPTURE_SCALE
	var k := r.size.y / face
	var tex: Texture2D = _LatchKey.PRESSED if hovered else _LatchKey.NORMAL
	var out := _LatchKey.KEY_INSET / _LatchKey.CAPTURE_SCALE
	var dest := Rect2(Vector2(-out, -out), Vector2(r.size.x / k + 2.0 * out, face + 2.0 * out))
	var cap_px := minf(_LatchKey.CAP / _LatchKey.CAPTURE_SCALE, dest.size.x * 0.5)
	var cap_tx := cap_px * _LatchKey.TEXELS_PER_PIXEL
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	draw_set_transform(_view_offset + r.position * _view_zoom, 0.0, Vector2.ONE * _view_zoom * k)
	draw_texture_rect_region(tex, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th))
	if dest.size.x > 2.0 * cap_px:
		draw_texture_rect_region(tex, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
			Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th))
	draw_texture_rect_region(tex, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th))
	draw_set_transform(_view_offset, 0.0, Vector2(_view_zoom, _view_zoom))


## Text engraved on a dark plate: off-white over a dark cut shadow; centred in `width` when one is given.
func _engrave(font: Font, at: Vector2, text: String, px: int, width: float = -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(font, at + Vector2(1.0, 1.0), text, align, width, px, Color(0, 0, 0, 0.85))
	draw_string(font, at, text, align, width, px, DS.PALETTE.TEXT)


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

## The alternate recipes grid in DS2: each recipe on a dark steel plate (an island), its name engraved at the top,
## and, when locked, the research it needs on a dot-matrix screen. Left of the recipe, the building's icon embossed
## in silver on the plate; then the recipe as Building Detail's diagram draws it, on the enamel sign: the inputs
## with their quantities, a navy arrow carrying the power it draws, and the output with its quantity. Faint steam
## rises behind it all.
const _GRID_MAX_ISLANDS := 5
const _ISL_PAD := 30.0
const _ISL_HEAD_H := 126.0    # the recipe's name, and under it, when locked, its research
const _ISL_RESEARCH_Y := 52.0 # the research row, below the name
const _SEE_KEY := Vector2(250.0, 52.0)  # the See Research key, right of the research screen
const _SEE_GAP := 18.0
const _SIGN_H := 240.0        # the enamel sign
const _SIGN_PAD := 30.0       # the sign's field inside its cut
const _ISL_BLD := 150.0       # the building's embossed icon, left of the sign
const _SIGN_IN := 124.0       # an input's icon
const _SIGN_IN_GAP := 26.0
const _SIGN_ARROW := Vector2(230.0, 96.0)
const _SIGN_OUT := 176.0      # the output's icon
const _SIGN_GAP := 44.0       # between the sign's groups
const _ISL_GAP_X := 120.0
const _ISL_GAP_Y := 90.0
const _GRUNGE: Texture2D = preload("res://assets/ui/bdp_v3/recipe_grunge.png")
const _BOLT_YELLOW := Color("#f5b800")
## Steam: how many puffs rise behind the grid, their size range on screen, and how bright the brightest is.
const _STEAM_PUFFS := 34
const _STEAM_SIZE := Vector2(180.0, 420.0)
const _STEAM_ALPHA := 0.09
static var _steam_tex: Texture2D
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
	_grid_key_hover = -1
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


## Pack up to 5 islands: a single column for <=3 recipes, two columns for 4-5, every island as wide as the widest
## recipe needs, so the signs line up.
func _layout_grid(internal: String, routes: Array) -> void:
	_grid_islands.clear()
	var node: Dictionary = _by_id.get(internal, {})
	var count := mini(routes.size(), _GRID_MAX_ISLANDS)
	var cols := 1 if count <= 3 else 2
	var most := 1
	for i in range(count):
		most = maxi(most, (((routes[i] as Dictionary)["recipe"] as Dictionary).get("inputs", []) as Array).size())
	var sign_w := _SIGN_PAD * 2.0 + float(most) * (_SIGN_IN + _SIGN_IN_GAP) - _SIGN_IN_GAP \
		+ _SIGN_GAP + _SIGN_ARROW.x + _SIGN_GAP + _SIGN_OUT
	var island := Vector2(_ISL_PAD * 2.0 + _ISL_BLD + _SIGN_GAP + sign_w, _ISL_PAD * 2.0 + _ISL_HEAD_H + _SIGN_H)
	_grid_bbox = Rect2()
	for i in range(count):
		var route: Dictionary = routes[i]
		var recipe: Dictionary = route["recipe"]
		var rect := Rect2(Vector2(float(i % cols) * (island.x + _ISL_GAP_X), float(i / cols) * (island.y + _ISL_GAP_Y)), island)
		var sign := Rect2(rect.position + Vector2(_ISL_PAD + _ISL_BLD + _SIGN_GAP, _ISL_PAD + _ISL_HEAD_H), Vector2(sign_w, _SIGN_H))
		var mid_y := sign.get_center().y
		var bicon := Rect2(Vector2(rect.position.x + _ISL_PAD, mid_y - _ISL_BLD * 0.5), Vector2(_ISL_BLD, _ISL_BLD))
		var x := sign.position.x + _SIGN_PAD
		var in_rects: Array = []
		for inp: Dictionary in recipe.get("inputs", []):
			in_rects.append({"rect": Rect2(Vector2(x, mid_y - _SIGN_IN * 0.5), Vector2(_SIGN_IN, _SIGN_IN)),
				"good_id": str(inp.get("good_id", "")), "internal": str(inp.get("internal_name", "")),
				"qty": int(inp.get("qty", 0))})
			x += _SIGN_IN + _SIGN_IN_GAP
		# The arrow and the output keep their places whatever the input count, so every sign's output lines up.
		var arrow_x := sign.end.x - _SIGN_PAD - _SIGN_OUT - _SIGN_GAP - _SIGN_ARROW.x
		var arrow := Rect2(Vector2(arrow_x, mid_y - _SIGN_ARROW.y * 0.5), _SIGN_ARROW)
		var out := Rect2(Vector2(sign.end.x - _SIGN_PAD - _SIGN_OUT, mid_y - _SIGN_OUT * 0.5), Vector2(_SIGN_OUT, _SIGN_OUT))
		var bld: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
		_grid_islands.append({
			"recipe": recipe,
			"gated": bool(route["gated"]) and not _recipe_unlocked(route["recipe"]),
			"rect": rect,
			"sign": sign,
			"inputs": in_rects,
			"arrow": arrow,
			"out_rect": out,
			"out_qty": Catalog.recipe_output_qty(recipe, str(node.get("good_id", ""))),
			"internal": internal,
			"building_name": str(bld.get("display_name", "")),
			"bicon_rect": bicon,
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
		_paint_plate(rect, _PLATE_DIM if gated else Color.WHITE, false)
		# The recipe's name engraved at the top with a locked one's padlock beside it; under it, the research it needs.
		var name := str(recipe.get("display_name", ""))
		var head := rect.position + Vector2(_ISL_PAD, _ISL_PAD)
		var name_w := _BEBAS.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		draw_string(_BEBAS, head + Vector2(1.5, 33.5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0, 0, 0, 0.85))
		draw_string(_BEBAS, head + Vector2(0.0, 32.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, DS.PALETTE.ACCENT)
		var research := _recipe_research_title(recipe)
		if gated:
			_draw_lock_tag(head + Vector2(name_w + 24.0, 22.0), 1.0, 1.2)
			# The research it needs on a dot-matrix screen, "REQUIRES" in amber, the research in white, and right of
			# it the See Research key. Clicking either opens Research (_grid_research_at).
			_draw_dot_screen(_research_screen_rect(island), _research_runs(recipe))
			var key := _see_research_rect(island)
			if key.has_area():
				var i := _grid_islands.find(island)
				_draw_key(key, i == _grid_key_hover)
				draw_string(_BEBAS, Vector2(key.position.x, key.get_center().y + 9.0), "See Research",
					HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 28, _KEY_INK)
		elif research != "" and str(recipe.get("tech_unlock_req", "")) != "":
			# Locked in the catalog, unlocked by research: the open padlock beside the name.
			_draw_lock_tag(head + Vector2(name_w + 24.0, 22.0), 1.0, 1.2, true)
		# The enamel sign and its wear.
		var sign: Rect2 = island["sign"]
		_paint_scaled(_ENAMEL, sign.grow(_ENAMEL_MARGIN * _PLATE_K), _ENAMEL_CORNER, _PLATE_K)
		draw_texture_rect(_GRUNGE, sign.grow(-_SIGN_PAD * 0.6), false, Color(1, 1, 1, 0.5))
		# The building left of the sign, embossed in silver on the plate: a dark cut shadow below right, a bright
		# edge above left, the silver face over both, and a shine across it.
		var bicon_rect: Rect2 = island["bicon_rect"]
		var bicon: Texture2D = _BuildingIcon.clean_texture(str(recipe.get("building_id", "")),
			str(Catalog.get_building(str(recipe.get("building_id", ""))).get("internal_name", "")))
		if bicon != null:
			draw_texture_rect(bicon, Rect2(bicon_rect.position + Vector2(3.0, 3.5), bicon_rect.size), false, Color(0, 0, 0, 0.8))
			draw_texture_rect(bicon, Rect2(bicon_rect.position - Vector2(1.5, 1.5), bicon_rect.size), false, Color(1, 1, 1, 0.75))
			draw_texture_rect(bicon, bicon_rect, false, _SILVER_FOOT)
			draw_texture_rect(bicon, Rect2(bicon_rect.position - Vector2(0.6, 0.6), bicon_rect.size), false, Color(_SILVER_TOP, 0.55))
		# The inputs, each with its quantity.
		var inputs: Array = island["inputs"]
		if inputs.is_empty():
			draw_string(font, Vector2(bicon_rect.end.x + _SIGN_GAP, sign.get_center().y + 8.0), "No inputs",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, DS.PALETTE.BG_PANEL)
		for inp in inputs:
			var entry: Dictionary = inp
			_draw_sign_good(entry["rect"] as Rect2, str(entry["good_id"]), str(entry["internal"]), int(entry["qty"]), font)
		# The arrow, carrying the power the recipe draws.
		var arrow: Rect2 = island["arrow"]
		var head_w := arrow.size.y * 0.55
		var body := Rect2(arrow.position + Vector2(0.0, arrow.size.y * 0.18), Vector2(arrow.size.x - head_w, arrow.size.y * 0.64))
		draw_rect(body, DS.PALETTE.BG_PANEL)
		draw_colored_polygon(PackedVector2Array([Vector2(body.end.x, arrow.position.y), Vector2(arrow.end.x, arrow.get_center().y),
			Vector2(body.end.x, arrow.end.y)]), DS.PALETTE.BG_PANEL)
		var energy := int(recipe.get("energy_req", 0))
		if energy > 0:
			var label := str(energy)
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			var x0 := body.get_center().x - (lw + 8.0 + 26.0) * 0.5
			draw_string(font, Vector2(x0, body.get_center().y + 12.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, DS.PALETTE.ACCENT)
			var bolt := PackedVector2Array()
			for p: Vector2 in _BOLT_SHAPE:
				bolt.append(Vector2(x0 + lw + 4.0, body.get_center().y - 17.0) + p * 34.0)
			draw_colored_polygon(bolt, _BOLT_YELLOW)
		# The output with its quantity.
		_draw_sign_good(island["out_rect"] as Rect2, str(node.get("good_id", "")), str(island["internal"]), int(island["out_qty"]), font)
	# Hovered building: its name over it, engraved on a small dark plate.
	if _grid_hover >= 0 and _grid_hover < _grid_islands.size():
		var isl: Dictionary = _grid_islands[_grid_hover]
		var brect: Rect2 = isl["bicon_rect"]
		var bname := str(isl["building_name"])
		var tw := font.get_string_size(bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var tip := Rect2(Vector2(brect.get_center().x - tw * 0.5 - 14.0, brect.position.y - 46.0), Vector2(tw + 28.0, 36.0))
		draw_colored_polygon(_rounded_rect_points(tip, 6.0), Color(DS.PALETTE.BG_PANEL, 0.96))
		var tr2 := _rounded_rect_points(tip, 6.0)
		tr2.append(tr2[0])
		draw_polyline(tr2, Color(DS.PALETTE.ACCENT, 0.8), 1.4, true)
		draw_string(font, Vector2(tip.position.x + 14.0, tip.get_center().y + 6.0), bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DS.PALETTE.TEXT)


## A good on the sign as Building Detail draws it: the icon straight on the enamel, its quantity on a dark round
## pill at its bottom right.
func _draw_sign_good(r: Rect2, good_id: String, internal: String, qty: int, font: Font) -> void:
	GoodHover.drawn(self, Rect2(r.position * _view_zoom + _view_offset, r.size * _view_zoom), good_id)
	var icon: Texture2D = GoodIcons.texture_for_size(good_id, internal, r.size.x)
	if icon != null:
		var ts := icon.get_size()
		var fit := minf(r.size.x / ts.x, r.size.y / ts.y)
		draw_texture_rect(icon, Rect2(r.get_center() - ts * fit * 0.5, ts * fit), false)
	if qty <= 0:
		return
	var text := str(qty)
	var fs := 26
	var ph := 40.0
	var pw := maxf(ph, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0)
	var pill := Rect2(r.end - Vector2(pw * 0.7, ph * 0.75), Vector2(pw, ph))
	draw_colored_polygon(_rounded_rect_points(pill, ph * 0.5), _SIGN_PILL)
	draw_string(font, Vector2(pill.position.x, pill.get_center().y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, fs, DS.PALETTE.ACCENT)


const _SIGN_PILL := Color("#0d0f13")
## The research line's screen: DotMatrix's mini screen (mini_screen.png, a gunmetal bezel round a dark pane) and
## its dots at this pitch in world units, rendered once per text into a cached texture, since the grid redraws
## every frame for its steam.
const _DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const _DOT_PITCH := 3.4
const _DOT_TEX_PX := 6               # texture pixels per dot pitch
static var _dot_cache: Dictionary = {}


## The research screen's runs for a locked recipe: "REQUIRES " in amber, the research in white.
func _research_runs(recipe: Dictionary) -> Array:
	var gate_raw := str(recipe.get("tech_unlock_req", ""))
	var gate_name := ResearchState.research_title_for_node_id(gate_raw)
	return [{"text": "REQUIRES ", "colour": DS.PALETTE.WARN},
		{"text": gate_name if gate_name != "" else gate_raw, "colour": Color.WHITE}]


## Where an island's research screen sits: on its own row under the name, as wide as its text, leaving room for
## the See Research key at its right.
func _research_screen_rect(island: Dictionary) -> Rect2:
	var rect: Rect2 = island["rect"]
	var at := rect.position + Vector2(_ISL_PAD, _ISL_PAD + _ISL_RESEARCH_Y)
	var room := rect.end.x - _ISL_PAD - at.x - _SEE_KEY.x - _SEE_GAP
	return Rect2(at, _dot_screen_size(_research_runs(island["recipe"] as Dictionary), room))


## The See Research key right of the research screen; empty when the research can't be shown in Research.
func _see_research_rect(island: Dictionary) -> Rect2:
	if not bool(island["gated"]) or _recipe_research_title(island["recipe"] as Dictionary) == "":
		return Rect2()
	var screen := _research_screen_rect(island)
	return Rect2(Vector2(screen.end.x + _SEE_GAP, screen.get_center().y - _SEE_KEY.y * 0.5), _SEE_KEY)


const _DOT_SCREEN_PAD := Vector2(10.0, 8.0)


## A dot-matrix screen's size for `runs`, no wider than `max_w`.
func _dot_screen_size(runs: Array, max_w: float) -> Vector2:
	var text := ""
	for run: Dictionary in runs:
		text += str(run.text)
	var dots := Vector2(_DotMatrix.string_width(text, 1.0) * _DOT_PITCH, _DotMatrix.ROWS * _DOT_PITCH)
	return Vector2(minf(max_w, dots.x + _DOT_SCREEN_PAD.x * 2.0), dots.y + _DOT_SCREEN_PAD.y * 2.0)


## `runs` ([{text, colour}]) on a dot-matrix screen fitted to `r`: the bezel, the pane, the dots left aligned.
func _draw_dot_screen(r: Rect2, runs: Array) -> void:
	var text := ""
	for run: Dictionary in runs:
		text += str(run.text)
	var tex := _dot_texture(runs)
	var pad := _DOT_SCREEN_PAD
	var dots := Vector2(_DotMatrix.string_width(text, 1.0) * _DOT_PITCH, _DotMatrix.ROWS * _DOT_PITCH)
	var screen := Rect2(r.position, _dot_screen_size(runs, r.size.x))
	var k := 1.0
	_paint_scaled(_DotMatrix.SCREEN, screen.grow(_DotMatrix.MARGIN / _DotMatrix.CAPTURE_SCALE * k),
		(_DotMatrix.MARGIN + _DotMatrix.RIM + _DotMatrix.RADIUS + 2.0) * 2.0 / _DotMatrix.CAPTURE_SCALE, k)
	draw_rect(screen.grow(-_DotMatrix.RIM / _DotMatrix.CAPTURE_SCALE), _DotMatrix.PANE)
	var shown := Vector2(minf(dots.x, screen.size.x - pad.x * 2.0), dots.y)
	draw_texture_rect_region(tex, Rect2(screen.position + pad, shown),
		Rect2(Vector2.ZERO, Vector2(shown.x / _DOT_PITCH * _DOT_TEX_PX, float(tex.get_height()))))


## The dots of `runs` as a texture: lit dots with their glow in each run's colour over faint unlit ones, as
## DotMatrix draws them, DOT_TEX_PX texture pixels a dot.
func _dot_texture(runs: Array) -> Texture2D:
	var key := str(runs)
	if _dot_cache.has(key):
		return _dot_cache[key]
	var text := ""
	for run: Dictionary in runs:
		text += str(run.text)
	var px := _DOT_TEX_PX
	var w := int(ceil(_DotMatrix.string_width(text, 1.0) * px)) + px
	var h := _DotMatrix.ROWS * px
	var img := Image.create(maxi(w, 1), h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(px) * 0.5
	for run: Dictionary in runs:
		var lit: Color = run.colour
		for ch in str(run.text).to_upper():
			var rows: Array = _DotMatrix.FONT.get(ch, _DotMatrix.FONT[" "])
			var cols := _DotMatrix.THIN_COLUMNS if ch == _DotMatrix.THIN else _DotMatrix.COLUMNS
			for row in _DotMatrix.ROWS:
				var bits := int(rows[row]) if ch != _DotMatrix.THIN else 0
				for col in cols:
					var c := Vector2(cx + col * px, row * px + px * 0.5)
					var on := (bits & (1 << (_DotMatrix.COLUMNS - 1 - col))) != 0
					_dot(img, c, px * (0.48 if on else 0.32), lit if on else Color(1, 1, 1, _DotMatrix.UNLIT_ALPHA * 2.0))
			cx += (cols + 1) * px
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_dot_cache[key] = tex
	return tex


static func _dot(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r - 1.0), int(c.y + r + 2.0)):
		for x in range(int(c.x - r - 1.0), int(c.x + r + 2.0)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r + 0.5 - d, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(col, col.a * a))
const _BOLT_SHAPE := preload("res://scripts/ds2/bolt_icon.gd").SHAPE
## Faint steam rising behind the grid, in screen space: soft puffs drifting up from below the screen, swelling and
## fading as they rise. Each puff's path is fixed by its index, so the drift is the same every time it opens.
func _draw_steam() -> void:
	if _steam_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_steam_tex = gt
	var view := get_rect().size
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in _STEAM_PUFFS:
		var fi := float(i)
		var speed := 0.018 + fposmod(fi * 0.371, 1.0) * 0.022
		var f := fposmod(fposmod(fi * 0.913, 1.0) + t * speed, 1.0)
		var size := lerpf(_STEAM_SIZE.x, _STEAM_SIZE.y, fposmod(fi * 0.577, 1.0)) * (0.6 + 0.8 * f)
		var x := fposmod(fi * 0.618, 1.0) * view.x + sin(t * 0.25 + fi) * 40.0 + f * 60.0
		var y := view.y * (1.15 - 1.4 * f)
		var a := _STEAM_ALPHA * sin(PI * f)
		draw_texture_rect(_steam_tex, Rect2(Vector2(x, y) - Vector2(size, size) * 0.5, Vector2(size, size)), false,
			Color(0.92, 0.94, 0.97, a))


## Resolve only actual, visible research; base recipes and demo-hidden nodes have no link.
func _recipe_research_title(recipe: Dictionary) -> String:
	var id := str(recipe.get("tech_unlock_req", ""))
	var title := ResearchState.research_title_for_node_id(id)
	if title == "": return ""
	var definition := ResearchState.get_unlock_def(title)
	return title if not definition.is_empty() and ResearchState.is_research_visible(definition) else ""

func _grid_research_at(world_pos: Vector2) -> String:
	for island in _grid_islands:
		var recipe: Dictionary = island["recipe"]
		var title := _recipe_research_title(recipe)
		if title == "": continue
		var head: Vector2 = (island["rect"] as Rect2).position + Vector2(_ISL_PAD, _ISL_PAD)
		var width := _BEBAS.get_string_size(str(recipe.get("display_name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		if Rect2(head, Vector2(width + 4.0, 40.0)).has_point(world_pos) or _research_screen_rect(island).has_point(world_pos) \
				or _see_research_rect(island).has_point(world_pos):
			return title
	return ""
