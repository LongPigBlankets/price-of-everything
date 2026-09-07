extends Node2D
## Look-dev: do the Blender PLAN renders fit inside the footprints they would have to live in?
##
## A fake tile — one hex, one road down the middle — laid out with COPIES OF REAL hijack-marked
## masses taken from the live document across the whole size range, each with a building's
## top-down render fitted inside it. Nothing here touches the game: it loads the sample
## polygons and the PNGs off disk, so it boots in a second and cannot be perturbed by the map.
##
##   <godot> --path . res://tools/plan_fit_lab.tscn --quit-after 400 -- --building=factory
##
## The question it answers is ASPECT. A mass is roughly square (the fabric draws terraces); a
## factory's plan is 1:2.2. Fitting one inside the other while preserving aspect is what leaves
## the dead space this scene is built to show.

const SAMPLES := "/private/tmp/claude-501/-Users-crisu-Price-of-Everything/bade1260-d5e3-4249-b6a6-9c20c8834b16/scratchpad/hijack_samples.json"
const PLANS := "/Users/crisu/Price of Everything/blender-assets/renders/plan/"

# Sampled off the shipped midcentury map so this reads like the real thing without booting it.
const GROUND := Color("8ea25e")
const GROUND_DARK := Color("7d9152")
const ROAD := Color("ecdcb0")
const ROAD_INK := Color("d9c79a")
const MASS := Color("6f6a5c")
const MASS_LIT := Color("7d7768")
const INK := Color("31302a")
const LABEL := Color("f2eee2")

const TILE_W := 540.0
const TILE_H := 480.0
const ROAD_W := 18.0            # AuthoredMap.ROAD_WIDTHS "mid"

var _samples: Array = []
var _plan: Texture2D = null
var _plan_size := Vector2.ZERO
var _building := "factory"
var _scale := 2.4
var _font: Font = null
var _fits: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--building="):
			_building = a.trim_prefix("--building=")
	var text := FileAccess.get_file_as_string(SAMPLES)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("[LAB] could not read %s" % SAMPLES); get_tree().quit(1); return
	_samples = parsed
	var image := Image.load_from_file(PLANS + _building + "_lvl2.png")
	if image == null:
		push_error("[LAB] no plan render for %s" % _building); get_tree().quit(1); return
	image.fix_alpha_edges()
	_plan = ImageTexture.create_from_image(image)
	# The render is padded transparency; what matters is the INKED extent, so measure it.
	_plan_size = _opaque_extent(image)
	_font = ThemeDB.fallback_font
	DisplayServer.window_set_size(Vector2i(1800, 1500))
	await get_tree().process_frame
	queue_redraw()
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "/tmp/poe_plan_fit_%s.png" % _building
	get_viewport().get_texture().get_image().save_png(path)
	print("[LAB] %s: plan opaque extent %.0fx%.0f px (aspect %.2f)" % [
		_building, _plan_size.x, _plan_size.y, _plan_size.x / maxf(_plan_size.y, 1.0)])
	for row in _fits:
		print("[LAB]   %-20s area=%6.0f  bbox=%5.1fx%5.1f  sprite fits %5.1fx%5.1f  = %4.1f%% of the mass" % [
			str(row.id), float(row.area), float(row.bw), float(row.bh),
			float(row.sw), float(row.sh), 100.0 * float(row.sw) * float(row.sh) / maxf(float(row.area), 1.0)])
	print("[LAB] saved ", path)
	get_tree().quit(0)


## The bounding box of everything non-transparent, in pixels — the render's real footprint
## inside its padded canvas.
func _opaque_extent(image: Image) -> Vector2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var w := image.get_width()
	var h := image.get_height()
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if image.get_pixel(x, y).a > 0.02:
				lo = Vector2(minf(lo.x, x), minf(lo.y, y))
				hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
	return (hi - lo) if hi.x > lo.x else Vector2(image.get_width(), image.get_height())


func _draw() -> void:
	var origin := Vector2(900, 760)
	draw_set_transform(origin, 0.0, Vector2(_scale, _scale))
	# --- the tile: a flat-top hex, the size the game uses -------------------------------
	var hex := PackedVector2Array([
		Vector2(-TILE_W * 0.5, 0.0), Vector2(-TILE_W * 0.25, -TILE_H * 0.5),
		Vector2(TILE_W * 0.25, -TILE_H * 0.5), Vector2(TILE_W * 0.5, 0.0),
		Vector2(TILE_W * 0.25, TILE_H * 0.5), Vector2(-TILE_W * 0.25, TILE_H * 0.5)])
	draw_colored_polygon(hex, GROUND)
	var closed := hex.duplicate(); closed.append(hex[0])
	draw_polyline(closed, INK, 1.2, true)
	# --- the road down the middle -------------------------------------------------------
	var road := PackedVector2Array([
		Vector2(-ROAD_W * 0.5 - 1.5, -TILE_H * 0.5), Vector2(ROAD_W * 0.5 + 1.5, -TILE_H * 0.5),
		Vector2(ROAD_W * 0.5 + 1.5, TILE_H * 0.5), Vector2(-ROAD_W * 0.5 - 1.5, TILE_H * 0.5)])
	draw_colored_polygon(road, ROAD_INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-ROAD_W * 0.5, -TILE_H * 0.5), Vector2(ROAD_W * 0.5, -TILE_H * 0.5),
		Vector2(ROAD_W * 0.5, TILE_H * 0.5), Vector2(-ROAD_W * 0.5, TILE_H * 0.5)]), ROAD)
	# --- the masses, either side of the road, biggest first ------------------------------
	_fits.clear()
	var left_y := -TILE_H * 0.5 + 20.0
	var right_y := -TILE_H * 0.5 + 20.0
	var i := 0
	for row_value in _samples:
		var row: Dictionary = row_value
		var verts := PackedVector2Array()
		for p in (row.get("verts", []) as Array):
			verts.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
		if verts.size() < 3:
			continue
		var bw := float(row.get("w", 0.0))
		var bh := float(row.get("h", 0.0))
		var left := i % 2 == 0
		var y: float = left_y if left else right_y
		var cx: float = (-ROAD_W * 0.5 - 12.0 - bw * 0.5) if left else (ROAD_W * 0.5 + 12.0 + bw * 0.5)
		var at := Vector2(cx, y + bh * 0.5)
		if left:
			left_y += bh + 12.0
		else:
			right_y += bh + 12.0
		i += 1
		var placed := PackedVector2Array()
		for v in verts:
			placed.append(v + at)
		# the mass, in the fabric's own language: shadow, wash, ink
		draw_colored_polygon(_offset(placed, Vector2(2.0, 2.4)), Color(0, 0, 0, 0.18))
		draw_colored_polygon(placed, MASS if i % 2 == 0 else MASS_LIT)
		var ring := placed.duplicate(); ring.append(placed[0])
		draw_polyline(ring, INK, 1.4, true)
		# The plan render, fitted INSIDE the polygon at its own aspect and ALONG THE MASS'S
		# OWN AXIS. An axis-aligned search is the wrong question: every mass sits at its
		# street's angle, so a world-aligned rectangle inside a rotated terrace collapses to a
		# sliver, and the building would too.
		var fit := _fit_oriented(placed, _plan_size.x / maxf(_plan_size.y, 1.0))
		var size: Vector2 = fit.get("size", Vector2.ZERO)
		if size.x > 1.0:
			draw_set_transform(origin + (fit["centre"] as Vector2) * _scale, float(fit["angle"]),
				Vector2(_scale, _scale))
			draw_texture_rect(_plan, Rect2(-size * 0.5, size), false, Color(1, 1, 1, 1))
			draw_rect(Rect2(-size * 0.5, size), Color(1, 0.35, 0.2, 0.55), false, 0.6)
			draw_set_transform(origin, 0.0, Vector2(_scale, _scale))
		_fits.append({"id": row.get("id", "?"), "area": row.get("area", 0.0),
			"bw": bw, "bh": bh, "sw": size.x, "sh": size.y})
		draw_set_transform(origin, 0.0, Vector2(_scale, _scale) * 0.34)
		draw_string(_font, (at + Vector2(-bw * 0.5, -bh * 0.5 - 3.0)) / 0.34,
			"%.0f u²" % float(row.get("area", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, LABEL)
		draw_set_transform(origin, 0.0, Vector2(_scale, _scale))
	# --- caption -------------------------------------------------------------------------
	draw_set_transform(Vector2(24, 34), 0.0, Vector2.ONE)
	draw_string(_font, Vector2.ZERO, "PLAN FIT — %s L2 in real hijack masses (red = fitted sprite rect, aspect preserved)"
		% _building.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, LABEL)


## The largest rectangle of `aspect` that fits inside `poly`, ALIGNED TO THE MASS and free to
## sit anywhere inside it. Returns {centre, angle, size}.
##
## Two things the naive version got wrong and this does not: the rectangle follows the
## polygon's own long axis rather than the world axes, and its centre is searched rather than
## assumed — a centroid lies OUTSIDE a C- or V-shaped mass, and those exist in the document.
func _fit_oriented(poly: PackedVector2Array, aspect: float) -> Dictionary:
	var best := {"centre": Vector2.ZERO, "angle": 0.0, "size": Vector2.ZERO}
	for angle in _candidate_angles(poly):
		var local := PackedVector2Array()
		for p in poly:
			local.append(p.rotated(-angle))
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in local:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		# Candidate centres on a grid across the local bbox, so a concave mass can still host
		# the rectangle in one of its arms.
		for gx in range(1, 8):
			for gy in range(1, 8):
				var c := Vector2(lerpf(lo.x, hi.x, gx / 8.0), lerpf(lo.y, hi.y, gy / 8.0))
				if not Geometry2D.is_point_in_polygon(c, local):
					continue
				var low := 0.0
				var high := maxf(hi.y - lo.y, hi.x - lo.x)
				for _i in 16:
					var mid := (low + high) * 0.5
					if _rect_inside(local, c, Vector2(mid * aspect, mid)):
						low = mid
					else:
						high = mid
				var size := Vector2(low * aspect, low)
				if size.x * size.y > float((best["size"] as Vector2).x) * float((best["size"] as Vector2).y):
					best = {"centre": c.rotated(angle), "angle": angle, "size": size}
	return best


## Orientations worth trying: every edge direction (a terrace's long wall is its street), plus
## the world axes as a fallback for a mass with no dominant edge.
func _candidate_angles(poly: PackedVector2Array) -> Array:
	var out: Array = [0.0]
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > 2.0:
			out.append(e.angle())
	return out


func _rect_inside(poly: PackedVector2Array, centre: Vector2, size: Vector2) -> bool:
	var h := size * 0.5
	for sx in [-1.0, 0.0, 1.0]:
		for sy in [-1.0, 0.0, 1.0]:
			var p := centre + Vector2(h.x * sx, h.y * sy)
			if not Geometry2D.is_point_in_polygon(p, poly):
				return false
	return true


func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out
