extends Node
## Dev tool: verify the Glass Merchant start intro — the founding modal (glass icon +
## title + lore + Vandel Glassworks bonus), with the lore scroll opened to full height
## so every paragraph is on screen for copy review.
##   /tmp/poe_glass_intro.png
## Needs a window: <godot> --path . res://tools/glass_merchant_intro_shot.tscn --quit-after 2000

func _ready() -> void:
	# Mirror the new-game flow: the start_id override is what world_map keys the intro on.
	SaveLoad.prepare_new_game("res://data/starts/glass_merchant.json", {"ruleset": {"start_id": "glass_merchant"}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(200)   # let finish_build run and mount the intro
	_open_lore_scroll()
	await _settle(5)
	await _shot("/tmp/poe_glass_intro.png")
	# Sanity: confirm the two Vandel Glassworks output modifiers registered.
	for mid in ["start_glass_merchant_glass", "start_glass_merchant_windows"]:
		print("[SHOT] modifier %s present: %s" % [mid, Modifiers._modifiers.has(mid)])
	get_tree().quit(0)

## The card caps the lore scroll at 336 px; for the review shot open it to the label's
## full height so no paragraph hides below the fold.
func _open_lore_scroll() -> void:
	var intro: Node = _find_intro(get_tree().root)
	if intro == null:
		push_warning("[SHOT] glass intro not mounted — screenshot will miss the card")
		return
	var scroll: ScrollContainer = _find_scroll(intro)
	if scroll != null:
		scroll.custom_minimum_size.y = 560

func _find_intro(n: Node) -> Node:
	var s: Variant = n.get_script()
	if s != null and str((s as Script).resource_path).ends_with("glass_merchant_intro.gd"):
		return n
	for c in n.get_children():
		var hit: Node = _find_intro(c)
		if hit != null:
			return hit
	return null

func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var hit: ScrollContainer = _find_scroll(c)
		if hit != null:
			return hit
	return null

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
