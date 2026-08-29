extends Node
## Verify IN GAME that demolishing an authored old-growth wood removes its canopy.
##
## Authored woods are drawn from the map document by AuthoredFabricVisuals, not by
## ForestVisuals, so removing the building cannot remove them the way it removes a factory —
## forget_forest() drops the wood and marks its baked tiles for repaint. That repaint only
## happens windowed, which is why this cannot be a unit test.
##
##   <godot> --path . res://tools/felled_wood_shot.tscn --quit-after 3000
##
## ONE boot, bake INTACT. (An earlier version of this check bypassed the bake and re-rendered
## every tile as live vectors seven times over, which made the machine unresponsive. There is
## no reason to do that: repainting a couple of tiles is exactly what the game already does.)

const AuthoredMapRef := preload("res://scripts/authored_map.gd")

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 860))
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(90)

	var fabric: Node = game.get_node_or_null("AuthoredFabricVisuals")
	var terrain: Node = game.get_node("%TerrainLayer")
	if fabric == null:
		push_error("felled_wood_shot: AuthoredFabricVisuals not found")
		get_tree().quit(1)
		return

	# A tile that carries BOTH an authored wood and the forest building seeded from it.
	# world_map owns the tile -> authored-area index (it needs the hex geometry to build it).
	var index: Dictionary = game.get("_authored_forest_areas_by_tile")
	var target := ""
	var target_iid := ""
	for tile_id in index:
		var tid := str(tile_id)
		for iid in MatchState.buildings:
			var b: Dictionary = MatchState.buildings[iid]
			if str(b.get("tile_id", "")) == tid and str(b.get("building_id", "")) == "b_016":
				target = tid
				target_iid = str(iid)
				break
		if target != "":
			break
	print("[FELL] authored woods indexed onto %d tiles  target=%s  building=%s  areas=%s"
		% [index.size(), target, target_iid, str(index.get(target, []))])
	if target == "":
		push_error("felled_wood_shot: no authored wood with a forest building")
		get_tree().quit(1)
		return

	# Frame it. The camera controller lerps toward its own target every frame and would pull
	# any zoom straight back out, so freeze it first.
	var cam: Camera2D = game.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.set_process(false)
		cam.set_physics_process(false)
		cam.set("edge_pan_enabled", false)
		var coord: Vector2i = terrain.call("id_to_coord", target)
		var cell = terrain.call("map_coord_for_tile_coord", coord)
		cam.position = terrain.call("to_global", terrain.call("map_to_local", cell))
		cam.zoom = Vector2(1.6, 1.6)
		cam.set("_target_zoom", Vector2(1.6, 1.6))
	var ui: Node = game.get_node_or_null("UILayer")
	if ui != null:
		(ui as CanvasLayer).visible = false
	await _settle(20)
	_shot("/tmp/poe_wood_before.png")

	# Fell it exactly as the demolish job does.
	MatchState.remove_building(target_iid)
	await _settle(6)
	var guard := 0
	while fabric.call("has_pending_repairs") and guard < 600:
		guard += 1
		await get_tree().process_frame
	print("[FELL] repaint finished after %d frames (pending=%s)"
		% [guard, str(fabric.call("has_pending_repairs"))])
	await _settle(20)
	_shot("/tmp/poe_wood_after.png")
	get_tree().quit(0)


func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("[FELL] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
