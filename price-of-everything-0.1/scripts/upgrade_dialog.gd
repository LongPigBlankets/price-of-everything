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
const GOODS_FRAME := preload("res://assets/ui/goods_frame.tres")  # skinny pipe frame (nine-patch)

const BADGE_DIAMETER := 22
const BADGE_TEXT_SIZE := 13
const CELL_SIZE := 72.0

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
	_content.add_child(_dlabel("Level %d  →  %d   ·   takes %d turn%s to upgrade" % [
		from_level, target, duration, "" if duration == 1 else "s"], "Caption"))

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
	_content.add_child(_sep())
	_content.add_child(_dlabel("MATERIALS", "Section"))
	var materials: Array = _preview.get("materials", [])
	if materials.is_empty():
		_content.add_child(_dlabel("No materials required.", "Body"))
	else:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", GOODS_FRAME)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var grid := GridContainer.new()
		grid.columns = mini(4, maxi(1, materials.size()))
		grid.add_theme_constant_override("h_separation", DS.SP.MD)
		grid.add_theme_constant_override("v_separation", DS.SP.SM)
		frame.add_child(grid)
		for m in materials:
			grid.add_child(_make_material_column(m))
		_content.add_child(frame)

	if not bool(_preview.get("all_on_tile", false)):
		_content.add_child(_dlabel(
			"Some materials aren't on this tile — order them from market or transfer them in to begin.",
			"Caption"))

	# --- Benefits & costs (cur → new) ---
	_content.add_child(_sep())
	_content.add_child(_dlabel("PER TURN AT LEVEL %d" % target, "Section"))
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
		_content.add_child(_dlabel("Requires research: %s" % str(_preview.get("research_gate", "")), "Numeric", DS.PALETTE.DANGER))
	if not bool(_preview.get("fits", true)):
		_content.add_child(_dlabel("Not enough room on the tile for the larger building.", "Numeric", DS.PALETTE.DANGER))

	# --- Action buttons ---
	_content.add_child(_sep())
	_content.add_child(_make_action_buttons())


func _make_action_buttons() -> Control:
	var locked := bool(_preview.get("research_locked", false))
	var fits := bool(_preview.get("fits", true))
	var blocked := locked or not fits
	var specs: Array = []
	if bool(_preview.get("all_on_tile", false)):
		var dur := int(_preview.get("duration", 3))
		specs.append({
			"text": "Upgrade (%d turns)" % dur,
			"cb": func(): _commit("tile"),
			"disabled": blocked, "primary": true,
		})
	else:
		# Market order — only when every shortfall good actually has a port route here.
		var sourceable := bool(_preview.get("market_sourceable", true))
		var cost := float(_preview.get("market_cost", 0.0))
		specs.append({
			"text": ("Order from market  (£%s)" % _money(cost)) if sourceable else "No market route for some materials",
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


# A "Label   cur → new  (±N% ↑)" row. `color` tints the value (and, when bold, the label too).
func _delta_row(label_text: String, cur: float, new_v: float, color: Color, decimals: int, prefix: String, bold: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP.SM)
	var name := _dlabel(label_text, "Numeric" if bold else "Body", color if bold else null)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)

	var pct_txt := ""
	if cur > 0.0:
		var pct := int(round((new_v / cur - 1.0) * 100.0))
		if new_v > cur:
			pct_txt = "  (+%d%% up ↑)" % pct
		elif new_v < cur:
			pct_txt = "  (%d%% down ↓)" % pct
	elif new_v > 0.0:
		pct_txt = "  (new)"
	var value := _dlabel("%s%s → %s%s%s" % [
		prefix, _fmt_num(cur, decimals), prefix, _fmt_num(new_v, decimals), pct_txt], "Numeric", color)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF  # keep "cur → new (±%)" on one line
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


# ---- material cell (icon + need badge + have/need) --------------------------

func _make_material_column(m: Dictionary) -> Control:
	var good_id := str(m.get("good_id", ""))
	var need := int(m.get("need", 0))
	var have := int(m.get("have", 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP.XS)
	col.custom_minimum_size = Vector2(CELL_SIZE, 0)

	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	var icon := GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(tr)
	else:
		var ph := _dlabel(Catalog.get_display_name(good_id), "Caption")
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(ph)
	slot.add_child(_make_qty_badge(need))
	col.add_child(slot)

	var ok := have >= need
	var have_lbl := _dlabel("%d/%d" % [mini(have, need), need], "Caption", DS.PALETTE.OK if ok else DS.PALETTE.DANGER)
	have_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(have_lbl)
	return col


func _make_qty_badge(qty: int) -> Control:
	var qty_text := str(qty)
	var h: int = BADGE_DIAMETER
	var w: int = h if qty_text.length() <= 1 else maxi(h, qty_text.length() * 9 + 12)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -w + 6
	badge.offset_top = -h + 6
	badge.offset_right = 6
	badge.offset_bottom = 6
	var style := StyleBoxFlat.new()
	style.bg_color = DS.PALETTE.BG_PANEL
	style.border_color = DS.PALETTE.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(h / 2.0))
	badge.add_theme_stylebox_override("panel", style)
	var ls := LabelSettings.new()
	ls.font_color = DS.PALETTE.ACCENT
	ls.font_size = BADGE_TEXT_SIZE
	var label := Label.new()
	label.text = qty_text
	label.label_settings = ls
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


# ---- small builders ---------------------------------------------------------

# A DS-styled Label: `variation` selects the theme type variation (Title / Section / Body /
# Caption / Numeric); `color` optionally overrides the font colour with a DS.PALETTE token.
func _dlabel(text: String, variation: String = "Body", color = null) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if color != null:
		l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
