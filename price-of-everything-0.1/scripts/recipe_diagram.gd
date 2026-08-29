extends RefCounted
## THE reusable recipe diagram — the DS-blessed "recipe strip" look, extracted from
## building_detail_panel_v2 so every panel renders a recipe identically. A cream
## parchment card with a thin navy inset outline holding:
##     inputs  →  navy power-arrow (carries the MW draw + bolt)  →  output
## Good icons are UNFRAMED chroma art that bleeds ~20% past its slot (the BDP look);
## quantities sit in a navy pill on each icon's bottom-right (with an optional
## struck base→effective delta + green/red rim when a modifier is in play).
##
## Referenced via `const RecipeDiagram := preload("res://scripts/recipe_diagram.gd")`
## so it resolves in headless runs without a class-cache rescan (same convention as
## ui_helpers.gd). Two entry points:
##   • build(flow)        — from a BuildingReadout.flow() dict (a live building).
##   • from_recipe(recipe) — from a Catalog recipe dict (no building instance; used
##                            by the encyclopedia). No modifiers, so plain pills.

const GoodIcons := preload("res://scripts/good_icons.gd")

const CREAM := Color(0.995234, 0.930806, 0.763265)      # recipe-strip parchment
const CREAM_INK := Color(0.0, 0.119856, 0.243095)       # navy ink on the parchment
const RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"
const CARD_HEIGHT := 156

# Navy right-pointing arrowhead (drawn) — the head of the recipe arrow.
class _ArrowHead extends Control:
	var col := Color(0.0, 0.119856, 0.243095)
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, size.y * 0.5), Vector2(0, size.y)]), col)

# A thin navy outline rectangle inset from the card edge (the recipe card's inner border).
class _InsetOutline extends Control:
	var col := Color(0.0, 0.119856, 0.243095)
	var inset := 4.0
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), col, false, 1.5)

## Build a recipe strip from a flow dict:
##   {inputs:[{good_id,internal,qty}], output:{good_id,internal,qty,base_qty},
##    power_in:int, mod_pct:int}
static func build(flow: Dictionary, card_height: int = CARD_HEIGHT) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(0)   # squared corners
	style.set_content_margin_all(0)  # children fill the card so the outline sits 4px from the edge
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(0, card_height)
	var outline := _InsetOutline.new()
	outline.col = CREAM_INK
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(outline)

	card.clip_contents = false  # let big recipe icons bleed past the card edge
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(row)

	var inputs: Array = flow.get("inputs", [])
	if inputs.is_empty():
		var none := Label.new()
		none.text = "No inputs"
		none.add_theme_color_override("font_color", CREAM_INK)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(none)
	else:
		row.add_child(_recipe_side(inputs))

	row.add_child(_recipe_arrow(int(flow.get("power_in", 0))))

	var output: Dictionary = flow.get("output", {})
	if not output.is_empty():
		var out_wrap := CenterContainer.new()
		out_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_wrap.clip_contents = false
		out_wrap.add_child(_recipe_icon(str(output.get("good_id", "")), str(output.get("internal", "")),
			int(output.get("qty", 0)), 126, 3, int(output.get("base_qty", -1)), int(flow.get("mod_pct", 0))))
		row.add_child(out_wrap)
	return card

## Convenience: build the strip straight from a Catalog recipe dict (no building
## instance, so no modifiers — plain pills, base output qty, raw energy_req).
static func from_recipe(recipe: Dictionary, card_height: int = CARD_HEIGHT) -> PanelContainer:
	return build(flow_from_recipe(recipe), card_height)

## A flow dict for a recipe with no live building context. output.base_qty = -1 so
## the pill renders plain (no struck delta).
static func flow_from_recipe(recipe: Dictionary) -> Dictionary:
	var inputs: Array = []
	for inp in recipe.get("inputs", []):
		inputs.append({
			"good_id": str(inp.get("good_id", "")),
			"internal": str(inp.get("internal_name", "")),
			"qty": int(inp.get("qty", 0)),
		})
	var output: Dictionary = {}
	var outs: Array = recipe.get("outputs", [])
	if not outs.is_empty():
		var o: Dictionary = outs[0]
		output = {
			"good_id": str(o.get("good_id", "")),
			"internal": str(o.get("internal_name", "")),
			"qty": int(o.get("qty", 0)),
			"base_qty": -1,
		}
	return {
		"inputs": inputs,
		"output": output,
		"power_in": int(recipe.get("energy_req", 0)),
		"mod_pct": 0,
	}

# One side of the diagram (inputs): a single hero icon, or a centred 2-col grid.
static func _recipe_side(items: Array) -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = false
	if items.size() == 1:
		var it: Dictionary = items[0]
		wrap.add_child(_recipe_icon(str(it.get("good_id", "")), str(it.get("internal", "")), int(it.get("qty", 0)), 126, 3))
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.clip_contents = false
		grid.add_theme_constant_override("h_separation", DS.SP["SM"])
		grid.add_theme_constant_override("v_separation", DS.SP["SM"])
		for it in items:
			grid.add_child(_recipe_icon(str(it.get("good_id", "")), str(it.get("internal", "")), int(it.get("qty", 0)), 58, 1))
		wrap.add_child(grid)
	return wrap

# An UNFRAMED recipe-diagram icon: bare chroma art centred in a `size` slot but drawn
# `bleed` px larger on every side (clip off) so it overflows ~20% past the slot.
static func _recipe_icon(good_id: String, internal: String, qty: int, size: int, bleed: int, base_qty: int = -1, mod_pct: int = 0) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size, size)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.clip_contents = false
	if good_id != "":
		slot.tooltip_text = Catalog.get_display_name(good_id)
	# Power drawn AS A GOOD (an output flowing somewhere) uses its isometric goods icon,
	# the same art the empire plates show (owner 2026-08-29). The flat lightning glyph is
	# reserved for the ENERGY badge on the arrow — the recipe grammar's cost marker.
	var tex: Texture2D = GoodIcons.texture_for_size(good_id, internal, float(size))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = -bleed
		tr.offset_top = -bleed
		tr.offset_right = bleed
		tr.offset_bottom = bleed
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
	else:
		var chip := Label.new()
		chip.text = internal.substr(0, 2).to_upper() if internal != "" else "?"
		chip.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip.add_theme_color_override("font_color", CREAM_INK)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(chip)
	slot.add_child(_qty_pill(qty, base_qty, mod_pct))
	return slot

# Navy qty pill overhanging an icon's bottom-right. With a modifier (base != qty) it
# shows the struck base + effective and a green/red 2px outline; else a plain pill.
static func _qty_pill(qty: int, base_qty: int = -1, _mod_pct: int = 0) -> Control:
	var has_delta := base_qty >= 0 and base_qty != qty
	var content := ("%d %d" % [base_qty, qty]) if has_delta else str(qty)
	var h := 22
	var w := maxi(h, content.length() * 9 + 14)
	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(w, h)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.offset_left = -w + 8
	pill.offset_top = -h + 8
	pill.offset_right = 8
	pill.offset_bottom = 8
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(h / 2.0))
	st.set_border_width_all(2)
	st.border_color = (DS.PALETTE["OK"] if qty > base_qty else DS.PALETTE["DANGER"]) if has_delta else DS.PALETTE["BORDER_STRONG"]
	pill.add_theme_stylebox_override("panel", st)
	if has_delta:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.text = "[center][s][color=#7f8fa5]%d[/color][/s] [color=#eaf1f8]%d[/color][/center]" % [base_qty, qty]
		pill.add_child(rt)
	else:
		var lbl := Label.new()
		lbl.theme_type_variation = "Numeric"
		lbl.text = str(qty)
		lbl.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(lbl)
	return pill

# Navy filled arrow: a rounded-left body carrying the power label + bolt, then a triangle head.
static func _recipe_arrow(power_in: int) -> Control:
	var arrow := HBoxContainer.new()
	arrow.add_theme_constant_override("separation", 0)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var body_h := 46
	var body := PanelContainer.new()
	body.custom_minimum_size = Vector2(0, body_h)
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bst := StyleBoxFlat.new()
	bst.bg_color = CREAM_INK
	bst.corner_radius_top_left = 6
	bst.corner_radius_bottom_left = 6
	bst.content_margin_left = 12
	bst.content_margin_right = 8
	bst.content_margin_top = 4
	bst.content_margin_bottom = 4
	body.add_theme_stylebox_override("panel", bst)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(hb)
	if power_in > 0:
		var n := Label.new()
		n.theme_type_variation = "Numeric"
		n.add_theme_font_size_override("font_size", 21)
		n.text = str(power_in)
		n.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(n)
		var bolt := _load_texture_rect(RECIPE_POWER_ICON_PATH, Vector2(18, 18))
		if bolt != null:
			hb.add_child(bolt)
		else:
			var kw := Label.new()
			kw.text = "MW"
			kw.add_theme_color_override("font_color", DS.PALETTE["WARN"])
			hb.add_child(kw)
	else:
		var nop := Label.new()
		nop.text = "no power"
		nop.theme_type_variation = "Caption"
		nop.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
		hb.add_child(nop)
	arrow.add_child(body)
	var head := _ArrowHead.new()
	head.col = CREAM_INK
	head.custom_minimum_size = Vector2(28, body_h)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_child(head)
	return arrow

static func _load_texture_rect(path: String, size: Vector2) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr
