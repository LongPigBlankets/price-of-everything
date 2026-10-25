extends Node
## Dev tool: the DS2 encyclopedia (scripts/encyclopedia_ds2/) in the real HUD, a capture a view: the contents, the
## look up for steel, Steel's entry on its first and second pages, the Furnace, Steelmaking, a mechanic, the
## recipes' contents and the demo's locked Mechanics tab. Renders, so run it windowed:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/encyclopedia_ds2_shot.tscn --quit-after 6000 -- --no-telemetry
## Captures go to ENCYCLOPEDIA_SHOT_DIR (default user://encyclopedia_ds2/), the book cropped from the screen.

const START := "res://data/starts/metal_magnate.json"

var _dir := "user://encyclopedia_ds2"


func _ready() -> void:
	DecisionState.auto_resolve = true
	if OS.get_environment("ENCYCLOPEDIA_SHOT_DIR") != "":
		_dir = OS.get_environment("ENCYCLOPEDIA_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(_dir if _dir.begins_with("/") else ProjectSettings.globalize_path(_dir))
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 6000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	# The start's opener and intro card out of the way, so the book opens over the map.
	if main.has_method("reveal_for_play"):
		main.call("reveal_for_play")
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		var sc := layer.get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(30)
	var so: Node = main.find_child("SearchOverlay", true, false)
	if so == null:
		push_error("no SearchOverlay")
		get_tree().quit(1)
		return
	so.call("open_encyclopedia")
	var book: Node = so.call("ds2_book")
	await _shot(book, "01_contents")
	book.call("open_fresh", {"kind": "index", "query": "STEEL"})
	await _shot(book, "02_lookup_steel")
	book.call("open_fresh", {"kind": "good", "id": "g_006"})
	await _shot(book, "03_steel_page1")
	book.call("next_page")
	await _shot(book, "04_steel_page2")
	book.call("open_fresh", {"kind": "building", "id": "b_002"})
	await _shot(book, "05_furnace")
	book.call("open_fresh", {"kind": "recipe", "id": "r_003"})
	await _shot(book, "06_steelmaking")
	book.call("open_fresh", {"kind": "mechanic", "id": "market_price_mechanics"})
	await _shot(book, "07_mechanic")
	book.call("next_page")
	await _shot(book, "07b_mechanic_page2")
	book.call("open_fresh", {"kind": "mechanic", "id": "building_economics"})
	await _shot(book, "07c_building_economics")
	book.call("next_page")
	await _shot(book, "07d_building_economics_page2")
	book.call("open_fresh", {"kind": "contents", "section": "recipes"})
	await _shot(book, "08_contents_recipes")
	book.call("open_fresh", {"kind": "good", "id": "g_001"})
	await _shot(book, "09_coal")
	MatchState.ruleset["victory_set"] = "demo_itch"
	book.call("open_fresh", {"kind": "contents", "section": "goods"})
	await _shot(book, "10_demo_contents")
	print("[ENC_SHOT] done")
	get_tree().quit(0)


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(book: Node, name: String) -> void:
	await _settle(12)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var inner: Control = book.get_node("Book")
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var r := Rect2i(Vector2i(inner.get_global_rect().position * k), Vector2i(inner.get_global_rect().size * k))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	var path := "%s/%s.png" % [_dir, name]
	crop.save_png(path)
	print("[ENC_SHOT] saved ", path)
