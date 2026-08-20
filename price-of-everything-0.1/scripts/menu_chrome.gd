extends RefCounted
## Shared main-menu chrome so every panel reads as one set: a dark fill with the brass
## metallic frame (baked lit top-left → bottom-right in the texture, so the lighting is
## consistent everywhere it's used). Mirrors the hexagonal logo's gold bezel. The goods
## board is deliberately NOT given this treatment.
##
## Referenced via preload const (no class_name), matching the menu scripts' headless pattern.

const BRASS_FRAME: Texture2D = preload("res://assets/ui/brass_frame.png")
const FRAME_MARGIN := 40   # 9-slice patch margin (source px): keeps the beveled corners fixed
const CORNER := 22         # fill corner radius; sits just inside the frame's rounded edge
const NAVY := Color(0, 0.07, 0.14)

# Brass palette (sampled from the logo bezel) for flat brass outlines too thin to bevel —
# e.g. the small start cards. Bright when picked out, mid otherwise.
const GOLD_HI := Color(0.965, 0.886, 0.659)   # highlight (246,226,168)
const GOLD_MID := Color(0.808, 0.667, 0.396)  # mid brass (206,170,101)
const GOLD_LO := Color(0.518, 0.408, 0.204)   # shadow (132,104,52)


## Replace a panel's border with the brass frame: set a dark fill with NO cream border, then
## overlay the frame. `panel` is anything that renders a "panel" stylebox (Panel/PanelContainer).
static func apply(panel: Control, fill: Color = NAVY) -> NinePatchRect:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(CORNER)
	panel.add_theme_stylebox_override("panel", sb)
	return add_frame(panel)


## Just overlay the brass frame filling `parent` (when the caller draws its own fill). Added on
## top and click-through. Use for a plain Control/Panel whose rect IS the frame.
static func add_frame(parent: Control) -> NinePatchRect:
	var frame := _new_frame()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(frame)
	return frame


## Overlay the brass frame at an explicit inset from `parent` (for container-type panels whose
## own child list is layout-managed, so the frame must be a free sibling instead of a child).
static func frame_rect(parent: Control, l: float, t: float, r: float, b: float) -> NinePatchRect:
	var frame := _new_frame()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = l
	frame.offset_top = t
	frame.offset_right = r
	frame.offset_bottom = b
	parent.add_child(frame)
	return frame


static func _new_frame() -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.texture = BRASS_FRAME
	frame.patch_margin_left = FRAME_MARGIN
	frame.patch_margin_right = FRAME_MARGIN
	frame.patch_margin_top = FRAME_MARGIN
	frame.patch_margin_bottom = FRAME_MARGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame
