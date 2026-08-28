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
const GoodIconHover := preload("res://scripts/good_icon_hover.gd")
const GOODS_FRAME_TEX := preload("res://assets/ui/goods_frame_plate_sm.png")
const BevelEdge := preload("res://scripts/bevel_edge.gd")
const ICON_FRAME_MARGIN := 12   # the goods plate's 9-slice (NinePatch) margin per side
const ICON_INSET := 9           # icon sits this far in from the frame edge
const ICON_ZOOM := 2            # icon overflows its slot by this many px each side (zoom)

## Give a directly-rendered good icon (a plain TextureRect, not the framed
## helper) the same hover behaviour: show the good's name, then any tooltip an
## ancestor row would have shown. Use at the direct GoodIcons.texture_for sites
## (recipe flow diagrams, stockpile bars) so every good icon names itself.
static func attach_good_name_tooltip(ctrl: Control, good_id: String) -> void:
	if ctrl == null or good_id == "":
		return
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.tooltip_text = Catalog.get_display_name(good_id)

## The single source of truth for the framed + bevelled goods icon. Layers, all
## full-rect so the icon inset and the bevel rim are positioned independently of
## the plate's 9-slice margins (the old StyleBoxTexture content_margin forced both
## ~12px in, pushing the rim into the middle of the art):
##   1. NinePatchRect — the off-white plate, edge to edge.
##   2. clip(ICON_INSET) → icon(zoom) — the art, inset and slightly zoomed/clipped.
##   3. BevelEdge — the raised rim, BevelEdge.INSET px in from the frame edge.
## `frame_size` is the outer plate, and it also picks the art tier — the frame IS the display
## size, so there is nothing for a caller to decide separately.
static func make_framed_good_icon(good_id: String, internal_name: String, frame_size: int = 60) -> Control:
	# GoodIconHover root: PASS lets clicks reach clickable parents while the icon
	# still supplies a hover tooltip (good name + any ancestor tooltip).
	var root := GoodIconHover.new()
	root.good_id = good_id
	root.custom_minimum_size = Vector2(frame_size, frame_size)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_PASS
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
	var tex: Texture2D = GoodIcons.texture_for_size(good_id, internal_name, float(frame_size))
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

## The good icon WITHOUT the metal plate: a plain cream rounded square with the art on it.
##
## The framed version above is the market/recipe treatment — a 9-slice plate and a raised
## bevel — which is a lot of chrome when a row is listing what is simply sitting on a tile.
## This is the same art on the same cream, minus the frame, so a list of goods reads as a
## list rather than as a shelf of trophies.
##
## `size` is the whole tile; callers overlay the navy quantity pill on it exactly as the
## recipe cards do (see building_detail_panel_v2._good_icon_pill).
## A "Requires research: X" line where X is an underlined link into the Research tree.
## The requirement is the most actionable thing on an upgrade sheet and used to be flat
## text, leaving the player to find the tech by hand (owner 2026-08-23).
static func make_research_requirement_link(gate: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var lead := Label.new()
	lead.theme_type_variation = "Body"
	lead.text = "Requires research: "
	lead.add_theme_color_override("font_color", color)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead)
	var link := Label.new()
	link.theme_type_variation = "Body"
	link.text = gate
	link.add_theme_color_override("font_color", color)
	# Underline via the font itself, so it tracks the label's size and wrapping rather than
	# being a drawn rule that drifts when the text reflows.
	link.add_theme_constant_override("underline_alignment", 1)
	link.mouse_filter = Control.MOUSE_FILTER_STOP
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.tooltip_text = "Open %s in the Research tree" % gate
	var underline := ColorRect.new()
	underline.color = color
	underline.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	underline.offset_top = -2.0
	underline.custom_minimum_size = Vector2(0, 1)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	link.add_child(underline)
	link.gui_input.connect(func(e: InputEvent) -> void:
		if not (e is InputEventMouseButton):
			return
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			MatchState.research_search_requested.emit(gate))
	row.add_child(link)
	return row

static func make_plain_good_icon(good_id: String, internal_name: String, size: int = 56) -> Control:
	var root := GoodIconHover.new()
	root.good_id = good_id
	root.custom_minimum_size = Vector2(size, size)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var plate := PanelContainer.new()
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PILL_PAPER
	style.set_corner_radius_all(int(round(size * 0.18)))
	plate.add_theme_stylebox_override("panel", style)
	root.add_child(plate)
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := int(round(size * 0.10))
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = GoodIcons.texture_for_size(good_id, internal_name, float(size))
	if tex != null:
		icon.texture = tex
	root.add_child(icon)
	return root


## The cream chip on its own, for a texture that is not a good — the infrastructure art, in
## practice. The transport panel sets pipes and reinforced pipes beside goods that all wear
## this plate, and only the infrastructure sat bare on the navy (owner, 25 Aug).
static func make_plain_texture_icon(texture: Texture2D, size: int = 38) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := PanelContainer.new()
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PILL_PAPER
	style.set_corner_radius_all(int(round(size * 0.18)))
	plate.add_theme_stylebox_override("panel", style)
	root.add_child(plate)
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := int(round(size * 0.10))
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture
	root.add_child(icon)
	return root


## The navy quantity pill, positioned to overhang an icon's bottom-right — the recipe-card
## placement. Add it as a CHILD of an icon returned above.
static func make_overlaid_quantity_pill(text: String, height: int = 22) -> Control:
	var pill := make_quantity_pill(text, height, 12)
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var w: float = pill.custom_minimum_size.x
	pill.offset_left = -w + 6.0
	pill.offset_top = -float(height) + 6.0
	pill.offset_right = 6.0
	pill.offset_bottom = 6.0
	return pill


## Make a good icon a LINK to that good in the Goods Graph.
##
## The icons are built by the helpers above and handed out all over the UI, so the click
## behaviour is attached here rather than rebuilt at each site: one place decides what a
## good icon does when you click it, and every panel that opts in agrees.
##
## AN ICON ON A CLICKABLE CARD DEFERS TO THE CARD. A building card, a construct row or a
## ledger line is one target as far as the player is concerned; swallowing part of it so a
## small picture inside can do something else makes the card feel broken exactly where it
## looks most pressable. So the icon keeps MOUSE_FILTER_PASS, and on a click it walks up
## for a clickable ancestor: if there is one it does nothing and the event carries on to
## the card, and only a standing-alone icon acts as a link.
##
## `always` overrides that for the one place the split is deliberate: an encyclopedia
## entry, where the row opens the article and the icon opens the web, which is what the
## player asked for there.
static func link_good_icon_to_graph(ctrl: Control, good_id: String, always := false) -> void:
	if ctrl == null or good_id == "":
		return
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP if always else Control.MOUSE_FILTER_PASS
	var name := Catalog.get_display_name(good_id)
	if always:
		ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		ctrl.tooltip_text = ("%s — click to see how it is made" % name) if name != "" else "Show in the Goods Graph"
	ctrl.gui_input.connect(func(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			return
		if not always and _clickable_ancestor(ctrl) != null:
			return   # the card owns this click; let it through untouched
		ctrl.accept_event()
		MatchState.goods_graph_good_requested.emit(good_id))
	if not always:
		# The hand cursor and the hint can only be promised once the icon is in a tree and
		# its ancestors are known, so they are settled on entry rather than here.
		ctrl.tree_entered.connect(func() -> void:
			if _clickable_ancestor(ctrl) != null:
				return
			ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			ctrl.tooltip_text = ("%s — click to see how it is made" % name) if name != "" else "Show in the Goods Graph")


## The nearest ancestor that is itself a click target — a button, or a card that has taken
## the hand cursor. Stops at the first one; returns null when the icon stands alone.
static func _clickable_ancestor(ctrl: Control) -> Control:
	var n: Node = ctrl.get_parent()
	while n != null:
		if n is BaseButton:
			return n as Control
		if n is Control:
			var c := n as Control
			var clickable: bool = (c.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND
					and c.mouse_filter != Control.MOUSE_FILTER_IGNORE)
			if clickable:
				return c
		n = n.get_parent()
	return null


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

## Telemetry consent row (shared by the New Game and Tutorial screens): opt-out
## checkbox + a hover caption explaining exactly what gets sent. Returns
## {"row": Control, "checkbox": CheckBox}. See docs/telemetry-spec.md §2.
static func make_telemetry_consent_row(checked: bool) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var cb := CheckBox.new()
	cb.text = "  Send in-game performance metrics to the developer"
	cb.add_theme_icon_override("unchecked", checkbox_icon(false))
	cb.add_theme_icon_override("checked", checkbox_icon(true))
	cb.add_theme_icon_override("unchecked_disabled", checkbox_icon(false))
	cb.add_theme_icon_override("checked_disabled", checkbox_icon(true))
	cb.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	cb.button_pressed = checked
	row.add_child(cb)

	var hint := Label.new()
	hint.text = "      What kind of metrics do you send?"
	hint.theme_type_variation = &"Caption"
	hint.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	hint.tooltip_text = "Revenue, profit, goods produced per turn, buildings count, loans.\nNothing outside the game is collected."
	# Labels default to MOUSE_FILTER_IGNORE, which suppresses tooltips.
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(hint)

	return {"row": row, "checkbox": cb}


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


## Ledger-grammar rule (Construct V3, spec §4): a fine full-width line. Rules are
## STRUCTURE, not status — they stay in the DS's soft cream and never take a
## semantic colour. double_rule is the classic ledger double line that sits above
## a verdict/total band.
class SectionRule extends Control:
	var double_rule := false

	func _init(is_double: bool = false) -> void:
		double_rule = is_double
		custom_minimum_size = Vector2(0, 5.0 if is_double else 2.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var tone: Color = DS.PALETTE["BORDER_SOFT"]
		draw_line(Vector2(0, 1), Vector2(size.x, 1), tone, 1.0)
		if double_rule:
			draw_line(Vector2(0, 4), Vector2(size.x, 4), tone, 1.0)


static func make_section_rule(double_rule: bool = false) -> Control:
	return SectionRule.new(double_rule)


## Ruled section head: rule above a small-caps title (the "SectionRuled" label
## variation). Replaces coloured tick-bar headings — same hierarchy, zero status
## colour spent on furniture. Pass double_rule=true only for the verdict band.
static func make_ruled_section_head(text: String, double_rule: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	box.add_child(SectionRule.new(double_rule))
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SectionRuled"
	box.add_child(label)
	return box


# --- mini recipe diagram ---------------------------------------------------------------------
# The compressed recipe glance shared between the Construct panel's browse-list recipe cards and
# the building detail panel's "Change recipe" sheet, so both stay visually IDENTICAL rather than
# drifting via two separate copies. Bare good icons only (no quantity pills, no power-cost badge)
# — inputs joined by "+", a solid navy arrow, then outputs joined by "+": the SHAPE of a recipe,
# not its numbers. These constants intentionally duplicate construct_panel_v2.gd's own
# DIAGRAM_PAPER/DIAGRAM_NAVY values rather than reaching into that panel's locals — this family
# needs to render correctly from either script, and the two colours are exceedingly unlikely to
# ever drift independently.
const MINI_DIAGRAM_PAPER := Color("#ffefc3")
const MINI_DIAGRAM_NAVY := Color("#001e3f")
const MINI_ICON_SIZE := 40
const MINI_ARROW_SIZE := Vector2(48, 30)
const MINI_RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"

## A SOLID navy arrow — same silhouette as recipe_arrow.png (a hollow outline) but
## filled, for this compressed look. Drawn rather than a second baked asset, same
## technique construct_panel_v2.gd's RecipePowerPentagon already uses for its shape.
class MiniRecipeArrow extends Control:
	func _draw() -> void:
		var cy := size.y * 0.5
		var half_shaft := size.y * 0.21
		var shaft_w := size.x * 0.55
		var poly := PackedVector2Array([
			Vector2(0, cy - half_shaft), Vector2(shaft_w, cy - half_shaft), Vector2(shaft_w, 0),
			Vector2(size.x, cy), Vector2(shaft_w, size.y), Vector2(shaft_w, cy + half_shaft),
			Vector2(0, cy + half_shaft),
		])
		draw_colored_polygon(poly, MINI_DIAGRAM_NAVY)


## Cream, rounded corners, one icon tall plus a little padding — full width of
## whatever it's given (callers set size_flags_horizontal = EXPAND_FILL so every
## card in a list renders at the same width, regardless of its own input/output
## count; _recipe_diagram's internal row already centres a narrower icon group
## within extra width, same idea as the full diagram).
static func mini_recipe_diagram(recipe: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "MiniRecipeDiagramCard"   # test/tutorial spotlight handle
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = MINI_DIAGRAM_PAPER
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", card_style)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, MINI_ICON_SIZE)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		var raw := Label.new()
		raw.text = "Raw"
		raw.add_theme_font_size_override("font_size", 12)
		raw.add_theme_color_override("font_color", MINI_DIAGRAM_NAVY)
		row.add_child(raw)
	else:
		for i in inputs.size():
			row.add_child(_mini_flow_icon(str((inputs[i] as Dictionary).get("good_id", ""))))
			if i < inputs.size() - 1:
				row.add_child(_mini_plus())

	var arrow_art := MiniRecipeArrow.new()
	arrow_art.name = "MiniRecipeArrow"   # test handle — an inner class's get_class() reports its base (Control), not its own name
	arrow_art.custom_minimum_size = MINI_ARROW_SIZE
	arrow_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow_art)

	var outputs: Array = recipe.get("outputs", [])
	if outputs.is_empty() and str(recipe.get("output_good_id", "")) != "":
		outputs = [{"good_id": recipe.get("output_good_id", "")}]
	for i in outputs.size():
		row.add_child(_mini_flow_icon(str((outputs[i] as Dictionary).get("good_id", ""))))
		if i < outputs.size() - 1:
			row.add_child(_mini_plus())
	return card


## One bare good icon for the mini diagram — no plate, no pill, no bevel. Power
## reuses the same lightning glyph the full diagram's energy badge uses (power has
## no chroma good-icon art of its own to draw here).
static func _mini_flow_icon(good_id: String) -> TextureRect:
	var art := TextureRect.new()
	if Catalog.get_internal_name(good_id) == "power":
		art.texture = load(MINI_RECIPE_POWER_ICON_PATH) as Texture2D
	else:
		art.texture = GoodIcons.texture_for_size(good_id, Catalog.get_internal_name(good_id), float(MINI_ICON_SIZE))
	art.custom_minimum_size = Vector2(MINI_ICON_SIZE, MINI_ICON_SIZE)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS, not IGNORE: this is the only thing carrying the good's name
	if good_id != "":
		art.tooltip_text = Catalog.get_display_name(good_id)
	return art


static func _mini_plus() -> Label:
	var plus := Label.new()
	plus.text = "+"
	# "Numeric" for its bold cut (Plex SemiBold, the theme's one bold face) — size and
	# colour below still override its own defaults, same as anywhere else this theme
	# variation gets reused purely for weight.
	plus.theme_type_variation = "Numeric"
	plus.add_theme_font_size_override("font_size", 20)
	plus.add_theme_color_override("font_color", MINI_DIAGRAM_NAVY)
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return plus
