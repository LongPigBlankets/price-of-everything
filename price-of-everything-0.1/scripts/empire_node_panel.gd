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
# Sprite-view style: the 2.5D building sprite is drawn at this fixed pixel size above the
# plate. PUBLIC because the LAYOUT has to reserve room for it — empire_graph.gd derives both
# `plate_dy` (= SPRITE_PX / 2) and the node's half-extent from it, and the edge anchoring in
# empire_graph_world.gd depends on the same value. One constant, three consumers.
const SPRITE_PX := 400.0
const GraphWorld := preload("res://scripts/empire_graph_world.gd")
# Badge area as a fraction of the sprite box. A hex inscribed in a 2h x 2h square covers ~3h^2,
# so h = sqrt(frac * SPRITE_PX^2 / 3) — 5% works out at about 52px on the 400px sprite.
const _BADGE_AREA_FRAC := 0.05
const _BADGE_GOLD := Color(0.995, 0.931, 0.763, 1.0)

static var _shared_tooltip_theme: Theme = null

var instance_id: String = ""
var _level := 1
var _bg_style: StyleBoxFlat
var _rivet_inset := 13.0
var _plate_rect := Rect2()      # metal-plate sub-rect (the whole Control in classic mode)


## Build the panel from a node dict (see empire_graph.gd). Sizes everything by the building's level.
## Two styles: CLASSIC — the whole Control is the metal plate (title, icon pair, RAG).
## SPRITE VIEW (`swap empire view sprite`, sprited buildings only) — a SPRITE_PX 2.5D sprite
## floats above with the plate attached to its bottom; the plate keeps title/good-icon/RAG but
## drops the building icon (the sprite replaced it). Unsprited buildings always use CLASSIC.
func setup(node: Dictionary) -> void:
	instance_id = str(node.get("iid", ""))
	_level = int(node.get("level", 1))
	var cs: float = _LEVEL_SCALE[clampi(_level, 1, 3)]
	# PLATE_HALF, not `half`: `half` is the LAYOUT footprint and in sprite view that is the
	# whole 400px sprite box, which would size the caption plate off the sprite.
	var plate_sz: Vector2 = (node.get("plate_half", node["half"]) as Vector2) * 2.0
	var sprite_tex = node.get("sprite")
	var sprite_mode: bool = MatchState.use_empire_sprite_view and sprite_tex != null
	var total := plate_sz
	if sprite_mode:
		# Plates stay at L1 size in sprite view: the sprite carries the building's scale (and
		# the L-tag names the level), so level-scaling the caption plate too made the row of
		# captions ragged. `plate_half` is ALREADY the L1 plate here, so no /cs rescale — that
		# only existed to undo the level-scaling that used to be baked into `half`.
		cs = 1.0
		total = Vector2(maxf(plate_sz.x, SPRITE_PX), SPRITE_PX + plate_sz.y)
	custom_minimum_size = total
	size = total
	_plate_rect = Rect2(Vector2((total.x - plate_sz.x) / 2.0, total.y - plate_sz.y), plate_sz)
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

	# The big free-floating sprite, top-centred, with the plate attached beneath it.
	if sprite_mode:
		var spr := TextureRect.new()
		spr.texture = sprite_tex
		# expand_mode BEFORE size: with the default (KEEP_SIZE) still active, the 800px
		# texture becomes the minimum size and the size assignment is clamped up to 800.
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.position = Vector2((total.x - SPRITE_PX) / 2.0, 0.0)
		spr.size = Vector2(SPRITE_PX, SPRITE_PX)
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# NO z_index shove. Pushing the sprite behind the world's _draw() also puts it behind
		# the empire view's own backdrop and it disappears outright (measured). It is also
		# unnecessary: the sprite's padding is TRANSPARENT, so a line crossing the margin was
		# always visible through it. The only lines that were ever lost were the ones crossing
		# the opaque building, and the router now refuses to cross that (see `sprite_rect`).
		add_child(spr)

		# PORT BADGE — only on buildings that ship to market, and only when enabled. Added
		# AFTER the sprite so it sits on top of it: a Control's own _draw() renders beneath
		# its children, so drawing this in the panel would put it under the building.
		var badge_icon = node.get("port_badge")
		if badge_icon != null and MatchState.show_port_badge:
			var bh: float = sqrt(_BADGE_AREA_FRAC * SPRITE_PX * SPRITE_PX / 3.0)
			# Anchored to the sprite's own CONTENT box, not the 400px frame: the frame's
			# bottom-right corner is transparent margin on most sprites, and a badge floating
			# in empty space reads as detached rather than as a mark ON the building.
			var content: Rect2 = Rect2(Vector2.ZERO, Vector2(SPRITE_PX, SPRITE_PX))
			var sr: Rect2 = node.get("sprite_rect", Rect2())
			if sr.size.x > 0.0:
				content = Rect2(sr.position + Vector2(SPRITE_PX * 0.5,
						(SPRITE_PX + plate_sz.y) * 0.5), sr.size)
			var bc := Vector2(content.end.x - bh * 0.9, content.end.y - bh * 0.9)
			var badge := Control.new()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.draw.connect(_draw_port_badge.bind(badge, bc, bh, badge_icon))
			add_child(badge)

	var m := int(round(9.0 * cs))
	var margin := MarginContainer.new()
	margin.position = _plate_rect.position
	margin.size = _plate_rect.size
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
	# Sprite view: the building sprite floats above the plate, so the plate holds only
	# the good icon. Classic (and unsprited buildings): glyph + good icon pair as always.
	if not sprite_mode:
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

	# Level tag, top-right corner of the PLATE (== the Control in classic mode).
	if _level >= 2:
		var lt := Label.new()
		lt.text = "L%d" % _level
		lt.add_theme_font_size_override("font_size", int(round(13.0 * cs)))
		lt.add_theme_color_override("font_color", _GOLD)
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lt.position = Vector2(_plate_rect.end.x - 38.0 * cs, _plate_rect.position.y + 6.0 * cs)
		lt.size = Vector2(30.0 * cs, 18.0 * cs)
		add_child(lt)

	queue_redraw()


## Open this building's detail panel on click (reuses the existing deep-link path in world_map).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if instance_id != "":
			# Two things happen on select: the detail panel opens (the existing deep-link) and
			# the empire view collapses to this building's depth-1 mini-chart.
			var w := get_parent()
			if w != null and w.has_method("focus_on"):
				w.call("focus_on", instance_id)
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


## A square cream plate with `tex` inset by `pad_frac` of the slot. Shared by the good
## icon and the 2.5D building sprites so both sit on identical plates.
func _make_chip(tex, isz: float, cs: float, pad_frac: float) -> Control:
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
		var pad := int(round(isz * pad_frac))
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
	return cont


## Good icon on a cream chip with the recipe-card qty pill at bottom-right.
func _make_good_icon(tex, qty: int, isz: float, cs: float) -> Control:
	var cont := _make_chip(tex, isz, cs, 0.12)
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
	# The metal plate covers only _plate_rect — the whole Control in classic mode, the
	# bottom strip under the sprite in sprite view.
	var r := _plate_rect if _plate_rect.size.x > 0.0 else Rect2(Vector2.ZERO, size)
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
	var rad := maxf(3.0, 3.5 * (r.size.x / 304.0))
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


## The port badge: the SAME lit gold hex the port nodes use, at badge scale, so it reads as a
## miniature of the destination rather than as a separate piece of UI. Geometry comes from the
## world's own hex helpers — one source of truth for the shape.
func _draw_port_badge(host: Control, c: Vector2, h: float, icon) -> void:
	var half := Vector2(h, h)
	var hex := GraphWorld.rounded_polygon(GraphWorld.hex_points(c, half), h * 0.22, 4)
	host.draw_polygon(hex, GraphWorld.grad_colors(hex, Color(1.0, 0.93, 0.63),
			Color(0.46, 0.35, 0.13)))
	var rim := PackedVector2Array(hex)
	rim.append(hex[0])
	host.draw_polyline(rim, _BADGE_GOLD, maxf(1.5, h * 0.05), true)
	if icon != null:
		var isz := h * 1.35
		host.draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
				false, Color(0.02, 0.06, 0.11, 0.95))
