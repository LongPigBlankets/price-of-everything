extends Node
## Dev tool: verify the infra building detail panel's new "Breakdown" table (goods
## that transited this tile last turn — icon+qty / cost / congestion penalty).
## Needs a window:  "$GODOT_BIN" --path . res://tools/breakdown_shot.tscn --quit-after 900

const OUT_DIR := "C:/Users/urigi/AppData/Local/Temp/claude/C--Users-urigi-price-of-everything-price-of-everything-0-1/07c26e3a-d370-4e95-9ab5-05bbb28794cb/scratchpad/out/"

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	MatchState.money = 5000.0

	# A real rail building (b_019, per the infra-upgrade test suite) so the panel takes
	# the actual is_infra branch, not a synthetic tile-view stand-in.
	var iid: String = MatchState.add_building("b_019", "", "tile_9_9", "player_1", "shot_infra_rail")

	# Two shipments transiting tile_9_9 on rail: a plain single-good haul (coal, tier-0 —
	# clean, no penalty) AND a multi-good sale shipment (coal + iron ore) loaded heavily
	# enough on the SAME link to push it into congestion, so the shot proves both the
	# per-good split AND a non-zero Penalties column in one panel.
	MatchState.pending_transport_shipments.clear()
	MatchState.pending_transport_shipments.append({
		"good_id": "g_001", "qty": 120, "turns_remaining": 2,
		"tile_distance": 1, "transport_turns": 1,
		"tiles": ["tile_9_8", "tile_9_9"],
		"legs": [{"mode": "rail", "from": "tile_9_8", "to": "tile_9_9"}],
	})
	MatchState.pending_transport_shipments.append({
		"is_sale": true, "turns_remaining": 2,
		"tile_distance": 1, "transport_turns": 1,
		"tiles": ["tile_9_9", "tile_9_10"],
		"legs": [{"mode": "rail", "from": "tile_9_9", "to": "tile_9_10"}],
		"sale_record": {"tile_id": "tile_9_9", "items": [
			{"good_id": "g_001", "qty": 700, "revenue": 7000.0},
			{"good_id": "g_002", "qty": 300, "revenue": 3600.0},
		], "total_qty": 1000, "total_revenue": 10600.0},
	})
	MatchState.update_transport_congestion()
	print("[breakdown_shot] rail L1 cap=", MatchState.tile_mode_capacity("rail", 1),
		" tier=", MatchState.route_congestion_tier({"tiles": ["tile_9_9", "tile_9_10"], "legs": [{"mode": "rail", "from": "tile_9_9", "to": "tile_9_10"}]}))
	var rows := MatchState.tile_good_breakdown("tile_9_9", "rail")
	for r in rows:
		print("[breakdown_shot] row good=", r.get("good_id", ""), " qty=", r.get("qty", 0),
			" cost=", r.get("cost", 0.0), " penalty=", r.get("penalty", 0.0))

	# The scene-authored BuildingDetailPanel node runs the OLD v1 script — the panel a
	# player actually sees (default since Phase 3, MatchState.use_bdp_v2) is v2, built
	# lazily off WorldMap.building_panel_v2. Go through that property, not the node.
	# main.tscn's ROOT node runs world_map.gd — `game` (its instantiated root) IS the
	# WorldMap, not a container holding one (topbar_v31_shot.gd's game.get_node("UILayer/…")
	# confirms this same layout: UILayer is one of game's own direct children).
	var panel: Control = game.building_panel_v2
	panel.show_building(MatchState.get_building(iid))
	await _settle(10)
	if panel.find_child("InfraBreakdownCard", true, false) == null:
		print("[breakdown_shot] WARNING: InfraBreakdownCard not found — did tile_good_breakdown come back empty?")
	await _shot(OUT_DIR + "infra_breakdown_panel.png")

	print("[breakdown_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[breakdown_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
