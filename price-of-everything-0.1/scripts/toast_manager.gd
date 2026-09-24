extends Control

## ToastManager: the updates container in the bottom-left corner.
##
## Every toast becomes a row in a slide-out that rises from behind a 60 px dock, and the
## slide-out collapses back into the dock TOAST_DURATION after its last row arrived. Like the
## toasts it replaces, a slide-out that opened by itself takes no clicks: the map and the
## panels under it (the Construct panel reaches down to the dock) keep theirs.
##
## The dock carries three bells, green, amber and red, each counting the rows of its colour
## that arrived since the player last opened the slide-out from the dock. Clicking the dock
## opens the slide-out on every row kept; that one takes the mouse, scrolls, and stays up
## while the mouse is over it. Clicking the dock again closes it.

## Rows the slide-out shows when it opens by itself: the newest that haven't been shown.
const MAX_TOASTS := 6
## Rows kept for the dock to reopen.
const HISTORY_MAX := 40
const TOAST_DURATION := 5.0
## How long a slide-out opened from the dock waits after the mouse leaves it.
const HOVER_GRACE := 2.0
const TOAST_WIDTH := 380.0
const DOCK_LEFT := 12.0
const DOCK_BOTTOM := 12.0
const DOCK_HEIGHT := 60.0
## How far the slide-out tucks under the dock, so it rises from behind it.
const TUCK := 10.0
## Bottom-left legends sit this far above the screen's foot, so they clear the dock.
const LEGEND_CLEARANCE := DOCK_BOTTOM + DOCK_HEIGHT + 8.0
const SLIDE_SEC := 0.22
## Share of the screen's height the slide-out may take; taller content scrolls.
const SLIDE_MAX_SHARE := 0.6
const PANEL_PAD := 8.0
const ROW_PAD_X := 14.0
const SCROLLBAR_ROOM := 12.0
const BELL_PX := 40.0
const BELL_GAP := 18.0
const BELL_ICON: Texture2D = preload("res://assets/icons/ui_icons/standalone/bell.png")
const TONES := ["green", "amber", "red"]
const NAVY_PRINT := Color("#0b2340")
const DOCK_BG := Color(0.015, 0.045, 0.075, 0.96)
const DOCK_BORDER := Color("#2f5578")
const DOCK_BORDER_HOT := Color("#4d7aa3")

const SUCCESS_BG := Color(0.015, 0.045, 0.075, 0.98)
const SUCCESS_BORDER := Color(0.4, 0.85, 0.4, 0.9)
const SUCCESS_TEXT := Color(0.92, 0.97, 1.0)

const WARNING_BG := Color(0.10, 0.015, 0.015, 0.98)
const WARNING_BORDER := Color(1.0, 0.35, 0.35, 0.95)
const WARNING_TEXT := Color(1.0, 0.92, 0.92)
const CAUTION_BG := Color(0.075, 0.045, 0.01, 0.98)
const CAUTION_BORDER := Color(1.0, 0.78, 0.18, 0.95)
const CAUTION_TEXT := Color(1.0, 0.96, 0.84)
const TOAST_SUCCESS := "success"
const TOAST_WARNING := "warning"
const TOAST_CAUTION := "caution"
const TOAST_ERROR := "error"

var _pending_sales: Array = []
var _prev_money: float = 0.0

var _dock: PanelContainer
var _dock_style: StyleBoxFlat
var _bells := {}            # tone -> {"root", "clip", "tex", "pill", "count"}
var _clip: Control          # clips the slide-out, so it rises out of the dock
var _panel: PanelContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _empty: Label
var _timer: Timer
var _slide: Tween
var _open := false
## The slide-out was opened from the dock and shows every kept row, not only the new ones.
var _all := false
## The mouse held the slide-out open; once it leaves, HOVER_GRACE runs before it closes.
var _held := false
var _fit_queued := false
var _dock_hover := false
var _unread := {"green": 0, "amber": 0, "red": 0}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_hidden(DecisionState.hide_updates)
	DecisionState.recording_updates_changed.connect(func(hidden: bool) -> void:
		if hidden:
			_pending_sales.clear()
			clear()
		_apply_hidden(hidden))
	TurnManager.turn_resolution_completed.connect(_flush_sales)
	MatchState.state_reset.connect(func() -> void:
		_pending_sales.clear()
		clear())
	_prev_money = MatchState.money
	BuildingState.building_added.connect(_on_building_added)
	Construction.construction_started.connect(_on_construction_started)
	Construction.materials_ordered.connect(_on_materials_ordered)
	Construction.construction_cancelled.connect(_on_construction_cancelled)
	MatchState.money_changed.connect(_on_money_changed)
	MatchState.stockpile_market_sale_completed.connect(_on_stockpile_market_sale_completed)
	MatchState.toast_requested.connect(_on_toast_requested)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)


## The bell a toast type rings: warnings and errors red, cautions amber, the rest green.
static func tone_of(toast_type: String) -> String:
	match toast_type:
		TOAST_WARNING, TOAST_ERROR:
			return "red"
		TOAST_CAUTION:
			return "amber"
		_:
			return "green"


static func tone_colour(tone: String) -> Color:
	match tone:
		"red":
			return DS.PALETTE.DANGER
		"amber":
			return DS.PALETTE.WARN
		_:
			return DS.PALETTE.OK


# ── Public ────────────────────────────────────────────────────────────────────

func show_error(message: String) -> void:
	_push_toast(message, TOAST_WARNING)

## A build the map turned away.
func show_blocked(message: String) -> void:
	_push_toast(message, TOAST_WARNING)

func show_caution(message: String) -> void:
	_push_toast(message, TOAST_CAUTION)

func is_open() -> bool:
	return _open

func row_count() -> int:
	return _rows.get_child_count()

## The kept rows' text, oldest first.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Node in _rows.get_children():
		out.append(str(row.get_meta("toast_message", "")))
	return out

## Rows of a tone that arrived since the slide-out was last opened from the dock.
func unread(tone: String) -> int:
	return int(_unread.get(tone, 0))

## Opens the slide-out on every kept row, as clicking the dock does.
func open_all() -> void:
	_open_slide(true)

## Closes the slide-out into the dock. The rows it showed stop counting as new.
func collapse(animate: bool = true) -> void:
	_timer.stop()
	_held = false
	for row: Node in _rows.get_children():
		row.set_meta("fresh", false)
	if not _open:
		return
	_open = false
	_all = false
	_set_interactive(false)
	_update_dock_rim()
	if animate:
		_tween_panel_to(_clip.size.y)
	else:
		if _slide != null and _slide.is_valid():
			_slide.kill()
		_panel.position.y = _clip.size.y

## Drops every row and count and closes the slide-out at once (a new match, recording mode).
func clear() -> void:
	collapse(false)
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for tone: String in TONES:
		_unread[tone] = 0
	_refresh_bells()
	_queue_fit()


# ── Building the container ────────────────────────────────────────────────────

func _build_ui() -> void:
	# The slide-out first, the dock after it, so the dock draws over the tucked-in edge.
	_clip = Control.new()
	_clip.name = "UpdatesSlideOut"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.anchor_left = 0.0
	_clip.anchor_right = 0.0
	_clip.anchor_top = 1.0
	_clip.anchor_bottom = 1.0
	_clip.offset_left = DOCK_LEFT
	_clip.offset_right = DOCK_LEFT + TOAST_WIDTH
	_clip.offset_bottom = -(DOCK_BOTTOM + DOCK_HEIGHT - TUCK)
	_clip.offset_top = _clip.offset_bottom
	add_child(_clip)

	_panel = PanelContainer.new()
	_panel.name = "Rows"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = DOCK_BG
	ps.border_color = DOCK_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(10)
	ps.content_margin_left = PANEL_PAD
	ps.content_margin_right = PANEL_PAD
	ps.content_margin_top = PANEL_PAD
	ps.content_margin_bottom = PANEL_PAD + TUCK
	_panel.add_theme_stylebox_override("panel", ps)
	_clip.add_child(_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_empty = Label.new()
	_empty.text = "No updates yet"
	_empty.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	_empty.add_theme_font_size_override("font_size", 15)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty.visible = false
	column.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "RowList"
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.minimum_size_changed.connect(_queue_fit)
	_scroll.add_child(_rows)

	_dock = PanelContainer.new()
	_dock.name = "UpdatesDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dock.tooltip_text = "Updates: click to see the recent ones"
	_dock.anchor_left = 0.0
	_dock.anchor_right = 0.0
	_dock.anchor_top = 1.0
	_dock.anchor_bottom = 1.0
	_dock.offset_left = DOCK_LEFT
	_dock.offset_bottom = -DOCK_BOTTOM
	_dock.offset_top = -(DOCK_BOTTOM + DOCK_HEIGHT)
	_dock.grow_horizontal = Control.GROW_DIRECTION_END
	_dock.custom_minimum_size = Vector2(0, DOCK_HEIGHT)
	_dock_style = StyleBoxFlat.new()
	_dock_style.bg_color = DOCK_BG
	_dock_style.border_color = DOCK_BORDER
	_dock_style.set_border_width_all(1)
	_dock_style.set_corner_radius_all(10)
	_dock_style.shadow_color = Color(0, 0, 0, 0.35)
	_dock_style.shadow_size = 8
	_dock_style.shadow_offset = Vector2(0, 3)
	_dock_style.content_margin_left = 14
	_dock_style.content_margin_right = 14
	_dock_style.content_margin_top = (DOCK_HEIGHT - BELL_PX) / 2.0
	_dock_style.content_margin_bottom = (DOCK_HEIGHT - BELL_PX) / 2.0
	_dock.add_theme_stylebox_override("panel", _dock_style)
	_dock.gui_input.connect(_on_dock_input)
	_dock.mouse_entered.connect(func() -> void:
		_dock_hover = true
		_update_dock_rim())
	_dock.mouse_exited.connect(func() -> void:
		_dock_hover = false
		_update_dock_rim())
	add_child(_dock)

	var bells := HBoxContainer.new()
	bells.add_theme_constant_override("separation", int(BELL_GAP))
	bells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(bells)
	for tone: String in TONES:
		var bell := _make_bell(tone)
		bells.add_child(bell.root)
		_bells[tone] = bell
	_refresh_bells()

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_queue_fit()


## A bell as the briefing notch draws it (the same art, clipped so the TextureRect keeps its
## box), tinted to its tone, with a count pill on its bottom-right corner.
func _make_bell(tone: String) -> Dictionary:
	var holder := Control.new()
	holder.name = "Bell_%s" % tone
	holder.custom_minimum_size = Vector2(BELL_PX, BELL_PX)
	# PASS: the tooltip shows, and the click still reaches the dock.
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.pivot_offset = Vector2(BELL_PX, BELL_PX) * 0.5
	holder.add_child(clip)
	var tex := TextureRect.new()
	tex.texture = BELL_ICON
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(tex)
	var pill := PanelContainer.new()
	pill.name = "Count"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(8)
	pill.add_theme_stylebox_override("panel", sb)
	var count := Label.new()
	count.add_theme_color_override("font_color", NAVY_PRINT)
	count.add_theme_font_size_override("font_size", 13)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(count)
	holder.add_child(pill)
	return {"root": holder, "clip": clip, "tex": tex, "pill": pill, "count": count}


func _refresh_bells(pulse_tone: String = "") -> void:
	for tone: String in TONES:
		var bell: Dictionary = _bells.get(tone, {})
		if bell.is_empty():
			continue
		var n: int = int(_unread[tone])
		var colour := tone_colour(tone)
		(bell.tex as TextureRect).modulate = colour if n > 0 else Color(colour, 0.4)
		var pill: PanelContainer = bell.pill
		pill.visible = n > 0
		var text := str(n) if n < 100 else "99+"
		(bell.count as Label).text = text
		var w: float = maxf(20.0, text.length() * 8.0 + 12.0)
		pill.custom_minimum_size = Vector2(w, 16)
		pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		pill.offset_left = -w + 4.0
		pill.offset_top = -16.0 + 4.0
		pill.offset_right = 4.0
		pill.offset_bottom = 4.0
		(bell.root as Control).tooltip_text = _bell_tooltip(tone, n)
		if tone == pulse_tone:
			var clip: Control = bell.clip
			var t := clip.create_tween()
			t.tween_property(clip, "scale", Vector2(1.18, 1.18), 0.12)
			t.tween_property(clip, "scale", Vector2.ONE, 0.18)


func _bell_tooltip(tone: String, n: int) -> String:
	var kind: String = {"green": "updates", "amber": "cautions", "red": "warnings"}[tone]
	return "No new %s" % kind if n == 0 else "%d new %s" % [n, kind]


## The dock's rim lights while the mouse is on it, and while the slide-out it opened is up.
func _update_dock_rim() -> void:
	_dock_style.border_color = DOCK_BORDER_HOT if _dock_hover or (_open and _all) else DOCK_BORDER


## Opened from the dock the slide-out takes the mouse (it scrolls, and hovering holds it up);
## opened by itself it lets every click through, as the toasts did.
func _set_interactive(on: bool) -> void:
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE


func _apply_hidden(hidden: bool) -> void:
	_dock.visible = not hidden
	_clip.visible = not hidden


# ── Rows ──────────────────────────────────────────────────────────────────────

func _push_toast(message: String, toast_type: String) -> void:
	if DecisionState.hide_updates:
		return
	# Nothing that fires while the world is still building behind the loading screen
	# is player-initiated: it is the match-start seeding (NPC ports, start companies,
	# their material orders).
	if LoadPacing.is_background_build() and not LoadPacing.legacy_load:
		return
	if toast_type == TOAST_CAUTION:
		for existing: Node in _rows.get_children():
			if existing.get_meta("fresh", false) and str(existing.get_meta("toast_message", "")) == message:
				return
	var tone := tone_of(toast_type)
	var row: PanelContainer = _make_toast(message, toast_type)
	row.set_meta("toast_message", message)
	row.set_meta("tone", tone)
	row.set_meta("fresh", true)
	_rows.add_child(row)
	# Detach before queue_free: queue_free is deferred, so it doesn't lower the child count.
	while _rows.get_child_count() > HISTORY_MAX:
		var oldest: Node = _rows.get_child(0)
		_rows.remove_child(oldest)
		oldest.queue_free()
	_unread[tone] = int(_unread[tone]) + 1
	_refresh_bells(tone)
	if _open:
		_apply_row_visibility()
		_scroll_to_newest.call_deferred()
		_held = false
		_timer.start(TOAST_DURATION)
	else:
		_open_slide(false)


func _make_toast(message: String, toast_type: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = _toast_bg_color(toast_type)
	sb.border_color = _toast_border_color(toast_type)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = ROW_PAD_X
	sb.content_margin_right = ROW_PAD_X
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A wrapping label measures its height at its width; giving it the row's width up front
	# keeps the first measurement from ballooning to one word a line.
	label.custom_minimum_size.x = TOAST_WIDTH - 2.0 * PANEL_PAD - 2.0 * ROW_PAD_X - SCROLLBAR_ROOM
	if toast_type == TOAST_WARNING:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _toast_text_color(toast_type))
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	return panel


## Opened by itself the slide-out shows the newest rows it hasn't shown yet, at most
## MAX_TOASTS; opened from the dock it shows every kept row.
func _apply_row_visibility() -> void:
	var rows := _rows.get_children()
	var shown := 0
	for i in range(rows.size() - 1, -1, -1):
		var row: Control = rows[i]
		if _all:
			row.visible = true
		else:
			row.visible = bool(row.get_meta("fresh", false)) and shown < MAX_TOASTS
		if row.visible:
			shown += 1
	_empty.visible = _all and rows.is_empty()
	_queue_fit()


func _open_slide(all_rows: bool) -> void:
	_all = all_rows
	_set_interactive(all_rows)
	if all_rows:
		for tone: String in TONES:
			_unread[tone] = 0
		_refresh_bells()
	_apply_row_visibility()
	_fit()
	if not _open:
		_open = true
		_panel.position.y = _clip.size.y
		_tween_panel_to(0.0)
	_update_dock_rim()
	_scroll_to_newest.call_deferred()
	_held = false
	_timer.start(TOAST_DURATION)


func _on_dock_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_dock.accept_event()
	if _open and _all:
		collapse()
	else:
		_open_slide(true)


func _on_timer() -> void:
	if not _open:
		return
	if _all and _panel.get_global_rect().has_point(get_global_mouse_position()):
		_held = true
		_timer.start(0.5)
		return
	if _held:
		_held = false
		_timer.start(HOVER_GRACE)
		return
	collapse()


func _tween_panel_to(y: float) -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = create_tween()
	_slide.tween_property(_panel, "position:y", y, SLIDE_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _scroll_to_newest() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


## Sizes the slide-out to its visible rows (capped; beyond that they scroll) and keeps its
## bottom edge tucked under the dock.
func _fit() -> void:
	_fit_queued = false
	var cap: float = maxf(120.0, size.y * SLIDE_MAX_SHARE)
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, cap)
	var h: float = _panel.get_combined_minimum_size().y
	_clip.offset_top = _clip.offset_bottom - h
	_panel.size = Vector2(TOAST_WIDTH, h)
	if not _open and not (_slide != null and _slide.is_valid() and _slide.is_running()):
		_panel.position.y = h


# ── Where toasts come from ────────────────────────────────────────────────────

func _on_build_rejected_no_funds(message: String) -> void:
	_push_toast(message, TOAST_WARNING)

func _on_toast_requested(message: String, toast_type: String) -> void:
	_push_toast(message, TOAST_WARNING if toast_type == TOAST_ERROR else toast_type)

func _on_building_added(instance: Dictionary) -> void:
	if not BuildingState.is_player_owned(instance):
		return
	# building_added fires at completion (promotion), so this is the "built" toast.
	_push_toast(_format_building_message(instance), TOAST_SUCCESS)

func _on_materials_ordered(instance_id: String, tile_id: String) -> void:
	var parts: Array = []
	var max_turns: int = 0
	for s in TransportState.get_inbound_transport_shipments(tile_id):
		if str(s.get("construction_instance_id", "")) != instance_id:
			continue
		parts.append("%d %s" % [int(s.get("qty", 0)), Catalog.get_display_name(str(s.get("good_id", "")))])
		max_turns = maxi(max_turns, int(s.get("turns_remaining", 0)))
	if parts.is_empty():
		return
	var msg: String = "Ordered %s — arriving in %d turn%s" % [", ".join(parts), max_turns, "" if max_turns == 1 else "s"]
	_push_toast(msg, TOAST_SUCCESS)

func _on_construction_cancelled(_instance_id: String, tile_id: String) -> void:
	_push_toast("Construction cancelled on tile %s — build cost refunded" % Catalog.tile_label(tile_id), TOAST_CAUTION)

func _on_construction_started(instance_id: String, tile_id: String) -> void:
	var project: Dictionary = Construction.construction_projects.get(instance_id, {})
	if project.is_empty():
		return  # 0-duration build completed instantly; the "built" toast covers it.
	var building: Dictionary = Catalog.get_building(str(project.get("building_id", "")))
	var b_name: String = str(building.get("display_name", project.get("building_id", "")))
	var recipe: Dictionary = Catalog.get_recipe(str(project.get("recipe_id", "")))
	var recipe_name: String = str(recipe.get("display_name", ""))
	var who: String = b_name if recipe_name == "" else "%s — %s" % [b_name, recipe_name]
	var duration: int = int(project.get("construction_duration", 0))
	var msg: String = "Construction started for %s on tile %s. Will be complete in %d turn%s" % [
		who, Catalog.tile_label(tile_id), duration, "" if duration == 1 else "s"
	]
	_push_toast(msg, TOAST_SUCCESS)

func _on_money_changed(new_amount: float) -> void:
	if _prev_money >= 0.0 and new_amount < 0.0:
		_push_toast("!  Cash is in the red: £%.2f" % new_amount, TOAST_WARNING)
	_prev_money = new_amount

func _format_building_message(instance: Dictionary) -> String:
	var building_id: String = instance.get("building_id", "")
	var recipe_id: String = instance.get("recipe_id", "")
	var building: Dictionary = Catalog.get_building(building_id)
	var b_name: String = building.get("display_name", building_id)
	var cost: float = building.get("base_price", 0.0)

	var line: String = "Built %s" % b_name

	var recipe: Dictionary = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	if not recipe.is_empty():
		var outputs: Array = recipe.get("outputs", [])
		var parts: Array = []
		for o in outputs:
			var iname: String = String(o.get("internal_name", ""))
			var qty: int = int(o.get("qty", 0))
			if iname == "" or qty <= 0:
				continue
			var good: Dictionary = Catalog.get_good_by_internal_name(iname)
			var disp: String = good.get("display_name", iname)
			parts.append("%d %s" % [qty, disp])
		if not parts.is_empty():
			line += " — produces %s/turn" % ", ".join(parts)

	var meta: Array = []
	if cost > 0:
		meta.append("£%.0f" % cost)
	if not meta.is_empty():
		line += "  ·  " + "  ·  ".join(meta)
	return line

func _on_stockpile_market_sale_completed(sale_record: Dictionary) -> void:
	_pending_sales.append(sale_record.duplicate(true))
	if not TurnManager.is_resolving:
		_flush_sales.call_deferred()

func _flush_sales() -> void:
	if _pending_sales.is_empty():
		return
	var message: String = _format_sales_batch(_pending_sales)
	_pending_sales.clear()
	if message != "":
		_push_toast(message, TOAST_SUCCESS)

func _format_sales_batch(records: Array) -> String:
	if records.size() == 1:
		return _format_stockpile_sale_message(records[0])
	var units: int = 0
	var goods: Dictionary = {}
	var revenue: float = 0.0
	for record: Dictionary in records:
		revenue += float(record.get("total_revenue", 0.0))
		for item: Dictionary in record.get("items", []):
			units += int(item.get("qty", 0))
			goods[str(item.get("good_id", ""))] = true
	return "Last turn you sold %d units of %d goods, totalling £%.2f." % [units, goods.size(), revenue]

func _format_stockpile_sale_message(sale_record: Dictionary) -> String:
	var items: Array = sale_record.get("items", [])
	if items.is_empty():
		return ""
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("qty", 0)) == int(b.get("qty", 0)):
			return str(a.get("good_id", "")) < str(b.get("good_id", ""))
		return int(a.get("qty", 0)) > int(b.get("qty", 0))
	)
	var first: Dictionary = items[0]
	var first_qty: int = int(first.get("qty", 0))
	var first_good_id: String = first.get("good_id", "")
	var first_revenue: float = float(first.get("revenue", 0.0))
	var message := "%d %s sold to market for £%.2f" % [
		first_qty,
		Catalog.get_display_name(first_good_id),
		first_revenue,
	]
	if items.size() > 1:
		var other_qty := 0
		var other_revenue := 0.0
		for i in range(1, items.size()):
			other_qty += int(items[i].get("qty", 0))
			other_revenue += float(items[i].get("revenue", 0.0))
		var good_word := "good" if items.size() == 2 else "goods"
		message += " and %d units of %d other %s sold for £%.2f" % [
			other_qty,
			items.size() - 1,
			good_word,
			other_revenue,
		]
	message += ". Total sales: £%.2f" % float(sale_record.get("total_revenue", 0.0))
	return message

func _toast_bg_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_BG
		TOAST_CAUTION:
			return CAUTION_BG
		_:
			return SUCCESS_BG

func _toast_border_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_BORDER
		TOAST_CAUTION:
			return CAUTION_BORDER
		_:
			return SUCCESS_BORDER

func _toast_text_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_TEXT
		TOAST_CAUTION:
			return CAUTION_TEXT
		_:
			return SUCCESS_TEXT
