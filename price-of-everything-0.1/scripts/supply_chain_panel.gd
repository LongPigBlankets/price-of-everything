extends Control
## Supply-chain review shown when SELLING or DEMOLISHING a building. A diagram:
## buildings that FEED the target on the left, the target in the middle, buildings that
## DEPEND on it on the right. Each neighbour has a dropdown — "Auto fulfill" (let the
## market cover the gap) or "Pause production" (mothball it). Confirm applies the
## dispositions and then performs the sell/demolish. Dismissible (Cancel / Esc).
##
## DS-themed, built in code (buy_building_dialog shell). Read-only against the sim
## except the final action + SupplyChain.apply, both of which go through sim APIs.

const SupplyChain := preload("res://scripts/supply_chain.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")

const CARD_WIDTH := 1160.0
const COLUMN_MIN := 300.0
const COLUMN_MAX_HEIGHT := 460.0

signal finished(confirmed: bool)

var _target_iid := ""
var _action := "sell"            # "sell" | "demolish"
var _feeders: Array = []
var _dependents: Array = []
var _modes: Dictionary = {}      # neighbour iid -> "auto" | "pause"
var _content: VBoxContainer

func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(card)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", DS.SP["MD"])
	card.add_child(_content)
	visible = false

func open(target_iid: String, action: String) -> void:
	_target_iid = target_iid
	_action = action
	var nb: Dictionary = SupplyChain.neighbours(target_iid)
	_feeders = nb.get("feeders", [])
	_dependents = nb.get("dependents", [])
	_modes.clear()
	for row in _feeders:
		_modes[str(row.iid)] = "auto"
	for row in _dependents:
		_modes[str(row.iid)] = "auto"
	_rebuild(str(nb.get("target_name", "this building")))
	visible = true
	move_to_front()
	PanelStack.push(self)
	print("[SupplyChain] panel opened for %s (action=%s)" % [target_iid, action])

func _close(confirmed: bool) -> void:
	PanelStack.remove(self)
	visible = false
	finished.emit(confirmed)
	queue_free()

# --- build ---------------------------------------------------------------------------

func _rebuild(target_name: String) -> void:
	for c in _content.get_children():
		c.queue_free()

	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = ("Sell " if _action == "sell" else "Demolish ") + target_name
	_content.add_child(title)

	var summary := Label.new()
	summary.theme_type_variation = "Body"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = _summary_text()
	_content.add_child(summary)

	if _feeders.is_empty() and _dependents.is_empty():
		var none := Label.new()
		none.theme_type_variation = "Caption"
		none.text = "This building has no connected suppliers or customers."
		_content.add_child(none)
	else:
		var lead := Label.new()
		lead.theme_type_variation = "Caption"
		lead.text = "Decide what happens to each connected building once this one is gone:"
		_content.add_child(lead)
		_content.add_child(_diagram(target_name))

	# Footer: Cancel + Confirm.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", DS.SP["SM"])
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: _close(false))
	footer.add_child(cancel)
	var confirm := Button.new()
	confirm.theme_type_variation = "Primary"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.text = "Sell building" if _action == "sell" else "Demolish (1 turn)"
	confirm.pressed.connect(_on_confirm)
	footer.add_child(confirm)
	_content.add_child(footer)

func _diagram(target_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	row.add_child(_column("Feeds it", _feeders, COLUMN_MIN))
	row.add_child(_arrow("→"))
	row.add_child(_target_column(target_name))
	row.add_child(_arrow("→"))
	row.add_child(_column("Depends on it", _dependents, COLUMN_MIN))
	return row

func _column(heading: String, rows: Array, min_w: float) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(min_w, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", DS.SP["SM"])
	var head := Label.new()
	head.theme_type_variation = "Section"
	head.text = "%s  (%d)" % [heading, rows.size()]
	col.add_child(head)
	if rows.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = "Caption"
		empty.text = "None"
		col.add_child(empty)
		return col
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(COLUMN_MAX_HEIGHT, float(rows.size()) * 118.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", DS.SP["SM"])
	scroll.add_child(list)
	for r in rows:
		list.add_child(_neighbour_card(r))
	return col

func _neighbour_card(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", DS.SP["XS"])
	card.add_child(vb)
	var name := Label.new()
	name.theme_type_variation = "Body"
	name.text = str(row.name)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name)
	var goods := Label.new()
	goods.theme_type_variation = "Caption"
	goods.text = "via " + ", ".join(PackedStringArray(row.get("good_names", [])))
	vb.add_child(goods)
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.add_item("Auto fulfill", 0)          # market covers the gap
	pick.add_item("Pause production", 1)      # mothball
	pick.select(0 if str(_modes.get(str(row.iid), "auto")) == "auto" else 1)
	var iid := str(row.iid)
	pick.item_selected.connect(func(idx: int) -> void:
		_modes[iid] = "auto" if idx == 0 else "pause")
	vb.add_child(pick)
	return card

func _target_column(target_name: String) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(240.0, 0)
	col.add_theme_constant_override("separation", DS.SP["XS"])
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var card := PanelContainer.new()
	card.theme_type_variation = "Outlined"
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", DS.SP["XS"])
	card.add_child(cvb)
	var head := Label.new()
	head.theme_type_variation = "Section"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.text = "Sold" if _action == "sell" else "Demolished"
	cvb.add_child(head)
	var name := Label.new()
	name.theme_type_variation = "Body"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.text = target_name
	cvb.add_child(name)
	col.add_child(card)
	return col

func _arrow(glyph: String) -> Control:
	var l := Label.new()
	l.theme_type_variation = "Title"
	l.text = glyph
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	return l

func _summary_text() -> String:
	var b: Dictionary = MatchState.get_building(_target_iid)
	if _action == "sell":
		return "Selling transfers this building to an NPC operator for £%d — it keeps standing but stops running for you. Instant." \
			% int(round(float(BuildingPrice.sale_price(b))))
	var refund: Dictionary = MatchState.refund_cost(_target_iid)
	return "Demolishing removes it over 1 turn and frees its land. You get back ~£%d of materials (overflow as cash); no money is returned." \
		% int(round(float(refund.get("materials_value", 0.0))))

# --- confirm / dismiss ---------------------------------------------------------------

func _on_confirm() -> void:
	SupplyChain.apply(_feeders, _dependents, _modes)
	if _action == "sell":
		MatchState.sell_building(_target_iid)
	else:
		# SAY SO WHEN IT IS REFUSED. The result was dropped, so a demolition the sim declined —
		# most often "you don't own this" on a wood the land owns rather than a company — closed
		# the panel and did nothing at all, which reads as the button being broken.
		var outcome: Dictionary = MatchState.start_demolish(_target_iid)
		if not bool(outcome.get("ok", false)):
			MatchState.request_toast(str(outcome.get("reason", "That cannot be demolished.")),
				"error")
	_close(true)

func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close(false)

func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO
