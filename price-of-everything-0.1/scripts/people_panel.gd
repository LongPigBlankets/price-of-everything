extends PanelContainer
## The People panel: the DS2 shell (scripts/people_ds2/people_ds2.gd, docs/people-ds2-plan.md) with its
## Advisors and Labour tabs. This host places the panel, drags it and closes it.

signal close_requested

const MARKET_FALLBACK_SIZE := Vector2(400, 500)
const PeopleDs2Script := preload("res://scripts/people_ds2/people_ds2.gd")
## One width for both tabs (plan §5): the tile view's.
const DS2_WIDTH := 800.0
## Under the top bar (60 px high, panels start at 72: docs/ds2-owner-decisions.md).
const DS2_TOP := 72.0
const HEADER_HEIGHT := 56.0

var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	name = "PeoplePanel"
	# This panel is created lazily and can be mounted beneath a non-Control helper
	# in tests/tools, so bind the design-system theme at the panel boundary.
	if DS and DS.theme:
		theme = DS.theme
	custom_minimum_size = MARKET_FALLBACK_SIZE
	size = MARKET_FALLBACK_SIZE
	_build()
	if not AdvisorState.advisor_acquired.is_connected(_on_advisor_acquired):
		AdvisorState.advisor_acquired.connect(_on_advisor_acquired)
	visibility_changed.connect(_on_visibility_changed)

## Places the panel and builds the DS2 shell in it.
func _build() -> void:
	_apply_window()
	theme_type_variation = &"PanelContainer"
	var shell: Control = PeopleDs2Script.new()
	shell.connect("close_requested", func() -> void: close_requested.emit())
	shell.connect("drag_input", _on_people_header_input)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(shell)

func _on_advisor_acquired(advisor_id: String) -> void:
	var a := AdvisorState.get_advisor(advisor_id)
	MatchState.request_toast("New advisor: %s" % str(a.get("name", advisor_id)), "success")

func _on_visibility_changed() -> void:
	if visible:
		_apply_window()
	else:
		_dragging = false

func _gui_input(event: InputEvent) -> void:
	_handle_people_drag_input(event, true)

func _on_people_header_input(event: InputEvent) -> void:
	_handle_people_drag_input(event, false)

func _handle_people_drag_input(event: InputEvent, limit_to_top_strip: bool) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if limit_to_top_strip and event.position.y > HEADER_HEIGHT:
				return
			PanelStack.focus(self)
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()

# One width for both tabs, centred horizontally under the top bar, its foot at
# viewport-130 (the ResearchPanel's). Tab contents scroll within this fixed height.
func _apply_window() -> void:
	var vp := get_viewport_rect().size
	var w := minf(DS2_WIDTH, vp.x - 24.0)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = maxf(0.0, (vp.x - w) / 2.0)
	offset_right = offset_left + w
	offset_top = DS2_TOP
	offset_bottom = maxf(232.0, vp.y - 130.0)
