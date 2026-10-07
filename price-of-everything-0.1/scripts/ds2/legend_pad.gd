extends RefCounted
## DS2: the pad a map legend sits on (the bottom-left legends: the map modes', build mode's, the transfer's). Dark
## moulded plastic with its four corners cut off (res://assets/ui/bdp_v3/legend_pad.png, render set `dockpad`,
## drawn as a 9-slice whose corner reaches past the cut). `dress` swaps a legend panel's flat box for the pad
## while UiPrefs.use_legend_ds2 is on, keeping the box's own content margins; `undress` puts the box back.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const PAD: Texture2D = preload("res://assets/ui/bdp_v3/legend_pad.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (legend_pad), in layout px: the render's shadow room and its 9-slice corner.
const MARGIN := 14.0
const CORNER := 44.0
## The least room between the pad's edge and what it holds, so print stays clear of the cut corners.
const MIN_PAD := 12.0
const META_BOX := "legend_pad_box"


## Puts `panel` on the pad when the DS2 legend look is on. Safe to call again.
static func dress(panel: PanelContainer) -> void:
	if not UiPrefs.use_legend_ds2:
		undress(panel)
		return
	if panel.has_meta(META_BOX):
		return
	var box := panel.get_theme_stylebox("panel")
	panel.set_meta(META_BOX, box)
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = maxf(box.content_margin_left, MIN_PAD) if box != null else MIN_PAD
	bare.content_margin_right = maxf(box.content_margin_right, MIN_PAD) if box != null else MIN_PAD
	bare.content_margin_top = maxf(box.content_margin_top, MIN_PAD) if box != null else MIN_PAD
	bare.content_margin_bottom = maxf(box.content_margin_bottom, MIN_PAD) if box != null else MIN_PAD
	panel.add_theme_stylebox_override("panel", bare)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var paint := func() -> void:
		if panel.has_meta(META_BOX):
			Nine.paint(panel, PAD, Rect2(Vector2.ZERO, panel.size).grow(MARGIN / CAPTURE_SCALE), (MARGIN + CORNER) * TEXELS_PER_PIXEL / CAPTURE_SCALE)
	if not panel.has_meta("legend_pad_painter"):
		panel.set_meta("legend_pad_painter", true)
		panel.draw.connect(paint)
	panel.queue_redraw()


## Takes `panel` off the pad, back to the box it had.
static func undress(panel: PanelContainer) -> void:
	if not panel.has_meta(META_BOX):
		return
	var box: Variant = panel.get_meta(META_BOX)
	panel.remove_meta(META_BOX)
	if box is StyleBox:
		panel.add_theme_stylebox_override("panel", box)
	else:
		panel.remove_theme_stylebox_override("panel")
	panel.queue_redraw()
