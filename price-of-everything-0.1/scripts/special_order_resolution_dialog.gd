extends PanelContainer
## Decision dialog for special-order shipments that can no longer be delivered
## as premium orders: over-delivered units from the latest shipment, and older
## tagged shipments still headed to port after the order has closed.

signal reroute_requested()

var _title: Label
var _body: Label
var _sell_button: Button
var _stockpile_button: Button
var _reroute_button: Button

var _queue: Array = []
var _current_entry: Dictionary = {}
var _waiting_for_reroute := false
var _allow_hide := false

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	_build_ui()
	visible = false
	visibility_changed.connect(_on_visibility_changed)
	if SpecialOrderState != null and not SpecialOrderState.order_closed.is_connected(_on_order_closed):
		SpecialOrderState.order_closed.connect(_on_order_closed)
	if MatchState != null and MatchState.has_signal("special_order_overflow_ready"):
		if not MatchState.special_order_overflow_ready.is_connected(_on_overflow_ready):
			MatchState.special_order_overflow_ready.connect(_on_overflow_ready)

func _build_ui() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -340
	offset_right = 340
	offset_top = -150
	offset_bottom = 150
	custom_minimum_size = Vector2(680, 300)
	clip_contents = true

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(_body)

	vb.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	_sell_button = _make_action_button("Sell normally")
	_sell_button.pressed.connect(_on_sell_pressed)
	row.add_child(_sell_button)

	_stockpile_button = _make_action_button("Stockpile at port")
	_stockpile_button.pressed.connect(_on_stockpile_pressed)
	row.add_child(_stockpile_button)

	_reroute_button = _make_action_button("Reroute to tile")
	_reroute_button.pressed.connect(_on_reroute_pressed)
	row.add_child(_reroute_button)

func _make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

func _on_order_closed(order: Dictionary, _reason: String) -> void:
	var order_id := str(order.get("id", ""))
	var shipments := MatchState.take_pending_special_order_shipments(order_id)
	if shipments.is_empty():
		return
	_enqueue({
		"kind": "pending",
		"order_id": order_id,
		"order": order.duplicate(true),
		"shipments": shipments,
	}, false)
	MatchState.request_toast("Special order ended with shipments awaiting instructions", "warning")

func _on_overflow_ready(record: Dictionary) -> void:
	_enqueue({
		"kind": "overflow",
		"order_id": str(record.get("order_id", "")),
		"record": record.duplicate(true),
	}, true)
	MatchState.request_toast("Special order complete: choose what to do with overflow goods", "warning")

func _enqueue(entry: Dictionary, priority: bool) -> void:
	if priority and not _current_entry.is_empty() and not _waiting_for_reroute:
		if str(_current_entry.get("kind", "")) == "pending" and str(_current_entry.get("order_id", "")) == str(entry.get("order_id", "")):
			_queue.push_front(_current_entry)
			_show_entry(entry)
			return
	if priority:
		_queue.push_front(entry)
	else:
		_queue.append(entry)
	if _current_entry.is_empty():
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_current_entry = {}
		_waiting_for_reroute = false
		_hide_resolved()
		return
	_show_entry(_queue.pop_front())

func _show_entry(entry: Dictionary) -> void:
	_current_entry = entry
	_waiting_for_reroute = false
	_update_content()
	visible = true
	move_to_front()
	PanelStack.push(self)

func _update_content() -> void:
	var kind := str(_current_entry.get("kind", ""))
	_sell_button.disabled = false
	_stockpile_button.disabled = false
	_reroute_button.disabled = kind != "pending"
	_reroute_button.visible = kind == "pending"
	if kind == "overflow":
		var record: Dictionary = _current_entry.get("record", {})
		var good_name := str(record.get("good_display", Catalog.get_display_name(str(record.get("good_id", "")))))
		var qty := int(record.get("qty", 0))
		_title.text = "Special order overflow"
		_body.text = "The special order is complete. The latest shipment has %d extra %s at %s. Sell them at the normal market price, or keep the whole overflow in the port stockpile." % [
			qty,
			good_name,
			Catalog.tile_label(str(record.get("port_tile", ""))),
		]
		var can_stockpile := MatchState.special_order_overflow_can_stockpile(record)
		_stockpile_button.disabled = not can_stockpile
		_stockpile_button.tooltip_text = "" if can_stockpile else "The port stockpile needs room for the entire overflow shipment."
	else:
		var order: Dictionary = _current_entry.get("order", {})
		var shipments: Array = _current_entry.get("shipments", [])
		var summary := _shipments_summary(shipments)
		_title.text = "Special order shipments"
		_body.text = "The %s special order has ended. %s still %s heading to port. Choose whether they should sell normally, unload into the port stockpile, or reroute to another tile stockpile." % [
			_order_label(order),
			summary,
			"is" if _shipments_total_qty(shipments) == 1 else "are",
		]
		var can_store := MatchState.can_store_special_order_shipments_at_ports(shipments)
		_stockpile_button.disabled = not can_store
		_stockpile_button.tooltip_text = "" if can_store else "The port stockpile needs room for all of these shipments."

func _on_sell_pressed() -> void:
	var kind := str(_current_entry.get("kind", ""))
	if kind == "overflow":
		var sold := MatchState.sell_special_order_overflow(_current_entry.get("record", {}))
		if not sold.is_empty():
			MatchState.request_toast("Special-order overflow sold at the normal market price", "success")
	else:
		var result := MatchState.resolve_special_order_shipments(_current_entry.get("shipments", []), "sell")
		if bool(result.get("ok", false)):
			MatchState.request_toast("Special-order shipments will sell normally when they arrive", "success")
	_finish_current()

func _on_stockpile_pressed() -> void:
	var kind := str(_current_entry.get("kind", ""))
	if kind == "overflow":
		if not MatchState.stockpile_special_order_overflow(_current_entry.get("record", {})):
			MatchState.request_toast("The port stockpile does not have room for the whole overflow shipment", "warning")
			_update_content()
			return
		MatchState.request_toast("Special-order overflow stored at the port", "success")
	else:
		var result := MatchState.resolve_special_order_shipments(_current_entry.get("shipments", []), "stockpile_port")
		if not bool(result.get("ok", false)):
			MatchState.request_toast("The port stockpile does not have room for all remaining shipments", "warning")
			_update_content()
			return
		MatchState.request_toast("Special-order shipments will unload into the port stockpile", "success")
	_finish_current()

func _on_reroute_pressed() -> void:
	if str(_current_entry.get("kind", "")) != "pending":
		return
	_waiting_for_reroute = true
	_sell_button.disabled = true
	_stockpile_button.disabled = true
	_reroute_button.disabled = true
	_body.text += "\n\nPick a destination tile on the map."
	reroute_requested.emit()

func reroute_current_to(tile_id: String) -> void:
	if str(_current_entry.get("kind", "")) != "pending":
		return
	var result := MatchState.resolve_special_order_shipments(_current_entry.get("shipments", []), "reroute", tile_id)
	if not bool(result.get("ok", false)):
		MatchState.request_toast("Could not reroute those shipments", "warning")
		cancel_reroute()
		return
	MatchState.request_toast("Special-order shipments rerouted to %s" % Catalog.tile_label(tile_id), "success")
	_finish_current()

func cancel_reroute() -> void:
	if not _waiting_for_reroute:
		return
	_waiting_for_reroute = false
	_update_content()

func _finish_current() -> void:
	_current_entry = {}
	_waiting_for_reroute = false
	_show_next()

func _hide_resolved() -> void:
	PanelStack.remove(self)
	_allow_hide = true
	visible = false
	_allow_hide = false

func _on_visibility_changed() -> void:
	if visible or _allow_hide or _current_entry.is_empty():
		return
	call_deferred("_restore_visibility")

func _restore_visibility() -> void:
	if _current_entry.is_empty():
		return
	visible = true
	move_to_front()
	PanelStack.push(self)

func _order_label(order: Dictionary) -> String:
	var label := str(order.get("display_name", "")).strip_edges()
	if label != "":
		return label
	return Catalog.get_display_name(str(order.get("good_id", "")))

func _shipments_summary(shipments: Array) -> String:
	var manifest := MatchState.special_order_shipments_manifest(shipments)
	var parts: Array = []
	for good_id in manifest.keys():
		parts.append("%d %s" % [int(manifest[good_id]), Catalog.get_display_name(str(good_id))])
	if parts.is_empty():
		return "No goods are"
	return ", ".join(parts)

func _shipments_total_qty(shipments: Array) -> int:
	var total := 0
	for qty in MatchState.special_order_shipments_manifest(shipments).values():
		total += int(qty)
	return total
