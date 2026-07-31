extends Control
## Empire view — graph drawing layer (Milestone 3+: pan/zoom, orthogonal routing, sell lines).
##
## A manual camera (`_view_offset` + `_view_zoom`) pans/zooms the graph. Node POSITIONS scale and
## translate with zoom; the FURNITURE (cards, port hexes, line widths, routing offsets) is drawn at
## a fixed pixel size times `_detail()` — it follows zoom out (so the zoom-out cap can be "the whole
## empire fits") and is capped at 1.0 zooming in.
## Input edges (thin amber) and sell-to-market edges (thick gold, building -> export port) are routed
## orthogonally with 45deg chamfered corners and lane separation so they avoid overlapping each other.
## Drag / two-finger pan, scroll / pinch to zoom, WASD to pan. No sim logic here (CLAUDE.md #2/#5).

const _GOLD := Color(0.995, 0.931, 0.763, 1.0)             # port rim / name text
const _EDGE := Color(0.995, 0.931, 0.763, 0.34)            # amber input lines, translucent
const _SELL := Color(0.98, 0.80, 0.30, 0.95)               # thick gold sell-to-market lines

const _EDGE_WIDTH := 2.0
const _SELL_WIDTH := 5.0
const _CHAMFER := 16.0                                      # 45deg corner cut length (screen px)
const _PORT_MAX_SLOTS := 5                                  # max distinct line entry points per port (2-1-2)

const _ZOOM_MIN := 0.05                                     # absolute floor; the REAL floor is the
                                                            # whole-composition fit, which a 50-building
                                                            # empire (7.6 viewports tall) puts at ~0.12 —
                                                            # the old 0.2 clamped above it and broke
                                                            # "see the entire empire at a glance"
const _ZOOM_MAX := 2.5
const _ZOOM_STEP := 1.12
const _PAN_SPEED := 900.0
const _MIN_GAP := 20.0                                      # hard minimum screen gap between panels, at any zoom
const _FIT_PAD := 120.0                                     # viewport margin left by the fit
const _DETAIL_MIN := 0.05                                   # furniture tracks zoom all the way to _ZOOM_MIN
const _SEP_ITERS := 28                                      # screen-space separation passes per frame

const NodePanelScript := preload("res://scripts/empire_node_panel.gd")
const LaneOrder := preload("res://scripts/lane_order.gd")

var _nodes: Array = []
var _ports: Array = []
var _edges: Array = []
var _sell_edges: Array = []
var _pos_by_iid: Dictionary = {}
var _box_by_iid: Dictionary = {}
var _panels: Array = []                                     # [{ctrl, iid, pos}] real node Controls
var _screen_by_iid: Dictionary = {}                         # iid -> current screen pos (panels separated, ports projected)

var _buy_ports: Array = []                  # the top-edge BUY mirrors of the four ports
var _market_edges: Array = []               # {from:"buy_<port>", to:iid, good, slot, slot_n}
var _view_zoom: float = 1.0
var _view_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false

# Dynamic zoom-out cap: panels are drawn at CONSTANT pixel size, so past a
# certain zoom-out the world positions compress under the fixed-size cards and
# the separation pass just shoves identical cards around the viewport
# ("jostling"). _compute_zoom_floor caps zoom-out at the point where typical
# card spacing meets the card footprint, so that regime is unreachable.
var _zoom_floor: float = _ZOOM_MIN
# Reposition-on-change: panel positions depend only on (zoom, offset, size,
# graph) — the old _process re-ran the O(n²) separation every frame regardless.
# --- FOCUS MINI-CHART (selecting a building) ---------------------------------------------
# Same animation contract as the goods graph: `_focus_t` eases 0->1 over 0.28s, members tween
# from their web position to a focus position, everyone else fades out. Depth ONE only — the
# selection, whatever feeds its inputs, and whatever it feeds (buildings or ports). Nothing
# beyond that: a second ring is what turns the goods graph's focus into a second web.
const _FOCUS_SECS := 0.28
const _FOCUS_COL := 620.0                   # column spacing (sprite panel is 400 wide)
const _FOCUS_ROW := 660.0                   # row spacing (sprite panel is 580 tall)
var _focus_iid := ""
var _focus_t := 0.0
var _focus_target := 0.0
var _fpos: Dictionary = {}                  # iid -> focus position (layout space)
var _focus_members: Dictionary = {}         # iid -> true

var _last_zoom := -1.0
var _last_offset := Vector2.INF
var _last_size := Vector2.ZERO


func _ready() -> void:
	set_process(true)
	# The floor is a function of the viewport, so re-derive it on resize — otherwise a window
	# change leaves you able to zoom out past the composition, or unable to reach it.
	resized.connect(func() -> void:
		_zoom_floor = _compute_zoom_floor()
		if is_finite(_zoom_floor):
			_view_zoom = maxf(_view_zoom, _zoom_floor)
		_mark_view_dirty())
	# A drag interrupted by the view closing never receives its mouse-up; without
	# this reset the next open pans on bare mouse motion.
	visibility_changed.connect(func() -> void: _dragging = false)


func _mark_view_dirty() -> void:
	_last_zoom = -1.0


func set_graph(nodes: Array, edges: Array, ports: Array, sell_edges: Array = [],
		market_edges: Array = [], buy_ports: Array = []) -> void:
	_nodes = nodes
	_edges = edges
	_ports = ports
	_sell_edges = sell_edges
	_market_edges = market_edges
	# The buy row always draws, fed or not — the two aligned rows frame the composition,
	# and a port with no dashed lines correctly reads as "nothing bought through here".
	_buy_ports = buy_ports
	_pos_by_iid.clear()
	_box_by_iid.clear()
	for arr in [_nodes, _ports, _buy_ports]:
		for n in arr:
			_pos_by_iid[n["iid"]] = n["pos"]
			_box_by_iid[n["iid"]] = n
	_assign_lanes()
	_rebuild_panels()
	_zoom_floor = _compute_zoom_floor()
	_reset_view()
	_mark_view_dirty()
	_reposition_panels()
	queue_redraw()


## Zoom-out stops when the ENTIRE composition fits the viewport — bounded by whichever of its
## dimensions is the more constraining one, so you can never zoom out into empty space.
## Owner decision 2026-07-30: seeing the whole empire at once beats crisp text; the furniture
## (cards, ports, lines) scales down with zoom via _detail() rather than holding its pixels,
## which is what retires the old median-spacing "jostling" floor.
func _compute_zoom_floor() -> float:
	var bb := _layout_bbox()
	if not (is_finite(bb.size.x) and is_finite(bb.size.y)):
		return _ZOOM_MIN
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return _ZOOM_MIN
	var view := get_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1920.0, 1080.0)
	var fit := minf((view.x - _FIT_PAD) / bb.size.x, (view.y - _FIT_PAD) / bb.size.y)
	if not is_finite(fit):
		return _ZOOM_MIN
	return clampf(fit, _ZOOM_MIN, 1.0)


## Fixed-pixel furniture is multiplied by this. Follows zoom on the way OUT (whole composition
## shrinks as one piece) and is capped at 1.0 on the way in (zooming past 100% spreads the
## graph apart without inflating the furniture). Never returns a non-finite value: a NaN here
## would reach Control.scale and draw_* widths, and a non-finite transform makes the renderer
## size buffers from an infinite bounding rect — that is a machine-killing allocation, not a
## visual glitch.
func _detail() -> float:
	if not is_finite(_view_zoom):
		return 1.0
	return clampf(_view_zoom, _DETAIL_MIN, 1.0)


## Build one real Control panel per building node (ports stay as drawn hexagons). Rebuilt on open.
func _rebuild_panels() -> void:
	# A rebuilt graph invalidates every focus position and member id.
	_focus_iid = ""
	_focus_t = 0.0
	_focus_target = 0.0
	_fpos.clear()
	_focus_members.clear()
	for p in _panels:
		(p["ctrl"] as Node).queue_free()
	_panels.clear()
	for n in _nodes:
		var panel: Control = NodePanelScript.new()
		add_child(panel)
		panel.call("setup", n)
		# Panel sizes settle a frame after creation; repositioning is gated on
		# view change, so a late size change must re-mark the view dirty.
		panel.resized.connect(_mark_view_dirty)
		_panels.append({"ctrl": panel, "iid": str(n["iid"]), "pos": n["pos"]})


## Recompute every node's current screen position and move the panels there. Ports project straight
## through; building panels then get a screen-space separation pass so no two are ever closer than
## _MIN_GAP — at ANY zoom (when zoomed out they spread apart instead of overlapping). Panels keep a
## fixed pixel size; only their position changes, so text/icons never resample. The connector lines
## read these same positions (via `_screen_by_iid`) so they follow.
func _reposition_panels() -> void:
	_screen_by_iid.clear()
	for p in _ports:
		_screen_by_iid[str(p["iid"])] = _world_to_screen(p["pos"] as Vector2)

	var sc := _detail()
	var ids: Array = []
	var pos: Dictionary = {}
	var half: Dictionary = {}
	for pan in _panels:
		var iid: String = pan["iid"]
		ids.append(iid)
		var wp: Vector2 = pan["pos"] as Vector2
		if _focus_t > 0.0 and _fpos.has(iid):
			wp = wp.lerp(_fpos[iid] as Vector2, _focus_t)
		pos[iid] = _world_to_screen(wp)
		# Footprint AND gap scale with the card, or the separation pass fights the zoom: an
		# unscaled gap dominates once cards are small and re-creates the jostling.
		half[iid] = (pan["ctrl"] as Control).size * (0.5 * sc) + Vector2(_MIN_GAP * sc * 0.5, _MIN_GAP * sc * 0.5)

	# Port hexes are OBSTACLES, not participants: they hold the positions the layout gave them
	# (their x carries the sector meaning) and panels give way. Without this the pass separated
	# panels from each other only, so a sprite — which is 400px tall growing upward — happily
	# sat on top of the buy-port row above it.
	var port_rects: Array = []
	for p2 in _ports:
		port_rects.append({
			"c": _world_to_screen(p2["pos"] as Vector2),
			"h": (p2["half"] as Vector2) * sc + Vector2(_MIN_GAP * sc, _MIN_GAP * sc),
		})

	for _it in range(_SEP_ITERS):
		var moved := false
		for i in range(ids.size()):
			var pid: String = ids[i]
			for pr in port_rects:
				var dp: Vector2 = (pos[pid] as Vector2) - (pr["c"] as Vector2)
				var hp: Vector2 = half[pid]
				var hh: Vector2 = pr["h"]
				var px := hp.x + hh.x - absf(dp.x)
				var py := hp.y + hh.y - absf(dp.y)
				if px <= 0.0 or py <= 0.0:
					continue
				moved = true
				# Resolve on the SHALLOWER axis, and move the panel only.
				if px <= py:
					pos[pid] = (pos[pid] as Vector2) + Vector2(px * (1.0 if dp.x >= 0.0 else -1.0), 0.0)
				else:
					pos[pid] = (pos[pid] as Vector2) + Vector2(0.0, py * (1.0 if dp.y >= 0.0 else -1.0))
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				var a: String = ids[i]
				var b: String = ids[j]
				var d: Vector2 = (pos[b] as Vector2) - (pos[a] as Vector2)
				var ha: Vector2 = half[a]
				var hb: Vector2 = half[b]
				var ox := ha.x + hb.x - absf(d.x)
				var oy := ha.y + hb.y - absf(d.y)
				if ox <= 0.0 or oy <= 0.0:
					continue
				moved = true
				if ox <= oy:
					var s := 0.5 * ox * (1.0 if d.x >= 0.0 else -1.0)
					if absf(d.x) < 0.01:
						s = 0.5
					pos[a] = (pos[a] as Vector2) - Vector2(s, 0.0)
					pos[b] = (pos[b] as Vector2) + Vector2(s, 0.0)
				else:
					var s2 := 0.5 * oy * (1.0 if d.y >= 0.0 else -1.0)
					if absf(d.y) < 0.01:
						s2 = 0.5
					pos[a] = (pos[a] as Vector2) - Vector2(0.0, s2)
					pos[b] = (pos[b] as Vector2) + Vector2(0.0, s2)
		if not moved:
			break

	for pan in _panels:
		var iid2: String = pan["iid"]
		_screen_by_iid[iid2] = pos[iid2]
		var ctrl := pan["ctrl"] as Control
		# scale pivots on the top-left, so the stored screen position is the CENTRE and the
		# top-left is walked back by the SCALED half-size.
		ctrl.scale = Vector2(sc, sc)
		ctrl.position = (pos[iid2] as Vector2) - ctrl.size * (0.5 * sc)
		# Non-members fade right out; members stay solid. Hidden once invisible so they stop
		# taking clicks — a ghost card you can still select is worse than no card.
		var a := 1.0 if (_focus_t <= 0.0 or _focus_members.has(iid2)) else (1.0 - _focus_t)
		ctrl.modulate.a = a
		ctrl.visible = a > 0.01


## Screen position of a node (separated for panels, projected for ports), with a projection fallback.
func _screen_of(iid: String, node: Dictionary) -> Vector2:
	if _screen_by_iid.has(iid):
		return _screen_by_iid[iid]
	return _world_to_screen(node["pos"] as Vector2)


## Screen centre of a node's PLATE. In sprite view the Control grows upward around the big
## sprite, so the plate centre sits `plate_dy` below the Control centre — edges anchor here
## so arrows keep emerging from the plate exactly as in classic mode. Ports have no plate_dy.
func _plate_screen_of(iid: String, node: Dictionary) -> Vector2:
	return _screen_of(iid, node) + Vector2(0.0, float(node.get("plate_dy", 0.0)) * _detail())


## Current screen-space CENTRES of the building panels (not ports) — the hex-field background ripples
## its building-origin pulses (anim 1) out of these. Uses the per-frame separated positions.
func building_screen_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for pan in _panels:
		var iid: String = pan["iid"]
		if _screen_by_iid.has(iid):
			out.append(_screen_by_iid[iid] as Vector2)
		else:
			out.append(_world_to_screen(pan["pos"] as Vector2))
	return out


## Give edges that cross the same vertical channel distinct lanes (so their vertical segments don't
## overlap), ordered by target Y to cut crossings; sell edges get distinct horizontal bus lanes.
func _assign_lanes() -> void:
	var buckets: Dictionary = {}
	for e in _edges:
		if not (_pos_by_iid.has(e["from"]) and _pos_by_iid.has(e["to"])):
			continue
		var pa: Vector2 = _pos_by_iid[e["from"]]
		var pb: Vector2 = _pos_by_iid[e["to"]]
		var key := "%d_%d" % [int(round(pa.x / 10.0)), int(round(pb.x / 10.0))]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(e)
	# CHANNEL LANES, ordered by minimum pairwise crossings — the same solver the goods graph
	# uses (scripts/lane_order.gd), not a sort by target y. Sorting by target y only stops
	# lanes braiding within the channel; it is blind to the horizontal runs that continue past
	# a lane, which is where the crossings actually come from. Each edge in a channel is a Z:
	# stub out of the source plate at its y, a vertical at its lane x, a run into the target.
	for key in buckets:
		var arr: Array = buckets[key]
		var legs: Array = []
		for i in range(arr.size()):
			var pa2: Vector2 = _pos_by_iid[arr[i]["from"]]
			var pb2: Vector2 = _pos_by_iid[arr[i]["to"]]
			legs.append([i, 0, pa2.y, pb2.y, 1 if pb2.x >= pa2.x else -1])
		var ordered: Array = LaneOrder.solve(legs)
		for li in range(ordered.size()):
			var ei: int = int((ordered[li] as Array)[0])
			arr[ei]["lane"] = li
			arr[ei]["lane_n"] = ordered.size()
	_sell_edges.sort_custom(func(x, y): return (_pos_by_iid[x["from"]] as Vector2).x < (_pos_by_iid[y["from"]] as Vector2).x)
	for i in range(_sell_edges.size()):
		_sell_edges[i]["bus"] = i
		_sell_edges[i]["bus_n"] = _sell_edges.size()
	# Per-port entry slots: each port hex takes at most _PORT_MAX_SLOTS (5) distinct entry points
	# along its top edge (spaced 2-1-2). When a port receives more lines than that, they share slots
	# (contiguous groups) and merge into the same entry — no port ever sprouts more than 5 lines.
	var by_port: Dictionary = {}
	for e in _sell_edges:
		var pid: String = str(e["to"])
		if not by_port.has(pid):
			by_port[pid] = []
		by_port[pid].append(e)
	for pid in by_port:
		var arr: Array = by_port[pid]
		# Entry order along the hex top is a channel problem too: the legs run DOWN into the
		# port, so x plays the role y does between columns.
		var slegs: Array = []
		for i in range(arr.size()):
			var sa: Vector2 = _pos_by_iid[arr[i]["from"]]
			var sb: Vector2 = _pos_by_iid[arr[i]["to"]]
			slegs.append([i, 0, sa.x, sb.x, 1 if sb.y >= sa.y else -1])
		var sord: Array = LaneOrder.solve(slegs)
		var reord: Array = []
		for lg in sord:
			reord.append(arr[int((lg as Array)[0])])
		arr = reord
		by_port[pid] = arr
		var n := mini(arr.size(), _PORT_MAX_SLOTS)
		for i in range(arr.size()):
			arr[i]["slot"] = (i * n) / arr.size() if arr.size() > 0 else 0
			arr[i]["slot_n"] = n

	# Market edges leave each buy port through the same <=5-slot spread as the sells enter
	# theirs, ordered by target x so the fan-out never self-crosses at the hex.
	var by_buy: Dictionary = {}
	for e in _market_edges:
		if not _pos_by_iid.has(str(e["to"])):
			continue
		var bid: String = str(e["from"])
		if not by_buy.has(bid):
			by_buy[bid] = []
		by_buy[bid].append(e)
	for bid in by_buy:
		var marr: Array = by_buy[bid]
		marr.sort_custom(func(x, y): return (_pos_by_iid[str(x["to"])] as Vector2).x < (_pos_by_iid[str(y["to"])] as Vector2).x)
		var mn := mini(marr.size(), _PORT_MAX_SLOTS)
		for i in range(marr.size()):
			marr[i]["slot"] = (i * mn) / marr.size()
			marr[i]["slot_n"] = mn


func _reset_view() -> void:
	var bb := _layout_bbox()
	var view := get_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1920.0, 1080.0)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		_view_zoom = 1.0
		_view_offset = view * 0.5
		return
	# Same _FIT_PAD as the floor, so for an empire larger than the viewport the opening view IS
	# the zoom-out cap — open, and you are already looking at everything.
	var fit := minf((view.x - _FIT_PAD) / bb.size.x, (view.y - _FIT_PAD) / bb.size.y)
	_view_zoom = clampf(fit, _zoom_floor, 1.0)
	_view_offset = view * 0.5 - bb.get_center() * _view_zoom


## While focused this is the MINI-CHART's box, not the empire's — the zoom floor and the fit
## both read it, so focusing frames the five nodes instead of leaving them adrift somewhere in
## a whole-empire view. Same trick the goods graph uses.
func _layout_bbox() -> Rect2:
	if _focus_t > 0.5 and not _fpos.is_empty():
		var fb := Rect2()
		var f1 := true
		for iid in _fpos:
			var nn: Dictionary = _box_by_iid.get(iid, {})
			var hh: Vector2 = (nn.get("half", Vector2(200.0, 290.0)) as Vector2)
			var r2 := Rect2((_fpos[iid] as Vector2) - hh, hh * 2.0)
			if f1:
				fb = r2
				f1 = false
			else:
				fb = fb.merge(r2)
		if fb.size.x > 0.0 and fb.size.y > 0.0:
			return fb
	var bb := Rect2()
	var first := true
	for arr in [_nodes, _ports, _buy_ports]:
		for n in arr:
			var r := Rect2((n["pos"] as Vector2) - (n["half"] as Vector2), (n["half"] as Vector2) * 2.0)
			if first:
				bb = r
				first = false
			else:
				bb = bb.merge(r)
	return bb


func _world_to_screen(p: Vector2) -> Vector2:
	return p * _view_zoom + _view_offset


# --- interaction -------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, _ZOOM_STEP)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _focus_target > 0.0:
			# The panels swallow their own clicks, so a left click that reaches the canvas is
			# a click on empty space — which is how you leave the mini-chart.
			clear_focus()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / _ZOOM_STEP)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_view_offset += event.relative
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:                      # trackpad pinch (macOS) / touch
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:                          # trackpad two-finger scroll
		_view_offset -= event.delta * 22.0
		queue_redraw()
		accept_event()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, _zoom_floor, _ZOOM_MAX)
	if not is_finite(new_zoom):
		return
	if is_equal_approx(new_zoom, _view_zoom):
		return
	var f := new_zoom / _view_zoom
	_view_offset = screen_pos - (screen_pos - _view_offset) * f
	_view_zoom = new_zoom
	queue_redraw()


## Depth-1 focus around `iid`: inputs on the left, the selection centred, outputs (buildings
## AND ports) on the right. Positions are built around the selection's CURRENT position so the
## arrangement gathers in around it rather than teleporting the camera somewhere else.
func focus_on(iid: String) -> void:
	if iid == "" or not _pos_by_iid.has(iid):
		return
	if _focus_iid == iid and _focus_target > 0.0:
		return
	_focus_iid = iid
	_build_focus_layout()
	_focus_target = 1.0
	_focus_t = maxf(_focus_t, 0.51)         # so _layout_bbox reports the CHART before fitting
	_zoom_floor = _ZOOM_MIN
	_reset_view()                           # frame the mini-chart, not the empire
	_last_zoom = -1.0                       # force the position pass to run while tweening
	queue_redraw()


func clear_focus() -> void:
	if _focus_target <= 0.0:
		return
	_focus_target = 0.0
	_focus_t = minf(_focus_t, 0.49)         # bbox reverts to the whole empire for the refit
	_zoom_floor = _compute_zoom_floor()
	_reset_view()
	_last_zoom = -1.0
	queue_redraw()


func _build_focus_layout() -> void:
	_fpos.clear()
	_focus_members.clear()
	var sel := _focus_iid
	var ins: Array = []
	var outs: Array = []
	for e in _edges:
		if str(e["to"]) == sel and not ins.has(str(e["from"])):
			ins.append(str(e["from"]))
		elif str(e["from"]) == sel and not outs.has(str(e["to"])):
			outs.append(str(e["to"]))
	for e in _market_edges:                 # a buy port feeding this building IS an input
		if str(e["to"]) == sel and not ins.has(str(e["from"])):
			ins.append(str(e["from"]))
	for e in _sell_edges:                   # ...and an export port IS an output
		if str(e["from"]) == sel and not outs.has(str(e["to"])):
			outs.append(str(e["to"]))
	var origin: Vector2 = _pos_by_iid[sel]
	_focus_members[sel] = true
	_fpos[sel] = origin
	for col in [{"ids": ins, "dx": -_FOCUS_COL}, {"ids": outs, "dx": _FOCUS_COL}]:
		var ids: Array = col["ids"]
		for i in range(ids.size()):
			var id2: String = ids[i]
			if not _pos_by_iid.has(id2):
				continue
			_focus_members[id2] = true
			_fpos[id2] = origin + Vector2(float(col["dx"]),
					(float(i) - (ids.size() - 1) * 0.5) * _FOCUS_ROW)


## Is this edge part of the focus chart? Only edges that TOUCH the selection survive — a link
## between two of its neighbours is depth-1 geometry but not depth-1 meaning.
func _focus_keeps(e: Dictionary) -> bool:
	return _focus_iid != "" and (str(e.get("from", "")) == _focus_iid
			or str(e.get("to", "")) == _focus_iid)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
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
	if _focus_t != _focus_target:
		_focus_t = move_toward(_focus_t, _focus_target, delta / _FOCUS_SECS)
		if _focus_target <= 0.0 and _focus_t <= 0.0:
			_focus_iid = ""
			_fpos.clear()
			_focus_members.clear()
		_last_zoom = -1.0                   # positions are moving; do not take the skip
		queue_redraw()
	# Positions depend only on (zoom, offset, size, graph): skip the O(n²)
	# separation pass and the full-graph redraw when none of them changed.
	elif _view_zoom == _last_zoom and _view_offset == _last_offset and size == _last_size:
		return
	_last_zoom = _view_zoom
	_last_offset = _view_offset
	_last_size = size
	_reposition_panels()
	queue_redraw()                                    # lines follow the separated panel positions


# --- drawing -----------------------------------------------------------------------------------

func _draw() -> void:
	if _nodes.is_empty() and _ports.is_empty():
		return
	var font := get_theme_default_font()
	var sc := _detail()
	# Focus fades everything that is not part of the mini-chart. `_edge_a` multiplies the alpha
	# of any edge the focus does not keep, so the web recedes on the same curve the panels do.
	var off_a := 1.0 - _focus_t

	# Market-input lines (dashed amber) dropped from each top buy port to the buildings it
	# feeds, beneath everything else. Always dashed: like the graph's other edges this is
	# inferred capability — the sim keeps no per-building market-buy record to promote them.
	for e in _market_edges:
		if not (_box_by_iid.has(str(e["to"])) and _box_by_iid.has(str(e["from"]))):
			continue
		var mpath := _route_market(_box_by_iid[str(e["from"])], _box_by_iid[str(e["to"])],
			int(e.get("slot", 0)), int(e.get("slot_n", 1)), sc)
		var ma := 0.85 * (1.0 if _focus_keeps(e) else off_a)
		if ma > 0.01:
			_draw_dashed_polyline(mpath, Color(_EDGE, ma), _EDGE_WIDTH * sc, sc)

	# Sell-to-market lines (thick gold) routed down to the port row, beneath everything else.
	var ports_top := INF
	for p in _ports:
		ports_top = minf(ports_top, _world_to_screen(p["pos"] as Vector2).y - (p["half"] as Vector2).y * sc)
	for e in _sell_edges:
		if not (_box_by_iid.has(e["from"]) and _box_by_iid.has(e["to"])):
			continue
		var path := _route_sell(_box_by_iid[e["from"]], _box_by_iid[e["to"]],
			int(e.get("bus", 0)), int(e.get("bus_n", 1)),
			int(e.get("slot", 0)), int(e.get("slot_n", 1)), ports_top, sc)
		# With the badge on, sell lines are drawn ONLY for the focused building: the badge
		# carries "this ships to market, and to which port" at rest, and the line answers
		# "which one" on demand. That is what takes 22 of the view's 30 edges out of the
		# resting picture.
		var sa := 1.0 if _focus_keeps(e) else (0.0 if MatchState.show_port_badge else off_a)
		if sa <= 0.01:
			continue
		if bool(e.get("actual", true)):
			draw_polyline(path, Color(_SELL, sa), _SELL_WIDTH * sc, true)
		else:
			# Standing default, nothing actually shipping yet: dashed — "this is
			# where sales WOULD leave" (goods are pooling in the tile stockpile).
			_draw_dashed_polyline(path, Color(_SELL, 0.8 * sa), _SELL_WIDTH * sc, sc)

	# Input lines (thin amber) routed left-to-right between columns.
	for e in _edges:
		if not (_box_by_iid.has(e["from"]) and _box_by_iid.has(e["to"])):
			continue
		var ea := 1.0 if _focus_keeps(e) else off_a
		if ea <= 0.01:
			continue
		var path := _route_input(_box_by_iid[e["from"]], _box_by_iid[e["to"]], int(e.get("lane", 0)), int(e.get("lane_n", 1)), sc)
		draw_polyline(path, Color(_EDGE, ea), _EDGE_WIDTH * sc, true)

	# Building nodes are real Control panels (children, drawn on top); ports stay as drawn hexagons.
	for p in _ports:
		if _focus_t <= 0.0 or _focus_members.has(str(p["iid"])):
			_draw_port(p, font, sc)
	for bp in _buy_ports:
		if _focus_t <= 0.0 or _focus_members.has(str(bp["iid"])):
			_draw_port(bp, font, sc)


## Orthogonal route producer-right -> vertical channel -> consumer-left. The channel x is the edge's
## lane within the gap so parallel edges don't overlap; falls back to routing past the right side when
## the consumer is not cleanly to the right.
## Screen-space OPAQUE sprite boxes for every panel except the two an edge belongs to. Lines
## are allowed to cross a sprite's transparent padding (that is why the sprite sits behind
## them) but never the building art, so this is what the router has to miss.
func _sprite_obstacles(skip_a: String, skip_b: String, sc: float) -> Array:
	var out: Array = []
	for n in _nodes:
		var iid: String = str(n["iid"])
		if iid == skip_a or iid == skip_b or not _screen_by_iid.has(iid):
			continue
		var r: Rect2 = n.get("sprite_rect", Rect2())
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		var c: Vector2 = _screen_by_iid[iid]
		out.append(Rect2(c + r.position * sc, r.size * sc))
	return out


## Does any segment of `pts` cut through any of `rects`? Rect2.intersects on the segment's own
## bounding box would reject far too much (a long diagonal's bbox covers everything between its
## ends), so this clips each segment against each rect properly.
func _blocked(pts: PackedVector2Array, rects: Array) -> bool:
	for i in range(pts.size() - 1):
		for r in rects:
			if _seg_hits_rect(pts[i], pts[i + 1], r as Rect2):
				return true
	return false


func _seg_hits_rect(p0: Vector2, p1: Vector2, r: Rect2) -> bool:
	if r.has_point(p0) or r.has_point(p1):
		return true
	# Liang-Barsky slab clip.
	var d := p1 - p0
	var t0 := 0.0
	var t1 := 1.0
	for k in range(2):
		var dk: float = d.x if k == 0 else d.y
		var p: float = p0.x if k == 0 else p0.y
		var lo: float = r.position.x if k == 0 else r.position.y
		var hi: float = r.end.x if k == 0 else r.end.y
		if absf(dk) < 0.000001:
			if p < lo or p > hi:
				return false
			continue
		var ta := (lo - p) / dk
		var tb := (hi - p) / dk
		if ta > tb:
			var sw := ta
			ta = tb
			tb = sw
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


func _route_input(a: Dictionary, b: Dictionary, lane: int, lane_n: int, sc: float) -> PackedVector2Array:
	var ca := _plate_screen_of(str(a["iid"]), a)
	var cb := _plate_screen_of(str(b["iid"]), b)
	# PLATE extents, not layout extents — see `plate_half` in empire_graph.gd.
	var ha: Vector2 = (a.get("plate_half", a["half"]) as Vector2) * sc
	var hb: Vector2 = (b.get("plate_half", b["half"]) as Vector2) * sc
	var start := Vector2(ca.x + ha.x, ca.y)
	var end := Vector2(cb.x - hb.x, cb.y)
	var stub := (18.0 + float(lane) * 7.0) * sc
	var obs := _sprite_obstacles(str(a["iid"]), str(b["iid"]), sc)
	var best := _iso_route_h(start, end, stub, lane, lane_n, sc)
	if not _blocked(best, obs):
		return best
	# Same shape, different place to put the diagonal. Sliding WHERE it turns is enough to
	# clear a neighbour's sprite in almost every case, and it keeps the 45-degree look; the
	# orthogonal detour is only worth taking when nothing else fits.
	for k in range(1, 7):
		var alt := _iso_route_h(start, end, stub, k, 7, sc)
		if not _blocked(alt, obs):
			return alt
	return best


## ORTHOGONAL route, horizontal-dominant: out of the source plate, along a vertical channel,
## into the target plate. Corners are chamfered (a short 45deg cut) rather than run as long
## diagonals — a 45deg trial read as busier than the square grid it replaced, and the square
## grid is also what makes the lane separation legible.
func _iso_route_h(start: Vector2, end: Vector2, stub: float, lane: int, lane_n: int,
		sc: float) -> PackedVector2Array:
	if absf(end.y - start.y) < 1.0:
		return PackedVector2Array([start, end])
	var mid_x: float
	if end.x > start.x + 4.0:
		mid_x = lerpf(start.x, end.x, float(lane + 1) / float(lane_n + 1))
	else:
		mid_x = maxf(start.x, end.x) + (50.0 + float(lane) * 26.0) * sc
	return _chamfer(PackedVector2Array([
		start, Vector2(mid_x, start.y), Vector2(mid_x, end.y), end]), _CHAMFER * sc)


## Orthogonal route, vertical-dominant: down out of the plate, across a horizontal lane, down
## into the target. `bias` (0..1) staggers the lane so neighbours do not share one.
func _iso_route_v(start: Vector2, end: Vector2, stub: float, bias: float,
		sc: float) -> PackedVector2Array:
	if absf(end.x - start.x) < 1.0:
		return PackedVector2Array([start, end])
	var span := end.y - start.y
	var lane_y := start.y + clampf(bias, 0.05, 0.95) * span
	if absf(span) < stub * 3.0:
		lane_y = start.y + span * 0.5
	return _chamfer(PackedVector2Array([
		start, Vector2(start.x, lane_y), Vector2(end.x, lane_y), end]), _CHAMFER * sc)


## Orthogonal route building-bottom -> horizontal bus lane -> one of the port's <=5 top-edge entry
## slots (spaced 2-1-2). Lines that share a slot (when a port has >5 feeders) converge on the same
## entry point, so they visually merge into the port.
func _route_sell(a: Dictionary, b: Dictionary, bus: int, bus_n: int, slot: int, slot_n: int, ports_top: float, sc: float) -> PackedVector2Array:
	var ca := _plate_screen_of(str(a["iid"]), a)
	var cb := _plate_screen_of(str(b["iid"]), b)
	# PLATE extents, not layout extents — see `plate_half` in empire_graph.gd.
	var ha: Vector2 = (a.get("plate_half", a["half"]) as Vector2) * sc
	var hb: Vector2 = (b.get("plate_half", b["half"]) as Vector2) * sc
	var start := Vector2(ca.x, ca.y + ha.y)
	# Entry point along the port hex's flat top edge (which spans cb.x +/- hb.x*0.5).
	var frac := float(slot + 1) / float(slot_n + 1)
	var entry_x := cb.x - hb.x * 0.5 + frac * hb.x
	var entry := Vector2(entry_x, cb.y - hb.y)
	# The old horizontal bus lane is gone: with a 45-degree run the stagger comes from WHERE the
	# diagonal starts, which keeps neighbours apart without a shared horizontal rail that had to
	# be squeezed above the port row.
	var bias := float(bus + 1) / float(maxi(bus_n, 1) + 1)
	var obs := _sprite_obstacles(str(a["iid"]), str(b["iid"]), sc)
	var best := _iso_route_v(start, entry, 26.0 * sc, bias, sc)
	if not _blocked(best, obs):
		return best
	for k in range(1, 8):
		var alt := _iso_route_v(start, entry, 26.0 * sc, float(k) / 8.0, sc)
		if not _blocked(alt, obs):
			return alt
	return best


## Orthogonal route market-hub-bottom -> horizontal bus lane -> building top. The exact mirror
## of _route_sell: exits spread across the hub's flat BOTTOM edge, one shared bus lane hangs
## below the hub, and each line drops vertically into its building's top edge.
func _route_market(hub: Dictionary, b: Dictionary, slot: int, slot_n: int, sc: float) -> PackedVector2Array:
	var ch := _screen_of(str(hub["iid"]), hub)
	var cb := _plate_screen_of(str(b["iid"]), b)
	var hh: Vector2 = (hub.get("plate_half", hub["half"]) as Vector2) * sc
	var hb: Vector2 = (b.get("plate_half", b["half"]) as Vector2) * sc
	var frac := float(slot + 1) / float(slot_n + 1)
	var exit_x := ch.x - hh.x * 0.5 + frac * hh.x
	var exit := Vector2(exit_x, ch.y + hh.y)
	var end := Vector2(cb.x, cb.y - hb.y)
	return _iso_route_v(exit, end, 26.0 * sc, float(slot + 1) / float(maxi(slot_n, 1) + 1), sc)


## Draw a polyline as dashes (12px on / 9px off), continuous across corners.
func _draw_dashed_polyline(pts: PackedVector2Array, color: Color, width: float, sc: float = 1.0) -> void:
	# Cadence scale is floored: at detail 0.1 a true-scale dash is under 1.5px, which reads as
	# a ragged solid AND multiplies the draw commands per edge by ~8x. Widths keep tracking.
	var csc := maxf(sc, 0.35)
	var dash := 12.0 * csc
	var gap := 9.0 * csc
	var carry := 0.0   # distance into the current dash/gap cycle, carried across segments
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.001:
			continue
		var dir := (b - a) / seg_len
		var t := 0.0
		# Epsilon-terminated, and this is load-bearing, not tidiness: the loop advances by
		# min(dash_remaining, seg_len - t), and once (seg_len - t) falls under the float eps
		# at t's magnitude, `t += run` stops changing t while `t < seg_len` stays true — an
		# infinite loop that queues a draw command per iteration and eats ALL system memory
		# inside one frame. Whether any segment hits that alignment depends on the dash
		# cadence; 12/9 happened never to, scaling the cadence with zoom found one
		# immediately. The 0.01px epsilon is invisible and closes the whole class.
		while t < seg_len - 0.01:
			var cycle_pos := fmod(carry + t, dash + gap)
			if cycle_pos < dash:
				var run := minf(dash - cycle_pos, seg_len - t)
				draw_line(a + dir * t, a + dir * (t + run), color, width, true)
				t += maxf(run, 0.01)
			else:
				t += maxf(minf((dash + gap) - cycle_pos, seg_len - t), 0.01)
		carry = fmod(carry + seg_len, dash + gap)


## Replace each interior corner of an orthogonal polyline with a 45deg chamfer.
func _chamfer(pts: PackedVector2Array, c: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var p := pts[i]
		var din := p - pts[i - 1]
		var dout := pts[i + 1] - p
		var lin := din.length()
		var lout := dout.length()
		if lin < 0.5 or lout < 0.5:
			continue
		var cc := minf(c, minf(lin * 0.49, lout * 0.49))
		out.append(p - din.normalized() * cc)
		out.append(p + dout.normalized() * cc)
	out.append(pts[pts.size() - 1])
	return out


## A port as a gold metallic hexagon with the port icon embossed in navy, name beneath.
func _draw_port(n: Dictionary, font: Font, sc: float) -> void:
	var center: Vector2 = _world_to_screen(n["pos"] as Vector2)
	var half: Vector2 = (n["half"] as Vector2) * sc
	var rect := Rect2(center - half, half * 2.0)
	if not get_rect().grow(240.0).intersects(rect):
		return
	var hex := rounded_polygon(hex_points(center, half), minf(half.x, half.y) * 0.22, 4)
	# Lit gold gradient fill: top-left bright -> bottom-right dark (same metal lighting as the plates).
	draw_polygon(hex, grad_colors(hex, Color(1.0, 0.93, 0.63), Color(0.46, 0.35, 0.13)))
	# Raised bezel: each edge lit (white) if it faces top-left, shadowed (black) if bottom-right.
	var diag := center.x + center.y
	var hn := hex.size()
	for i in range(hn):
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % hn]
		var mid := (a + b) * 0.5
		draw_line(a, b, Color(1, 1, 1, 0.38) if (mid.x + mid.y <= diag) else Color(0, 0, 0, 0.32), 2.5 * sc, true)
	var rim := PackedVector2Array(hex)
	rim.append(hex[0])
	draw_polyline(rim, Color(1.0, 0.95, 0.72, 0.85), 1.5 * sc, true)

	var icon = n.get("icon")
	if icon != null:
		var isz := minf(half.x, half.y) * 1.5     # larger icon embossed inside the hex
		draw_texture_rect(icon, Rect2(center - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(0.02, 0.06, 0.11, 0.95))

	draw_string(font, Vector2(rect.position.x - 20.0 * sc, rect.end.y + 16.0 * sc), str(n.get("name", "")),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 40.0 * sc, maxi(6, int(round(13.0 * sc))), _GOLD)


## Flat-top hexagon (pointed left/right) filling the node's box.
static func hex_points(center: Vector2, half: Vector2) -> PackedVector2Array:
	var bx := half.x * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x + bx, -half.y),
		center + Vector2(half.x - bx, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(half.x - bx, half.y),
		center + Vector2(-half.x + bx, half.y),
		center + Vector2(-half.x, 0.0),
	])


## Round a polygon's corners with a small quadratic-bezier arc per vertex (research-panel style).
static func rounded_polygon(verts: PackedVector2Array, radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := verts.size()
	for i in range(n):
		var v: Vector2 = verts[i]
		var a: Vector2 = verts[(i - 1 + n) % n]
		var b: Vector2 = verts[(i + 1) % n]
		var p1 := v + (a - v).normalized() * minf(radius, v.distance_to(a) * 0.45)
		var p2 := v + (b - v).normalized() * minf(radius, v.distance_to(b) * 0.45)
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			out.append(p1.lerp(v, t).lerp(v.lerp(p2, t), t))
	return out


## Per-vertex colours for a top-left (light) -> bottom-right (dark) gradient.
static func grad_colors(pts: PackedVector2Array, light: Color, dark: Color) -> PackedColorArray:
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	var denom := maxf(bounds.size.x + bounds.size.y, 1.0)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf(((p.x - bounds.position.x) + (p.y - bounds.position.y)) / denom, 0.0, 1.0)
		cols.append(light.lerp(dark, t))
	return cols
