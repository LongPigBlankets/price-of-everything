extends Control
## The People panel's Labour tab, restyled to the "People Panel" design's lever
## language: policies grouped into 3-point SPECTRUMS with their effects spelled
## out under the selected option, instead of a flat checkbox grid.
##
##   Work effort    0.8x Lean | 1.0x Standard | 1.2x Overtime   (labour slider)
##   Safety         Minimal | Standard | High                    (existing trio)
##   Pensions       Minimum legal | Industry average | Generous
##   Annual bonus   None | Small | Generous
##   Profit share   None | 5% | 10%
##   Automation     Push / Don't push (toggle)
##
## Every spectrum point moves real numbers through MatchState workforce policies
## (the four former placeholder rungs were wired 2026-08). Read-only against the
## sim (rule #5): every change goes through MatchState (set_labour_multiplier /
## set_workforce_policy_enabled).

const _CARD_BORDER := Color("#1C3149")     # card chrome, mirrors advisor_council_tab

var _root: HBoxContainer
var _refresh_queued := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	_root = HBoxContainer.new()
	_root.add_theme_constant_override("separation", 22)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_root)
	MatchState.workforce_policies_changed.connect(_queue_refresh)
	MatchState.labour_multiplier_changed.connect(func(_v: float) -> void: _queue_refresh())
	MatchState.advisors_changed.connect(_queue_refresh)   # HR gating on Other policies
	TurnManager.turn_resolution_completed.connect(_queue_refresh)
	visibility_changed.connect(_queue_refresh)
	_rebuild()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if is_visible_in_tree():
		_rebuild()

# ── current selections derived from sim state ───────────────────────────────
func _safety_key() -> String:
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_STRICT_SAFETY):
		return "high"
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_LAX_SAFETY):
		return "minimal"
	return "standard"

func _pensions_key() -> String:
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS):
		return "generous"
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_PENSIONS_MINIMUM):
		return "minimum"
	return "average"

func _bonus_key() -> String:
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_BONUS):
		return "generous"
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_SMALL_BONUS):
		return "small"
	return "none"

func _profit_key() -> String:
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		return "five"
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_PROFIT_SHARE_10):
		return "ten"
	return "none"

## Pick one policy id out of a mutually-exclusive group ("" = none of them).
func _pick_exclusive(group: Array, chosen: String) -> void:
	for pid in group:
		if str(pid) != chosen:
			MatchState.set_workforce_policy_enabled(str(pid), false)
	if chosen != "":
		MatchState.set_workforce_policy_enabled(chosen, true)

# ── rebuild ─────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	_root.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	_root.add_child(right)

	left.add_child(_sec_label("WORKFORCE POLICIES"))
	_build_effort(left)
	_build_idle_pay(left)
	_build_safety(left)
	_build_pensions(left)
	_build_bonus(left)
	_build_profit_share(left)
	_build_automation(left)

	_build_labour_costs(right)
	_build_other_policies(right)

# ── left column: the spectrums ───────────────────────────────────────────────
func _build_effort(parent: Control) -> void:
	var v := MatchState.labour_multiplier
	var key := "std"
	if v < 0.999:
		key = "lean"
	elif v > 1.001:
		key = "over"
	parent.add_child(_spectrum("Work effort", [
		{"key": "lean", "label": "0.8x Lean",
			"caption": "Salary cost −20% · output pressure −2%/turn, down to −30%.",
			"pick": func() -> void: MatchState.set_labour_multiplier(0.8)},
		{"key": "std", "label": "1.0x Standard",
			"caption": "Salary cost ±0% · output pressure recovers 1%/turn toward 0%.",
			"pick": func() -> void: MatchState.set_labour_multiplier(1.0)},
		{"key": "over", "label": "1.2x Overtime",
			"caption": "Salary cost +20% · output momentum +1%/turn, up to +10%.",
			"pick": func() -> void: MatchState.set_labour_multiplier(1.2)},
	], key))

## "Worker pay while not running" — what a workforce is owed on a turn its building produced
## nothing. Sits beside Work effort because both price the same people, just in opposite
## directions: one buys more output, this one stops paying for output that never came.
func _build_idle_pay(parent: Control) -> void:
	var share := MatchState.idle_labour_pay_share
	var key := "full"
	if share < 0.6:
		key = "half"
	elif share < 0.9:
		key = "most"
	parent.add_child(_spectrum("Worker pay while building not running", [
		{"key": "half", "label": "50%",
			"caption": "A building that made nothing this turn pays half its wage bill. Cheapest, and hardest on the workforce.",
			"pick": func() -> void: MatchState.set_idle_labour_pay_share(0.5)},
		{"key": "most", "label": "75%",
			"caption": "Most of the wage bill is paid through an idle turn.",
			"pick": func() -> void: MatchState.set_idle_labour_pay_share(0.75)},
		{"key": "full", "label": "100%",
			"caption": "Workers are paid in full whether the line runs or not.",
			"pick": func() -> void: MatchState.set_idle_labour_pay_share(1.0)},
	], key))

func _build_safety(parent: Control) -> void:
	var group := [MatchState.WORKFORCE_POLICY_LAX_SAFETY, MatchState.WORKFORCE_POLICY_STANDARD_SAFETY, MatchState.WORKFORCE_POLICY_STRICT_SAFETY]
	parent.add_child(_spectrum("Safety standards", [
		{"key": "minimal", "label": "Minimal",
			"caption": "Output +5% · labour +0.5%/turn (max +15%) · maintenance +5%/turn while active, up to +100%.",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_LAX_SAFETY)},
		{"key": "standard", "label": "Standard",
			"caption": "Regulation compliance — no output or labour cost change.",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_STANDARD_SAFETY)},
		{"key": "high", "label": "High",
			"caption": "Output −10% · labour costs fall −0.5%/turn while active, down to −15%.",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_STRICT_SAFETY)},
	], _safety_key()))

func _build_pensions(parent: Control) -> void:
	var third := MatchState.workforce_policy_game_third_turns()
	var group := [MatchState.WORKFORCE_POLICY_PENSIONS_MINIMUM, MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS]
	parent.add_child(_spectrum("Pensions", [
		{"key": "minimum", "label": "Minimum legal",
			"caption": "Labour costs fall −0.1%/turn while active (max −5%) · output drifts −0.05%/turn as people leave (max −5%).",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_PENSIONS_MINIMUM)},
		{"key": "average", "label": "Industry average",
			"caption": "The baseline — no modifiers either way.",
			"pick": func() -> void: _pick_exclusive(group, "")},
		{"key": "generous", "label": "Generous",
			"caption": "Output +0.05%%/turn (max +5%%) · labour costs ramp +0.1%%→+0.4%%/turn as the game ages (thirds of %d turns)." % (third * 3),
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS)},
	], _pensions_key()))

func _build_bonus(parent: Control) -> void:
	var group := [MatchState.WORKFORCE_POLICY_SMALL_BONUS, MatchState.WORKFORCE_POLICY_ANNUAL_BONUS]
	parent.add_child(_spectrum("Annual bonus", [
		{"key": "none", "label": "No annual bonus",
			"caption": "Nothing paid, nothing gained.",
			"pick": func() -> void: _pick_exclusive(group, "")},
		{"key": "small", "label": "Small annual bonus",
			"caption": "Labour costs +2.5% · output +10% every 10th turn (the bonus month).",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_SMALL_BONUS)},
		{"key": "generous", "label": "Generous annual bonus",
			"caption": "Labour costs +5% · output +20% every 10th turn (the bonus month).",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_ANNUAL_BONUS)},
	], _bonus_key()))

func _build_profit_share(parent: Control) -> void:
	var group := [MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, MatchState.WORKFORCE_POLICY_PROFIT_SHARE_10]
	parent.add_child(_spectrum("Profit share", [
		{"key": "none", "label": "No profit share",
			"caption": "Profits stay with the company.",
			"pick": func() -> void: _pick_exclusive(group, "")},
		{"key": "five", "label": "5% profit share",
			"caption": "Pay 5% of post-tax, post-dividend profit to workers · output +10%.",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE)},
		{"key": "ten", "label": "10% profit share",
			"caption": "Pay 10% of post-tax, post-dividend profit to workers · output +15%.",
			"pick": func() -> void: _pick_exclusive(group, MatchState.WORKFORCE_POLICY_PROFIT_SHARE_10)},
	], _profit_key()))

func _build_automation(parent: Control) -> void:
	var on := MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_PUSH_AUTOMATION)
	parent.add_child(_spectrum("Automation", [
		{"key": "push", "label": "Push for automation",
			"caption": "Labour costs fall −0.2%/turn while active (max −15%) · maintenance +2%/turn (max +10%).",
			"pick": func() -> void: MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_PUSH_AUTOMATION, true)},
		{"key": "no_push", "label": "Don't push for automation",
			"caption": "Keep the current balance of hands and machines.",
			"pick": func() -> void: MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_PUSH_AUTOMATION, false)},
	], "push" if on else "no_push"))

## A titled row of mutually-exclusive segment buttons with the SELECTED
## option's effect spelled out underneath ("effects clear").
func _spectrum(title: String, options: Array, selected_key: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	box.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var caption := ""
	for opt in options:
		var o: Dictionary = opt
		var on := str(o.get("key", "")) == selected_key
		if on:
			caption = str(o.get("caption", ""))
		var b := Button.new()
		b.text = str(o.get("label", ""))
		b.toggle_mode = true
		b.set_pressed_no_signal(on)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		if on:
			# Selected segment matches the DS selected-tab treatment: cream fill, navy text.
			var sel := StyleBoxFlat.new()
			sel.bg_color = DS.PALETTE.ACCENT
			sel.border_color = DS.PALETTE.ACCENT_DIM
			sel.set_border_width_all(1)
			sel.set_corner_radius_all(8)
			sel.set_content_margin_all(8)
			for state in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(state, sel)
			for cname in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
				b.add_theme_color_override(cname, DS.PALETTE.BG_PANEL)
		var pick: Callable = o.get("pick", Callable())
		b.pressed.connect(func() -> void:
			if not pick.is_null():
				pick.call()
			_queue_refresh())
		row.add_child(b)
	var cap := Label.new()
	cap.text = caption
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	box.add_child(cap)
	return box

# ── right column: live labour costs + the remaining toggles ─────────────────
func _build_labour_costs(parent: Control) -> void:
	parent.add_child(_sec_label("LABOUR COST · PER TURN"))
	var card := _card_panel()
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var ov: Dictionary = Production.labour_overview()
	if not bool(ov.get("has_buildings", false)):
		col.add_child(_dim_label("No player buildings yet — labour costs start with your first build.", 12))
		return
	var current := float(ov.get("current", 0.0))
	var base := float(ov.get("base_total", 0.0))
	var est := float(ov.get("est_ten", current))
	var pct := (current / base * 100.0) if base > 0.0 else 100.0
	var now_row := HBoxContainer.new()
	now_row.add_theme_constant_override("separation", 8)
	col.add_child(now_row)
	var amount := Label.new()
	amount.text = "£%.2f" % current
	amount.theme_type_variation = &"Numeric"
	amount.add_theme_font_size_override("font_size", 24)
	amount.add_theme_color_override("font_color", DS.PALETTE.DANGER if pct > 100.0 else DS.PALETTE.OK)
	now_row.add_child(amount)
	now_row.add_child(_dim_label("%.0f%% of base" % pct, 13))
	var trend := est - current
	var trend_l := _dim_label("10-turn estimate £%.2f (%s%.2f)" % [est, "+" if trend >= 0.0 else "−", absf(trend)], 12)
	trend_l.add_theme_color_override("font_color", DS.PALETTE.DANGER if trend > 0.005 else (DS.PALETTE.OK if trend < -0.005 else DS.PALETTE.TEXT_MUTED))
	col.add_child(trend_l)
	if bool(ov.get("at_floor", false)):
		var floor_l := _dim_label("Maximum labour reduction reached — further bonuses will not stack below 40% of base.", 11)
		floor_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		floor_l.add_theme_color_override("font_color", DS.PALETTE.WARN)
		col.add_child(floor_l)

func _build_other_policies(parent: Control) -> void:
	parent.add_child(_sec_label("OTHER POLICIES"))
	var card := _card_panel()
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var defs := [
		{"id": MatchState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, "name": "Extended Annual Leave",
			"tip": "Output −5% every 10th turn · labour −0.1%/turn while active (max −5%)."},
		{"id": MatchState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, "name": "Generous Parental Leave",
			"tip": "Output −5% for 10 turns every other 10 · labour −0.1%/turn while active (max −5%)."},
		{"id": MatchState.WORKFORCE_POLICY_LONG_TENURE, "name": "Long Tenure Awards",
			"tip": "Labour +10% every 10th turn (payout) · labour −0.1%/turn while active (max −10%). Requires an HR Director."},
		{"id": MatchState.WORKFORCE_POLICY_STOCK_OPTIONS, "name": "Stock Options",
			"tip": "Dividends grow +0.05%/turn (max +10%) · output +0.1%/turn while active (max +5%). Unlocked by an HR advisor's mission."},
	]
	var first := true
	for d in defs:
		var def: Dictionary = d
		var pid := str(def.get("id", ""))
		if not first:
			var sep := HSeparator.new()
			sep.add_theme_color_override("separator", _CARD_BORDER)
			col.add_child(sep)
		first = false
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = str(def.get("tip", ""))
		col.add_child(row)
		var name_l := _dim_label(str(def.get("name", pid)), 12.5)
		name_l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var toggle := CheckButton.new()
		toggle.set_pressed_no_signal(MatchState.is_workforce_policy_enabled(pid))
		var available: bool = MatchState.is_workforce_policy_available(pid)
		toggle.disabled = not available
		if not available:
			row.tooltip_text += "  (locked)"
		toggle.toggled.connect(func(pressed: bool) -> void:
			MatchState.set_workforce_policy_enabled(pid, pressed))
		row.add_child(toggle)

# ── atoms (mirrors advisor_council_tab's look) ───────────────────────────────
func _card_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0E2034")
	sb.border_color = _CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

func _sec_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	return l

func _dim_label(text: String, fs: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(fs))
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	return l
