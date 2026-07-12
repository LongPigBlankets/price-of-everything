extends Node
func _ready() -> void:
	get_window().size = Vector2i(680, 360)
	await get_tree().process_frame
	var bg := ColorRect.new(); bg.color = DS.PALETTE["BG_PANEL"]; bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var vb := VBoxContainer.new(); vb.position = Vector2(24, 20); vb.add_theme_constant_override("separation", 10); add_child(vb)
	var rows := [
		["Title (H1)", "Title", null],
		["Section heading", "Section", null],
		["Body text — the quick brown fox (14px)", "Body", null],
		["Caption / small text — now off-white at 14px", "Caption", null],
		["TEXT_MUTED small label sample", "Caption", DS.PALETTE["TEXT_MUTED"]],
		["TEXT_DIM small label sample (dim)", "Caption", DS.PALETTE["TEXT_DIM"]],
	]
	for r in rows:
		var l := Label.new()
		l.text = r[0]; l.theme_type_variation = r[1]
		if r[2] != null: l.add_theme_color_override("font_color", r[2])
		vb.add_child(l)
	for _i in range(6): await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://font_sample.png")
	print("[SHOT] font_sample.png saved")
	get_tree().quit(0)
