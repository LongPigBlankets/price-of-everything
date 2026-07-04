extends Control
## Empire view — graph drawing layer (Milestone 3+: pan/zoom, orthogonal routing, sell lines).
##
## A manual camera (`_view_offset` + `_view_zoom`) pans/zooms the graph: node POSITIONS and connector
## LINES scale and translate with zoom, but each box is drawn at a CONSTANT pixel size (zoom-invariant).
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

const _ZOOM_MIN := 0.2
const _ZOOM_MAX := 2.5
const _ZOOM_STEP := 1.12
const _PAN_SPEED := 900.0
const _MIN_GAP := 20.0                                      # hard minimum screen gap between panels, at any zoom
const _SEP_ITERS := 28                                      # screen-space separation passes per frame

const NodePanelScript := preload("res://scripts/empire_node_panel.gd")

var _nodes: Array = []
var _ports: Array = []
var _edges: Array = []
var _sell_edges: Array = []
var _pos_by_iid: Dictionary = {}
var _box_by_iid: Dictionary = {}
var _panels: Array = []                                     # [{ctrl, iid, pos}] real node Controls
var _screen_by_iid: Dictionary = {}                         # iid -> current screen pos (panels separated, ports projected)

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
var _last_zoom := -1.0
var _last_offset := Vector2.INF
var _last_size := Vector2.ZERO


func _ready() -> void:
	set_process(true)
	resized.connect(func() -> void: _mark_view_dirty())
	# A drag interrupted by the view closing never receives its mouse-up; without
	# this reset the next open pans on bare mouse motion.
	visibility_changed.connect(func() -> void: _dragging = false)


func _mark_view_dirty() -> void:
	_last_zoom = -1.0


func set_graph(nodes: Array, edges: Array, ports: Array, sell_edges: Array = []) -> void:
	_nodes = nodes
	_edges = edges
	_ports = ports
	_sell_edges = sell_edges
	_pos_by_iid.clear()
	_box_by_iid.clear()
	for arr in [_nodes, _ports]:
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


## The zoom below which the fixed-pixel-size cards can no longer sit at their
## world positions: the median nearest-neighbour spacing (screen px at that
## zoom) drops under the widest card + gap, and every card ends up at its
## separation-forced position instead. Zoom-out is capped there.
func _compute_zoom_floor() -> float:
	if _nodes.size() < 2:
		return _ZOOM_MIN
	var dists: Array[float] = []
	for i in range(_nodes.size()):
		var best := INF
		var pi: Vector2 = _nodes[i]["pos"] as Vector2
		for j in range(_nodes.size()):
			if i != j:
				best = minf(best, pi.distance_to(_nodes[j]["pos"] as Vector2))
		if best < INF:
			dists.append(best)
	dists.sort()
	var median: float = dists[dists.size() / 2]
	if median <= 1.0:
		return _ZOOM_MIN
	var need := 0.0
	for n in _nodes:
		need = maxf(need, (n["half"] as Vector2).x * 2.0)
	need += _MIN_GAP
	return clampf(need / median, _ZOOM_MIN, 1.0)


## Build one real Control panel per building node (ports stay as drawn hexagons). Rebuilt on open.
func _rebuild_panels() -> void:
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

	var ids: Array = []
	var pos: Dictionary = {}
	var half: Dictionary = {}
	for pan in _panels:
		var iid: String = pan["iid"]
		ids.append(iid)
		pos[iid] = _world_to_screen(pan["pos"] as Vector2)
		half[iid] = (pan["ctrl"] as Control).size * 0.5 + Vector2(_MIN_GAP * 0.5, _MIN_GAP * 0.5)

	for _it in range(_SEP_ITERS):
		var moved := false
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
		(pan["ctrl"] as Control).position = (pos[iid2] as Vector2) - (pan["ctrl"] as Control).size * 0.5


## Screen position of a node (separated for panels, projected for ports), with a projection fallback.
func _screen_of(iid: String, node: Dictionary) -> Vector2:
	if _screen_by_iid.has(iid):
		return _screen_by_iid[iid]
	return _world_to_screen(node["pos"] as Vector2)


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
	for key in buckets:
		var arr: Array = buckets[key]
		arr.sort_custom(func(x, y): return (_pos_by_iid[x["to"]] as Vector2).y < (_pos_by_iid[y["to"]] as Vector2).y)
		for i in range(arr.size()):
			arr[i]["lane"] = i
			arr[i]["lane_n"] = arr.size()
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
		arr.sort_custom(func(x, y): return (_pos_by_iid[x["from"]] as Vector2).x < (_pos_by_iid[y["from"]] as Vector2).x)
		var n := mini(arr.size(), _PORT_MAX_SLOTS)
		for i in range(arr.size()):
			arr[i]["slot"] = (i * n) / arr.size() if arr.size() > 0 else 0
			arr[i]["slot_n"] = n


func _reset_view() -> void:
	var bb := _layout_bbox()
	var view := get_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1920.0, 1080.0)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		_view_zoom = 1.0
		_view_offset = view * 0.5
		return
	var pad := 140.0
	var fit := minf((view.x - pad) / bb.size.x, (view.y - pad) / bb.size.y)
	_view_zoom = clampf(fit, _zoom_floor, 1.0)
	_view_offset = view * 0.5 - bb.get_center() * _view_zoom


func _layout_bbox() -> Rect2:
	var bb := Rect2()
	var first := true
	for arr in [_nodes, _ports]:
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
	if is_equal_approx(new_zoom, _view_zoom):
		return
	var f := new_zoom / _view_zoom
	_view_offset = screen_pos - (screen_pos - _view_offset) * f
	_view_zoom = new_zoom
	queue_redraw()


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
	# Positions depend only on (zoom, offset, size, graph): skip the O(n²)
	# separation pass and the full-graph redraw when none of them changed.
	if _view_zoom == _last_zoom and _view_offset == _last_offset and size == _last_size:
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

	# Sell-to-market lines (thick gold) routed down to the port row, beneath everything else.
	var ports_top := INF
	for p in _ports:
		ports_top = minf(ports_top, _world_to_screen(p["pos"] as Vector2).y - (p["half"] as Vector2).y)
	for e in _sell_edges:
		if not (_box_by_iid.has(e["from"]) and _box_by_iid.has(e["to"])):
			continue
		var path := _route_sell(_box_by_iid[e["from"]], _box_by_iid[e["to"]],
			int(e.get("bus", 0)), int(e.get("bus_n", 1)),
			int(e.get("slot", 0)), int(e.get("slot_n", 1)), ports_top)
		draw_polyline(_chamfer(path, _CHAMFER), _SELL, _SELL_WIDTH, true)

	# Input lines (thin amber) routed left-to-right between columns.
	for e in _edges:
		if not (_box_by_iid.has(e["from"]) and _box_by_iid.has(e["to"])):
			continue
		var path := _route_input(_box_by_iid[e["from"]], _box_by_iid[e["to"]], int(e.get("lane", 0)), int(e.get("lane_n", 1)))
		draw_polyline(_chamfer(path, _CHAMFER), _EDGE, _EDGE_WIDTH, true)

	# Building nodes are real Control panels (children, drawn on top); ports stay as drawn hexagons.
	for p in _ports:
		_draw_port(p, font)


## Orthogonal route producer-right -> vertical channel -> consumer-left. The channel x is the edge's
## lane within the gap so parallel edges don't overlap; falls back to routing past the right side when
## the consumer is not cleanly to the right.
func _route_input(a: Dictionary, b: Dictionary, lane: int, lane_n: int) -> PackedVector2Array:
	var ca := _screen_of(str(a["iid"]), a)
	var cb := _screen_of(str(b["iid"]), b)
	var ha: Vector2 = a["half"] as Vector2
	var hb: Vector2 = b["half"] as Vector2
	var start := Vector2(ca.x + ha.x, ca.y)
	var end := Vector2(cb.x - hb.x, cb.y)
	var frac := float(lane + 1) / float(lane_n + 1)
	var mid_x: float
	if end.x > start.x + 4.0:
		mid_x = lerpf(start.x, end.x, frac)
	else:
		mid_x = maxf(start.x, end.x) + 50.0 + float(lane) * 26.0
	return PackedVector2Array([start, Vector2(mid_x, start.y), Vector2(mid_x, end.y), end])


## Orthogonal route building-bottom -> horizontal bus lane -> one of the port's <=5 top-edge entry
## slots (spaced 2-1-2). Lines that share a slot (when a port has >5 feeders) converge on the same
## entry point, so they visually merge into the port.
func _route_sell(a: Dictionary, b: Dictionary, bus: int, bus_n: int, slot: int, slot_n: int, ports_top: float) -> PackedVector2Array:
	var ca := _screen_of(str(a["iid"]), a)
	var cb := _screen_of(str(b["iid"]), b)
	var ha: Vector2 = a["half"] as Vector2
	var hb: Vector2 = b["half"] as Vector2
	var start := Vector2(ca.x, ca.y + ha.y)
	# Entry point along the port hex's flat top edge (which spans cb.x +/- hb.x*0.5).
	var frac := float(slot + 1) / float(slot_n + 1)
	var entry_x := cb.x - hb.x * 0.5 + frac * hb.x
	var entry := Vector2(entry_x, cb.y - hb.y)
	var bus_y := ports_top - 40.0 - float(bus_n - 1 - bus) * 26.0
	bus_y = maxf(bus_y, start.y + 28.0)
	return PackedVector2Array([start, Vector2(start.x, bus_y), Vector2(entry_x, bus_y), entry])


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
func _draw_port(n: Dictionary, font: Font) -> void:
	var center: Vector2 = _world_to_screen(n["pos"] as Vector2)
	var half: Vector2 = n["half"] as Vector2
	var rect := Rect2(center - half, half * 2.0)
	if not get_rect().grow(240.0).intersects(rect):
		return
	var hex := _rounded_polygon(_hex_points(center, half), minf(half.x, half.y) * 0.22, 4)
	# Lit gold gradient fill: top-left bright -> bottom-right dark (same metal lighting as the plates).
	draw_polygon(hex, _grad_colors(hex, Color(1.0, 0.93, 0.63), Color(0.46, 0.35, 0.13)))
	# Raised bezel: each edge lit (white) if it faces top-left, shadowed (black) if bottom-right.
	var diag := center.x + center.y
	var hn := hex.size()
	for i in range(hn):
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % hn]
		var mid := (a + b) * 0.5
		draw_line(a, b, Color(1, 1, 1, 0.38) if (mid.x + mid.y <= diag) else Color(0, 0, 0, 0.32), 2.5, true)
	var rim := PackedVector2Array(hex)
	rim.append(hex[0])
	draw_polyline(rim, Color(1.0, 0.95, 0.72, 0.85), 1.5, true)

	var icon = n.get("icon")
	if icon != null:
		var isz := minf(half.x, half.y) * 1.5     # larger icon embossed inside the hex
		draw_texture_rect(icon, Rect2(center - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(0.02, 0.06, 0.11, 0.95))

	draw_string(font, Vector2(rect.position.x - 20.0, rect.end.y + 16.0), str(n.get("name", "")),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 40.0, 13, _GOLD)


## Flat-top hexagon (pointed left/right) filling the node's box.
func _hex_points(center: Vector2, half: Vector2) -> PackedVector2Array:
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
func _rounded_polygon(verts: PackedVector2Array, radius: float, steps: int) -> PackedVector2Array:
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
