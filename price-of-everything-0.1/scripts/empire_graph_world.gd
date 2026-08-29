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

# --- Carried from the coal-prohibition empire pass (owner, 2026-08-13..16) ---
const _GLOW_HEIGHT_FRAC := 0.15             # selection halo reach as a fraction of sprite height
const _GLOW_ALPHA := 0.55                   # peak alpha at the halo's centre
const _PORT_BADGE_FRAC := 0.17              # corner hex size as a fraction of the port sprite box
const _PORT_MIN_SEP_SPRITES := 3.0          # lane a charted port reserves, in sprite-widths
const _PORT_SPRITE_MULT := 2.0              # port sprite box = NodePanelScript.SPRITE_PX * this
const _SHIPMENT_LOOKAHEAD := 5              # "expected in N turns" window
const _COST_OK := 2.0                       # £/turn at or under which a line is cheap
const _COST_WARN := 8.0                     # ...and over which it is expensive
const _CREAM_TEXT := Color(0.976, 0.945, 0.867, 1.0)
const BuildingSprites := preload("res://scripts/building_sprites.gd")

const NodePanelScript := preload("res://scripts/empire_node_panel.gd")
const LaneOrder := preload("res://scripts/lane_order.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")

var _nodes: Array = []
var _ports: Array = []
var _edges: Array = []
var _sell_edges: Array = []
var _pos_by_iid: Dictionary = {}
var _box_by_iid: Dictionary = {}
var _panels: Array = []                                     # [{ctrl, iid, pos}] real node Controls
var _screen_by_iid: Dictionary = {}                         # iid -> current screen pos (panels separated, ports projected)

var _edge_icon_rects: Array = []            # [{rect, edge, kind}] chip hit-boxes, rebuilt per draw
var _hover_edge: Dictionary = {}            # the chip under the cursor (empty = none)
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

# --- CONSTRUCTION-SITE MINI-CHART --------------------------------------------------------
# A site has no inputs and no outputs, so the depth-1 chart above would show a lone plate. What
# it does have is a DELIVERY, and that is what the chart draws: the port its materials come
# through on the left, the site on the right, and the kit itself somewhere along the run —
# one lane per material, each parked at its own arrival time. All of it is read from the live
# sim on every frame (`_site_lanes`), so a turn landing moves the goods with no rebuild.
const _SITE_RUN := 1560.0                   # port -> site distance in the chart (layout px)
const _LANE_ROW := 122.0                    # vertical pitch between material lanes
const _LANE_CHIP := 74.0                    # material icon box
const _ALERT := Color(0.94, 0.24, 0.19)     # blocked-shipment red
const _WHITE := Color(1.0, 1.0, 1.0)
const _CREAM := Color(0.995234, 0.930806, 0.763265)   # DS ACCENT / recipe-card OFF_WHITE
const _PILL_NAVY := Color(0.0, 0.119856, 0.243095)    # recipe-card BADGE_NAVY
## Every edge (input, market, sell — dashed or not) carries a good-icon chip partway along its
## routed path, reusing _LANE_CHIP's own cream-chip look (owner, 27 Aug). 0.4 = 40% of the way
## from source to destination, by arc length along the actual (elbowed) route.
const _EDGE_CHIP_T := 0.4
var _focus_site: Dictionary = {}            # {} unless the selection is a construction site
var _site_lane_n := 0                       # lane count, so _layout_bbox can frame them
var _site_lane_pitch := _LANE_ROW           # widens when a lane carries a blocked message
var _pulse := 0.0                           # 0..1 sawtooth driving the blocked-shipment flash
var _chip_style: StyleBoxFlat = null        # reused per draw (draw_rect has no corner radius)
var _pill_style: StyleBoxFlat = null

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
	_focus_site.clear()
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
	for arr in [_ports, _buy_ports]:
		for p in arr:
			_screen_by_iid[str(p["iid"])] = _world_to_screen(
					_focus_pos(str(p["iid"]), p["pos"] as Vector2))

	var sc := _detail()
	var ids: Array = []
	var pos: Dictionary = {}
	var half: Dictionary = {}
	for pan in _panels:
		var iid: String = pan["iid"]
		ids.append(iid)
		pos[iid] = _world_to_screen(_focus_pos(iid, pan["pos"] as Vector2))
		# Footprint AND gap scale with the card, or the separation pass fights the zoom: an
		# unscaled gap dominates once cards are small and re-creates the jostling.
		half[iid] = (pan["ctrl"] as Control).size * (0.5 * sc) + Vector2(_MIN_GAP * sc * 0.5, _MIN_GAP * sc * 0.5)

	# Port hexes are OBSTACLES, not participants: they hold the positions the layout gave them
	# (their x carries the sector meaning) and panels give way. Without this the pass separated
	# panels from each other only, so a sprite — which is 400px tall growing upward — happily
	# sat on top of the buy-port row above it.
	var port_rects: Array = []
	var port_sprite_half := NodePanelScript.SPRITE_PX * _PORT_SPRITE_MULT * 0.5 * sc
	# Wider than the sprite on purpose: a charted port has to READ as its own place, so it
	# reserves _PORT_MIN_SEP_SPRITES regular sprite-widths of lane and panels are pushed out.
	var port_sep_half := NodePanelScript.SPRITE_PX * _PORT_MIN_SEP_SPRITES * 0.5 * sc
	for arr2 in [_ports, _buy_ports]:
		for p2 in arr2:
			var pid2 := str(p2["iid"])
			var in_chart: bool = _focus_target > 0.0 and _focus_members.has(pid2)
			# Buy ports are NOT obstacles at rest (the resting layout is tuned around that).
			# They become obstacles only inside a chart, where they stop being a small hex
			# and start being a 2x building sprite.
			if arr2 == _buy_ports and not in_chart:
				continue
			var ph: Vector2 = (p2["half"] as Vector2) * sc
			# A port in an open chart is drawn as that big sprite, not as its hex, so the
			# footprint the panels give way to has to be the sprite's or they sit on top of it.
			if in_chart:
				ph = Vector2(maxf(ph.x, port_sep_half), maxf(ph.y, port_sprite_half))
			port_rects.append({
				"c": _world_to_screen(_focus_pos(pid2, p2["pos"] as Vector2)),
				"h": ph + Vector2(_MIN_GAP * sc, _MIN_GAP * sc),
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
		# The focused building's own sell line (with its good-icon chip) now says "ships to
		# market, and where" directly — its port badge would just repeat that.
		ctrl.call("set_badge_hidden", iid2 == _focus_iid)


## A node's LAYOUT position, eased toward its focus-chart position while a mini-chart is open.
## PORTS go through this too, and that is the point: they are chart members (the export port of
## the selection, and the port a construction site's materials come through), but they used to
## keep drawing in their resting row while the panels gathered around the selection — so every
## focus line ran off to the bottom of the composition instead of into the chart.
func _focus_pos(iid: String, base: Vector2) -> Vector2:
	if _focus_t > 0.0 and _fpos.has(iid):
		return base.lerp(_fpos[iid] as Vector2, _focus_t)
	return base


## Screen position of a node (separated for panels, projected for ports), with a projection fallback.
func _screen_of(iid: String, node: Dictionary) -> Vector2:
	if _screen_by_iid.has(iid):
		return _screen_by_iid[iid]
	return _world_to_screen(_focus_pos(iid, node["pos"] as Vector2))


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
			# A charted port draws as a sprite twice the building box; framing on its hex
			# left the port hanging half off the side of the view. Width uses the
			# SEPARATION lane, not just the sprite — the pass pushes panels to that radius.
			if bool(nn.get("is_port", false)):
				hh = Vector2(maxf(hh.x, NodePanelScript.SPRITE_PX * _PORT_MIN_SEP_SPRITES * 0.5),
					maxf(hh.y, NodePanelScript.SPRITE_PX * _PORT_SPRITE_MULT * 0.5))
			var r2 := Rect2((_fpos[iid] as Vector2) - hh, hh * 2.0)
			if f1:
				fb = r2
				f1 = false
			else:
				fb = fb.merge(r2)
		# The material lanes fan out above and below the two chart nodes and can be taller than
		# either of them, so the fit has to know about them or a six-material build frames with
		# its top and bottom lanes off screen.
		if not _focus_site.is_empty() and _site_lane_n > 0:
			# The pitch itself widens when a lane carries a blocked message, so read it back
			# rather than assuming the resting row height — otherwise a blocked seven-material
			# build frames with its outer lanes off screen.
			var lh := float(_site_lane_n) * _site_lane_pitch * 0.5 + 220.0
			fb = fb.grow_individual(0.0, maxf(0.0, lh - fb.size.y * 0.5), 0.0,
					maxf(0.0, lh - fb.size.y * 0.5))
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
	elif event is InputEventMouseMotion:
		_update_edge_hover((event as InputEventMouseMotion).position)
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
## `instant` skips the ease-in: used when the graph is REBUILT under an open chart (a turn
## landing), where re-animating would read as the view flinching once per turn.
func focus_on(iid: String, instant: bool = false) -> void:
	if iid == "" or not _pos_by_iid.has(iid):
		return
	if _focus_iid == iid and _focus_target > 0.0 and not instant:
		return
	_focus_iid = iid
	_build_focus_layout()
	_focus_target = 1.0
	_focus_t = 1.0 if instant else maxf(_focus_t, 0.51)   # >0.5 so _layout_bbox reports the CHART
	_zoom_floor = _ZOOM_MIN
	_reset_view()                           # frame the mini-chart, not the empire
	_last_zoom = -1.0                       # force the position pass to run while tweening
	queue_redraw()


## The building the mini-chart is open on ("" when at rest) — so a graph rebuild can put it back.
func focus_iid() -> String:
	return _focus_iid if _focus_target > 0.0 else ""


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
	_focus_site.clear()
	_site_lane_n = 0
	var sel := _focus_iid
	if bool((_box_by_iid.get(sel, {}) as Dictionary).get("under_construction", false)):
		_build_site_focus_layout(_box_by_iid[sel] as Dictionary)
		return
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


## A construction site's chart is a DELIVERY, not a supply web: the port its materials come
## through, the site, and nothing else. The wide run between them is the working area — the
## material lanes are drawn into it from live sim state (`_draw_site_lanes`), so the two nodes
## are the whole of the layout.
func _build_site_focus_layout(seln: Dictionary) -> void:
	var sel := str(seln["iid"])
	var origin: Vector2 = _pos_by_iid[sel]
	_focus_members[sel] = true
	_fpos[sel] = origin
	# `port_hint` is the port the sim actually sources this project's materials through
	# (Catalog.nearest_port_tile — see empire_graph._append_construction_nodes).
	var port_iid := str(seln.get("port_hint", ""))
	if (port_iid == "" or not _pos_by_iid.has(port_iid)) and not _ports.is_empty():
		port_iid = str((_ports[0] as Dictionary)["iid"])
	if port_iid != "" and _pos_by_iid.has(port_iid):
		_focus_members[port_iid] = true
		_fpos[port_iid] = origin - Vector2(_SITE_RUN, 0.0)
	_focus_site = {"iid": sel, "port": port_iid}
	_site_lane_n = _site_lanes(sel).size()


## Is this edge part of the focus chart? Only edges that TOUCH the selection survive — a link
## between two of its neighbours is depth-1 geometry but not depth-1 meaning.
func _focus_keeps(e: Dictionary) -> bool:
	return _focus_iid != "" and (str(e.get("from", "")) == _focus_iid
			or str(e.get("to", "")) == _focus_iid)


## LIVE per-material delivery state for a focused construction site — one entry per required
## good, read straight from the sim every frame, so a turn landing moves the goods along their
## lanes with no graph rebuild.
##
## A material can be PART delivered (claim_materials takes whatever landed and leaves the rest
## outstanding; queue_buy cash-clips an order the same way), so a lane carries two quantities:
## `arrived` sits on the site and `outstanding` is still somewhere on the run.
##   at        0..1 for the OUTSTANDING quantity: 0 = still at the source, 1 = at the site
##   eta       turns until it reaches the site
##   cause     why nothing is coming, "" when it is simply in transit:
##             "infra"    — the route cannot be travelled at all. Same test queue_buy makes (a
##                          fluid needs a pipe at the port AND a pipe network to the site),
##                          which is why this one fails SILENTLY: the order is refused, not
##                          queued, and the project waits forever.
##             "capacity" — it reached the tile and cannot unload; it sits in overflow-hold.
##             "cash"     — the order costs more than the financeable headroom.
##             "" with nothing inbound = not ordered yet; reorder_market_materials will place it
##             next turn, so that is a WAIT, not a fault, and raises no alert.
func _site_lanes(iid: String) -> Array:
	var proj: Dictionary = Construction.construction_projects.get(iid, {})
	if proj.is_empty():
		return []
	var tile := str(proj.get("tile_id", ""))
	# Market projects source from the nearest port, a tile-sourced one from its own source tile.
	# Both are quoted through the same route(), so one test covers both.
	var from_tile := str((proj.get("source", {}) as Dictionary).get("from_tile_id", ""))
	if from_tile == "":
		from_tile = str(Catalog.nearest_port_tile(tile))
	var req: Dictionary = proj.get("required_materials", {})
	var missing: Dictionary = proj.get("missing_materials", {})
	var goods: Array = req.keys()
	goods.sort()                                   # stable lane order from turn to turn
	var out: Array = []
	for g in goods:
		var gid := str(g)
		var required := int(req.get(gid, 0))
		var outstanding := int(missing.get(gid, 0))
		var eta := -1
		var total := 1
		for s in MatchState.get_inbound_transport_shipments(tile, gid):
			# Only OUR freight: a neighbour importing the same good is not this build's kit.
			if str((s as Dictionary).get("construction_instance_id", "")) != iid:
				continue
			var t := int((s as Dictionary).get("turns_remaining", 0))
			if eta < 0 or t < eta:
				eta = t
				total = int((s as Dictionary).get("transport_turns", t))
		var held := 0
		for h in MatchState.get_overflow_shipments_for_tile(tile):
			if str((h as Dictionary).get("construction_instance_id", "")) == iid \
					and str((h as Dictionary).get("good_id", "")) == gid:
				held += int((h as Dictionary).get("qty", 0))
		var cause := ""
		var infra := ""
		var infra_icon: Texture2D = null
		if outstanding > 0:
			if from_tile == "" or not Catalog.tile_can_pipe_good(from_tile, gid) \
					or not TransportService.route_is_reachable(
						TransportService.route(from_tile, tile, gid)):
				cause = "infra"
				var info: Dictionary = Catalog.route_infra_for_good(gid)
				infra = str(info.get("name", ""))
				var modes: Array = info.get("modes", [])
				if not modes.is_empty():
					# Routing calls it "rail"; the building that builds it is "rails".
					var internal := "rails" if str(modes[0]) == "rail" else str(modes[0])
					infra_icon = BuildingIcon.clean_texture(
							str(Catalog.get_building_by_internal_name(internal).get("id", "")), internal)
			elif held > 0 or (eta < 0 and Stockpile.get_free_capacity(tile) <= 0):
				cause = "capacity"
			elif eta < 0 and float(MatchState.preview_buy(tile, gid, outstanding).get("cost", 0.0)) \
					> MatchState.purchase_headroom():
				cause = "cash"
		# Held freight is AT the site and cannot unload — that is a real position, not a guess.
		var at := 0.0
		if cause == "capacity" and held > 0:
			at = 1.0
		elif cause == "":
			at = (0.0 if eta < 0 else 1.0 - float(eta) / float(maxi(maxi(total, eta), 1)))
		out.append({
			"good": gid,
			"icon": GoodIcons.texture_for(gid, str(Catalog.get_internal_name(gid))),
			"required": required,
			"arrived": maxi(0, required - outstanding),
			"outstanding": outstanding,
			"eta": maxi(0, eta),
			"ordered": eta >= 0,
			"at": at,
			"delivered": outstanding <= 0,
			"blocked": cause != "",
			"cause": cause,
			"infra": infra,
			"infra_icon": infra_icon,
			"message": _block_message(cause, infra),
		})
	return out


## Why a material is not moving, in the owner's sentence shape. The infrastructure name is
## data-driven (Catalog.route_infra_for_good reads infrastructure.csv), so it says exactly
## "Pipework" / "Reinforced Pipework" / "Rail or Roads" rather than a hardcoded guess.
func _block_message(cause: String, infra: String) -> String:
	match cause:
		"infra":
			return "%s missing. Cannot deliver to construction site." % infra
		"capacity":
			return "Stockpile full at the site. Cannot deliver to construction site."
		"cash":
			return "Not enough cash to order. Cannot deliver to construction site."
	return ""


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# The blocked-shipment flash and the per-turn material positions both live in _draw, so a
	# site chart redraws every frame. Only while one is open — at rest this costs nothing.
	if not _focus_site.is_empty() and _focus_t > 0.0:
		_pulse = fmod(_pulse + delta * 0.8, 1.0)
		queue_redraw()
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
			_focus_site.clear()
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
	_edge_icon_rects.clear()
	# The gold light the selected building radiates — beneath every line and panel, so the
	# lines lie over the halo the way lit smoke sits behind cables.
	_draw_selection_glow(sc)

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
			_draw_edge_good_chip(mpath, e, "market", font, sc, ma)

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
		_draw_edge_good_chip(path, e, "sell", font, sc, sa)

	# Input lines (thin amber) routed left-to-right between columns.
	for e in _edges:
		if not (_box_by_iid.has(e["from"]) and _box_by_iid.has(e["to"])):
			continue
		var ea := 1.0 if _focus_keeps(e) else off_a
		if ea <= 0.01:
			continue
		var path := _route_input(_box_by_iid[e["from"]], _box_by_iid[e["to"]], int(e.get("lane", 0)), int(e.get("lane_n", 1)), sc)
		draw_polyline(path, Color(_EDGE, ea), _EDGE_WIDTH * sc, true)
		_draw_edge_good_chip(path, e, "input", font, sc, ea)

	# The construction-site delivery chart, under the port hexes so their gold sits on top of
	# the lane ends (and under the panels, which are Controls and always above _draw).
	if not _focus_site.is_empty() and _focus_t > 0.0:
		_draw_site_lanes(font, sc)

	# Building nodes are real Control panels (children, drawn on top); ports are drawn here.
	# With the port badges on, the resting empire no longer carries the bottom row of
	# sell-port hexes (owner 2026-08-16): the badge on each selling building carries "this
	# ships to market" at rest, and the port appears — as its 2x building sprite — only when
	# a mini-chart opens on one. With badges off the hexes return, because then the sell
	# lines need somewhere visible to land.
	for p in _ports:
		var pid := str(p["iid"])
		if _focus_target > 0.0 and _focus_members.has(pid):
			_draw_port(p, font, sc)
		elif _focus_t <= 0.0 and not MatchState.show_port_badge:
			_draw_port(p, font, sc)
	for bp in _buy_ports:
		if _focus_t <= 0.0 or _focus_members.has(str(bp["iid"])):
			_draw_port(bp, font, sc)

	# Last, so it sits over the lines and chips it explains.
	_draw_edge_good_tooltip(font, sc)


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
	var s := _seg_rect_span(p0, p1, r)
	return s.y > s.x


## Parametric span (t0, t1) of the segment p0->p1 that lies inside `r`, by Liang-Barsky slab
## clip; t1 <= t0 means it misses. One routine serves both "does this line cross a sprite"
## and "where does this line have to stop for an icon".
func _seg_rect_span(p0: Vector2, p1: Vector2, r: Rect2) -> Vector2:
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
				return Vector2(1.0, 0.0)
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
			return Vector2(1.0, 0.0)
	return Vector2(t0, t1)


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
	# Buy lines dive the full height of the composition, so they meet more sprites than any
	# other family — and they were the ONLY family with no avoidance at all, which is where
	# most measured "line disappears under a building" cases came from.
	var obs := _sprite_obstacles(str(hub["iid"]), str(b["iid"]), sc)
	var bias := float(slot + 1) / float(maxi(slot_n, 1) + 1)
	var best := _iso_route_v(exit, end, 26.0 * sc, bias, sc)
	if not _blocked(best, obs):
		return best
	for k in range(1, 8):
		var alt := _iso_route_v(exit, end, 26.0 * sc, float(k) / 8.0, sc)
		if not _blocked(alt, obs):
			return alt
	return best


# --- construction-site delivery chart -----------------------------------------------------

## One lane per required material, running from the port hex to the site plate. The material's
## position ALONG its lane is its arrival time (`at`), so the picture answers "how far off is
## this build" at a glance; the white counter between the goods and the site gives the number.
## A material whose route cannot be travelled never moves at all, so its lane turns red and
## carries the missing-infrastructure alert instead.
func _draw_site_lanes(font: Font, sc: float) -> void:
	var plan := site_lane_plan(sc)
	var a := _focus_t
	var fs := maxi(7, int(round(15.0 * sc)))
	var chip := _LANE_CHIP * sc
	for row in plan:
		var lane: Dictionary = row["lane"]
		var y: float = row["y"]
		var blocked := bool(lane["blocked"])
		var delivered := bool(lane["delivered"])
		var col := Color(_ALERT, 0.85 * a) if blocked \
			else Color(_SELL, (0.9 if delivered else 0.5) * a)
		for piece in row["pieces"]:
			if delivered:
				draw_polyline(piece, col, _EDGE_WIDTH * 1.6 * sc, true)
			else:
				_draw_dashed_polyline(piece, col, _EDGE_WIDTH * 1.6 * sc, sc)
		for m in row["marks"]:
			_draw_material_chip((m as Dictionary)["c"], chip, lane["icon"],
				int((m as Dictionary)["qty"]), font, sc, a)
		if blocked:
			_draw_blocked_alert(row["alert"],
				lane["infra_icon"] if str(lane["cause"]) == "infra" else null,
				str(lane["message"]) if bool(row["say"]) else "", font, sc, a)
			continue
		draw_string(font, Vector2(float(row["label_x"]) - 240.0 * sc, y - 16.0 * sc - chip * 0.5),
			str(row["label"]), HORIZONTAL_ALIGNMENT_CENTER, 480.0 * sc, fs,
			Color(_WHITE, (0.55 if delivered else 1.0) * a))


## Everything the delivery chart draws, as data: per lane the goods marks (with their rects),
## the line pieces that survive after the icons are cut out of them, the alert box and the
## counter. The drawing above is a thin loop over this, so the probe measures exactly the
## picture the player gets rather than a second copy of the arithmetic.
func site_lane_plan(sc: float) -> Array:
	var lanes := _site_lanes(str(_focus_site.get("iid", "")))
	_site_lane_n = lanes.size()
	var geo := site_lane_geometry(lanes, sc)
	var chip := _LANE_CHIP * sc
	var out: Array = []
	var holes: Array = []                # CHART-wide, not per lane: see the clip below
	var said: Dictionary = {}            # causes whose sentence has already been printed
	for i in range(geo.size()):
		var lane: Dictionary = lanes[i]
		var g: Dictionary = geo[i]
		var y: float = g["y"]
		var lo: float = g["run_a"]
		var hi: float = g["run_b"]
		# A PART-delivered material shows TWICE: what landed sits on the site, what is still
		# owed sits wherever it has got to. One icon could only ever tell half that story.
		var marks: Array = []
		if int(lane["arrived"]) > 0:
			marks.append({"c": Vector2(hi, y), "qty": int(lane["arrived"]), "outstanding": false})
		if int(lane["outstanding"]) > 0:
			marks.append({"c": Vector2(lerpf(lo, hi, clampf(float(lane["at"]), 0.0, 1.0)), y),
					"qty": int(lane["outstanding"]), "outstanding": true})
		for m in marks:
			holes.append(_chip_hole((m as Dictionary)["c"], chip, sc))
		var alert := Rect2()
		var say := false
		if bool(lane["blocked"]):
			alert = _alert_box(lane, marks, lo, hi, y, chip, sc)
			if str(lane["cause"]) == "infra":
				holes.append(alert.grow(5.0 * sc))
			# The sentence appears ONCE per distinct cause. Every affected material still gets
			# its red square; repeating the same line five times down the chart reads as five
			# problems rather than one, and buries the one that IS different.
			say = not said.has(str(lane["cause"]))
			said[str(lane["cause"])] = true
		# The counter tracks the OUTSTANDING quantity — the arrived half needs no countdown —
		# and stays inside the open run: past the turn-down point it prints over the building
		# art, which is where "on site" landed once the goods arrived, so when the gap ahead
		# closes up the counter moves BEHIND the goods instead.
		var label := "on site"
		var mx := hi
		if not bool(lane["delivered"]):
			if bool(lane["ordered"]):
				label = "%d turn%s to construction site" % [int(lane["eta"]),
						("" if int(lane["eta"]) == 1 else "s")]
				mx = lerpf(lo, hi, clampf(float(lane["at"]), 0.0, 1.0))
			else:
				label = "awaiting order"
				mx = lo
		var ahead := mx + chip * 0.55
		var lx := clampf((ahead + hi) * 0.5, lo, hi)
		if hi - ahead < 150.0 * sc:
			lx = maxf(lo, mx - chip * 0.55 - 150.0 * sc)
		out.append({
			"lane": lane, "y": y, "path": g["path"], "marks": marks, "alert": alert,
			"say": say, "label": label, "label_x": lx,
		})
	# Every icon (and the pill overhanging it) is a HOLE in EVERY line: no line of any colour,
	# dashed or not, may cross a goods icon anywhere in the focused view. Clipping each lane
	# against only its own icons is not enough — the lanes fan out of one point at the port, so
	# a lane's vertical leg runs straight through its neighbours' icons on the way to its row.
	for row in out:
		(row as Dictionary)["holes"] = holes
		(row as Dictionary)["pieces"] = _polyline_minus((row as Dictionary)["path"], holes)
	return out


## Keep-out box for a material chip: the cream plate plus the quantity pill that overhangs its
## bottom-right corner, so a line cannot clip the pill either.
func _chip_hole(c: Vector2, box: float, sc: float) -> Rect2:
	var r := Rect2(c - Vector2(box, box) * 0.5, Vector2(box, box))
	return r.grow_individual(4.0 * sc, 4.0 * sc, 22.0 * sc, 16.0 * sc)


## Box the blocked-shipment pulse radiates from. It rings the OUTSTANDING goods when the goods
## themselves are what cannot move (no cash, nowhere to unload); for missing INFRASTRUCTURE it
## instead stands further along the run around the absent network's own icon, because there the
## subject of the alert is the piece of network, not the cargo.
func _alert_box(lane: Dictionary, marks: Array, lo: float, hi: float, y: float,
		box: float, sc: float) -> Rect2:
	var ox := lo
	for m in marks:
		if bool((m as Dictionary)["outstanding"]):
			ox = ((m as Dictionary)["c"] as Vector2).x
	if str(lane["cause"]) != "infra":
		return _chip_hole(Vector2(ox, y), box, sc)
	var cx := maxf(ox + box * 1.1 + 40.0 * sc, (ox + hi) * 0.5)
	return Rect2(Vector2(cx, y) - Vector2(box, box) * 0.43, Vector2(box, box) * 0.86)


## Screen geometry of the material lanes, one entry per lane: the drawn polyline, the straight
## middle run the goods travel along, and the lane's y. Split out of the drawing so the probe
## measures the SAME polylines the player sees rather than a second copy of the arithmetic.
func site_lane_geometry(lanes: Array, sc: float) -> Array:
	var iid := str(_focus_site.get("iid", ""))
	var site: Dictionary = _box_by_iid.get(iid, {})
	if site.is_empty() or lanes.is_empty():
		return []
	var sp := _plate_screen_of(iid, site)
	var sh: Vector2 = (site.get("plate_half", site["half"]) as Vector2) * sc
	var feed_x := sp.x - sh.x                    # every lane feeds into the plate's left edge
	var pc := sp - Vector2(_SITE_RUN * _view_zoom, 0.0)
	var port: Dictionary = _box_by_iid.get(str(_focus_site.get("port", "")), {})
	if not port.is_empty():
		pc = _screen_of(str(port["iid"]), port)
		pc.x += (port["half"] as Vector2).x * sc
	var jog := 52.0 * sc
	# Where the lanes turn down toward the plate. Lane heights sit level with the SPRITE, not
	# the plate, so this has to clear the sprite's full width (`half`), not the plate's —
	# otherwise the tail of each run crosses the very building art it is delivering to.
	var tx := sp.x - maxf(sh.x, (site["half"] as Vector2).x * sc) - 26.0 * sc
	var n := lanes.size()
	# A blocked lane carries its reason UNDER the alert, and two lines of it do not fit in the
	# normal pitch — the sentence landed on the next lane's icons. Open the rows up whenever
	# any lane is blocked rather than shortening the sentence.
	_site_lane_pitch = _LANE_ROW
	for l in lanes:
		if bool((l as Dictionary)["blocked"]):
			_site_lane_pitch = _LANE_ROW * 1.6
			break
	var pitch := _site_lane_pitch * sc
	var out: Array = []
	for i in range(n):
		var y := pc.y + (float(i) - float(n - 1) * 0.5) * pitch
		out.append({
			"y": y,
			# Goods start clear of the fan, not on it: the lanes all turn down at pc.x + jog, so
			# a material parked at the very start of its run would sit ON the vertical legs of
			# every other lane.
			"run_a": pc.x + jog + _LANE_CHIP * sc * 0.7,
			"run_b": tx,
			"feed_x": feed_x,
			"path": _orth(PackedVector2Array([
				Vector2(pc.x, pc.y), Vector2(pc.x + jog, pc.y), Vector2(pc.x + jog, y),
				Vector2(tx, y), Vector2(tx, sp.y), Vector2(feed_x, sp.y)]), _CHAMFER * sc),
		})
	return out


## The point at fraction `t` (0..1) of the way along a polyline's total ARC LENGTH — used to
## place a good-icon chip partway along a routed edge regardless of how many elbows the route
## takes (a straight fraction of one segment would land wrong on anything but a 2-point path).
## Degenerates to Vector2.ZERO for under 2 points; callers must not draw on that.
func _point_along_polyline(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.size() < 2:
		return Vector2.ZERO
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	if total <= 0.0:
		return pts[0]
	var target := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if walked + seg >= target or i == pts.size() - 2:
			var seg_t := 0.0 if seg <= 0.0 else clampf((target - walked) / seg, 0.0, 1.0)
			return pts[i].lerp(pts[i + 1], seg_t)
		walked += seg
	return pts[pts.size() - 1]


## The good-icon chip every edge carries at _EDGE_CHIP_T along its route (owner, 27 Aug — "any
## line, dashed or not"). Reuses _draw_material_chip's exact cream-rounded-chip look with qty=0
## so its quantity pill stays off — this chip says WHAT flows, not how much. Silent no-op for a
## good with no icon art (nothing to put on the chip) or a path too short to have a "40% along".
func _draw_edge_good_chip(path: PackedVector2Array, e: Dictionary, kind: String, font: Font, sc: float, a: float) -> void:
	var good_id := str(e.get("good", ""))
	if good_id == "" or a <= 0.01 or path.size() < 2:
		return
	var icon := GoodIcons.texture_for_size(good_id, str(Catalog.get_internal_name(good_id)), _LANE_CHIP * sc)
	if icon == null:
		return
	var c := _point_along_polyline(path, _EDGE_CHIP_T)
	var box := _LANE_CHIP * sc
	_draw_material_chip(c, box, icon, 0, font, sc, a)
	# Record the chip's hit-box so the hover readout can find it (cleared per draw).
	_edge_icon_rects.append({"rect": Rect2(c - Vector2(box, box) * 0.5, Vector2(box, box)),
		"edge": e, "kind": kind})


## A material on its lane: the good's icon on the same ROUNDED cream chip the plates use, with
## the quantity in the navy bottom-right pill — the recipe-card treatment (recipe_diagram.gd
## `_qty_pill`, empire_node_panel `_make_badge`), so a material here reads as the same object
## the build panel listed. Drawn through StyleBoxFlat rather than draw_rect because that is the
## only canvas primitive with corner radii.
func _draw_material_chip(c: Vector2, box: float, icon, qty: int, font: Font, sc: float, a: float) -> void:
	var r := Rect2(c - Vector2(box, box) * 0.5, Vector2(box, box))
	if _chip_style == null:
		_chip_style = StyleBoxFlat.new()
	_chip_style.bg_color = Color(_CREAM.r, _CREAM.g, _CREAM.b, 0.95 * a)
	_chip_style.set_corner_radius_all(maxi(2, int(round(box * 0.13))))
	draw_style_box(_chip_style, r)
	if icon != null:
		draw_texture_rect(icon, r.grow(-box * 0.11), false, Color(1, 1, 1, a))
	if qty > 0:
		_draw_qty_pill(r.end, qty, font, sc, a)


## The recipe-card quantity pill: navy, fully rounded, cream border and number, overhanging the
## icon's bottom-right corner by the same fraction the Control version uses.
func _draw_qty_pill(anchor: Vector2, qty: int, font: Font, sc: float, a: float) -> void:
	var txt := str(qty)
	var h := 26.0 * sc
	var fs := maxi(6, int(round(15.0 * sc)))
	var w := maxf(h, float(txt.length()) * 10.0 * sc + 14.0 * sc)
	var over := h * 0.36
	var r := Rect2(anchor + Vector2(over, over) - Vector2(w, h), Vector2(w, h))
	if _pill_style == null:
		_pill_style = StyleBoxFlat.new()
	_pill_style.bg_color = Color(_PILL_NAVY.r, _PILL_NAVY.g, _PILL_NAVY.b, a)
	_pill_style.border_color = Color(_CREAM.r, _CREAM.g, _CREAM.b, a)
	_pill_style.set_border_width_all(maxi(1, int(round(2.0 * sc))))
	_pill_style.set_corner_radius_all(int(round(h * 0.5)))
	draw_style_box(_pill_style, r)
	draw_string(font, Vector2(r.position.x, r.get_center().y + float(fs) * 0.36), txt,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(_CREAM.r, _CREAM.g, _CREAM.b, a))


## Split a polyline into the pieces lying OUTSIDE every rect in `holes`, so a line stops at an
## icon and resumes past it. Drawing the icon on top is not the same thing — the line still
## reads as passing behind it, which is exactly what the owner ruled out.
func _polyline_minus(pts: PackedVector2Array, holes: Array) -> Array:
	if holes.is_empty() or pts.size() < 2:
		return ([pts] if pts.size() >= 2 else [])
	var out: Array = []
	var cur: Array = []                # plain Array: Packed arrays copy on assignment
	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var spans: Array = []
		for h in holes:
			var s := _seg_rect_span(p0, p1, h as Rect2)
			if s.y > s.x:
				spans.append(s)
		spans.sort_custom(func(x, y): return (x as Vector2).x < (y as Vector2).x)
		var t := 0.0
		for sv in spans:
			var a0: float = clampf((sv as Vector2).x, 0.0, 1.0)
			var b0: float = clampf((sv as Vector2).y, 0.0, 1.0)
			if b0 <= t:
				continue                # already covered by an earlier, overlapping hole
			if a0 > t:
				_add_pt(cur, p0.lerp(p1, t))
				_add_pt(cur, p0.lerp(p1, a0))
			if cur.size() >= 2:
				out.append(PackedVector2Array(cur))
			cur = []
			t = b0
		if t < 1.0:
			_add_pt(cur, p0.lerp(p1, t))
			_add_pt(cur, p1)
	if cur.size() >= 2:
		out.append(PackedVector2Array(cur))
	return out


func _add_pt(arr: Array, p: Vector2) -> void:
	if arr.is_empty() or (arr[arr.size() - 1] as Vector2).distance_to(p) > 0.01:
		arr.append(p)


## The blocked-shipment alert: the MISSING infrastructure's own icon, ringed by a red pulse that
## radiates OUTWARD from the icon's edge. Every ring starts outside the art and only grows away
## from it, so the flash never covers the icon (owner's ask) — the message sits underneath.
## `base` is what the pulse radiates from: the missing-infrastructure icon's box when the fault
## is the network, or the outstanding goods chip itself when the cargo is what cannot move
## (no cash, nowhere to unload). Rings only ever grow AWAY from `base`, so whatever sits inside
## it — icon or goods chip — is never covered.
func _draw_blocked_alert(base: Rect2, icon, msg: String, font: Font, sc: float, a: float) -> void:
	var c := base.get_center()
	for k in range(3):
		var ph := fmod(_pulse + float(k) / 3.0, 1.0)
		draw_rect(base.grow(3.0 * sc + ph * 26.0 * sc), Color(_ALERT, (1.0 - ph) * 0.9 * a),
			false, maxf(1.5, 3.0 * sc))
	if icon != null:
		draw_texture_rect(icon, base, false, Color(1.0, 0.86, 0.83, a))
	if msg == "":
		return
	# The message stays INSIDE this lane's own half-pitch: dropped further it landed on the next
	# lane's counter, and two overlapping white strings read as neither. Backed by a navy plate
	# so the neighbouring lane lines never run through the words.
	var fs := maxi(7, int(round(14.0 * sc)))
	var w := 380.0 * sc
	var top := base.end.y + 8.0 * sc
	draw_rect(Rect2(c.x - w * 0.5, top - 4.0 * sc, w, float(fs) * 2.4 + 10.0 * sc),
		Color(0.02, 0.05, 0.10, 0.88 * a), true)
	draw_multiline_string(font, Vector2(c.x - w * 0.5, top + float(fs)), msg,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, 2, Color(_WHITE, a))


## Chamfer an orthogonal polyline after dropping coincident points — a single-lane chart puts
## the lane y exactly on the port y, and a zero-length segment there leaves _chamfer with no
## direction to cut against.
func _orth(pts: PackedVector2Array, c: float) -> PackedVector2Array:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.5:
			clean.append(p)
	return _chamfer(clean, c)


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
	# _screen_of, not a raw projection: a port that is part of an open mini-chart moves to its
	# chart position like everything else, and the lines already anchor there.
	var center: Vector2 = _screen_of(str(n["iid"]), n)
	var half: Vector2 = (n["half"] as Vector2) * sc
	var rect := Rect2(center - half, half * 2.0)
	# The cull margin has to clear the SPRITE, not the hex: inside a chart the port draws at
	# twice the building sprite box, so a flat 240px would drop a port whose centre has just
	# left the viewport while most of its building is still on screen.
	if not get_rect().grow(240.0 + NodePanelScript.SPRITE_PX * _PORT_SPRITE_MULT * 0.5 * sc).intersects(rect):
		return
	# Inside an open mini-chart the port is a PLACE, not a symbol, so it wears the same
	# building sprite the rest of the chart does and keeps only a small gold hex in the
	# bottom-right corner — the identical badge a building selling to market carries.
	if _focus_target > 0.0 and _focus_members.has(str(n["iid"])):
		_draw_port_sprite(n, center, half, font, sc)
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


## The port as it appears INSIDE an open mini-chart: its building sprite, with the lit gold
## hex shrunk to a corner badge. Mirrors empire_node_panel's port badge so a port and a
## building that sells to one are visibly the same statement.
func _draw_port_sprite(n: Dictionary, center: Vector2, half: Vector2, font: Font, sc: float) -> void:
	var tex: Texture2D = BuildingSprites.texture_for("port", 1)
	# TWICE the building sprite box (owner 2026-08-14). Sized off SPRITE_PX, not off the node's
	# own half-extent: `half` is the footprint of the RESTING gold hex (86x78), which drew the
	# port at 156px beside a building's 400px and made the place a whole chain ships through
	# read as a stray icon rather than a destination.
	var box := NodePanelScript.SPRITE_PX * _PORT_SPRITE_MULT * sc
	var draw_sz := Vector2(box, box)
	if tex != null:
		var ts := Vector2(tex.get_width(), tex.get_height())
		var fit := box / maxf(ts.x, ts.y)          # aspect-kept, same contract as the panels
		draw_sz = ts * fit
		draw_texture_rect(tex, Rect2(center - draw_sz * 0.5, draw_sz), false)
	else:
		# No sprite installed: fall back to the icon so the node is never blank.
		var icon = n.get("icon")
		if icon != null:
			var isz := box * 0.6
			draw_sz = Vector2(isz, isz)
			draw_texture_rect(icon, Rect2(center - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
				false, Color(0.02, 0.06, 0.11, 0.95))

	# The corner badge: a lit gold hex at the sprite's bottom-right, overlapping it slightly so
	# it reads as attached rather than floating. Anchored to the SPRITE's own corner rather than
	# the node's layout half — the sprite is now far the larger of the two, and against `half`
	# the badge would land in the middle of the building.
	var bh := box * _PORT_BADGE_FRAC * 0.5
	if bh < 2.0:
		return  # far zoom: a sub-2px hex degenerates (rounded_polygon triangulation fails)
	var bc := center + draw_sz * 0.5 - Vector2(bh, bh) * 0.85
	var bhex := rounded_polygon(hex_points(bc, Vector2(bh, bh)), bh * 0.22, 4)
	draw_polygon(bhex, grad_colors(bhex, Color(1.0, 0.93, 0.63), Color(0.46, 0.35, 0.13)))
	var brim := PackedVector2Array(bhex)
	brim.append(bhex[0])
	draw_polyline(brim, Color(1.0, 0.95, 0.72, 0.9), 1.5 * sc, true)

	draw_string(font, Vector2(center.x - draw_sz.x * 0.5 - 20.0 * sc,
		center.y + draw_sz.y * 0.5 + 16.0 * sc),
		str(n.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, draw_sz.x + 40.0 * sc,
		maxi(6, int(round(13.0 * sc))), _GOLD)


## The gold light a selected building radiates. The reach is a fraction of the building's own
## drawn HEIGHT, so it grows and shrinks with the sprite under zoom instead of holding a fixed
## pixel halo.
func _draw_selection_glow(sc: float) -> void:
	if _focus_iid == "" or _focus_target <= 0.0:
		return
	if not _screen_by_iid.has(_focus_iid):
		return
	var node: Dictionary = _box_by_iid.get(_focus_iid, {})
	if node.is_empty():
		return
	var center: Vector2 = _screen_by_iid[_focus_iid]
	var half: Vector2 = (node.get("half", Vector2(200.0, 290.0)) as Vector2) * sc
	var reach: float = half.y * 2.0 * _GLOW_HEIGHT_FRAC
	if reach <= 0.5:
		return
	# Fade the whole halo in with the focus tween so it arrives with the arrangement.
	var lit: float = clampf(_focus_t, 0.0, 1.0)
	# One stretched radial gradient rather than a stack of shapes. Concentric polygons —
	# filled or outlined — band visibly at this size: filled ones accumulate into a flat
	# slab and outlined ones read as rings. A gradient texture is smooth, and it is a
	# single draw call besides.
	var r := Rect2(center - half - Vector2(reach, reach), (half + Vector2(reach, reach)) * 2.0)
	draw_texture_rect(_glow_texture(), r, false, Color(_GOLD.r, _GOLD.g, _GOLD.b, _GLOW_ALPHA * lit))


## Radial falloff for the selection halo, built once. Opaque at the centre (where the
## sprite covers it anyway) easing to nothing at the edge, so the light bleeds outward.
static var _glow_tex: GradientTexture2D = null

static func _glow_texture() -> GradientTexture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := Gradient.new()
	g.set_offsets(PackedFloat32Array([0.0, 0.42, 0.72, 1.0]))
	g.set_colors(PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0),
	]))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 192
	t.height = 192
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_glow_tex = t
	return _glow_tex


## Which material chip (if any) the cursor is over. Only redraws when the answer changes,
## so moving the mouse across an open chart is not a per-pixel repaint.
func _update_edge_hover(pos: Vector2) -> void:
	var found: Dictionary = {}
	for entry in _edge_icon_rects:
		if ((entry as Dictionary)["rect"] as Rect2).has_point(pos):
			found = entry
			break
	var was := str((_hover_edge.get("edge", {}) as Dictionary).get("from", "")) \
		+ ">" + str((_hover_edge.get("edge", {}) as Dictionary).get("to", "")) \
		+ ":" + str((_hover_edge.get("edge", {}) as Dictionary).get("good", ""))
	var now := str((found.get("edge", {}) as Dictionary).get("from", "")) \
		+ ">" + str((found.get("edge", {}) as Dictionary).get("to", "")) \
		+ ":" + str((found.get("edge", {}) as Dictionary).get("good", ""))
	if was == now:
		return
	_hover_edge = found
	queue_redraw()


## The hovered chip's readout: a panel the same height as the chip, opening to its right,
## carrying two right-aligned figures. Text is off-white; only the numbers carry colour, on
## the same OK/WARN/DANGER scale the building diagnostics use.
func _draw_edge_good_tooltip(font: Font, sc: float) -> void:
	if _hover_edge.is_empty():
		return
	var e: Dictionary = _hover_edge.get("edge", {})
	var plate: Rect2 = _hover_edge.get("rect", Rect2())
	if e.is_empty() or plate.size.x <= 0.0:
		return
	var to_iid := str(e.get("to", ""))
	var good := str(e.get("good", ""))
	var tile := str((_box_by_iid.get(to_iid, {}) as Dictionary).get("tile_id", ""))
	if tile == "":
		tile = str((MatchState.buildings.get(to_iid, {}) as Dictionary).get("tile_id", ""))

	# Row 1 — what this line costs to run, per turn. "no route" rather than £0.00 when there is
	# nothing priceable: zero reads as free, and the case it actually covers is a haul the goods
	# cannot make at all (a fluid with no pipe network to the destination, say).
	var tc: Dictionary = _edge_transport_cost(e, str(_hover_edge.get("kind", "input")))
	var known: bool = bool(tc.get("known", false))
	var cost: float = float(tc.get("cost", 0.0))
	var cost_txt: String = ("£%.2f" % cost) if known else "no route"
	var cost_col: Color = _cost_colour(cost) if known else DS.PALETTE["DANGER"]
	# Row 2 — what is already on its way, and how dependable the line has been. The
	# colour is the CONSISTENCY verdict; a young building is not judged for silence.
	var inbound := 0
	for s in MatchState.get_inbound_transport_shipments(tile, good):
		if int((s as Dictionary).get("turns_remaining", 99)) <= _SHIPMENT_LOOKAHEAD:
			inbound += int((s as Dictionary).get("qty", 0))
	var hits: int = MatchState.arrivals_in_window(tile, good)
	var age := _building_age(to_iid)
	var ship_col := _consistency_colour(hits, age)
	var ship_txt := "%d" % inbound

	var fs := maxi(9, int(round(13.0 * sc)))
	var row_h := float(fs) + 6.0 * sc
	var pad := 10.0 * sc
	var label1 := "Transport cost per turn"
	var label2 := "Shipments expected in %d turns" % _SHIPMENT_LOOKAHEAD
	var w := maxf(font.get_string_size(label1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		font.get_string_size(label2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) \
		+ maxf(font.get_string_size(cost_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
			font.get_string_size(ship_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) \
		+ pad * 3.0
	var h := maxf(plate.size.y, row_h * 2.0 + pad * 1.4)
	var panel := Rect2(Vector2(plate.end.x + 6.0 * sc, plate.position.y), Vector2(w, h))
	# Flip to the left if it would leave the viewport.
	if panel.end.x > get_rect().size.x - 8.0:
		panel.position.x = plate.position.x - 6.0 * sc - w

	var poly := rounded_polygon(PackedVector2Array([
		panel.position, Vector2(panel.end.x, panel.position.y), panel.end,
		Vector2(panel.position.x, panel.end.y),
	]), 8.0 * sc, 5)
	draw_colored_polygon(poly, Color(0.04, 0.08, 0.14, 0.96))
	var rim := PackedVector2Array(poly)
	rim.append(poly[0])
	draw_polyline(rim, Color(_GOLD.r, _GOLD.g, _GOLD.b, 0.55), 1.5 * sc, true)

	var y := panel.position.y + (h - row_h * 2.0) * 0.5 + float(fs)
	_tooltip_row(font, panel, label1, cost_txt, cost_col, y, fs, pad)
	_tooltip_row(font, panel, label2, ship_txt, ship_col, y + row_h, fs, pad)


func _tooltip_row(font: Font, panel: Rect2, label: String, value: String, col: Color,
		y: float, fs: int, pad: float) -> void:
	draw_string(font, Vector2(panel.position.x + pad, y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _CREAM_TEXT)
	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Drawn twice with a 1px offset: the numbers are the point of the panel, and there is
	# no bold face in this font set to lean on.
	draw_string(font, Vector2(panel.end.x - pad - vw + 1.0, y), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, Vector2(panel.end.x - pad - vw, y), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Per-turn transport cost of the movement THIS EDGE represents. Which route that is depends on
## what kind of edge it is — quoting one route for all three is the bug the owner spotted as
## "£0.00 on a haul that surely costs something" (2026-08-14):
##   market  buy port -> building   a real market purchase; preview_buy is the right quote
##   sell    building -> port       the haul out to the port the goods leave through
##   input   building -> building   the INTERNAL haul, producer tile -> consumer tile
## Returns {cost, known}. `known` false means no priceable route exists; the caller must not
## print that as £0.00, which reads as "free" when it means "this cannot be shipped at all".
func _edge_transport_cost(e: Dictionary, kind: String) -> Dictionary:
	var good := str(e.get("good", ""))
	var g: Dictionary = Catalog.get_good(good)
	if g.is_empty():
		g = Catalog.get_good_by_internal_name(good)
	var gid := str(g.get("id", good))
	var src := _tile_of(str(e.get("from", "")))
	var dst := _tile_of(str(e.get("to", "")))
	if kind == "market":
		if dst == "":
			return {"cost": 0.0, "known": false}
		var quote: Dictionary = MatchState.preview_buy(dst, gid, 1)
		if quote.is_empty():
			return {"cost": 0.0, "known": false}   # refused or unroutable — NOT free
		return {"cost": float(quote.get("transport_cost", 0.0)), "known": true}
	return _route_leg_cost(gid, src, dst)


## One unit over the real route between two tiles. Unreachable is deliberately NOT free: the
## engine returns 0.0 there on purpose (the INF_TURNS sentinel once billed ~£1e9 for fluids with
## no pipe network), so reachability is what decides `known` — never the number itself.
func _route_leg_cost(gid: String, src: String, dst: String) -> Dictionary:
	if src == "" or dst == "":
		return {"cost": 0.0, "known": false}
	if src == dst:
		return {"cost": 0.0, "known": true}        # same tile: genuinely no haul to pay for
	var route_data: Dictionary = TransportService.route(src, dst, gid)
	if not TransportService.route_is_reachable(route_data):
		return {"cost": 0.0, "known": false}
	return {"cost": TransportService.transport_cost_for_route(gid, 1, route_data), "known": true}


## The tile a graph node stands on. Nodes carry `tile_id` for buildings AND ports (buy ports are
## copies of their port), so this resolves every endpoint an edge can have.
func _tile_of(iid: String) -> String:
	var t := str((_box_by_iid.get(iid, {}) as Dictionary).get("tile_id", ""))
	if t == "":
		t = str((MatchState.buildings.get(iid, {}) as Dictionary).get("tile_id", ""))
	return t


## Cheap is green, ordinary amber, dear red — the building diagnostics' own scale.
func _cost_colour(cost: float) -> Color:
	if cost <= _COST_OK:
		return DS.PALETTE["OK"]
	if cost <= _COST_WARN:
		return DS.PALETTE["WARN"]
	return DS.PALETTE["DANGER"]


## Delivered every turn is green; patchy is amber; two or fewer of the last ten is red —
## unless the building is younger than that, in which case there was nothing to deliver.
func _consistency_colour(hits: int, age_turns: int) -> Color:
	if hits >= MatchState.ARRIVAL_HISTORY_TURNS:
		return DS.PALETTE["OK"]
	if hits <= 2:
		return DS.PALETTE["WARN"] if age_turns <= 2 else DS.PALETTE["DANGER"]
	return DS.PALETTE["WARN"]


func _building_age(iid: String) -> int:
	var b: Dictionary = MatchState.buildings.get(iid, {})
	if b.is_empty():
		return 999
	var built := int(b.get("built_turn", b.get("construction_turn", 0)))
	if built <= 0:
		return 999
	return maxi(0, int(TurnManager.current_turn) - built)


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
