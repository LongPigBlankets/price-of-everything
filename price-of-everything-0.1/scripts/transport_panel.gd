extends PanelContainer
## Transport panel — the logistics dashboard behind the top bar's Transport module.
##
## Three columns, each answering a question the player could not previously ask:
##   Stockpiles       — which tiles are about to run out of room, and how soon
##   Infrastructure   — which links are over capacity, how often, and what it has cost
##   Units in transit — what is actually moving, and when it lands
##
## Everything here is a READ. The sim already knew all of it: freight has always
## carried its route and its arrival turn, tiles have always had a fill level — it
## simply had nowhere to be seen. The only genuinely new state is HISTORY (Stockpile's
## fill ring, MatchState's per-link over-capacity ring), because a trend and an ETA
## cannot be recovered from a single frame's snapshot.
##
## See docs/top-bar-v3-spec.md §3.

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const InfraIcons := preload("res://scripts/infra_icons.gd")

const PANEL_WIDTH := 1180.0
const PANEL_HEIGHT := 620.0
const COLUMN_MIN_WIDTH := 330.0
const HEADER_HEIGHT := 44.0
const GOOD_ICON := 56           # the frameless cream tile; the usual size for a good
const INFRA_ICON := 26          # the infrastructure's own building icon
const PILL_HEIGHT := 22

## The filter chips over the infrastructure column, in build order. Cables carry power
## rather than freight, so they are listed for completeness and simply never have rows.
const INFRA_FILTERS: Array[Dictionary] = [
	{"mode": "roads", "label": "Roads"},
	{"mode": "rail", "label": "Rails"},
	{"mode": "pipes", "label": "Pipes"},
	{"mode": "reinf_pipes", "label": "Reinf."},
	{"mode": "cables", "label": "Cables"},
]
const ROW_SEPARATION := 6

## A tile at or above this share of capacity counts as "full" — the same threshold the
## top bar counts with, so the module badge and this panel can never disagree.
const NEAR_FULL := 0.95
## Fill trend and the turns-until-full estimate look back this many turns (spec §3.2).
const TREND_TURNS := 3

var _stock_list: VBoxContainer
var _infra_list: VBoxContainer
var _transit_list: VBoxContainer
var _dragging := false
var _drag_offset := Vector2.ZERO
var _refresh_queued := false
var _infra_enabled: Dictionary = {}      # mode -> bool, driven by the filter chips


func _ready() -> void:
	name = "TransportPanel"
	theme = DS.theme
	theme_type_variation = "Card"
	visible = false
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# Coalesced (the notification-bell pattern the other panels use): stockpile_changed
	# fires per transaction during PROCESS — hundreds of times in one burst — and each
	# would otherwise tear down and rebuild all three columns.
	Stockpile.stockpile_changed.connect(_refresh_if_visible)
	MatchState.transport_shipments_changed.connect(_refresh_if_visible)
	TurnManager.turn_resolution_completed.connect(_refresh_if_visible)


func open() -> void:
	_refresh()
	visible = true
	_centre()
	move_to_front()
	PanelStack.push(self)


func _centre() -> void:
	var vp := get_viewport_rect().size
	position = ((vp - size) * 0.5).floor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)


func _refresh_if_visible(_a: Variant = null) -> void:
	if not visible or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")


func _apply_refresh() -> void:
	_refresh_queued = false
	if visible:
		_refresh()


# ── Chrome ────────────────────────────────────────────────────────────────────

func _build() -> void:
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, DS.SP.MD)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", DS.SP.SM)
	margin.add_child(root)

	root.add_child(_header())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", DS.SP.MD)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	_stock_list = _column(columns, "Stockpiles", "Fullest first")
	_infra_list = _column(columns, "Infrastructure", "Most congested first", _infra_filter_bar())
	_transit_list = _column(columns, "Units in transit", "Largest shipment first")


func _header() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	row.add_theme_constant_override("separation", DS.SP.SM)
	var title := Label.new()
	title.theme_type_variation = "Section"
	title.text = "Transport"
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	row.add_child(close)
	return row


## One titled, scrolling column. The subtitle is the sort order, and it rides on the
## RIGHT of the title's own row rather than taking a second line — three columns of
## two-line headers pushed the actual content down for no information gained.
##
## `extra` is dropped between the header and the list (the infrastructure filters).
func _column(parent: HBoxContainer, title: String, subtitle: String, extra: Control = null) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(COLUMN_MIN_WIDTH, 0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	parent.add_child(wrap)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", DS.SP.SM)
	wrap.add_child(head_row)
	var head := Label.new()
	head.theme_type_variation = "Section"
	head.add_theme_font_size_override("font_size", DS.FS.BODY + 4)
	head.text = title
	head_row.add_child(head)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(gap)
	var sub := Label.new()
	sub.theme_type_variation = "Body"
	sub.add_theme_font_size_override("font_size", DS.FS.CAPTION - 1)
	sub.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.text = subtitle
	head_row.add_child(sub)

	if extra != null:
		wrap.add_child(extra)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(list)
	return list


## Card behind one row. `clickable` gives it the hand cursor.
func _row_card(clickable: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.theme_type_variation = "Inset"
	if clickable:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return card


func _label(text: String, size: int = DS.FS.BODY, color: Color = DS.PALETTE.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Body"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _numeric(text: String, size: int = DS.FS.CAPTION, color: Color = DS.PALETTE.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Numeric"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _empty_note(list: VBoxContainer, text: String) -> void:
	var l := _label(text, DS.FS.CAPTION, DS.PALETTE.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(l)


func _clear(container: Node) -> void:
	# remove THEN free: queue_free is deferred, so the old rows would otherwise still be
	# laid out beside the new ones for one frame (the flicker _clear_now fixes in the bar).
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	_build_stockpiles()
	_build_infra()
	_build_transit()


# ── Column 1 · Stockpiles ─────────────────────────────────────────────────────

func _build_stockpiles() -> void:
	_clear(_stock_list)
	var rows: Array = []
	for tile_key in Stockpile.tiles_with_stock():
		var tile_id := str(tile_key)
		if not tile_id.begins_with("tile_"):
			continue   # the legacy global bucket is not a place on the map
		var cap := float(Stockpile.get_capacity(tile_id))
		if cap <= 0.0:
			continue
		var used := float(Stockpile.get_used_capacity(tile_id))
		rows.append({"tile_id": tile_id, "used": used, "cap": cap, "fill": used / cap})
	rows.sort_custom(func(a, b): return float(a.fill) > float(b.fill))
	if rows.is_empty():
		_empty_note(_stock_list, "No tile is holding goods yet.")
		return
	for row: Dictionary in rows:
		_stock_list.add_child(_stockpile_row(row))


func _stockpile_row(row: Dictionary) -> Control:
	var tile_id := str(row.tile_id)
	var fill := float(row.fill)
	var cap := float(row.cap)
	var card := _row_card(true)
	card.tooltip_text = "Open this tile's stockpile"
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			card.accept_event()
			MatchState.tile_stockpile_requested.emit(tile_id))

	var col := _card_body(card)

	# Line 1 — name, warehouse level, fill %, trend.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", DS.SP.SM)
	col.add_child(top)
	var name_label := _label(Catalog.tile_label(tile_id), DS.FS.BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	top.add_child(_label("L%d" % Stockpile.get_warehouse_level(tile_id), DS.FS.CAPTION - 1, DS.PALETTE.TEXT))
	top.add_child(_numeric("%d%%" % int(round(fill * 100.0)), DS.FS.CAPTION, _fill_color(fill)))
	var trend := Stockpile.fill_trend_per_turn(tile_id, TREND_TURNS)
	top.add_child(_label(_trend_glyph(trend, cap), DS.FS.CAPTION, _trend_color(trend, cap)))

	# Line 2 — the bar, then the raw numbers and how long the room lasts.
	col.add_child(_fill_bar(fill, _fill_color(fill)))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", DS.SP.SM)
	col.add_child(bottom)
	bottom.add_child(_numeric("%d / %d" % [int(row.used), int(cap)], DS.FS.CAPTION - 1, DS.PALETTE.TEXT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	bottom.add_child(_label(_full_eta_text(tile_id, fill), DS.FS.CAPTION - 1, _eta_color(tile_id, fill)))

	# Top goods, as the framed icons used everywhere else goods appear.
	var goods := Stockpile.get_top_goods(tile_id, 3)
	if not goods.is_empty():
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 4)
		col.add_child(icons)
		for g: Dictionary in goods:
			icons.add_child(_good_chip(str(g.good_id), int(g.qty)))
	return card


## Padded VBox inside a row card — the shared body layout for all three columns.
func _card_body(card: PanelContainer) -> VBoxContainer:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(m, DS.SP.SM)
	for m in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 6)
	card.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	pad.add_child(col)
	return col


## A good as the frameless cream tile, with its count as the navy pill overhanging the
## bottom-right — the placement the recipe cards use, so a good reads the same wherever
## it appears.
func _good_chip(good_id: String, qty: int) -> Control:
	var icon := UIHelpers.make_plain_good_icon(good_id, Catalog.get_internal_name(good_id), GOOD_ICON)
	icon.add_child(UIHelpers.make_overlaid_quantity_pill(_short_qty(qty), PILL_HEIGHT))
	return icon


func _fill_bar(fill: float, color: Color) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 6)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = DS.PALETTE.BG_INSET
	tsb.set_corner_radius_all(3)
	track.add_theme_stylebox_override("panel", tsb)
	var bar := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = color
	bsb.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.anchor_right = clampf(fill, 0.0, 1.0)
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	track.add_child(bar)
	return track


func _fill_color(fill: float) -> Color:
	if fill >= NEAR_FULL:
		return DS.PALETTE.DANGER
	if fill >= 0.75:
		return DS.PALETTE.WARN
	return DS.PALETTE.OK


## ▲ filling · ▼ draining · — steady. Steady is a BAND, not an exact zero: a tile
## drifting a couple of units a turn is not a trend the player should act on.
func _trend_glyph(rate: float, cap: float) -> String:
	var dead := maxf(1.0, cap * 0.01)
	if rate > dead:
		return "▲"
	if rate < -dead:
		return "▼"
	return "—"


func _trend_color(rate: float, cap: float) -> Color:
	var dead := maxf(1.0, cap * 0.01)
	if rate > dead:
		return DS.PALETTE.WARN
	if rate < -dead:
		return DS.PALETTE.OK
	return DS.PALETTE.TEXT


func _full_eta_text(tile_id: String, fill: float) -> String:
	if fill >= 1.0:
		return "FULL"
	var turns := Stockpile.turns_until_full(tile_id, TREND_TURNS)
	if turns < 0:
		return "not filling"
	if turns == 0:
		return "full now"
	return "full in %d turn%s" % [turns, "" if turns == 1 else "s"]


func _eta_color(tile_id: String, fill: float) -> Color:
	if fill >= 1.0:
		return DS.PALETTE.DANGER
	var turns := Stockpile.turns_until_full(tile_id, TREND_TURNS)
	if turns < 0:
		return DS.PALETTE.TEXT
	return DS.PALETTE.DANGER if turns <= 3 else DS.PALETTE.WARN


# ── Column 2 · Infrastructure ─────────────────────────────────────────────────

func _build_infra() -> void:
	_clear(_infra_list)
	var links: Array = []
	var hidden := 0
	for link_v in MatchState.active_links():
		var link: Dictionary = link_v
		if bool(_infra_enabled.get(str(link.mode), true)):
			links.append(link)
		else:
			hidden += 1
	if links.is_empty():
		if hidden > 0:
			_empty_note(_infra_list, "%d link%s hidden by the filters above." % [hidden, "" if hidden == 1 else "s"])
		else:
			_empty_note(_infra_list, "Nothing is crossing a road, rail or pipe this turn.")
		return
	for link: Dictionary in links:
		_infra_list.add_child(_infra_row(link))


func _infra_row(link: Dictionary) -> Control:
	var mode := str(link.mode)
	var ratio := float(link.ratio)
	var card := _row_card()
	var col := _card_body(card)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", DS.SP.SM)
	col.add_child(top)
	top.add_child(_infra_icon(mode))
	var name_label := _label("%s · %s" % [_mode_label(mode), Catalog.tile_label(str(link.tile_id))], DS.FS.CAPTION)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	top.add_child(_label("L%d" % int(link.level), DS.FS.CAPTION - 1, DS.PALETTE.TEXT))
	top.add_child(_numeric("%d%%" % int(round(ratio * 100.0)), DS.FS.CAPTION, _load_color(ratio)))

	# Over-capacity links pin the bar full; the % beside it carries the overshoot.
	col.add_child(_fill_bar(minf(ratio, 1.0), _load_color(ratio)))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", DS.SP.SM)
	col.add_child(bottom)
	bottom.add_child(_numeric("%d / %d units" % [int(round(float(link.flow))), int(round(float(link.cap)))],
		DS.FS.CAPTION - 1, DS.PALETTE.TEXT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var over_turns := MatchState.link_turns_over(str(link.key))
	bottom.add_child(_label("at cap %d of last %d" % [over_turns, MatchState.LINK_HISTORY_TURNS],
		DS.FS.CAPTION - 1, DS.PALETTE.WARN if over_turns > 0 else DS.PALETTE.TEXT))

	# Shown only once congestion has actually cost money — a £0 line on every clear
	# link would bury the ones that are really billing.
	var paid := MatchState.link_congestion_paid(str(link.key))
	if paid > 0.0:
		col.add_child(_label("congestion has added £%s so far" % _money(paid),
			DS.FS.CAPTION - 1, DS.PALETTE.DANGER))
	return card


func _load_color(ratio: float) -> Color:
	if ratio > 1.0:
		return DS.PALETTE.DANGER
	if ratio >= 0.85:
		return DS.PALETTE.WARN
	return DS.PALETTE.OK


func _mode_label(mode: String) -> String:
	match mode:
		"roads": return "Road"
		"rail": return "Rail"
		"pipes": return "Pipework"
		"reinf_pipes": return "Reinforced pipework"
	return mode.capitalize()


## The infrastructure's own building icon, so a road row is recognisably the thing the
## player built. Falls back to nothing rather than to a coloured square: the swatch this
## replaced said only 'road' twice, once in colour and once in words.
func _infra_icon(mode: String) -> Control:
	var holder := TextureRect.new()
	holder.custom_minimum_size = Vector2(INFRA_ICON, INFRA_ICON)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := InfraIcons.normalise(mode)
	var building: Dictionary = Catalog.get_building_by_internal_name(key)
	holder.texture = InfraIcons.texture_for(str(building.get("id", "")), key)
	return holder


## The filter chips above the infrastructure list. Every mode starts on, so the column
## opens showing everything and the filters only ever narrow it.
func _infra_filter_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for row: Dictionary in INFRA_FILTERS:
		var mode := str(row.mode)
		_infra_enabled[mode] = true
		var chip := Button.new()
		chip.text = str(row.label)
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", DS.FS.CAPTION - 2)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.toggled.connect(func(on: bool) -> void:
			_infra_enabled[mode] = on
			_build_infra())
		bar.add_child(chip)
	return bar


# ── Column 3 · Units in transit ───────────────────────────────────────────────

func _build_transit() -> void:
	_clear(_transit_list)
	var rows: Array = []
	for s in MatchState.pending_transport_shipments:
		var ship: Dictionary = s
		var manifest := _manifest(ship)
		var units := 0
		for entry: Dictionary in manifest:
			units += int(entry.qty)
		if units <= 0:
			continue
		rows.append({
			"manifest": manifest,
			"units": units,
			"turns": int(ship.get("turns_remaining", 0)),
			"to_market": bool(ship.get("is_sale", false)),
			"destination": str(ship.get("destination_tile", "")),
		})
	rows.sort_custom(func(a, b): return int(a.units) > int(b.units))
	if rows.is_empty():
		_empty_note(_transit_list, "Nothing is on the move.")
		return
	for row: Dictionary in rows:
		_transit_list.add_child(_transit_row(row))


## What a shipment is carrying, as [{good_id, qty}]. Sales carry an itemised
## sale_record; moves and purchases carry a single good.
func _manifest(ship: Dictionary) -> Array:
	var out: Array = []
	if bool(ship.get("is_sale", false)):
		for it in (ship.get("sale_record", {}) as Dictionary).get("items", []):
			var item: Dictionary = it
			if int(item.get("qty", 0)) > 0:
				out.append({"good_id": str(item.get("good_id", "")), "qty": int(item.get("qty", 0))})
		return out
	var gid := str(ship.get("good_id", ""))
	var qty := int(ship.get("qty", 0))
	if gid != "" and qty > 0:
		out.append({"good_id": gid, "qty": qty})
	return out


func _transit_row(row: Dictionary) -> Control:
	var card := _row_card()
	var col := _card_body(card)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", DS.SP.SM)
	col.add_child(outer)

	# The cargo itself: one framed icon per good, each with its count pill. A
	# multi-good shipment simply grows wider — the row is sized by what it carries.
	var goods := HBoxContainer.new()
	goods.add_theme_constant_override("separation", 6)
	goods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(goods)
	for entry: Dictionary in row.manifest:
		goods.add_child(_good_chip(str(entry.good_id), int(entry.qty)))

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 2)
	outer.add_child(right)

	var dest := HBoxContainer.new()
	dest.add_theme_constant_override("separation", 4)
	dest.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(dest)
	if bool(row.to_market):
		dest.add_child(_PortIcon.new(DS.PALETTE.ACCENT))
		dest.add_child(_label("Market", DS.FS.CAPTION - 1, DS.PALETTE.ACCENT))
	else:
		dest.add_child(_label(Catalog.tile_label(str(row.destination)), DS.FS.CAPTION - 1, DS.PALETTE.TEXT))

	var turns := int(row.turns)
	var eta := _numeric(("arrives now" if turns <= 0 else "%d turn%s" % [turns, "" if turns == 1 else "s"]),
		DS.FS.CAPTION, DS.PALETTE.TEXT)
	eta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(eta)
	return card


## Small harbour mark — a quay with a bollard, water beneath — flagging freight bound
## for the global market rather than another tile. Drawn: no port glyph in the font.
class _PortIcon extends Control:
	var color := Color.WHITE
	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(14, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_line(Vector2(1.0, h * 0.62), Vector2(w * 0.62, h * 0.62), color, 1.4, true)
		draw_line(Vector2(w * 0.30, h * 0.62), Vector2(w * 0.30, h * 0.22), color, 1.4, true)
		draw_circle(Vector2(w * 0.30, h * 0.20), 1.8, color)
		for i in 2:
			var y := h * (0.78 + 0.14 * float(i))
			draw_line(Vector2(1.0, y), Vector2(w - 1.0, y), Color(color, 0.45), 1.0, true)


# ── Formatting ────────────────────────────────────────────────────────────────

## Compact count for the quantity pill: 1200 -> "1.2k". The pill is a small capsule and
## a five-digit run would stretch it out of proportion with the icon beside it.
func _short_qty(qty: int) -> String:
	if qty < 1000:
		return str(qty)
	if qty < 10000:
		return "%.1fk" % (float(qty) / 1000.0)
	return "%dk" % int(round(float(qty) / 1000.0))


func _money(amount: float) -> String:
	var v := int(round(amount))
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("−" if v < 0 else "") + out


# ── Dragging (matches the other floating panels) ──────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
