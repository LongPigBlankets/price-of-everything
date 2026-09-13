extends VBoxContainer
## Shared DS presentation; economic calculations stay in CashCommitments.
const Forecast := preload("res://scripts/cash_commitments.gd")

const UIHelpers := preload("res://scripts/ui_helpers.gd")
var _folded: Dictionary = {}
const BILLS := Color("#E6B85C")
const ORDERS := Color("#78BBDD")
const RUNNING := Color("#5BD180")

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 16)
	var data := Forecast.snapshot()
	var costs := Forecast.next_turn_costs(data)
	var hero := card(self, "Outlined")
	text_line(hero, "UPCOMING EXTRA COSTS", "Section")
	var amount := text_line(hero, "≈ £%.2f" % float(costs.total), "Numeric")
	amount.name = "UpcomingCostTotal"
	amount.add_theme_font_size_override("font_size", 38)
	text_line(hero, "Construction materials and initial inputs payable next turn.")
	var metrics := HBoxContainer.new()
	hero.add_child(metrics)
	metric(metrics, "MATERIALS / INPUTS IN TRANSIT", float(costs.bills) + float(costs.later), BILLS, false)
	metric(metrics, "NEW PURCHASES EXPECTED", float(costs.orders), ORDERS, true)
	if is_zero_approx(float(costs.total)):
		text_line(hero, "No extra costs to plan for.")
	text_line(hero, "Routine running costs, restocking and loan repayments are excluded.", "Caption")
	if not (costs.payments as Array).is_empty():
		var bills := section("bills", "Materials and initial inputs on the way", "£%.2f" % (float(costs.bills) + float(costs.later)), BILLS)
		for row: Dictionary in costs.payments:
			line(bills, str(row.label), "£%.2f · %s" % [float(row.amount), when(int(row.due_in))])
	if not (costs.order_rows as Array).is_empty():
		var orders := section("orders", "Purchases expected next turn", "≈ £%.2f" % float(costs.orders), ORDERS)
		for row: Dictionary in costs.order_rows:
			var entry := HBoxContainer.new()
			entry.add_theme_constant_override("separation", 12)
			orders.add_child(entry)
			entry.add_child(UIHelpers.make_plain_good_icon(str(row.good), Catalog.get_internal_name(str(row.good)), 38))
			var copy := VBoxContainer.new()
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.add_child(copy)
			text_line(copy, "%d %s" % [int(row.qty), Catalog.get_display_name(str(row.good))], "Numeric")
			var purpose := "Construction materials" if str(row.kind) in ["construction", "upgrade"] else "Initial inputs"
			text_line(copy, Catalog.tile_label(str(row.tile)) + " · " + purpose, "Caption")
			var price := text_line(entry, "≈ £%.2f\n%s" % [float(row.amount), when(int(row.payment_in))], "Numeric")
			price.autowrap_mode = TextServer.AUTOWRAP_OFF
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		text_line(orders, "Estimated at current prices, including freight.", "Caption")

func section(key: String, title: String, summary: String, tint: Color, closed: bool = false) -> VBoxContainer:
	var outer := card(self)
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	header.add_theme_font_size_override("font_size", 17)
	outer.add_child(header)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	outer.add_child(body)
	body.visible = not bool(_folded.get(key, closed))
	header.text = ("⌄  " if body.visible else "›  ") + title + "   ·   " + summary
	var accent := ColorRect.new()
	accent.color = tint
	accent.custom_minimum_size.y = 2
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(accent)
	outer.move_child(accent, 1)
	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		_folded[key] = not body.visible
		header.text = ("⌄  " if body.visible else "›  ") + title + "   ·   " + summary)
	return body

static func card(parent: Node, style: String = "Card") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = StringName(style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	return col

static func metric(parent: Node, title: String, value: float, tint: Color, estimate: bool) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var label := text_line(col, title, "Caption")
	label.add_theme_font_size_override("font_size", 12)
	var number := text_line(col, ("≈ " if estimate else "") + "£%.2f" % value, "Numeric")
	number.add_theme_color_override("font_color", tint)
	number.add_theme_font_size_override("font_size", 22)

static func make_link(action: Callable) -> LinkButton:
	var button := LinkButton.new()
	button.theme = DS.theme
	button.name = "UpcomingCostsLink"
	button.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	button.custom_minimum_size.y = 30
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 15)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, DS.PALETTE.ACCENT)
	button.pressed.connect(action)
	return button

static func update_link(button: LinkButton, data: Dictionary) -> void:
	button.text = "Upcoming extra costs: ≈ £%.2f" % float(Forecast.next_turn_costs(data).total)
	button.tooltip_text = "Open Upcoming: construction materials and initial inputs only. Excludes routine running costs, restocking and repayments."

static func quantities(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in rows:
		var key := str(row.tile) + "|" + str(row.good)
		out[key] = int(out.get(key, 0)) + int(row.qty)
	return out

static func when(turns: int) -> String:
	return "due next turn" if turns <= 1 else "due in %d turns" % turns

static func line(parent: Node, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var left := text_line(row, label)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := text_line(row, value, "Numeric")
	right.autowrap_mode = TextServer.AUTOWRAP_OFF
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

static func text_line(parent: Node, content: String, style: String = "Body") -> Label:
	var label := Label.new()
	label.text = content
	label.theme_type_variation = StringName(style)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	parent.add_child(label)
	return label

static func build_card(_ledger: Dictionary, _total: float, forecast: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "BuildUpcomingPayments"
	col.add_theme_constant_override("separation", 8)
	text_line(col, "Recommended buffer (cash or loan) for initial inputs and startup costs before first sales.")
	var amount := text_line(col, "≈ £%.2f" % maxf(0.0, float(forecast.get("cash_needed", 0.0))), "Numeric")
	amount.name = "RecommendedBufferAmount"
	amount.add_theme_font_size_override("font_size", 24)
	col.tooltip_text = "Construction materials and freight are charged on confirmation. Cancel before End Turn to release those funds."
	return col
