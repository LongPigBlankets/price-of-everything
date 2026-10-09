extends RefCounted
## Plan-space artwork, never a camera-angle bake. All three tiers preserve exact
## source contours, beaches, riverbanks and deterministic surface marks.
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const WaterArt := preload("res://scripts/supply_chain_3d/water_art.gd")
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const EXTENT := Vector2(548, 488) # four-unit gutter prevents filtered seams at hex borders

class Painter extends Node2D:
	var relief: Dictionary
	var tile: Dictionary
	var rivers: Array
	var mines: Array
	var water_art: ArrayMesh
	func _draw() -> void:
		var sea := MapStyle.sea_colors()
		var bands := MapStyle.band_colors()
		var ocean := str(tile.type) in ["sea", "deep_sea"]
		draw_rect(Rect2(tile.center - EXTENT * 0.5, EXTENT), sea[0 if str(tile.type) == "deep_sea" else 2] if ocean else Legacy._warm(sea[5]))
		for e in relief.get("sea", []): _polygon(e.p, sea[int(e.b)])
		if not ocean:
			for e in relief.get("land", []): _polygon(e.p, Legacy._warm(bands[clampi(int(e.b), 0, bands.size() - 1)]))
		for p in relief.get("lakes", []): _polygon(p, sea[4])
		if water_art != null and water_art.get_surface_count() > 0: draw_mesh(water_art, null)
		# Same seed in every tier: low tiers integrate marks instead of changing geography.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(tile.center))
		for i in 1300:
			var p: Vector2 = tile.center + Vector2(rng.randf_range(-274, 274), rng.randf_range(-244, 244))
			if Ground.is_water(relief, p):
				continue # Water glints are animated on the actual surface, as in the source view.
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

static func bake(host: Node, tile: Dictionary, relief: Dictionary, rivers: Array, mines: Array, height: Callable) -> Array:
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
	var water := WaterArt.new()
	painter.water_art = water.artwork(tile, relief, rivers, height)
	water.free()
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
