extends Node
const Expansion := preload("res://scripts/public_road_expansion.gd")
var failures := 0
var checks := 0
var money_clicks := 0

class MapInputProbe extends Node:
	var clicks := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			clicks += 1

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click_at(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await get_tree().process_frame

func _ready() -> void:
	for turn in [1, 19, 21, 24, 26, 29]:
		check(Expansion.batch_size(turn) == 0, "No road expansion on turn %d" % turn)
	check(Expansion.batch_size(20) == 3, "Three tiles at turn 20")
	check(Expansion.batch_size(25) == 4, "Four tiles at turn 25")
	check(Expansion.batch_size(30) == 3, "Three tiles at turn 30")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for i in 160:
		await get_tree().process_frame
	var terrain := world.get_node("TerrainLayer")
	var candidates: Array = terrain.tiles.values()
	var expected := Expansion.next_tiles(candidates, 20)
	var reversed := candidates.duplicate()
	reversed.reverse()
	check(expected == Expansion.next_tiles(reversed, 20), "Radial order is deterministic")
	var max_distance := 0
	for id in expected:
		max_distance = maxi(max_distance, Catalog.tile_hex_distance(id, Catalog.nearest_port_tile(id)))
	for tile in candidates:
		var id := str(tile.id)
		if Expansion.LAND_TYPES.has(Catalog.tile_type(id)) and not Catalog.tile_has_infrastructure(id, "roads") and not expected.has(id):
			check(Catalog.tile_hex_distance(id, Catalog.nearest_port_tile(id)) >= max_distance, "Nearer port rings are filled first")
	Construction.construction_projects["public-road-test"] = {"building_id": "b_005", "tile_id": expected[0]}
	check(not Expansion.next_tiles(candidates, 20).has(expected[0]), "Player road construction is skipped")
	Construction.construction_projects.erase("public-road-test")
	var cash := MatchState.money
	var before20: Array = world._expand_public_roads(19)
	check(before20.is_empty(), "World waits until turn 20")
	var first: Array = world._expand_public_roads(20)
	check(first == expected and first.size() == 3, "World applies the first radial batch")
	check(world._expand_public_roads(20).is_empty(), "Same turn cannot repeat a batch")
	var second: Array = world._expand_public_roads(25)
	check(second.size() == 4, "World applies four more tiles on turn 25")
	for id in first + second:
		check(Expansion.LAND_TYPES.has(Catalog.tile_type(id)), "Public roads avoid mountain and water tiles")
		check(Catalog.tile_has_infrastructure(id, "roads"), "Routing sees public roads")
		check(terrain.tiles[terrain.id_to_coord(id)].infrastructure_present.has("roads"), "Terrain sees public roads")
	check(MatchState.money == cash, "Public roads do not charge the player")
	var snapshot := SaveLoad.export_snapshot()
	check(int(snapshot.match.public_roads_last_turn) == 25, "Save records the last public road batch")
	for id in first + second:
		check(snapshot.infrastructure[id].present.has("roads"), "Save includes new infrastructure")
	MatchState.public_roads_last_turn = 0
	MatchState.import_state(snapshot.match)
	check(world._expand_public_roads(25).is_empty(), "Restored batch cannot repeat")
	# Exercise real GUI propagation, with a positive control below the bar.
	var probe := MapInputProbe.new()
	add_child(probe)
	var bar: Control = world.get_node("UILayer/HUD/TopBar")
	var rect := bar.get_global_rect()
	await click_at(Vector2(rect.position.x + rect.size.x * 0.7, rect.end.y - 2))
	check(probe.clicks == 0, "Empty top bar consumes click press and release")
	await click_at(Vector2(rect.position.x + rect.size.x * 0.7, rect.end.y - 2), MOUSE_BUTTON_WHEEL_UP)
	check(probe.clicks == 0, "Empty top bar consumes scrolling")
	var money: Button = bar.get_node("MarginContainer/HBoxContainer/MoneyWidget")
	money.pressed.connect(func(): money_clicks += 1)
	await click_at(money.get_global_rect().get_center())
	check(money_clicks == 1 and probe.clicks == 0, "Top bar buttons still work without map input")
	bar._close_fly()
	await click_at(Vector2(rect.size.x * 0.7, rect.end.y + 180))
	check(probe.clicks > 0, "Map below the top bar remains interactive")
	print("[public_roads] first=%s second=%s; %d checks, %d failures" % [first, second, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
