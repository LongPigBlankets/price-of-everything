extends Node
## Windowed shot: the encyclopedia landing with the Goods grid open (cream chips, two and
## a half rows), the demo-locked Game mechanics header, and a TILE search.

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	for _i in range(20):
		await get_tree().process_frame
	var so: Node = main.find_child("SearchOverlay", true, false)
	if so == null:
		push_error("no SearchOverlay"); get_tree().quit(1); return
	# Demo rules, so the Game mechanics section shows its locked state.
	MatchState.ruleset["victory_set"] = "demo_itch"
	so.set("_accordion_expanded", {"Goods": true})
	so.call("open_encyclopedia")
	await _settle(20)
	await _shot("user://poe_encyclopedia_demo.png")
	# ...and a tile search.
	var input: Node = so.get("_search_input")
	if input != null:
		so.call("open_search")
		await _settle(6)
		input.set("text", "silver")
		so.call("_on_search_text_changed", "silver")
		await _settle(20)
		await _shot("user://poe_search_tiles.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[ENC_SHOT] saved ", path)
