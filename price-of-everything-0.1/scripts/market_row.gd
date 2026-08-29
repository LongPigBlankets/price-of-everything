extends VBoxContainer
## A market goods row: 60x60 icon + name button + market/cost columns, with an
## expandable Sell / Purchase / Move / Expand action block underneath.

const UIHelpers := preload("res://scripts/ui_helpers.gd")

const ICON_SIZE := 98      # outer plate; icon fills ICON_SIZE - 2×12px frame margin
const NAME_W := 240.0
const NAME_MAX_CHARS := 24
# Name font is sized as large as possible while the longest real name still fits
# the button with NAME_RIGHT_PAD px clear of the right edge.
const NAME_BOUND := "Electrical Components"
const NAME_RIGHT_PAD := 20.0
const NAME_FS_MAX := 30
const NAME_FS_MIN := 14
# Kept in sync with market_panel.gd's COL_PRICE_W / COL_EST_W (separate containers — a
# mismatch silently skews every column to the right of it).
const COL_PRICE := 104.0
const COL_SOLD := 60.0
const COL_COST := 100.0
const COL_PROFIT := 110.0
const FIELD_FS := 19  # larger per-field text
# The collapsible impact-ladder group: one narrow cell per EconomyConfig ladder
# rung, packed in a nested HBox with its own tighter separation.
const COL_RUNG := 74.0     # holds a 5-digit quantity and the 3-line header above it
const RUNG_SEP := 4
const RUNG_FS := 16
const RUNG_ACTIVE_TINT := Color(0.95, 0.72, 0.22, 0.30)  # amber: the rung you are on
const RUNG_IDLE_TINT := Color(0.50, 0.53, 0.58, 0.10)

const COST_GREEN := Color(0.36, 0.82, 0.40)
const COST_AMBER := Color(0.95, 0.72, 0.22)
const COST_RED := Color(0.90, 0.38, 0.38)
const COST_GREY := Color(0.62, 0.62, 0.62)
const COST_LEGEND := "Green: cheaper than market (<90%) · Amber: about even (90–110%) · Red: dearer than market (>110%)"
# Column tints: the sale pair (light grey) and the purchase pair (medium grey).
const SALE_TINT := Color(0.82, 0.85, 0.90, 0.10)
const BUY_TINT := Color(0.50, 0.53, 0.58, 0.22)

var good_id: String = ""
var internal_name: String = ""

var _price_label: Label = null
var _buy_price_label: Label = null
var _impact_group: HBoxContainer = null
var _rung_cells: Array[Label] = []
var _sold_label: Label = null
var _cost_label: Label = null
var _profit_label: Label = null
var _expand_section: VBoxContainer = null
var _expanded := false

func setup(good_data: Dictionary) -> void:
	good_id = str(good_data.get("id", ""))
	internal_name = str(good_data.get("internal_name", ""))

	var main := HBoxContainer.new()
	main.custom_minimum_size = Vector2(0, ICON_SIZE)  # row height == icon == name button
	main.add_theme_constant_override("separation", 10)
	add_child(main)

	# Icon sits inside the off-white pipe-frame slot. Shared with the mapmode good
	# picker (UIHelpers) so both stay identical. The 98px row uses the small art.
	main.add_child(UIHelpers.make_framed_good_icon(good_id, internal_name, ICON_SIZE))

	# Name button, truncated to NAME_MAX_CHARS so long names don't blow out the column.
	var disp := str(good_data.get("display_name", good_id))
	if disp.length() > NAME_MAX_CHARS:
		disp = disp.substr(0, NAME_MAX_CHARS) + "…"
	var name_btn := Button.new()
	name_btn.text = disp
	name_btn.clip_text = true
	name_btn.custom_minimum_size = Vector2(NAME_W, ICON_SIZE)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_toggle_expand)
	main.add_child(name_btn)
	name_btn.add_theme_font_size_override("font_size", _fit_name_font_size(name_btn))

	# Base columns (owner ruling 2026-08-29): buy price, sale price, sold, cost,
	# profit. The forecast columns are gone — with decay retired a forecast is
	# identical to the current price for any good the player isn't pressuring —
	# and the ladder detail lives in the collapsible impact group instead.
	_buy_price_label = _make_col(COL_PRICE)
	_price_label = _make_col(COL_PRICE)
	_sold_label = _make_col(COL_SOLD)
	_cost_label = _make_col(COL_COST)
	_profit_label = _make_col(COL_PROFIT)
	_tint_col(_buy_price_label, BUY_TINT)
	_tint_col(_price_label, SALE_TINT)
	for l in [_buy_price_label, _price_label, _sold_label, _cost_label, _profit_label]:
		main.add_child(l)
	_build_impact_group(main)

	_expand_section = VBoxContainer.new()
	_expand_section.visible = false
	_expand_section.add_theme_constant_override("separation", 4)
	for action in ["Sell", "Purchase", "Move", "Expand"]:
		var b := Button.new()
		b.text = action
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if action == "Expand":
			b.pressed.connect(_on_expand_to_construct)
		elif action == "Move":
			b.pressed.connect(_on_move)
		elif action == "Purchase":
			b.pressed.connect(_on_purchase)
			if not Catalog.is_good_buyable(good_id):
				b.disabled = true
				b.tooltip_text = "This good can't be bought from the market."
		_expand_section.add_child(b)
	add_child(_expand_section)

	if not CostSolver.costs_updated.is_connected(_on_costs_updated):
		CostSolver.costs_updated.connect(_on_costs_updated)
	if not Production.turn_processed.is_connected(_on_turn_processed):
		Production.turn_processed.connect(_on_turn_processed)
	visibility_changed.connect(_on_row_visibility_changed)
	_refresh()

# ── Filter helpers (used by the market panel's filter bar) ───────────────────
## True when the player actually produces this good (a unit cost has been solved).
func is_produced() -> bool:
	return CostSolver.get_good_unit_cost(good_id) >= 0.0

## Profit per unit sold to market last turn, or NAN when there were no sales.
func profit_per_unit() -> float:
	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = summary.get("sold", {}).get(good_id, {})
	var sold_qty := int(sold_entry.get("qty", 0))
	if sold_qty <= 0:
		return NAN
	var uc: float = CostSolver.get_good_unit_cost(good_id)
	var sale_price := float(sold_entry.get("revenue", 0.0)) / float(sold_qty)
	return sale_price - (uc if uc >= 0.0 else 0.0)

func _fit_name_font_size(btn: Button) -> int:
	# Largest font size (<= NAME_FS_MAX) at which NAME_BOUND fits the button width
	# with NAME_RIGHT_PAD px clear of the right edge. Measured against the button's
	# actual theme font + left content margin so it stays correct if the theme changes.
	var font := btn.get_theme_font("font")
	if font == null:
		return NAME_FS_MAX
	var left_margin := 8.0
	var sb := btn.get_theme_stylebox("normal")
	if sb != null:
		left_margin = maxf(0.0, sb.get_margin(SIDE_LEFT))
	var avail := NAME_W - left_margin - NAME_RIGHT_PAD
	var fs := NAME_FS_MAX
	while fs > NAME_FS_MIN:
		if font.get_string_size(NAME_BOUND, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
			break
		fs -= 1
	return fs


## The collapsible impact-ladder group: one cell per EconomyConfig ladder rung,
## showing the %/turn at that step, with the rung the player's 10-turn average
## net volume currently sits on highlighted in amber. Hidden until the panel's
## "impact ladder" toggle expands it. Cell content is refreshed per turn — the
## unit thresholds inflate as the world economy grows, and the highlight follows
## the rolling average.
func _build_impact_group(main: HBoxContainer) -> void:
	_impact_group = HBoxContainer.new()
	_impact_group.add_theme_constant_override("separation", RUNG_SEP)
	_impact_group.visible = false
	for i in EconomyConfig.PRICE_IMPACT_LADDER.size():
		var cell := Label.new()
		cell.custom_minimum_size = Vector2(COL_RUNG, ICON_SIZE)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_theme_font_size_override("font_size", RUNG_FS)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP  # tooltips on a plain Label need this
		_rung_cells.append(cell)
		_impact_group.add_child(cell)
	# Trailing clearance so the scroll bar doesn't sit over the last rung.
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(14, 0)
	_impact_group.add_child(tail)
	main.add_child(_impact_group)

## Show/hide the ladder columns (driven by the market panel's toggle).
func set_impact_expanded(expanded: bool) -> void:
	if _impact_group == null:
		return
	_impact_group.visible = expanded
	if expanded:
		_refresh_impact_cells()

## The rung index the player's 10-turn average net volume sits on, or -1.
func _active_rung() -> int:
	var base_out := Catalog.base_output_for_good(good_id)
	if base_out <= 0:
		return -1
	var v: float = absf(MarketState.rolling_net_volume(good_id))
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var active := -1
	for i in EconomyConfig.PRICE_IMPACT_LADDER.size():
		if v > float(EconomyConfig.PRICE_IMPACT_LADDER[i][0]) * float(base_out) * scale:
			active = i
		else:
			break
	return active

## Each cell carries THIS GOOD'S quantity for that column's rate (owner 2026-08-29): the
## rate is identical down a column and lives in the header, while the units that trigger it
## differ per good and grow with the world economy — so the number in the table is the one
## the player actually has to act on.
func _refresh_impact_cells() -> void:
	var thresholds: PackedInt32Array = MarketState.impact_thresholds(good_id)
	var avg: float = MarketState.rolling_net_volume(good_id)
	var active := _active_rung()
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var base_out := Catalog.base_output_for_good(good_id)
	for i in _rung_cells.size():
		var cell := _rung_cells[i]
		var rate := float(EconomyConfig.PRICE_IMPACT_LADDER[i][1])
		var mult := String.num(float(EconomyConfig.PRICE_IMPACT_LADDER[i][0]), 0)
		if thresholds.is_empty():
			cell.text = "—"
			cell.tooltip_text = "No production recipe — this good has no base output and takes no impact."
			_tint_col(cell, RUNG_IDLE_TINT)
			continue
		cell.text = _thousands(thresholds[i])
		var tip := "%s: sell (or buy) more than %s in one turn and its price moves %s%%/turn.\n" % [
			Catalog.get_display_name(good_id), _thousands(thresholds[i]), String.num(rate, 2)]
		tip += "That is %s× its base output of %d/turn (its best un-researched recipe), at today's ×%s threshold growth." % [
			mult, base_out, String.num(scale, 2)]
		if i == active:
			tip += "\nYOU ARE HERE — your 10-turn average net volume is %s %s/turn." % [
				String.num(absf(avg), 1), "sold" if avg > 0.0 else "bought"]
		cell.tooltip_text = tip
		_tint_col(cell, RUNG_ACTIVE_TINT if i == active else RUNG_IDLE_TINT)


## 1240 -> "1,240". These volumes run to five digits late game and read badly unseparated.
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


## Which way this good's price is headed: -1 falling, +1 rising, 0 steady.
## Mirrors MarketState's regime logic (accrue while the 10-turn average is over
## the first rung; otherwise walk home to base) so the arrow can't disagree
## with the simulation.
func _price_direction() -> int:
	var avg: float = MarketState.rolling_net_volume(good_id)
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var rate: float = EconomyConfig.price_impact_rate(avg, Catalog.base_output_for_good(good_id), scale)
	var a: float = MarketState.get_impact_pct(good_id)
	if rate > 0.0:
		return -1 if avg > 0.0 else 1
	if absf(a) > 0.0005:
		return 1 if a < 0.0 else -1
	return 0

func _direction_tooltip(dir: int) -> String:
	var avg: float = MarketState.rolling_net_volume(good_id)
	var a: float = MarketState.get_impact_pct(good_id)
	if dir == 0:
		if absf(avg) > 0.0:
			return "Steady — your recent market volume is under the first impact threshold."
		return "Steady — you are not moving this market."
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var rate: float = EconomyConfig.price_impact_rate(avg, Catalog.base_output_for_good(good_id), scale)
	if rate > 0.0:
		return "%s %s%%/turn — your 10-turn average net volume (%s/turn %s) is over the impact threshold. Current impact: %s%%." % [
			"Falling" if dir < 0 else "Rising", String.num(rate, 2),
			String.num(absf(avg), 1), "sold" if avg > 0.0 else "bought",
			String.num(a, 1)]
	return "%s — your volume has eased off, so the price is walking back to base over %d turns (impact now %s%%)." % [
		"Recovering" if dir > 0 else "Easing back down", EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS, String.num(a, 1)]

func _make_col(width: float) -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(width, ICON_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", FIELD_FS)
	return l

func _tint_col(l: Label, tint: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.content_margin_left = 6
	box.content_margin_right = 6
	l.add_theme_stylebox_override("normal", box)

func _toggle_expand() -> void:
	_expanded = not _expanded
	_expand_section.visible = _expanded

func _on_expand_to_construct() -> void:
	MatchState.show_construct_for_good.emit(good_id)

func _on_move() -> void:
	MatchState.transfer_for_good_requested.emit(good_id)

func _on_purchase() -> void:
	MatchState.purchase_for_good_requested.emit(good_id)

# Off-screen rows don't repaint — once built, every row used to refresh twice
# per turn (costs_updated + turn_processed) whether or not the Market panel was
# even open. Off-screen rows now just mark themselves stale and catch up when
# they actually become visible (panel opened / tab switched).
var _stale := false

func _on_turn_processed(_summary: Dictionary) -> void:
	_queue_row_refresh()

func _on_costs_updated() -> void:
	_queue_row_refresh()

func _queue_row_refresh() -> void:
	if not is_visible_in_tree():
		_stale = true
		return
	_refresh()

func _on_row_visibility_changed() -> void:
	if _stale and is_visible_in_tree():
		_stale = false
		_refresh()

func _refresh() -> void:
	if _price_label == null:
		return
	# When glut/deficit impact is active, show the actual price with the
	# impact-free base price of the turn in brackets underneath. A direction
	# arrow says which way the price is headed (falling red / rising green),
	# derived from the same regime logic the simulation runs on.
	var impact: float = MarketState.get_impact_pct(good_id)
	var has_impact := absf(impact) > 0.0005
	var impact_mult := 1.0 + impact / 100.0
	var dir := _price_direction()
	var arrow := "" if dir == 0 else (" ▼" if dir < 0 else " ▲")
	var dir_tip := _direction_tooltip(dir)
	var sale_now: float = MarketState.get_price(good_id)
	_price_label.text = ("£%.2f%s\n(£%.2f)" % [sale_now, arrow, MarketState.get_base_price_now(good_id)]) if has_impact \
		else "£%.2f%s" % [sale_now, arrow]
	_price_label.tooltip_text = dir_tip
	var buy_now: float = MarketState.get_buy_price(good_id)
	_buy_price_label.text = ("£%.2f%s\n(£%.2f)" % [buy_now, arrow, buy_now / impact_mult]) if has_impact \
		else "£%.2f%s" % [buy_now, arrow]
	_buy_price_label.tooltip_text = dir_tip
	for pl: Label in [_price_label, _buy_price_label]:
		if dir < 0:
			pl.add_theme_color_override("font_color", COST_RED)
		elif dir > 0:
			pl.add_theme_color_override("font_color", COST_GREEN)
		else:
			pl.remove_theme_color_override("font_color")

	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = summary.get("sold", {}).get(good_id, {})
	var sold_qty := int(sold_entry.get("qty", 0))
	var sold_rev := float(sold_entry.get("revenue", 0.0))
	var bought_qty := int(summary.get("purchased", {}).get(good_id, 0))
	_sold_label.text = str(sold_qty)
	_sold_label.tooltip_text = "Sold to market last turn: %d · Bought: %d\n10-turn average net volume: %s — the number the price impact model reads." % [
		sold_qty, bought_qty, String.num(MarketState.rolling_net_volume(good_id), 1)]
	if _impact_group != null and _impact_group.visible:
		_refresh_impact_cells()

	var uc: float = CostSolver.get_good_unit_cost(good_id)
	var price: float = MarketState.get_price(good_id)
	if uc < 0.0:
		_cost_label.text = "—"
		_cost_label.add_theme_color_override("font_color", COST_GREY)
		_cost_label.tooltip_text = "Not produced yet.\n" + COST_LEGEND
	else:
		var pct: float = (uc / price * 100.0) if price > 0.0 else 0.0
		var color := COST_AMBER
		if pct < 90.0:
			color = COST_GREEN
		elif pct > 110.0:
			color = COST_RED
		_cost_label.text = "£%.2f" % uc
		_cost_label.add_theme_color_override("font_color", color)
		_cost_label.tooltip_text = "Production cost per unit: £%.2f (%.1f%% of market)\n%s" % [uc, pct, COST_LEGEND]

	if sold_qty > 0:
		var sale_price := sold_rev / float(sold_qty)
		var profit := sale_price - (uc if uc >= 0.0 else 0.0)
		_profit_label.text = "£%.2f" % profit
		_profit_label.add_theme_color_override("font_color", COST_GREEN if profit > 0.0 else COST_RED)
		_profit_label.tooltip_text = "Profit per unit = avg sale £%.2f − cost £%.2f" % [sale_price, maxf(0.0, uc)]
	else:
		_profit_label.text = "No sales"
		_profit_label.add_theme_color_override("font_color", COST_GREY)
		_profit_label.tooltip_text = "No units sold to market last turn."
