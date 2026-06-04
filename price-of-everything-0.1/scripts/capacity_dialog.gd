extends PanelContainer
# Modal shown when a tile FIRST reaches its maximum storage capacity. Offers three
# ways to proceed and an optional "apply to all tiles from now on" default. Built
# entirely in code; instantiated by world_map.gd and parented to the HUD.
#
# Listens to Stockpile.tile_reached_capacity. One tile is handled at a time; further
# tiles that fill while the dialog is open are queued. A per-tile latch means a tile
# is only ever asked about once. If "Don't ask me again" is ticked, the chosen action
# becomes the standing default and is applied silently to every future tile.

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")

# Placeholder expansion cost (hardcoded for now): 10 steel, 10 concrete, 10 copper
# wiring + £50.  g_006 steel, g_017 concrete, g_007 copper_wiring.
const EXPAND_MATERIALS := [["g_006", 10], ["g_017", 10], ["g_007", 10]]
const EXPAND_MONEY := 50

const ACTION_SELL := "sell_surplus"
const ACTION_EXPAND := "expand"
const ACTION_STOP := "stop"

var _title: Label
var _checkbox: CheckBox
var _default_action: String = ""    # "" = always ask; otherwise applied to every tile
var _decided: Dictionary = {}       # tile_id -> true once handled
var _queue: Array = []              # tiles waiting for a decision
var _current_tile: String = ""


func _ready() -> void:
	_build_ui()
	visible = false
	if Stockpile.has_signal("tile_reached_capacity"):
		Stockpile.tile_reached_capacity.connect(_on_tile_reached_capacity)


func _on_tile_reached_capacity(tile_id: String) -> void:
	if tile_id == "" or bool(_decided.get(tile_id, false)):
		return
	# A standing default applies immediately — no prompt.
	if _default_action != "":
		_apply_action(_default_action, tile_id)
		_decided[tile_id] = true
		return
	if tile_id == _current_tile or _queue.has(tile_id):
		return
	_queue.append(tile_id)
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_current_tile = ""
		visible = false
		return
	_current_tile = str(_queue.pop_front())
	_title.text = "Tile %s has reached maximum capacity.\nHow do you want to proceed?" % Catalog.tile_label(_current_tile)
	_checkbox.button_pressed = false
	visible = true
	move_to_front()


func _choose(action: String) -> void:
	var tile := _current_tile
	if tile != "":
		_apply_action(action, tile)
		_decided[tile] = true
	# "Don't ask me again" — promote to the standing default and clear the backlog.
	if _checkbox.button_pressed:
		_default_action = action
		for t in _queue:
			if not bool(_decided.get(t, false)):
				_apply_action(action, str(t))
				_decided[t] = true
		_queue.clear()
	_current_tile = ""
	_show_next()


func _apply_action(action: String, tile_id: String) -> void:
	match action:
		ACTION_SELL:
			# Real behaviour: stand up an auto-sell-surplus order on the tile so its
			# surplus is sold to market every turn (visible under Transactions),
			# keeping room for the goods the tile actually uses. Uncapped impact so it
			# can always clear the overflow.
			MatchState.enable_sell_surplus(tile_id)
			if MatchState.has_method("set_auto_sell_impact"):
				MatchState.set_auto_sell_impact(tile_id, MatchState.IMPACT_ANY)
		ACTION_EXPAND:
			pass  # Storage expansion not implemented yet (cost shown, no effect).
		ACTION_STOP:
			pass  # Stop-production not implemented yet (no such concept yet).


func _build_ui() -> void:
	theme = DS.theme
	# Centre on screen.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -240.0
	offset_right = 240.0
	offset_top = -190.0
	offset_bottom = 190.0

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title)
	vb.add_child(HSeparator.new())

	# Option 1 — sell surplus automatically (the one that actually does something).
	vb.add_child(_make_option_button("Sell surplus automatically", ACTION_SELL))
	var hint := Label.new()
	hint.text = "Creates a standing sale for this tile's surplus every turn, keeping room for what it uses. Shown under Transactions."
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	# Option 2 — expand storage (+500). Cost shown; no effect yet.
	vb.add_child(_make_option_button("Expand Logistics and Storage on tile by 500. This will cost:", ACTION_EXPAND))
	vb.add_child(_build_cost_section())

	# Option 3 — stop production (no effect yet).
	vb.add_child(_make_option_button("Stop Production on tile", ACTION_STOP))

	vb.add_child(HSeparator.new())

	# "Don't ask me again" — applies the chosen action to all future tiles.
	_checkbox = UIHelpers.make_custom_checkbox()
	vb.add_child(UIHelpers.make_setting_row(
		"Don't ask me again, apply this to all tiles if they hit capacity", _checkbox))


func _make_option_button(text: String, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = false
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_choose.bind(action))
	return b


func _build_cost_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	for m in EXPAND_MATERIALS:
		var gid := str(m[0])
		var qty := int(m[1])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := GoodIcons.texture_for(gid, Catalog.get_internal_name(gid))
		if icon != null:
			var tr := TextureRect.new()
			tr.texture = icon
			tr.custom_minimum_size = Vector2(18, 18)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tr)
		var lbl := Label.new()
		lbl.text = "%d  %s" % [qty, Catalog.get_display_name(gid)]
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)
		box.add_child(row)
	var money := Label.new()
	money.text = "£%d" % EXPAND_MONEY
	money.add_theme_font_size_override("font_size", 12)
	box.add_child(money)
	return box
