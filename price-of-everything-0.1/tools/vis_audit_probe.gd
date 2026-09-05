extends Node
## Dev probe: for a few tiles, is every gameplay building actually ON SCREEN? Lists what the
## sim says stands on the tile against what BuildingVisuals placed, and why each is or is not
## drawn — hijacked (wearing a decorative mass), placed normally, or missing a footprint.
##   <godot> --path . res://tools/vis_audit_probe.tscn --quit-after 60000 -- --start=metal_magnate

const TILES := ["tile_5_10", "tile_9_16", "tile_23_8", "tile_22_16"]

func _ready() -> void:
	var start_id := "metal_magnate"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--start="):
			start_id = a.trim_prefix("--start=")
	SaveLoad.prepare_new_game("res://data/starts/%s.json" % start_id, {"ruleset": {
		"start_id": start_id, "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		push_error("[VIS] no BuildingVisuals"); get_tree().quit(1); return
	var placements: Array = bv.get("_placements")
	var hijacked: Dictionary = bv.get("_hijacked_masses")
	print("[VIS] start=%s  total placements=%d  hijack claims=%d" % [start_id, placements.size(), hijacked.size()])
	for tile_id in TILES:
		var sim: Array = MatchState.get_buildings_on_tile(tile_id)
		var drawn := 0
		var worn := 0
		var rows: Array = []
		for p_value in placements:
			var p: Dictionary = p_value
			if str(p.get("tile_id", "")) != tile_id:
				continue
			var hid := str(p.get("hijack_id", ""))
			if hid == "":
				drawn += 1
			else:
				worn += 1
			rows.append("%s%s via=%s" % [str(p.get("iname", "?")),
				(" WEARS " + hid) if hid != "" else " DRAWN", str(p.get("via", "?"))])
		print("[VIS] %s: sim=%d placed=%d  drawn=%d worn(invisible)=%d" % [
			tile_id, sim.size(), drawn + worn, drawn, worn])
		for r in rows:
			print("[VIS]      %s" % r)
		if sim.size() > drawn + worn:
			print("[VIS]      !! %d building(s) on this tile have NO placement at all" % (sim.size() - drawn - worn))
	get_tree().quit(0)
