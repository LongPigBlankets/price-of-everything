extends Control
# Expanded "Upgrade building" dialog — the upgrade counterpart to construction_missing_dialog.
# Built entirely in code, styled from the DS design system (DS.theme variations + DS.PALETTE /
# DS.SP / DS.FS tokens — no ad-hoc hex/px). Shows, for the next level: the material kit (framed
# icon grid with qty badges), what's on the tile vs the shortfall, the cur → new benefit/cost
# deltas, a bold cost-of-production-per-unit row, and the 3-turn build time. Sourcing mirrors
# construction: upgrade from tile stock, order the shortfall from market, or transfer it in.
#
# Self-contained: reads MatchState.preview_upgrade() and commits via MatchState.start_upgrade().
# A full-rect scrim makes it modal. One instance is reused across buildings via open().

const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")

## Each material is its OWN cream chip at 80 px with the count in bold underneath (owner,
## 2026-08-28), instead of four icons sharing one framed strip with a black corner badge.
const CELL_SIZE := 80.0
## Ordinary copy at 14; the figures stay a step larger, so a row still reads label-then-number
## at a glance. Panel-scoped overrides rather than a DS change -- the owner sized this one
## dialog by eye, and the variations are shared with every other panel.
const TEXT_PX := 14
const NUMBER_PX := 17

signal closed
signal committed(instance_id: String)

var _instance_id: String = ""
var _preview: Dictionary = {}

var _card: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	_build_shell()
	visible = false
	# Keep the dialog live while it's open as the upgrade is queued, advances, and completes.
	MatchState.building_upgrade_progress.connect(_on_upgrade_signal)
	MatchState.building_upgraded.connect(_on_upgrade_signal)
	MatchState.building_upgrade_cancelled.connect(_on_upgrade_signal)


# Open for a building instance, rebuilding the card from a fresh preview.
func open(instance_id: String) -> void:
	_instance_id = instance_id
	_preview = MatchState.preview_upgrade(instance_id)
	_rebuild()
	visible = true
	move_to_front()


func close() -> void:
	visible = false
	closed.emit()


# A turn advanced this building's upgrade — refresh the open card so the countdown/state is live.
func _on_upgrade_signal(instance_id: String, _arg = 0) -> void:
	if visible and instance_id == _instance_id:
		_preview = MatchState.preview_upgrade(_instance_id)
		_rebuild()


func _build_shell() -> void:
	theme = DS.theme
	# This Control lives directly under a CanvasLayer (no parent Control rect), so FULL_RECT anchors
	# resolve to nothing — size it to the viewport explicitly and track window resizes.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the dialog

	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	# A CenterContainer keeps the card centred as its content height changes (no manual re-centre).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Default PanelContainer = the DS base panel (navy + cream 2px outline, 14px rounded corners,
	# generous padding) — exactly the "rounded corners the DS theme specifies".
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(580, 0)
	center.add_child(_card)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", DS.SP.SM)
	_card.add_child(_content)


func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()


func _rebuild() -> void:
	_clear()
	if _preview.is_empty() or not bool(_preview.get("ok", false)):
		_content.add_child(_dlabel(str(_preview.get("reason", "Cannot upgrade.")), "Body"))
		_content.add_child(_button_row([{"text": "Close", "cb": close}]))
		return

	var bname := str(_preview.get("building_name", "Building"))

	if bool(_preview.get("at_max", false)):
		_content.add_child(_dlabel(bname.to_upper(), "Title"))
		_content.add_child(_dlabel("Already at the maximum level (L%d)." % int(_preview.get("from_level", 3)), "Caption"))
		_content.add_child(_button_row([{"text": "Close", "cb": close}]))
		return

	var from_level := int(_preview.get("from_level", 1))
	var target := int(_preview.get("target_level", from_level + 1))
	var duration := int(_preview.get("duration", 3))

	_content.add_child(_dlabel("Upgrade %s" % bname.to_upper(), "Title"))
	_content.add_child(_dlabel("Level %d  →  %d" % [from_level, target], "Caption"))

	# Already in progress: show the countdown and offer Cancel / Close only.
	if bool(_preview.get("already_upgrading", false)):
		var status := str(_preview.get("pending_status", ""))
		var left := int(_preview.get("pending_turns_left", 0))
		var msg := "Upgrade in progress — %d turn%s left." % [left, "" if left == 1 else "s"]
		if status == MatchState.UPGRADE_STATUS_AWAITING:
			msg = "Waiting on materials to arrive, then %d turn%s to upgrade." % [left, "" if left == 1 else "s"]
		_content.add_child(_sep())
		_content.add_child(_dlabel(msg, "Numeric", DS.PALETTE.OK))
		_content.add_child(_button_row([{"text": "Cancel upgrade", "cb": func(): _cancel()}, {"text": "Close", "cb": close}]))
		return

	# --- Materials ---
	# DS.ruled_section_head, not the "Section" variation: Section is Barlow Condensed, and
	# Construct V3 already ruled that a panel runs on ONE family with Bebas for its title
	# only (ds.gd's SectionRuled note). It draws its own rule, so the separator goes.
	_content.add_child(DS.ruled_section_head("MATERIALS"))
	var materials: Array = _preview.get("materials", [])
	if materials.is_empty():
		_content.add_child(_dlabel("No materials required.", "Body"))
	else:
		var grid := GridContainer.new()
		grid.columns = mini(4, maxi(1, materials.size()))
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_theme_constant_override("h_separation", DS.SP.MD)
		grid.add_theme_constant_override("v_separation", DS.SP.SM)
		for m in materials:
			grid.add_child(_make_material_column(m))
		_content.add_child(grid)
		var to_buy := float(_preview.get("market_cost", 0.0))
		if to_buy > 0.0:
			var price := _dlabel("Market Price of Materials:  £%s" % _money(to_buy), "Numeric")
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_content.add_child(price)

	# --- Benefits & costs (cur → new) ---
	_content.add_child(DS.ruled_section_head("PER TURN AT LEVEL %d" % target))
	_add_stat_rows(_preview.get("stats", {}))

	# --- Cost of production per unit (bold summary row) ---
	var uc: Dictionary = _preview.get("unit_cost", {})
	if uc.has("cur") and uc.has("new"):
		_content.add_child(_sep())
		var cc := float(uc.get("cur", 0.0))
		var cn := float(uc.get("new", 0.0))
		# Rising unit cost is bad (red); a cheaper unit is good (green).
		var col: Color = DS.PALETTE.DANGER if cn > cc else DS.PALETTE.OK
		_content.add_child(_delta_row("Cost of production per unit", cc, cn, col, 2, "£", true))

	# --- Blockers ---
	if bool(_preview.get("research_locked", false)):
		_content.add_child(UIHelpers.make_research_requirement_link(
			str(_preview.get("research_gate", "")), DS.PALETTE.DANGER))
	if not bool(_preview.get("fits", true)):
		_content.add_child(_dlabel(str(_preview.get("fits_reason",
			"Not enough room on the tile for the larger building.")), "Numeric", DS.PALETTE.DANGER))

	# --- Action buttons ---
	_content.add_child(_sep())
	_content.add_child(_dlabel(
		"Upgrading takes %d turns. The building continues to produce at its previous level until done."
			% duration, "Caption"))
	_content.add_child(_make_action_buttons())


## The action row. "Use materials on tile" is ALWAYS present (owner, 2026-08-28) rather than
## swapping in and out with the market button: a CTA that appears only when it would work
## tells the player nothing about why it is not there. It is enabled exactly when every good
## in the kit is on the tile AND unclaimed by another awaiting job -- see
## MatchState.reserved_materials_on_tile, which is why this reads `all_on_tile_free` and not
## the raw `all_on_tile`.
func _make_action_buttons() -> Control:
	var locked := bool(_preview.get("research_locked", false))
	var fits := bool(_preview.get("fits", true))
	var blocked := locked or not fits
	var on_tile := bool(_preview.get("all_on_tile", false))
	var free := bool(_preview.get("all_on_tile_free", on_tile))
	var specs: Array = []
	var tile_text := "Use materials on tile"
	if on_tile and not free:
		tile_text = "Materials on tile are already claimed"
	specs.append({
		"text": tile_text,
		"cb": func(): _commit("tile"),
		"disabled": blocked or not free, "primary": free and not blocked,
	})
	if not free:
		# Market order — only when every shortfall good actually has a port route here.
		var sourceable := bool(_preview.get("market_sourceable", true))
		specs.append({
			"text": "Order from market" if sourceable else "No market route for some materials",
			"cb": func(): _commit("market"),
			"disabled": blocked or not sourceable, "primary": sourceable,
		})
		var src := str(_preview.get("source_tile", ""))
		if src != "":
			specs.append({
				"text": "Use spare stockpile from %s" % Catalog.tile_label(src),
				"cb": func(): _commit("transfer"),
				"disabled": blocked,
			})
	specs.append({"text": "Cancel", "cb": close})
	return _button_row(specs)


func _cancel() -> void:
	# MatchState emits building_upgrade_cancelled, which the detail panel listens for to refresh.
	if MatchState.cancel_upgrade(_instance_id):
		_toast("Upgrade cancelled — materials returned to the tile.", "show_caution")
	close()


func _commit(mode: String) -> void:
	var result: Dictionary = MatchState.start_upgrade(_instance_id, mode)
	if bool(result.get("ok", false)):
		var status := str(result.get("status", ""))
		if status == MatchState.UPGRADE_STATUS_AWAITING:
			_toast("Upgrade queued — sourcing materials, then %d turns." % int(_preview.get("duration", 3)), "show_caution")
		else:
			_toast("Upgrade started — ready in %d turns." % int(_preview.get("duration", 3)), "show_caution")
		committed.emit(_instance_id)
		close()
		return
	var reason := str(result.get("reason", "Cannot upgrade."))
	if result.has("missing"):
		var parts: PackedStringArray = []
		for gid in (result.get("missing", {}) as Dictionary):
			parts.append("%d× %s" % [int(result["missing"][gid]), Catalog.get_display_name(str(gid))])
		reason += "  Need: " + ", ".join(parts)
	_toast(reason, "show_error")


# ---- stat rows --------------------------------------------------------------

func _add_stat_rows(stats: Dictionary) -> void:
	var cur: Dictionary = stats.get("cur", {})
	var new_s: Dictionary = stats.get("new", {})
	if cur.is_empty() or new_s.is_empty():
		return
	# Output + inputs (throughput) are whole units → green. Energy / labour / maintenance are
	# costs and may be fractional (1 decimal) → red. Tile size stays a whole number.
	var cur_out: Array = cur.get("outputs", [])
	var new_out: Array = new_s.get("outputs", [])
	for i in range(mini(cur_out.size(), new_out.size())):
		_content.add_child(_delta_row("Output: %s" % str(cur_out[i].get("name", "")),
			float(cur_out[i].get("qty", 0)), float(new_out[i].get("qty", 0)), DS.PALETTE.OK, 0, ""))
	var cur_in: Array = cur.get("inputs", [])
	var new_in: Array = new_s.get("inputs", [])
	for i in range(mini(cur_in.size(), new_in.size())):
		_content.add_child(_delta_row("Input: %s" % str(cur_in[i].get("name", "")),
			float(cur_in[i].get("qty", 0)), float(new_in[i].get("qty", 0)), DS.PALETTE.OK, 0, ""))
	if float(cur.get("energy", 0)) > 0.0 or float(new_s.get("energy", 0)) > 0.0:
		_content.add_child(_delta_row("Energy draw", float(cur.get("energy", 0)), float(new_s.get("energy", 0)), DS.PALETTE.DANGER, 1, ""))
	_content.add_child(_delta_row("Labour", float(cur.get("labour", 0.0)), float(new_s.get("labour", 0.0)), DS.PALETTE.DANGER, 1, "£"))
	_content.add_child(_delta_row("Maintenance", float(cur.get("maintenance", 0.0)), float(new_s.get("maintenance", 0.0)), DS.PALETTE.DANGER, 1, "£"))
	_content.add_child(_delta_row("Tile size", float(cur.get("size", 1.0)), float(new_s.get("size", 1.0)), DS.PALETTE.DANGER, 0, ""))


# A "Label   cur → new  (±N%)" row. `color` tints the value (and, when bold, the label too).
#
# The percentage carries its own sign and its own colour, so it needs neither the word "up"
# nor an arrow after it: "(+100% up ↑)" said one thing three times, on six rows at once.
func _delta_row(label_text: String, cur: float, new_v: float, color: Color, decimals: int, prefix: String, bold: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP.SM)
	# The label stays TEXT even on the bold summary row: green-on-navy for a heading is the
	# contrast rule's grey-on-navy in another hue, and the colour belongs to the number that
	# earned it (owner, 2026-08-28).
	var name := _dlabel(label_text, "Numeric" if bold else "Body", DS.PALETTE.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)

	var pct_txt := ""
	if cur > 0.0:
		var pct := int(round((new_v / cur - 1.0) * 100.0))
		if new_v > cur:
			pct_txt = "  (+%d%%)" % pct
		elif new_v < cur:
			pct_txt = "  (%d%%)" % pct
	elif new_v > 0.0:
		pct_txt = "  (new)"
	var value := _dlabel("%s%s → %s%s%s" % [
		prefix, _fmt_num(cur, decimals), prefix, _fmt_num(new_v, decimals), pct_txt], "Numeric", color)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF  # keep "cur → new (±%)" on one line
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


# ---- material cell (icon + need badge + have/need) --------------------------

## One material: its own cream rounded chip, with the count in bold underneath.
##
## The chip is `UIHelpers.make_plain_good_icon`, the same one the Resources table uses, so a
## good looks like itself wherever it appears. The count moved out from a black badge on the
## artwork's corner -- at 80 px that badge was covering the picture it labelled.
func _make_material_column(m: Dictionary) -> Control:
	var good_id := str(m.get("good_id", ""))
	var need := int(m.get("need", 0))
	var have := int(m.get("have", 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP.XS)
	col.custom_minimum_size = Vector2(CELL_SIZE, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var chip := UIHelpers.make_plain_good_icon(good_id,
		Catalog.get_internal_name(good_id), int(CELL_SIZE))
	chip.tooltip_text = Catalog.get_display_name(good_id)
	col.add_child(chip)

	var ok := have >= need
	var count := _dlabel("%d/%d" % [mini(have, need), need], "Numeric",
		DS.PALETTE.OK if ok else DS.PALETTE.WARN)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", NUMBER_PX)
	col.add_child(count)
	return col


func _dlabel(text: String, variation: String = "Body", color = null) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if color != null:
		l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Sizes are set HERE rather than in DS: the owner sized this one dialog by eye, and the
	# variations are shared with every other panel. Titles and section heads keep theirs.
	if variation == "Body" or variation == "Caption":
		l.add_theme_font_size_override("font_size", TEXT_PX)
	elif variation == "Numeric":
		l.add_theme_font_size_override("font_size", NUMBER_PX)
	return l


func _sep() -> HSeparator:
	return HSeparator.new()


# specs: Array of {text, cb: Callable, disabled?: bool, primary?: bool}
func _button_row(specs: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP.SM)
	for s in specs:
		var b := Button.new()
		b.text = str(s.get("text", ""))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = bool(s.get("disabled", false))
		b.theme_type_variation = "Primary" if bool(s.get("primary", false)) else "Build"
		var cb: Callable = s.get("cb")
		if cb != null:
			b.pressed.connect(cb)
		row.add_child(b)
	return row


func _fmt_num(v: float, decimals: int) -> String:
	if decimals <= 0:
		return str(int(round(v)))
	return String.num(v, decimals)


func _money(v: float) -> String:
	return str(int(round(v)))


func _toast(message: String, method_name: String) -> void:
	var toast := get_tree().root.find_child("ToastLayer", true, false)
	if toast != null and toast.has_method(method_name):
		toast.call(method_name, message)
	else:
		push_warning(message)
