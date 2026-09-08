extends Node2D
## Look-dev: a REAL neighbourhood, not a size ladder. Reads an actual contiguous cluster of
## hijack masses (their true world outlines and the real road strokes between them, pulled
## straight from the document) and fits each building's plan render into each mass at the
## game's own near-LOD scale. The question the ladder could not answer: does a STREET of grey
## roofs read as a town, or as porridge.
##
##   <godot> --path . res://tools/plan_street_lab.tscn --quit-after 700 -- --building=factory

const CLUSTER := "/private/tmp/claude-501/-Users-crisu-Price-of-Everything/bade1260-d5e3-4249-b6a6-9c20c8834b16/scratchpad/street_cluster.json"
const PLANS := "/Users/crisu/Price of Everything/blender-assets/renders/plan/"

const GROUND := Color("8ea25e")
const ROAD := Color("ecdcb0")
const ROAD_CASE := Color("d9c79a")
const MASS := Color("6f6a5c")
const INK := Color("31302a")
const LABEL := Color("f2eee2")
const NEAR_PPU := 2.008           # the game's max-zoom logical px/world-unit at base 1920

var _building := "factory"
var _plan: Texture2D = null
var _plan_aspect := 1.0
var _cluster: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--building="):
			_building = a.trim_prefix("--building=")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLUSTER))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[STREET] no cluster"); get_tree().quit(1); return
	_cluster = parsed
	var image := Image.load_from_file(PLANS + _building + "_lvl2.png")
	if image == null:
		push_error("[STREET] no plan for %s" % _building); get_tree().quit(1); return
	image.fix_alpha_edges()
	var ext := _opaque_extent(image)
	_plan_aspect = ext.x / maxf(ext.y, 1.0)
	_plan = ImageTexture.create_from_image(image)
	_font = ThemeDB.fallback_font
	DisplayServer.window_set_size(Vector2i(1900, 1500))
	await get_tree().process_frame
	queue_redraw()
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "/tmp/poe_plan_street_%s.png" % _building
	get_viewport().get_texture().get_image().save_png(path)
	print("[STREET] %s: %d masses at NEAR_PPU %.2f, saved %s" % [
		_building, (_cluster.get("masses", []) as Array).size(), NEAR_PPU, path])
	get_tree().quit(0)


func _opaque_extent(image: Image) -> Vector2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > 0.02:
				lo = Vector2(minf(lo.x, x), minf(lo.y, y)); hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
	return (hi - lo) if hi.x > lo.x else Vector2(image.get_size())


func _draw() -> void:
	var centre_arr: Array = _cluster.get("centre", [0, 0])
	var world_centre := Vector2(float(centre_arr[0]), float(centre_arr[1]))
	# Draw at the near-LOD scale the game reaches at max zoom, so the sizes here are the sizes
	# a player sees. The window shows a ~950/NEAR_PPU u wide slice of the world.
	var screen_centre := Vector2(950, 750)
	draw_set_transform(screen_centre, 0.0, Vector2(NEAR_PPU, NEAR_PPU))
	var W := (get_viewport_rect().size / NEAR_PPU)
	draw_rect(Rect2(-W * 0.5 - world_centre + screen_centre / NEAR_PPU, W), GROUND)  # ground fill, roughly
	# roads (real strokes)
	for road_value in (_cluster.get("roads", []) as Array):
		var road: Dictionary = road_value
		var pts := PackedVector2Array()
		for p in (road.get("points", []) as Array):
			pts.append(Vector2(float((p as Array)[0]), float((p as Array)[1])) - world_centre)
		if pts.size() >= 2:
			draw_polyline(pts, ROAD_CASE, 22.0, true)
			draw_polyline(pts, ROAD, 16.0, true)
	# masses + fitted plan sprites
	for mass_value in (_cluster.get("masses", []) as Array):
		var mass: Dictionary = mass_value
		var world := PackedVector2Array()
		for p in (mass.get("outline", []) as Array):
			world.append(Vector2(float((p as Array)[0]), float((p as Array)[1])) - world_centre)
		if world.size() < 3:
			continue
		draw_colored_polygon(_offset(world, Vector2(1.6, 2.0)), Color(0, 0, 0, 0.16))
		draw_colored_polygon(world, MASS)
		var ring := world.duplicate(); ring.append(world[0])
		draw_polyline(ring, INK, 1.2, true)
		var fit := _fit_oriented(world, _plan_aspect)
		var size: Vector2 = fit.get("size", Vector2.ZERO)
		if size.x > 1.0:
			draw_set_transform(screen_centre + (fit["centre"] as Vector2) * NEAR_PPU,
				float(fit["angle"]), Vector2(NEAR_PPU, NEAR_PPU))
			draw_texture_rect(_plan, Rect2(-size * 0.5, size), false)
			draw_set_transform(screen_centre, 0.0, Vector2(NEAR_PPU, NEAR_PPU))
	draw_set_transform(Vector2(24, 34), 0.0, Vector2.ONE)
	draw_string(_font, Vector2.ZERO, "REAL STREET (Arin) — %s L2 in %d actual masses, at max-zoom scale"
		% [_building.to_upper(), (_cluster.get("masses", []) as Array).size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, LABEL)


func _fit_oriented(poly: PackedVector2Array, aspect: float) -> Dictionary:
	var best := {"centre": Vector2.ZERO, "angle": 0.0, "size": Vector2.ZERO}
	for angle in _angles(poly):
		var local := PackedVector2Array()
		for p in poly:
			local.append(p.rotated(-angle))
		var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
		for p in local:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		for gx in range(1, 8):
			for gy in range(1, 8):
				var c := Vector2(lerpf(lo.x, hi.x, gx / 8.0), lerpf(lo.y, hi.y, gy / 8.0))
				if not Geometry2D.is_point_in_polygon(c, local):
					continue
				var low := 0.0; var high := maxf(hi.y - lo.y, hi.x - lo.x)
				for _i in 16:
					var mid := (low + high) * 0.5
					if _rect_inside(local, c, Vector2(mid * aspect, mid)): low = mid
					else: high = mid
				var size := Vector2(low * aspect, low)
				if size.x * size.y > (best["size"] as Vector2).x * (best["size"] as Vector2).y:
					best = {"centre": c.rotated(angle), "angle": angle, "size": size}
	return best


func _angles(poly: PackedVector2Array) -> Array:
	var out: Array = [0.0]
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > 2.0: out.append(e.angle())
	return out


func _rect_inside(poly: PackedVector2Array, c: Vector2, size: Vector2) -> bool:
	var h := size * 0.5
	for sx in [-1.0, 0.0, 1.0]:
		for sy in [-1.0, 0.0, 1.0]:
			if not Geometry2D.is_point_in_polygon(c + Vector2(h.x * sx, h.y * sy), poly):
				return false
	return true


func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(p + by)
	return out
