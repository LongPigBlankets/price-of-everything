extends Node
## De-risk spike: build main.tscn's BASE in a hidden SubViewport (prewarm), then reparent it
## into the live tree and finish_build() a chosen start — proving the prewarm→reveal mechanism
## before it touches the menu. Windowed:  <godot> --path . res://tools/prewarm_spike.tscn --quit-after 1500
const MAIN := "res://scenes/main.tscn"

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	# ---- PREWARM (stands in for "player is on the menu") ----
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t0 := Time.get_ticks_msec()
	var main: Node = (load(MAIN) as PackedScene).instantiate()
	main.set("prewarm_mode", true)
	var done := [false]
	main.base_ready.connect(func() -> void: done[0] = true)   # connect BEFORE add_child (can fire synchronously)
	vp.add_child(main)                 # _ready runs base-only, emits base_ready
	while not done[0]:
		await get_tree().process_frame
	print("SPIKE base built in %d ms (in subviewport)" % (Time.get_ticks_msec() - t0))
	for _i in range(8):
		await get_tree().process_frame  # render frames → warm shaders/textures
	# ---- REVEAL (stands in for "player clicked Start") ----
	var t2 := Time.get_ticks_msec()
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	vp.remove_child(main)
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await main.finish_build(true)
	print("SPIKE reveal+finish in %d ms" % (Time.get_ticks_msec() - t2))
	var got := 0
	for iid in MatchState.buildings:
		if MatchState.is_player_owned(MatchState.buildings[iid]):
			got += 1
	print("SPIKE player buildings placed: %d (want 4 for coal_baron)" % got)
	for _i in range(12):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/poe_prewarm_reveal.png")
	print("SPIKE saved /tmp/poe_prewarm_reveal.png")
	get_tree().quit(0)
