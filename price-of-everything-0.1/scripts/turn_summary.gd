extends PanelContainer

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const RUNWAY_THRESHOLD_TURNS := 5
const AUTO_COLLAPSE_DELAY := 5.0
const MAX_LIST_ITEMS := 3
const COLLAPSED_HEIGHT := 56.0

@onready var header_row: HBoxContainer = $MarginContainer/VBoxContainer/HeaderRow
@onready var expand_icon: Label = $MarginContainer/VBoxContainer/HeaderRow/ExpandIcon
@onready var compact_cash_label: Label = $MarginContainer/VBoxContainer/HeaderRow/CompactCashLabel
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ContentVBox
@onready var cash_arrow: Label = $MarginContainer/VBoxContainer/ContentVBox/CashSection/CashArrow
@onready var cash_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashSection/CashLabel
@onready var buildings_built_label: Label = $MarginContainer/VBoxContainer/ContentVBox/BuildingsBuiltLabel
@onready var buildings_starved_label: Label = $MarginContainer/VBoxContainer/ContentVBox/BuildingsStarvedLabel
@onready var goods_produced_label: Label = $MarginContainer/VBoxContainer/ContentVBox/GoodsProducedLabel
@onready var goods_running_out_label: Label = $MarginContainer/VBoxContainer/ContentVBox/GoodsRunningOutLabel
@onready var dismiss_button: Button = $MarginContainer/VBoxContainer/ContentVBox/DismissButton
@onready var goods_sales_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/GoodsSalesLabel
@onready var power_sales_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/PowerSalesLabel
@onready var power_purchase_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/PowerPurchaseLabel
@onready var costs_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/CostsLabel
@onready var taxes_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/TaxesLabel
@onready var interest_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/InterestLabel
@onready var tax_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/TaxesLabel
@onready var dividends_label: Label = $MarginContainer/VBoxContainer/ContentVBox/CashBreakdown/DividendsLabel

var _expanded := true
var _collapse_timer: SceneTreeTimer = null
var _expanded_offset_top := 0.0
var _expanded_offset_bottom := 0.0
var _in_transit_link: LinkButton = null
var _in_transit_details: VBoxContainer = null
var _in_transit_expanded := false

var _buildings_added_this_turn: Array = []
var _suppress_expand := false  # set by the "don't expand again" tickbox; resets each game

func _ready() -> void:
	_expanded_offset_top = offset_top
	_expanded_offset_bottom = offset_bottom
	header_row.gui_input.connect(_on_header_clicked)
	dismiss_button.pressed.connect(_collapse)
	Production.turn_processed.connect(_on_turn_processed)
	MatchState.building_added.connect(_on_building_added)
	_build_in_transit_section()
	_build_suppress_expand_checkbox()
	_render_empty()
	_collapse()

func _build_suppress_expand_checkbox() -> void:
	var checkbox := UIHelpers.make_custom_checkbox()
	checkbox.toggled.connect(func(pressed: bool) -> void: _suppress_expand = pressed)
	var row := UIHelpers.make_setting_row("Don't expand again", checkbox)
	content_vbox.add_child(row)
	content_vbox.move_child(row, dismiss_button.get_index() + 1)

func _on_building_added(instance: Dictionary) -> void:
	_buildings_added_this_turn.append(instance)

func _on_turn_processed(summary: Dictionary) -> void:
	_render_summary(summary)
	if not _suppress_expand:
		_expand()
		_start_collapse_timer()
	_buildings_added_this_turn.clear()

func _render_empty() -> void:
	cash_arrow.text = ""
	cash_label.text = "-"
	compact_cash_label.text = cash_label.text
	buildings_built_label.text = ""
	buildings_starved_label.text = ""
	goods_produced_label.text = ""
	goods_running_out_label.text = ""
	_render_in_transit()

func _render_summary(summary: Dictionary) -> void:
	goods_sales_label.text = "  Goods sold: +£%.2f" % summary.goods_sales_revenue
	power_sales_label.text = "  Power sold: +£%.2f" % summary.power_sales_revenue
	power_purchase_label.text = "  Power bought: -£%.2f" % summary.power_purchase_cost
	var total_costs: float = summary.maintenance_paid + summary.labour_paid + summary.get("transport_paid", 0.0)
	costs_label.text = "  Costs: -£%.2f" % total_costs
	var total_taxes: float = summary.taxes_paid + summary.dividends_paid
	taxes_label.text = "  Taxes & dividends: -£%.2f" % total_taxes
	
	power_sales_label.visible = summary.power_sales_revenue > 0
	power_purchase_label.visible = summary.power_purchase_cost > 0
	taxes_label.visible = total_taxes > 0
	
	var interest: float = summary.get("interest_paid", 0.0)
	interest_label.text = "  Interest: -£%.2f" % interest
	interest_label.visible = interest > 0
	var tax: float = summary.get("taxes_paid", 0.0)
	tax_label.text = "  Tax: -£%.2f" % tax
	tax_label.visible = tax > 0
	var dividends: float = summary.get("dividends_paid", 0.0)
	dividends_label.text = "  Dividends: -£%.2f" % dividends
	dividends_label.visible = dividends > 0
	
	var net: float = summary.money_in - summary.money_out
	if net > 0.005:
		cash_arrow.text = "↑"
		cash_arrow.modulate = Color.GREEN
		cash_label.text = "+£%.2f" % net
	elif net < -0.005:
		cash_arrow.text = "↓"
		cash_arrow.modulate = Color.RED
		cash_label.text = "-£%.2f" % abs(net)
	else:
		cash_arrow.text = ""
		cash_arrow.modulate = Color.WHITE
		cash_label.text = "£0.00"
	compact_cash_label.text = cash_label.text
	compact_cash_label.modulate = cash_arrow.modulate
	
	buildings_built_label.text = _format_buildings_built()
	buildings_starved_label.text = _format_starved(summary.starved)
	goods_produced_label.text = _format_produced(summary.produced)
	goods_running_out_label.text = _format_running_out(summary.consumed)
	_render_in_transit()

func _build_in_transit_section() -> void:
	_in_transit_link = LinkButton.new()
	_in_transit_link.add_theme_font_size_override("font_size", 13)
	_in_transit_link.pressed.connect(_toggle_in_transit_details)
	content_vbox.add_child(_in_transit_link)
	content_vbox.move_child(_in_transit_link, goods_running_out_label.get_index() + 1)

	_in_transit_details = VBoxContainer.new()
	_in_transit_details.add_theme_constant_override("separation", 2)
	_in_transit_details.visible = false
	content_vbox.add_child(_in_transit_details)
	content_vbox.move_child(_in_transit_details, _in_transit_link.get_index() + 1)

func _toggle_in_transit_details() -> void:
	_in_transit_expanded = not _in_transit_expanded
	_render_in_transit()

func _render_in_transit() -> void:
	if _in_transit_link == null or _in_transit_details == null:
		return
	var shipments := MatchState.get_pending_transport_shipments()
	var total_qty := 0
	for shipment in shipments:
		total_qty += int(shipment.get("qty", 0))
	_in_transit_link.visible = not shipments.is_empty()
	_in_transit_link.text = "In transit: %d units across %d shipments %s" % [
		total_qty,
		shipments.size(),
		"hide" if _in_transit_expanded else "show",
	]
	for child in _in_transit_details.get_children():
		child.queue_free()
	_in_transit_details.visible = _in_transit_expanded and not shipments.is_empty()
	if not _in_transit_details.visible:
		return
	shipments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_turns := int(a.get("turns_remaining", 0))
		var b_turns := int(b.get("turns_remaining", 0))
		if a_turns == b_turns:
			return str(a.get("destination_tile", "")) < str(b.get("destination_tile", ""))
		return a_turns < b_turns
	)
	for shipment in shipments:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.text = "  %d %s from %s to %s, arrives %s" % [
			int(shipment.get("qty", 0)),
			Catalog.get_display_name(shipment.get("good_id", "")),
			shipment.get("source_tile", "unknown"),
			shipment.get("destination_tile", "unknown"),
			_arrival_text(int(shipment.get("turns_remaining", 0))),
		]
		_in_transit_details.add_child(label)

func _format_buildings_built() -> String:
	var count: int = _buildings_added_this_turn.size()
	if count == 0:
		return "Constructed: none"
	if count <= MAX_LIST_ITEMS:
		var names: Array = []
		for inst in _buildings_added_this_turn:
			names.append(_building_display_name(inst.building_id))
		return "Constructed: " + ", ".join(names)
	return "Constructed: %d buildings  Go to ->" % count

func _format_starved(starved: Array) -> String:
	var count: int = starved.size()
	if count == 0:
		return "Starved: 0"
	if count <= MAX_LIST_ITEMS:
		var entries: Array = []
		for s in starved:
			var missing_names: Array = []
			for m in s.missing:
				missing_names.append(m.internal_name)
			var display_id: String = s.instance_id.replace("inst_", "")
			entries.append("%s (%s)" % [display_id, ", ".join(missing_names)])
		return "Starved: " + "; ".join(entries)
	return "%d buildings starved  Go to ->" % count

func _format_produced(produced: Dictionary) -> String:
	if produced.is_empty():
		return "Produced: nothing"
	var sorted_pairs: Array = []
	for good_id in produced.keys():
		sorted_pairs.append({"good_id": good_id, "qty": produced[good_id]})
	sorted_pairs.sort_custom(func(a, b): return a.qty > b.qty)
	
	if sorted_pairs.size() <= MAX_LIST_ITEMS:
		var entries: Array = []
		for pair in sorted_pairs:
			var name: String = Catalog.get_display_name(pair.good_id)
			entries.append("%d %s" % [pair.qty, name])
		return "Produced: " + ", ".join(entries)
	
	var total_units := 0
	for pair in sorted_pairs:
		total_units += pair.qty
	return "Produced: %d units across %d goods  Go to ->" % [total_units, sorted_pairs.size()]

func _format_running_out(consumed: Dictionary) -> String:
	if MatchState.sell_mode != MatchState.SellMode.STOCKPILE_ALL:
		return ""
	var warnings: Array = []
	for good_id in consumed.keys():
		var consumption_rate: int = consumed[good_id]
		if consumption_rate <= 0:
			continue
		var stockpile: int = Stockpile.get_total(good_id)
		var runway: float = float(stockpile) / consumption_rate
		if runway < RUNWAY_THRESHOLD_TURNS:
			warnings.append({"good_id": good_id, "runway": runway})
	
	if warnings.is_empty():
		return ""
	warnings.sort_custom(func(a, b): return a.runway < b.runway)
	
	if warnings.size() <= MAX_LIST_ITEMS:
		var entries: Array = []
		for w in warnings:
			var name: String = Catalog.get_display_name(w.good_id)
			entries.append("%s (%.1fT)" % [name, w.runway])
		return "Running out: " + ", ".join(entries)
	return "%d goods running out  Go to ->" % warnings.size()

func _building_display_name(building_id: String) -> String:
	return Catalog.get_building_display_name(building_id)

func _arrival_text(turns_remaining: int) -> String:
	if turns_remaining <= 1:
		return "next turn"
	return "in %d turns" % turns_remaining

func _on_header_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _expanded:
			_collapse()
		else:
			_expand()

func _expand() -> void:
	_expanded = true
	offset_top = _expanded_offset_top
	offset_bottom = _expanded_offset_bottom
	content_vbox.show()
	compact_cash_label.hide()
	expand_icon.text = "▾"
	_cancel_collapse_timer()

func _collapse() -> void:
	_expanded = false
	offset_bottom = _expanded_offset_bottom
	offset_top = offset_bottom - COLLAPSED_HEIGHT
	content_vbox.hide()
	compact_cash_label.show()
	expand_icon.text = "▸"
	_cancel_collapse_timer()

func _start_collapse_timer() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(AUTO_COLLAPSE_DELAY)
	_collapse_timer = timer
	await timer.timeout
	if _collapse_timer == timer:
		_collapse()

func _cancel_collapse_timer() -> void:
	_collapse_timer = null
