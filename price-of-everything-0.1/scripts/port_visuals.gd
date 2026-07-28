extends Node2D
## Port dockhouse glyphs: every port tile (data/ports.csv) gets a large white
## harbour building hugging its sea-facing edge, with rectangular pier fingers
## sticking out into the sea. Static decoration — geometry computed once in
## setup(), drawn once, no _process (CLAUDE.md rule #2).

## Dockhouse/pier/outline colors live in MapStyle ('toggle ink' swaps them).
# The dockhouse reads ~40 screen px thick at max zoom: max zoom frames ~2.5
# tile-heights per ~1080px viewport, so 40px ≈ 0.09 tile heights.
const THICKNESS_FRAC := 0.09
const LENGTH_FRAC := 0.52      # dockhouse length along the shore, in tile heights
const PIER_LEN_FRAC := 0.30    # how far the pier fingers reach into the sea
const PIER_COUNT := 3

var _glyphs: Array = []   # [{pos: Vector2, angle: float, tile_h: float}]

func _ready() -> void:
	MapStyle.style_changed.connect(queue_redraw)

func setup(hex_map: TileMapLayer) -> void:
	_glyphs.clear()
	var tile_h := float(hex_map.tile_set.tile_size.y)
	for p in Catalog.all_ports():
		var coord: Vector2i = hex_map.id_to_coord(str(p.get("tile_id", "")))
		if coord == Vector2i(-1, -1) or not hex_map.tiles.has(coord):
			continue
		var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
		var center: Vector2 = hex_map.map_to_local(cell)
		# Face the first sea neighbour — ports sit on the coast by construction.
		var sea_dir := Vector2.ZERO
		for ncell in hex_map.get_surrounding_cells(cell):
			var ntile: Dictionary = hex_map.tiles.get(hex_map.tile_coord_for_map_coord(ncell), {})
			if str(ntile.get("type", "")) in ["sea", "deep_sea"]:
				sea_dir = (hex_map.map_to_local(ncell) - center).normalized()
				break
		if sea_dir == Vector2.ZERO:
			continue   # no adjacent sea — nothing sensible to draw
		_glyphs.append({
			"pos": to_local(hex_map.to_global(center + sea_dir * tile_h * 0.30)),
			"angle": sea_dir.angle(),
			"tile_h": tile_h,
		})
	queue_redraw()

func _draw() -> void:
	if MapStyle.ink:
		# Ink mode: the shape-language port (quay spine + warehouses +
		# container stacks + plank piers + jib cranes), world-lit like every
		# other generated building. Ports are neutral infrastructure -> npc
		# tint off.
		# Anchor design-space (74, 78) — the quay spine's seaward edge — at the
		# glyph position on the shoreline, so the spine hugs the coast and the
		# three piers reach out to sea (owner ruling; -20% size).
		for g in _glyphs:
			InkBuildingGen.draw(self, "port", 1, g["pos"] as Vector2, float(g["angle"]), float(g["tile_h"]) * 0.44, false, Vector2(74, 78))
		return
	var dockhouse := MapStyle.port_dockhouse()
	var outline := MapStyle.port_outline()
	var pier := MapStyle.port_pier()
	for g in _glyphs:
		var tile_h: float = g["tile_h"]
		var thick := tile_h * THICKNESS_FRAC
		var b_len := tile_h * LENGTH_FRAC
		var pier_len := tile_h * PIER_LEN_FRAC
		var pier_w := thick * 0.45
		# Local +x points seaward; the dockhouse slab sits on the land side of
		# the origin, the piers finger out into the water.
		draw_set_transform(g["pos"] as Vector2, float(g["angle"]), Vector2.ONE)
		for i in range(PIER_COUNT):
			var t := (float(i) - float(PIER_COUNT - 1) / 2.0) / float(PIER_COUNT)
			var y := t * b_len * 0.8 - pier_w * 0.5
			draw_rect(Rect2(Vector2(0.0, y), Vector2(pier_len, pier_w)), pier, true)
			draw_rect(Rect2(Vector2(0.0, y), Vector2(pier_len, pier_w)), outline, false, tile_h * 0.008)
			if MapStyle.ink:
				# Timber read: plank tick hairlines across each finger.
				var plank := MapStyle.pier_plank_color()
				var px := 5.0
				while px < pier_len - 2.0:
					draw_line(Vector2(px, y), Vector2(px, y + pier_w), plank, 0.9, true)
					px += 6.0
		draw_rect(Rect2(Vector2(-thick, -b_len * 0.5), Vector2(thick, b_len)), dockhouse, true)
		draw_rect(Rect2(Vector2(-thick, -b_len * 0.5), Vector2(thick, b_len)), outline, false, tile_h * 0.012)
	draw_set_transform_matrix(Transform2D.IDENTITY)
