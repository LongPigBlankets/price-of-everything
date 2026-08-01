extends Node
## Dev tool: stress the empire sprite view with 50 player buildings at mixed levels and
## measure what matters at that scale — composition extent, the zoom-out cap, and memory.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/empire_stress_shot.tscn --quit-after 1200
## Peak process RSS is measured OUTSIDE by watchdog.sh (ps polling); the prints here cover
## the engine-side monitors (static mem, texture mem, node count) for attribution.

const COUNT := 50
# Four sprited types + two glyph-only, so the mix exercises both card paths.
const KINDS := ["b_001", "b_002", "b_007", "b_011", "b_008", "b_012"]


func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	_seed()
	await _settle(4)

	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	if ev == null:
		push_error("EmpireView not found")
		get_tree().quit(1)
		return
	MatchState.use_empire_sprite_view = true
	ev.call("toggle")
	await _settle(24)

	var gw: Node = ev.get_node_or_null("GraphWorld")
	if gw == null:
		push_error("GraphWorld not found")
		get_tree().quit(1)
		return

	var nodes: Array = gw.get("_nodes") as Array
	var sprited := 0
	for n in nodes:
		if n.get("sprite") != null:
			sprited += 1
	var bb: Rect2 = gw.call("_layout_bbox")
	var view: Vector2 = (gw as Control).get_rect().size
	print("STRESS nodes=", nodes.size(), " sprited=", sprited,
		" edges=", (gw.get("_edges") as Array).size(),
		" sell=", (gw.get("_sell_edges") as Array).size())
	print("BBOX world %.0f x %.0f px  (%.2f x %.2f viewports of %.0f x %.0f)" % [
		bb.size.x, bb.size.y, bb.size.x / view.x, bb.size.y / view.y, view.x, view.y])
	print("ZOOM open=%.3f floor=%.3f detail=%.3f" % [
		float(gw.get("_view_zoom")), float(gw.get("_zoom_floor")), float(gw.call("_detail"))])

	_shot("/tmp/poe_stress_open.png")

	# Force to the cap, then to max zoom-in, exercising both extremes of the draw path.
	gw.call("_zoom_at", view * 0.5, 0.001)
	await _settle(24)
	print("CAPPED zoom=%.3f" % float(gw.get("_view_zoom")))
	_shot("/tmp/poe_stress_capped.png")
	gw.call("_zoom_at", view * 0.5, 1000.0)
	await _settle(12)
	gw.call("_zoom_at", view * 0.5, 0.001)
	await _settle(12)

	print("MEM static=%.0f MB  textures=%.0f MB  nodes=%d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	get_tree().quit(0)


func _seed() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	var placed := 0
	for k in range(COUNT):
		var bid: String = KINDS[k % KINDS.size()]
		var recs: Array = Catalog.get_recipes_for_building(bid)
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var iid := "stress_%d" % k
		MatchState.add_building(bid, rid, tiles[(k * 7) % tiles.size()], "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = (k % 3) + 1
			placed += 1
	print("seeded ", placed, "/", COUNT, " stress buildings")


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
