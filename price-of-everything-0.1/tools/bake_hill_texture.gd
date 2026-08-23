extends Node
## Offline bake of the far-zoom hill texture. Run WINDOWED (it needs a real renderer;
## --headless draws nothing):
##     <godot> --path . res://tools/bake_hill_texture.tscn --quit-after 120000
##     <godot> --headless --import --path .      # so Godot can load the new PNG
##
## Writes assets/baked/hills_far_zoom.png plus data/hills_texture_bake.json (the source
## hash, the palette it was rendered in and the framing it was rendered for). HillVisuals
## loads that instead of rendering the same picture at every single game start.
##
## Re-run after tools/bake_hills.tscn, or after any change to the relief palette
## (MapStyle band/sea/water colours) or to the painter. If you forget, nothing breaks:
## the staleness check refuses the file and the game renders it live, one frame slower.

const HillTextureBaked := preload("res://scripts/hill_texture_baked.gd")
const HillVisualsScript := preload("res://scripts/hill_visuals.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bake_hill_texture: needs a real renderer — run WITHOUT --headless.")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	# HillVisuals is self-sufficient: its geometry is HillBaked (a disk loader) and its
	# palette is the MapStyle autoload, so the bake does not need the map scene at all.
	var hills: Node2D = HillVisualsScript.new()
	hills.name = "HillVisuals"
	hills.visible = false   # nothing should be drawn to the window; we want the SubViewport
	add_child(hills)
	# Let its _ready run (and, with no bake on disk yet, warm the fill meshes the painter
	# draws from). It yields between batches, so wait for the flag rather than a frame count.
	while not bool(hills.get("_meshes_warm")):
		await get_tree().process_frame
	var rect: Rect2 = hills.get("_bake_rect")
	print("bake_hill_texture: framing %s, long side %d px" % [str(rect), int(HillVisualsScript.BAKE_LONG_SIDE)])

	var image: Image = await hills.render_bake_image()
	if image == null or image.is_empty():
		push_error("bake_hill_texture: the render produced no image.")
		get_tree().quit(1)
		return

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(HillTextureBaked.TEXTURE_PATH).get_base_dir())
	if image.save_png(HillTextureBaked.TEXTURE_PATH) != OK:
		push_error("bake_hill_texture: could not write %s." % HillTextureBaked.TEXTURE_PATH)
		get_tree().quit(1)
		return

	var manifest := {
		"bake_version": HillTextureBaked.BAKE_VERSION,
		"source_hash": HillBaked.source_hash(),
		"style": HillTextureBaked.style_key(MapStyle.ink, MapStyle.plate, MapStyle.is_midcentury()),
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"size_px": [image.get_width(), image.get_height()],
		"texture": HillTextureBaked.TEXTURE_PATH,
	}
	var file := FileAccess.open(HillTextureBaked.MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		push_error("bake_hill_texture: could not write %s." % HillTextureBaked.MANIFEST_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()

	print("bake_hill_texture: %d x %d px -> %s (%.1f s)" % [
		image.get_width(), image.get_height(), HillTextureBaked.TEXTURE_PATH,
		float(Time.get_ticks_msec() - started) / 1000.0])
	print("bake_hill_texture: style %s, source_hash %s" % [manifest.style, str(manifest.source_hash).left(12)])
	print("bake_hill_texture: now run `--headless --import` so Godot can load the PNG.")
	get_tree().quit(0)
