extends PanelContainer
## Offered one turn before a build completes, when its inputs are being ordered and the first
## money is about to move. A new building costs everything and earns nothing until its first
## output reaches a market — or becomes something worth more further down the chain — and that
## gap is what sinks new players. See docs/early-game-onboarding-spec.md §5.3.
##
## Built in code and parented to the HUD, mirroring construction_missing_dialog.gd. One
## instance is reused; open() re-labels it for the building in question.
##
## The sim never opens this. Construction emits building_tab_opened and the HUD listens, so a
## headless run resolves with the default (interest-free slices) and never waits on a dialog.

signal choice_made(instance_id: String, mode: String)   # mode: slices | loan | none

const BODY := "We have a credit facility that will smooth over the large costs when a building starts up. Inputs, labour, energy and maintenance are all really expensive until we ship the first unit to the market — or make it into something more valuable down the line. Our facility covers the next %d turns."

var _instance_id: String = ""
var _options: VBoxContainer
var _buttons: HBoxContainer


func _ready() -> void:
	_build_ui()
	visible = false


func open(instance_id: String, building_name: String) -> void:
	_instance_id = instance_id
	var turn: int = TurnManager.current_turn
	var window: int = MatchState.TAB_WINDOW_TURNS
	var slices: int = MatchState.TAB_SLICES
	# The window runs from this turn; repayment starts the turn after it closes.
	var slice_start: int = turn + window + 1
	var slice_end: int = slice_start + slices
	var loan_first: int = turn + window + EconomyConfig.LOAN_GRACE_TURNS
	var loan_turns: int = EconomyConfig.LOAN_GRACE_TURNS + EconomyConfig.LOAN_TERM_TURNS
	var rate_pct: float = LoanState.effective_loan_interest_rate() * 100.0

	for child in _options.get_children():
		child.queue_free()
	_options.add_child(_option_line(
		"Pay the debt at no interest between turns %d and %d." % [slice_start, slice_end]))
	_options.add_child(_option_line(
		"Pay the debt at regular interest as a loan over %d turns, with the first payment in turn %d."
			% [loan_turns, loan_first]))
	_options.add_child(_option_line("Do not use the credit facility."))

	for child in _buttons.get_children():
		child.queue_free()
	_buttons.add_child(_cta("%d turns, no interest" % slices, "slices", true))
	_buttons.add_child(_cta("%d turns, %.0f%% interest" % [loan_turns, rate_pct], "loan", false))
	_buttons.add_child(_cta("Don't use", "none", false))

	($MarginContainer/VBox/Title as Label).text = "Credit facility — %s" % building_name
	visible = true
	PanelStack.push(self)


func _choose(mode: String) -> void:
	var iid := _instance_id
	_instance_id = ""
	visible = false
	PanelStack.remove(self)
	choice_made.emit(iid, mode)


func _option_line(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := Label.new()
	dot.text = "•"
	dot.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	row.add_child(dot)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)
	return row


func _cta(text: String, mode: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.name = "CreditChoice_%s" % mode
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		btn.theme_type_variation = &"Primary"
	btn.pressed.connect(func() -> void: _choose(mode))
	return btn


func _build_ui() -> void:
	theme = DS.theme
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -320.0
	offset_right = 320.0
	offset_top = -180.0
	offset_bottom = 180.0
	custom_minimum_size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	var title := Label.new()
	title.name = "Title"
	title.text = "Credit facility"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	var body := Label.new()
	body.text = BODY % MatchState.TAB_WINDOW_TURNS
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	vb.add_child(body)

	var prompt := Label.new()
	prompt.text = "Do you want to:"
	prompt.add_theme_font_size_override("font_size", 13)
	vb.add_child(prompt)

	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	vb.add_child(_options)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	vb.add_child(_buttons)
