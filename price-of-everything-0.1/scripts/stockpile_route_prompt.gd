extends PanelContainer
## Optional follow-up to a player-selected stockpile route. The existing route stays valid.
const Guidance := preload("res://scripts/stockpile_guidance.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
static var _pending: Array = []
static var _active: WeakRef
static var _dont_show_again := false # Session-only, like the tile surplus confirmation.
var _tile := ""
var _good := ""
var _closing := false
var _dont_show: CheckBox

static func offer(host: Node, tile: String, good: String) -> void:
	if _dont_show_again or tile == "" or good == "" or Tutorial.active or TurnManager.is_resolving:
		return
	_pending.append({"host": weakref(host), "tile": tile, "good": good})
	_offer_next()

static func offer_split(host: Node, instance_id: String, good: String) -> void:
	for destination: Dictionary in MatchState.get_output_split_destinations(instance_id, good):
		offer(host, str(destination.get("tile_id", "")), good)

static func _offer_next() -> void:
	if _dont_show_again:
		_pending.clear()
		return
	if _active != null and is_instance_valid(_active.get_ref()):
		return
	if _pending.is_empty():
		return
	var request: Dictionary = _pending.pop_front()
	var host: Node = request.host.get_ref()
	if not is_instance_valid(host) or not host.is_inside_tree():
		_offer_next()
		return
	var prompt := (load("res://scripts/stockpile_route_prompt.gd") as GDScript).new() as PanelContainer
	_active = weakref(prompt)
	prompt.set("_tile", request.tile)
	prompt.set("_good", request.good)
	prompt.tree_exited.connect(func() -> void:
		_active = null
		_offer_next.call_deferred(), CONNECT_ONE_SHOT)
	var layer := CanvasLayer.new()
	layer.layer = 130
	host.add_child(layer)
	layer.add_child(prompt)
	prompt.call_deferred("_open")

func _open() -> void:
	if _dont_show_again:
		_close()
		return
	var projection := Guidance.estimate(_tile, _good)
	if bool(projection.auto_sell) or int(projection.growth) <= 0:
		_close()
		return
	name = "StockpileRoutePrompt"
	theme = DS.theme
	theme_type_variation = &"Card"
	custom_minimum_size = Vector2(520, 0)
	set_anchors_preset(Control.PRESET_CENTER)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	_add_text(col, "Surplus at " + Catalog.tile_label(_tile), "Title")
	_add_text(col, "%d units of %s will accumulate in stockpile each turn instead of selling, which will reduce your profit." % [projection.growth, Catalog.get_display_name(_good)], "Body")
	_add_text(col, "Confirm if you want to sell the surplus your buildings on the tile don't need or keep all as stock.", "Body")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	var sell := Button.new()
	sell.name = "EnableGoodSurplus"
	sell.text = "Sell surplus"
	sell.theme_type_variation = &"Primary"
	sell.pressed.connect(func() -> void:
		_dont_show_again = _dont_show.button_pressed
		MatchState.enable_auto_sell_good(_tile, _good)
		MatchState.request_toast("Surplus %s at %s will be sold each turn." % [Catalog.get_display_name(_good), Catalog.tile_label(_tile)], "success")
		_close())
	buttons.add_child(sell)
	var keep := Button.new()
	keep.name = "KeepSurplusStock"
	keep.text = "Keep all as stock"
	keep.pressed.connect(func() -> void:
		_dont_show_again = _dont_show.button_pressed
		Guidance.retain_intentionally(_tile, _good)
		_close())
	buttons.add_child(keep)
	_dont_show = UIHelpers.make_custom_checkbox()
	_dont_show.name = "DontShowSurplusAgain"
	col.add_child(UIHelpers.make_setting_row("Don't show again", _dont_show))
	visibility_changed.connect(func() -> void:
		if not visible:
			_close())
	PanelStack.push(self)
	await get_tree().process_frame
	position = (get_viewport_rect().size - size) * 0.5

func _add_text(parent: Node, text: String, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = StringName(variation)
	label.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 484
	parent.add_child(label)

func _close() -> void:
	if _closing:
		return
	_closing = true
	PanelStack.remove(self)
	get_parent().queue_free()
