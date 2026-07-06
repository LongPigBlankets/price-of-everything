extends Node2D
# Dev-only: render the Settings panel (opens on the Audio tab).
#   Godot --path . res://tools/settings_shot.tscn --quit-after 600
var _frame := 0


func _ready() -> void:
	get_window().size = Vector2i(1100, 720)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	await get_tree().process_frame   # let DS assign the theme to the root viewport
	SettingsPanel.open(root)


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://settings_shot.png")
		print("SAVED settings_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
