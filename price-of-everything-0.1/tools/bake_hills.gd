extends Node
## Offline hill bake. Run headless:
##     <godot> --headless res://tools/bake_hills.tscn
## Generates the hill field for ALL hill tiles via HillField and writes the
## canonical cache to data/hills_baked.json (polygons in paint order + blocked
## subtile masks + a source hash for staleness detection). Re-run after any
## edit to tile_properties.csv / river_properties.csv — the iteration loop is:
## bake -> inspect blocked report -> retype unsuitable tiles in the CSV -> bake.

@onready var terrain: HexMap = %TerrainLayer
@onready var river_visuals: Node2D = %RiverVisuals

func _ready() -> void:
	await get_tree().process_frame   # let TerrainLayer/_RiverVisuals _ready run
	var started := Time.get_ticks_msec()
	# playable tiles + the decorative border cells painted straight into the
	# TileMapLayer (north scenery, sea frame) so the heightmap covers them too
	var tiles_all := {}
	var centers := {}
	for coord in terrain.tiles:
		tiles_all[coord] = terrain.tiles[coord]
		centers[coord] = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var deco := 0
	for cell in terrain.get_used_cells():
		var tc: Vector2i = terrain.tile_coord_for_map_coord(cell)
		if terrain.tiles.has(tc):
			continue
		var ttype: String = terrain._tile_type_for_source(terrain.get_cell_source_id(cell))
		if ttype == "":
			continue
		tiles_all[tc] = {"id": "deco_%d_%d" % [tc.x, tc.y], "type": ttype, "has_river": false}
		centers[tc] = terrain.map_to_local(cell)
		deco += 1
	print("bake_hills: %d decorative border tiles included" % deco)
	var rivers: Array = []
	for entry in river_visuals.get_river_polylines():
		rivers.append(entry.points)
	var lakes := _collect_lakes()
	print("bake_hills: %d tiles, %d river polylines, %d lakes" % [tiles_all.size(), rivers.size(), lakes.size()])
	var result := HillField.generate(tiles_all, centers, rivers, lakes, HillBaked.SEED)
	_write_json(result)
	print("bake_hills: %d massifs, %d polys, %d tiles with blocked subtiles (%.1fs)" % [
		result.massifs.size(), result.polys.size(), result.blocked.size(),
		(Time.get_ticks_msec() - started) / 1000.0])
	print("bake_hills: ms loops closed=%d open=%d raw_kept_input=%d" % [HillField.debug_closed, HillField.debug_open_chains, HillField.debug_raw_loops])
	print("bake_hills: grid=%s field_max=%.2f depression_subtiles=%.1f (budget %d)" % [
		str(result.grid), result.field_max, result.depression_subtiles, int(HillField.DEPRESSION_BUDGET)])
	print("bake_hills: %d lake polys, %d sea polys, %d islands, %d river mouths" % [
		result.lakes.size(), result.sea.size(), result.islands, result.river_mouths])
	for ls in result.lake_stats:
		print("  lake (%d tiles) rim lv%d exit_via_existing_river=%s" % [ls.tiles, ls.rim_lv, str(ls.has_exit)])
	for ms in result.massifs:
		print("  massif %s mtns=%s knolls=%d" % [str(ms.tiles), str(ms.mtns), ms.knolls])
	print("---- blocked report (drive map tuning with this) ----")
	print(HillField.blocked_report(result))
	get_tree().quit(0)

func _collect_lakes() -> Array:
	var lakes: Array = []
	for coord in terrain.tiles:
		var tile_data: Dictionary = terrain.tiles[coord]
		if not tile_data.get("has_river", false):
			continue
		var river_type := str(tile_data.get("river_type", ""))
		if river_type == "" or not terrain.river_properties.has(river_type):
			continue
		var rd: Dictionary = terrain.river_properties[river_type]
		if str(rd.get("kind", "single")) != "source":
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var lake_local := str(rd.get("lake_point", "C0"))
		var lp: Vector2 = SubtileGrid.RIVER_POINTS.get(lake_local, Vector2(270, 240))
		var lw := 200.0 if str(rd.get("lake_width", "")) == "" else float(rd.get("lake_width"))
		var lh := 150.0 if str(rd.get("lake_height", "")) == "" else float(rd.get("lake_height"))
		lakes.append([center + lp - Vector2(270, 240), lw * 0.5, lh * 0.5])
	return lakes

func _write_json(result: Dictionary) -> void:
	var polys_out: Array = []
	for entry in result.polys:
		var flat: Array = []
		for p in entry.p:
			flat.append(snappedf(p.x, 0.1))
			flat.append(snappedf(p.y, 0.1))
		polys_out.append({"b": entry.b, "p": flat})
	var lakes_out: Array = []
	for entry in result.lakes:
		var lflat: Array = []
		for p in entry.p:
			lflat.append(snappedf(p.x, 0.1))
			lflat.append(snappedf(p.y, 0.1))
		lakes_out.append({"p": lflat})
	var sea_out: Array = []
	for entry in result.sea:
		var sflat: Array = []
		for p in entry.p:
			sflat.append(snappedf(p.x, 0.1))
			sflat.append(snappedf(p.y, 0.1))
		sea_out.append({"b": entry.b, "p": sflat})
	var doc := {
		"version": HillField.GEN_VERSION,
		"seed": HillBaked.SEED,
		"source_hash": HillBaked.source_hash(),
		"polys": polys_out,
		"lakes": lakes_out,
		"sea": sea_out,
		"blocked": result.blocked,
		"massifs": result.massifs,
	}
	var file := FileAccess.open(HillBaked.BAKED_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	print("bake_hills: wrote %s" % HillBaked.BAKED_PATH)
