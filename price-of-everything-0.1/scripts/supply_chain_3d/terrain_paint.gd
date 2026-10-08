extends RefCounted
## Plan-space artwork, never a camera-angle bake. All three tiers preserve exact
## source contours, beaches, riverbanks and deterministic surface marks.
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const EXTENT := Vector2(548, 488) # four-unit gutter prevents filtered seams at hex borders

class Painter extends Node2D:
	var relief: Dictionary
	var tile: Dictionary
	var rivers: Array
	var mines: Array
	func _draw() -> void:
		var sea := MapStyle.sea_colors()
		var bands := MapStyle.band_colors()
		var ocean := str(tile.type) in ["sea", "deep_sea"]
		draw_rect(Rect2(tile.center - EXTENT * 0.5, EXTENT), sea[0 if str(tile.type) == "deep_sea" else 2] if ocean else Legacy._warm(sea[5]))
		for e in relief.get("sea", []): _polygon(e.p, sea[int(e.b)])
		if not ocean:
			for e in relief.get("land", []): _polygon(e.p, Legacy._warm(bands[clampi(int(e.b), 0, bands.size() - 1)]))
		for p in relief.get("lakes", []): _polygon(p, sea[4])
		# The original board's layered beach, wet sand, foam and shallow water.
		var shore := Legacy._shore_of(relief, Model.hex_points(tile.center))
		for band in [[13.0, 30.0, sea[4].lightened(0.14)], [5.85, 18.0, sea[4].lightened(0.3)],
				[-7.5, 15.0, Legacy._SAND], [0.6, 3.4, Legacy._SAND.darkened(0.16)], [2.6, 1.1, Legacy._FOAM]]:
			for edge in shore:
				var shift: Vector2 = edge[2] * float(band[0])
				var a: Vector2 = edge[0] + shift
				var b: Vector2 = edge[1] + shift
				draw_line(a, b, band[2], float(band[1]), true)
				draw_circle(a, float(band[1]) * 0.5, band[2], true, -1, true)
				draw_circle(b, float(band[1]) * 0.5, band[2], true, -1, true)
		for lake in relief.get("lakes", []):
			var ring: PackedVector2Array = lake.duplicate()
			ring.append(ring[0])
			draw_polyline(ring, Legacy._SAND.darkened(0.08), 4.0, true)
			draw_polyline(ring, sea[4].lightened(0.3), 1.6, true)
		for rec in rivers:
			var path: PackedVector2Array = rec.points
			if path.size() < 2: continue
			var width := (float(rec.start_width) + float(rec.end_width)) * 0.5
			draw_polyline(path, Legacy._BANK, width + 5.0, true)
			draw_polyline(path, sea[4], width, true)
			draw_polyline(path, sea[4].lightened(0.16), width * 0.46, true)
			for side in [-1.0, 1.0]:
				draw_polyline(Legacy._beside(path, width * 0.5 * side), Legacy._INK_SOFT, 0.65, true)
		# Same seed in every tier: low tiers integrate marks instead of changing geography.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(tile.center))
		for i in 1300:
			var p: Vector2 = tile.center + Vector2(rng.randf_range(-274, 274), rng.randf_range(-244, 244))
			if Ground.is_water(relief, p):
				if i % 6 == 0: draw_line(p, p + Vector2(3.5, 0.6), Color(0.95, 0.95, 0.80, 0.18), 0.4, true)
			else:
				var ink := Color(0.24, 0.30, 0.18, rng.randf_range(0.045, 0.10))
				draw_line(p, p + Vector2(0.6, -rng.randf_range(0.5, 1.8)), ink, 0.32, true)
		# The source board's two ragged rings of worked earth, now baked in plan
		# around the real opening rather than painted over unbroken terrain.
		for mine in mines:
			rng.seed = int(mine.seed)
			for ring in [[0.62, Legacy._MINE_EARTH_EDGE], [0.54, Legacy._MINE_EARTH]]:
				var patch := PackedVector2Array()
				for i in 22:
					var angle := TAU * i / 22.0
					patch.append((mine.pos as Vector2) + Vector2(cos(angle), sin(angle)) * float(mine.side) * float(ring[0]) * rng.randf_range(0.9, 1.08))
				_polygon(patch, ring[1])

	func _polygon(points: PackedVector2Array, color: Color) -> void:
		# Source clipping can leave touching loops or repeated vertices. Merge through
		# the polygon clipper, and submit explicit triangles rather than asking Canvas
		# to triangulate a self-touching contour.
		var clean := PackedVector2Array()
		for p in points:
			if clean.is_empty() or not p.is_equal_approx(clean[-1]): clean.append(p)
		if clean.size() > 1 and clean[0].is_equal_approx(clean[-1]): clean.remove_at(clean.size() - 1)
		if clean.size() < 3: return
		var parts: Array[PackedVector2Array] = [clean]
		if Geometry2D.triangulate_polygon(clean).is_empty(): parts = Geometry2D.offset_polygon(clean, 0.01)
		for part in parts:
			var indices := Geometry2D.triangulate_polygon(part)
			if indices.is_empty(): continue
			var colors := PackedColorArray([color])
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, part, colors, PackedVector2Array())

static func bake(host: Node, tile: Dictionary, relief: Dictionary, rivers: Array, mines: Array = []) -> Array:
	var textures: Array = []
	if DisplayServer.get_name() == "headless":
		# Dummy renderer cannot read a viewport. Geometry and input tests still run.
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Legacy._warm(MapStyle.band_colors()[2]))
		for i in 3: textures.append(ImageTexture.create_from_image(image))
		return textures
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 1824)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(viewport)
	var painter := Painter.new()
	painter.tile = tile
	painter.relief = relief
	painter.rivers = rivers
	painter.mines = mines
	var scale := Vector2(viewport.size) / EXTENT
	painter.scale = scale
	painter.position = -(tile.center - EXTENT * 0.5) * scale
	viewport.add_child(painter)
	# force_draw also works while the game window is covered by the user's app.
	await host.get_tree().process_frame
	RenderingServer.force_draw(false)
	var source := viewport.get_texture().get_image()
	if source != null and not source.is_empty():
		for width in Detail.TEXTURES:
			var image := source.duplicate() as Image
			image.resize(width, roundi(width * EXTENT.y / EXTENT.x), Image.INTERPOLATE_LANCZOS)
			image.generate_mipmaps()
			textures.append(ImageTexture.create_from_image(image))
	viewport.queue_free()
	return textures
