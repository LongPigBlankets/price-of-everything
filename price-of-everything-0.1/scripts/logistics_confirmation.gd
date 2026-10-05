extends RefCounted
## The one question asked before a building's goods leave Local Suppliers: a card over the screen titled
## Change supplier (inputs) or Change destination (outputs), what the change may cost for the side and
## destination chosen, a Do not show again box, and Cancel and Confirm at the two ends of a row.
## It also stands for the stockpile surplus prompt: a change it confirmed raises no second prompt.
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const StockpileRoutePrompt := preload("res://scripts/stockpile_route_prompt.gd")
static var skip_confirmation := false

const CARD_W := 540.0
## The room between Cancel and Confirm, at the least.
const BUTTON_GAP := 120.0


static func title_for(context: Dictionary) -> String:
	return "Change supplier" if str(context.get("side", "")) == "input" else "Change destination"


## The card's words for the side and destination the player chose:
##   context {side: "input"|"output", destination: "market"|"stockpile"|"tile"|"other", good: good_id}
## Anything not given reads as the building's goods, both sides.
static func message_for(context: Dictionary) -> String:
	var side := str(context.get("side", ""))
	var destination := str(context.get("destination", ""))
	var what := str({"input": "the source of your inputs", "output": "the destination of your outputs"}.get(side,
		"the source or destination of your goods"))
	var parts: Array = ["You're about to change %s. This could impact your profit." % what]
	if side == "output" and destination in ["stockpile", "tile", "other"]:
		parts.append("Stockpiles may accumulate your goods if you don't sell the surplus. View the Tile stockpile to change that, because by default it does not sell surplus.")
	elif side == "output" and destination == "market":
		parts.append("Selling to market is a great way to integrate but be aware that transport and port fees may eat into your profit. Improve the infrastructure and use the right transport method to keep costs low.")
	parts.append("Do you want to continue?")
	return "\n\n".join(parts)


static func request(parent: Node, mode: String, apply: Callable, canceled: Callable = Callable(), context: Dictionary = {}) -> void:
	if mode == "middleman" or skip_confirmation:
		apply.call()
		return
	var layer := CanvasLayer.new()
	layer.layer = 130
	parent.add_child(layer)
	var card := PanelContainer.new()
	card.name = "TransportSupplierConfirmation"
	card.theme = DS.theme
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(CARD_W, 0)
	layer.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	card.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(_text(title_for(context), &"Title"))
	col.add_child(_text(message_for(context), &"Body"))
	var dont_show := UIHelpers.make_custom_checkbox()
	dont_show.name = "DontShowSupplierAgain"
	col.add_child(UIHelpers.make_setting_row("Do not show again", dont_show))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(BUTTON_GAP))
	col.add_child(row)
	var cancel := Button.new()
	cancel.name = "CancelSupplierChange"
	cancel.text = "Cancel"
	row.add_child(cancel)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var confirm := Button.new()
	confirm.name = "ConfirmSupplierChange"
	confirm.text = "Confirm"
	confirm.theme_type_variation = &"Primary"
	row.add_child(confirm)
	for b: Button in [cancel, confirm]:
		b.custom_minimum_size = Vector2(140, 0)
	var state := {"done": false}
	var close := func(confirmed: bool) -> void:
		if bool(state.done):
			return
		state.done = true
		PanelStack.remove(card)
		if confirmed:
			# The surplus prompt the change would raise is this card's to say, and it has.
			StockpileRoutePrompt.hold = true
			if apply.call():
				skip_confirmation = dont_show.button_pressed
			StockpileRoutePrompt.hold = false
		elif canceled.is_valid():
			canceled.call()
		layer.queue_free()
	confirm.pressed.connect(func() -> void: close.call(true))
	cancel.pressed.connect(func() -> void: close.call(false))
	# Esc (the panel stack hides the top card) cancels.
	card.visibility_changed.connect(func() -> void:
		if not card.visible:
			close.call(false))
	PanelStack.push(card)
	await card.get_tree().process_frame
	if is_instance_valid(card):
		card.position = ((card.get_viewport_rect().size - card.size) * 0.5).round()


static func _text(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_W - 40.0
	return label
