extends RefCounted
## Shared UI builders. Referenced via preload (const UIHelpers := preload(...)) so it
## resolves in headless runs without a global-class-cache rescan. The custom checkbox is the borderless, right-aligned tickbox
## used in the tile panel's setting rows ("sell surplus" etc.) — no button box/outline.

const CHECKBOX_ICON_SIZE := 18

# Quantity-pill colours — the navy/paper used by the recipe-diagram badge so the
# pill reads identically wherever it appears (recipe flow, deposits overlay…).
const PILL_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const PILL_PAPER := Color(0.995234, 0.930806, 0.763265, 1.0)

const GoodIcons := preload("res://scripts/good_icons.gd")
const GOODS_FRAME_TEX := preload("res://assets/ui/goods_frame_plate_sm.png")
const BevelEdge := preload("res://scripts/bevel_edge.gd")
const ICON_FRAME_MARGIN := 12   # the goods plate's 9-slice (NinePatch) margin per side
const ICON_INSET := 9           # icon sits this far in from the frame edge
const ICON_ZOOM := 2            # icon overflows its slot by this many px each side (zoom)

## The single source of truth for the framed + bevelled goods icon. Layers, all
## full-rect so the icon inset and the bevel rim are positioned independently of
## the plate's 9-slice margins (the old StyleBoxTexture content_margin forced both
## ~12px in, pushing the rim into the middle of the art):
##   1. NinePatchRect — the off-white plate, edge to edge.
##   2. clip(ICON_INSET) → icon(zoom) — the art, inset and slightly zoomed/clipped.
##   3. BevelEdge — the raised rim, BevelEdge.INSET px in from the frame edge.
## `frame_size` is the outer plate; `prefer_small` picks the small icon variant.
static func make_framed_good_icon(good_id: String, internal_name: String, frame_size: int = 60, prefer_small: bool = true) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(frame_size, frame_size)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Plate (9-slice off-white frame) fills the whole node.
	var plate := NinePatchRect.new()
	plate.texture = GOODS_FRAME_TEX
	plate.patch_margin_left = ICON_FRAME_MARGIN
	plate.patch_margin_top = ICON_FRAME_MARGIN
	plate.patch_margin_right = ICON_FRAME_MARGIN
	plate.patch_margin_bottom = ICON_FRAME_MARGIN
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	# Icon, inset ICON_INSET from the frame edge; it overflows its clip by ICON_ZOOM
	# px each side and is clipped, so the art reads as slightly zoomed-in.
	var clip := Control.new()
	clip.clip_contents = true
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.offset_left = ICON_INSET
	clip.offset_top = ICON_INSET
	clip.offset_right = -ICON_INSET
	clip.offset_bottom = -ICON_INSET
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = -ICON_ZOOM
	icon.offset_top = -ICON_ZOOM
	icon.offset_right = ICON_ZOOM
	icon.offset_bottom = ICON_ZOOM
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = GoodIcons.texture_for(good_id, internal_name, prefer_small)
	if tex != null:
		icon.texture = tex
	clip.add_child(icon)
	# Raised bevel rim, spanning the whole frame so BevelEdge.INSET is measured from
	# the frame edge — keeps the rim close to the plate border, not over the art.
	var bevel := BevelEdge.new()
	bevel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bevel)
	return root

static var _checked_tex: Texture2D = null
static var _unchecked_tex: Texture2D = null

## The quantity pill from the recipe diagram: a navy capsule with a cream outline
## and cream text. Short text (≤1 char) renders as a circle; longer text widens
## into a pill. Returns a self-contained PanelContainer with the label inside.
static func make_quantity_pill(text: String, height: int = 24, text_size: int = 14) -> PanelContainer:
	var width: int = height
	if text.length() > 1:
		width = maxi(height, (text.length() * 9) + 14)

	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(width, height)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = PILL_NAVY
	style.border_color = PILL_PAPER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	var radius := int(height / 2.0)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	pill.add_theme_stylebox_override("panel", style)

	var label_settings := LabelSettings.new()
	label_settings.font_color = PILL_PAPER
	label_settings.font_size = text_size

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, height)
	label.label_settings = label_settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label)
	return pill

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
