extends PanelContainer

const RUNWAY_THRESHOLD_TURNS := 5
const AUTO_COLLAPSE_DELAY := 5.0
const MAX_LIST_ITEMS := 3

@onready var header_row: HBoxContainer = $MarginContainer/VBoxContainer/HeaderRow
@onready var expand_icon: Label = $MarginContainer/VBoxContainer/HeaderRow/ExpandIcon
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

var _expanded: bool = true
var _collapse_timer: SceneTreeTimer = null

# Track buildings added this turn (between PROCESS phases)
var _buildings_added_this_turn: Array = []

func _ready() -> void:
	header_row.gui_input.connect(_on_header_clicked)
	dismiss_button.pressed.connect(_collapse)
	Production.turn_processed.connect(_on_turn_processed)
	MatchState.building_added.connect(_on_building_added)
	
	# Start collapsed; will auto-show when first turn processes
	_render_empty()
	_collapse()

func _on_building_added(instance: Dictionary) -> void:
	_buildings_added_this_turn.append(instance)

func _on_turn_processed(summary: Dictionary) -> void:
	_render_summary(summary)
	_expand()
	_start_collapse_timer()
	_buildings_added_this_turn.clear()

func _render_empty() -> void:
	cash_arrow.text = ""
	cash_label.text = "—"
	buildings_built_label.text = ""
	buildings_starved_label.text = ""
	goods_produced_label.text = ""
	goods_running_out_label.text = ""

func _render_summary(summary: Dictionary) -> void:
	# --- THIS BLOCK IS NOW PROPERLY INDENTED ---
	goods_sales_label.text = "  Goods sold: +£%.2f" % summary.goods_sales_revenue
	power_sales_label.text = "  Power sold: +£%.2f" % summary.power_sales_revenue
	power_purchase_label.text = "  Power bought: -£%.2f" % summary.power_purchase_cost
	var total_costs: float = summary.maintenance_paid + summary.labour_paid
	costs_label.text = "  Costs: -£%.2f" % total_costs
	var total_taxes: float = summary.taxes_paid + summary.dividends_paid
	taxes_label.text = "  Taxes & dividends: -£%.2f" % total_taxes
	
	# Optionally hide rows where the value is exactly zero, to reduce noise:
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

	# --- YOUR DEBUG PRINT (Added here so it has access to total_costs & total_taxes) ---
	print("[Production] Cash breakdown: goods=£%.2f power_sold=£%.2f power_bought=£%.2f costs=£%.2f taxes=£%.2f net=£%.2f" % [
		summary.goods_sales_revenue,
		summary.power_sales_revenue,
		summary.power_purchase_cost,
		total_costs,
		total_taxes,
		summary.money_in - summary.money_out
	])

	# 1. Cash change
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
		cash_label.text = "£0.00"
	
	# 2. Buildings constructed
	buildings_built_label.text = _format_buildings_built()
	
	# 3. Buildings starved
	buildings_starved_label.text = _format_starved(summary.starved)
	
	# 4. Goods produced
	goods_produced_label.text = _format_produced(summary.produced)
	
	# 5. Goods running out (only in stockpile mode)
	goods_running_out_label.text = _format_running_out(summary.consumed)

func _format_buildings_built() -> String:
	var count: int = _buildings_added_this_turn.size()
	if count == 0:
		return "Constructed: none"
	if count <= MAX_LIST_ITEMS:
		var names: Array = []
		for inst in _buildings_added_this_turn:
			names.append(_building_display_name(inst.building_id))
		return "Constructed: " + ", ".join(names)
	return "Constructed: %d buildings  Go to →" % count

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
		return "⚠ Starved: " + "; ".join(entries)
	return "⚠ %d buildings starved  Go to →" % count

func _format_produced(produced: Dictionary) -> String:
	if produced.is_empty():
		return "Produced: nothing"
	
	# Sort by unit count descending
	var sorted_pairs: Array = []
	for good_id in produced.keys():
		sorted_pairs.append({"good_id": good_id, "qty": produced[good_id]})
	sorted_pairs.sort_custom(func(a, b): return a.qty > b.qty)
	
	var count: int = sorted_pairs.size()
	if count <= MAX_LIST_ITEMS:
		var entries: Array = []
		for pair in sorted_pairs:
			@warning_ignore("shadowed_variable_base_class")
			var name: String = Catalog.get_display_name(pair.good_id)
			entries.append("%d %s" % [pair.qty, name])
		return "Produced: " + ", ".join(entries)
	
	var total_units: int = 0
	for pair in sorted_pairs:
		total_units += pair.qty
	return "Produced: %d units across %d goods  Go to →" % [total_units, count]

func _format_running_out(consumed: Dictionary) -> String:
	# Only flag in STOCKPILE_ALL mode — in SELL_ALL, stockpile is always 0 by design
	if MatchState.sell_mode != MatchState.SellMode.STOCKPILE_ALL:
		return ""
	
	var warnings: Array = []
	for good_id in consumed.keys():
		var consumption_rate: int = consumed[good_id]
		if consumption_rate <= 0:
			continue
		
		# NOTE: If Stockpile was removed, update this to MatchState.get_good_qty(good_id)
		var stockpile: int = Stockpile.get_total(good_id) 
		
		var runway: float = float(stockpile) / consumption_rate
		if runway < RUNWAY_THRESHOLD_TURNS:
			warnings.append({
				"good_id": good_id,
				"runway": runway,
			})
	
	if warnings.is_empty():
		return ""
	
	# Sort by shortest runway first (most urgent)
	warnings.sort_custom(func(a, b): return a.runway < b.runway)
	
	var count: int = warnings.size()
	if count <= MAX_LIST_ITEMS:
		var entries: Array = []
		for w in warnings:
			@warning_ignore("shadowed_variable_base_class")
			var name: String = Catalog.get_display_name(w.good_id)
			entries.append("%s (%.1fT)" % [name, w.runway])
		return "⏳ Running out: " + ", ".join(entries)
	return "⏳ %d goods running out  Go to →" % count

func _building_display_name(building_id: String) -> String:
	# Stub — eventually this comes from Catalog.get_building(building_id).display_name
	return building_id

# --- Expand / collapse ---

func _on_header_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _expanded:
			_collapse()
		else:
			_expand()

func _expand() -> void:
	_expanded = true
	content_vbox.show()
	expand_icon.text = "▾"
	_cancel_collapse_timer()

func _collapse() -> void:
	_expanded = false
	content_vbox.hide()
	expand_icon.text = "▸"
	_cancel_collapse_timer()

func _start_collapse_timer() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(AUTO_COLLAPSE_DELAY)
	_collapse_timer = timer
	await timer.timeout
	if _collapse_timer == timer:  # this timer wasn't superseded
		_collapse()

func _cancel_collapse_timer() -> void:
	# Godot timers don't have a clean cancel — just nil the reference.
	# If the previous timer fires after we've manually expanded again,
	# we check _expanded state in the callback... actually we don't.
	# The simplest fix: track timer instances and ignore stale fires.
	_collapse_timer = null
