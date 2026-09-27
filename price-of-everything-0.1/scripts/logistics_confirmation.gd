extends RefCounted
const UIHelpers := preload("res://scripts/ui_helpers.gd")
static var skip_confirmation := false

## What leaving the intermediary means, for the side and destination the player chose:
##   context {side: "input"|"output", destination: "market"|"stockpile"|"tile", good: good_id}
## Anything not given reads as the whole building or tile, both sides.
static func message_for(context: Dictionary) -> String:
	var good := str(context.get("good", ""))
	var what := Catalog.get_display_name(good).to_lower() if good != "" else "these goods"
	var side := str(context.get("side", ""))
	match [side, str(context.get("destination", ""))]:
		["output", "market"]:
			return "The intermediary stops buying %s. It will sell at the global market through the nearest port, paying freight and the port charge." % what
		["output", "stockpile"], ["output", "tile"]:
			return "The intermediary stops buying %s. It will go to the stockpile you choose, and you sell it or use it yourself." % what
		["input", "market"]:
			return "The intermediary stops supplying %s. You will buy it at the global market through a port, paying freight and the port charge." % what
		["input", "stockpile"]:
			return "The intermediary stops supplying %s. It will come from your stockpile, so keep it stocked." % what
	return "The intermediary stops handling %s. Your own transport and the ports take over, which costs freight and port charges." % what


static func request(parent: Node, mode: String, apply: Callable, canceled: Callable = Callable(), context: Dictionary = {}) -> void:
	if mode == "middleman" or skip_confirmation:
		apply.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.name = "TransportSupplierConfirmation"
	dialog.title = "Change supplier"
	dialog.get_ok_button().text = "Change supplier"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	var message := Label.new()
	message.custom_minimum_size.x = 520
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = message_for(context)
	content.add_child(message)
	var dont_show := UIHelpers.make_custom_checkbox()
	dont_show.name = "DontShowSupplierAgain"
	content.add_child(UIHelpers.make_setting_row("Do not show again", dont_show))
	dialog.add_child(content)
	dialog.confirmed.connect(func() -> void:
		if apply.call(): skip_confirmation = dont_show.button_pressed
		dialog.queue_free())
	dialog.canceled.connect(func() -> void:
		if canceled.is_valid(): canceled.call()
		dialog.queue_free())
	parent.add_child(dialog)
	dialog.popup_centered(Vector2i(560, 230))
