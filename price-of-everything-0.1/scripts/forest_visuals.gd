extends Node2D
## Draws forest buildings as blobby terrain patches instead of small icon slots.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS: Array[Vector2] = [
	Vector2(135, 0), Vector2(405, 0), Vector2(540, 240),
	Vector2(405, 480), Vector2(135, 480), Vector2(0, 240),
]
const RIVER_POINTS := {
	"C0": Vector2(270, 240),
	"S1": Vector2(390, 120),
	"S2": Vector2(390, 360),
	"S3": Vector2(150, 360),
	"S4": Vector2(150, 120),
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}

## Canopy colours live in MapStyle ('toggle ink' / 'toggle plate' swap them):
## classic and ink return these exact values, so both stay byte-identical.
const FOREST_SHADOW := Color(0.02, 0.10, 0.05, 0.28)
const RIVER_SCREEN_CLEARANCE_PX := 5.0
const RIVER_HALF_WIDTH := 7.5
# Canopy fill: a coarse jittered grid of large overlapping lobes (lobe > step so
# neighbours merge into a continuous mass). Coarse on purpose — a 10%-of-tile
# forest with a fine grid was ~80 circles; this is ~30, and the pattern itself is
# cached per (shape, variant) and reused across every forest of that kind.
const FOREST_FILL_STEP := 30.0
const FOREST_FILL_JITTER := 6.0
const FOREST_LOBE := 20.0
const FOREST_PATTERN_VARIANTS := 4
const SOURCE_LAKE_DEFAULT_WIDTH := 200.0
const SOURCE_LAKE_DEFAULT_HEIGHT := 150.0

@onready var terrain_layer: HexMap = get_node_or_null("%TerrainLayer") as HexMap
@onready var river_visuals: Node = get_node_or_null("../RiverVisuals")

var _forests: Dictionary = {}
var _river_paths_by_coord: Dictionary = {}
var _river_cache_ready: bool = false
# "kind:variant" -> Array[{off:Vector2, r:float, shade:float}]: the reusable
# canopy stamps (shape-local, unrotated), generated once.
var _pattern_cache: Dictionary = {}
# instance_id -> {circles, shadow_r, mean_half, center}: the per-forest draw
# list, computed (incl. water/hex clipping) once and replayed on redraw.
var _draw_cache: Dictionary = {}
# World centres of every forested tile, for the gravitate-toward-neighbours pull.
var _neighbour_centers: Array = []
var _neighbour_dirty: bool = true
# Every forest's canopy + shadow is drawn as ONE MultiMesh (one draw call) and
# every highlight arc as ONE batched multiline — in GL-compat each draw_circle is
# its own draw call, so ~150 forests × ~25 lobes was thousands of draws/frame.
var _disc_mesh: Mesh = null
var _canopy_mm: MultiMesh = null
var _arc_pts: PackedVector2Array = PackedVector2Array()
var _base_indices: PackedInt32Array = PackedInt32Array()
var _base_colors: Array[Color] = []
var _base_alpha := -1.0
var _crown_alpha := -1.0
var _mm_dirty: bool = true
var _bulk := false   # begin_bulk()/end_bulk() window (match-start placement)
var _white_tex: Texture2D = null

func _white_texture() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

func _ready() -> void:
	MapStyle.style_changed.connect(_on_style_changed)

## Canopy colours are baked into _draw_cache and then into the MultiMesh instance
## colours, so a style flip has to drop both.
func _on_style_changed() -> void:
	_draw_cache.clear()
	_base_indices = PackedInt32Array()
	_base_colors.clear()
	_base_alpha = -1.0
	_crown_alpha = -1.0
	_mm_dirty = true
	queue_redraw()

func _process(_delta: float) -> void:
	if not MapStyle.is_midcentury() or _canopy_mm == null:
		return
	var redraw := false
	var base_alpha := _canopy_base_alpha()
	if not is_equal_approx(base_alpha, _base_alpha):
		_base_alpha = base_alpha
		for i in _base_indices.size():
			var color := _base_colors[i]
			color.a *= base_alpha
			_canopy_mm.set_instance_color(_base_indices[i], color)
		redraw = true
	var crown_alpha := _canopy_crown_alpha()
	if not is_equal_approx(crown_alpha, _crown_alpha):
		_crown_alpha = crown_alpha
		redraw = true
	if redraw:
		queue_redraw()

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if not FOREST_BUILDING_IDS.has(building_id):
		return
	var key: String = instance_id if instance_id != "" else "%s:%s" % [tile_id, building_id]
	_forests[key] = {
		"tile_id": tile_id,
		"building_id": building_id,
		"coord": coord,
	}
	# A new forest changes its neighbours' pull, so recompute centres next draw.
	_neighbour_dirty = true
	_mm_dirty = true
	if _bulk:
		return
	_draw_cache.clear()
	queue_redraw()


## Bulk window (match-start placement): defer the cache clear + redraw to end_bulk so
## placing ~145 start forests rebuilds the draw data once instead of once per forest.
func begin_bulk() -> void:
	_bulk = true


func end_bulk() -> void:
	_bulk = false
	_neighbour_dirty = true
	_draw_cache.clear()
	_mm_dirty = true
	queue_redraw()

func clear_all() -> void:
	_forests.clear()
	_draw_cache.clear()
	_neighbour_dirty = true
	_mm_dirty = true
	_river_paths_by_coord.clear()
	_river_cache_ready = false
	queue_redraw()

## True once this forest instance is tracked (and thus drawn). Forests never get a
## building_visuals footprint, so this is their equivalent of has_placement() — the
## start-building passes use it to skip re-emitting forests that already render.
func has_forest(instance_id: String) -> bool:
	return _forests.has(instance_id)

## The tile a registered forest stands on, or "". The registry outlives the building record —
## which is erased before `building_removed` reaches its listeners — so this is how world_map
## knows which authored canopy a felled wood was drawing (see `_drop_building_visual`).
func tile_of_instance(instance_id: String) -> String:
	var entry: Dictionary = _forests.get(instance_id, {})
	return str(entry.get("tile_id", ""))


func remove_instance(instance_id: String) -> void:
	if not _forests.has(instance_id):
		return
	_forests.erase(instance_id)
	_neighbour_dirty = true
	_draw_cache.clear()
	_mm_dirty = true
	queue_redraw()

func _draw() -> void:
	var _lpd := Time.get_ticks_usec()
	_lp_draw_inner()
	var _lpms := float(Time.get_ticks_usec() - _lpd) / 1000.0
	if _lpms > 50.0 and OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF-DRAW %s %.0f ms   abs=%d" % [name, _lpms, Time.get_ticks_msec()])


func _lp_draw_inner() -> void:
	if terrain_layer == null:
		return
	_ensure_river_cache()
	_ensure_canopy()
	if _canopy_mm != null and _canopy_mm.instance_count > 0:
		draw_multimesh(_canopy_mm, _white_texture())   # all shadows + canopy lobes, one draw call
	var arc := MapStyle.forest_arc()
	if MapStyle.is_midcentury():
		arc.a *= maxf(0.0, _crown_alpha)
	if not _arc_pts.is_empty() and arc.a > 0.0:
		draw_multiline(_arc_pts, arc, 1.15 if MapStyle.is_midcentury() else 3.0)

## Build the canopy MultiMesh and batched arc lines from every forest's clipped
## draw data. Rebuilt only when forests change (rare); the GPU then redraws the
## whole canopy every frame as a single instanced draw.
func _ensure_canopy() -> void:
	if not _mm_dirty:
		return
	_mm_dirty = false
	# THE DOCUMENT DRAWS THE WOODS NOW. Once `import_forests` has written every canopy out as
	# a `forests` area, these discs would be a second copy of the same wood drawn over the top
	# of the trees -- which is what was hiding the authored tree vocabulary (owner,
	# 2026-08-28). The gate lives HERE, in the draw path, and not in `_forest_draw_data`: that
	# function is the only description of where a wood is and how big, and the importer has to
	# read it to do the conversion in the first place. Gating the data made the tool unable to
	# see the very forests it had been asked to convert, the second time it was run.
	if AuthoredMap.is_active() and AuthoredMap.forests_imported():
		_canopy_mm = null
		_arc_pts = PackedVector2Array()
		return
	var shadows: Array = []   # [pos, r, aspect, rotation]
	var bases: Array = []     # [pos, r, color, aspect, rotation]
	var lobes: Array = []     # [pos, r, color, aspect, rotation]
	_arc_pts = PackedVector2Array()
	# City plate: the canopy is a low park block on the shared light model. One
	# opaque shadow disc PER LOBE, offset SE — their union IS the offset canopy
	# silhouette for any footprint shape, where the single centre disc below
	# under-covers oblong woods (its radius is the MEAN half-extent).
	var plate := MapStyle.has_cartographic_depth()
	var organic_lobes := MapStyle.is_midcentury()
	var lobe_off := MapStyle.extrude_offset(MapStyle.Extrude.MILD)
	var lobe_side := MapStyle.extrude_side(MapStyle.forest_base(), MapStyle.Extrude.MILD)
	for instance_key in _forests.keys():
		var instance_id: String = str(instance_key)
		var entry: Dictionary = _forests[instance_id] as Dictionary
		var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
		if not terrain_layer.tiles.has(coord):
			continue
		var data: Dictionary = _forest_draw_data(instance_id, str(entry.get("tile_id", "")), coord)
		var circles: Array = data.circles
		if circles.is_empty():
			continue
		if plate:
			for circle in circles:
				shadows.append([circle.pos + lobe_off, float(circle.r),
					float(circle.aspect) if organic_lobes else 1.0,
					float(circle.rot) if organic_lobes else 0.0])
		else:
			shadows.append([data.center + Vector2(0, 3.0), float(data.shadow_r), 1.0, 0.0])
		if organic_lobes:
			for base_lobe in data.base_lobes:
				if _circle_drawable(base_lobe.pos, float(base_lobe.r), coord):
					bases.append([base_lobe.pos, float(base_lobe.r), base_lobe.color,
						float(base_lobe.aspect), float(base_lobe.rot)])
		for circle in circles:
			lobes.append([circle.pos, float(circle.r), circle.color,
				float(circle.aspect) if organic_lobes else 1.0,
				float(circle.rot) if organic_lobes else 0.0])
		if organic_lobes:
			_append_crown_marks(circles, instance_id, coord)
		else:
			_append_arc_segments(data.center, float(data.mean_half), instance_id, coord)

	if _disc_mesh == null:
		_disc_mesh = _build_disc_mesh(16)
	if _canopy_mm == null:
		_canopy_mm = MultiMesh.new()
		_canopy_mm.transform_format = MultiMesh.TRANSFORM_2D
		_canopy_mm.use_colors = true
		_canopy_mm.mesh = _disc_mesh
	# Shadows first, then the zoom-faded under-mass, then edge/detail lobes.
	# Instances render in index order; the three arrays remain one draw call.
	_canopy_mm.instance_count = shadows.size() + bases.size() + lobes.size()
	var idx := 0
	for s in shadows:
		_canopy_mm.set_instance_transform_2d(idx, _lobe_xform(s[0], float(s[1]), float(s[2]), float(s[3])))
		_canopy_mm.set_instance_color(idx, lobe_side if plate else FOREST_SHADOW)
		idx += 1
	_base_indices = PackedInt32Array()
	_base_colors.clear()
	_base_alpha = _canopy_base_alpha()
	_crown_alpha = _canopy_crown_alpha()
	for b in bases:
		_canopy_mm.set_instance_transform_2d(idx, _lobe_xform(b[0], float(b[1]), float(b[3]), float(b[4])))
		var base_color: Color = b[2]
		_base_colors.append(base_color)
		_base_indices.append(idx)
		base_color.a *= _base_alpha
		_canopy_mm.set_instance_color(idx, base_color)
		idx += 1
	for l in lobes:
		_canopy_mm.set_instance_transform_2d(idx, _lobe_xform(l[0], float(l[1]), float(l[3]), float(l[4])))
		_canopy_mm.set_instance_color(idx, l[2])
		idx += 1

func _disc_xform(pos: Vector2, r: float) -> Transform2D:
	return Transform2D(Vector2(r, 0.0), Vector2(0.0, r), pos)

func _lobe_xform(pos: Vector2, r: float, aspect: float, rotation: float) -> Transform2D:
	# aspect == 1 and rotation == 0 is the exact legacy disc transform. The
	# mid-century renderer alone supplies narrower, rotated lobes whose major
	# radius never exceeds the existing occupancy/clearance disc.
	if is_equal_approx(aspect, 1.0) and is_zero_approx(rotation):
		return _disc_xform(pos, r)
	var axis := Vector2.from_angle(rotation)
	var cross := Vector2(-axis.y, axis.x)
	return Transform2D(axis * r, cross * r * aspect, pos)

func _canopy_base_alpha() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.0
	var zoom := cam.zoom.x
	var alpha: float
	if zoom <= 0.22:
		alpha = 0.62
	elif zoom >= 1.05:
		alpha = 0.0
	else:
		var t := smoothstep(0.22, 1.05, zoom)
		alpha = lerpf(0.62, 0.0, t)
	# Quantising prevents hundreds of MultiMesh colour uploads during a smooth
	# wheel gesture while retaining an imperceptible fade between detail bands.
	return roundf(alpha * 16.0) / 16.0

func _canopy_crown_alpha() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.0
	var zoom := cam.zoom.x
	var alpha: float
	if zoom <= 0.55:
		alpha = 0.0
	elif zoom >= 1.2:
		alpha = 1.0
	else:
		alpha = smoothstep(0.55, 1.2, zoom)
	return roundf(alpha * 12.0) / 12.0

func _append_crown_marks(circles: Array, instance_id: String, coord: Vector2i) -> void:
	# Sparse short arcs add cartographic crown structure without reintroducing a
	# repeated whole-cluster ring. Geometry follows each accepted ellipse and is
	# invisible at wide zoom through _canopy_crown_alpha().
	for i in circles.size():
		if _seed("%s|crown|%d" % [instance_id, i]) % 100 >= 19:
			continue
		var circle: Dictionary = circles[i]
		var center: Vector2 = circle.pos
		var radius := float(circle.r) * 0.54
		if not _circle_drawable(center, radius, coord):
			continue
		var aspect := float(circle.aspect)
		var rot := float(circle.rot)
		var axis := Vector2.from_angle(rot)
		var cross := Vector2(-axis.y, axis.x)
		var start := 3.35 + float(_seed("%s|crown-start|%d" % [instance_id, i]) % 101) / 100.0
		var steps := 4
		var prev := center + axis * cos(start) * radius + cross * sin(start) * radius * aspect
		for step in range(1, steps + 1):
			var angle := start + 0.82 * float(step) / float(steps)
			var point := center + axis * cos(angle) * radius + cross * sin(angle) * radius * aspect
			_arc_pts.append(prev)
			_arc_pts.append(point)
			prev = point

func _build_disc_mesh(seg: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in seg + 1:
		var a := TAU * float(i) / float(seg)
		verts.append(Vector3(cos(a), sin(a), 0.0))
	var indices := PackedInt32Array()
	for i in seg:
		indices.append_array([0, 1 + i, 2 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Tessellate this forest's highlight arc into disjoint segments appended to the
## shared _arc_pts buffer (drawn together as one multiline).
func _append_arc_segments(center: Vector2, mean_half: float, instance_id: String, coord: Vector2i) -> void:
	if not _circle_drawable(center, 10.0, coord):
		return
	var radius: float = maxf(10.0, mean_half * 0.55)
	var start: float = float(_seed(instance_id + "|arc") % 628) / 100.0
	var origin := center + Vector2(-2.0, -mean_half * 0.18)
	var steps := 14
	var prev := origin + Vector2(cos(start), sin(start)) * radius
	for i in range(1, steps + 1):
		var a := start + 1.7 * float(i) / float(steps)
		var p := origin + Vector2(cos(a), sin(a)) * radius
		_arc_pts.append(prev)
		_arc_pts.append(p)
		prev = p

## Build (and cache) the clipped draw list for one forest: canopy circles, the
## shadow radius and centre — water/hex clipping done once, reused on rebuild.
func _forest_draw_data(instance_id: String, tile_id: String, coord: Vector2i) -> Dictionary:
	if _draw_cache.has(instance_id):
		return _draw_cache[instance_id]
	var center: Vector2 = _forest_center(instance_id, tile_id, coord)
	var shape: Dictionary = ForestFootprint.shape_for(instance_id, tile_id, center)
	var mean_half: float = (float(shape.hw) + float(shape.hh)) * 0.5
	var base_lobes := _forest_base_lobes(instance_id, center, shape)
	var visible_circles: Array = []
	for circle in _forest_circles(instance_id, center, shape):
		if _circle_drawable(circle.pos, float(circle.r), coord):
			visible_circles.append(circle)
	if visible_circles.is_empty() and _circle_drawable(center, 18.0, coord):
		visible_circles.append({
			"pos": center,
			"r": 18.0,
			"aspect": 1.0,
			"rot": 0.0,
			"color": MapStyle.forest_base(),
		})
	visible_circles.sort_custom(_sort_circle_radius_desc)
	var data := {
		"circles": visible_circles,
		"shadow_r": mean_half * 0.92,
		"mean_half": mean_half,
		"center": center,
		"base_lobes": base_lobes,
	}
	_draw_cache[instance_id] = data
	return data

## World-space avoidance discs {center, radius} for every forest on `coord`,
## matching the drawn blob exactly (same _forest_center + circumscribing radius).
## The polygon building layout keeps footprints out of these so a building never
## lands under a canopy. Cheap — only the forests actually on this tile.
func discs_on_tile(coord: Vector2i) -> Array:
	var out: Array = []
	for key in _forests:
		var e: Dictionary = _forests[key]
		if (e.get("coord", Vector2i(-1, -1)) as Vector2i) != coord:
			continue
		var tid := str(e.get("tile_id", ""))
		var center := _forest_center(str(key), tid, coord)
		var shape := ForestFootprint.shape_for(str(key), tid, center)
		out.append({"center": center, "radius": float(shape.radius)})
	return out

func _forest_center(instance_id: String, tile_id: String, coord: Vector2i) -> Vector2:
	# Delegates to ForestFootprint so the drawn blob and the road/occupancy
	# obstacle disc can never diverge (roads-v2 spec section 1).
	_ensure_river_cache()
	var paths: Array = _river_paths_by_coord.get(coord, [])
	return ForestFootprint._center(instance_id, tile_id, _tile_center(coord), paths,
		_lake_for_coord(coord), _forest_neighbour_centers())

## World centres of every forested tile (cached), for the gravitate-toward pull.
func _forest_neighbour_centers() -> Array:
	if not _neighbour_dirty:
		return _neighbour_centers
	_neighbour_centers = []
	for key in _forests:
		var coord: Vector2i = (_forests[key] as Dictionary).get("coord", Vector2i(-1, -1))
		if terrain_layer != null and terrain_layer.tiles.has(coord):
			_neighbour_centers.append(_tile_center(coord))
	_neighbour_dirty = false
	return _neighbour_centers

func _lake_for_coord(coord: Vector2i) -> Dictionary:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return {}
	return RiverGeometry.lake_ellipse(terrain_layer.tiles[coord], terrain_layer.river_properties, _tile_center(coord))

func _sort_circle_radius_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("r", 0.0)) > float(b.get("r", 0.0))

func _forest_circles(instance_id: String, center: Vector2, shape: Dictionary) -> Array:
	# Place a cached canopy stamp (shape-local lobes) at this forest's centre and
	# rotation. The stamp is generated once per (shape kind, variant) and reused.
	var kind: String = str(shape.get("kind", "circle"))
	var rot: float = float(shape.get("rot", 0.0))
	var variant: int = abs(hash(instance_id)) % FOREST_PATTERN_VARIANTS
	var pattern: Array = _canopy_pattern(kind, variant, float(shape.hw), float(shape.hh))
	var base := MapStyle.forest_base()
	var dark := MapStyle.forest_lobe_dark()
	var circles: Array = []
	for lobe in pattern:
		circles.append({
			"pos": center + (lobe.off as Vector2).rotated(rot),
			"r": float(lobe.r),
			"aspect": float(lobe.aspect),
			"rot": float(lobe.rot) + rot,
			"color": base.lerp(dark, float(lobe.shade)),
		})
	return circles

func _forest_base_lobes(instance_id: String, center: Vector2, shape: Dictionary) -> Array:
	# Three overlapping, differently oriented ellipses form a low-frequency
	# irregular union. They are a wide/regional grouping device, never a second
	# occupancy shape, and fade out before close zoom.
	var hw := float(shape.hw)
	var hh := float(shape.hh)
	var rot := float(shape.get("rot", 0.0))
	var base := MapStyle.forest_base().lerp(MapStyle.forest_lobe_dark(), 0.06)
	var specs := [
		[-0.13, 0.04, 0.52, 0.70, -0.22],
		[0.17, -0.10, 0.46, 0.76, 0.28],
		[0.04, 0.18, 0.40, 0.68, 0.62],
	]
	var major := maxf(hw, hh)
	var minor := minf(hw, hh)
	var long_rot := rot + (PI * 0.5 if hh > hw else 0.0)
	var out: Array = []
	for i in specs.size():
		var spec: Array = specs[i]
		var local_off := Vector2(hw * float(spec[0]), hh * float(spec[1])).rotated(rot)
		var jitter := float(_seed("%s|base-rot|%d" % [instance_id, i]) % 181 - 90) / 900.0
		out.append({
			"pos": center + local_off,
			"r": major * float(spec[2]),
			"aspect": clampf((minor / maxf(major, 0.001)) * float(spec[3]), 0.42, 0.86),
			"rot": long_rot + float(spec[4]) + jitter,
			"color": base,
		})
	return out

func _canopy_pattern(kind: String, variant: int, hw: float, hh: float) -> Array:
	var key := "%s:%d" % [kind, variant]
	if _pattern_cache.has(key):
		return _pattern_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(key)
	var pattern: Array = []
	var y: float = -hh
	while y <= hh + 0.01:
		var x: float = -hw
		while x <= hw + 0.01:
			var lx: float = x + rng.randf_range(-FOREST_FILL_JITTER, FOREST_FILL_JITTER)
			var ly: float = y + rng.randf_range(-FOREST_FILL_JITTER, FOREST_FILL_JITTER)
			if _in_forest_shape(kind, lx, ly, hw, hh):
				pattern.append({
					"off": Vector2(lx, ly),
					"r": FOREST_LOBE * rng.randf_range(0.85, 1.18),
					# These values are ignored by every frozen legacy style. In
					# mid-century they break the repeated circular flower glyph while
					# remaining inside the same conservative lobe radius.
					"aspect": rng.randf_range(0.66, 0.91),
					"rot": rng.randf_range(-PI, PI),
					"shade": rng.randf_range(0.0, 0.28),
				})
			x += FOREST_FILL_STEP
		y += FOREST_FILL_STEP
	_pattern_cache[key] = pattern
	return pattern

func _in_forest_shape(kind: String, lx: float, ly: float, hw: float, hh: float) -> bool:
	match kind:
		"square", "rectangle":
			return absf(lx) <= hw and absf(ly) <= hh
		"patch":
			# chamfered/rounded rectangle
			if absf(lx) > hw or absf(ly) > hh:
				return false
			var cut: float = minf(hw, hh) * 0.5
			var ox: float = absf(lx) - (hw - cut)
			var oy: float = absf(ly) - (hh - cut)
			if ox > 0.0 and oy > 0.0:
				return ox * ox + oy * oy <= cut * cut
			return true
		"blob":
			var ang: float = atan2(ly, lx)
			var wob: float = 0.82 + 0.18 * sin(ang * 3.0 + 1.3) + 0.08 * sin(ang * 5.0 - 0.6)
			return (lx / hw) * (lx / hw) + (ly / hh) * (ly / hh) <= wob * wob
		_:  # circle
			return (lx / hw) * (lx / hw) + (ly / hh) * (ly / hh) <= 1.0

func _circle_drawable(pos: Vector2, radius: float, coord: Vector2i) -> bool:
	if not _inside_hex(pos, _tile_center(coord), 14.0):
		return false
	var clearance: float = radius + RIVER_HALF_WIDTH + _river_clearance_world()
	if _water_clearance_score(pos, coord) < clearance:
		return false
	return _clear_of_source_lake(pos, radius, coord)

func _water_clearance_score(point: Vector2, coord: Vector2i) -> float:
	var best: float = INF
	var paths: Array = _river_paths_by_coord.get(coord, [])
	for path_data in paths:
		var pts: PackedVector2Array = path_data
		for i in range(pts.size() - 1):
			best = minf(best, _distance_to_segment(point, pts[i], pts[i + 1]))
	return best

func _clear_of_source_lake(point: Vector2, radius: float, coord: Vector2i) -> bool:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return true
	var tile_data: Dictionary = terrain_layer.tiles[coord]
	if not bool(tile_data.get("has_river", false)):
		return true
	var river_type: String = str(tile_data.get("river_type", ""))
	if river_type == "" or not terrain_layer.river_properties.has(river_type):
		return true
	var river_data: Dictionary = terrain_layer.river_properties[river_type]
	if str(river_data.get("kind", "")) != "source":
		return true
	var lake_point: String = str(river_data.get("lake_point", "C0"))
	if not RIVER_POINTS.has(lake_point):
		return true
	var lake_offset: Vector2 = RIVER_POINTS[lake_point]
	var lake_center: Vector2 = _tile_center(coord) + lake_offset - TILE_CENTER
	var lake_w: float = _float_or_default(str(river_data.get("lake_width", "")), SOURCE_LAKE_DEFAULT_WIDTH)
	var lake_h: float = _float_or_default(str(river_data.get("lake_height", "")), SOURCE_LAKE_DEFAULT_HEIGHT)
	var clearance: float = _river_clearance_world() + radius
	var dx: float = (point.x - lake_center.x) / (lake_w * 0.5 + clearance)
	var dy: float = (point.y - lake_center.y) / (lake_h * 0.5 + clearance)
	return Vector2(dx, dy).length() >= 1.0

func _ensure_river_cache() -> void:
	if _river_cache_ready:
		return
	if river_visuals == null:
		river_visuals = get_node_or_null("../RiverVisuals")
	_river_paths_by_coord.clear()
	if river_visuals != null and river_visuals.has_method("get_river_polylines"):
		var river_paths: Array = river_visuals.call("get_river_polylines") as Array
		for entry in river_paths:
			var path_entry: Dictionary = entry as Dictionary
			var coord: Vector2i = path_entry.get("coord", Vector2i(-1, -1))
			if not _river_paths_by_coord.has(coord):
				_river_paths_by_coord[coord] = []
			var points: PackedVector2Array = path_entry.get("points", PackedVector2Array())
			_river_paths_by_coord[coord].append(points)
	_river_cache_ready = true

func _inside_hex(point: Vector2, tile_center: Vector2, margin: float) -> bool:
	var local: Vector2 = point - tile_center + TILE_CENTER
	var inset: PackedVector2Array = PackedVector2Array()
	for vertex in HEX_VERTS:
		var from_center: Vector2 = vertex - TILE_CENTER
		inset.append(TILE_CENTER + from_center.normalized() * maxf(0.0, from_center.length() - margin))
	return Geometry2D.is_point_in_polygon(local, inset)

func _tile_center(coord: Vector2i) -> Vector2:
	if terrain_layer == null:
		return Vector2.ZERO
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _river_clearance_world() -> float:
	var zoom_max: float = 1.0
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var value: Variant = cam.get("zoom_max")
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			zoom_max = maxf(float(value), 0.01)
	return RIVER_SCREEN_CLEARANCE_PX / zoom_max

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _seed(text: String) -> int:
	return abs(hash(text))

func _float_or_default(value: String, fallback: float) -> float:
	if value == "":
		return fallback
	return float(value)
