extends Control
## Coach overlay — the one net-new UI primitive of the tutorial system. A full-screen
## Control mounted under the HUD's UILayer that dims everything except a spotlight rect
## (four dark quads drawn around a hole), and floats a DS-themed coach card with the
## step copy plus Next / Skip. Clicks inside the hole fall through to the widget beneath
## (via _has_point), so a spotlit panel stays fully interactive. Reusable for any future
## guided flow. Referenced via preload (no class_name) for headless.

signal advanced           # info-card "Next" pressed
signal skipped            # "Skip Tutorial" pressed
signal choice_made(goto)  # a branch choice button pressed (goto = target step id)

const DIM := Color(0, 0, 0, 0.6)
const GLOW := Color(0.98, 0.80, 0.42)  # warm gold spotlight glow

var _pulse := 0.0                      # drives the animated glow pulse
var _no_dim := false                   # true = no dim/block (card only), so the map stays visible + interactive
var _hole: Rect2 = Rect2()             # spotlight rect in screen space (empty = full dim)
var _target_node: Control = null       # live node whose rect we track each frame
var _card: PanelContainer = null
var _eyebrow: Label = null
var _title: Label = null
var _body: Label = null
var _next_btn: Button = null
var _choices_box: VBoxContainer = null
var _spot: Dictionary = {}              # the current step's spotlight dict (for re-finding)
var _reresolve_t := 0.0                 # throttle for re-finding the target as panels settle
var _scrolled_node: Control = null      # the node we've already scrolled into view
var _mode := ""                         # "" normal · "welcome" centred intro panel · "annotate" HUD primer
var _welcome_card: PanelContainer = null
var _welcome_title: Label = null
var _welcome_body: VBoxContainer = null
var _welcome_btn: Button = null
var _annot_items: Array = []            # [{ref, side, label}] — HUD-primer labels + their leader-line targets
var _hint_items: Array = []             # left-edge fixed hint Labels (no leader line)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks on the dimmed surround
	z_index = 200
	# A runtime overlay added under the HUD's CanvasLayer does NOT inherit the root-viewport
	# DS theme, so its cards/buttons would fall back to Godot defaults (translucent panel,
	# plain button). Assign DS.theme explicitly so the whole subtree resolves the DS look —
	# the CoachCard / Silver variations included.
	if typeof(DS) != TYPE_NIL and DS.theme != null:
		theme = DS.theme
	set_process(false)
	_build_card()


# Only "solid" (dimmed) area is hit — the spotlight hole passes clicks through to the
# HUD beneath. The card is a child Control and is hit-tested independently.
func _has_point(point: Vector2) -> bool:
	# no_dim + a hole (e.g. "explore the Encyclopedia"): don't dim, but still restrict clicks
	# to the spotlit element — the player sees the whole viewport yet can only click the target.
	if _no_dim and _hole.has_area():
		return not _hole.has_point(point + global_position)
	# no_dim + no hole (e.g. "look at the logistics map"): never block — free hover/pan.
	if _no_dim:
		return false
	# No spotlight hole → don't block the game underneath (the coach card still captures
	# its own Next/Skip/choice clicks). This prevents a soft-lock on an AUTO step whose
	# spotlight target failed to resolve (no hole + no Next = nothing the player can do).
	if not _hole.has_area():
		return false
	return not _hole.has_point(point + global_position)


func _draw() -> void:
	if _no_dim:
		return   # card-only step: leave the map fully visible
	var full := Rect2(Vector2.ZERO, size)
	if not _hole.has_area():
		draw_rect(full, DIM)
		if _mode == "annotate":
			_draw_annotation_lines()
		return
	var h := _hole
	# Four quads around the hole (top / bottom / left band / right band).
	draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)                                   # top
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)                          # bottom
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)                       # left
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)             # right
	# Pulsing golden glow: concentric stroked rings around the spotlight, fading out,
	# their intensity breathing via _pulse. Draws the eye to the highlighted element.
	var t := 0.5 + 0.5 * sin(_pulse * 3.2)
	for i in range(5):
		var grow := 2.0 + float(i) * 5.0
		var a := (0.45 - float(i) * 0.08) * (0.55 + 0.45 * t)
		if a > 0.0:
			draw_rect(h.grow(grow), Color(GLOW.r, GLOW.g, GLOW.b, a), false, 2.5)
	draw_rect(h.grow(1.0), Color(GLOW.r, GLOW.g, GLOW.b, 0.9), false, 2.0)   # crisp inner frame


func _process(dt: float) -> void:
	# HUD primer: keep the labels pinned to their (possibly-animating) targets and redraw the
	# leader lines each frame. No spotlight tracking below.
	if _mode == "annotate":
		_position_annotations()
		_pulse += dt
		queue_redraw()
		return
	# Panels build/rebuild over several frames after they open (the stock chart pushes the
	# Sell toggle down; an infra grid sizes its dials late). The node we grabbed on entry can
	# end up freed-and-replaced or at a stale position, leaving the hole in the wrong place.
	# Re-find the CURRENT node by name/path — on a throttle, and immediately if ours is gone.
	_reresolve_t += dt
	if _needs_refind():
		var stale := _target_node == null or not is_instance_valid(_target_node)
		if stale or _reresolve_t >= 0.2:
			_reresolve_t = 0.0
			_refind()
	if _target_node != null and is_instance_valid(_target_node):
		var r := _node_rect(_target_node)
		if r != _hole:
			_hole = r
			_reposition_card()
	if _hole.has_area() or _no_dim:
		_pulse += dt
		queue_redraw()


# Padded hole around a spotlit Control: a little breathing room, biased UPWARD so a
# stacked cell (e.g. InfraCell_cables: a 78px dial "+" above two small labels) isn't
# clipped at the top.
func _node_rect(c: Control) -> Rect2:
	return c.get_global_rect().grow_individual(8.0, 14.0, 8.0, 6.0)


# Walk the target's ancestors for a ScrollContainer and scroll the target into view,
# so a below-the-fold spotlight (CostToProduceCard, an infra cell) is visible before we
# lock the hole. Deferred a frame: right after a panel rebuild the child rects are stale.
func _scroll_target_into_view(target: Control) -> void:
	if target == _scrolled_node:
		return   # already scrolled this node into view; don't fight the player
	_scrolled_node = target
	var scroll := _find_scroll_ancestor(target)
	if scroll == null:
		return
	scroll.ensure_control_visible(target)
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(target):
		return
	scroll.ensure_control_visible(target)
	if _target_node == target:
		_hole = _node_rect(target)
		_reposition_card()
		queue_redraw()


func _find_scroll_ancestor(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


# Does the current spotlight target a named/pathed node we should keep re-finding?
func _needs_refind() -> bool:
	var k := str(_spot.get("kind", ""))
	return k == "node_name" or k == "node_path"


# Re-find the CURRENT node for the active spotlight (panels rebuild → the node we grabbed
# may be freed/replaced or repositioned). Switches to the live node and re-scrolls it in.
func _refind() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var kind := str(_spot.get("kind", ""))
	var ref := str(_spot.get("ref", ""))
	var node: Control = null
	if kind == "node_name":
		var m := scene.find_child(ref, true, false)
		if m is Control and (m as Control).is_visible_in_tree():
			node = m as Control
	elif kind == "node_path":
		var n := scene.get_node_or_null(NodePath(ref))
		if n is Control and (n as Control).is_visible_in_tree():
			node = n as Control
	if node == null:
		# Target gone (e.g. the encyclopedia was closed): drop the hole.
		_target_node = null
		if _hole.has_area():
			_hole = Rect2()
			queue_redraw()
		return
	if node != _target_node:
		_target_node = node
		_hole = _node_rect(node)
		_scroll_target_into_view(node)
		_reposition_card()


## True when the current spotlight is still resolvable/visible — used by the engine to
## know a locked panel is still open (else it re-opens it).
func spotlight_ok() -> bool:
	if _target_node != null:
		return is_instance_valid(_target_node) and (_target_node as Control).visible
	return _hole.has_area()


## Show a step: sets card copy, resolves the spotlight target, positions the card.
func show_step(step: Dictionary, index: int, total: int) -> void:
	visible = true
	_mode = str(step.get("mode", ""))
	_no_dim = bool(step.get("no_dim", false))
	_clear_annotations()

	# "welcome": a centred modal intro panel — no corner card, no spotlight.
	if _mode == "welcome":
		_card.visible = false
		_show_welcome(step)
		_spot = {}
		_target_node = null
		_hole = Rect2()
		set_process(false)
		queue_redraw()
		return

	_welcome_card.visible = false
	_card.visible = true
	_eyebrow.text = "%s  ·  Step %d/%d" % [str(step.get("chapter", "")), index + 1, total]
	_title.text = str(step.get("title", ""))
	_body.text = str(step.get("body", ""))
	# Choice step: render one Primary button per option (goto target step id).
	for c in _choices_box.get_children():
		c.queue_free()
	var choices: Array = step.get("choices", [])
	for ch in choices:
		if not (ch is Dictionary):
			continue
		var b := Button.new()
		b.text = str((ch as Dictionary).get("label", "Choose"))
		b.theme_type_variation = &"Primary"
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var goto := str((ch as Dictionary).get("goto", ""))
		b.pressed.connect(func() -> void: choice_made.emit(goto))
		_choices_box.add_child(b)
	# Next is for plain info steps only (hidden when this is a choice step).
	_next_btn.visible = str(step.get("advance", "auto")) == "next" and choices.is_empty()

	# "annotate": a HUD primer — full dim, the corner card centred, plus labels + leader
	# lines pointing at named HUD nodes, and fixed left-edge hint text.
	if _mode == "annotate":
		_spot = {}
		_target_node = null
		_hole = Rect2()
		_build_annotations(step)
		set_process(true)          # track HUD rects (buttons animate) + redraw the leader lines
		_card.reset_size()
		_center_card_for_annotate()
		_defer_reposition()
		queue_redraw()
		return

	_resolve_spotlight(step.get("spotlight", {}))
	# Drop any oversized size left by a previous (longer) step so the card can shrink,
	# place it provisionally now (no flash), then re-measure next frame once the body
	# Label has re-wrapped — get_combined_minimum_size() is stale on this same frame.
	_card.reset_size()
	_reposition_card()
	_defer_reposition()
	queue_redraw()
	# Cue the player's eye to a freshly-highlighted element with the hint sound.
	if _hole.has_area() and typeof(Audio) != TYPE_NIL and Audio.has_method("hint"):
		Audio.hint()


# Re-measure and reposition after the next layout pass, when the body Label has
# re-wrapped to the new text and get_combined_minimum_size() is finally accurate.
func _defer_reposition() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(self) or _card == null:
		return
	_card.reset_size()
	if _mode == "annotate":
		_center_card_for_annotate()
	else:
		_reposition_card()
	queue_redraw()


func _resolve_spotlight(spot: Dictionary) -> void:
	_spot = spot
	_scrolled_node = null
	_reresolve_t = 0.0
	_target_node = null
	_hole = Rect2()
	match str(spot.get("kind", "none")):
		"node_path":
			var scene := get_tree().current_scene
			if scene != null:
				var n := scene.get_node_or_null(NodePath(str(spot.get("ref", ""))))
				if n is Control and (n as Control).visible:
					_target_node = n           # track the rect (panels rebuild/move)
					_hole = _node_rect(n as Control)
					_scroll_target_into_view(n as Control)
		"node_name":
			# Recursive find by node name — for deeply-nested cards that rebuild each
			# refresh (cost/diagnostics cards), which have no stable fixed path.
			var root := get_tree().current_scene
			if root != null:
				var m := root.find_child(str(spot.get("ref", "")), true, false)
				if m is Control and (m as Control).visible:
					_target_node = m
					_hole = _node_rect(m as Control)
					_scroll_target_into_view(m as Control)
		"tile":
			_hole = _tile_screen_rect(str(spot.get("ref", "")))
		_:
			pass   # "none": full dim, centred card
	# Run _process (glow pulse + node tracking) only while a spotlight exists.
	set_process(_hole.has_area() or _target_node != null)


# Screen-space rect of a map tile, for map spotlights.
func _tile_screen_rect(tile_id: String) -> Rect2:
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null or not hex_map.has_method("id_to_coord"):
		return Rect2()
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Rect2()
	var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
	var world: Vector2 = hex_map.to_global(hex_map.map_to_local(cell))
	var xform := get_viewport().get_canvas_transform()
	var centre := xform * world
	var half := Vector2(70, 60)   # generous tile box; refined per zoom later
	if hex_map.tile_set != null:
		var ts: Vector2 = Vector2(hex_map.tile_set.tile_size) * xform.get_scale()
		half = ts * 0.7
	return Rect2(centre - half, half * 2.0)


# ── Card ─────────────────────────────────────────────────────────────────────────

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme_type_variation = &"CoachCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size = Vector2(460, 0)
	add_child(_card)

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, _sp("LG", 18))
	_card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _sp("SM", 8))
	margin.add_child(col)

	_eyebrow = Label.new()
	_eyebrow.theme_type_variation = &"Caption"
	col.add_child(_eyebrow)

	_title = Label.new()
	_title.theme_type_variation = &"Section"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)

	_body = Label.new()
	_body.theme_type_variation = &"Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(430, 0)
	col.add_child(_body)

	# Branch-choice buttons (one per option), shown only on a choice step.
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", _sp("XS", 4))
	col.add_child(_choices_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _sp("SM", 8))
	col.add_child(buttons)

	# Tertiary "skip" link, bottom-left, underlined and muted.
	var skip := LinkButton.new()
	skip.text = "Skip tutorial"
	skip.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_color_override("font_color", Color(0.995, 0.930, 0.763, 0.72))
	skip.add_theme_color_override("font_hover_color", Color(0.995, 0.930, 0.763, 1.0))
	skip.pressed.connect(func() -> void: skipped.emit())
	buttons.add_child(skip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	_next_btn = Button.new()
	_next_btn.text = "Next"
	_next_btn.theme_type_variation = &"Silver"
	_next_btn.pressed.connect(func() -> void: advanced.emit())
	buttons.add_child(_next_btn)

	_build_welcome_panel()


# A larger, screen-centred modal panel for the opening "welcome" step: a title, several
# body paragraphs, a Skip and a Begin button. Reuses the same `advanced`/`skipped` wiring
# as the corner card, so the engine advances with no engine-side changes.
func _build_welcome_panel() -> void:
	_welcome_card = PanelContainer.new()
	_welcome_card.theme_type_variation = &"CoachCard"
	_welcome_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_welcome_card.custom_minimum_size = Vector2(620, 0)
	_welcome_card.visible = false
	add_child(_welcome_card)

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, _sp("XL", 26))
	_welcome_card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _sp("MD", 12))
	margin.add_child(col)

	_welcome_title = Label.new()
	_welcome_title.theme_type_variation = &"Title"
	_welcome_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_welcome_title)

	_welcome_body = VBoxContainer.new()
	_welcome_body.add_theme_constant_override("separation", _sp("SM", 8))
	col.add_child(_welcome_body)

	var wbtns := HBoxContainer.new()
	wbtns.add_theme_constant_override("separation", _sp("SM", 8))
	col.add_child(wbtns)

	var wskip := LinkButton.new()
	wskip.text = "Skip tutorial"
	wskip.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	wskip.focus_mode = Control.FOCUS_NONE
	wskip.add_theme_color_override("font_color", Color(0.995, 0.930, 0.763, 0.72))
	wskip.add_theme_color_override("font_hover_color", Color(0.995, 0.930, 0.763, 1.0))
	wskip.pressed.connect(func() -> void: skipped.emit())
	wbtns.add_child(wskip)

	var wspacer := Control.new()
	wspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wbtns.add_child(wspacer)

	_welcome_btn = Button.new()
	_welcome_btn.text = "Begin"
	_welcome_btn.theme_type_variation = &"Silver"
	_welcome_btn.custom_minimum_size = Vector2(0, 44)
	_welcome_btn.pressed.connect(func() -> void: advanced.emit())
	wbtns.add_child(_welcome_btn)


# Park the card in the first screen corner that clears the spotlight, hugging its
# content height (never force-grown), and always fully on-screen.
func _reposition_card() -> void:
	if _card == null:
		return
	var pad := 40.0
	# True content size: keep the 460 min width; height is the wrapped content height,
	# clamped so a very long body can never exceed the screen.
	var card_size := _card.get_combined_minimum_size()
	card_size.x = maxf(card_size.x, 460.0)
	card_size.y = minf(card_size.y, maxf(size.y - 2.0 * pad, 0.0))

	var left_x := pad
	var right_x := size.x - card_size.x - pad
	var top_y := pad
	var bottom_y := size.y - card_size.y - pad
	var candidates := [
		Vector2(left_x, bottom_y), Vector2(right_x, bottom_y),
		Vector2(left_x, top_y), Vector2(right_x, top_y),
	]
	var pos: Vector2 = candidates[0]
	if _hole.has_area():
		var chosen := false
		for c in candidates:
			if not Rect2(c, card_size).intersects(_hole):
				pos = c
				chosen = true
				break
		if not chosen:
			# All corners overlap a huge spotlight: sit fully above or below the hole.
			pos = candidates[candidates.size() - 1]
			var above := _hole.position.y - card_size.y - pad
			pos.y = above if above >= pad else _hole.end.y + pad
	# Clamp fully on-screen so the bottom/edges are never cut off.
	pos.x = clampf(pos.x, pad, maxf(size.x - card_size.x - pad, pad))
	pos.y = clampf(pos.y, pad, maxf(size.y - card_size.y - pad, pad))

	_card.position = pos
	# Width via custom_minimum_size; let the container hug content height.
	_card.custom_minimum_size = Vector2(card_size.x, 0.0)
	_card.size = card_size


# ── Welcome + HUD-primer modes ─────────────────────────────────────────────────────

func _show_welcome(step: Dictionary) -> void:
	_welcome_card.visible = true
	_welcome_title.text = str(step.get("title", ""))
	for c in _welcome_body.get_children():
		c.queue_free()
	var paras: Array = step.get("paragraphs", [])
	if paras.is_empty():
		paras = [str(step.get("body", ""))]
	for p in paras:
		var pl := Label.new()
		pl.theme_type_variation = &"Body"
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(560, 0)
		pl.text = str(p)
		_welcome_body.add_child(pl)
	_welcome_btn.text = str(step.get("cta", "Begin"))
	_center_welcome()
	_defer_center_welcome()


func _center_welcome() -> void:
	if _welcome_card == null:
		return
	var s := _welcome_card.get_combined_minimum_size()
	s.x = maxf(s.x, 620.0)
	s.y = minf(s.y, maxf(size.y - 60.0, 0.0))
	_welcome_card.custom_minimum_size = Vector2(s.x, 0.0)
	_welcome_card.size = s
	_welcome_card.position = (size - s) * 0.5


func _defer_center_welcome() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(self) or _welcome_card == null or not _welcome_card.visible:
		return
	_welcome_card.reset_size()
	_center_welcome()


# Park the annotate card in the upper-middle, clear of the top-bar and bottom-bar labels.
func _center_card_for_annotate() -> void:
	if _card == null:
		return
	var s := _card.get_combined_minimum_size()
	s.x = maxf(s.x, 460.0)
	_card.custom_minimum_size = Vector2(s.x, 0.0)
	_card.size = s
	_card.position = Vector2((size.x - s.x) * 0.5, clampf(size.y * 0.32 - s.y * 0.5, 40.0, maxf(size.y - s.y - 40.0, 40.0)))


# Build the HUD-primer child Labels: one per target (pinned near its HUD node with a leader
# line) plus the fixed left-edge hint Labels (no line). Freed on the next show_step.
func _build_annotations(step: Dictionary) -> void:
	for t in step.get("targets", []):
		if not (t is Dictionary):
			continue
		var lbl := Label.new()
		lbl.theme_type_variation = &"Caption"
		lbl.text = str((t as Dictionary).get("label", ""))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", _col("ACCENT", GLOW))
		add_child(lbl)
		_annot_items.append({
			"ref": str((t as Dictionary).get("ref", "")),
			"side": str((t as Dictionary).get("side", "above")),
			"label": lbl, "trect": Rect2(),
		})
	for h in step.get("hints", []):
		var hl := Label.new()
		hl.theme_type_variation = &"Body"
		hl.text = str(h)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size = Vector2(250, 0)
		hl.add_theme_color_override("font_color", _col("ACCENT", GLOW))
		add_child(hl)
		_hint_items.append(hl)
	_position_annotations()


func _position_annotations() -> void:
	var scene := get_tree().current_scene
	for it in _annot_items:
		var lbl: Label = it["label"]
		var node: Node = scene.find_child(str(it["ref"]), true, false) if scene != null else null
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			lbl.visible = false
			it["trect"] = Rect2()
			continue
		lbl.visible = true
		var r := (node as Control).get_global_rect()
		var ls := lbl.get_combined_minimum_size()
		var gap := 12.0
		var pos := Vector2.ZERO
		match str(it["side"]):
			"below":
				pos = Vector2(r.get_center().x - ls.x * 0.5, r.end.y + gap)
			"left":
				pos = Vector2(r.position.x - gap - ls.x, r.get_center().y - ls.y * 0.5)
			"right":
				pos = Vector2(r.end.x + gap, r.get_center().y - ls.y * 0.5)
			_:  # "above"
				pos = Vector2(r.get_center().x - ls.x * 0.5, r.position.y - gap - ls.y)
		pos.x = clampf(pos.x, 4.0, maxf(size.x - ls.x - 4.0, 4.0))
		pos.y = clampf(pos.y, 4.0, maxf(size.y - ls.y - 4.0, 4.0))
		lbl.position = pos - global_position
		lbl.size = ls
		it["trect"] = Rect2(r.position - global_position, r.size)
	var hy := size.y * 0.40
	for h in _hint_items:
		var hl := h as Label
		if hl == null:
			continue
		var hs := hl.get_combined_minimum_size()
		hl.position = Vector2(24.0, hy) - global_position
		hl.size = hs
		hy += hs.y + 40.0


func _draw_annotation_lines() -> void:
	var lc := _col("ACCENT", GLOW)
	lc.a = 0.85
	for it in _annot_items:
		var lbl: Label = it["label"]
		if lbl == null or not is_instance_valid(lbl) or not lbl.visible:
			continue
		var tr: Rect2 = it.get("trect", Rect2())
		if not tr.has_area():
			continue
		var lr := Rect2(lbl.position, lbl.size)
		var from := Vector2.ZERO
		var to := Vector2.ZERO
		match str(it["side"]):
			"below":
				from = Vector2(lr.get_center().x, lr.position.y)
				to = Vector2(tr.get_center().x, tr.end.y)
			"left":
				from = Vector2(lr.end.x, lr.get_center().y)
				to = Vector2(tr.position.x, tr.get_center().y)
			"right":
				from = Vector2(lr.position.x, lr.get_center().y)
				to = Vector2(tr.end.x, tr.get_center().y)
			_:  # "above"
				from = Vector2(lr.get_center().x, lr.end.y)
				to = Vector2(tr.get_center().x, tr.position.y)
		draw_line(from, to, lc, 2.0, true)
		draw_circle(to, 3.0, lc)


func _clear_annotations() -> void:
	for it in _annot_items:
		var lbl = it.get("label")
		if lbl != null and is_instance_valid(lbl):
			lbl.queue_free()
	_annot_items.clear()
	for hl in _hint_items:
		if hl != null and is_instance_valid(hl):
			hl.queue_free()
	_hint_items.clear()


# ── DS token helpers (defensive: DS builds its palette at runtime) ─────────────────

func _col(key: String, fallback: Color) -> Color:
	if typeof(DS) != TYPE_NIL and "PALETTE" in DS and DS.PALETTE.has(key):
		return DS.PALETTE[key]
	return fallback

func _sp(key: String, fallback: int) -> int:
	if typeof(DS) != TYPE_NIL and "SP" in DS and DS.SP.has(key):
		return int(DS.SP[key])
	return fallback
