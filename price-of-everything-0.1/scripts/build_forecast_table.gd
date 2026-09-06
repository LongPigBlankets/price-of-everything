extends PanelContainer
## Shared compact, qualitative forecast for the confirm screen and map hover.
const Forecast := preload("res://scripts/build_forecast.gd")
const PHASE_NAMES := {"completes": "Build completes", "shipping": "First production", "selling": "Revenue arrives"}

func set_forecast(data: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	add_theme_stylebox_override("panel", style)
	add_child(timeline(data))

static func timeline(data: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "RevenueTimeline"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	grid.tooltip_text = "Estimated turns from construction start, after materials arrive. At current prices and standing output, before company taxes. Credit is temporary; payback describes the ongoing outlook after repayment."
	for heading in ["When", "Stage", "Cash flow"]:
		grid.add_child(_cell(heading, DS.PALETTE.ACCENT))
	for phase in data.get("phases", []):
		if str(phase.kind) == "building":
			continue
		var marker := "Turn " + str(phase.range).replace("t", "").trim_suffix(" onwards")
		grid.add_child(_cell(marker))
		var stage := _cell(str(PHASE_NAMES.get(str(phase.kind), phase.label)))
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(stage)
		var net := float(phase.per_turn)
		grid.add_child(_cell("No supply" if bool(data.get("no_supply", false)) else _cash_direction(net),
			DS.PALETTE.DANGER if bool(data.get("no_supply", false)) else _cash_tone(net)))
	var finance: Dictionary = data.get("financing", {})
	if not finance.is_empty():
		var mode := str(finance.get("mode", "ask"))
		var when := "If chosen" if mode == "ask" else ("—" if mode == "none" else "Turn %d–%d" % [finance.start, finance.end])
		grid.add_child(_cell(when))
		grid.add_child(_cell("During repayment"))
		var net := float(finance.get("net", 0.0))
		grid.add_child(_cell("No credit" if mode == "none" else _cash_direction(net), DS.PALETTE.TEXT if mode == "none" else _cash_tone(net)))
	# Keep the lasting operating outlook last, separate from temporary repayments.
	var financed := not finance.is_empty() and str(finance.get("mode", "none")) != "none"
	var stable_turn := int(data.get("first_selling_turn", 0))
	if financed:
		stable_turn = maxi(stable_turn, int(finance.get("end", stable_turn - 1)) + 1)
	grid.add_child(_cell("If chosen" if financed and str(finance.get("mode", "")) == "ask" else "Turn %d onwards" % stable_turn))
	grid.add_child(_cell("Stable production\nafter repayment" if financed else "Stable production"))
	var steady := float(data.get("steady_net", 0.0))
	grid.add_child(_cell("No supply" if bool(data.get("no_supply", false)) else _cash_direction(steady),
		DS.PALETTE.DANGER if bool(data.get("no_supply", false)) else _cash_tone(steady)))
	return grid

static func payback(data: Dictionary) -> Label:
	var band := Forecast.payback_band(float(data.get("steady_net", 0.0)), bool(data.get("no_supply", false)))
	var label := _cell("Payback: " + str(band.text), DS.PALETTE[str(band.tone)])
	label.name = "ForecastPayback"
	label.add_theme_font_size_override("font_size", 20)
	label.tooltip_text = "Broad outlook at current prices, after any credit is repaid. Prices, supply and company taxes can change the result."
	return label

static func _cash_direction(net: float) -> String:
	if net > 0.0:
		return "Small Surplus" if net < 15.0 else "Surplus"
	if net < 0.0:
		return "Small Deficit" if net > -15.0 else "Deficit"
	return "Even"

static func _cash_tone(net: float) -> Color:
	return DS.PALETTE.OK if net > 0.0 else (DS.PALETTE.DANGER if net < 0.0 else DS.PALETTE.WARN)

static func _cell(text: String, tone: Color = Color("e8eef7")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", tone)
	return label
