extends RefCounted
## Shared UI builders. Referenced via preload (const UIHelpers := preload(...)) so it
## resolves in headless runs without a global-class-cache rescan. The custom checkbox is the borderless, right-aligned tickbox
## used in the tile panel's setting rows ("sell surplus" etc.) — no button box/outline.

const CHECKBOX_ICON_SIZE := 18

static var _checked_tex: Texture2D = null
static var _unchecked_tex: Texture2D = null

static func checkbox_icon(checked: bool) -> Texture2D:
	if checked and _checked_tex != null:
		return _checked_tex
	if not checked and _unchecked_tex != null:
		return _unchecked_tex
	var image := Image.create(CHECKBOX_ICON_SIZE, CHECKBOX_ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if checked:
		image.fill(Color.WHITE)
	else:
		for i in CHECKBOX_ICON_SIZE:
			image.set_pixel(i, 0, Color.WHITE)
			image.set_pixel(i, CHECKBOX_ICON_SIZE - 1, Color.WHITE)
			image.set_pixel(0, i, Color.WHITE)
			image.set_pixel(CHECKBOX_ICON_SIZE - 1, i, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	if checked:
		_checked_tex = texture
	else:
		_unchecked_tex = texture
	return texture

static func make_custom_checkbox() -> CheckBox:
	var cb := CheckBox.new()
	cb.text = ""
	cb.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cb.add_theme_icon_override("unchecked", checkbox_icon(false))
	cb.add_theme_icon_override("checked", checkbox_icon(true))
	cb.add_theme_icon_override("unchecked_disabled", checkbox_icon(false))
	cb.add_theme_icon_override("checked_disabled", checkbox_icon(true))
	cb.flat = true
	var no_box := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_theme_stylebox_override(state, no_box)
	return cb

static func make_setting_row(label_text: String, control: Control, row_height: float = 30.0) -> HBoxContainer:
	# Label on the left, control pushed to the right edge.
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, row_height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	if control is CheckBox:
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(control)
	return row
