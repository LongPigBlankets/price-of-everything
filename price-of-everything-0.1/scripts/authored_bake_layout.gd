extends RefCounted
## THE PARTITION: how an authored-map document is cut into per-tile bake units.
##
## Pure geometry and record-sorting — no drawing, no file access, no scene tree — so the
## export tool, the runtime layer and the unit suite all agree on the same answer, and the
## whole thing is testable without standing a map up. This is the "extract the JSON and break
## it into tiles" step; `tools/map_editor/bake_authored_map.gd` renders what this returns and
## `scripts/authored_bake.gd` reads the result back at play time.
##
## THE UNIT IS THE PITCH RECT, NOT THE HEX BBOX (docs/map-editor-plan.md §7). Hex bboxes are
## 540 wide at 405 column pitch, so neighbours overlap by 135 u and could never partition the
## plane. The pitch rect — 405×480 u centred on the tile centre — tiles the plane exactly.
## Every rect renders the SAME global geometry clipped at its edges, so a stroke crossing a
## seam recomposes pixel-exactly when the textures are laid back down side by side.
##
## COORDINATE AUTHORITY. Tile centres are NEVER computed from the digits in a tile id here;
## the caller passes the centre it got from `%TerrainLayer.map_to_local()` (§2). This file
## only ever does centre→rect arithmetic, which is why it can stay pure.
##
## STATIC BAKES, DYNAMIC STAYS LIVE. A record is baked only if its visibility can never change
## during a match. Unlockable roads (revealed when a tile gains the road flag) and sacrificial
## masses (removed when a gameplay building takes their ground) are therefore EXCLUDED from
## the bake and keep drawing as vectors over the texture. On the current document that is 37
## of 324 strokes and 0 masses — a rounding error at draw time, and it means the reveal and
## eviction paths keep working exactly as they do today with no overlay-sprite machinery.
## (docs/map-editor-plan.md §7 specifies per-tile unlock overlays and connector patches
## instead; that is strictly more artifacts for the same picture, and is only worth building
## if the live remainder ever grows big enough to measure.)

## World units per bake pixel. 4/3 gives integer texel rects (405×480 u → 540×640 px) and sits
## ~20% above the ~1.107 px/u maximum play zoom, so a baked tile is never magnified on screen.
const BAKE_SCALE := 4.0 / 3.0

## The pitch rect's size in world units: column pitch × row pitch.
const PITCH := Vector2(405.0, 480.0)

## Every record kind the fabric layer draws, in the order `authored_fabric_visuals.gd` draws
## them. LAYER-MAJOR ACROSS SETTLEMENTS: all ground first, then everything standing on it, so
## one settlement's greens can never cover a neighbouring settlement's buildings. The bake
## must use this exact order or the texture and the live render disagree.
const FABRIC_ORDER: Array[String] = ["plazas", "parks", "farms", "decor", "specials", "forests"]

## Culling margin, world units. A record is drawn into a tile when its outline bbox, grown by
## this much, meets the tile's rect — the slack covers everything a painter puts OUTSIDE the
## authored outline: mass drop shadows (2.2, 2.8), park/plaza edge strokes, tree crowns that
## overhang a woodland edge, and half of the widest road bed (18 u) plus its ink casing.
## Generous on purpose: too large only costs a little bake time, too small clips content at a
## seam, which is the one defect this whole partition exists to avoid.
const CULL_MARGIN := 64.0

## How far the fabric is cut back from a harbour, world units. THE ONE definition —
## `port_visuals` reads it from here, so the cut the exporter bakes in and the cut the running
## game applies cannot drift apart.
const PORT_CLEARANCE := 10.0


## The bake unit for a tile whose centre is `centre` (from the terrain layer).
static func pitch_rect(centre: Vector2) -> Rect2:
	return Rect2(centre - PITCH * 0.5, PITCH)


## Texture dimensions for one tile. Integer by construction at BAKE_SCALE = 4/3.
static func texture_size() -> Vector2i:
	return Vector2i(int(round(PITCH.x * BAKE_SCALE)), int(round(PITCH.y * BAKE_SCALE)))


## World → texture transform for the painter node inside the export SubViewport: scale by the
## bake scale and shift the rect's origin to the texture's (0,0). Matches `HillPainter`'s
## recipe (docs/map-editor-plan.md §7).
static func bake_transform(rect: Rect2) -> Transform2D:
	return Transform2D(Vector2(BAKE_SCALE, 0.0), Vector2(0.0, BAKE_SCALE), -rect.position * BAKE_SCALE)


## Is this road stroke part of the permanent picture? Unlockable strokes appear mid-match when
## their tiles gain the road flag, so they can never be baked into a static texture.
static func road_is_static(stroke: Dictionary) -> bool:
	return not bool(stroke.get("unlockable", false))


## Is this mass part of the permanent picture?
##
## Two kinds are not, and both stay live vectors instead:
##   * a `sacrificial` mass, which may be removed at any time to make room for a gameplay
##     building (the eviction rule);
##   * anything belonging to a HARBOUR (`port`), because a harbour carries cargo, cranes and a
##     fuel line that move with it, and because the quay is drawn as one merged silhouette
##     rather than as separate shapes — baking it would freeze both.
static func mass_is_static(record: Dictionary) -> bool:
	if bool(record.get("sacrificial", false)):
		return false
	return str(record.get("port", "")) == ""


## The records this tile's texture must draw, already filtered to static content and grouped by
## kind. Shape: {"plazas": [...], ..., "roads": [...]}, every key present (possibly empty) so
## callers need no defaults. Order within each list follows the document, and the caller walks
## the kinds in FABRIC_ORDER.
static func records_for_rect(settlements: Dictionary, rect: Rect2) -> Dictionary:
	var grown := rect.grow(CULL_MARGIN)
	var out: Dictionary = {"roads": []}
	for kind in FABRIC_ORDER:
		out[kind] = []
	# Settlement keys sorted so two runs over the same document emit records in the same
	# order — the bake has to be byte-reproducible (the `bake_roads` determinism gate).
	var keys := settlements.keys()
	keys.sort()
	for kind in FABRIC_ORDER:
		for key in keys:
			var settlement_value: Variant = settlements[key]
			if typeof(settlement_value) != TYPE_DICTIONARY:
				continue
			for record in _list(settlement_value as Dictionary, kind):
				if not mass_is_static(record):
					continue
				if bounds_of(record).intersects(grown):
					(out[kind] as Array).append(record)
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for stroke in _list(settlement_value as Dictionary, "roads"):
			if not road_is_static(stroke):
				continue
			if bounds_of(stroke).intersects(grown):
				(out["roads"] as Array).append(stroke)
	return out


## The keep-out regions for every harbour the DOCUMENT carries: each port's shapes unioned and
## grown by PORT_CLEARANCE. Derived from the document alone, so the exporter can bake the cut
## without standing up a port planner — which it has no way to do, since it never builds the
## world. At runtime `port_visuals` supplies the same regions for planner-drawn harbours too.
static func port_keep_out(settlements: Dictionary) -> Array:
	var by_tile: Dictionary = {}
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for record in _list(settlement_value as Dictionary, "specials"):
			var tile_id := str(record.get("port", ""))
			if tile_id == "":
				continue
			var poly := _points(record, "outline")
			if poly.size() < 3:
				continue
			if not by_tile.has(tile_id):
				by_tile[tile_id] = []
			(by_tile[tile_id] as Array).append(poly)
	var out: Array = []
	var tiles := by_tile.keys()
	tiles.sort()
	for tile_id in tiles:
		for poly_value in (by_tile[tile_id] as Array):
			for grown_value in Geometry2D.offset_polygon(poly_value as PackedVector2Array,
					PORT_CLEARANCE, Geometry2D.JOIN_MITER):
				var grown: PackedVector2Array = grown_value
				if grown.size() >= 3 and not Geometry2D.is_polygon_clockwise(grown):
					out.append(grown)
	return out


## True when a tile's texture would be empty — nothing static reaches it. The exporter skips
## these rather than writing 139 transparent PNGs, and the manifest simply has no entry, which
## is what makes the runtime "no texture → draw nothing" path the same as "not authored".
static func is_empty(records: Dictionary) -> bool:
	for kind in records:
		if not (records[kind] as Array).is_empty():
			return false
	return true


## Bounding box of any authored record, in world units. Public because the runtime repaint
## (authored_fabric_visuals) has to ask the SAME question the bake asked — which tiles does
## this record reach — when a mass is evicted. Handles all three geometry shapes the
## document uses: an `outline` polygon (parks, plazas, farms, forests, specials, zones), a
## `points` list (road strokes), and `pos`+`size` (decorative masses, which are a form drawn
## about a centre — the diagonal covers any rotation).
static func bounds_of(record: Dictionary) -> Rect2:
	var outline := _points(record, "outline")
	if not outline.is_empty():
		return _bounds_of_points(outline)
	var points := _points(record, "points")
	if not points.is_empty():
		return _bounds_of_points(points)
	var pos_value: Variant = record.get("pos", null)
	if typeof(pos_value) == TYPE_ARRAY and (pos_value as Array).size() >= 2:
		var centre := Vector2(float((pos_value as Array)[0]), float((pos_value as Array)[1]))
		var reach := 1.0
		var size_value: Variant = record.get("size", null)
		if typeof(size_value) == TYPE_ARRAY and (size_value as Array).size() >= 2:
			# Rotation is free, so the safe half-extent is the diagonal, not the axes.
			reach = Vector2(float((size_value as Array)[0]), float((size_value as Array)[1])).length()
		return Rect2(centre - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	# Unknown shape: claim everything so it is never wrongly culled. Correctness first — a
	# record drawn into a tile it does not touch is invisible, but one culled by mistake is a
	# hole. Finite (the world is 13905×11760) because INF corners make intersects() return NaN.
	return Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)


static func _bounds_of_points(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


static func _points(record: Dictionary, key: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var value: Variant = record.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in (value as Array):
		if typeof(entry) == TYPE_ARRAY and (entry as Array).size() >= 2:
			out.append(Vector2(float((entry as Array)[0]), float((entry as Array)[1])))
	return out


static func _list(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	var value: Variant = settlement.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in (value as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	return out
