extends Node
## Captures of the Politics panel on its own: before the election (the empty state), partway through the arc,
## with every event in, and a longer record that scrolls.
##   POLITICS_SHOT_DIR=<dir> <godot> --path . res://tools/politics_ds2_shot.tscn --quit-after 2000 -- --no-telemetry
## Writes politics_ds2_<state>.png.

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
	# A longer record than the arc holds today, to show the scroll past five rows.
	var long_script := GDScript.new()
	long_script.source_code = "extends \"res://scripts/politics_panel.gd\"\nfunc _entries() -> Array:\n\tvar out: Array = super._entries()\n\tfor i in 3:\n\t\tout.append({\"icon\": \"gavel\", \"title\": \"A later act of the house\", \"body\": \"A made up entry, here to show the record scrolling past five rows.\", \"turn\": 110 + i * 5})\n\treturn out\n"
	long_script.reload()
	states["long"] = int(states["all"])
	for state: String in states:
		TurnManager.current_turn = int(states[state])
		var panel: Control = (long_script if state == "long" else load("res://scripts/politics_panel.gd") as GDScript).new()
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
		img.get_region(r).save_png(dir.path_join("politics_ds2_%s.png" % state))
		panel.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
