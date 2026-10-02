extends Node
## Captures of the updates dock on its own, v2 beside DS2: the dock with counts on its pen and bells, and its
## slide-out opened on a green, an amber and a red row and a link.
##   DOCK_SHOT_DIR=<dir> <godot> --path . res://tools/dock_ds2_shot.tscn --quit-after 2000 -- --no-telemetry
## Writes dock_<look>.png.

func _ready() -> void:
	var dir := OS.get_environment("DOCK_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var back := ColorRect.new()
	back.color = Color(0.36, 0.42, 0.3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var toasts: Control = (load("res://scripts/toast_manager.gd") as GDScript).new()
	add_child(toasts)
	await _settle(4)
	toasts.call("push_research", "Open Logistics Contracts")
	toasts.call("push_row", "Motor Factory A is built at Thistle River Valley.", "green")
	toasts.call("push_row", "Copper ingots accumulating at Stoneshore (+19/turn). Open stockpile to move or sell.", "amber", "stock", func() -> void: pass)
	toasts.call("push_row", "We've taken a £371 loan to pay for the intermediary's batches this turn.", "red")
	toasts.call("push_row", "First sale to the market. Our company sold its first goods to the global market via Port Lightning.", "green")
	for ds2: bool in [false, true]:
		UiPrefs.set_use_dock_ds2(ds2)
		toasts.call("open_all")
		await _settle(30)
		RenderingServer.force_draw(false)
		var img := get_viewport().get_texture().get_image()
		var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		var vp := get_viewport().get_visible_rect().size
		var g := Rect2(0, vp.y - 460.0, 420.0, 460.0)
		var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(dir.path_join("dock_%s.png" % ("ds2" if ds2 else "v2")))
	UiPrefs.set_use_dock_ds2(false)
	get_tree().quit(0)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
