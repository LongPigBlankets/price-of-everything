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
const CARD_WIDTH := 340.0       # fixed frame width; icons centre and shrink to fit
const OPTION_HEIGHT := 150.0    # the three choice cards; fixed so they cannot balloon
const OVERFLOW_ICON := 72.0     # goods shown filling the tile
const OVERFLOW_MAX := 4         # ...how many of them, biggest first
const MONEY_FONT := preload("res://assets/fonts/BarlowCondensed-Bold.ttf")

const ACTION_SELL := "sell_surplus"
const ACTION_EXPAND := "expand"
const ACTION_STOP := "stop"

var _title: Label
var _checkbox: CheckBox
var _sell_btn: Button
var _expand_btn: Button
var _stop_btn: Button
var _cost_label: Label
var _cost_holder: VBoxContainer     # per-tile cost card is rebuilt into this
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
	_refresh_for_tile()
	visible = true
	move_to_front()


# Rebuild the cost card and the Expand button for the tile now being shown: the material
# bill, whether it's affordable, and the capacity gain all depend on this tile's current
# warehouse level and live market prices, so this can't be baked once at build time.
func _refresh_for_tile() -> void:
	for c in _cost_holder.get_children():
		c.queue_free()
	var quote: Dictionary = MatchState.warehouse_upgrade_quote(_current_tile)
	if bool(quote.get("maxed", false)):
		# Storage maxed: expanding is off the table, so the card shows what is actually
		# filling the tile. That is the thing the player needs in order to choose between
		# selling the surplus and stopping production, and the dialog never showed it.
		_cost_label.text = "Filling this tile:"
		_cost_label.visible = true
		var overflow := _build_overflow_section(_current_tile)
		if overflow != null:
			_cost_holder.add_child(overflow)
		var note := Label.new()
		note.text = "This tile's warehouse is already fully upgraded."
		note.add_theme_font_size_override("font_size", 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cost_holder.add_child(note)
		_expand_btn.text = "Storage maxed"
		_expand_btn.disabled = true
		_expand_btn.tooltip_text = "This warehouse is already at its maximum level."
		return
	_cost_label.text = "This will cost:"
	_cost_label.visible = true
	_cost_holder.add_child(_build_cost_section(quote))
	var gain: int = int(quote.get("next_cap", 0)) - int(quote.get("current_cap", 0))
	_expand_btn.text = "Expand storage (+%d)" % gain
	var affordable: bool = bool(quote.get("empire_ok", false)) or bool(quote.get("money_ok", false))
	_expand_btn.disabled = not affordable
	_expand_btn.tooltip_text = "" if affordable else "You don't have the materials in stock, nor the cash to buy them."


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
			# Real per-tile warehouse upgrade (same path as the tile panel's Expand
			# Warehouse). Pay from empire stock when the full bill is on hand, else buy
			# the materials at market. Applies immediately; upgrade_warehouse toasts on
			# success. The Expand button is disabled when neither source can cover it, so
			# a click that reaches here can normally afford it — but guard anyway (the
			# "apply to all tiles" default path routes future tiles through here unseen).
			var quote: Dictionary = MatchState.warehouse_upgrade_quote(tile_id)
			if bool(quote.get("maxed", false)):
				return
			var source := "empire" if bool(quote.get("empire_ok", false)) else "market"
			var res: Dictionary = MatchState.upgrade_warehouse(tile_id, source)
			if not bool(res.get("ok", false)):
				MatchState.request_toast("Couldn't expand storage on %s (%s)." % [
					Catalog.tile_label(tile_id), str(res.get("reason", "?"))], "warning")
		ACTION_STOP:
			pass  # Stop-production is not built yet — the button is disabled ("Coming soon").


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
	# SHRINK, not EXPAND: with EXPAND the three buttons absorbed every spare pixel of the
	# 540 px dialog, and on a tile whose storage is already maxed — where there is no cost
	# card to fill the rest — they rendered as three enormous empty boxes.
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.custom_minimum_size = Vector2(0, OPTION_HEIGHT)
	_sell_btn = _make_option_button("Sell surplus automatically", ACTION_SELL, 1.0)
	row.add_child(_sell_btn)
	_expand_btn = _make_option_button("Expand storage", ACTION_EXPAND, 2.0)
	row.add_child(_expand_btn)
	_stop_btn = _make_option_button("Stop Production on tile", ACTION_STOP, 1.0)
	# Not built yet: show it, but greyed out with a "Coming soon" hint on hover.
	_stop_btn.disabled = true
	_stop_btn.tooltip_text = "Coming soon"
	row.add_child(_stop_btn)
	vb.add_child(row)

	# "This will cost:" — compact row introducing the cost card below the options.
	_cost_label = Label.new()
	_cost_label.text = "This will cost:"
	_cost_label.add_theme_font_size_override("font_size", 12)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_cost_label)

	# Framed goods card with the expansion materials — populated per tile in _show_next.
	_cost_holder = VBoxContainer.new()
	_cost_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_cost_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_cost_holder)

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
	b.size_flags_vertical = Control.SIZE_FILL
	b.size_flags_stretch_ratio = ratio
	b.custom_minimum_size = Vector2(60, 0)   # let autowrap shrink width; share the 400 row
	b.pressed.connect(_choose.bind(action))
	return b


## The goods actually filling the tile, biggest first, in the same framed cream card the
## cost section uses. Returns null when the tile is somehow empty.
func _build_overflow_section(tile_id: String) -> Control:
	var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
	var rows: Array = []
	for gid_variant: Variant in totals:
		var qty := int(totals[gid_variant])
		if qty > 0:
			rows.append({"good_id": str(gid_variant), "qty": qty})
	if rows.is_empty():
		return null
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["qty"]) > int(b["qty"]))
	rows = rows.slice(0, OVERFLOW_MAX)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GOODS_FRAME)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(pad)
	var icons_row := HBoxContainer.new()
	icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icons_row.add_theme_constant_override("separation", 6)
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant
		icons_row.add_child(_cost_cell(str(row["good_id"]), int(row["qty"]), OVERFLOW_ICON))
	pad.add_child(icons_row)
	return card

func _build_cost_section(quote: Dictionary) -> Control:
	# A framed cream card (the pipe frame, matching the title card) holding the REAL
	# warehouse-upgrade materials from the quote — each good icon carries the standard
	# quantity pill — with a navy line below saying how the works are paid for. The icons
	# sit in a centred row that shrinks for the four-material L2→L3 bill so it still fits
	# the fixed-width frame.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", GOODS_FRAME)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var mats: Array = quote.get("materials", [])
	# Full 100px icons for the three-material L1→L2 bill; shrink to 72 for the four
	# materials of L2→L3 so the row stays inside the frame.
	var icon_px: float = ICON_SIZE if mats.size() <= 3 else 72.0
	var icons_row := HBoxContainer.new()
	icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icons_row.add_theme_constant_override("separation", 8 if mats.size() <= 3 else 4)
	for m in mats:
		icons_row.add_child(_cost_cell(str(m.get("good_id", "")), int(m.get("qty", 0)), icon_px))
	col.add_child(icons_row)

	# Payment line: pull from your own stock when you hold the whole bill, otherwise buy
	# it at market — this mirrors what _apply_action(EXPAND) will actually do.
	var pay := Label.new()
	if bool(quote.get("empire_ok", false)):
		pay.text = "from your stockpiles"
	else:
		pay.text = "£%d at market" % int(round(float(quote.get("market_total", 0.0))))
	pay.add_theme_font_override("font", MONEY_FONT)
	pay.add_theme_font_size_override("font_size", 20)
	pay.add_theme_color_override("font_color", BADGE_NAVY)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pay)
	return card


func _cost_cell(gid: String, qty: int, size: float) -> Control:
	# A square icon slot with the quantity pill overlaid on its bottom-right corner.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size, size)
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
	slot.add_child(_make_qty_badge(qty, size))
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
