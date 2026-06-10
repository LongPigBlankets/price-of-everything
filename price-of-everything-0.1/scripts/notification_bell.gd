extends Control
## The top-bar notification bell + its dropdown panel.
##
## Pure read-side widget: subscribes to EventScheduler signals, never mutates
## game state. The top-bar trigger is a single navy bell (cream glyph, off-white
## ring) sized to fill the bar; a small badge shows the unread count, and a new
## event briefly flashes the bell its severity colour. The panel header carries
## the four severity bells (red / amber / navy / green) under the title.
##
## Identical messages collapse into one group row; clicking a group expands its
## members inline (indented) in the same panel, each with a tertiary "Go to".

const BELL_TEXTURE_PATH := "res://assets/icons/ui_icons/bell.png"
const SIZE := 36.0           # fills the 36px top bar top-to-bottom
const ICON_INSET := 3.0      # small inset → a big bell glyph inside the ring
const RING_WIDTH := 2.0
const BADGE_DIAM := 14.0
# Hard cap on how many rows the dropdown ever builds. The list scrolls, so the
# player never sees more than a handful at once; building hundreds of row
# node-trees just to scroll past them is the real "hundreds of events" cost.
const MAX_VISIBLE_ROWS := 40
const DROPDOWN_WIDTH := 360.0
const DROPDOWN_MAX_HEIGHT := 420.0
const FLASH_DURATION := 0.4

const PalSchemeForSeverity := {
	"":         "BG_INSET",
	"info":     "OK",
	"warning":  "WARN",
	"critical": "DANGER",
}
# The four header bells, left→right: red, amber, navy, green.
const HEADER_BELLS := [
	["critical", "DANGER"],
	["warning", "WARN"],
	["", "BG_HIGHLIGHT"],   # navy
	["info", "OK"],
]

# Recolours any silhouette texture to a flat tint using only its alpha, so the
# (cream) source PNG can render red / amber / navy / green. Built in code so
# there is no .gdshader asset to ship.
const _ICON_TINT_SHADER := "shader_type canvas_item;\nuniform vec4 tint : source_color;\nvoid fragment() { COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).a); }"

var _bg_current_color: Color = Color()
var _bell_texture: Texture2D = null
var _icon_rect: TextureRect = null
var _badge: Label = null
var _dropdown: PanelContainer = null
var _dropdown_list: VBoxContainer = null
var _empty_label: Label = null
var _flash_tween: Tween = null
# Refreshes are coalesced: signals set _refresh_queued and defer one
# _apply_refresh to idle, so a storm of events does ONE rebuild — and the rebuild
# never runs inside a row button's `pressed` emission (which would free that
# button mid-dispatch and hard-crash).
var _refresh_queued := false
var _pending_flash := false
# Which group is expanded inline in the dropdown ("" = none).
var _expanded_group_key := ""
# Severity filter from the header bells ("" = navy = show all).
var _filter_severity := ""
var _filter_bells: Array = []   # [{sev, bg, hover}] for the 4 header bells


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Notifications"
	_bg_current_color = _navy()
	if ResourceLoader.exists(BELL_TEXTURE_PATH):
		_bell_texture = load(BELL_TEXTURE_PATH) as Texture2D
	_build_icon()
	_build_badge()
	_build_dropdown()
	queue_redraw()
	EventScheduler.event_fired.connect(_on_event_fired)
	EventScheduler.event_dismissed.connect(func(_id): _mark_dirty())
	EventScheduler.active_events_changed.connect(_mark_dirty)


func _navy() -> Color:
	return DS.PALETTE.BG_INSET

func _palette_for_severity(sev: String) -> Color:
	return DS.PALETTE[str(PalSchemeForSeverity.get(sev, "BG_INSET"))]


# ── Painting ─────────────────────────────────────────────────────────────

func _build_icon() -> void:
	if _bell_texture == null:
		return  # vector glyph fallback (see _draw)
	_icon_rect = TextureRect.new()
	_icon_rect.texture = _bell_texture
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.position = Vector2(ICON_INSET, ICON_INSET)
	_icon_rect.size = Vector2(SIZE - ICON_INSET * 2.0, SIZE - ICON_INSET * 2.0)
	_icon_rect.material = _tint_material(DS.PALETTE.BORDER)
	add_child(_icon_rect)

func _tint_material(color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _ICON_TINT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", color)
	return mat

func _draw() -> void:
	var centre := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0 - 1.0
	draw_circle(centre, radius, _bg_current_color)
	draw_arc(centre, radius, 0.0, TAU, 64, DS.PALETTE.BORDER, RING_WIDTH, true)
	if _bell_texture == null:
		_draw_bell_glyph(centre, DS.PALETTE.BORDER)

# Vector fallback bell (dome, flared skirt, clapper, crown loop) for when no
# bell.png is present.
func _draw_bell_glyph(centre: Vector2, color: Color) -> void:
	var w := 16.0
	var h := 18.0
	var cx := centre.x
	var top := centre.y - h * 0.5
	var bot := centre.y + h * 0.36
	var body := PackedVector2Array([
		Vector2(cx - w * 0.20, top), Vector2(cx + w * 0.20, top),
		Vector2(cx + w * 0.42, top + h * 0.45), Vector2(cx + w * 0.55, bot),
		Vector2(cx - w * 0.55, bot), Vector2(cx - w * 0.42, top + h * 0.45),
	])
	draw_colored_polygon(body, color)
	draw_rect(Rect2(Vector2(cx - w * 0.55, bot), Vector2(w * 1.10, 1.6)), color)
	draw_circle(Vector2(cx, bot + 3.2), 1.8, color)
	draw_arc(Vector2(cx, top - 1.6), 1.8, 0.0, TAU, 12, color, 1.5, true)


# ── Trigger behaviour ─────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		toggle_dropdown()
		accept_event()

func toggle_dropdown() -> void:
	if _dropdown.visible:
		_dropdown.hide()
		PanelStack.remove(_dropdown)
	else:
		_rebuild_dropdown_rows()
		_position_dropdown()
		_dropdown.show()
		PanelStack.push(_dropdown)


# ── Badge (count pip) ─────────────────────────────────────────────────────

func _build_badge() -> void:
	var bg := Panel.new()
	bg.size = Vector2(BADGE_DIAM, BADGE_DIAM)
	bg.position = Vector2(SIZE - BADGE_DIAM, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.DANGER
	sb.set_corner_radius_all(int(BADGE_DIAM / 2))
	bg.add_theme_stylebox_override("panel", sb)
	bg.name = "BadgeBg"
	add_child(bg)
	_badge = Label.new()
	_badge.theme_type_variation = &"Caption"
	_badge.add_theme_font_size_override("font_size", 9)
	_badge.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size = Vector2(BADGE_DIAM, BADGE_DIAM)
	_badge.position = bg.position
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.name = "BadgeLabel"
	add_child(_badge)
	bg.visible = false
	_badge.visible = false

func _refresh_badge() -> void:
	# The trigger stays navy, so the badge is the persistent unread signal: show
	# it whenever there is anything active.
	var n := EventScheduler.active_count()
	var show := n > 0
	var bg := get_node_or_null("BadgeBg") as Panel
	if bg != null:
		bg.visible = show
	if _badge != null:
		_badge.visible = show
		_badge.text = "9+" if n > 9 else str(n)


# ── Dropdown ──────────────────────────────────────────────────────────────

func _build_dropdown() -> void:
	_dropdown = PanelContainer.new()
	_dropdown.custom_minimum_size = Vector2(DROPDOWN_WIDTH, 0)
	_dropdown.visible = false
	_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown.z_index = 100
	_dropdown.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dropdown.top_level = true
	# Tight stylebox: the DS "Outlined" variation pads 24px each side — way too
	# much. Same navy + cream-border look, but only 5px horizontal padding so the
	# list uses the full width.
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = DS.PALETTE.BG_HIGHLIGHT
	panel_sb.border_color = DS.PALETTE.BORDER
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(10)
	panel_sb.content_margin_left = 5
	panel_sb.content_margin_right = 5
	panel_sb.content_margin_top = 8
	panel_sb.content_margin_bottom = 8
	_dropdown.add_theme_stylebox_override("panel", panel_sb)
	add_child(_dropdown)
	# Clamp the scroll wheel to the panel so reaching the list end never zooms
	# the map behind it.
	_dropdown.gui_input.connect(func(e):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in \
				[MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_dropdown.accept_event())

	# VBox sits directly in the panel — the stylebox content margins ARE the
	# padding (no extra MarginContainer).
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_dropdown.add_child(vb)

	# Header: title + close.
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"Section"
	title.text = "Notifications"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(24, 24)
	close.pressed.connect(toggle_dropdown)
	header.add_child(close)
	vb.add_child(header)

	# The four severity bells under the title — clickable filters (navy = all).
	_filter_bells.clear()
	var bells := HBoxContainer.new()
	bells.add_theme_constant_override("separation", 10)
	bells.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in HEADER_BELLS:
		bells.add_child(_make_filter_bell(str(entry[0]), DS.PALETTE[str(entry[1])]))
	vb.add_child(bells)
	vb.add_child(HSeparator.new())

	# Scrollable list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(func(e):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in \
				[MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scroll.accept_event())
	vb.add_child(scroll)
	_dropdown_list = VBoxContainer.new()
	_dropdown_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dropdown_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_dropdown_list)

	_empty_label = Label.new()
	_empty_label.theme_type_variation = &"Caption"
	_empty_label.text = "No new events."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dropdown_list.add_child(_empty_label)

	# Footer: no separator — just the vbox spacing, then the button.
	var clear_btn := Button.new()
	clear_btn.text = "Mark all read"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(EventScheduler.dismiss_all)
	vb.add_child(clear_btn)


# A header bell that filters the list to one severity. Each has a 2px off-white
# rounded-square outline; the bg fills on hover and on the active (selected)
# state. Navy ("" severity) clears the filter / shows all.
func _make_filter_bell(sev: String, color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(26, 26)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = _filter_tooltip(sev)
	var bgp := Panel.new()
	bgp.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bgp)
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + s, 4)
	holder.add_child(inner)
	if _bell_texture != null:
		var tr := TextureRect.new()
		tr.texture = _bell_texture
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.material = _tint_material(color)
		inner.add_child(tr)
	else:
		var dot := Panel.new()
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = color
		dsb.set_corner_radius_all(8)
		dot.add_theme_stylebox_override("panel", dsb)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(dot)
	var entry := {"sev": sev, "bg": bgp, "hover": false}
	_filter_bells.append(entry)
	holder.mouse_entered.connect(func(): entry.hover = true; _style_filter_bell(entry))
	holder.mouse_exited.connect(func(): entry.hover = false; _style_filter_bell(entry))
	holder.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_filter_severity = "" if _filter_severity == sev else sev
			for fe in _filter_bells:
				_style_filter_bell(fe)
			_rebuild_dropdown_rows())
	_style_filter_bell(entry)
	return holder

func _filter_tooltip(sev: String) -> String:
	match sev:
		"critical": return "Show critical only"
		"warning": return "Show warnings only"
		"info": return "Show info only"
		_: return "Show all"

func _style_filter_bell(entry: Dictionary) -> void:
	var active := _filter_severity == str(entry.sev)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = DS.PALETTE.BORDER
	if active:
		sb.bg_color = DS.PALETTE.ACTION_BLUE
	elif bool(entry.hover):
		sb.bg_color = DS.PALETTE.BG_HIGHLIGHT
	else:
		sb.bg_color = Color(0, 0, 0, 0)
	(entry.bg as Panel).add_theme_stylebox_override("panel", sb)


# Tight row backgrounds (the DS Card/Inset variations pad 24px/14px each side);
# content_margins 0 so the row's own MarginContainer fully controls padding.
func _row_style(inset: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_INSET if inset else DS.PALETTE.BG_CARD
	sb.border_color = DS.PALETTE.BORDER_SOFT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _position_dropdown() -> void:
	var gpos := global_position
	var gsize := size
	var x := gpos.x + gsize.x - DROPDOWN_WIDTH
	var y := gpos.y + gsize.y + 4.0
	_dropdown.global_position = Vector2(maxf(8.0, x), y)
	_dropdown.size = Vector2(DROPDOWN_WIDTH, 0)
	var viewport_size := get_viewport_rect().size
	var available := viewport_size.y - y - 12.0
	_dropdown.custom_minimum_size = Vector2(DROPDOWN_WIDTH, minf(DROPDOWN_MAX_HEIGHT, maxf(80.0, available)))


func _rebuild_dropdown_rows() -> void:
	for child in _dropdown_list.get_children():
		if child != _empty_label:
			child.queue_free()
	var groups: Array = EventScheduler.grouped_active()
	# Header-bell filter: when a severity is selected, show only matching groups.
	if _filter_severity != "":
		var kept: Array = []
		for g in groups:
			if str(g.severity) == _filter_severity:
				kept.append(g)
		groups = kept
	if groups.is_empty():
		_empty_label.visible = true
		_empty_label.text = "No notifications." if _filter_severity == "" \
			else "No %s notifications." % _filter_severity
	else:
		_empty_label.visible = false
	var shown: int = mini(groups.size(), MAX_VISIBLE_ROWS)
	for i in range(shown):
		var g: Dictionary = groups[i]
		var members: Array = g.members
		if members.size() <= 1:
			_dropdown_list.add_child(_make_row(members[0]))
			continue
		_dropdown_list.add_child(_make_group_row(g))
		if str(g.group_key) == _expanded_group_key:
			var mshown: int = mini(members.size(), MAX_VISIBLE_ROWS)
			for j in range(mshown):
				_dropdown_list.add_child(_make_member_row(members[j]))
			if members.size() > mshown:
				_dropdown_list.add_child(_make_indent_note(
					"+%d more — “Dismiss all” to clear" % (members.size() - mshown)))
	if groups.size() > shown:
		_dropdown_list.add_child(_make_indent_note(
			"+%d more — “Mark all read” to clear" % (groups.size() - shown), false))


# A thin group header: rotating "›" + severity dot + "N {title}" (≤2 lines) + a
# dismiss-all ✕, 8px top/bottom padding. The body toggles inline expansion.
func _make_group_row(group: Dictionary) -> Control:
	var members: Array = group.members
	var gk := str(group.group_key)
	var expanded := gk == _expanded_group_key
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 5)  # X sits 5px from the card edge
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	# A large ">" that rotates 90° to point down when expanded.
	var caret := Label.new()
	caret.text = ">"
	caret.add_theme_font_size_override("font_size", 18)
	caret.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	caret.custom_minimum_size = Vector2(16, 16)
	caret.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caret.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caret.pivot_offset = Vector2(8, 8)
	caret.rotation = deg_to_rad(90.0) if expanded else 0.0
	caret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(caret)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = _palette_for_severity(str(group.severity))
	dot_sb.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", dot_sb)
	hb.add_child(dot)

	var label := Label.new()
	label.text = "%d %s" % [members.size(), str(group.title)]
	label.theme_type_variation = &"Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	hb.add_child(label)

	var dismiss := _make_x_button("Dismiss all", 10)  # small X on the group card
	dismiss.pressed.connect(func(): EventScheduler.dismiss_group(gk))
	hb.add_child(dismiss)

	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_expanded_group_key = "" if expanded else gk
			_rebuild_dropdown_rows())
	return row


# An indented member: "<building name> (<nickname|tile>)", a tertiary Go-to link,
# and a per-member dismiss.
func _make_member_row(ev: Dictionary) -> Control:
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 20)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(true))
	indent.add_child(row)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	m.add_child(hb)

	var label := Label.new()
	label.text = _member_label(ev)
	label.theme_type_variation = &"Caption"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	hb.add_child(label)

	var go := LinkButton.new()
	go.text = "Go to"
	go.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	go.pressed.connect(func(): _go_to(ev))
	hb.add_child(go)

	var dismiss := _make_x_button("Dismiss")
	dismiss.pressed.connect(func(): EventScheduler.dismiss(str(ev.id)))
	hb.add_child(dismiss)
	return indent


func _member_label(ev: Dictionary) -> String:
	var name := str(ev.get("building_name", ev.get("title", "")))
	var where := str(ev.get("where", ""))
	return "%s (%s)" % [name, where] if where != "" else name


func _make_x_button(tip: String, px: int = 18) -> Button:
	var b := Button.new()
	b.text = "✕"
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", maxi(9, int(px * 0.85)))
	# Strip the button's own padding so a tiny (e.g. 10px) button fits the glyph.
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT)
	return b


func _make_indent_note(text: String, indented: bool = true) -> Control:
	var note := Label.new()
	note.text = text
	note.theme_type_variation = &"Caption"
	note.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	if indented:
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_left", 28)
		wrap.add_child(note)
		return wrap
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return note


# A lone (ungrouped) event row: severity dot + title (≤2 lines) + dismiss.
func _make_row(ev: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(false))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 5)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = _palette_for_severity(str(ev.get("severity", "info")))
	dot_sb.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", dot_sb)
	hb.add_child(dot)

	var label := Label.new()
	label.text = str(ev.get("title", ""))
	label.theme_type_variation = &"Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	hb.add_child(label)

	var dismiss := _make_x_button("Dismiss")
	dismiss.pressed.connect(func(): EventScheduler.dismiss(str(ev.id)))
	hb.add_child(dismiss)

	# A tile/building deep-link makes the whole row a Go-to target.
	var dl: Dictionary = ev.get("deeplink", {})
	if str(dl.get("building_id", "")) != "" or str(dl.get("tile_id", "")) != "":
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_go_to(ev))
	return row


# Deep-link: a starved-building event opens the building detail panel; anything
# else with a tile focuses the tile. The dropdown STAYS OPEN.
func _go_to(ev: Dictionary) -> void:
	var dl: Dictionary = ev.get("deeplink", {})
	var building_id := str(dl.get("building_id", ""))
	var tile_id := str(dl.get("tile_id", ""))
	if str(dl.get("panel", "")) == "building" and building_id != "":
		MatchState.focus_building_requested.emit(building_id)
	elif tile_id != "":
		MatchState.focus_tile_requested.emit(tile_id)


# ── Signals ──────────────────────────────────────────────────────────────

func _on_event_fired(_ev: Dictionary) -> void:
	_pending_flash = true
	_mark_dirty()

func _mark_dirty() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if _pending_flash:
		_pending_flash = false
		_flash()
	_refresh_badge()
	if _dropdown != null and _dropdown.visible:
		_rebuild_dropdown_rows()

# A new event briefly flashes the bell its severity colour, then settles to navy.
func _flash() -> void:
	if EventScheduler.active_count() == 0:
		_set_bg_color(_navy())
		return
	var peak := _palette_for_severity(EventScheduler.max_severity())
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_bg_color, peak, _navy(), FLASH_DURATION)

func _set_bg_color(c: Color) -> void:
	_bg_current_color = c
	queue_redraw()
