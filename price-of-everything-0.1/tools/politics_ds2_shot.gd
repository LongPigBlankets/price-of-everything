extends Node
## Captures of the Politics panel on its own, v2 beside DS2: before the election (the empty state), partway
## through the arc, and with every event in.
##   POLITICS_SHOT_DIR=<dir> <godot> --path . res://tools/politics_ds2_shot.tscn --quit-after 2000 -- --no-telemetry
## Writes politics_<look>_<state>.png.

func _ready() -> void:
	var dir := OS.get_environment("POLITICS_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var back := ColorRect.new()
	back.color = Color(0.16, 0.18, 0.2)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var states := {"empty": maxi(1, PolicyState.beat("election_news") - 1), "ramping": PolicyState.beat("ramp_first"),
		"all": maxi(PolicyState.beat("p1"), PolicyState.beat("subsidy"))}
	for ds2: bool in [false, true]:
		UiPrefs.set_use_politics_ds2(ds2)
		for state: String in states:
			TurnManager.current_turn = int(states[state])
			var panel: Control = (load("res://scripts/politics_panel.gd") as GDScript).new()
			add_child(panel)
			panel.show()
			panel.call("_refresh")
			for _i in 12:
				await get_tree().process_frame
			RenderingServer.force_draw(false)
			var img := get_viewport().get_texture().get_image()
			var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
			var g := panel.get_global_rect().grow(8)
			var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img.get_region(r).save_png(dir.path_join("politics_%s_%s.png" % ["ds2" if ds2 else "v2", state]))
			panel.queue_free()
			await get_tree().process_frame
	UiPrefs.set_use_politics_ds2(false)
	get_tree().quit(0)
