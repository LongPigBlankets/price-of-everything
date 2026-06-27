extends Control
## Empire view — a building node as a real Control (Milestone 6: research-panel metal plate).
##
## A metallic navy plate styled like the research-panel nodes: rounded gold-bordered plate with a
## TOP-LEFT → BOTTOM-RIGHT lit gradient, machined-bevel lip, corner rivets and a drop shadow, holding
## CRISP Control children — centred full title ("Type - Output - Letter"), the building + output good
## icon pair (good icon on a cream chip with the recipe-card qty pill), and the RAG row (4 colour
## indicators + a £ number + a Δ…% number, all hover-tooltipped exactly like the detail panel).
## Built once via setup(); the graph layer only moves it (position), never scales it. Clicking it
## opens that building's detail panel. Size scales with the building's level (L2 x1.5, L3 x2.25).

const _CREAM := Color(0.995234, 0.930806, 0.763265)        # recipe-card OFF_WHITE / DS ACCENT
const _PILL_NAVY := Color(0.0, 0.119856, 0.243095)         # recipe-card BADGE_NAVY
const _BORDER := Color(0.995, 0.931, 0.763, 0.95)          # gold border
const _GOLD := Color(0.995, 0.931, 0.763, 1.0)
const _TEXT := Color(0.88, 0.92, 0.97, 1.0)
const _BG := Color(0.04, 0.115, 0.20, 1.0)                 # panel navy base
const _GREY := Color(0.45, 0.48, 0.52)
const _TOOLTIP_NAVY := Color(0.03, 0.07, 0.13)             # detail-panel TOOLTIP_NAVY
const _LEVEL_SCALE := [1.0, 1.0, 1.5, 2.25]

static var _shared_tooltip_theme: Theme = null

var instance_id: String = ""
var _level := 1
var _bg_style: StyleBoxFlat
var _rivet_inset := 13.0


## Build the panel from a node dict (see empire_graph.gd). Sizes everything by the building's level.
func setup(node: Dictionary) -> void:
	instance_id = str(node.get("iid", ""))
	_level = int(node.get("level", 1))
	var cs: float = _LEVEL_SCALE[clampi(_level, 1, 3)]
	var sz: Vector2 = (node["half"] as Vector2) * 2.0
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP          # clickable → opens the building detail panel
	clip_contents = false
	_rivet_inset = 13.0 * cs
	for c in get_children():
		c.queue_free()

	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = _BG
	_bg_style.border_color = _GOLD if _level >= 3 else _BORDER
	_bg_style.set_border_width_all(maxi(2, int(round((3.5 if _level >= 3 else 2.0)))))
	_bg_style.set_corner_radius_all(int(round(12.0 * cs)))
	_bg_style.shadow_color = Color(0, 0, 0, 0.45)
	_bg_style.shadow_size = int(round(7.0 * cs))

	var m := int(round(9.0 * cs))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, m)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", int(round(5.0 * cs)))
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# Title — full public name, centred.
	var title := Label.new()
	title.text = str(node.get("name", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.add_theme_font_size_override("font_size", int(round(15.0 * cs)))
	title.add_theme_color_override("font_color", _TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(title)

	# Icon pair — building icon + good icon, same size (100px at full zoom), centred, tight.
	var isz := 100.0 * cs
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", int(round(10.0 * cs)))
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icons)
	icons.add_child(_make_icon(node.get("icon"), isz))
	if str(node.get("output_good", "")) != "":
		icons.add_child(_make_good_icon(node.get("good_icon"), int(node.get("output_qty", 0)), isz, cs))

	# RAG row — 4 colour indicators (20x30) + £number + Δ…% number, each hover-tooltipped, centred.
	var rag: Array = node.get("rag", [])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(round(10.0 * cs)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	for i in range(mini(4, rag.size())):
		var sq := ColorRect.new()
		sq.color = rag[i].get("color", _GREY)
		sq.custom_minimum_size = Vector2(30.0 * cs, 20.0 * cs)
		_wire_tooltip(sq, str(rag[i].get("tooltip", "")))
		row.add_child(sq)
	if rag.size() >= 6:
		row.add_child(_make_value(str(rag[4].get("text", "")), rag[4].get("color", _GREY), str(rag[4].get("tooltip", "")), cs))
		row.add_child(_make_value(str(rag[5].get("text", "")), rag[5].get("color", _GREY), str(rag[5].get("tooltip", "")), cs))

	# Level tag, top-right corner.
	if _level >= 2:
		var lt := Label.new()
		lt.text = "L%d" % _level
		lt.add_theme_font_size_override("font_size", int(round(13.0 * cs)))
		lt.add_theme_color_override("font_color", _GOLD)
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lt.offset_left = -int(round(38.0 * cs))
		lt.offset_right = -int(round(8.0 * cs))
		lt.offset_top = int(round(6.0 * cs))
		add_child(lt)

	queue_redraw()


## Open this building's detail panel on click (reuses the existing deep-link path in world_map).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if instance_id != "":
			MatchState.focus_building_requested.emit(instance_id)
		accept_event()


func _make_icon(tex, isz: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(isz, isz)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Good icon on a cream chip with the recipe-card qty pill at bottom-right.
func _make_good_icon(tex, qty: int, isz: float, cs: float) -> Control:
	var cont := Control.new()
	cont.custom_minimum_size = Vector2(isz, isz)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := PanelContainer.new()
	chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = _CREAM
	chip_style.set_corner_radius_all(int(round(6.0 * cs)))
	chip.add_theme_stylebox_override("panel", chip_style)
	cont.add_child(chip)

	if tex != null:
		var pad := int(round(isz * 0.12))
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = pad
		tr.offset_top = pad
		tr.offset_right = -pad
		tr.offset_bottom = -pad
		cont.add_child(tr)

	cont.add_child(_make_badge(qty, isz, cs))
	return cont


## Recipe-card style qty pill: navy bg, cream border, fully rounded, number only, bottom-right.
func _make_badge(qty: int, slot: float, cs: float) -> Control:
	var text := str(qty)
	var h := int(round(22.0 * cs))
	var fs := int(round(13.0 * cs))
	var w: int = h if text.length() <= 1 else maxi(h, text.length() * int(round(9 * cs)) + int(round(12 * cs)))
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overlap := int(round(4.0 * cs))
	badge.offset_left = -w + overlap
	badge.offset_top = -h + overlap
	badge.offset_right = overlap
	badge.offset_bottom = overlap
	var style := StyleBoxFlat.new()
	style.bg_color = _PILL_NAVY
	style.border_color = _CREAM
	style.set_border_width_all(maxi(1, int(round(2.0 * cs))))
	style.set_corner_radius_all(int(h / 2.0))
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_color_override("font_color", _CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


func _make_value(text: String, color: Color, tooltip: String, cs: float) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(round(14.0 * cs)))
	label.add_theme_color_override("font_color", color)
	_wire_tooltip(label, tooltip)
	return label


## Hover tooltip identical to the detail panel: navy styled tooltip, mouse_filter PASS so the click
## still reaches the panel (and opens the detail view).
func _wire_tooltip(ctrl: Control, tip: String) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.tooltip_text = tip
	ctrl.theme = _tooltip_theme()


static func _tooltip_theme() -> Theme:
	if _shared_tooltip_theme == null:
		var t := Theme.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = _TOOLTIP_NAVY
		sb.set_content_margin_all(6)
		t.set_stylebox("panel", "TooltipPanel", sb)
		t.set_color("font_color", "TooltipLabel", _CREAM)
		_shared_tooltip_theme = t
	return _shared_tooltip_theme


# --- metal plate drawing (research-panel look) -------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _bg_style != null:
		draw_style_box(_bg_style, r)
	# TL→BR lit gradient sheen (inset to stay within the rounded corners).
	var ir := r.grow(-5.0)
	var pts := PackedVector2Array([
		ir.position, Vector2(ir.end.x, ir.position.y), ir.end, Vector2(ir.position.x, ir.end.y)])
	draw_polygon(pts, _grad_colors(pts, Color(1, 1, 1, 0.10), Color(0, 0, 0, 0.16)))
	# Machined bevel lip: light top/left, shadow bottom/right.
	var b := r.grow(-3.0)
	draw_line(b.position, Vector2(b.end.x, b.position.y), Color(1, 1, 1, 0.18), 1.5)
	draw_line(b.position, Vector2(b.position.x, b.end.y), Color(1, 1, 1, 0.12), 1.5)
	draw_line(Vector2(b.position.x, b.end.y), b.end, Color(0, 0, 0, 0.30), 1.5)
	draw_line(Vector2(b.end.x, b.position.y), b.end, Color(0, 0, 0, 0.22), 1.5)
	# Corner rivets.
	var rad := maxf(3.0, 3.5 * (size.x / 304.0))
	for c in [Vector2(r.position.x + _rivet_inset, r.position.y + _rivet_inset),
			Vector2(r.end.x - _rivet_inset, r.position.y + _rivet_inset),
			Vector2(r.position.x + _rivet_inset, r.end.y - _rivet_inset),
			Vector2(r.end.x - _rivet_inset, r.end.y - _rivet_inset)]:
		draw_circle(c, rad, Color(0.58, 0.61, 0.62, 1.0))
		draw_circle(c + Vector2(-1.0, -1.0) * rad * 0.4, rad * 0.5, Color(1, 1, 1, 0.18))


## Per-vertex colours for a TOP-LEFT (light) → BOTTOM-RIGHT (dark) gradient (research-panel math).
func _grad_colors(pts: PackedVector2Array, light: Color, dark: Color) -> PackedColorArray:
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	var denom := maxf(bounds.size.x + bounds.size.y, 1.0)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf(((p.x - bounds.position.x) + (p.y - bounds.position.y)) / denom, 0.0, 1.0)
		cols.append(light.lerp(dark, t))
	return cols
