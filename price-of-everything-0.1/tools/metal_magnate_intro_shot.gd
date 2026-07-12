extends Node
## Dev tool: verify the Metal Magnate start intro — camera pinned to Stoneshore Docks
## and the founding modal (iron icon + title + lore + Legacy of Metal bonus).
##   /tmp/poe_metal_magnate_intro.png
## Needs a window: <godot> --path . res://tools/metal_magnate_intro_shot.tscn --quit-after 2000

func _ready() -> void:
	# Mirror the new-game flow: the start_id override is what world_map keys the intro on.
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {"start_id": "metal_magnate"}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(200)   # let finish_build run and mount the intro
	await _shot("/tmp/poe_metal_magnate_intro.png")
	# Sanity: confirm the four Legacy-of-Metal output modifiers registered.
	for gid in ["iron", "copper", "alloy", "steel"]:
		print("[SHOT] modifier start_metals_magnate_%s present: %s" % [gid, Modifiers._modifiers.has("start_metals_magnate_%s" % gid)])
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
