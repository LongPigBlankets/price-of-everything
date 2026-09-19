extends RefCounted
const UIHelpers := preload("res://scripts/ui_helpers.gd")
static var skip_confirmation := false

static func request(parent: Node, mode: String, apply: Callable, canceled: Callable = Callable()) -> void:
	if mode == "middleman" or skip_confirmation:
		apply.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.name = "TransportSupplierConfirmation"
	dialog.title = "Change transport supplier"
	dialog.get_ok_button().text = "Change supplier"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	var message := Label.new()
	message.custom_minimum_size.x = 520
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = "Are you sure you want to change your transport supplier? This will incur costs and require you to sell to the global market via a port."
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
