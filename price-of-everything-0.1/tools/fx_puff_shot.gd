extends Node
## Dev tool: the supply-chain view's chimney effects in isolation. A furnace L2 sprite at the
## view's 400 px, twice side by side — left forced to SMOKE, right forced to STEAM — with the
## `EmpireFx` layer over each, then five frames a few tenths of a second apart. Needs a window
## (NOT --headless):
##   <godot> --path . res://tools/fx_puff_shot.tscn --quit-after 900
## Writes /tmp/poe_puff_f0..4.png.

const EmpireFx := preload("res://scripts/empire_fx.gd")
const BuildingSprites := preload("res://scripts/building_sprites.gd")

const BOX := 400.0
const FRAME_GAP := 0.35
const FRAMES := 5


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.058, 0.105, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var tex: Texture2D = BuildingSprites.texture_for("furnace", 2)
	if tex == null:
		push_error("furnace L2 sprite missing")
		get_tree().quit(1)
		return
	for i in 2:
		var spr := TextureRect.new()
		spr.texture = tex
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.position = Vector2(60.0 + i * (BOX + 120.0), 140.0)
		spr.size = Vector2(BOX, BOX)
		root.add_child(spr)
		var fx := EmpireFx.new()
		fx.position = spr.position
		fx.size = spr.size
		root.add_child(fx)
		fx.setup("furnace", 2, i == 0, "shot_%d" % i, BOX)
		var lbl := Label.new()
		lbl.text = "SMOKE (carbon recipe)" if i == 0 else "STEAM (clean recipe)"
		lbl.position = spr.position + Vector2(0.0, BOX + 90.0)
		root.add_child(lbl)
	await _settle(20)
	for f in FRAMES:
		await _settle(int(round(FRAME_GAP * 60.0)))
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/poe_puff_f%d.png" % f)
		print("FRAME %d saved" % f)
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
