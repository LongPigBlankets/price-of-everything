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


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Notifications"
	if ResourceLoader.exists(BELL_TEXTURE_PATH):
		_bell_texture = load(BELL_TEXTURE_PATH) as Texture2D
	_build_badge()
	_build_dropdown()
	_refresh_bg()
	# All three collapse into one deferred refresh per frame (see _mark_dirty).
	# event_fired additionally arms a single flash.
	EventScheduler.event_fired.connect(_on_event_fired)
	EventScheduler.event_dismissed.connect(func(_id): _mark_dirty())
	EventScheduler.active_events_changed.connect(_mark_dirty)


# ── Painting ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var centre := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0 - 1.0
	draw_circle(centre, radius, _bg_current_color)
	draw_arc(centre, radius, 0.0, TAU, 64, DS.PALETTE.BORDER, RING_WIDTH, true)
	if _bell_texture != null:
		var dest := Rect2(Vector2(8, 8), Vector2(SIZE - 16, SIZE - 16))
		draw_texture_rect(_bell_texture, dest, false, DS.PALETTE.BORDER)
	else:
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
	var rows: Array = EventScheduler.active_events()
	_empty_label.visible = rows.is_empty()
	var shown: int = mini(rows.size(), MAX_VISIBLE_ROWS)
	for i in range(shown):
		_dropdown_list.add_child(_make_row(rows[i]))
	# Overflow note (a plain Label, rebuilt each pass alongside the rows) so a
	# few hundred active events never become a few thousand UI nodes.
	if rows.size() > shown:
		var more := Label.new()
		more.text = "+%d more — “Mark all read” to clear" % (rows.size() - shown)
		more.theme_type_variation = &"Caption"
		more.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_dropdown_list.add_child(more)


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
