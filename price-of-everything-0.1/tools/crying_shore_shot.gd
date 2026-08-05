extends Node2D
## Load the REAL main scene and audit the Crying Shore urban tile (tile_3_8) at GAME START:
## render it, and measure every building footprint against the road centreline so a clash is
## reported as a number, not an impression.
##   Godot --path . res://tools/crying_shore_shot.tscn --quit-after 800   -> res://crying_shore.png
var _wm
var _bv
var _terrain
var _frame := 0
const TARGET := "tile_3_8"      # Crying Shore (urban)
const ROAD_CLEAR := 15.0        # BuildingVisuals.ROAD_CLEAR — the rule a footprint must satisfy

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	for _i in 14:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	_bv = _wm.get_node("%BuildingVisuals")
	var coord: Vector2i = _terrain.id_to_coord(TARGET)
	var center: Vector2 = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
	var td: Dictionary = _terrain.tiles.get(coord, {})
	var tmpl: Dictionary = _bv._tile_block_templates.get(TARGET, {})
	print("[CS] tile=%s type=%s block_mode=%s lots=%d rows=%s cell=%s" % [TARGET,
		str(td.get("type", "")), str(_bv._tile_block_mode.get(TARGET, "unset")),
		(tmpl.get("lots", []) as Array).size(), str(tmpl.get("rows", [])), str(tmpl.get("cell", Vector2.ZERO))])

	# Road segments crossing the tile, in tile-local coords (same space the mask uses).
	var segs: Array = _bv._block_road_segments(coord)
	print("[CS] road segments on tile: %d   buildings: %d" % [segs.size(), MatchState.get_buildings_on_tile(TARGET).size()])

	# Measure each placed footprint against every road segment.
	var worst := 1.0e9
	var clashes := 0
	for p in _bv._placements:
		if str(p.tile_id) != TARGET:
			continue
		var verts: PackedVector2Array = p.verts
		var d := 1.0e9
		for v in verts:
			var rel: Vector2 = v - center
			for s in segs:
				d = minf(d, _pt_seg(rel, s[0], s[1]))
		if d < 1.0e8:
			var tag := ""
			if d < ROAD_CLEAR:
				clashes += 1
				tag = "  <-- CLASH (under ROAD_CLEAR %.0f)" % ROAD_CLEAR
			if d < worst:
				worst = d
			# The DRAWN art is what the player sees, and it is sized from the footprint
			# but floored at ART_DRAWN_MIN — so measure it too, not just the polygon.
			var da := _art_dist(p, center, segs)
			print("[CS] %s cat=%s npc=%s  footprint=%.1f  drawn_art=%.1f%s" % [
				str(p.instance_id), str(p.cat), str(p.is_npc), d, da, tag])
	print("[CS] RESULT clashes=%d worst_dist=%.1f (rule: every footprint >= %.0f)" % [clashes, worst, ROAD_CLEAR])

	var cam := Camera2D.new()
	cam.position = center
	cam.zoom = Vector2(1.9, 1.9)
	add_child(cam)
	cam.make_current()

## Closest approach of the DRAWN art box to a road, mirroring _draw_ink_art's sizing
## (long art side scaled to `target`, art-local x along the footprint's first edge).
func _art_dist(p: Dictionary, center: Vector2, segs: Array) -> float:
	var key: String = _bv.INK_ART_KEY.get(str(p.get("iname", "")), "")
	if key == "":
		return -1.0
	var verts: PackedVector2Array = p.verts
	var dir: Vector2 = (verts[1] - verts[0]).normalized()
	var ctr := Vector2.ZERO
	for v in verts:
		ctr += v
	ctr /= float(verts.size())
	var dmax := 0.0
	var nmax := 0.0
	for v in verts:
		var r: Vector2 = v - ctr
		dmax = maxf(dmax, absf(r.dot(dir)))
		nmax = maxf(nmax, absf(r.dot(Vector2(-dir.y, dir.x))))
	var target: float = clampf(minf(_bv._art_size_for(int(p.get("size_units", 1)), key), maxf(dmax, nmax) * 2.0), 40.0, 90.0)
	var frame: Vector2 = InkBuildingGen.level_frame(key, 3)
	var s: float = target / maxf(frame.x, frame.y)
	var ahx := frame.x * s * 0.5
	var ahy := frame.y * s * 0.5
	var perp := Vector2(-dir.y, dir.x)
	var d := 1.0e9
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = ctr + dir * (ahx * sx) + perp * (ahy * sy) - center
			for sg in segs:
				d = minf(d, _pt_seg(corner, sg[0], sg[1]))
	return d

func _pt_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _process(_d: float) -> void:
	# Must outlast the 14 frames _ready() awaits — _process ticks independently of the
	# coroutine, so quitting too early kills the audit before it prints.
	_frame += 1
	if _frame == 30:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://crying_shore.png")
		print("SAVED crying_shore.png")
		get_tree().quit()
