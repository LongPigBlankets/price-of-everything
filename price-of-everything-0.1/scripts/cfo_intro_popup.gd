extends CanvasLayer
## One-time narrative flourish: the first time the CFO files a tax-loss carry-forward
## credit, their portrait slides into the TOP-LEFT with a dark gradient around it and a
## few first-person lines explaining what just happened. Mounted by top_bar.gd on the
## MatchState.cfo_tax_credit_filed signal; self-frees on dismiss (button, or a timeout).

const CARD_W := 430.0
const PORTRAIT := 104.0

var _vig_tex: Texture2D = null

func show_for(cfo: Dictionary, body_text: String) -> void:
	layer = 130
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var card := PanelContainer.new()
	card.position = Vector2(20.0, 72.0)   # top-left, just below the top bar
	card.custom_minimum_size = Vector2(CARD_W, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0B1826")
	sb.border_color = Color(Color("#CDB98A"), 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.shadow_size = 12
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(_portrait_frame(cfo))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	var title := Label.new()
	title.text = "%s · CFO" % _cfo_name(cfo)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#E8EEF7"))
	col.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_W - PORTRAIT - 62.0, 0.0)
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color("#C2D2E5"))
	col.add_child(body)

	var btn := Button.new()
	btn.text = "Got it"
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(_dismiss)
	col.add_child(btn)

	# Safety auto-dismiss so it never lingers in the corner forever.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 18.0
	add_child(timer)
	timer.timeout.connect(_dismiss)
	timer.start()

	root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.35)

func _dismiss() -> void:
	queue_free()

func _cfo_name(cfo: Dictionary) -> String:
	var nm := str(cfo.get("name", ""))
	return nm if nm != "" else str(cfo.get("id", "cfo")).capitalize()

func _accent(cfo: Dictionary) -> Color:
	var a: Variant = cfo.get("accent", "#53687A")
	return Color(a) if a is String else (a as Color)

func _portrait_frame(cfo: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := _accent(cfo)
	var box := StyleBoxFlat.new()
	box.bg_color = accent.darkened(0.5)
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", box)

	var tex := _load_portrait(str(cfo.get("portrait_path", "")))
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(img)
	else:
		var center := CenterContainer.new()
		frame.add_child(center)
		var initials := Label.new()
		initials.text = str(cfo.get("initials", "CFO"))
		initials.add_theme_font_size_override("font_size", 30)
		initials.add_theme_color_override("font_color", Color("#E8EEF7"))
		center.add_child(initials)

	# Dark gradient around the portrait edges (slight vignette).
	var vig := TextureRect.new()
	vig.texture = _vignette()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(vig)
	return frame

func _load_portrait(path: String) -> Texture2D:
	if path == "":
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _vignette() -> Texture2D:
	if _vig_tex != null:
		return _vig_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var cc := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx := (float(x) - cc) / cc
			var dy := (float(y) - cc) / cc
			var d := sqrt(dx * dx + dy * dy) / 1.41421356
			var a := clampf((d - 0.45) / 0.55, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * a * 0.7))
	_vig_tex = ImageTexture.create_from_image(img)
	return _vig_tex
