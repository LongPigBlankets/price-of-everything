extends Node
## Dev tool: render the end-game screen so its verdict and its embedded empire graph can be
## checked. Seeds a few buildings so the graph has something to draw, forces the outcome, and
## shoots the header plus the empire section.
##
## The empire embed deliberately shows the BUY row only — nothing leaves through the sell docks
## once the company has stopped trading (owner 2026-08-01) — so this is also the check that the
## bottom port row is gone and the top one survived.
##   <godot> --path . res://tools/end_screen_shot.tscn --quit-after 1400
##   VERDICT=continuity|defeat|victory picks which ending to render (default continuity).

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(36)

	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	var bids := ["b_001", "b_002", "b_007", "b_011", "b_013", "b_003"]
	for i in range(bids.size()):
		var recs: Array = Catalog.get_recipes_for_building(bids[i])
		if recs.is_empty():
			continue
		MatchState.add_building(bids[i], str((recs[0] as Dictionary).get("recipe_id", "")),
			tiles[(i * 3) % tiles.size()], MatchState.LOCAL_PLAYER, "endshot_%d" % i)
	await _settle(6)

	var verdict := OS.get_environment("VERDICT")
	if verdict == "":
		verdict = "continuity"
	# Drive the verdict through the same net/turn the screen reads.
	Production.last_turn_summary = {"money_in": 900.0, "money_out": 400.0} if verdict != "defeat" \
		else {"money_in": 100.0, "money_out": 900.0}
	if verdict == "victory":
		VictoryState.won = true
		VictoryState.won_turn = 240

	var data: Dictionary = load("res://scripts/end_game_data.gd").gather()
	print("VERDICT=%s -> result=%s title=%s" % [verdict, str(data.get("result", "")), str(data.get("title", ""))])

	var screen: CanvasLayer = load("res://scripts/victory_end_screen.gd").new()
	add_child(screen)
	screen.show_end(data)
	await _settle(50)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_end_%s.png" % verdict)
	print("SAVED /tmp/poe_end_%s.png" % verdict)

	# The empire section usually sits below the fold, so check the embedded graph's own state
	# rather than relying on the screenshot reaching it: buy row present, sell row gone.
	var world := _find_graph_world(screen)
	if world == null:
		print("EMPIRE EMBED: no GraphWorld found")
	else:
		print("EMPIRE EMBED: sell ports=%d (want 0)  buy ports=%d (want 4)  sell edges=%d (want 0)  market edges=%d"
			% [(world.get("_ports") as Array).size(), (world.get("_buy_ports") as Array).size(),
				(world.get("_sell_edges") as Array).size(), (world.get("_market_edges") as Array).size()])
	get_tree().quit(0)


func _find_graph_world(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("empire_graph_world.gd"):
		return n
	for c in n.get_children():
		var f := _find_graph_world(c)
		if f != null:
			return f
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
