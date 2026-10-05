extends CanvasLayer
## DS2: the sheet that asks before a building's goods leave the Logistics Intermediary (scripts/
## logistics_confirmation.gd builds it). A scrim over the game and, centred on it, Building Detail's navy
## steel backing with a raised title, what the change means in white print, the "Do not show again" tick and
## two cream keys at the two ends of a row, a small Cancel and Confirm. A phrase of the message can be a link (underlined, in the keys'
## cream): pressing it opens the Stockpile tab of the tile the message is about and leaves the sheet up with
## its decision still to make. The scrim then lets the game through, so the tab can be read and used, and the
## sheet drags by its title out of the way. Pressing the scrim or Escape cancels.

signal confirmed
signal canceled

const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")

const WIDTH := 600.0
const LINK_META := "stockpile"
## The keys' widths: Cancel the smaller, at the left end of the row, Confirm at the right.
const CANCEL_W := 130.0
const CONFIRM_W := 200.0

## Set before the sheet enters the tree.
var title_text := "Change destination"
var confirm_text := "Confirm"
var message := ""
## The words of `message` that link to `link_tile`'s Stockpile tab; none when either is empty.
var link_phrase := ""
var link_tile := ""

var _sheet: PanelContainer = null
var _dont_show: CheckBox = null
var _done := false
var _scrim: ColorRect = null
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	layer = 130
	var scrim := ColorRect.new()
	_scrim = scrim
	scrim.name = "Scrim"
	scrim.color = Color(0, 0, 0, 0.5)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			canceled.emit())
	add_child(scrim)
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	# A CanvasLayer's children do not inherit the game's theme.
	_sheet.theme = DS.theme
	_sheet.custom_minimum_size.x = WIDTH
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)
	LedgerV3.dress(_sheet)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, LedgerV3.CONTENT_MARGIN)
	_sheet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	var title: Control = Title.new()
	title.call("set_text", title_text)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_title_input)
	col.add_child(title)
	col.add_child(LedgerV3.seam())
	col.add_child(_message())

	_dont_show = UIHelpers.make_custom_checkbox()
	_dont_show.name = "DontShowSupplierAgain"
	col.add_child(UIHelpers.make_setting_row("Do not show again", _dont_show))

	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 12)
	col.add_child(keys)
	var cancel := Parts.key_button("Cancel", "CancelKey", 0.7)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size.x = CANCEL_W
	cancel.pressed.connect(func() -> void: canceled.emit())
	keys.add_child(cancel)
	# Cancel at the row's left end, Confirm at its right, the room between them open.
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_child(gap)
	var ok := Parts.key_button(confirm_text, "ConfirmKey", 0.8)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.custom_minimum_size.x = CONFIRM_W
	ok.pressed.connect(func() -> void: confirmed.emit())
	keys.add_child(ok)

	LampOverlay.attach(_sheet)
	# Escape closes the top panel by hiding it: hidden without an answer is a cancel.
	PanelStack.push(_sheet)
	_sheet.visibility_changed.connect(func() -> void:
		if not _sheet.visible and not _done:
			canceled.emit())
	confirmed.connect(func() -> void: _done = true)
	canceled.connect(func() -> void: _done = true)
	_centre.call_deferred()


## The sheet in the middle of the screen, once it has its size.
func _centre() -> void:
	await get_tree().process_frame
	if is_instance_valid(_sheet):
		_sheet.reset_size()
		_sheet.position = ((_sheet.get_viewport_rect().size - _sheet.size) * 0.5).floor()


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = _sheet.global_position - _sheet.get_global_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		_sheet.global_position = _sheet.get_global_mouse_position() + _drag_offset


## True when the player ticked "Do not show again".
func dont_show_again() -> bool:
	return _dont_show != null and _dont_show.button_pressed


## The message as the sheet prints it, the link phrase marked up.
func message_bbcode() -> String:
	if link_phrase == "" or link_tile == "" or not message.contains(link_phrase):
		return message
	var link := "[url=%s][color=#%s]%s[/color][/url]" % [LINK_META, (DS.PALETTE["ACCENT"] as Color).to_html(false), link_phrase]
	return message.replace(link_phrase, link)


func _message() -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = "Message"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.meta_underlined = true
	text.custom_minimum_size.x = WIDTH - 2.0 * LedgerV3.CONTENT_MARGIN
	text.add_theme_font_override("normal_font", Parts.FONT_BODY)
	text.add_theme_font_size_override("normal_font_size", Parts.BODY_PX + 1)
	text.add_theme_color_override("default_color", DS.PALETTE["TEXT"])
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	text.add_theme_constant_override("shadow_offset_x", 1)
	text.add_theme_constant_override("shadow_offset_y", 1)
	text.add_theme_constant_override("line_separation", 4)
	text.text = message_bbcode()
	text.set_meta("plain", message)
	text.meta_clicked.connect(func(_meta: Variant) -> void: open_link())
	return text


## The link pressed: the tile's Stockpile tab opens and the sheet stays, its decision still to make. The scrim
## clears and lets the pointer through, so the tab can be used behind the sheet.
func open_link() -> void:
	if link_tile == "":
		return
	if _scrim != null:
		_scrim.color.a = 0.0
		_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MatchState.tile_stockpile_requested.emit(link_tile)
