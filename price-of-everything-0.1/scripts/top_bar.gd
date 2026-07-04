extends PanelContainer

@onready var money_widget: Button = $MarginContainer/HBoxContainer/MoneyWidget

signal money_widget_clicked
## The top-bar victory score widget was clicked (opens the Victory panel).
signal victory_widget_clicked
## The council loyalty surface was clicked (opens the People panel).
signal council_widget_clicked

const FLASH_RED := Color(0.9, 0.2, 0.2)
const SAVE_TOOLTIP := "Save the game (quicksave slot)"
const SAVE_LOCKED_TOOLTIP := "Please wait until the turn resolves"

var _flashing := false
var _save_button: Button

func _ready() -> void:
	money_widget.pressed.connect(_on_money_clicked)
	MatchState.money_changed.connect(_on_money_changed)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)
	_refresh_money_display(MatchState.money)
	_add_victory_widget()
	_add_council_widget()
	_add_save_button()
	_add_notification_bell()

func _add_victory_widget() -> void:
	# The victory score widget sits next to MoneyWidget at the left of the top-bar
	# HBox (peer to the Save button + NotificationBell). Click opens the Victory panel.
	var widget: Control = load("res://scripts/victory_widget.gd").new()
	widget.name = "VictoryWidget"
	widget.clicked.connect(func() -> void: victory_widget_clicked.emit())
	money_widget.get_parent().add_child(widget)

func _add_notification_bell() -> void:
	# The bell sits at the right end of the top-bar HBox, just inside the money
	# row's container — it's a peer to MoneyWidget and the (programmatic) Save
	# button. EventScheduler signals drive its colour, badge and dropdown.
	var bell: Control = load("res://scripts/notification_bell.gd").new()
	bell.name = "NotificationBell"
	money_widget.get_parent().add_child(bell)

# ── Council loyalty surface (design: People Panel top bar) ──────────────────
# Average council loyalty (tone-coloured) plus an overlapping stack of seated
# advisor portraits, with hollow slots for unfilled seat capacity. Click opens
# the People panel's Advisors tab.
const _COUNCIL_GOOD := Color("#5FBF6B")
const _COUNCIL_WARN := Color("#E6B34A")
const _COUNCIL_BAD := Color("#E2604A")

var _council_button: Button
var _council_mood_label: Label
var _council_stack: HBoxContainer
var _council_refresh_queued := false

func _add_council_widget() -> void:
	_council_button = Button.new()
	_council_button.tooltip_text = "Council loyalty — open People"
	_council_button.pressed.connect(func() -> void: council_widget_clicked.emit())
	# Buttons don't size to child containers: anchor the row full-rect with
	# padding and set the button's min width from the slot count on refresh.
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 9
	row.offset_right = -9
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_council_button.add_child(row)
	_council_mood_label = Label.new()
	_council_mood_label.add_theme_font_size_override("font_size", 13)
	row.add_child(_council_mood_label)
	_council_stack = HBoxContainer.new()
	_council_stack.add_theme_constant_override("separation", -7)
	_council_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_council_stack)
	money_widget.get_parent().add_child(_council_button)
	MatchState.advisors_changed.connect(_queue_council_refresh)
	MatchState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_council_refresh())
	_refresh_council_widget()

func _queue_council_refresh() -> void:
	if _council_refresh_queued:
		return
	_council_refresh_queued = true
	call_deferred("_refresh_council_widget")

func _refresh_council_widget() -> void:
	_council_refresh_queued = false
	if not is_instance_valid(_council_button):
		return
	var seated: Array = MatchState.advisor_seats.values()
	var slots: int = MatchState.max_advisor_slots
	var avg := 0.0
	for aid in seated:
		avg += MatchState.advisor_loyalty_value(str(aid))
	avg = avg / float(seated.size()) if seated.size() > 0 else 0.0
	var tone := _COUNCIL_WARN
	if seated.size() > 0:
		tone = _COUNCIL_GOOD if avg >= 3.4 else (_COUNCIL_WARN if avg > -3.4 else _COUNCIL_BAD)
	_council_mood_label.text = ("%+.1f" % avg) if seated.size() > 0 else "—"
	_council_mood_label.add_theme_color_override("font_color", tone if seated.size() > 0 else Color("#8298AC"))
	for c in _council_stack.get_children():
		_council_stack.remove_child(c)
		c.queue_free()
	for aid in seated:
		_council_stack.add_child(_council_mini_portrait(MatchState.get_advisor(str(aid))))
	for _i in range(maxi(0, slots - seated.size())):
		_council_stack.add_child(_council_empty_slot())
	# Buttons don't size to non-container children: width = padding + label + stack.
	var label_w := 34.0 if seated.size() > 0 else 16.0
	var stack_w := 22.0 + float(maxi(0, slots - 1)) * 15.0
	_council_button.custom_minimum_size = Vector2(26.0 + label_w + stack_w, 32)

func _council_mini_portrait(adv: Dictionary) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(22, 22)
	holder.clip_contents = true
	var accent: Color = adv.get("portrait_color", Color("#53687A"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.45)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(11)
	holder.add_theme_stylebox_override("panel", sb)
	var path := str(adv.get("portrait_path", ""))
	if path != "" and ResourceLoader.exists(path):
		var img := TextureRect.new()
		img.texture = load(path) as Texture2D
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		holder.add_child(img)
	else:
		var initials := Label.new()
		initials.text = str(adv.get("initials", "?")).substr(0, 1)
		initials.add_theme_font_size_override("font_size", 10)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(initials)
	return holder

func _council_empty_slot() -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(22, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0A1220")
	sb.border_color = Color("#D96AA0", 0.4)   # People pink, hollow
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(11)
	holder.add_theme_stylebox_override("panel", sb)
	return holder

func _add_save_button() -> void:
	# Quicksave to the "quicksave" slot (named saves via the debug terminal /
	# the main menu's Load Game lists both). Saving is DECIDE-phase-only;
	# SaveLoad returns the reason when it refuses and we toast it either way.
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.tooltip_text = SAVE_TOOLTIP
	save_button.pressed.connect(_on_save_pressed)
	money_widget.get_parent().add_child(save_button)
	_save_button = save_button
	# Saving is DECIDE-only; grey the button out during resolution instead of
	# letting the click fail with a toast.
	TurnManager.turn_resolution_started.connect(_refresh_save_lock)
	TurnManager.turn_resolution_completed.connect(_refresh_save_lock)
	_refresh_save_lock()

func _refresh_save_lock() -> void:
	var locked: bool = TurnManager.is_resolving
	_save_button.disabled = locked
	_save_button.tooltip_text = SAVE_LOCKED_TOOLTIP if locked else SAVE_TOOLTIP

func _on_save_pressed() -> void:
	var err: String = SaveLoad.save_slot("quicksave")
	if err == "":
		MatchState.request_toast("Game saved (quicksave).", "success")
	else:
		MatchState.request_toast("Could not save: %s" % err, "warning")

func _on_money_changed(new_amount: float) -> void:
	_refresh_money_display(new_amount)

func _on_build_rejected_no_funds(_message: String) -> void:
	flash_red()

func _base_money_color() -> Color:
	var amount: float = MatchState.money
	if amount < 0:
		return FLASH_RED
	elif amount < 10:
		return Color(1.0, 0.6, 0.2)
	return Color(0.995234, 0.930806, 0.763265)

func _refresh_money_display(amount: float) -> void:
	money_widget.text = " £%.2f" % amount
	if not _flashing:
		money_widget.add_theme_color_override("font_color", _base_money_color())

func _set_money_color(c: Color) -> void:
	money_widget.add_theme_color_override("font_color", c)

func flash_red() -> void:
	# Flash twice: base→red→base→red→base, 0.2s each leg. Re-triggering while
	# flashing is ignored (the sequence completes once and does not loop).
	if _flashing:
		return
	_flashing = true
	var base := _base_money_color()
	var tween := create_tween()
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_callback(func() -> void:
		_flashing = false
		_set_money_color(_base_money_color())
	)

func _on_money_clicked() -> void:
	money_widget_clicked.emit()
