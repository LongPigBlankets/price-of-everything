extends Node
## Dev tool: the supply-chain view's FLAME LICKS in isolation — furnace L3, EAF L2 and the
## refinery L1 + L3 at the view's 400 px with the `EmpireFx` layer over each, then four
## frames a few tenths of a second apart. Needs a window (NOT --headless):
##   <godot> --path . res://tools/fx_flame_shot.tscn --quit-after 900
## Writes /tmp/poe_flame_f0..3.png.

const EmpireFx := preload("res://scripts/empire_fx.gd")
const BuildingSprites := preload("res://scripts/building_sprites.gd")

const BOX := 400.0
const FRAME_GAP := 0.3
const FRAMES := 4
const SET := [["assembly_plant", 1], ["assembly_plant", 2], ["assembly_plant", 3], ["industrial_factory", 2]]


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.058, 0.105, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in SET.size():
		var iname: String = SET[i][0]
		var level: int = SET[i][1]
		var tex: Texture2D = BuildingSprites.texture_for(iname, level)
		if tex == null:
			push_error("%s L%d sprite missing" % [iname, level])
			get_tree().quit(1)
			return
		var spr := TextureRect.new()
		spr.texture = tex
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.position = Vector2(20.0 + float(i % 2) * (BOX + 40.0), 20.0 + float(i / 2) * (BOX + 60.0))
		spr.size = Vector2(BOX, BOX)
		root.add_child(spr)
		var fx := EmpireFx.new()
		fx.position = spr.position
		fx.size = spr.size
		root.add_child(fx)
		fx.setup(iname, level, true, "shot_%d" % i, BOX)
		if not fx._bay.is_empty():
			fx._bay["t0"] = 0.0          # lock the loading-bay loop's phase for the shot
		if not fx._arms.is_empty():
			fx._arms["t0"] = 0.0
		fx._clock = float(OS.get_environment("POE_FX_T0")) if OS.has_environment("POE_FX_T0") else 0.0
		var lbl := Label.new()
		lbl.text = "%s L%d" % [iname, level]
		lbl.position = spr.position + Vector2(0.0, BOX + 10.0)
		root.add_child(lbl)
	await _settle(20)
	var gap := float(OS.get_environment("POE_FX_GAP")) if OS.has_environment("POE_FX_GAP") else FRAME_GAP
	var frames := int(OS.get_environment("POE_FX_FRAMES")) if OS.has_environment("POE_FX_FRAMES") else FRAMES
	for f in frames:
		await _settle(int(round(gap * 60.0)))
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/poe_flame_f%d.png" % f)
		print("FRAME %d saved" % f)
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
