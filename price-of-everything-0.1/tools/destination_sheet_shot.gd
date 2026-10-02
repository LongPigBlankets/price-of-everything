extends Node
## Captures of the destination change sheet on its own: an output to the global market, to a tile stockpile,
## and an input to the market.
##   DEST_SHOT_DIR=<dir> <godot> --path . res://tools/destination_sheet_shot.tscn --quit-after 2000 -- --no-telemetry
## Writes destination_sheet_<state>.png.

func _ready() -> void:
	var dir := OS.get_environment("DEST_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var back := ColorRect.new()
	back.color = Color(0.2, 0.26, 0.3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var confirm := preload("res://scripts/logistics_confirmation.gd")
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var states := {
		"output_market": {"side": "output", "destination": "market", "good": coal, "tile": "tile_5_10"},
		"output_stockpile": {"side": "output", "destination": "stockpile", "good": coal, "tile": "tile_5_10"},
		"input_market": {"side": "input", "destination": "market", "good": coal, "tile": "tile_5_10"},
	}
	for state: String in states:
		confirm.skip_confirmation = false
		confirm.request(self, "managed", func() -> bool: return true, Callable(), states[state])
		for _i in 12:
			await get_tree().process_frame
		var sheet := find_child("Sheet", true, false) as Control
		RenderingServer.force_draw(false)
		var img := get_viewport().get_texture().get_image()
		var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		var g := sheet.get_global_rect().grow(24)
		var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png(dir.path_join("destination_sheet_%s.png" % state))
		find_child("TransportSupplierConfirmation", true, false).emit_signal("canceled")
		for _i in 3:
			await get_tree().process_frame
	get_tree().quit(0)
