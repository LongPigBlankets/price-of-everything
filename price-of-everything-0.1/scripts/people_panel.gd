extends PanelContainer

signal close_requested

const MARKET_FALLBACK_SIZE := Vector2(400, 500)
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const AdvisorCouncilTabScript := preload("res://scripts/advisor_council_tab.gd")
const LabourPolicyTabScript := preload("res://scripts/labour_policy_tab.gd")

const ADVISOR_CARD_WIDTH := 260.0
const ADVISOR_CARD_HEIGHT := 460.0
const ADVISOR_PORTRAIT_SIZE := ADVISOR_CARD_WIDTH
const PERMANENT_ADVISOR_CARD_WIDTH := ADVISOR_CARD_WIDTH + 30.0
const PERMANENT_ADVISOR_CARD_HEIGHT := ADVISOR_CARD_HEIGHT + 40.0
const PERMANENT_ADVISOR_PORTRAIT_SIZE := PERMANENT_ADVISOR_CARD_WIDTH
const HEADER_HEIGHT := 56.0
const MISSION_TRACK_POSITIONS := [0.10, 0.30, 0.50, 0.70, 0.90]
const MISSION_TRACK_THRESHOLDS := [2.0, 5.0, 7.0, 9.0, 10.0]
const MISSION_REWARD_CARD_WIDTH := 164.0
const MISSION_REWARD_CARD_HEIGHT := 104.0
const MISSION_REWARD_GAP := 20
const MISSION_REWARD_EDGE_MARGIN := 10

var _labour_buttons: Dictionary = {}
var _policy_buttons: Dictionary = {}
var _policies_grid: GridContainer
var _labour_effects: VBoxContainer
var _labour_indicator: PanelContainer
var _labour_pct_label: Label
var _labour_trend_label: Label
var _labour_amount_label: Label
var _labour_est_label: Label
var _labour_floor_label: Label
var _advisors_root: VBoxContainer
var _advisor_payroll_label: Label
var _advisor_detail_panel: PanelContainer
var _advisor_modifiers_panel: PanelContainer
var _discipline_info_section: VBoxContainer
var _shown_discipline: String = ""
const _DISCIPLINE_NAMES := {"inf": "Influencing", "ops": "Operations", "lead": "Leadership", "inn": "Innovation", "fin": "Finance"}
const _DISCIPLINE_GIVES := {
	"inf": "Markets & government — sale-price boosts, tighter spread, forewarnings, green subsidy, tax relief.",
	"ops": "The production machine — labour, maintenance, energy, transport, retrofits.",
	"lead": "People & organisation — unique labour policies, morale, advisor retention.",
	"inn": "Technology — recipe output by discipline, free tech unlocks, cheaper clean retrofits.",
	"fin": "Capital & treasury — loan interest & term, dividends, tax, land & building purchase.",
}
var _advisor_detail_body: VBoxContainer
var _advisor_detail_advisor_id := ""
var _advisor_missions_content: VBoxContainer
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
	_apply_research_window(self)
	theme_type_variation = &"PanelContainer"
	_build_panel()
	MatchState.labour_multiplier_changed.connect(func(_value: float): _refresh_labour())
	MatchState.workforce_policies_changed.connect(_refresh_policy_buttons)
	MatchState.workforce_policies_changed.connect(_refresh_labour_indicator)
	MatchState.advisors_changed.connect(_rebuild_policy_rows)   # re-gate HR-locked policies
	TurnManager.turn_resolution_completed.connect(_refresh_labour_indicator)
	TurnManager.turn_resolution_completed.connect(_refresh_advisors_tab)
	if not MatchState.advisors_changed.is_connected(_on_advisors_changed):
		MatchState.advisors_changed.connect(_on_advisors_changed)
	if not MatchState.advisor_acquired.is_connected(_on_advisor_acquired):
		MatchState.advisor_acquired.connect(_on_advisor_acquired)
	if not MatchState.advisor_loyalty_changed.is_connected(_on_advisor_loyalty_changed):
		MatchState.advisor_loyalty_changed.connect(_on_advisor_loyalty_changed)
	if not MatchState.advisor_mission_state_changed.is_connected(_on_advisor_mission_state_changed):
		MatchState.advisor_mission_state_changed.connect(_on_advisor_mission_state_changed)
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

	# Advisors first — the council is the panel's headline view (design: People Panel).
	var advisors := _build_advisors_tab()
	advisors.name = "Advisors"
	tabs.add_child(advisors)

	var labour := _build_labour_tab()
	labour.name = "Labour"
	tabs.add_child(labour)

func _build_labour_tab() -> Control:
	# Spectrum-based policy levers (scripts/labour_policy_tab.gd): safety,
	# pensions, bonus and profit share as 3-point spectrums, automation as a
	# toggle. The legacy checkbox-grid machinery below is inert while its node
	# refs stay null (every refresher guards on them) — scheduled for removal
	# together with the legacy advisors code.
	var tab: Control = LabourPolicyTabScript.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return tab

func _build_labour_tab_legacy() -> Control:
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
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_policies_grid = GridContainer.new()
	_policies_grid.columns = 2
	_policies_grid.add_theme_constant_override("h_separation", 10)
	_policies_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(_policies_grid)
	_rebuild_policy_rows()

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
	return outer_scroll

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

	# Shown only when labour reductions bottom out at the LABOUR_FACTOR_MIN floor.
	_labour_floor_label = _label("", "Caption")
	_labour_floor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_labour_floor_label.add_theme_color_override("font_color", DS.PALETTE["OK"])
	_labour_floor_label.visible = false
	vb.add_child(_labour_floor_label)

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

	# Cap notice: labour reductions have bottomed out at the 40% floor.
	if _labour_floor_label != null:
		var at_floor: bool = has and bool(ov.get("at_floor", false))
		_labour_floor_label.visible = at_floor
		if at_floor:
			_labour_floor_label.text = "Maximum labour cost reduction achieved. Further bonuses will not stack below 40% of base cost."

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
			"cost": "Labour +0.5%/turn (max +15%) and maintenance +5%/turn while active, up to +100%.",
			"benefit": "Output +5%.",
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
			"id": MatchState.WORKFORCE_POLICY_LONG_TENURE,
			"name": "Long Tenure Awards",
			"cost": "Labour costs +10% one turn every 10th turn (the awards payout).",
			"benefit": "Labour costs -0.1%/turn while active, max -10%.",
			"requires": "Requires an HR Director advisor.",
		},
		{
			"id": MatchState.WORKFORCE_POLICY_STOCK_OPTIONS,
			"name": "Stock Options",
			"cost": "Dividends grow +0.05%/turn, up to +10% (30% of profit max).",
			"benefit": "Output +0.1%/turn while active, max +5%.",
			"requires": "Requires a Leadership-3 HR Director advisor.",
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

	var policy_id := str(policy.get("id", ""))
	var available: bool = MatchState.is_workforce_policy_available(policy_id)

	var checkbox := UIHelpers.make_custom_checkbox()
	checkbox.button_pressed = MatchState.is_workforce_policy_enabled(policy_id)
	checkbox.disabled = not available
	checkbox.toggled.connect(_on_policy_toggled.bind(policy_id))
	row.add_child(checkbox)
	_policy_buttons[policy_id] = checkbox

	var row_label := _label("Name", "Caption")
	row_label.custom_minimum_size = Vector2(46, 0)
	row_label.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	row.add_child(row_label)

	# Locked HR policies show a padlocked title + the unlock requirement.
	var name_text := str(policy.get("name", ""))
	if not available and policy.has("requires"):
		name_text = "🔒 %s — %s" % [name_text, str(policy.get("requires", ""))]
	var name := _label(name_text, "BuildingName")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not available:
		name.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
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

# Rebuild every policy row (called on advisor seat changes so HR-gated policies
# lock/unlock live).
func _rebuild_policy_rows() -> void:
	if not is_instance_valid(_policies_grid):
		return
	_policy_buttons.clear()
	for child in _policies_grid.get_children():
		child.queue_free()
	for policy in _policy_definitions():
		_policies_grid.add_child(_policy_row(policy))

func _refresh_policy_buttons() -> void:
	for policy_id in _policy_buttons:
		var checkbox: CheckBox = _policy_buttons[policy_id]
		if is_instance_valid(checkbox):
			checkbox.set_pressed_no_signal(MatchState.is_workforce_policy_enabled(str(policy_id)))

func _build_advisors_tab() -> Control:
	# Role-first council view (scripts/advisor_council_tab.gd): pick the seat,
	# then pick the advisor into it. The legacy card-roster machinery below is
	# inert while _advisors_root stays null (every refresher guards on it) —
	# scheduled for removal once the new tab has survived a few sessions.
	var tab: Control = AdvisorCouncilTabScript.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return tab

func _on_advisors_changed() -> void:
	_sync_advisor_lists()
	_refresh_advisors_tab()
	if _advisor_detail_advisor_id != "":
		_refresh_advisor_missions_detail(_advisor_detail_advisor_id)

func _on_advisor_loyalty_changed(advisor_id: String, _loyalty: float) -> void:
	_refresh_advisors_tab()
	if advisor_id == _advisor_detail_advisor_id:
		_refresh_advisor_missions_detail(advisor_id)

func _on_advisor_mission_state_changed(advisor_id: String) -> void:
	_refresh_advisors_tab()
	if advisor_id == _advisor_detail_advisor_id:
		_refresh_advisor_missions_detail(advisor_id)

func _sync_advisor_lists() -> void:
	_permanent_advisors = MatchState.permanent_advisors()
	_available_advisors = MatchState.available_advisors()

func _refresh_advisors_tab() -> void:
	if not is_instance_valid(_advisors_root):
		return
	_sync_advisor_lists()
	_clear_children(_advisors_root)
	_advisors_root.add_child(_advisor_profit_track())
	_advisors_root.add_child(_advisor_payroll_summary())
	# The "+" open-slot swaps the permanent row for the available pool (shown in the
	# same place, not stacked below), with a tertiary button to return.
	if _available_pool_open:
		_advisors_root.add_child(_back_to_permanent_button())
		_available_advisors_section = _add_advisor_section(_advisors_root, "Available Advisors", _available_advisors, false)
	else:
		_available_advisors_section = null
		_add_advisor_section(_advisors_root, "Permanent Advisors", _permanent_advisors, true)

func _back_to_permanent_button() -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "← Back to permanent advisors"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(func() -> void:
		_available_pool_open = false
		_refresh_advisors_tab())
	return btn

# Progress track at the top of the Advisors tab: peak profit/turn + next advisor unlock.
func _advisor_profit_track() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	var peak: float = MatchState.peak_profit_per_turn
	var next_m: int = MatchState.next_advisor_milestone()

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _label("Profit / turn — peak", "Section")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("£%s" % _fmt_amount(peak), "Numeric"))

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	if next_m > 0:
		var prev := 0
		for mm in MatchState.PROFIT_MILESTONES:
			if int(mm) < next_m:
				prev = int(mm)
		bar.min_value = float(prev)
		bar.max_value = float(next_m)
		bar.value = clampf(peak, float(prev), float(next_m))
	else:
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 1.0
	root.add_child(bar)

	var caption := ("Next advisor at £%d / turn" % next_m) if next_m > 0 else "All advisors recruited"
	root.add_child(_label(caption, "Caption"))
	return panel

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

	# Compact cost readout (payroll + N/cap) on the left...
	var cost_box := VBoxContainer.new()
	cost_box.add_theme_constant_override("separation", 0)
	cost_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var cost_title := _label("Advisor cost", "Caption")
	cost_title.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	cost_box.add_child(cost_title)
	_advisor_payroll_label = _label("", "Numeric")
	cost_box.add_child(_advisor_payroll_label)
	_refresh_advisor_payroll_label()
	row.add_child(cost_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# ...and a button to open the combined net-modifiers panel on the right.
	var see_all := Button.new()
	see_all.text = "See all advisor modifiers"
	see_all.focus_mode = Control.FOCUS_NONE
	see_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	see_all.pressed.connect(_open_advisor_modifiers_panel)
	row.add_child(see_all)
	return panel

# Net effect of every seated advisor, aggregated per modifier domain.
func _advisor_net_modifiers() -> Array:
	var by_domain: Dictionary = {}
	for m in Modifiers.active():
		if str(m.get("source", "")) == "advisor_seat":
			var d := str(m.get("domain", ""))
			by_domain[d] = float(by_domain.get(d, 0.0)) + float(m.get("pct", 0.0))
	var out: Array = []
	for d in by_domain:
		if absf(float(by_domain[d])) >= 0.001:
			out.append({"domain": d, "pct": float(by_domain[d])})
	return out

# DS-style overlay listing all advisor modifiers together (net), closeable via the X.
func _open_advisor_modifiers_panel() -> void:
	if is_instance_valid(_advisor_modifiers_panel):
		_advisor_modifiers_panel.queue_free()
	_advisor_modifiers_panel = PanelContainer.new()
	_advisor_modifiers_panel.name = "AdvisorModifiersPanel"
	_advisor_modifiers_panel.custom_minimum_size = Vector2(360, 420)
	_advisor_modifiers_panel.size = Vector2(360, 420)
	_apply_market_window(_advisor_modifiers_panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	_advisor_modifiers_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _label("Advisor Modifiers (net)", "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func() -> void:
		if is_instance_valid(_advisor_modifiers_panel):
			PanelStack.remove(_advisor_modifiers_panel)
			_advisor_modifiers_panel.queue_free())
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var mods := _advisor_net_modifiers()
	if mods.is_empty():
		list.add_child(_label("No advisor modifiers active — seat some advisors to see their combined impact here.", "Caption"))
	else:
		for mod in mods:
			list.add_child(_impact_row(str(mod["domain"]), float(mod["pct"])))

	var host := get_parent()
	if host == null:
		add_child(_advisor_modifiers_panel)
	else:
		host.add_child(_advisor_modifiers_panel)
	PanelStack.push(_advisor_modifiers_panel)
	_advisor_modifiers_panel.move_to_front()

func _refresh_advisor_payroll_label() -> void:
	if not is_instance_valid(_advisor_payroll_label):
		return
	var count := MatchState.permanent_advisor_ids.size()
	var payroll := MatchState.advisor_payroll_per_turn()
	_advisor_payroll_label.text = "%d / %d advisor%s · £%.2f/turn" % [count, MatchState.max_advisor_slots, ("" if count == 1 else "s"), payroll]

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
	var header_text := title_text
	if permanent:
		header_text = "%s  (%d / %d)" % [title_text, MatchState.permanent_advisor_ids.size(), MatchState.max_advisor_slots]
	section.add_child(_advisor_section_header(header_text, scroll))
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
	if permanent and MatchState.permanent_advisor_ids.size() < MatchState.max_advisor_slots:
		row.add_child(_advisor_card({}, true, true))   # "+" hidden once at the cap
	elif not permanent and shown == 0:
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
		if MatchState.is_fired(str(advisor.get("id", ""))):
			card.modulate = Color(1, 1, 1, 0.45)   # dismissed: greyed, opens a read-only profile
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

	var role_text := "" if add_slot else _advisor_assigned_role_label(str(advisor.get("id", "")))
	if role_text != "":
		var role := _label(role_text, "Caption")
		role.name = "AssignedAdvisorRole"
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(role)

	# Available (unhired) cards drop loyalty + the black recommendation box in favour
	# of a stat pentagon and Great-for / Bad-for role rows.
	if not permanent and not add_slot:
		root.add_child(_card_pentagon(advisor))
		var aid := str(advisor.get("id", ""))
		if MatchState.is_fired(aid):
			var cd := _label(_fire_cooldown_text(aid), "Caption")
			cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			root.add_child(cd)
		else:
			var fit := _advisor_role_fit(aid)
			root.add_child(_role_fit_row("Great for", fit["great"], DS.PALETTE["OK"]))
			if not (fit["bad"] as Array).is_empty():
				root.add_child(_role_fit_row("Bad for", fit["bad"], DS.PALETTE["DANGER"]))
		var av_spacer := Control.new()
		av_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(av_spacer)
		_make_click_through(root)
		return card

	if not add_slot:
		# Hired advisors show live loyalty (-10..+10); the pool/detail use the static value.
		var loyalty_val: int = int(round(MatchState.advisor_loyalty_value(str(advisor.get("id", ""))))) if permanent else int(advisor.get("happiness", 0))
		root.add_child(_happiness_row(loyalty_val))

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
	var rec_text := _slot_recommendation(permanent) if add_slot else str(advisor.get("recommendation", ""))
	if not add_slot and MatchState.is_fired(str(advisor.get("id", ""))):
		rec_text = _fire_cooldown_text(str(advisor.get("id", "")))
	var rec_label := _label(rec_text, "Caption")
	rec_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rec_margin.add_child(rec_label)
	_make_click_through(root)
	return card

# Small unlabelled stat pentagon for an advisor card (reuses the detail-panel draw).
func _card_pentagon(advisor: Dictionary) -> Control:
	var stats := MatchState._roster_entry(str(advisor.get("id", "")))
	var radar := Control.new()
	radar.custom_minimum_size = Vector2(0, 104)
	radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radar.draw.connect(_draw_pentagon.bind(radar, stats))
	return radar

# Best-fit / worst-fit seats for an unhired advisor: the 3 strongest seats (tier >= 2)
# and any seats where they'd be a malus (tier 1). Bad is empty when every stat is >= 2.
func _advisor_role_fit(advisor_id: String) -> Dictionary:
	var rows: Array = []
	for seat_id in MatchState.SEAT_DEFINITIONS:
		var seat: Dictionary = MatchState.SEAT_DEFINITIONS[seat_id]
		rows.append({"name": str(seat.get("seat_name", seat_id)), "tier": MatchState.advisor_seat_tier(advisor_id, str(seat_id))})
	rows.sort_custom(func(a, b): return int(a["tier"]) > int(b["tier"]))
	var great: Array = []
	var bad: Array = []
	for r in rows:
		if int(r["tier"]) >= 2 and great.size() < 3:
			great.append(str(r["name"]))
		elif int(r["tier"]) <= 1 and bad.size() < 3:
			bad.append(str(r["name"]))
	return {"great": great, "bad": bad}

# Human phrasing per modifier domain: {noun, good_down} — good_down means a DECREASE
# is the benefit (a cost), so colour follows the sign accordingly.
const _IMPACT_LABELS := {
	"labour_headcount": {"noun": "labour cost", "good_down": true},
	"maintenance": {"noun": "maintenance cost", "good_down": true},
	"building_power": {"noun": "building power use", "good_down": true},
	"transport_cost": {"noun": "transport cost", "good_down": true},
	"transport_throughput": {"noun": "transport throughput", "good_down": false},
	"tax_rate": {"noun": "tax", "good_down": true},
	"market_spread": {"noun": "market buy spread", "good_down": true},
	"market_price": {"noun": "sale prices", "good_down": false},
	"loan_interest": {"noun": "loan interest", "good_down": true},
	"dividend_rate": {"noun": "dividend payouts", "good_down": true},
	"construction_rebate": {"noun": "build & upgrade materials rebate", "good_down": false},
	"purchase_cost": {"noun": "land & building prices", "good_down": true},
	"grid_buy_price": {"noun": "grid power cost", "good_down": true},
	"grid_sell_price": {"noun": "grid power sales", "good_down": false},
}

# Concrete numeric impact of an advisor (bonuses + maluses), one per row, for the
# seat they best demonstrate — plus their trait bonuses beneath.
func _advisor_impact_block(advisor: Dictionary) -> Control:
	var advisor_id := str(advisor.get("id", ""))
	var seat_id := MatchState.advisor_best_effect_seat(advisor_id)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	var rows: Array = MatchState.advisor_seat_effect_list(advisor_id, seat_id)
	if seat_id != "" and not rows.is_empty():
		var seat_name := str(MatchState.SEAT_DEFINITIONS.get(seat_id, {}).get("seat_name", seat_id))
		root.add_child(_label("As %s:" % seat_name, "Caption"))
	for r in rows:
		root.add_child(_impact_row(str(r["domain"]), float(r["pct"])))
	if rows.is_empty():
		root.add_child(_label("No direct modifiers in their best seat.", "Caption"))

	var traits: Array = advisor.get("bonuses", [])
	if not traits.is_empty():
		for t in traits:
			var tl := _label("• %s" % str(t), "Caption")
			tl.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			root.add_child(tl)
	return panel

func _impact_row(domain: String, pct: float) -> Control:
	var meta: Dictionary = _IMPACT_LABELS.get(domain, {"noun": domain, "good_down": true})
	var word := "increase" if pct > 0.0 else "decrease"
	var text := "%.0f%% %s in %s" % [absf(pct), word, str(meta["noun"])]
	var benefit := (pct < 0.0) == bool(meta["good_down"])
	var lbl := _label(text, "Caption")
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", DS.PALETTE["OK"] if benefit else DS.PALETTE["DANGER"])
	return lbl

func _role_fit_row(prefix: String, roles: Array, color: Color) -> Control:
	var lbl := _label("%s: %s" % [prefix, ", ".join(roles)], "Caption")
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", color)
	return lbl

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

func _slot_recommendation(permanent: bool) -> String:
	if permanent:
		return "Click to choose a permanent specialist from the advisor pool."
	return "Click to add this advisor to the permanent team."

func _advisor_assigned_role_label(advisor_id: String) -> String:
	if advisor_id == "":
		return ""
	for seat_id in MatchState.advisor_seats.keys():
		if str(MatchState.advisor_seats[seat_id]) == advisor_id:
			var seat: Dictionary = MatchState.SEAT_DEFINITIONS.get(str(seat_id), {})
			return str(seat.get("seat_name", seat_id))
	return ""

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
		_open_advisor_detail(advisor)   # profile + Confirm Hire; hiring happens from the detail
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
	var advisor_id := str(advisor.get("id", ""))
	_advisor_detail_advisor_id = advisor_id
	_advisor_missions_content = null
	var is_hired: bool = MatchState.permanent_advisor_ids.has(advisor_id)
	var is_fired: bool = MatchState.is_fired(advisor_id)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_advisor_detail_panel.add_child(margin)

	# Outer column: fixed header, scrolling body (capped to the panel height), fixed footer CTA.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_advisor_detail_header_input)
	outer.add_child(header)
	var title := _label(str(advisor.get("role", "Advisor")), "Title")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(_close_advisor_detail)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_advisor_detail_body = VBoxContainer.new()
	_advisor_detail_body.add_theme_constant_override("separation", 12)
	_advisor_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_fired:
		_advisor_detail_body.modulate = Color(1, 1, 1, 0.55)   # dismissed profile reads greyed
	scroll.add_child(_advisor_detail_body)

	if is_fired:
		_advisor_detail_body.add_child(_label("On leave — dismissed advisor returns to the pool in %d turn%s." % [
			MatchState.fire_cooldown_remaining(advisor_id), "" if MatchState.fire_cooldown_remaining(advisor_id) == 1 else "s"], "Caption"))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_advisor_detail_body.add_child(top)

	var portrait_col := VBoxContainer.new()
	portrait_col.custom_minimum_size = Vector2(180, 0)
	portrait_col.add_theme_constant_override("separation", 10)
	top.add_child(portrait_col)
	portrait_col.add_child(_portrait_panel(advisor, true, false, Vector2(180, 180)))
	portrait_col.add_child(_recommendation_box(str(advisor.get("recommendation", ""))))
	portrait_col.add_child(_stat_pentagon(advisor))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)

	var bio := _label(str(advisor.get("bio", "")), "Body")
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(bio)

	# Collapsible sections — scroll down to reach Seats and Missions.
	_advisor_detail_body.add_child(_collapsible("Agenda", _agenda_block(advisor)))
	_advisor_detail_body.add_child(_collapsible("Impact", _advisor_impact_block(advisor)))
	_advisor_detail_body.add_child(_collapsible("Seats", _seat_assignment_section(advisor, false)))
	_advisor_missions_content = VBoxContainer.new()
	_advisor_missions_content.name = "AdvisorMissionsContent"
	_advisor_missions_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_advisor_missions_detail(advisor_id)
	_advisor_detail_body.add_child(_collapsible("Missions", _advisor_missions_content, false))

	outer.add_child(_advisor_detail_footer(advisor, is_hired, is_fired))

func _refresh_advisor_missions_detail(advisor_id: String) -> void:
	if advisor_id == "" or not is_instance_valid(_advisor_missions_content):
		return
	_clear_children(_advisor_missions_content)
	var fresh := MatchState.get_advisor(advisor_id)
	if fresh.is_empty():
		return
	_advisor_missions_content.add_child(_quest_diagram(
		fresh.get("missions", fresh.get("quests", [])),
		MatchState.advisor_loyalty_value(advisor_id)))

# A titled section that folds away when its header is tapped.
func _collapsible(title_text: String, content: Control, start_open: bool = true) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.toggle_mode = true
	head.button_pressed = start_open
	head.add_theme_font_size_override("font_size", 15)
	head.text = ("▾  " if start_open else "▸  ") + title_text
	content.visible = start_open
	head.toggled.connect(func(on: bool) -> void:
		content.visible = on
		head.text = ("▾  " if on else "▸  ") + title_text)
	box.add_child(head)
	box.add_child(content)
	return box

func _fire_cooldown_text(advisor_id: String) -> String:
	var n := MatchState.fire_cooldown_remaining(advisor_id)
	return "Re-hireable in %d turn%s" % [n, "" if n == 1 else "s"]

# Bottom CTA: Confirm Hire for an available advisor, Fire Advisor for an employed
# one, or a disabled cooldown marker while a fired advisor is benched.
func _advisor_detail_footer(advisor: Dictionary, is_hired: bool, is_fired: bool) -> Control:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 40)
	if is_fired:
		btn.text = _fire_cooldown_text(str(advisor.get("id", "")))
		btn.disabled = true
	elif is_hired:
		btn.text = "Fire Advisor"
		btn.add_theme_color_override("font_color", Color(0.86, 0.28, 0.24))
		btn.pressed.connect(_on_fire_advisor_pressed.bind(advisor))
	elif MatchState.permanent_advisor_ids.size() >= MatchState.max_advisor_slots:
		btn.text = "No free advisor slot"
		btn.disabled = true
	else:
		btn.text = "Confirm Hire"
		btn.pressed.connect(_on_confirm_hire_pressed.bind(advisor))
	return btn

func _on_confirm_hire_pressed(advisor: Dictionary) -> void:
	if MatchState.hire_advisor(str(advisor.get("id", ""))):
		_close_advisor_detail()
		_available_pool_open = true
		_refresh_advisors_tab()

func _on_fire_advisor_pressed(advisor: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Fire Advisor"
	dialog.dialog_text = "Dismiss %s?\nThis frees their seat. They will sit out %d turns before they can be re-hired." % [str(advisor.get("name", "this advisor")), MatchState.FIRE_COOLDOWN_TURNS]
	dialog.ok_button_text = "Fire"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		MatchState.fire_advisor(str(advisor.get("id", "")))
		dialog.queue_free()
		if is_instance_valid(_advisor_detail_panel) and _advisor_detail_panel.visible:
			_build_advisor_detail(advisor)   # re-render greyed, footer now "Dismissed"
		_refresh_advisors_tab())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()

func _stat_pentagon(advisor: Dictionary) -> Control:
	var advisor_id := str(advisor.get("id", ""))
	var stats := MatchState._roster_entry(advisor_id)
	var col := VBoxContainer.new()
	col.name = "StatPentagon"
	col.add_theme_constant_override("separation", 4)
	col.add_child(_label("Disciplines  (tap a label)", "Caption"))

	var radar := Control.new()
	radar.custom_minimum_size = Vector2(176, 168)
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	radar.draw.connect(_draw_pentagon.bind(radar, stats))
	var keys := ["inf", "ops", "lead", "inn", "fin"]
	var names := ["Inf", "Ops", "Lead", "Inn", "Fin"]
	var center := Vector2(88.0, 84.0)
	var label_r: float = minf(176.0, 168.0) * 0.32 + 13.0
	for i in 5:
		var ang := -PI / 2.0 + float(i) * TAU / 5.0
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "%s %d" % [names[i], int(stats.get(keys[i], 1))]
		btn.add_theme_font_size_override("font_size", 11)
		btn.size = Vector2(42, 18)
		btn.position = center + Vector2(cos(ang), sin(ang)) * label_r - Vector2(21, 9)
		btn.pressed.connect(_on_discipline_label.bind(keys[i], advisor_id))
		radar.add_child(btn)
	col.add_child(radar)

	_discipline_info_section = VBoxContainer.new()
	_discipline_info_section.name = "DisciplineInfo"
	_discipline_info_section.custom_minimum_size = Vector2(100, 0)
	_discipline_info_section.add_theme_constant_override("separation", 3)
	col.add_child(_discipline_info_section)
	_shown_discipline = ""
	return col

func _draw_pentagon(node: Control, stats: Dictionary) -> void:
	var keys := ["inf", "ops", "lead", "inn", "fin"]
	var center: Vector2 = node.size * 0.5
	var radius: float = minf(node.size.x, node.size.y) * 0.32
	var grid := Color(1, 1, 1, 0.14)
	for ring in [1.0 / 3.0, 2.0 / 3.0, 1.0]:
		var ring_pts := PackedVector2Array()
		for i in 5:
			var ang := -PI / 2.0 + float(i) * TAU / 5.0
			ring_pts.append(center + Vector2(cos(ang), sin(ang)) * radius * float(ring))
		ring_pts.append(ring_pts[0])
		node.draw_polyline(ring_pts, grid, 1.0)
	for i in 5:
		var ang := -PI / 2.0 + float(i) * TAU / 5.0
		node.draw_line(center, center + Vector2(cos(ang), sin(ang)) * radius, grid, 1.0)
	var poly := PackedVector2Array()
	for i in 5:
		var ang := -PI / 2.0 + float(i) * TAU / 5.0
		var v: float = clampf(float(stats.get(keys[i], 1)) / 3.0, 0.0, 1.0)
		poly.append(center + Vector2(cos(ang), sin(ang)) * radius * v)
	var accent: Color = DS.PALETTE.get("ACCENT", Color(0.9, 0.85, 0.7))
	node.draw_colored_polygon(poly, Color(accent.r, accent.g, accent.b, 0.28))
	var outline := poly.duplicate()
	outline.append(poly[0])
	node.draw_polyline(outline, Color(accent.r, accent.g, accent.b, 0.95), 5.0)
	for i in 5:
		node.draw_circle(poly[i], 4.5, Color(accent.r, accent.g, accent.b, 1.0))

# Tapping a discipline label expands a narrow multi-row info section: what the
# discipline gives, how this advisor performs, the seats it governs, and bonuses.
func _on_discipline_label(disc: String, advisor_id: String) -> void:
	if not is_instance_valid(_discipline_info_section):
		return
	_clear_children(_discipline_info_section)
	if _shown_discipline == disc:
		_shown_discipline = ""   # tap again to collapse
		return
	_shown_discipline = disc
	var a := MatchState._roster_entry(advisor_id)
	var stat := int(a.get(disc, 1))
	var tier_word: String = ["-", "malus", "modest", "strong"][clampi(stat, 0, 3)]
	_discipline_info_section.add_child(_label(str(_DISCIPLINE_NAMES.get(disc, disc)), "Section"))
	_discipline_info_section.add_child(_wrapped(str(_DISCIPLINE_GIVES.get(disc, "")), "Caption"))
	_discipline_info_section.add_child(_wrapped("This advisor: %s  (%d / 3)" % [tier_word, stat], "Body"))
	var seat_names: Array = []
	for seat_id in MatchState.SEAT_DEFINITIONS:
		var seat: Dictionary = MatchState.SEAT_DEFINITIONS[seat_id]
		if str(seat.get("governs", "")) == disc or (seat.get("flexible", []) as Array).has(disc):
			seat_names.append(str(seat.get("seat_name", seat_id)))
	if not seat_names.is_empty():
		_discipline_info_section.add_child(_wrapped("Seats: " + ", ".join(seat_names), "Caption"))
	var bonuses: Array = MatchState.get_advisor(advisor_id).get("bonuses", [])
	if not bonuses.is_empty():
		_discipline_info_section.add_child(_label("Bonuses", "Caption"))
		for b in bonuses:
			_discipline_info_section.add_child(_wrapped("- " + str(b), "Caption"))

func _wrapped(text: String, variation: String) -> Label:
	var l := _label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(100, 0)
	return l

# Seat picker: one row per seat with this advisor's governing tier + assign/unassign.
func _seat_assignment_section(advisor: Dictionary, with_header: bool = true) -> Control:
	var advisor_id := str(advisor.get("id", ""))
	var hired: bool = MatchState.permanent_advisor_ids.has(advisor_id)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	panel.name = "SeatAssignmentSection"
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	if with_header:
		root.add_child(_label("Seats  (%d / %d filled)" % [MatchState.advisor_seats.size(), MatchState.max_advisor_slots], "Section"))
	else:
		root.add_child(_label("%d / %d seats filled" % [MatchState.advisor_seats.size(), MatchState.max_advisor_slots], "Caption"))
	if not hired:
		root.add_child(_label("Hire this advisor to assign a seat.", "Caption"))
	for seat_id in MatchState.SEAT_DEFINITIONS:
		root.add_child(_seat_row(str(seat_id), advisor_id, hired))
	return panel

func _seat_row(seat_id: String, advisor_id: String, hired: bool) -> Control:
	var seat: Dictionary = MatchState.SEAT_DEFINITIONS[seat_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var occupant := MatchState.get_advisor_in_seat(seat_id)
	var here: bool = occupant == advisor_id
	var tier: int = MatchState.advisor_seat_tier(advisor_id, seat_id)
	var tier_word: String = ["-", "malus", "modest", "strong"][clampi(tier, 0, 3)]
	var name_text := str(seat.get("seat_name", seat_id))
	if occupant != "" and not here:
		name_text += " · " + str(MatchState.get_advisor(occupant).get("name", occupant))
	var name_lbl := _label(name_text, "Body")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	var disc := MatchState.advisor_seat_governing_discipline(advisor_id, seat_id)
	var preview := _label("%s %s" % [disc.to_upper(), tier_word], "Caption")
	preview.custom_minimum_size = Vector2(108, 0)
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(preview)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(84, 28)
	if here:
		btn.text = "Unassign"
		btn.pressed.connect(_on_seat_unassign.bind(seat_id, advisor_id))
	else:
		btn.text = "Assign"
		var slot_full: bool = not MatchState.advisor_seats.has(seat_id) and MatchState.advisor_seats.size() >= MatchState.max_advisor_slots
		btn.disabled = (not hired) or slot_full
		btn.pressed.connect(_on_seat_assign.bind(seat_id, advisor_id))
	row.add_child(btn)
	return row

func _on_seat_assign(seat_id: String, advisor_id: String) -> void:
	if MatchState.assign_advisor_to_seat(seat_id, advisor_id):
		_reopen_advisor_detail(advisor_id)

func _on_seat_unassign(seat_id: String, advisor_id: String) -> void:
	if MatchState.unassign_seat(seat_id):
		_reopen_advisor_detail(advisor_id)

func _reopen_advisor_detail(advisor_id: String) -> void:
	var a := MatchState.get_advisor(advisor_id)
	if not a.is_empty() and is_instance_valid(_advisor_detail_panel):
		_build_advisor_detail(a)

func _on_advisor_acquired(advisor_id: String) -> void:
	var a := MatchState.get_advisor(advisor_id)
	MatchState.request_toast("New advisor: %s" % str(a.get("name", advisor_id)), "success")

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
	if title_text != "":
		root.add_child(_label(title_text, "Section"))
	var body := _label(body_text, "Caption")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(body)
	return panel

# The Agenda section: flavour line + the concrete loyalty drivers (signed points,
# per-turn or one-off) so it's clear exactly how to please/annoy this advisor.
func _agenda_block(advisor: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Inset"
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	margin.add_child(root)

	var flavour := str(advisor.get("agenda", "")).strip_edges()
	if flavour != "":
		var fl := _wrapped(flavour, "Caption")
		fl.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		root.add_child(fl)

	var rows: Array = MatchState.advisor_agenda_rows(str(advisor.get("id", "")))
	var likes := rows.filter(func(r): return bool(r.get("benefit", false)))
	var dislikes := rows.filter(func(r): return not bool(r.get("benefit", false)))
	if not likes.is_empty():
		root.add_child(_label("Raises loyalty", "Caption"))
		for r in likes:
			root.add_child(_agenda_row_label(r))
	if not dislikes.is_empty():
		root.add_child(_label("Lowers loyalty", "Caption"))
		for r in dislikes:
			root.add_child(_agenda_row_label(r))
	var note := _label("Loyalty also drifts 0.1/turn back toward 0.", "Caption")
	note.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)
	return panel

func _agenda_row_label(r: Dictionary) -> Label:
	var pts: float = float(r.get("points", 0.0))
	var mag: String = "%.1f" % absf(pts)
	if mag.ends_with(".0"):
		mag = mag.substr(0, mag.length() - 2)
	var suffix: String = "/turn" if bool(r.get("per_turn", false)) else ""
	var text: String = "%s%s%s   %s" % ["+" if pts >= 0.0 else "−", mag, suffix, str(r.get("text", ""))]
	var lbl := _label(text, "Caption")
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", DS.PALETTE["OK"] if bool(r.get("benefit", false)) else DS.PALETTE["DANGER"])
	return lbl

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

func _quest_diagram(quests: Variant, current_loyalty: float = 0.0) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(0, 262)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_label("Missions", "Section"))

	var quest_list: Array = quests if quests is Array else []
	root.add_child(_mission_plaque_row(quest_list))
	root.add_child(_loyalty_bar(current_loyalty, quest_list))
	root.add_child(_mission_rewards_row(quest_list))
	return panel

func _mission_plaque_row(quest_list: Array) -> Control:
	var row := HBoxContainer.new()
	row.name = "MissionPlaqueRow"
	row.custom_minimum_size = Vector2(0, 58)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	for i in range(5):
		var wrapper := CenterContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(wrapper)
		wrapper.add_child(_mission_plaque(_mission_quest_at(quest_list, i)))
	return row

# A mission-progress loyalty track. Its milestone labels are centered under the five
# mission slots, while the fill interpolates through the actual loyalty thresholds.
func _loyalty_bar(current_loyalty: float, quests: Variant = []) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_label("Loyalty  (now %+d)" % int(round(current_loyalty)), "Caption"))

	var area := Control.new()
	area.custom_minimum_size = Vector2(0, 54)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(area)

	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.set_anchors_preset(Control.PRESET_TOP_WIDE)
	track.offset_top = 7
	track.offset_bottom = 16
	area.add_child(track)

	# Mission V hold zone: the span between mission IV and mission V markers.
	var accent: Color = DS.PALETTE.get("ACCENT", Color("#D9B35A"))
	var zone := ColorRect.new()
	zone.color = Color(accent.r, accent.g, accent.b, 0.28)
	zone.anchor_left = float(MISSION_TRACK_POSITIONS[3])
	zone.anchor_right = float(MISSION_TRACK_POSITIONS[4])
	zone.offset_top = 7
	zone.offset_bottom = 16
	area.add_child(zone)

	var frac: float = _loyalty_track_fraction(current_loyalty)
	var fill := ColorRect.new()
	fill.color = DS.PALETTE.get("OK", Color(0.3, 0.7, 0.4))
	fill.anchor_right = frac
	fill.offset_top = 7
	fill.offset_bottom = 16
	area.add_child(fill)

	var quest_list: Array = quests if quests is Array else []
	for i in range(5):
		var x: float = float(MISSION_TRACK_POSITIONS[i])
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.75)
		tick.anchor_left = x
		tick.anchor_right = x
		tick.offset_left = -1
		tick.offset_right = 1
		tick.offset_top = 3
		tick.offset_bottom = 20
		area.add_child(tick)
		var lbl := _label(_mission_milestone_label(i, _mission_quest_at(quest_list, i)), "Caption")
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.anchor_left = x
		lbl.anchor_right = x
		lbl.offset_left = -34
		lbl.offset_right = 34
		lbl.offset_top = 23
		lbl.offset_bottom = 52
		area.add_child(lbl)

	var v_note := _label(_mission_v_requirement(quest_list), "Caption")
	v_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v_note.add_theme_font_size_override("font_size", 10)
	v_note.add_theme_color_override("font_color", accent)
	col.add_child(v_note)
	return col

func _mission_rewards_row(quest_list: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "MissionRewardsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, MISSION_REWARD_CARD_HEIGHT + 12.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.name = "MissionRewardsMargin"
	margin.add_theme_constant_override("margin_left", MISSION_REWARD_EDGE_MARGIN)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_right", MISSION_REWARD_EDGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", 2)
	scroll.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "MissionRewardsRow"
	row.custom_minimum_size = Vector2(
		MISSION_REWARD_CARD_WIDTH * 5.0 + float(MISSION_REWARD_GAP * 4),
		MISSION_REWARD_CARD_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", MISSION_REWARD_GAP)
	margin.add_child(row)
	for i in range(5):
		row.add_child(_mission_reward_card(_mission_quest_at(quest_list, i)))
	return scroll

func _mission_reward_card(quest: Dictionary) -> Control:
	var state := str(quest.get("state", "locked"))
	var panel := PanelContainer.new()
	panel.name = "MissionReward_%s" % str(quest.get("roman", "I"))
	panel.custom_minimum_size = Vector2(MISSION_REWARD_CARD_WIDTH, MISSION_REWARD_CARD_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var border := Color(1, 1, 1, 0.16)
	if state == "completed":
		border = DS.PALETTE.get("OK", Color("#66BA78"))
	elif state == "next":
		border = DS.PALETTE.get("ACCENT", Color("#D9B35A"))
	panel.add_theme_stylebox_override("panel", _round_box(Color(0, 0, 0, 0.28), border, 6, 1, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_theme_constant_override("separation", 3)
	margin.add_child(root)

	var caption := _label("Mission %s Reward" % str(quest.get("roman", "I")), "Caption")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	root.add_child(caption)

	var reward := _label(str(quest.get("reward", "-")), "Caption")
	reward.name = "MissionRewardText"
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward.add_theme_font_size_override("font_size", 10)
	if state == "locked":
		reward.modulate = Color(1, 1, 1, 0.68)
	root.add_child(reward)
	return panel

func _mission_plaque(quest: Dictionary) -> Control:
	var state := str(quest.get("state", "locked"))
	var plaque := PanelContainer.new()
	plaque.name = "MissionPlaque_%s" % str(quest.get("roman", "I"))
	plaque.custom_minimum_size = Vector2(58, 54)
	plaque.add_theme_stylebox_override("panel", _mission_style(state, quest.get("color", Color("#56687C"))))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	plaque.add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(root)

	var roman := _label(str(quest.get("roman", "I")), "Section")
	roman.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roman.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roman.add_theme_font_size_override("font_size", 20)
	root.add_child(roman)
	return plaque

func _mission_quest_at(quest_list: Array, index: int) -> Dictionary:
	if index >= 0 and index < quest_list.size() and quest_list[index] is Dictionary:
		return quest_list[index]
	return {
		"roman": ["I", "II", "III", "IV", "V"][clampi(index, 0, 4)],
		"title": "Mission",
		"state": "locked",
		"color": Color("#56687C"),
		"reward": "-",
		"req_text": "",
	}

func _loyalty_track_fraction(current_loyalty: float) -> float:
	var value := clampf(current_loyalty, 0.0, 10.0)
	var previous_threshold := 0.0
	var previous_position := 0.0
	for i in range(MISSION_TRACK_THRESHOLDS.size()):
		var threshold := float(MISSION_TRACK_THRESHOLDS[i])
		var position := float(MISSION_TRACK_POSITIONS[i])
		if value <= threshold:
			var span := threshold - previous_threshold
			if is_equal_approx(span, 0.0):
				return position
			var t := clampf((value - previous_threshold) / span, 0.0, 1.0)
			return lerpf(previous_position, position, t)
		previous_threshold = threshold
		previous_position = position
	return 1.0

func _mission_milestone_label(index: int, quest: Dictionary) -> String:
	var roman := str(quest.get("roman", ["I", "II", "III", "IV", "V"][clampi(index, 0, 4)]))
	if index < MISSION_TRACK_THRESHOLDS.size() - 1:
		return "%s\n%d" % [roman, int(MISSION_TRACK_THRESHOLDS[index])]
	return "%s\n%d+ %dt" % [roman, int(MatchState.MISSION5_LOYALTY), int(MatchState.MISSION5_STREAK_TURNS)]

func _mission_v_requirement(quest_list: Array) -> String:
	var quest := _mission_quest_at(quest_list, 4)
	var req := str(quest.get("req_text", "")).strip_edges()
	if req == "":
		req = "loyalty %d+ for %d turns" % [int(MatchState.MISSION5_LOYALTY), int(MatchState.MISSION5_STREAK_TURNS)]
	return "V: %s" % req

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
	_advisor_detail_advisor_id = ""
	_advisor_missions_content = null
	_advisor_detail_dragging = false

func _on_visibility_changed() -> void:
	if visible:
		_apply_research_window(self)
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

# Cap the main People panel to the ResearchPanel's vertical band (top 32, bottom
# viewport-130), centred horizontally. Tab contents scroll within this fixed height.
func _apply_research_window(control: Control) -> void:
	var vp := get_viewport_rect().size
	var w := minf(1220.0, vp.x - 60.0)
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = maxf(0.0, (vp.x - w) / 2.0)
	control.offset_right = control.offset_left + w
	control.offset_top = 32.0
	control.offset_bottom = maxf(232.0, vp.y - 130.0)

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
