extends Control

const BRASS_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/brass_pipe_frame_transparent.png")
const PANEL_TITLE_FONT: Font = preload("res://assets/fonts/BebasNeue-Regular.ttf")
const TITLE_FONT: Font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")

const RESEARCH_UNLOCKS_PATH := "res://data/research_unlocks.csv"
# The advisor-seat progression nodes stay hidden until MatchState.advisors_unlocked (the
# `unlock advisors` cheat). Nothing else prereqs them, so hiding strands no chain.
const _SEAT_RESEARCH := {"research_people_008": true, "research_people_009": true,
	"research_people_010": true, "research_people_011": true}
var _seat_research_shown := false
const NAVY_TOP_LEFT := Color(0.025, 0.18, 0.34, 1.0)
const NAVY_TOP_RIGHT := Color(0.0, 0.12156863, 0.24313726, 1.0)
const NAVY_BOTTOM_LEFT := Color(0.0, 0.105, 0.215, 1.0)
const NAVY_BOTTOM_RIGHT := Color(0.0, 0.067, 0.145, 1.0)
const PANEL_OUTLINE_WIDTH := 5.0
const PANEL_EDGE_INSET := PANEL_OUTLINE_WIDTH
const LEGACY_BRASS_SOURCE_FRAME_SLICE := 168.0
const LEGACY_BRASS_DEST_FRAME_SLICE := 72.0
const LEGACY_BRASS_MAX_STRETCH_SEGMENT := 250.0
const LEGACY_BRASS_BRACKET_SOURCE_LENGTH := 56.0
const LEGACY_BRASS_BRACKET_DEST_LENGTH := 30.0
const TAB_BAR_HEIGHT := 82.0
const TREE_MARGIN := 34.0
const PANEL_TOP_BAR_HEIGHT := 60.0
const PANEL_TITLE_SIZE := 32
const PANEL_HEADER_PADDING := 12.0
const PANEL_CLOSE_MINIMUM_SIZE := Vector2(20.0, 20.0)
const PANEL_CLOSE_FONT_SIZE := 20
const PANEL_OUTLINE_RADIUS := 12
const UNLOCK_TITLE_SHADOW_OFFSET := 2.0
const KNOWLEDGE_PANEL_SIZE := Vector2(250.0, 100.0)
const KNOWLEDGE_PANEL_EXPANDED_HEIGHT := 140.0
const KNOWLEDGE_PANEL_GAP := 10.0
const KNOWLEDGE_PANEL_TEXT_SIZE := 14
const FREE_UNLOCK_BUTTON_HEIGHT := 30.0
const TAB_GAP := 6.0
const TAB_HEIGHT := 54.0
const TAB_FONT_SIZE := 14
const UNLOCK_SIZE := Vector2(320.0, 292.0)
const UNLOCK_RADIUS := 12
const UNLOCK_SLOT_SIZE := 80.0
const UNLOCK_TITLE_SIZE := 22
const UNLOCK_DESC_SIZE := 12
const UNLOCK_CONDITION_SIZE := 12
const UNLOCK_LANE_GAP := 370.0
const TREE_FIT_PADDING := 28.0
const TREE_BOTTOM_PADDING := 42.0
const ROOT_TO_RANK_GAP := 50.0
const RANK_SEPARATOR_GAP := 70.0
const RANK_VERTICAL_GAP := 50.0
const UNLOCK_MIN_GAP := 50.0
const RANK_ROWS_PER_COLUMN := 2
const RANK_COLUMNS_PER_ROW := 5
const UNLOCK_BEVEL_SIZE := 5.0
const RANK_STAMP_SIZE := Vector2(180.0, 150.0)
const RANK_STAMP_OUTLINE := 6.0
const RANK_STAMP_CORNER_RADIUS := 18.0
const RANK_STAMP_OFFSET_FROM_UNLOCK := 100.0
const RANK_STAMP_FONT_SIZE := 82
const CABLE_WIDTH_AT_MAX_ZOOM := 10.0
const CABLE_STRIPE_WIDTH_AT_MAX_ZOOM := 2.0
const CABLE_CONNECTOR_SIZE := Vector2(36.0, 18.0)
const CABLE_ROUTE_MARGIN := 80.0
const CABLE_BEND_RADIUS := 28.0
const CABLE_CONNECTOR_LEAD := 10.0
const PAN_SPEED_MULTIPLIER := 1.2
const MAX_ZOOM := 1.0
const ZOOM_STEP := 1.12
# ── Free-unlock cadence (owner, 2026-08-19) ────────────────────────────────
# One free unlock at turns 1, 12, 36, 60 and 84; then two more every 48 turns
# (132, 180, 228, 276 in the 300-turn game). Turn 1 carries no turn_advanced event
# — that signal fires for turns 2..MAX_TURNS+1 — so the turn-1 grant lands as the
# opening balance in _ready, and every later milestone is added as its turn arrives.
const FREE_UNLOCK_MILESTONES: Array[int] = [1, 12, 36, 60, 84]
const FREE_UNLOCK_RECUR_AFTER := 84
const FREE_UNLOCK_RECUR_EVERY := 48
const FREE_UNLOCK_RECUR_COUNT := 2
const RANKS := ["I", "II", "III"]
const CATEGORIES := [
	"Mining and Surveying",
	"Petrochemistry",
	"Metallurgy",
	"Inorganic Chemistry",
	"Biochemistry",
	"Manufacturing",
	"Hydrocarbon Power",
	"Renewable Power",
	"Recycling",
	"Infrastructure",
	"Logistics",
	"Markets and Operations",
	"People Management",
]

var _unlock_rows: Array[Dictionary] = []
var _selected_category := "Mining and Surveying"
var _category_view_state := {}
var _tab_rects := {}
var _unlock_style: StyleBoxFlat
var _unlock_slot_style: StyleBoxFlat
var _description_style: StyleBoxFlat
var _condition_style: StyleBoxFlat
var _tab_selected_style: StyleBoxFlat
var _tab_unselected_style: StyleBoxFlat
var _close_button: Button
var _search_input: LineEdit
var _search_query := ""
var _stamp_font: Font
var _dragging_tree := false
var _free_unlocks := 0
var _choosing_free_unlock := false
var _hover_unlock_title := ""
var _free_unlocked_titles := {}
var _expanded_requirement_titles := {}
# turn -> free unlocks granted that turn; built from the cadence above in _ready.
var _knowledge_grants: Dictionary = {}

## The cadence as a {turn: grant} table. Pure — MAX_TURNS is the only input — so the
## schedule can be unit-tested without standing the panel up.
static func free_unlock_schedule(max_turns: int) -> Dictionary:
	var out: Dictionary = {}
	for t in FREE_UNLOCK_MILESTONES:
		if t <= max_turns:
			out[t] = int(out.get(t, 0)) + 1
	var recur := FREE_UNLOCK_RECUR_AFTER + FREE_UNLOCK_RECUR_EVERY
	while recur <= max_turns:
		out[recur] = int(out.get(recur, 0)) + FREE_UNLOCK_RECUR_COUNT
		recur += FREE_UNLOCK_RECUR_EVERY
	return out

## Free unlocks earned by `turn` inclusive — the opening balance for a panel that comes
## up mid-game (a load, or lazy creation), since past turn_advanced events won't replay.
static func free_unlocks_earned_by(turn: int, max_turns: int) -> int:
	var total := 0
	var schedule := free_unlock_schedule(max_turns)
	for t in schedule:
		if int(t) <= turn:
			total += int(schedule[t])
	return total

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_stamp_font = _make_stamp_font()
	_create_close_button()
	_create_search_input()
	_build_styles()
	_load_unlock_rows()
	_knowledge_grants = free_unlock_schedule(TurnManager.MAX_TURNS)
	# Opening balance = everything earned up to the current turn (turn 1 for a new game,
	# more if this panel came up after a load). Later milestones arrive via turn_advanced.
	_free_unlocks = free_unlocks_earned_by(TurnManager.current_turn, TurnManager.MAX_TURNS)
	if not TurnManager.turn_advanced.is_connected(_on_turn_advanced):
		TurnManager.turn_advanced.connect(_on_turn_advanced)
	_seat_research_shown = MatchState.advisors_unlocked
	if not MatchState.advisors_changed.is_connected(_on_advisors_changed):
		MatchState.advisors_changed.connect(_on_advisors_changed)
	resized.connect(_on_resized)
	call_deferred("_sync_close_button_layout")

func _create_close_button() -> void:
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.custom_minimum_size = PANEL_CLOSE_MINIMUM_SIZE
	_close_button.add_theme_font_size_override("font_size", PANEL_CLOSE_FONT_SIZE)
	if DS.theme != null:
		_close_button.theme = DS.theme
	_close_button.pressed.connect(_close_panel)
	add_child(_close_button)


## Search box in the panel header. A real LineEdit child rather than something painted in
## _draw(): this panel is a custom canvas, but the close button already proves Control
## children work here, and text entry is not worth hand-rolling.
func _create_search_input() -> void:
	_search_input = LineEdit.new()
	_search_input.name = "ResearchSearchInput"
	_search_input.placeholder_text = "Search research — name or reward"
	_search_input.clear_button_enabled = true
	if DS.theme != null:
		_search_input.theme = DS.theme
	_search_input.text_changed.connect(_on_search_changed)
	add_child(_search_input)


func _on_search_changed(text: String) -> void:
	_search_query = text
	# Results are drawn as a flat rank layout across every category, so the stored
	# per-category pan/zoom would leave them off-screen. Reset the view each keystroke.
	_category_view_state.erase(_selected_category)
	queue_redraw()

func begin_free_unlock_choice() -> void:
	if _free_unlocks <= 0:
		return
	_choosing_free_unlock = true
	_hover_unlock_title = ""
	queue_redraw()

## Tutorial/coach hook: the exact on-screen rectangle of a searched research node.
## The tree is custom drawn, so it cannot otherwise be spotlighted like a normal Control.
func tutorial_unlock_rect(title: String) -> Rect2:
	if title == "" or not is_visible_in_tree():
		return Rect2()
	var unlocks := _category_unlocks(_selected_category)
	var layout := _layout_unlocks(unlocks)
	if not layout.has(title):
		return Rect2()
	var state := _current_view_state()
	var zoom: float = state["zoom"]
	var origin := _tree_origin() + (state["pan"] as Vector2)
	var local: Rect2 = layout[title]
	return Rect2(global_position + origin + local.position * zoom, local.size * zoom).grow(8.0)


func _search_input_rect() -> Rect2:
	var body := _body_rect()
	var close := _close_button_rect()
	var h := PANEL_TOP_BAR_HEIGHT - 16.0
	var w := minf(300.0, maxf(140.0, body.size.x * 0.28))
	var x := close.position.x - PANEL_HEADER_PADDING - w
	return Rect2(Vector2(x, body.position.y + (PANEL_TOP_BAR_HEIGHT - h) * 0.5), Vector2(w, h))


func _sync_search_input_layout() -> void:
	if _search_input == null:
		return
	if DS.theme != null and _search_input.theme != DS.theme:
		_search_input.theme = DS.theme
	var rect := _search_input_rect()
	_search_input.position = rect.position
	_search_input.size = rect.size
	_search_input.visible = visible

func _make_stamp_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Times New Roman", "Times"])
	font.font_weight = 800
	return font

func _input(event: InputEvent) -> void:
	# Esc cancels free-unlock picking and must work even while the search LineEdit has focus.
	if _choosing_free_unlock and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_ESCAPE:
		_choosing_free_unlock = false
		_hover_unlock_title = ""
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not visible or not _event_inside_panel(event):
		return

	if event is InputEventMagnifyGesture:
		var gesture := event as InputEventMagnifyGesture
		_zoom_tree_by_factor(gesture.factor, get_local_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		_pan_tree(-(event as InputEventPanGesture).delta)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_tree_by_factor(ZOOM_STEP if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP, _event_local_position(mouse_event))
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_tree_by_factor(ZOOM_STEP if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP, mouse_event.position)
			get_viewport().set_input_as_handled()
			accept_event()
			return

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if _close_button_rect().has_point(mouse_event.position):
					_close_panel()
					accept_event()
					return
				if _choose_free_unlock_button_rect().has_point(mouse_event.position) and _free_unlocks > 0:
					_choosing_free_unlock = true
					_update_hover_unlock(mouse_event.position)
					queue_redraw()
					accept_event()
					return
				if _toggle_requirement_dropdown(mouse_event.position):
					accept_event()
					return
				if _choosing_free_unlock and _try_choose_free_unlock(mouse_event.position):
					accept_event()
					return
				if _select_tab_at(mouse_event.position):
					accept_event()
					return
				_dragging_tree = _tree_rect().has_point(mouse_event.position)
				if _dragging_tree:
					accept_event()
					return
			elif _dragging_tree:
				_dragging_tree = false
				accept_event()
				return

	if event is InputEventMouseMotion and _dragging_tree:
		var motion := event as InputEventMouseMotion
		_pan_tree(motion.relative)
		get_viewport().set_input_as_handled()
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_hover_unlock(motion.position)
		_update_profitability_tooltip(motion.position)

	if event is InputEventMagnifyGesture:
		var gesture := event as InputEventMagnifyGesture
		_zoom_tree_by_factor(gesture.factor, get_local_mouse_position())
		get_viewport().set_input_as_handled()
		accept_event()

	if event is InputEventPanGesture:
		_pan_tree(-(event as InputEventPanGesture).delta)
		get_viewport().set_input_as_handled()
		accept_event()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_draw_navy_fill()
	_draw_tree()
	_draw_tabs()
	_draw_panel_top_bar()
	_draw_knowledge_panel()
	_draw_panel_outline()

func _draw_navy_fill() -> void:
	var body_rect := Rect2(Vector2(PANEL_EDGE_INSET, PANEL_EDGE_INSET), size - Vector2(PANEL_EDGE_INSET * 2.0, PANEL_EDGE_INSET * 2.0))
	if body_rect.size.x <= 0.0 or body_rect.size.y <= 0.0:
		return

	draw_polygon(
		PackedVector2Array([
			body_rect.position,
			Vector2(body_rect.end.x, body_rect.position.y),
			body_rect.end,
			Vector2(body_rect.position.x, body_rect.end.y),
		]),
		PackedColorArray([
			NAVY_TOP_LEFT,
			NAVY_TOP_RIGHT,
			NAVY_BOTTOM_RIGHT,
			NAVY_BOTTOM_LEFT,
		])
	)

func _draw_panel_top_bar() -> void:
	var header := _panel_top_bar_rect()
	if header.size.x <= 0.0:
		return

	draw_polygon(
		PackedVector2Array([
			header.position,
			Vector2(header.end.x, header.position.y),
			header.end,
			Vector2(header.position.x, header.end.y),
		]),
		PackedColorArray([
			DS.PALETTE["BG_PANEL"].lightened(0.05),
			DS.PALETTE["BG_PANEL"],
			DS.PALETTE["BG_PANEL"].darkened(0.18),
			DS.PALETTE["BG_PANEL"].darkened(0.08),
		])
	)
	draw_line(Vector2(header.position.x, header.end.y), header.end, DS.PALETTE["BORDER_SOFT"], 1.0)
	var title_position := _panel_header_content_origin()
	_draw_text_fit(
		PANEL_TITLE_FONT,
		"Research",
		Rect2(title_position, Vector2(220.0, header.size.y - PANEL_HEADER_PADDING * 2.0)),
		PANEL_TITLE_SIZE,
		DS.PALETTE["TEXT"],
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_sync_close_button_layout()
	_sync_search_input_layout()

func _draw_knowledge_panel() -> void:
	var rect := _knowledge_panel_rect()
	var style := _make_stylebox(DS.PALETTE["BG_PANEL"], DS.PALETTE["BORDER_SOFT"], 8, 1)
	draw_style_box(style, rect)

	var padded := rect.grow(-10.0)
	var message_rect := Rect2(padded.position, Vector2(padded.size.x, 38.0))
	_draw_wrapped_lines(BODY_FONT, _knowledge_opportunity_text(), message_rect, KNOWLEDGE_PANEL_TEXT_SIZE, DS.PALETTE["ACCENT"], 2, HORIZONTAL_ALIGNMENT_LEFT, true)

	var separator_y := rect.position.y + 56.0
	draw_line(Vector2(rect.position.x + 10.0, separator_y), Vector2(rect.end.x - 10.0, separator_y), DS.PALETTE["BORDER_SOFT"], 1.0)
	_draw_text_fit(BODY_FONT, "Free Unlocks: %d" % _free_unlocks, Rect2(rect.position + Vector2(10.0, 62.0), Vector2(rect.size.x - 20.0, 24.0)), KNOWLEDGE_PANEL_TEXT_SIZE, DS.PALETTE["TEXT"], HORIZONTAL_ALIGNMENT_LEFT)

	if _free_unlocks > 0:
		var button_rect := _choose_free_unlock_button_rect()
		var hovered := button_rect.has_point(get_local_mouse_position())
		# Two states: SELECTED (mid-choice) keeps the filled accent look — cream fill,
		# navy text. DEFAULT is the reverse — navy fill with cream/off-white text.
		var selected := _choosing_free_unlock
		var fill_color: Color = DS.PALETTE["ACCENT"] if selected else DS.PALETTE["BG_PANEL"]
		var text_color: Color = DS.PALETTE["BG_PANEL"] if selected else DS.PALETTE["ACCENT"]
		if hovered:
			fill_color = fill_color.lightened(0.08)
		var button_style := _make_stylebox(fill_color, DS.PALETTE["BORDER"], 8, 1)
		draw_style_box(button_style, button_rect)
		_draw_text_fit(BODY_FONT, "Choose Free Unlocks", button_rect.grow(-7.0), KNOWLEDGE_PANEL_TEXT_SIZE, text_color, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_panel_outline() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = DS.PALETTE["BORDER_STRONG"]
	style.border_width_left = int(PANEL_OUTLINE_WIDTH)
	style.border_width_top = int(PANEL_OUTLINE_WIDTH)
	style.border_width_right = int(PANEL_OUTLINE_WIDTH)
	style.border_width_bottom = int(PANEL_OUTLINE_WIDTH)
	style.corner_radius_top_left = PANEL_OUTLINE_RADIUS
	style.corner_radius_top_right = PANEL_OUTLINE_RADIUS
	style.corner_radius_bottom_right = PANEL_OUTLINE_RADIUS
	style.corner_radius_bottom_left = PANEL_OUTLINE_RADIUS
	draw_style_box(style, Rect2(Vector2.ZERO, size))

# Kept dormant so the brass pipe frame can be restored without rebuilding its
# 9-slice/stretch settings.
func _draw_legacy_brass_pipe_frame() -> void:
	var frame_rect := Rect2(Vector2.ZERO, size)
	var texture_size: Vector2 = BRASS_FRAME_TEXTURE.get_size()
	var source_slice: float = min(LEGACY_BRASS_SOURCE_FRAME_SLICE, texture_size.x * 0.5, texture_size.y * 0.5)
	var dest_slice: float = min(LEGACY_BRASS_DEST_FRAME_SLICE, frame_rect.size.x * 0.35, frame_rect.size.y * 0.35)
	var dest_right: float = frame_rect.end.x - dest_slice
	var dest_bottom: float = frame_rect.end.y - dest_slice
	var source_right: float = texture_size.x - source_slice
	var source_bottom: float = texture_size.y - source_slice

	_draw_region(Rect2(0.0, 0.0, source_slice, source_slice), Rect2(frame_rect.position, Vector2(dest_slice, dest_slice)))
	_draw_region(Rect2(source_right, 0.0, source_slice, source_slice), Rect2(dest_right, frame_rect.position.y, dest_slice, dest_slice))
	_draw_region(Rect2(0.0, source_bottom, source_slice, source_slice), Rect2(frame_rect.position.x, dest_bottom, dest_slice, dest_slice))
	_draw_region(Rect2(source_right, source_bottom, source_slice, source_slice), Rect2(dest_right, dest_bottom, dest_slice, dest_slice))

	_draw_segmented_edge(
		Rect2((texture_size.x - LEGACY_BRASS_MAX_STRETCH_SEGMENT) * 0.5, 0.0, LEGACY_BRASS_MAX_STRETCH_SEGMENT, source_slice),
		Rect2(frame_rect.position.x + dest_slice, frame_rect.position.y, frame_rect.size.x - dest_slice * 2.0, dest_slice),
		true,
		Rect2((texture_size.x - LEGACY_BRASS_BRACKET_SOURCE_LENGTH) * 0.5, 0.0, LEGACY_BRASS_BRACKET_SOURCE_LENGTH, source_slice)
	)
	_draw_segmented_edge(
		Rect2((texture_size.x - LEGACY_BRASS_MAX_STRETCH_SEGMENT) * 0.5, source_bottom, LEGACY_BRASS_MAX_STRETCH_SEGMENT, source_slice),
		Rect2(frame_rect.position.x + dest_slice, dest_bottom, frame_rect.size.x - dest_slice * 2.0, dest_slice),
		true,
		Rect2((texture_size.x - LEGACY_BRASS_BRACKET_SOURCE_LENGTH) * 0.5, source_bottom, LEGACY_BRASS_BRACKET_SOURCE_LENGTH, source_slice)
	)
	_draw_segmented_edge(
		Rect2(0.0, (texture_size.y - LEGACY_BRASS_MAX_STRETCH_SEGMENT) * 0.5, source_slice, LEGACY_BRASS_MAX_STRETCH_SEGMENT),
		Rect2(frame_rect.position.x, frame_rect.position.y + dest_slice, dest_slice, frame_rect.size.y - dest_slice * 2.0),
		false,
		Rect2(0.0, (texture_size.y - LEGACY_BRASS_BRACKET_SOURCE_LENGTH) * 0.5, source_slice, LEGACY_BRASS_BRACKET_SOURCE_LENGTH)
	)
	_draw_segmented_edge(
		Rect2(source_right, (texture_size.y - LEGACY_BRASS_MAX_STRETCH_SEGMENT) * 0.5, source_slice, LEGACY_BRASS_MAX_STRETCH_SEGMENT),
		Rect2(dest_right, frame_rect.position.y + dest_slice, dest_slice, frame_rect.size.y - dest_slice * 2.0),
		false,
		Rect2(source_right, (texture_size.y - LEGACY_BRASS_BRACKET_SOURCE_LENGTH) * 0.5, source_slice, LEGACY_BRASS_BRACKET_SOURCE_LENGTH)
	)

func _draw_segmented_edge(source_rect: Rect2, dest_rect: Rect2, horizontal: bool, bracket_rect: Rect2) -> void:
	var length: float = dest_rect.size.x if horizontal else dest_rect.size.y
	if length <= 0.0:
		return

	var segment_count: int = max(1, ceili(length / LEGACY_BRASS_MAX_STRETCH_SEGMENT))
	var segment_length: float = length / segment_count

	for index in segment_count:
		var segment_dest := dest_rect
		if horizontal:
			segment_dest.position.x += segment_length * index
			segment_dest.size.x = segment_length
		else:
			segment_dest.position.y += segment_length * index
			segment_dest.size.y = segment_length
		_draw_region(source_rect, segment_dest)

	for index in range(1, segment_count):
		var bracket_dest := dest_rect
		if horizontal:
			bracket_dest.position.x += segment_length * index - LEGACY_BRASS_BRACKET_DEST_LENGTH * 0.5
			bracket_dest.size.x = LEGACY_BRASS_BRACKET_DEST_LENGTH
		else:
			bracket_dest.position.y += segment_length * index - LEGACY_BRASS_BRACKET_DEST_LENGTH * 0.5
			bracket_dest.size.y = LEGACY_BRASS_BRACKET_DEST_LENGTH
		_draw_region(bracket_rect, bracket_dest)

func _draw_region(source_rect: Rect2, dest_rect: Rect2) -> void:
	draw_texture_rect_region(BRASS_FRAME_TEXTURE, dest_rect, source_rect)

func _build_styles() -> void:
	_unlock_style = _make_stylebox(DS.PALETTE["BG_INSET"], DS.PALETTE["BORDER_SOFT"], UNLOCK_RADIUS, 2)
	_unlock_slot_style = _make_stylebox(DS.PALETTE["BG_PANEL"], DS.PALETTE["BORDER"], 10, 2)
	_description_style = _make_stylebox(DS.PALETTE["BG_PANEL"], DS.PALETTE["BORDER_SOFT"], 7, 1)
	_condition_style = _make_stylebox(DS.PALETTE["BG_PANEL"], DS.PALETTE["BORDER"], 8, 1)
	_tab_selected_style = _make_stylebox(DS.PALETTE["ACCENT"], DS.PALETTE["BG_PANEL"], 9, 2)
	_tab_unselected_style = _make_stylebox(DS.PALETTE["BG_PANEL"], DS.PALETTE["BORDER_SOFT"], 9, 1)

func _make_stylebox(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	return style

func _load_unlock_rows() -> void:
	_unlock_rows.clear()
	if not FileAccess.file_exists(RESEARCH_UNLOCKS_PATH):
		push_warning("Research unlock CSV missing at %s" % RESEARCH_UNLOCKS_PATH)
		return

	var file := FileAccess.open(RESEARCH_UNLOCKS_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open research unlock CSV at %s" % RESEARCH_UNLOCKS_PATH)
		return

	var header := file.get_csv_line()
	var column_index := {}
	for index in header.size():
		column_index[header[index]] = index

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or row[0].strip_edges().is_empty():
			continue
		if _SEAT_RESEARCH.has(_csv_value(row, column_index, "research_node_id")) and not MatchState.advisors_unlocked:
			continue
		_unlock_rows.append({
			"category": _csv_value(row, column_index, "category"),
			"prereq_1": _csv_value(row, column_index, "prereq_1"),
			"prereq_2": _csv_value(row, column_index, "prereq_2"),
			"prereq_3": _csv_value(row, column_index, "prereq_3"),
			"prereq_othercategory": _csv_value(row, column_index, "prereq_othercategory"),
			"rank": _csv_value(row, column_index, "rank", "I"),
			"action": _csv_value(row, column_index, "Action"),
			"object": _csv_value(row, column_index, "Object"),
			"quantity": _csv_value(row, column_index, "Quantity"),
			"unit": _csv_value(row, column_index, "Unit"),
			"title": _csv_value(row, column_index, "title"),
			"icon": _csv_value(row, column_index, "icon"),
			"description": _csv_value(row, column_index, "description"),
		})
	_category_view_state.clear()

func _on_resized() -> void:
	_category_view_state.clear()
	_sync_close_button_layout()
	_sync_search_input_layout()
	queue_redraw()

## Reload the tree only when the seat-research visibility actually flips (the `unlock
## advisors` cheat) — not on every hire/fire, which also emit advisors_changed.
func _on_advisors_changed() -> void:
	if _seat_research_shown == MatchState.advisors_unlocked:
		return
	_seat_research_shown = MatchState.advisors_unlocked
	_load_unlock_rows()
	queue_redraw()

func _on_turn_advanced(new_turn: int) -> void:
	if _knowledge_grants.has(new_turn):
		_free_unlocks += int(_knowledge_grants[new_turn])
	queue_redraw()

func _csv_value(row: PackedStringArray, column_index: Dictionary, key: String, fallback: String = "") -> String:
	if not column_index.has(key):
		return fallback
	var index: int = column_index[key]
	if index < 0 or index >= row.size():
		return fallback
	return row[index].strip_edges()

func _body_rect() -> Rect2:
	return Rect2(Vector2(PANEL_EDGE_INSET, PANEL_EDGE_INSET), size - Vector2(PANEL_EDGE_INSET * 2.0, PANEL_EDGE_INSET * 2.0))

func _panel_top_bar_rect() -> Rect2:
	var body := _body_rect()
	return Rect2(body.position, Vector2(body.size.x, PANEL_TOP_BAR_HEIGHT))

func _panel_header_content_origin() -> Vector2:
	return _body_rect().position + Vector2(PANEL_HEADER_PADDING, PANEL_HEADER_PADDING)

func _close_button_rect() -> Rect2:
	var body := _body_rect()
	var button_size := PANEL_CLOSE_MINIMUM_SIZE
	if _close_button != null:
		button_size = _close_button.get_combined_minimum_size()
		button_size.x = maxf(button_size.x, PANEL_CLOSE_MINIMUM_SIZE.x)
		button_size.y = maxf(button_size.y, PANEL_CLOSE_MINIMUM_SIZE.y)
	var y := body.position.y + (PANEL_TOP_BAR_HEIGHT - button_size.y) * 0.5
	return Rect2(Vector2(body.end.x - button_size.x - PANEL_HEADER_PADDING, y), button_size)

func _sync_close_button_layout() -> void:
	if _close_button == null:
		return
	if DS.theme != null and _close_button.theme != DS.theme:
		_close_button.theme = DS.theme
	var rect := _close_button_rect()
	_close_button.position = rect.position
	_close_button.size = rect.size
	_close_button.visible = visible

func _knowledge_panel_rect() -> Rect2:
	var body := _body_rect()
	var height := KNOWLEDGE_PANEL_EXPANDED_HEIGHT if _free_unlocks > 0 else KNOWLEDGE_PANEL_SIZE.y
	return Rect2(body.position + Vector2(TREE_MARGIN, PANEL_HEADER_PADDING + PANEL_TOP_BAR_HEIGHT + KNOWLEDGE_PANEL_GAP), Vector2(KNOWLEDGE_PANEL_SIZE.x, height))

func _choose_free_unlock_button_rect() -> Rect2:
	if _free_unlocks <= 0:
		return Rect2()
	var panel := _knowledge_panel_rect()
	return Rect2(panel.position + Vector2(10.0, 100.0), Vector2(panel.size.x - 20.0, FREE_UNLOCK_BUTTON_HEIGHT))

func _tree_rect() -> Rect2:
	var body := _body_rect()
	return Rect2(
		body.position + Vector2(TREE_MARGIN, TREE_MARGIN + PANEL_TOP_BAR_HEIGHT),
		body.size - Vector2(TREE_MARGIN * 2.0, TREE_MARGIN * 2.0 + TAB_BAR_HEIGHT + PANEL_TOP_BAR_HEIGHT)
	)

func _tab_bar_rect() -> Rect2:
	var body := _body_rect()
	return Rect2(body.position.x + TREE_MARGIN, body.end.y - TAB_BAR_HEIGHT + 12.0, body.size.x - TREE_MARGIN * 2.0, TAB_HEIGHT)

func _current_view_state() -> Dictionary:
	if not _category_view_state.has(_selected_category):
		_category_view_state[_selected_category] = _default_view_state(_selected_category)
	return _category_view_state[_selected_category]

func _default_view_state(category: String) -> Dictionary:
	var unlocks := _category_unlocks(category)
	var layout := _layout_unlocks(unlocks)
	var bounds := _tree_content_bounds(layout, unlocks)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {"zoom": MAX_ZOOM, "pan": Vector2.ZERO}

	var zoom := _fit_zoom_for_bounds(bounds)
	var origin := _tree_origin()
	var tree := _tree_rect()
	var pan := Vector2(
		tree.get_center().x - origin.x - bounds.get_center().x * zoom,
		tree.position.y + TREE_FIT_PADDING - origin.y - bounds.position.y * zoom
	)
	return {"zoom": zoom, "pan": pan}

func _fit_zoom_for_bounds(bounds: Rect2) -> float:
	var tree := _tree_rect()
	var fit_width := (tree.size.x - TREE_FIT_PADDING * 2.0) / maxf(bounds.size.x, 1.0)
	var fit_height := (tree.size.y - TREE_FIT_PADDING * 2.0) / maxf(bounds.size.y, 1.0)
	return clampf(minf(fit_width, fit_height), 0.05, MAX_ZOOM)

func _min_zoom_for_selected_category() -> float:
	var unlocks := _category_unlocks(_selected_category)
	var bounds := _tree_content_bounds(_layout_unlocks(unlocks), unlocks)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return MAX_ZOOM
	return _fit_zoom_for_bounds(bounds)

func _zoom_tree_by_factor(factor: float, mouse_position: Vector2) -> void:
	var state := _current_view_state()
	var old_zoom: float = state["zoom"]
	var new_zoom: float = clampf(old_zoom * factor, _min_zoom_for_selected_category(), MAX_ZOOM)
	var origin := _tree_origin()
	var pan: Vector2 = state["pan"]
	var world_at_mouse := (mouse_position - origin - pan) / old_zoom
	pan = mouse_position - origin - world_at_mouse * new_zoom
	state["zoom"] = new_zoom
	state["pan"] = pan
	_category_view_state[_selected_category] = state
	queue_redraw()

func _pan_tree(delta: Vector2) -> void:
	var state := _current_view_state()
	state["pan"] = (state["pan"] as Vector2) + delta * PAN_SPEED_MULTIPLIER
	_category_view_state[_selected_category] = state
	queue_redraw()

func _event_inside_panel(event: InputEvent) -> bool:
	if event is InputEventMouse:
		return get_global_rect().has_point((event as InputEventMouse).global_position)
	return get_global_rect().has_point(get_viewport().get_mouse_position())

func _event_local_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return make_canvas_position_local((event as InputEventMouse).position)
	return get_local_mouse_position()

func _close_panel() -> void:
	PanelStack.remove(self)
	hide()

func _knowledge_opportunity_text() -> String:
	var current_turn: int = TurnManager.current_turn
	var opportunity_turns := _knowledge_grants.keys()
	opportunity_turns.sort()
	for opportunity_turn in opportunity_turns:
		var turn: int = opportunity_turn
		if current_turn < turn:
			return "Next International Knowledge Sharing Opportunity in %d turns" % max(0, turn - current_turn)
	return "No further International Knowledge Sharing Opportunities"

func _update_hover_unlock(position: Vector2) -> void:
	var next_hover := ""
	if _choosing_free_unlock:
		next_hover = _unlock_title_at_position(position)
	if next_hover != _hover_unlock_title:
		_hover_unlock_title = next_hover
		queue_redraw()

func _try_choose_free_unlock(position: Vector2) -> bool:
	var title := _unlock_title_at_position(position)
	if title.is_empty():
		return false
	if not MatchState.is_node_available(title):
		return false   # greyed (tier- or prereq-locked) node — can't be free-picked either
	_free_unlocked_titles[title] = true
	MatchState.grant_unlock(title, false)  # free choice — unlocked, but no "Unlocked …" dialog
	_free_unlocks = maxi(0, _free_unlocks - 1)
	_hover_unlock_title = ""
	if _free_unlocks <= 0:
		_choosing_free_unlock = false
	queue_redraw()
	return true

func _unlock_title_at_position(position: Vector2) -> String:
	if not _tree_rect().has_point(position):
		return ""
	var unlocks := _category_unlocks(_selected_category)
	var layout := _layout_unlocks(unlocks)
	var state := _current_view_state()
	var zoom: float = state["zoom"]
	var pan: Vector2 = state["pan"]
	var origin := _tree_origin() + pan
	var world_position := (position - origin) / zoom
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var title: String = unlock["title"]
		if _free_unlocked_titles.has(title):
			continue
		if layout.has(title) and (layout[title] as Rect2).has_point(world_position):
			return title
	return ""

## The requirements row is the card's small disclosure control. Keeping it in the
## custom canvas (rather than adding 235 Buttons) preserves the panel's pan/zoom
## behaviour while making every node expose its full unlock contract on demand.
func _toggle_requirement_dropdown(position: Vector2) -> bool:
	var unlocks := _category_unlocks(_selected_category)
	var layout := _layout_unlocks(unlocks)
	var state := _current_view_state()
	var origin := _tree_origin() + (state["pan"] as Vector2)
	var world_position := (position - origin) / float(state["zoom"])
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var title := str(unlock.get("title", ""))
		if title == "" or not layout.has(title):
			continue
		if _requirement_row_rect(layout[title] as Rect2).has_point(world_position):
			if _expanded_requirement_titles.has(title):
				_expanded_requirement_titles.erase(title)
			else:
				_expanded_requirement_titles[title] = true
			queue_redraw()
			return true
	return false

func _update_profitability_tooltip(position: Vector2) -> void:
	var next_tooltip := ""
	var unlocks := _category_unlocks(_selected_category)
	var layout := _layout_unlocks(unlocks)
	var state := _current_view_state()
	var origin := _tree_origin() + (state["pan"] as Vector2)
	var world_position := (position - origin) / float(state["zoom"])
	for unlock in unlocks:
		if str(unlock.get("action", "")) != "Run Profitable":
			continue
		var title := str(unlock.get("title", ""))
		if title != "" and layout.has(title) and _requirement_row_rect(layout[title] as Rect2).has_point(world_position):
			next_tooltip = "Profitably means its unit cost is lower than the current market price of what it produces."
			break
	if tooltip_text != next_tooltip:
		tooltip_text = next_tooltip

func _select_tab_at(position: Vector2) -> bool:
	for category in CATEGORIES:
		var rect := _tab_rect_for_category(category)
		if rect.has_point(position):
			_selected_category = category
			_category_view_state[_selected_category] = _default_view_state(_selected_category)
			_hover_unlock_title = ""
			queue_redraw()
			return true
	return false

func _tree_origin() -> Vector2:
	var tree := _tree_rect()
	return Vector2(tree.get_center().x, tree.end.y - TREE_FIT_PADDING)

func _tab_rect_for_category(category: String) -> Rect2:
	var index := CATEGORIES.find(category)
	var tab_bar := _tab_bar_rect()
	if index < 0 or tab_bar.size.x <= 0.0:
		return Rect2()
	var tab_width := (tab_bar.size.x - TAB_GAP * float(CATEGORIES.size() - 1)) / float(CATEGORIES.size())
	return Rect2(tab_bar.position + Vector2(float(index) * (tab_width + TAB_GAP), 0.0), Vector2(tab_width, TAB_HEIGHT))

func _draw_tree() -> void:
	var tree := _tree_rect()
	if tree.size.x <= 0.0 or tree.size.y <= 0.0:
		return

	var unlocks := _category_unlocks(_selected_category)
	if unlocks.is_empty():
		return

	var layout := _layout_unlocks(unlocks)
	var layout_bounds := _layout_bounds(layout)
	var state := _current_view_state()
	var zoom: float = state["zoom"]
	var pan: Vector2 = state["pan"]
	var origin := _tree_origin() + pan

	_draw_rank_separators(origin, zoom, unlocks)
	_draw_rank_stamps(origin, zoom, layout, unlocks)
	draw_set_transform(origin, 0.0, Vector2(zoom, zoom))
	_draw_connections(unlocks, layout, zoom)
	for unlock in unlocks:
		var title: String = unlock["title"]
		if layout.has(title):
			_draw_unlock(unlock, layout[title], _unlock_brightness(layout[title], layout_bounds))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The single filter every consumer goes through — layout, hit-testing, zoom bounds and
## drawing all read this — so search hooks in here and the rest follows for free.
##
## With a query active the tab is IGNORED and matches come from EVERY category. That is
## the point: the node you are hunting is usually in a tab you would not have guessed
## (the tutorial asks for High Strength Glassmaking, which is filed under Inorganic
## Chemistry), and a search that only looked in the open tab would not have helped.
## Prereq cables to filtered-out parents simply do not draw — _draw_connections already
## skips a prereq that is not in the layout.
func _category_unlocks(category: String) -> Array[Dictionary]:
	var query := _search_query.strip_edges().to_lower()
	if query != "":
		var hits: Array[Dictionary] = []
		for unlock in _unlock_rows:
			if _unlock_matches(unlock, query):
				hits.append(unlock)
		return hits
	var rows: Array[Dictionary] = [_category_root_unlock(category)]
	for unlock in _unlock_rows:
		if unlock.get("category", "") == category:
			rows.append(unlock)
	return rows


## Name or reward text. The description is where the reward lives ("Increases Concrete
## output by 10% permanently"), so searching "concrete" or "maintenance" finds nodes by
## what they DO, not just what they are called. Category is included too, so typing a
## tab name still gathers that tree.
func _unlock_matches(unlock: Dictionary, query: String) -> bool:
	for key in ["title", "description", "category"]:
		if str(unlock.get(key, "")).to_lower().contains(query):
			return true
	return false

func _category_root_unlock(category: String) -> Dictionary:
	return {
		"category": category,
		"prereq_1": "",
		"prereq_2": "",
		"prereq_3": "",
		"prereq_othercategory": "",
		"rank": "I",
		"action": "",
		"object": "",
		"quantity": "",
		"unit": "",
		"title": category,
		"icon": "",
		"description": "",
		"is_category_root": true,
	}

func _layout_unlocks(unlocks: Array[Dictionary]) -> Dictionary:
	var layout := {}
	var root_title := _selected_category
	layout[root_title] = Rect2(Vector2(-UNLOCK_SIZE.x * 0.5, -TREE_BOTTOM_PADDING - UNLOCK_SIZE.y), UNLOCK_SIZE)
	var occupied := {}
	var placements := {}
	placements[root_title] = {"rank": "I", "row": -1, "column": 0}

	var by_rank := {}
	var dependent_titles: Array[String] = []
	for rank in RANKS:
		by_rank[rank] = []
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var title: String = unlock["title"]
		var rank := _rank_value(unlock)
		if _prereq_titles(unlock).is_empty():
			by_rank[rank].append(title)
		else:
			dependent_titles.append(title)

	var bands := _rank_bands(unlocks)
	for rank in RANKS:
		_layout_rank_unlocks(by_rank[rank], rank, bands[rank], layout, occupied, placements)
	_layout_dependency_unlocks(unlocks, dependent_titles, layout, bands, occupied, placements)
	_compact_rank_columns(unlocks, layout, placements)
	return layout

func _rank_value(unlock: Dictionary) -> String:
	var rank := String(unlock.get("rank", "I")).strip_edges().to_upper()
	return rank if RANKS.has(rank) else "I"

func _rank_bands(unlocks: Array[Dictionary]) -> Dictionary:
	var row_counts := _rank_row_counts(unlocks)
	var bands := {}
	var rank_bottom := -TREE_BOTTOM_PADDING - UNLOCK_SIZE.y - ROOT_TO_RANK_GAP
	for rank in RANKS:
		var row_count: int = row_counts[rank]
		var band_height := UNLOCK_SIZE.y * float(row_count) + RANK_VERTICAL_GAP * float(maxi(0, row_count - 1))
		bands[rank] = {"bottom": rank_bottom, "top": rank_bottom - band_height}
		rank_bottom -= band_height + RANK_SEPARATOR_GAP
	return bands

func _rank_row_counts(unlocks: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for rank in RANKS:
		counts[rank] = 0
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var rank := _rank_value(unlock)
		counts[rank] += 1

	var rows := {}
	for rank in RANKS:
		rows[rank] = clampi(counts[rank], 1, RANK_ROWS_PER_COLUMN)
	return rows

func _layout_rank_unlocks(titles: Array, rank: String, band: Dictionary, layout: Dictionary, occupied: Dictionary, placements: Dictionary) -> void:
	if titles.is_empty():
		return

	var column_count: int = ceili(float(titles.size()) / float(RANK_ROWS_PER_COLUMN))
	var columns := _centered_columns(column_count)
	for index in titles.size():
		var row: int = int(index / column_count)
		var column: int = columns[index % column_count]
		while _grid_occupied(occupied, rank, row, column):
			column += 1
		_place_unlock_at_grid(titles[index], rank, row, column, band, layout, occupied, placements)

func _layout_dependency_unlocks(unlocks: Array[Dictionary], dependent_titles: Array[String], layout: Dictionary, bands: Dictionary, occupied: Dictionary, placements: Dictionary) -> void:
	var by_title := {}
	for unlock in unlocks:
		by_title[unlock.get("title", "")] = unlock

	var remaining := dependent_titles.duplicate()
	var safety: int = max(1, remaining.size() * 2)
	while not remaining.is_empty() and safety > 0:
		safety -= 1
		var placed_this_pass := false
		var index: int = 0
		while index < remaining.size():
			var title: String = remaining[index]
			var unlock: Dictionary = by_title.get(title, {})
			var prereq: String = _first_placed_prereq(unlock, layout)
			if prereq.is_empty():
				index += 1
				continue
			_place_dependency_unlock(title, unlock, prereq, bands, layout, occupied, placements)
			remaining.remove_at(index)
			placed_this_pass = true
		if not placed_this_pass:
			break

	var leftovers_by_rank := {}
	for rank in RANKS:
		leftovers_by_rank[rank] = []
	for title in remaining:
		var unlock: Dictionary = by_title.get(title, {})
		var rank: String = _rank_value(unlock)
		leftovers_by_rank[rank].append(title)
	for rank in RANKS:
		_layout_rank_unlocks(leftovers_by_rank[rank], rank, bands[rank], layout, occupied, placements)

func _first_placed_prereq(unlock: Dictionary, layout: Dictionary) -> String:
	for prereq in _prereq_titles(unlock):
		if layout.has(prereq):
			return prereq
	return ""

func _place_dependency_unlock(title: String, unlock: Dictionary, prereq: String, bands: Dictionary, layout: Dictionary, occupied: Dictionary, placements: Dictionary) -> void:
	var rank: String = _rank_value(unlock)
	var parent_placement: Dictionary = placements.get(prereq, {"rank": rank, "row": -1, "column": 0})
	var start_row: int = 0
	if parent_placement.get("rank", "") == rank:
		start_row = mini(int(parent_placement.get("row", -1)) + 1, RANK_ROWS_PER_COLUMN - 1)
	var parent_column: int = int(parent_placement.get("column", 0))
	var rows := _dependency_rows(start_row)
	var columns := _dependency_columns(parent_column, max(8, occupied.size() + 8))
	for row in rows:
		for column in columns:
			if not _grid_occupied(occupied, rank, row, column):
				_place_unlock_at_grid(title, rank, row, column, bands[rank], layout, occupied, placements)
				return

	var fallback_column: int = parent_column
	while _grid_occupied(occupied, rank, RANK_ROWS_PER_COLUMN - 1, fallback_column):
		fallback_column += 1
	_place_unlock_at_grid(title, rank, RANK_ROWS_PER_COLUMN - 1, fallback_column, bands[rank], layout, occupied, placements)

func _dependency_rows(preferred_row: int) -> Array[int]:
	var rows: Array[int] = [clampi(preferred_row, 0, RANK_ROWS_PER_COLUMN - 1)]
	for row in RANK_ROWS_PER_COLUMN:
		if not rows.has(row):
			rows.append(row)
	return rows

func _dependency_columns(parent_column: int, distance_limit: int) -> Array[int]:
	var columns: Array[int] = [parent_column]
	for distance in range(1, distance_limit + 1):
		columns.append(parent_column - distance)
		columns.append(parent_column + distance)
	return columns

func _centered_columns(column_count: int) -> Array[int]:
	var columns: Array[int] = []
	if column_count <= 0:
		return columns
	var start: int = -int(floor(float(column_count - 1) * 0.5))
	for index in column_count:
		columns.append(start + index)
	return columns

func _rank_wide_column(slot: int) -> int:
	return _centered_columns(maxi(slot + 1, 1))[slot]

func _place_unlock_at_grid(title: String, rank: String, row: int, column: int, band: Dictionary, layout: Dictionary, occupied: Dictionary, placements: Dictionary) -> void:
	var row_step := UNLOCK_SIZE.y + RANK_VERTICAL_GAP
	var band_bottom: float = band["bottom"]
	var bottom_y := band_bottom - float(row) * row_step
	var center_x := float(column) * UNLOCK_LANE_GAP
	layout[title] = Rect2(Vector2(center_x - UNLOCK_SIZE.x * 0.5, bottom_y - UNLOCK_SIZE.y), UNLOCK_SIZE)
	occupied[_grid_key(rank, row, column)] = true
	placements[title] = {"rank": rank, "row": row, "column": column}

func _grid_occupied(occupied: Dictionary, rank: String, row: int, column: int) -> bool:
	return occupied.has(_grid_key(rank, row, column))

func _grid_key(rank: String, row: int, column: int) -> String:
	return "%s:%d:%d" % [rank, row, column]

func _rank_wide_column_offset(slot: int) -> float:
	return float(_rank_wide_column(slot)) * UNLOCK_LANE_GAP

func _compact_rank_columns(unlocks: Array[Dictionary], layout: Dictionary, placements: Dictionary) -> void:
	for rank in RANKS:
		var columns: Array[int] = []
		var titles: Array[String] = []
		for unlock in unlocks:
			if bool(unlock.get("is_category_root", false)):
				continue
			if _rank_value(unlock) != rank:
				continue
			var title: String = unlock["title"]
			if not placements.has(title) or not layout.has(title):
				continue
			var placement: Dictionary = placements[title]
			var column: int = int(placement.get("column", 0))
			if not columns.has(column):
				columns.append(column)
			titles.append(title)
		columns.sort()
		if columns.is_empty():
			continue

		var compact_columns := _centered_columns(columns.size())
		var column_map := {}
		for index in columns.size():
			column_map[columns[index]] = compact_columns[index]

		for title in titles:
			var placement: Dictionary = placements[title]
			var original_column: int = int(placement.get("column", 0))
			var compact_column: int = int(column_map.get(original_column, original_column))
			var rect: Rect2 = layout[title]
			rect.position.x = float(compact_column) * UNLOCK_LANE_GAP - UNLOCK_SIZE.x * 0.5
			layout[title] = rect
			placement["column"] = compact_column
			placements[title] = placement

func _layout_bounds(layout: Dictionary) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for title in layout:
		var rect: Rect2 = layout[title]
		if has_bounds:
			bounds = bounds.merge(rect)
		else:
			bounds = rect
			has_bounds = true
	return bounds

func _tree_content_bounds(layout: Dictionary, unlocks: Array[Dictionary]) -> Rect2:
	var bounds := _layout_bounds(layout)
	for rect in _rank_stamp_world_rects(layout, unlocks).values():
		bounds = bounds.merge(rect)
	return bounds

func _rank_stamp_world_rects(layout: Dictionary, unlocks: Array[Dictionary]) -> Dictionary:
	var stamp_rects := {}
	if layout.is_empty():
		return stamp_rects

	var leftmost := INF
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var title: String = unlock["title"]
		if layout.has(title):
			var rect: Rect2 = layout[title]
			leftmost = minf(leftmost, rect.position.x)

	if is_inf(leftmost):
		leftmost = _layout_bounds(layout).position.x

	var x := leftmost - RANK_STAMP_OFFSET_FROM_UNLOCK - RANK_STAMP_SIZE.x
	var bands := _rank_bands(unlocks)
	for rank in RANKS:
		var band: Dictionary = bands[rank]
		var center_y := (float(band["top"]) + float(band["bottom"])) * 0.5
		stamp_rects[rank] = Rect2(Vector2(x, center_y - RANK_STAMP_SIZE.y * 0.5), RANK_STAMP_SIZE)
	return stamp_rects

func _find_unlock(unlocks: Array[Dictionary], title: String) -> Dictionary:
	for unlock in unlocks:
		if unlock.get("title", "") == title:
			return unlock
	return {}

## Prereq columns store research_node_ids, but this panel's layout/graph is keyed by
## display title, so resolve on the way out. Anything that doesn't resolve is passed
## through unchanged (bare cheat tokens like "hydro" have no node).
func _prereq_titles(unlock: Dictionary) -> Array[String]:
	var titles: Array[String] = []
	for key in ["prereq_1", "prereq_2", "prereq_3"]:
		var value: String = unlock.get(key, "")
		if value.is_empty():
			continue
		var resolved := MatchState.research_title_for_node_id(value)
		titles.append(resolved if resolved != "" else value)
	return titles

func _draw_connections(unlocks: Array[Dictionary], layout: Dictionary, zoom: float) -> void:
	var cable_width := CABLE_WIDTH_AT_MAX_ZOOM / MAX_ZOOM
	var stripe_width := CABLE_STRIPE_WIDTH_AT_MAX_ZOOM / MAX_ZOOM
	for unlock in unlocks:
		if bool(unlock.get("is_category_root", false)):
			continue
		var title: String = unlock["title"]
		if not layout.has(title):
			continue
		var child_rect: Rect2 = layout[title]
		var prereqs := _prereq_titles(unlock)
		if prereqs.is_empty():
			continue
		else:
			for prereq in prereqs:
				if not layout.has(prereq):
					continue
				var parent_rect: Rect2 = layout[prereq]
				_draw_cable_between_unlocks(parent_rect, child_rect, layout, cable_width, stripe_width)

func _draw_rank_separators(origin: Vector2, zoom: float, unlocks: Array[Dictionary]) -> void:
	var bands := _rank_bands(unlocks)
	for index in range(0, RANKS.size() - 1):
		var lower_band: Dictionary = bands[RANKS[index]]
		var separator_y: float = origin.y + (float(lower_band["top"]) - RANK_SEPARATOR_GAP * 0.5) * zoom
		_draw_rank_separator(separator_y)

func _draw_rank_separator(y: float) -> void:
	var tree := _tree_rect()
	if y < tree.position.y - 12.0 or y > tree.end.y + 12.0:
		return

	var body := _body_rect()
	var left := body.position.x + 40.0
	var right := body.end.x - 40.0
	var point := 18.0
	var half_height := 2.5
	var shadow := Color(0.0, 0.0, 0.0, 0.25)
	var dark_metal: Color = DS.PALETTE["BORDER"]
	var bright_metal: Color = DS.PALETTE["ACCENT"]
	var points := PackedVector2Array([
		Vector2(left, y),
		Vector2(left + point, y - half_height),
		Vector2(right - point, y - half_height),
		Vector2(right, y),
		Vector2(right - point, y + half_height),
		Vector2(left + point, y + half_height),
	])
	var shadow_points := PackedVector2Array()
	for point_position in points:
		shadow_points.append(point_position + Vector2(0.0, 1.5))
	draw_polygon(shadow_points, PackedColorArray([shadow, shadow, shadow, shadow, shadow, shadow]))
	draw_polygon(points, PackedColorArray([dark_metal, bright_metal, bright_metal, dark_metal, dark_metal, bright_metal]))

func _draw_rank_stamps(origin: Vector2, zoom: float, layout: Dictionary, unlocks: Array[Dictionary]) -> void:
	var tree := _tree_rect()
	var stamp_rects := _rank_stamp_world_rects(layout, unlocks)
	for rank in RANKS:
		if not stamp_rects.has(rank):
			continue
		var world_rect: Rect2 = stamp_rects[rank]
		var rect := Rect2(origin + world_rect.position * zoom, world_rect.size * zoom)
		if rect.end.x < tree.position.x or rect.position.x > tree.end.x or rect.end.y < tree.position.y or rect.position.y > tree.end.y:
			continue
		_draw_rank_stamp(rank, rect, zoom)

func _draw_rank_stamp(rank: String, rect: Rect2, zoom: float) -> void:
	var fill := _rank_stamp_color(rank)
	var outline_dark := Color(0.34, 0.36, 0.37, 0.78)
	var outline_light := Color(0.74, 0.77, 0.78, 0.74)
	var outline := maxf(2.0, RANK_STAMP_OUTLINE * zoom)
	var corner_radius := maxf(3.0, RANK_STAMP_CORNER_RADIUS * zoom)
	var outer := _rounded_hex_points(rect, corner_radius)
	var inner := _rounded_hex_points(rect.grow(-outline), maxf(2.0, corner_radius - outline * 0.35))
	var shadow_points := PackedVector2Array()
	for point in outer:
		shadow_points.append(point + Vector2(0.0, 2.0 * zoom))

	draw_polygon(shadow_points, _solid_colors(shadow_points.size(), Color(0, 0, 0, 0.22)))
	draw_polygon(outer, _hex_gradient_colors(outer, outline_light, outline_dark))
	draw_polygon(inner, _hex_gradient_colors(inner, fill.lightened(0.10), fill.darkened(0.18)))

	var edge_width := maxf(1.0, 1.8 * zoom)
	_draw_rounded_edge_lighting(outer, rect, edge_width, Color(1.0, 1.0, 1.0, 0.20), Color(0.0, 0.0, 0.0, 0.24))
	_draw_rounded_edge_lighting(inner, rect.grow(-outline), edge_width, Color(1.0, 1.0, 1.0, 0.14), Color(0.0, 0.0, 0.0, 0.18))

	var text_rect := rect.grow(-outline - 8.0 * zoom)
	var text_color := _with_alpha(DS.PALETTE["ACCENT"], 0.88)
	_draw_debossed_text_fit(_stamp_font, rank, text_rect, maxi(18, int(round(float(RANK_STAMP_FONT_SIZE) * zoom))), text_color, zoom)

func _rank_stamp_color(rank: String) -> Color:
	return _rank_shared_color(rank)

func _rank_shared_color(rank: String) -> Color:
	match rank:
		"I":
			return Color(0.62, 0.25, 0.16, 0.58)
		"II":
			return Color(0.62, 0.66, 0.67, 0.58)
		"III":
			return Color(0.78, 0.57, 0.18, 0.58)
		_:
			return Color(0.58, 0.39, 0.20, 0.58)

func _hex_points(rect: Rect2) -> PackedVector2Array:
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	var middle_y := rect.get_center().y
	var bevel := rect.size.x * 0.22
	return PackedVector2Array([
		Vector2(left + bevel, top),
		Vector2(right - bevel, top),
		Vector2(right, middle_y),
		Vector2(right - bevel, bottom),
		Vector2(left + bevel, bottom),
		Vector2(left, middle_y),
	])

func _rounded_hex_points(rect: Rect2, corner_radius: float) -> PackedVector2Array:
	return _rounded_polygon_points(_hex_points(rect), corner_radius)

func _rounded_polygon_points(vertices: PackedVector2Array, corner_radius: float) -> PackedVector2Array:
	if vertices.size() < 3:
		return vertices

	var points := PackedVector2Array()
	for index in vertices.size():
		var current := vertices[index]
		var previous := vertices[(index - 1 + vertices.size()) % vertices.size()]
		var next := vertices[(index + 1) % vertices.size()]
		var radius := minf(corner_radius, minf(current.distance_to(previous), current.distance_to(next)) * 0.42)
		var from_point := current + (previous - current).normalized() * radius
		var to_point := current + (next - current).normalized() * radius
		for step in 5:
			var t := float(step) / 4.0
			var a := from_point.lerp(current, t)
			var b := current.lerp(to_point, t)
			points.append(a.lerp(b, t))
	return points

func _draw_rounded_edge_lighting(points: PackedVector2Array, rect: Rect2, width: float, light_color: Color, shadow_color: Color) -> void:
	if points.size() < 2:
		return

	var center_sum := rect.get_center().x + rect.get_center().y
	for index in points.size():
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var mid := (start + end) * 0.5
		var color := light_color if mid.x + mid.y <= center_sum else shadow_color
		draw_line(start, end, color, width, true)

func _solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for index in count:
		colors.append(color)
	return colors

func _hex_gradient_colors(points: PackedVector2Array, light_color: Color, dark_color: Color) -> PackedColorArray:
	var bounds := Rect2()
	var has_bounds := false
	for point in points:
		if has_bounds:
			bounds = bounds.expand(point)
		else:
			bounds = Rect2(point, Vector2.ZERO)
			has_bounds = true

	var colors := PackedColorArray()
	var denominator := maxf(bounds.size.x + bounds.size.y, 1.0)
	for point in points:
		var ratio := clampf(((point.x - bounds.position.x) + (point.y - bounds.position.y)) / denominator, 0.0, 1.0)
		colors.append(light_color.lerp(dark_color, ratio))
	return colors

func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func _draw_cable_between_unlocks(parent_rect: Rect2, child_rect: Rect2, layout: Dictionary, cable_width: float, stripe_width: float) -> void:
	var start_edge := Vector2(parent_rect.get_center().x, parent_rect.position.y)
	var end_edge := Vector2(child_rect.get_center().x, child_rect.end.y)
	var start_normal := Vector2.UP
	var end_normal := Vector2.DOWN
	var start := _cable_inner_endpoint(start_edge, start_normal)
	var end := _cable_inner_endpoint(end_edge, end_normal)
	var start_lead := start + start_normal * CABLE_CONNECTOR_LEAD
	var end_lead := end + end_normal * CABLE_CONNECTOR_LEAD
	var route := _direct_cable_route(start_lead, end_lead, start_normal, end_normal)
	if _route_hits_unlock(route, layout, parent_rect, child_rect, cable_width):
		route = _outside_cable_route(start_lead, end_lead, layout)
	route = _clean_route_points([start] + route + [end])

	var points := _rounded_route_points(route, CABLE_BEND_RADIUS)
	draw_polyline(points, Color(0.01, 0.011, 0.012, 0.95), cable_width + 2.0, true)
	draw_polyline(points, Color(0.05, 0.045, 0.035, 1.0), cable_width, true)
	draw_polyline(points, Color(0.92, 0.68, 0.14, 0.95), stripe_width, true)
	_draw_copper_connector(start_edge, start_normal)
	_draw_copper_connector(end_edge, end_normal)

func _cable_inner_endpoint(edge_point: Vector2, normal: Vector2) -> Vector2:
	return edge_point + normal * (CABLE_CONNECTOR_SIZE.y * 0.5 + 2.0)

func _direct_cable_route(start: Vector2, end: Vector2, start_normal: Vector2, end_normal: Vector2) -> Array:
	if is_equal_approx(start.x, end.x) or is_equal_approx(start.y, end.y):
		return _clean_route_points([start, end])

	if absf(start_normal.y) > 0.0 or absf(end_normal.y) > 0.0:
		var route_y := (start.y + end.y) * 0.5
		return _clean_route_points([start, Vector2(start.x, route_y), Vector2(end.x, route_y), end])

	var route_x := (start.x + end.x) * 0.5
	return _clean_route_points([start, Vector2(route_x, start.y), Vector2(route_x, end.y), end])

func _outside_cable_route(start: Vector2, end: Vector2, layout: Dictionary) -> Array:
	var bounds := _layout_bounds(layout)
	var average_x := (start.x + end.x) * 0.5
	var route_x := bounds.position.x - CABLE_ROUTE_MARGIN
	if average_x > bounds.get_center().x:
		route_x = bounds.end.x + CABLE_ROUTE_MARGIN
	return _clean_route_points([start, Vector2(route_x, start.y), Vector2(route_x, end.y), end])

func _clean_route_points(route: Array) -> Array:
	var cleaned := []
	for point in route:
		var point_position: Vector2 = point
		if cleaned.is_empty() or point_position.distance_squared_to(cleaned[cleaned.size() - 1]) > 0.01:
			cleaned.append(point_position)

	var index := 1
	while index < cleaned.size() - 1:
		var previous: Vector2 = cleaned[index - 1]
		var current: Vector2 = cleaned[index]
		var next: Vector2 = cleaned[index + 1]
		var same_x := is_equal_approx(previous.x, current.x) and is_equal_approx(current.x, next.x)
		var same_y := is_equal_approx(previous.y, current.y) and is_equal_approx(current.y, next.y)
		if same_x or same_y:
			cleaned.remove_at(index)
		else:
			index += 1
	return cleaned

func _rounded_route_points(route: Array, bend_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if route.size() <= 2:
		for point in route:
			points.append(point as Vector2)
		return points

	points.append(route[0] as Vector2)
	for index in range(1, route.size() - 1):
		var previous: Vector2 = route[index - 1]
		var current: Vector2 = route[index]
		var next: Vector2 = route[index + 1]
		var radius := minf(bend_radius, minf(current.distance_to(previous), current.distance_to(next)) * 0.45)
		var before := current + (previous - current).normalized() * radius
		var after := current + (next - current).normalized() * radius
		if points[points.size() - 1].distance_squared_to(before) > 0.01:
			points.append(before)
		for step in range(1, 6):
			var t := float(step) / 6.0
			var a := before.lerp(current, t)
			var b := current.lerp(after, t)
			points.append(a.lerp(b, t))
	points.append(route[route.size() - 1] as Vector2)
	return points

func _route_hits_unlock(route: Array, layout: Dictionary, parent_rect: Rect2, child_rect: Rect2, cable_width: float) -> bool:
	for index in range(0, route.size() - 1):
		var start: Vector2 = route[index]
		var end: Vector2 = route[index + 1]
		for rect in layout.values():
			var obstacle: Rect2 = rect
			if _same_rect(obstacle, parent_rect) or _same_rect(obstacle, child_rect):
				continue
			if _axis_segment_intersects_rect(start, end, obstacle.grow(cable_width * 0.5 + 8.0)):
				return true
	return false

func _axis_segment_intersects_rect(start: Vector2, end: Vector2, rect: Rect2) -> bool:
	if is_equal_approx(start.x, end.x):
		var low_y := minf(start.y, end.y)
		var high_y := maxf(start.y, end.y)
		return start.x >= rect.position.x and start.x <= rect.end.x and maxf(low_y, rect.position.y) <= minf(high_y, rect.end.y)
	if is_equal_approx(start.y, end.y):
		var low_x := minf(start.x, end.x)
		var high_x := maxf(start.x, end.x)
		return start.y >= rect.position.y and start.y <= rect.end.y and maxf(low_x, rect.position.x) <= minf(high_x, rect.end.x)

	for step in range(0, 9):
		var point := start.lerp(end, float(step) / 8.0)
		if rect.has_point(point):
			return true
	return false

func _same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_squared_to(b.position) <= 0.01 and a.size.distance_squared_to(b.size) <= 0.01

func _draw_copper_connector(center: Vector2, normal: Vector2) -> void:
	var connector_size := CABLE_CONNECTOR_SIZE if absf(normal.y) > 0.0 else Vector2(CABLE_CONNECTOR_SIZE.y, CABLE_CONNECTOR_SIZE.x)
	var rect := Rect2(center - connector_size * 0.5, connector_size)
	var outline := rect.grow(2.0)
	draw_polygon(
		PackedVector2Array([
			outline.position,
			Vector2(outline.end.x, outline.position.y),
			outline.end,
			Vector2(outline.position.x, outline.end.y),
		]),
		PackedColorArray([
			Color(0.18, 0.10, 0.05, 1.0),
			Color(0.38, 0.22, 0.08, 1.0),
			Color(0.12, 0.07, 0.04, 1.0),
			Color(0.28, 0.15, 0.06, 1.0),
		])
	)
	draw_polygon(
		PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]),
		PackedColorArray([
			Color(0.93, 0.50, 0.20, 1.0),
			Color(0.68, 0.32, 0.12, 1.0),
			Color(0.34, 0.16, 0.07, 1.0),
			Color(0.62, 0.28, 0.10, 1.0),
		])
	)
	draw_line(rect.position + Vector2(3.0, 3.0), Vector2(rect.end.x - 3.0, rect.position.y + 3.0), Color(1.0, 0.75, 0.36, 0.55), 1.4, true)
	draw_line(Vector2(rect.position.x + 3.0, rect.end.y - 3.0), rect.end - Vector2(3.0, 3.0), Color(0.08, 0.04, 0.02, 0.44), 1.4, true)

func _unlock_brightness(rect: Rect2, bounds: Rect2) -> float:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return 0.0
	var center := rect.get_center()
	var x_ratio := clampf((center.x - bounds.position.x) / bounds.size.x, 0.0, 1.0)
	var y_ratio := clampf((center.y - bounds.position.y) / bounds.size.y, 0.0, 1.0)
	var zone := (x_ratio + y_ratio) * 0.5
	if zone < 1.0 / 3.0:
		return 0.08
	if zone > 2.0 / 3.0:
		return -0.08
	return 0.0

func _draw_unlock(unlock: Dictionary, rect: Rect2, brightness: float) -> void:
	var title: String = unlock["title"]
	var is_root := bool(unlock.get("is_category_root", false))
	var free_unlocked := _free_unlocked_titles.has(title) or MatchState.is_unlocked(title)
	var locked := not free_unlocked and not is_root and not MatchState.is_node_available(title)
	var hovered_for_free := _choosing_free_unlock and _hover_unlock_title == title and not free_unlocked and not is_root and not locked
	_draw_unlock_shell(rect, brightness, unlock, free_unlocked, hovered_for_free, locked)
	_draw_unlock_rivets(rect, brightness)
	if is_root:
		_draw_unlock_title_text(TITLE_FONT, unlock["title"], rect.grow(-16.0), UNLOCK_TITLE_SIZE)
		return

	var title_rect := Rect2(rect.position + Vector2(12.0, 10.0), Vector2(rect.size.x - 24.0, 28.0))
	_draw_unlock_title_text(TITLE_FONT, unlock["title"], title_rect, UNLOCK_TITLE_SIZE)

	var slot_rect := Rect2(rect.position + Vector2(14.0, 44.0), Vector2(UNLOCK_SLOT_SIZE, UNLOCK_SLOT_SIZE))
	draw_style_box(_unlock_slot_style, slot_rect)
	_draw_text_fit(BODY_FONT, unlock.get("icon", ""), slot_rect.grow(-8.0), 15, DS.PALETTE["ACCENT"], HORIZONTAL_ALIGNMENT_CENTER)

	var desc_rect := Rect2(rect.position + Vector2(106.0, 44.0), Vector2(rect.size.x - 120.0, UNLOCK_SLOT_SIZE))
	draw_style_box(_description_style, desc_rect)
	_draw_wrapped_lines(BODY_FONT, unlock["description"], desc_rect.grow(-7.0), UNLOCK_DESC_SIZE, DS.PALETTE["TEXT_MUTED"], 4)

	var requirement_rect := _requirement_row_rect(rect)
	var expanded := _expanded_requirement_titles.has(title)
	draw_style_box(_condition_style, requirement_rect)
	var summary := "Unlocked" if free_unlocked else (_lock_reason(unlock) if locked else _condition_text(unlock))
	_draw_wrapped_lines(BODY_FONT, summary, requirement_rect.grow_individual(-7.0, -5.0, -26.0, -5.0), UNLOCK_CONDITION_SIZE, DS.PALETTE["TEXT_MUTED"] if locked else DS.PALETTE["ACCENT"], 2, HORIZONTAL_ALIGNMENT_CENTER, true)
	_draw_requirement_caret(requirement_rect, expanded, DS.PALETTE["ACCENT"] if not locked else DS.PALETTE["TEXT_MUTED"])
	if expanded:
		var details_rect := Rect2(rect.position + Vector2(14.0, 186.0), Vector2(rect.size.x - 28.0, rect.size.y - 200.0))
		draw_style_box(_description_style, details_rect)
		_draw_wrapped_lines(BODY_FONT, _requirement_details(unlock), details_rect.grow( -7.0), UNLOCK_CONDITION_SIZE, DS.PALETTE["TEXT_MUTED"], 5, HORIZONTAL_ALIGNMENT_LEFT, true)

func _requirement_row_rect(card_rect: Rect2) -> Rect2:
	return Rect2(card_rect.position + Vector2(14.0, 142.0), Vector2(card_rect.size.x - 28.0, 38.0))

func _draw_requirement_caret(rect: Rect2, expanded: bool, color: Color) -> void:
	var center := Vector2(rect.end.x - 15.0, rect.get_center().y)
	var points := PackedVector2Array([
		center + (Vector2(-4.0, 2.0) if expanded else Vector2(-2.0, -4.0)),
		center + (Vector2(4.0, 2.0) if expanded else Vector2(-2.0, 4.0)),
		center + (Vector2(0.0, -3.0) if expanded else Vector2(4.0, 0.0)),
	])
	draw_colored_polygon(points, color)

func _requirement_details(unlock: Dictionary) -> String:
	var lines: Array[String] = []
	var condition := _condition_text(unlock)
	if condition != "":
		lines.append("Requirement: %s" % condition)
	var prereqs := _prereq_titles(unlock)
	if prereqs.is_empty():
		lines.append("Prerequisites: none")
	else:
		lines.append("Prerequisites: %s" % _join_condition_parts(prereqs))
	var rank := _rank_value(unlock)
	if rank == "I":
		lines.append("Tier I: available from the start")
	else:
		var previous: String = str(RANKS[maxi(0, RANKS.find(rank) - 1)])
		var category := str(unlock.get("category", ""))
		var prior_tier_nodes := 0
		for node in _unlock_rows:
			if str(node.get("category", "")) == category and _rank_value(node) == previous:
				prior_tier_nodes += 1
		var required_nodes := mini(3, prior_tier_nodes)
		lines.append("Tier %s: unlock %d Tier %s node%s in %s" % [rank, required_nodes, previous, "" if required_nodes == 1 else "s", category])
	return "\n".join(lines)

func _draw_unlock_shell(rect: Rect2, brightness: float, unlock: Dictionary, free_unlocked: bool, hovered_for_free: bool, locked: bool = false) -> void:
	_draw_unlock_shadow(rect, brightness)
	if hovered_for_free:
		for index in 3:
			var glow_rect := rect.grow(5.0 + float(index) * 4.0)
			var glow_style := StyleBoxFlat.new()
			glow_style.bg_color = Color(0.75, 0.95, 1.0, 0.08 - float(index) * 0.018)
			glow_style.corner_radius_top_left = UNLOCK_RADIUS + 6
			glow_style.corner_radius_top_right = UNLOCK_RADIUS + 6
			glow_style.corner_radius_bottom_right = UNLOCK_RADIUS + 6
			glow_style.corner_radius_bottom_left = UNLOCK_RADIUS + 6
			draw_style_box(glow_style, glow_rect)

	var base_color := DS.PALETTE["BG_INSET"]
	var border_color := DS.PALETTE["BORDER_SOFT"]
	if free_unlocked:
		base_color = _rank_plate_color(_rank_value(unlock))
		border_color = base_color.lightened(0.20)
	elif locked:
		base_color = DS.PALETTE["BG_INSET"].darkened(0.45)
		border_color = DS.PALETTE["BORDER_SOFT"].darkened(0.35)
	var style := _make_stylebox(_shade_color(base_color, brightness + (0.10 if hovered_for_free else 0.0)), _shade_color(border_color, brightness), UNLOCK_RADIUS, 2)
	draw_style_box(style, rect)
	_draw_machined_bevel(rect, brightness)
	var bevel_rect := rect.grow(-UNLOCK_BEVEL_SIZE)
	draw_polygon(
		PackedVector2Array([
			bevel_rect.position,
			Vector2(bevel_rect.end.x, bevel_rect.position.y),
			bevel_rect.end,
			Vector2(bevel_rect.position.x, bevel_rect.end.y),
		]),
		PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.12 + maxf(brightness, 0.0)),
			Color(1.0, 1.0, 1.0, 0.04),
			Color(0.0, 0.0, 0.0, 0.16 + maxf(-brightness, 0.0)),
			Color(1.0, 1.0, 1.0, 0.03),
		])
	)

## Why a node is greyed out — shown on its card in place of the unlock condition.
func _lock_reason(unlock: Dictionary) -> String:
	var rank := _rank_value(unlock)
	var category := String(unlock.get("category", ""))
	if not MatchState.is_tier_available(category, rank):
		var prev_i: int = maxi(0, RANKS.find(rank) - 1)
		return "Locked — unlock more Tier %s research first" % RANKS[prev_i]
	for p in _prereq_titles(unlock):
		if not MatchState.is_unlocked(str(p)):
			return "Requires: %s" % str(p)
	return "Locked"

func _rank_plate_color(rank: String) -> Color:
	return _rank_shared_color(rank)

func _draw_unlock_title_text(font: Font, text: String, rect: Rect2, font_size: int) -> void:
	var fitted_size := _fitted_font_size(font, text, rect.size.x, font_size)
	var position := _text_baseline_position(font, text, rect, fitted_size)
	var shadow_offset := Vector2(UNLOCK_TITLE_SHADOW_OFFSET, UNLOCK_TITLE_SHADOW_OFFSET)
	draw_string(font, position + shadow_offset, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, Color(0.0, 0.0, 0.0, 0.42))
	draw_string(font, position + Vector2(-1.0, -1.0), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, Color(1.0, 1.0, 1.0, 0.12))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, DS.PALETTE["TEXT"])

func _draw_free_unlock_bar(rect: Rect2) -> void:
	var style := _make_stylebox(Color(0.02, 0.22, 0.08, 1.0), Color(0.46, 0.86, 0.30, 1.0), 8, 1)
	draw_style_box(style, rect)
	draw_polygon(
		PackedVector2Array([
			rect.position + Vector2(2.0, 2.0),
			Vector2(rect.end.x - 2.0, rect.position.y + 2.0),
			rect.end - Vector2(2.0, 2.0),
			Vector2(rect.position.x + 2.0, rect.end.y - 2.0),
		]),
		PackedColorArray([
			Color(0.45, 0.95, 0.32, 0.85),
			Color(0.22, 0.70, 0.18, 0.85),
			Color(0.03, 0.30, 0.08, 0.92),
			Color(0.12, 0.55, 0.12, 0.88),
		])
	)

func _draw_unlock_shadow(rect: Rect2, brightness: float) -> void:
	var shadow_alpha := 0.20 + maxf(-brightness, 0.0) * 0.7
	for index in 3:
		var offset := Vector2(3.0 + float(index) * 2.0, 4.0 + float(index) * 2.0)
		var shadow_style := StyleBoxFlat.new()
		shadow_style.bg_color = Color(0.0, 0.0, 0.0, shadow_alpha * (0.55 - float(index) * 0.13))
		shadow_style.corner_radius_top_left = UNLOCK_RADIUS
		shadow_style.corner_radius_top_right = UNLOCK_RADIUS
		shadow_style.corner_radius_bottom_right = UNLOCK_RADIUS
		shadow_style.corner_radius_bottom_left = UNLOCK_RADIUS
		draw_style_box(shadow_style, Rect2(rect.position + offset, rect.size))

func _draw_machined_bevel(rect: Rect2, brightness: float) -> void:
	var bevel := UNLOCK_BEVEL_SIZE
	var inner := rect.grow(-bevel)
	var top_light := _shade_color(Color(1.0, 1.0, 1.0, 0.18), brightness)
	var left_light := _shade_color(Color(1.0, 1.0, 1.0, 0.12), brightness)
	var right_shadow := Color(0.0, 0.0, 0.0, 0.22 + maxf(-brightness, 0.0))
	var bottom_shadow := Color(0.0, 0.0, 0.0, 0.30 + maxf(-brightness, 0.0))
	var mid := Color(0.55, 0.58, 0.60, 0.10)

	draw_polygon(PackedVector2Array([
		rect.position + Vector2(bevel, 0.0),
		Vector2(rect.end.x - bevel, rect.position.y),
		Vector2(inner.end.x, inner.position.y),
		inner.position,
	]), PackedColorArray([top_light, top_light, mid, mid]))
	draw_polygon(PackedVector2Array([
		rect.position + Vector2(0.0, bevel),
		inner.position,
		Vector2(inner.position.x, inner.end.y),
		Vector2(rect.position.x, rect.end.y - bevel),
	]), PackedColorArray([left_light, mid, mid, left_light]))
	draw_polygon(PackedVector2Array([
		Vector2(rect.end.x, rect.position.y + bevel),
		Vector2(rect.end.x, rect.end.y - bevel),
		Vector2(inner.end.x, inner.end.y),
		Vector2(inner.end.x, inner.position.y),
	]), PackedColorArray([right_shadow, right_shadow, mid, mid]))
	draw_polygon(PackedVector2Array([
		Vector2(rect.position.x + bevel, rect.end.y),
		Vector2(inner.position.x, inner.end.y),
		inner.end,
		Vector2(rect.end.x - bevel, rect.end.y),
	]), PackedColorArray([bottom_shadow, mid, mid, bottom_shadow]))

func _draw_unlock_rivets(rect: Rect2, brightness: float) -> void:
	var centers := [
		rect.position + Vector2(12.0, 12.0),
		Vector2(rect.end.x - 12.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 12.0, rect.end.y - 12.0),
		rect.end - Vector2(12.0, 12.0),
	]
	var radius := 4.0
	var rivet_color := _shade_color(Color(0.58, 0.61, 0.62, 1.0), brightness)
	var cross_color := Color(0.23, 0.25, 0.27, 1.0)
	for center in centers:
		draw_circle(center, radius, rivet_color)
		draw_circle(center + Vector2(-1.1, -1.1), radius * 0.45, Color(1.0, 1.0, 1.0, 0.16))
		draw_line(center + Vector2(-2.4, 0.0), center + Vector2(2.4, 0.0), cross_color, 1.2, true)
		draw_line(center + Vector2(0.0, -2.4), center + Vector2(0.0, 2.4), cross_color, 1.2, true)

func _shade_color(color: Color, brightness: float) -> Color:
	if brightness > 0.0:
		return color.lightened(brightness)
	if brightness < 0.0:
		return color.darkened(absf(brightness))
	return color

func _condition_text(unlock: Dictionary) -> String:
	var action := String(unlock.get("action", "")).strip_edges()
	# Spare/unused nodes carry a "Placeholder" sentinel instead of a real condition.
	if action == "Placeholder":
		return "No activity requirement"
	var object_name := String(unlock.get("object", "")).strip_edges()
	var quantity := String(unlock.get("quantity", "")).strip_edges()
	var unit := String(unlock.get("unit", "")).strip_edges()
	if action.is_empty() or object_name.is_empty() or quantity.is_empty() or unit.is_empty():
		return ""
	if action == "Produce All":
		var goods := object_name.split("|", false)
		var quantities := quantity.split("|", false)
		if goods.size() == quantities.size() and not goods.is_empty():
			var parts: Array = []
			for index in goods.size():
				parts.append("%s %s" % [str(quantities[index]), str(goods[index]).capitalize()])
			return "Produce %s" % _join_condition_parts(parts)
	match action:
		"Produce": return "Produce %s %s" % [quantity, object_name.capitalize()]
		"Sell": return "Sell %s units through the market" % quantity if object_name.to_lower() == "freight" else "Sell %s %s through the market" % [quantity, object_name.capitalize()]
		"Build": return "Build %s %s" % [quantity, object_name.capitalize()]
		"Own": return "Own %s land plots" % quantity if object_name.to_lower() == "land" else "Own %s %s" % [quantity, object_name.capitalize()]
		"Run":
			var run_turns := _leading_condition_int(unit, 0)
			return "Operate at least %s %s at full capacity for %s consecutive turns" % [quantity, _condition_building_label(object_name, int(quantity)), run_turns] if run_turns > 0 else "Operate %s at full capacity for %s consecutive turns" % [object_name, quantity]
		"Run L1": return "Operate %s Level 1 %s at full capacity for %s" % [quantity, object_name.capitalize(), unit]
		"Run Profitable":
			var profitable_turns := _leading_condition_int(unit, 0)
			return "Operate at least %s %s profitably for %s consecutive turns" % [quantity, _condition_building_label(object_name, int(quantity)), profitable_turns] if profitable_turns > 0 else "Operate %s %s profitably" % [quantity, _condition_building_label(object_name, int(quantity))]
		"Run Profitable L2": return "Operate %s Level 2 %s profitably" % [quantity, object_name.capitalize()]
		"Run Multiple": return _run_multiple_condition_text(unlock)
		"Fulfil Special Orders": return "Fulfil at least %s special orders" % quantity
		"Run Recipe": return "Operate %s buildings using a %s recipe" % [quantity, object_name]
		"Survey": return "Survey %s %s" % [quantity, object_name]
		"Stockpile filled": return "Supply one stockpile from %s for %s consecutive turns" % [object_name, quantity]
		"Sustain": return "Maintain %s for %s consecutive turns" % [object_name, quantity]
		"Use Infrastructure": return "Use at least %s %s at 80%% throughput or higher" % [quantity, object_name.capitalize()] if not "for" in unit else "Use %s %s at 80%% capacity for %s consecutive turns" % [quantity, object_name.capitalize(), _leading_condition_int(unit.get_slice("for", 1), 5)]
		"Firm Intermittency": return "Firm at least %s power of intermittent generation" % quantity
	return "%s %s %s" % [action, object_name, quantity]

func _run_multiple_condition_text(unlock: Dictionary) -> String:
	var targets := str(unlock.get("object", "")).split("|", false)
	var quantities := str(unlock.get("quantity", "")).split("|", false)
	var turns := _leading_condition_int(str(unlock.get("unit", "")), 0)
	if targets.is_empty() or targets.size() != quantities.size() or turns <= 0:
		return ""
	var parts: Array[String] = []
	for index in targets.size():
		parts.append("%s %s" % [str(quantities[index]), _condition_building_label(str(targets[index]), int(quantities[index]))])
	return "Operate at least %s at full capacity for %s consecutive turns" % [_join_condition_parts(parts), turns]

func _condition_building_label(raw: String, quantity: int = 1) -> String:
	var key := raw.strip_edges().to_lower().replace(" ", "_")
	if key == "high_tech_manufactory|assembly_plant":
		return "High Tech Manufactories and/or Assembly Plants"
	if key == "any":
		return "buildings"
	var label: String = str({
		"high_tech_manufactory": "High Tech Manufactory",
		"assembly_plant": "Assembly Plant",
		"solar_farm": "Solar Farm",
		"farm": "Farm",
	}.get(key, raw.capitalize()))
	if quantity != 1:
		if label.ends_with("y"):
			return "%sies" % label.left(label.length() - 1)
		return "%ss" % label
	return label

func _leading_condition_int(value: String, default_value: int) -> int:
	var digits := ""
	for ch in value.strip_edges():
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return int(digits) if digits != "" else default_value

func _join_condition_parts(parts: Array) -> String:
	if parts.size() <= 1:
		return str(parts[0]) if parts.size() == 1 else ""
	if parts.size() == 2:
		return "%s and %s" % [str(parts[0]), str(parts[1])]
	return ", ".join(parts.slice(0, parts.size() - 1)) + ", and " + str(parts[parts.size() - 1])

func _draw_tabs() -> void:
	var tab_bar := _tab_bar_rect()
	_tab_rects.clear()
	if tab_bar.size.x <= 0.0:
		return

	for index in CATEGORIES.size():
		var category: String = CATEGORIES[index]
		var rect := _tab_rect_for_category(category)
		_tab_rects[category] = rect
		var selected := category == _selected_category
		draw_style_box(_tab_selected_style if selected else _tab_unselected_style, rect)
		var text_color: Color = DS.PALETTE["BG_PANEL"] if selected else DS.PALETTE["ACCENT"]
		if selected:
			var shadow_rect := rect.grow(-8.0)
			shadow_rect.position += Vector2(1.0, 1.0)
			_draw_text_fit(BODY_FONT, category, shadow_rect, TAB_FONT_SIZE, Color(0, 0, 0, 0.26), HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text_fit(BODY_FONT, category, rect.grow(-8.0), TAB_FONT_SIZE, text_color, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_text_fit(font: Font, text: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment) -> void:
	var fitted_size := _fitted_font_size(font, text, rect.size.x, font_size)
	draw_string(font, _text_baseline_position(font, text, rect, fitted_size), text, alignment, rect.size.x, fitted_size, color)

func _draw_text_fixed(font: Font, text: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment) -> void:
	draw_string(font, _text_baseline_position(font, text, rect, font_size), text, alignment, rect.size.x, font_size, color)

func _draw_debossed_text_fit(font: Font, text: String, rect: Rect2, font_size: int, color: Color, zoom: float) -> void:
	var fitted_size := _fitted_font_size(font, text, rect.size.x, font_size)
	var position := _text_baseline_position(font, text, rect, fitted_size)
	var offset := maxf(0.7, 1.1 * zoom)
	draw_string(font, position + Vector2(-offset, -offset), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, Color(0.0, 0.0, 0.0, 0.34))
	draw_string(font, position + Vector2(offset, offset), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, Color(1.0, 1.0, 1.0, 0.13))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, color)
	draw_string(font, position + Vector2(0.0, offset * 0.55), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted_size, Color(0.0, 0.0, 0.0, 0.16))

func _fitted_font_size(font: Font, text: String, max_width: float, font_size: int) -> int:
	var fitted_size := font_size
	while fitted_size > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted_size).x > max_width:
		fitted_size -= 1
	return fitted_size

func _text_baseline_position(font: Font, text: String, rect: Rect2, font_size: int) -> Vector2:
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var content_height := ascent + descent
	var y := rect.position.y + (rect.size.y - content_height) * 0.5 + ascent
	return Vector2(rect.position.x, y)

func _draw_wrapped_lines(font: Font, text: String, rect: Rect2, font_size: int, color: Color, max_lines: int, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, center_vertically: bool = false) -> void:
	var words := text.split(" ", false)
	var lines: Array[String] = []
	var current := ""
	var overflow := false
	for word_index in words.size():
		var word := words[word_index]
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= rect.size.x:
			current = candidate
		else:
			if not current.is_empty():
				lines.append(current)
			current = word
			if lines.size() == max_lines:
				overflow = true
				break

	if not overflow and not current.is_empty():
		if lines.size() < max_lines:
			lines.append(current)
		else:
			overflow = true
	if lines.size() > max_lines:
		lines.resize(max_lines)
		overflow = true
	if overflow and not lines.is_empty():
		lines[max_lines - 1] = _ellipsize(font, lines[max_lines - 1], rect.size.x, font_size)

	var line_step := float(font_size + 2)
	var content_height := line_step * float(lines.size())
	var start_y := rect.position.y + font_size + 2.0
	if center_vertically:
		start_y = rect.position.y + (rect.size.y - content_height) * 0.5 + font_size
	for index in lines.size():
		var baseline_y := start_y + float(index) * line_step
		draw_string(font, Vector2(rect.position.x, baseline_y), lines[index], alignment, rect.size.x, font_size, color)
		_draw_profitably_underline(font, lines[index], rect, baseline_y, font_size, alignment, color)

func _draw_profitably_underline(font: Font, line: String, rect: Rect2, baseline_y: float, font_size: int, alignment: HorizontalAlignment, color: Color) -> void:
	var keyword := "profitably"
	var keyword_index := line.to_lower().find(keyword)
	if keyword_index < 0:
		return
	var line_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var line_start_x := rect.position.x
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		line_start_x += (rect.size.x - line_width) * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		line_start_x += rect.size.x - line_width
	var prefix_width := font.get_string_size(line.left(keyword_index), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var keyword_width := font.get_string_size(keyword, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var underline_y := baseline_y + 1.5
	draw_line(Vector2(line_start_x + prefix_width, underline_y), Vector2(line_start_x + prefix_width + keyword_width, underline_y), color, 1.0)

func _ellipsize(font: Font, text: String, max_width: float, font_size: int) -> String:
	var output := text
	while not output.is_empty() and font.get_string_size("%s..." % output, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > max_width:
		output = output.left(output.length() - 1)
	return "%s..." % output if not output.is_empty() else "..."
