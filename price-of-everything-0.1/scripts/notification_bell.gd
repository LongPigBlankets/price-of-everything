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
	_dropdown.theme_type_variation = &"Outlined"
	_dropdown.custom_minimum_size = Vector2(DROPDOWN_WIDTH, 0)
	_dropdown.visible = false
	_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown.z_index = 100
	_dropdown.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dropdown.top_level = true
	add_child(_dropdown)
	# Clamp the scroll wheel to the panel: when the list is at its limit the
	# event must NOT fall through to the map's camera zoom.
	_dropdown.gui_input.connect(func(e):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in \
				[MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_dropdown.accept_event())

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	# Outer padding: minimal, so the scroll list keeps only ~5px left/right.
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 5)
	mc.add_theme_constant_override("margin_right", 5)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	mc.add_child(vb)
	_dropdown.add_child(mc)

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

	# The four severity bells under the title (red / amber / navy / green).
	var bells := HBoxContainer.new()
	bells.add_theme_constant_override("separation", 10)
	bells.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in HEADER_BELLS:
		bells.add_child(_make_header_bell(DS.PALETTE[str(entry[1])]))
	vb.add_child(bells)
	vb.add_child(HSeparator.new())

	# Scrollable list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Absorb the wheel here too (the ScrollContainer sees it before the panel),
	# so reaching the top/bottom of the list never zooms the map behind it.
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

	# Footer: no separator before it — just the vbox spacing, then the button.
	var clear_btn := Button.new()
	clear_btn.text = "Mark all read"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(EventScheduler.dismiss_all)
	vb.add_child(clear_btn)


func _make_header_bell(color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(22, 22)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bell_texture != null:
		tr.texture = _bell_texture
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.material = _tint_material(color)
	else:
		# No PNG: a coloured dot stands in.
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(11)
		var p := Panel.new()
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(p)
		return holder
	holder.add_child(tr)
	return holder


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
	_empty_label.visible = groups.is_empty()
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
	row.theme_type_variation = &"Card"
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
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

	var dismiss := _make_x_button("Dismiss all")
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
	row.theme_type_variation = &"Inset"
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


func _make_x_button(tip: String) -> Button:
	var b := Button.new()
	b.text = "✕"
	b.custom_minimum_size = Vector2(20, 20)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = tip
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
	row.theme_type_variation = &"Card"
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
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
