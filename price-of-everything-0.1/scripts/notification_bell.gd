extends Control
## The top-bar notification bell + its dropdown.
##
## Pure read-side widget: subscribes to EventScheduler signals, never mutates
## game state. Bell colour rolls up to the worst active severity (info=green,
## warning=amber, critical=red, empty=grey). A small badge shows unread count.
##
## The bell glyph is DRAWN, not loaded — keeps the demo self-contained, no asset
## dependency, and renders identically at every zoom. To swap in a custom icon
## later, drop a Texture2D at BELL_TEXTURE_PATH and the override kicks in.

const BELL_TEXTURE_PATH := "res://assets/icons/ui_icons/bell.png"
const SIZE := 36.0
const RING_WIDTH := 2.0
const BADGE_DIAM := 14.0
# Hard cap on how many event rows the dropdown ever builds. The list scrolls, so
# the player never sees more than a handful at once anyway — building 400 row
# node-trees just to scroll past them is the real "hundreds of notifications"
# cost. Beyond this we render a "+N more" note and "Mark all read" clears them.
const MAX_VISIBLE_ROWS := 40
const DROPDOWN_WIDTH := 340.0
const DROPDOWN_MAX_HEIGHT := 420.0
const FLASH_DURATION := 0.4

const PalSchemeForSeverity := {
	"":         "BG_INSET",        # empty
	"info":     "OK",
	"warning":  "WARN",
	"critical": "DANGER",
}

var _bg_target_color: Color = Color()
var _bg_current_color: Color = Color()
var _bell_texture: Texture2D = null
var _badge: Label = null
var _dropdown: PanelContainer = null
var _dropdown_list: VBoxContainer = null
var _empty_label: Label = null
var _flash_tween: Tween = null
# Refreshes are coalesced: signals set _refresh_queued and defer one _apply_refresh
# to idle, so a storm of events in a single turn (e.g. 10 buildings starving) does
# ONE dropdown rebuild, not 20 — and the rebuild never runs inside a row button's
# `pressed` emission (which would free that button mid-dispatch and hard-crash).
var _refresh_queued := false
var _pending_flash := false
# Which group is expanded inline in the dropdown ("" = none). Clicking a group
# header toggles this; its members render indented underneath.
var _expanded_group_key := ""
var _icon_rect: TextureRect = null


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Notifications"
	if ResourceLoader.exists(BELL_TEXTURE_PATH):
		_bell_texture = load(BELL_TEXTURE_PATH) as Texture2D
	_build_icon()
	_build_badge()
	_build_dropdown()
	_refresh_bg()
	# All three collapse into one deferred refresh per frame (see _mark_dirty).
	# event_fired additionally arms a single flash.
	EventScheduler.event_fired.connect(_on_event_fired)
	EventScheduler.event_dismissed.connect(func(_id): _mark_dirty())
	EventScheduler.active_events_changed.connect(_mark_dirty)


# Recolours any silhouette texture to a flat tint using only its alpha, so a
# dark or coloured source icon still renders in the DS cream. Built in code so
# there's no .tres/.gdshader asset to ship.
const _ICON_TINT_SHADER := "shader_type canvas_item;\nuniform vec4 tint : source_color;\nvoid fragment() { COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).a); }"

# ── Painting ─────────────────────────────────────────────────────────────

func _build_icon() -> void:
	# The bell glyph: a recoloured TextureRect when a bell.png is present,
	# otherwise the vector glyph drawn in _draw(). The off-white ring + coloured
	# disc are always drawn in _draw() so the icon sits inside the DS ring.
	if _bell_texture == null:
		return
	_icon_rect = TextureRect.new()
	_icon_rect.texture = _bell_texture
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.position = Vector2(7, 7)
	_icon_rect.size = Vector2(SIZE - 14, SIZE - 14)
	var shader := Shader.new()
	shader.code = _ICON_TINT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", DS.PALETTE.BORDER)  # off-white cream
	_icon_rect.material = mat
	add_child(_icon_rect)

func _draw() -> void:
	var centre := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0 - 1.0
	draw_circle(centre, radius, _bg_current_color)
	# The off-white ring (same cream as the bottom-menu icon rings).
	draw_arc(centre, radius, 0.0, TAU, 64, DS.PALETTE.BORDER, RING_WIDTH, true)
	# Vector fallback only when no texture was supplied (recoloured TextureRect
	# handles the textured case).
	if _bell_texture == null:
		_draw_bell_glyph(centre, DS.PALETTE.BORDER)

# A bell silhouette built from primitives — proportions kept close to the icon
# the user shared: dome top, flared skirt, clapper, with a tiny crown loop.
func _draw_bell_glyph(centre: Vector2, color: Color) -> void:
	var scale_v := 0.72
	var w := 14.0 * scale_v
	var h := 16.0 * scale_v
	var cx := centre.x
	var top := centre.y - h * 0.55
	var bot := centre.y + h * 0.40
	# Body — flared bell shape as a polygon.
	var body := PackedVector2Array([
		Vector2(cx - w * 0.20, top),         # shoulder L
		Vector2(cx + w * 0.20, top),         # shoulder R
		Vector2(cx + w * 0.42, top + h * 0.45),
		Vector2(cx + w * 0.55, bot),         # skirt R
		Vector2(cx - w * 0.55, bot),         # skirt L
		Vector2(cx - w * 0.42, top + h * 0.45),
	])
	draw_colored_polygon(body, color)
	# Skirt rim — small horizontal band beneath, helps it read as a bell.
	draw_rect(Rect2(Vector2(cx - w * 0.55, bot), Vector2(w * 1.10, 1.5)), color)
	# Clapper — small filled circle just below the skirt.
	draw_circle(Vector2(cx, bot + 3.0), 1.6, color)
	# Crown loop — tiny hoop on top.
	draw_arc(Vector2(cx, top - 1.5), 1.6, 0.0, TAU, 12, color, 1.4, true)


func _refresh_bg() -> void:
	_bg_target_color = _palette_for_severity(EventScheduler.max_severity())
	_bg_current_color = _bg_target_color
	queue_redraw()

func _palette_for_severity(sev: String) -> Color:
	var key := str(PalSchemeForSeverity.get(sev, "BG_INSET"))
	return DS.PALETTE[key]


# ── Bell button behaviour ─────────────────────────────────────────────────

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
	_badge = Label.new()
	_badge.theme_type_variation = &"Caption"
	_badge.add_theme_font_size_override("font_size", 10)
	_badge.add_theme_color_override("font_color", DS.PALETTE.BG)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size = Vector2(BADGE_DIAM, BADGE_DIAM)
	_badge.position = Vector2(SIZE - BADGE_DIAM - 1.0, 1.0)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Background via a small panel behind the label.
	var bg := Panel.new()
	bg.size = Vector2(BADGE_DIAM, BADGE_DIAM)
	bg.position = _badge.position
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BORDER
	sb.set_corner_radius_all(int(BADGE_DIAM / 2))
	bg.add_theme_stylebox_override("panel", sb)
	add_child(bg)
	add_child(_badge)
	bg.name = "BadgeBg"
	_badge.name = "BadgeLabel"
	bg.visible = false
	_badge.visible = false


func _refresh_badge() -> void:
	var n := EventScheduler.active_count()
	var show := n > 1
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
	# Anchor to top-right so we can offset it from the bell on _position_dropdown.
	_dropdown.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Parent to the bell + top_level: drawn on the same CanvasLayer as the top bar
	# (so it floats above world panels) while ignoring the HBox parent's layout.
	_dropdown.top_level = true
	add_child(_dropdown)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var mc := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + s, 10)
	mc.add_child(vb)
	_dropdown.add_child(mc)

	# Header
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
	vb.add_child(HSeparator.new())

	# Scrollable list of event rows.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DROPDOWN_WIDTH - 20, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_dropdown_list = VBoxContainer.new()
	_dropdown_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dropdown_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_dropdown_list)

	# Empty state
	_empty_label = Label.new()
	_empty_label.theme_type_variation = &"Caption"
	_empty_label.text = "No new events."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dropdown_list.add_child(_empty_label)

	# Footer
	vb.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	var clear_btn := Button.new()
	clear_btn.text = "Mark all read"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(EventScheduler.dismiss_all)
	footer.add_child(clear_btn)
	vb.add_child(footer)


func _position_dropdown() -> void:
	# Sit the dropdown beneath the bell, right-aligned with its right edge.
	var gpos := global_position
	var gsize := size
	var x := gpos.x + gsize.x - DROPDOWN_WIDTH
	var y := gpos.y + gsize.y + 4.0
	_dropdown.global_position = Vector2(maxf(8.0, x), y)
	_dropdown.size = Vector2(DROPDOWN_WIDTH, 0)
	# Cap height so a long list stays scrollable instead of pushing off-screen.
	var viewport_size := get_viewport_rect().size
	var available := viewport_size.y - y - 12.0
	_dropdown.custom_minimum_size = Vector2(DROPDOWN_WIDTH, minf(DROPDOWN_MAX_HEIGHT, maxf(80.0, available)))


func _rebuild_dropdown_rows() -> void:
	for child in _dropdown_list.get_children():
		if child != _empty_label:
			child.queue_free()
	# Identical messages collapse: a group with 2+ members renders as one
	# "N Buildings Starved of …" header; clicking it expands the members inline
	# (indented) in this same panel. A lone event renders as its own row.
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


# A group header: severity dot + chevron (▾ when expanded) + "N {title}" + a
# dismiss-all ✕. Clicking the body toggles inline expansion in place.
func _make_group_row(group: Dictionary) -> Control:
	var members: Array = group.members
	var gk := str(group.group_key)
	var expanded := gk == _expanded_group_key
	var row := PanelContainer.new()
	row.theme_type_variation = &"Card"
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var chevron := Label.new()
	chevron.text = "▾" if expanded else "▸"
	chevron.theme_type_variation = &"Body"
	chevron.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	hb.add_child(chevron)

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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(label)

	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.custom_minimum_size = Vector2(20, 20)
	dismiss.tooltip_text = "Dismiss all"
	dismiss.pressed.connect(func(): EventScheduler.dismiss_group(gk))
	hb.add_child(dismiss)

	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_expanded_group_key = "" if expanded else gk
			_rebuild_dropdown_rows())
	return row


# An indented member of an expanded group: building + tile, a tertiary (text)
# "Go to" link, and a per-member dismiss.
func _make_member_row(ev: Dictionary) -> Control:
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 18)
	var row := PanelContainer.new()
	row.theme_type_variation = &"Inset"
	indent.add_child(row)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 6)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	m.add_child(hb)

	var deeplink: Dictionary = ev.get("deeplink", {})
	var tile_id := str(deeplink.get("tile_id", ""))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = str(ev.get("title", ""))
	name_label.theme_type_variation = &"Caption"
	col.add_child(name_label)
	if tile_id != "":
		var where := Label.new()
		where.text = Catalog.tile_label(tile_id)
		where.theme_type_variation = &"Caption"
		where.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		col.add_child(where)
	hb.add_child(col)

	# Tertiary action: an underlined text link (LinkButton), not a padded button.
	var go := LinkButton.new()
	go.text = "Go to"
	go.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	go.pressed.connect(func(): _go_to(ev))
	hb.add_child(go)

	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.custom_minimum_size = Vector2(20, 20)
	dismiss.tooltip_text = "Dismiss"
	dismiss.pressed.connect(func(): EventScheduler.dismiss(str(ev.id)))
	hb.add_child(dismiss)
	return indent


func _make_indent_note(text: String, indented: bool = true) -> Control:
	var note := Label.new()
	note.text = text
	note.theme_type_variation = &"Caption"
	note.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	if indented:
		note.add_theme_constant_override("margin_left", 18)
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_left", 24)
		wrap.add_child(note)
		return wrap
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return note


# Deep-link: a starved-building event opens the building detail panel; anything
# else with a tile focuses the tile. Closes the dropdown after navigating.
func _go_to(ev: Dictionary) -> void:
	var dl: Dictionary = ev.get("deeplink", {})
	var building_id := str(dl.get("building_id", ""))
	var tile_id := str(dl.get("tile_id", ""))
	if str(dl.get("panel", "")) == "building" and building_id != "":
		MatchState.focus_building_requested.emit(building_id)
	elif tile_id != "":
		MatchState.focus_tile_requested.emit(tile_id)
	if _dropdown != null and _dropdown.visible:
		toggle_dropdown()


func _make_row(ev: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = &"Card"
	var inner_margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		inner_margin.add_theme_constant_override("margin_" + s, 8)
	row.add_child(inner_margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	inner_margin.add_child(vb)

	# Title row: severity dot + title + dismiss button.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = _palette_for_severity(str(ev.get("severity", "info")))
	dot_sb.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", dot_sb)
	title_row.add_child(dot)
	var title_label := Label.new()
	title_label.text = str(ev.get("title", ""))
	title_label.theme_type_variation = &"Body"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(title_label)
	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.custom_minimum_size = Vector2(20, 20)
	dismiss.tooltip_text = "Dismiss"
	dismiss.pressed.connect(func(): EventScheduler.dismiss(str(ev.id)))
	title_row.add_child(dismiss)
	vb.add_child(title_row)

	# Body — progressive disclosure. Body label hidden until the row is clicked.
	var body_text := str(ev.get("body", ""))
	if body_text != "":
		var body_label := Label.new()
		body_label.text = body_text
		body_label.theme_type_variation = &"Caption"
		body_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.visible = false
		vb.add_child(body_label)
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				body_label.visible = not body_label.visible
		)
	return row


# ── Signals ──────────────────────────────────────────────────────────────

func _on_event_fired(_ev: Dictionary) -> void:
	_pending_flash = true
	_mark_dirty()

# Coalesce: many signal emissions in one frame queue exactly one _apply_refresh,
# run at idle — AFTER the current input/signal dispatch unwinds. This is what
# stops a row's ✕ from rebuilding (and freeing) the dropdown while that button
# is still mid-`pressed`.
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
	_refresh_bg()
	if _dropdown != null and _dropdown.visible:
		_rebuild_dropdown_rows()

# Flash brightens the bell briefly to draw the eye when a new event arrives.
func _flash() -> void:
	var target := _palette_for_severity(EventScheduler.max_severity())
	var hi := target.lightened(0.45)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_bg_color, hi, target, FLASH_DURATION)

func _set_bg_color(c: Color) -> void:
	_bg_current_color = c
	queue_redraw()
