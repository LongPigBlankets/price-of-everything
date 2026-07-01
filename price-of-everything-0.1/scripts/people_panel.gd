extends PanelContainer

signal close_requested

const MARKET_FALLBACK_SIZE := Vector2(400, 500)
const UIHelpers := preload("res://scripts/ui_helpers.gd")

const ADVISOR_CARD_WIDTH := 260.0
const ADVISOR_CARD_HEIGHT := 480.0
const ADVISOR_PORTRAIT_SIZE := ADVISOR_CARD_WIDTH
const PERMANENT_ADVISOR_CARD_WIDTH := ADVISOR_CARD_WIDTH + 30.0
const PERMANENT_ADVISOR_CARD_HEIGHT := ADVISOR_CARD_HEIGHT + 40.0
const PERMANENT_ADVISOR_PORTRAIT_SIZE := PERMANENT_ADVISOR_CARD_WIDTH
const HEADER_HEIGHT := 56.0

var _labour_buttons: Dictionary = {}
var _policy_buttons: Dictionary = {}
var _labour_effects: VBoxContainer
var _labour_indicator: PanelContainer
var _labour_pct_label: Label
var _labour_trend_label: Label
var _labour_amount_label: Label
var _labour_est_label: Label
var _advisors_root: VBoxContainer
var _advisor_payroll_label: Label
var _advisor_detail_panel: PanelContainer
var _advisor_detail_body: VBoxContainer
var _available_advisors_section: Control
var _available_pool_open := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _advisor_detail_dragging := false
var _advisor_detail_drag_offset := Vector2.ZERO
var _available_advisors: Array = []
var _permanent_advisors: Array = []

func _ready() -> void:
	name = "PeoplePanel"
	custom_minimum_size = MARKET_FALLBACK_SIZE
	size = MARKET_FALLBACK_SIZE
	_apply_market_window(self)
	theme_type_variation = &"PanelContainer"
	_build_panel()
	MatchState.labour_multiplier_changed.connect(func(_value: float): _refresh_labour())
	MatchState.workforce_policies_changed.connect(_refresh_policy_buttons)
	MatchState.workforce_policies_changed.connect(_refresh_labour_indicator)
	TurnManager.turn_resolution_completed.connect(_refresh_labour_indicator)
	if not MatchState.advisors_changed.is_connected(_on_advisors_changed):
		MatchState.advisors_changed.connect(_on_advisors_changed)
	visibility_changed.connect(_on_visibility_changed)

func _build_panel() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_people_header_input)
	layout.add_child(header)

	var title := _label("People", "Title")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(func(): close_requested.emit())
	header.add_child(close_button)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)

	var labour := _build_labour_tab()
	labour.name = "Labour"
	tabs.add_child(labour)

	var advisors := _build_advisors_tab()
	advisors.name = "Advisors"
	tabs.add_child(advisors)

func _build_labour_tab() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	root.add_child(top_row)

	var salaries := VBoxContainer.new()
	salaries.add_theme_constant_override("separation", 8)
	salaries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	salaries.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_row.add_child(salaries)

	salaries.add_child(_label("Labour Salaries", "Section"))

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	salaries.add_child(button_row)

	_add_labour_button(button_row, 0.8, "0.8x")
	_add_labour_button(button_row, 1.0, "1x")
	_add_labour_button(button_row, 1.2, "1.2x")

	# Big at-a-glance labour indicator, top-right beside the multiplier buttons.
	_labour_indicator = _build_labour_indicator()
	_labour_indicator.size_flags_horizontal = Control.SIZE_SHRINK_END
	_labour_indicator.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_row.add_child(_labour_indicator)

	_labour_effects = VBoxContainer.new()
	_labour_effects.add_theme_constant_override("separation", 6)
	root.add_child(_labour_effects)

	var separator := HSeparator.new()
	root.add_child(separator)

	root.add_child(_label("Workforce Policies", "Section"))
	var policies := GridContainer.new()
	policies.columns = 2
	policies.add_theme_constant_override("h_separation", 10)
	policies.add_theme_constant_override("v_separation", 8)
	root.add_child(policies)
	for policy in _policy_definitions():
		policies.add_child(_policy_row(policy))

	var total := HBoxContainer.new()
	total.add_theme_constant_override("separation", 8)
	root.add_child(total)
	var total_label := _label("Total policy impact", "Body")
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(total_label)
	var total_value := _label("0%", "Numeric")
	total_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_child(total_value)

	_refresh_labour()
	_refresh_policy_buttons()
	return margin

func _build_labour_indicator() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(132, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	margin.add_child(vb)

	vb.add_child(_label("Labour cost", "Caption"))

	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 6)
	vb.add_child(headline)
	_labour_pct_label = _label("100%", "Title")
	headline.add_child(_labour_pct_label)
	_labour_trend_label = _label("–", "Title")
	_labour_trend_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	headline.add_child(_labour_trend_label)

	_labour_amount_label = _label("£0/turn", "Numeric")
	vb.add_child(_labour_amount_label)

	_labour_est_label = _label("10t ≈ £0", "Caption")
	vb.add_child(_labour_est_label)

	return panel

# Refresh the labour indicator from the live aggregate: current % of base, raw
# £/turn, a coloured up/down arrow (from next-turn workforce-policy accrual), and
# the 10-turn estimate.
func _refresh_labour_indicator() -> void:
	if _labour_pct_label == null:
		return
	var ov: Dictionary = Production.labour_overview()
	var has: bool = bool(ov.get("has_buildings", false))
	var current: float = float(ov.get("current", 0.0))
	var est: float = float(ov.get("est_10_turns", current))
	_labour_pct_label.text = ("%d%%" % int(round(float(ov.get("factor_pct", 100.0))))) if has else "—"
	_labour_amount_label.text = "£%s/turn" % _fmt_amount(current)
	_labour_est_label.text = ("10t ≈ £%s" % _fmt_amount(est)) if has else "no buildings yet"

	# Trend arrow follows the 10-turn direction (matches the estimate shown below),
	# so slow workforce-policy drift still registers.
	var eps := 0.005 * maxf(1.0, current)
	if not has or absf(est - current) <= eps:
		_labour_trend_label.text = "–"
		_labour_trend_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif est > current:
		# Labour trending up (more expensive) — red.
		_labour_trend_label.text = "▲"
		_labour_trend_label.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
	else:
		# Labour trending down (cheaper) — green.
		_labour_trend_label.text = "▼"
		_labour_trend_label.add_theme_color_override("font_color", DS.PALETTE["OK"])

func _fmt_amount(v: float) -> String:
	if absf(v) >= 10000.0:
		return "%.0fk" % (v / 1000.0)
	if absf(v) >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%.0f" % v

func _add_labour_button(parent: HBoxContainer, multiplier: float, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.theme_type_variation = &"Build"
	button.custom_minimum_size = Vector2(64, 40)
	button.pressed.connect(_on_labour_button_pressed.bind(multiplier))
	parent.add_child(button)
	_labour_buttons[multiplier] = button

func _on_labour_button_pressed(multiplier: float) -> void:
	MatchState.set_labour_multiplier(multiplier)
	_refresh_labour()

func _refresh_labour() -> void:
	if _labour_effects == null:
		return
	var selected := _nearest_labour_choice(MatchState.labour_multiplier)
	for key in _labour_buttons.keys():
		var button: Button = _labour_buttons[key]
		button.set_pressed_no_signal(absf(float(key) - selected) < 0.001)

	_clear_children(_labour_effects)
	if selected < 1.0:
		_labour_effects.add_child(_effect_row([
			{"text": "Salary cost "},
			{"text": "-20%", "color": DS.PALETTE["OK"]},
		]))
		_labour_effects.add_child(_effect_row([
			{"text": "Output pressure "},
			{"text": "-2%", "color": DS.PALETTE["DANGER"]},
			{"text": " per turn, up to "},
			{"text": "-30%", "color": DS.PALETTE["DANGER"]},
		]))
	elif selected > 1.0:
		_labour_effects.add_child(_effect_row([
			{"text": "Salary cost "},
			{"text": "+20%", "color": DS.PALETTE["DANGER"]},
		]))
		_labour_effects.add_child(_effect_row([
			{"text": "Output momentum "},
			{"text": "+1%", "color": DS.PALETTE["OK"]},
			{"text": " per turn, up to "},
			{"text": "+10%", "color": DS.PALETTE["OK"]},
		]))
	else:
		_labour_effects.add_child(_effect_row([
			{"text": "Salary cost "},
			{"text": "0%"},
		]))
		_labour_effects.add_child(_effect_row([
			{"text": "Output pressure recovers "},
			{"text": "1%", "color": DS.PALETTE["OK"]},
			{"text": " per turn toward "},
			{"text": "0%"},
		]))

	_refresh_labour_indicator()

func _nearest_labour_choice(value: float) -> float:
	var choices := [0.8, 1.0, 1.2]
	var best: float = choices[0]
	var best_delta := absf(value - best)
	for choice in choices:
		var delta := absf(value - float(choice))
		if delta < best_delta:
			best = float(choice)
			best_delta = delta
	return best

func _effect_row(segments: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for segment in segments:
		var label := _label(str(segment.get("text", "")), "Body")
		if segment.has("color"):
			label.add_theme_color_override("font_color", segment["color"])
		row.add_child(label)
	return row

func _policy_definitions() -> Array:
	var third := _policy_game_third_turns()
	var second := third * 2
	var end := third * 3
	return [
		{
			"id": MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS,
			"name": "Generous Pensions",
			"cost": "Labour costs +0.1%%/turn for turns 1-%d, +0.25%%/turn for %d-%d, then +0.4%%/turn to turn %d." % [third, third + 1, second, end],
			"benefit": "Output +0.05%/turn while active, max +5%; decays 0.1%/turn when removed.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE,
			"name": "Extended Annual Leave",
			"cost": "Output -5% every 10th turn.",
			"benefit": "Labour costs -0.1%/turn while active, max -5%; decays 0.25%/turn when removed.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE,
			"name": "Generous Parental Leave",
			"cost": "Output -5% for 10 turns every other 10 turns.",
			"benefit": "Labour costs -0.1%/turn while active, max -5%; decays 0.25%/turn when removed.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_STRICT_SAFETY,
			"name": "Strict Safety Procedures",
			"cost": "Output -10%.",
			"benefit": "Labour costs -0.5%/turn while active, max -15%.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_STANDARD_SAFETY,
			"name": "Standard Safety Procedures",
			"cost": "No output change.",
			"benefit": "No labour cost change.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_LAX_SAFETY,
			"name": "Lax Safety Procedures",
			"cost": "Labour costs +0.5%/turn while active, max +15%.",
			"benefit": "Output +10%.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_ANNUAL_BONUS,
			"name": "Annual Bonus",
			"cost": "Labour costs +5%.",
			"benefit": "Output +20% every 10th turn.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE,
			"name": "Annual Profit Share",
			"cost": "Pay 5% of post-tax, post-dividend profit to workers.",
			"benefit": "Output +10%.",
		},
		{
			"id": "wellness_programme",
			"name": "Wellness Programme",
			"cost": "Placeholder.",
			"benefit": "No impact yet.",
			"placeholder": true,
		},
		{
			"id": "training_academy",
			"name": "Training Academy",
			"cost": "Placeholder.",
			"benefit": "No impact yet.",
			"placeholder": true,
		},
	]

func _policy_game_third_turns() -> int:
	return MatchState.workforce_policy_game_third_turns()

func _policy_row(policy: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 132)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)

	root.add_child(_policy_name_row(policy))
	root.add_child(_policy_text_row("Cost", str(policy.get("cost", "")), DS.PALETTE["DANGER"]))
	root.add_child(_policy_text_row("Benefit", str(policy.get("benefit", "")), DS.PALETTE["OK"]))
	return panel

func _policy_name_row(policy: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var checkbox := UIHelpers.make_custom_checkbox()
	checkbox.button_pressed = MatchState.is_workforce_policy_enabled(str(policy.get("id", "")))
	checkbox.toggled.connect(_on_policy_toggled.bind(str(policy.get("id", ""))))
	row.add_child(checkbox)
	_policy_buttons[str(policy.get("id", ""))] = checkbox

	var row_label := _label("Name", "Caption")
	row_label.custom_minimum_size = Vector2(46, 0)
	row_label.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	row.add_child(row_label)

	var name := _label(str(policy.get("name", "")), "BuildingName")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	return row

func _policy_text_row(row_name: String, text: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(26, 0)
	row.add_child(spacer)

	var row_label := _label(row_name, "Caption")
	row_label.custom_minimum_size = Vector2(46, 0)
	row_label.add_theme_color_override("font_color", Color(accent, 0.86))
	row.add_child(row_label)

	var body := _label(text, "Caption")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row

func _on_policy_toggled(pressed: bool, policy_id: String) -> void:
	MatchState.set_workforce_policy_enabled(policy_id, pressed)

func _refresh_policy_buttons() -> void:
	for policy_id in _policy_buttons:
		var checkbox: CheckBox = _policy_buttons[policy_id]
		if is_instance_valid(checkbox):
			checkbox.set_pressed_no_signal(MatchState.is_workforce_policy_enabled(str(policy_id)))

func _build_advisors_tab() -> Control:
	var outer_scroll := ScrollContainer.new()
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	outer_scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	_advisors_root = root

	_refresh_advisors_tab()
	return outer_scroll

func _on_advisors_changed() -> void:
	_sync_advisor_lists()
	_refresh_advisors_tab()

func _sync_advisor_lists() -> void:
	_permanent_advisors = MatchState.permanent_advisors()
	_available_advisors = MatchState.available_advisors()

func _refresh_advisors_tab() -> void:
	if not is_instance_valid(_advisors_root):
		return
	_sync_advisor_lists()
	_clear_children(_advisors_root)
	_advisors_root.add_child(_advisor_payroll_summary())
	_add_advisor_section(_advisors_root, "Permanent Advisors", _permanent_advisors, true)
	_available_advisors_section = _add_advisor_section(_advisors_root, "Available Advisors", _available_advisors, false)
	_available_advisors_section.visible = _available_pool_open

func _advisor_payroll_summary() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var title := _label("Advisor payroll", "Section")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_advisor_payroll_label = _label("", "Numeric")
	_advisor_payroll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_advisor_payroll_label)
	_refresh_advisor_payroll_label()
	return panel

func _refresh_advisor_payroll_label() -> void:
	if not is_instance_valid(_advisor_payroll_label):
		return
	var count := MatchState.permanent_advisor_ids.size()
	var payroll := MatchState.advisor_payroll_per_turn()
	_advisor_payroll_label.text = "%d x £%.0f = £%.2f/turn" % [count, MatchState.ADVISOR_COST_PER_TURN, payroll]

func _add_advisor_section(parent: VBoxContainer, title_text: String, advisors: Array, permanent: bool) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, _advisor_card_height(permanent) + 22.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(_advisor_section_header(title_text, scroll))
	section.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	var shown := 0
	for advisor in advisors:
		if advisor is Dictionary:
			row.add_child(_advisor_card(advisor, permanent, false))
			shown += 1
	if permanent:
		row.add_child(_advisor_card({}, true, true))
	elif shown == 0:
		row.add_child(_empty_advisor_pool_card())
	return section

func _advisor_card(advisor: Dictionary, permanent: bool, add_slot: bool) -> Control:
	var card := PanelContainer.new()
	var card_w := _advisor_card_width(permanent)
	var card_h := _advisor_card_height(permanent)
	card.name = "AdvisorAddSlot" if add_slot else "AdvisorCard_%s" % str(advisor.get("id", "unknown"))
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.add_theme_stylebox_override("panel", _round_box(DS.PALETTE["BG_CARD"], DS.PALETTE["BORDER_SOFT"], 10, 1, 0))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if add_slot and permanent:
		card.gui_input.connect(_on_permanent_add_slot_input)
	elif permanent and not add_slot:
		card.gui_input.connect(_on_advisor_card_input.bind(advisor))
	elif not add_slot:
		card.gui_input.connect(_on_available_advisor_card_input.bind(advisor))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(root)

	var portrait_size := _advisor_portrait_size(permanent)
	var portrait := _portrait_panel(advisor, permanent, add_slot, Vector2(portrait_size, portrait_size))
	portrait.name = "AdvisorPortrait"
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(portrait)

	var name_label := _label("Open Slot" if add_slot else str(advisor.get("name", "")), "BuildingName")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(name_label)

	var role := _label(_slot_role_label(permanent) if add_slot else str(advisor.get("role", "")), "Caption")
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(role)

	if not add_slot:
		root.add_child(_happiness_row(int(advisor.get("happiness", 0))))

	var bonus := _label("Open slot" if add_slot else str(advisor.get("bonus", "")), "Caption")
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(bonus)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var rec := PanelContainer.new()
	rec.custom_minimum_size = Vector2(card_w, 82)
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec.add_theme_stylebox_override("panel", _round_box(Color(0, 0, 0, 0.82), Color(0, 0, 0, 0), 7, 0, 10))
	root.add_child(rec)
	var rec_margin := MarginContainer.new()
	rec_margin.add_theme_constant_override("margin_left", 8)
	rec_margin.add_theme_constant_override("margin_top", 8)
	rec_margin.add_theme_constant_override("margin_right", 8)
	rec_margin.add_theme_constant_override("margin_bottom", 8)
	rec.add_child(rec_margin)
	var rec_label := _label(_slot_recommendation(permanent) if add_slot else str(advisor.get("recommendation", "")), "Caption")
	rec_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rec_margin.add_child(rec_label)
	_make_click_through(root)
	return card

func _empty_advisor_pool_card() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(ADVISOR_CARD_WIDTH, 160)
	card.add_theme_stylebox_override("panel", _round_box(DS.PALETTE["BG_CARD"], DS.PALETTE["BORDER_SOFT"], 10, 1, 14))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var body := _label("No available advisors remain.", "Caption")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(body)
	return card

func _advisor_section_header(title_text: String, content: Control) -> Button:
	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.text = _section_title(true, title_text)
	header.set_meta("expanded", true)
	header.add_theme_stylebox_override("normal", _section_header_style(false, false))
	header.add_theme_stylebox_override("hover", _section_header_style(true, false))
	header.add_theme_stylebox_override("pressed", _section_header_style(true, true))
	header.add_theme_stylebox_override("focus", _section_header_style(true, false))
	header.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	header.add_theme_color_override("font_hover_color", DS.PALETTE["ACCENT"])
	header.add_theme_color_override("font_pressed_color", DS.PALETTE["ACCENT"])
	header.pressed.connect(_on_advisor_section_pressed.bind(header, content, title_text))
	return header

func _on_advisor_section_pressed(header: Button, content: Control, title_text: String) -> void:
	var expanded := true
	if is_instance_valid(header):
		expanded = not bool(header.get_meta("expanded", true))
		header.set_meta("expanded", expanded)
	if is_instance_valid(content):
		content.visible = expanded
	if is_instance_valid(header):
		header.text = _section_title(expanded, title_text)

func _section_title(expanded: bool, title_text: String) -> String:
	return ("%s %s" % ["v" if expanded else ">", title_text])

func _slot_role_label(permanent: bool) -> String:
	return "Permanent Advisor" if permanent else "Available Advisor"

func _slot_recommendation(permanent: bool) -> String:
	if permanent:
		return "Click to choose a permanent specialist from the advisor pool."
	return "Click to add this advisor to the permanent team."

func _advisor_card_width(permanent: bool) -> float:
	return PERMANENT_ADVISOR_CARD_WIDTH if permanent else ADVISOR_CARD_WIDTH

func _advisor_card_height(permanent: bool) -> float:
	return PERMANENT_ADVISOR_CARD_HEIGHT if permanent else ADVISOR_CARD_HEIGHT

func _advisor_portrait_size(permanent: bool) -> float:
	return PERMANENT_ADVISOR_PORTRAIT_SIZE if permanent else ADVISOR_PORTRAIT_SIZE

func _on_permanent_add_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_available_pool_open = true
		_refresh_advisors_tab()
		accept_event()

func _happiness_row(value: int) -> Control:
	var meter := Control.new()
	meter.custom_minimum_size = Vector2(0, 36)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.draw.connect(_draw_happiness_meter.bind(meter))

	var pill := UIHelpers.make_quantity_pill(_signed_value(value), 24, 14)
	var anchor := clampf((float(value) + 10.0) / 20.0, 0.08, 0.92)
	var pill_w := pill.custom_minimum_size.x
	pill.anchor_left = anchor
	pill.anchor_right = anchor
	pill.anchor_top = 0.0
	pill.anchor_bottom = 0.0
	pill.offset_left = -pill_w / 2.0
	pill.offset_right = pill_w / 2.0
	pill.offset_top = 2.0
	pill.offset_bottom = 26.0
	meter.add_child(pill)
	meter.resized.connect(func() -> void: meter.queue_redraw())
	return meter

func _draw_happiness_meter(meter: Control) -> void:
	var w := meter.size.x
	if w <= 0.0:
		return
	var y := 24.0
	var h := 5.0
	meter.draw_rect(Rect2(0.0, y, w * 0.5, h), Color(0.78, 0.18, 0.16, 0.34))
	meter.draw_rect(Rect2(w * 0.5, y, w * 0.5, h), Color(0.18, 0.62, 0.35, 0.34))
	for i in range(3):
		var x := w * float(i + 1) / 4.0
		meter.draw_line(Vector2(x, y - 4.0), Vector2(x, y + h + 4.0), Color(DS.PALETTE["ACCENT"], 0.72), 2.0)

func _signed_value(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)

func _on_advisor_card_input(event: InputEvent, advisor: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_advisor_detail(advisor)
		accept_event()

func _on_available_advisor_card_input(event: InputEvent, advisor: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if MatchState.hire_advisor(str(advisor.get("id", ""))):
			_available_pool_open = true
			_refresh_advisors_tab()
		accept_event()

func _open_advisor_detail(advisor: Dictionary) -> void:
	_ensure_detail_panel()
	_build_advisor_detail(advisor)
	_apply_market_window(_advisor_detail_panel)
	_advisor_detail_panel.show()
	PanelStack.push(_advisor_detail_panel)
	_advisor_detail_panel.move_to_front()
	call_deferred("_raise_advisor_detail")

func _ensure_detail_panel() -> void:
	if is_instance_valid(_advisor_detail_panel):
		return
	_advisor_detail_panel = PanelContainer.new()
	_advisor_detail_panel.name = "AdvisorDetailPanel"
	_advisor_detail_panel.custom_minimum_size = MARKET_FALLBACK_SIZE
	_advisor_detail_panel.size = MARKET_FALLBACK_SIZE
	_advisor_detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_advisor_detail_panel.gui_input.connect(_on_advisor_detail_panel_input)
	_advisor_detail_panel.hide()

	var host := get_parent()
	if host == null:
		add_child(_advisor_detail_panel)
	else:
		host.add_child(_advisor_detail_panel)

func _build_advisor_detail(advisor: Dictionary) -> void:
	_clear_children(_advisor_detail_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_advisor_detail_panel.add_child(margin)

	_advisor_detail_body = VBoxContainer.new()
	_advisor_detail_body.add_theme_constant_override("separation", 12)
	margin.add_child(_advisor_detail_body)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_advisor_detail_header_input)
	_advisor_detail_body.add_child(header)
	var title := _label(str(advisor.get("role", "Advisor")), "Title")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(_close_advisor_detail)
	header.add_child(close_button)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_advisor_detail_body.add_child(top)

	var portrait_col := VBoxContainer.new()
	portrait_col.custom_minimum_size = Vector2(180, 0)
	portrait_col.add_theme_constant_override("separation", 10)
	top.add_child(portrait_col)
	portrait_col.add_child(_portrait_panel(advisor, true, false, Vector2(180, 180)))
	portrait_col.add_child(_recommendation_box(str(advisor.get("recommendation", ""))))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)

	var bio := _label(str(advisor.get("bio", "")), "Body")
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(bio)

	info.add_child(_detail_block("Agenda", _agenda_text(advisor)))
	info.add_child(_detail_block("Bonuses", _list_text(advisor.get("bonuses", []))))

	_advisor_detail_body.add_child(_quest_diagram(advisor.get("missions", advisor.get("quests", []))))

func _detail_block(title_text: String, body_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)
	root.add_child(_label(title_text, "Section"))
	var body := _label(body_text, "Caption")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(body)
	return panel

func _agenda_text(advisor: Dictionary) -> String:
	var agenda := str(advisor.get("agenda", "")).strip_edges()
	var likes := _list_text(advisor.get("likes", []))
	var dislikes := _list_text(advisor.get("dislikes", []))
	if agenda != "":
		return "%s\n\nLikes\n%s\n\nDislikes\n%s" % [agenda, likes, dislikes]
	return "Likes\n%s\n\nDislikes\n%s" % [likes, dislikes]

func _list_text(items: Variant) -> String:
	if not (items is Array):
		return str(items)
	var lines: Array[String] = []
	for item in items:
		lines.append("- " + str(item))
	return "\n".join(lines)

func _recommendation_box(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_box(Color(0, 0, 0, 0.85), Color(0, 0, 0, 0), 8, 0, 12))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var label := _label(text, "Caption")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(label)
	return panel

func _quest_diagram(quests: Variant) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(0, 156)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	root.add_child(_label("Missions", "Section"))

	var rail_area := Control.new()
	rail_area.custom_minimum_size = Vector2(0, 104)
	rail_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(rail_area)

	var rail_shadow := ColorRect.new()
	rail_shadow.color = Color(0, 0, 0, 0.42)
	rail_shadow.anchor_left = 0.06
	rail_shadow.anchor_right = 0.94
	rail_shadow.anchor_top = 0.5
	rail_shadow.anchor_bottom = 0.5
	rail_shadow.offset_top = -6
	rail_shadow.offset_bottom = 18
	rail_area.add_child(rail_shadow)

	var rail := ColorRect.new()
	rail.color = Color("#B68B3A")
	rail.anchor_left = 0.06
	rail.anchor_right = 0.94
	rail.anchor_top = 0.5
	rail.anchor_bottom = 0.5
	rail.offset_top = -10
	rail.offset_bottom = 10
	rail_area.add_child(rail)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	rail_area.add_child(row)

	var quest_list: Array = quests if quests is Array else []
	for i in range(5):
		var wrapper := CenterContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(wrapper)
		var quest: Dictionary = {"roman": str(i + 1), "title": "Mission", "state": "locked", "color": Color("#56687C")}
		if i < quest_list.size() and quest_list[i] is Dictionary:
			quest = quest_list[i]
		wrapper.add_child(_mission_plaque(quest))
	return panel

func _mission_plaque(quest: Dictionary) -> Control:
	var state := str(quest.get("state", "locked"))
	var plaque := PanelContainer.new()
	plaque.custom_minimum_size = Vector2(104, 82)
	plaque.add_theme_stylebox_override("panel", _mission_style(state, quest.get("color", Color("#56687C"))))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	plaque.add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 2)
	margin.add_child(root)

	var roman := _label(str(quest.get("roman", "I")), "Section")
	roman.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(roman)

	var title := _label(str(quest.get("title", "Mission")), "Caption")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	return plaque

func _mission_style(state: String, base_color: Variant) -> StyleBoxFlat:
	var fill := Color("#56687C")
	if base_color is Color:
		fill = base_color
	var border := Color("#D9B35A")
	if state == "completed":
		fill = Color("#CDA349")
		border = Color("#F6D57A")
	elif state == "locked":
		fill = fill.darkened(0.18)
		border = Color("#806A3A")

	var sb := _round_box(fill, border, 9, 3, 14)
	sb.shadow_color = Color(0, 0, 0, 0.34)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	if state == "next":
		sb.border_color = Color("#F9D877")
		sb.shadow_color = Color(1, 1, 1, 0.62)
		sb.shadow_size = 20
		sb.shadow_offset = Vector2.ZERO
	return sb

func _portrait_panel(advisor: Dictionary, permanent: bool, add_slot: bool, min_size: Vector2) -> Control:
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = min_size
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := Color("#53687A")
	var color_value: Variant = advisor.get("portrait_color", Color("#53687A"))
	if color_value is Color:
		color = color_value

	var texture := _advisor_texture(str(advisor.get("portrait_path", ""))) if not add_slot else null
	if texture != null:
		portrait.add_theme_stylebox_override("panel", _round_box(Color("#071421"), DS.PALETTE["BORDER_SOFT"], 12, 2, 0))
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(image)
		return portrait

	if permanent or add_slot:
		portrait.add_theme_stylebox_override("panel", _frost_style(color if not add_slot else Color("#DCEBFF")))
	else:
		portrait.add_theme_stylebox_override("panel", _round_box(color, DS.PALETTE["BORDER_SOFT"], 10, 2, 10))

	var center := CenterContainer.new()
	portrait.add_child(center)
	var label := _label("+" if add_slot else str(advisor.get("initials", "?")), "Title")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if add_slot:
		label.add_theme_font_size_override("font_size", 52)
	center.add_child(label)
	return portrait

func _make_click_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_click_through(child)

func _advisor_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _close_advisor_detail() -> void:
	if is_instance_valid(_advisor_detail_panel):
		PanelStack.remove(_advisor_detail_panel)
		_advisor_detail_panel.hide()
	_advisor_detail_dragging = false

func _on_visibility_changed() -> void:
	if visible:
		_apply_market_window(self)
		_refresh_advisors_tab()
	else:
		_close_advisor_detail()
		_dragging = false

func _gui_input(event: InputEvent) -> void:
	_handle_people_drag_input(event, true)

func _on_people_header_input(event: InputEvent) -> void:
	_handle_people_drag_input(event, false)

func _on_advisor_detail_panel_input(event: InputEvent) -> void:
	_handle_advisor_detail_drag_input(event, true)

func _on_advisor_detail_header_input(event: InputEvent) -> void:
	_handle_advisor_detail_drag_input(event, false)

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

func _handle_advisor_detail_drag_input(event: InputEvent, limit_to_top_strip: bool) -> void:
	if not is_instance_valid(_advisor_detail_panel):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if limit_to_top_strip and event.position.y > HEADER_HEIGHT:
				return
			PanelStack.focus(_advisor_detail_panel)
			_advisor_detail_dragging = true
			_advisor_detail_drag_offset = _advisor_detail_panel.global_position - get_global_mouse_position()
			accept_event()
		else:
			_advisor_detail_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _advisor_detail_dragging:
		_advisor_detail_panel.global_position = get_global_mouse_position() + _advisor_detail_drag_offset
		accept_event()

func _raise_advisor_detail() -> void:
	if is_instance_valid(_advisor_detail_panel) and _advisor_detail_panel.visible:
		PanelStack.focus(_advisor_detail_panel)

func _label(text: String, variation: String = "Body") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = StringName(variation)
	return label

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _apply_market_window(control: Control) -> void:
	var vp := get_viewport_rect().size
	var w := minf(1220.0, vp.x - 60.0)
	var base_h := minf(640.0, vp.y - 80.0)
	var h := (base_h + 40.0) * 1.30
	var centred_top := maxf(40.0, (vp.y - base_h) / 2.0)
	var bottom := centred_top + base_h
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = maxf(0.0, (vp.x - w) / 2.0)
	control.offset_top = maxf(8.0, bottom - h)
	control.offset_right = control.offset_left + w
	control.offset_bottom = bottom

func _round_box(fill: Color, border: Color, radius: int, border_width: int, padding: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(padding)
	return sb

func _section_header_style(hovered: bool, pressed: bool) -> StyleBoxFlat:
	var fill := Color(DS.PALETTE["BG_CARD"], 0.0)
	var border := Color(DS.PALETTE["BORDER_SOFT"], 0.0)
	if hovered:
		fill = Color(DS.PALETTE["BG_HIGHLIGHT"], 0.42)
		border = Color(DS.PALETTE["BORDER_SOFT"], 0.42)
	if pressed:
		fill = Color(DS.PALETTE["BG_HIGHLIGHT"], 0.62)
		border = DS.PALETTE["BORDER_SOFT"]
	return _round_box(fill, border, 5, 1, 6)

func _frost_style(color: Color) -> StyleBoxFlat:
	var sb := _round_box(Color(color, 0.28), Color(1, 1, 1, 0.42), 12, 2, 10)
	sb.shadow_color = Color(0.8, 0.95, 1.0, 0.18)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2.ZERO
	return sb
