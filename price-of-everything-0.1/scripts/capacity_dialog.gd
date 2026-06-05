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
const GOODS_FRAME := preload("res://assets/ui/goods_frame.tres")  # pipe frame, matches the title card

# Standard quantity pill (mirrors building_row._make_qty_badge).
const BADGE_DIAMETER := 24
const BADGE_TEXT_SIZE := 14
const BADGE_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const BADGE_PAPER := Color(0.995234, 0.930806, 0.763265, 1.0)
const ICON_SIZE := 100.0
const CARD_WIDTH := 340.0       # fixed so the icons can pin to the frame edges
const MONEY_FONT := preload("res://assets/fonts/BarlowCondensed-Bold.ttf")

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
	# Centred, capped at 400x400.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -400.0
	offset_right = 400.0
	offset_top = -270.0
	offset_bottom = 270.0
	custom_minimum_size = Vector2(800, 540)
	clip_contents = true   # backstop against overflow

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title)
	vb.add_child(HSeparator.new())

	# The three options sit on one row; the expand option is wider (stretch ratio 2).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_make_option_button("Sell surplus automatically", ACTION_SELL, 1.0))
	row.add_child(_make_option_button("Expand Logistics and Storage on tile by 500", ACTION_EXPAND, 2.0))
	row.add_child(_make_option_button("Stop Production on tile", ACTION_STOP, 1.0))
	vb.add_child(row)

	# "This will cost:" — compact row introducing the cost card below the options.
	var cost_label := Label.new()
	cost_label.text = "This will cost:"
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cost_label)

	# Framed goods card with the expansion materials.
	vb.add_child(_build_cost_section())

	# Divider, then the "don't ask again" label + tickbox pushed to the right.
	vb.add_child(HSeparator.new())
	var cb_row := HBoxContainer.new()
	cb_row.alignment = BoxContainer.ALIGNMENT_END
	cb_row.add_theme_constant_override("separation", 8)
	var cb_label := Label.new()
	cb_label.text = "Don't ask me again, apply to all tiles"
	cb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cb_row.add_child(cb_label)
	_checkbox = UIHelpers.make_custom_checkbox()
	cb_row.add_child(_checkbox)
	vb.add_child(cb_row)


func _make_option_button(text: String, action: String, ratio: float) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = false
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = ratio
	b.custom_minimum_size = Vector2(60, 0)   # let autowrap shrink width; share the 400 row
	b.pressed.connect(_choose.bind(action))
	return b


func _build_cost_section() -> Control:
	# A framed card (the pipe frame, matching the title card) holding the 60x60 good
	# icons — each with the standard quantity pill — and the money cost.
	# Fixed-width framed card. The icons are placed by anchor (not a row container):
	# the left icon's left edge and the right icon's right edge pin to the frame's
	# inner edges, the middle icon centres, and they overlap if 3x100 exceeds the
	# inner width. The money cost sits navy + bold along the bottom of the frame.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GOODS_FRAME)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var inner := Control.new()
	# Icons (100) at the top + 50px breathing room + the money strip (30) at the bottom.
	inner.custom_minimum_size = Vector2(0, ICON_SIZE + 50.0 + 30.0)
	card.add_child(inner)

	var mats := EXPAND_MATERIALS

	# Middle (centred), added first so the edge-pinned icons draw over it.
	var mid := _cost_cell(str(mats[1][0]), int(mats[1][1]))
	_anchor_slot(mid, 0.5, -ICON_SIZE / 2.0, ICON_SIZE / 2.0)
	inner.add_child(mid)

	# Left: left edge pinned to the frame's inner-left.
	var left := _cost_cell(str(mats[0][0]), int(mats[0][1]))
	_anchor_slot(left, 0.0, 0.0, ICON_SIZE)
	inner.add_child(left)

	# Right: right edge pinned to the frame's inner-right.
	var right := _cost_cell(str(mats[2][0]), int(mats[2][1]))
	_anchor_slot(right, 1.0, -ICON_SIZE, 0.0)
	inner.add_child(right)

	# Money cost: navy, bold, bottom of the frame.
	var money := Label.new()
	money.text = "and £%d" % EXPAND_MONEY
	money.add_theme_font_override("font", MONEY_FONT)
	money.add_theme_font_size_override("font_size", 22)
	money.add_theme_color_override("font_color", BADGE_NAVY)
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	money.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money.anchor_left = 0.0
	money.anchor_right = 1.0
	money.anchor_top = 1.0
	money.anchor_bottom = 1.0
	money.offset_top = -30.0
	inner.add_child(money)
	return card


func _anchor_slot(slot: Control, anchor_x: float, off_left: float, off_right: float) -> void:
	# Pin a 100x100 icon slot to the top of `inner` at the given horizontal anchor.
	slot.anchor_left = anchor_x
	slot.anchor_right = anchor_x
	slot.anchor_top = 0.0
	slot.anchor_bottom = 0.0
	slot.offset_left = off_left
	slot.offset_right = off_right
	slot.offset_top = 0.0
	slot.offset_bottom = ICON_SIZE


func _cost_cell(gid: String, qty: int) -> Control:
	# A 60x60 icon slot with the quantity pill overlaid on its corner.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := GoodIcons.texture_for(gid, Catalog.get_internal_name(gid))
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(tr)
	else:
		# Placeholder so the slot reads even when the good has no art yet.
		var ph := Label.new()
		ph.text = Catalog.get_display_name(gid)
		ph.add_theme_font_size_override("font_size", 9)
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(ph)
	slot.add_child(_make_qty_badge(qty, ICON_SIZE))
	return slot


func _make_qty_badge(qty: int, slot_size: float) -> Control:
	# Standard quantity pill (mirrors building_row._make_qty_badge): navy rounded
	# pill with paper border + text, anchored to the slot's bottom-right corner.
	var qty_text := str(qty)
	var h: int = BADGE_DIAMETER
	var w: int = h if qty_text.length() <= 1 else maxi(h, qty_text.length() * 9 + 14)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overlap: int = maxi(4, roundi(slot_size * 0.10))
	badge.offset_left = -w + overlap
	badge.offset_top = -h + overlap
	badge.offset_right = overlap
	badge.offset_bottom = overlap
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_NAVY
	style.border_color = BADGE_PAPER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(h / 2.0))
	style.set_content_margin_all(0)
	badge.add_theme_stylebox_override("panel", style)
	var ls := LabelSettings.new()
	ls.font_color = BADGE_PAPER
	ls.font_size = BADGE_TEXT_SIZE
	var label := Label.new()
	label.text = qty_text
	label.label_settings = ls
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge
