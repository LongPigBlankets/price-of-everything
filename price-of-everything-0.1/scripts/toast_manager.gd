extends Control

# ToastManager: shows transient notifications.
# - Top stack: "building placed" success toasts (one per building_added).
# - Bottom stack: red warning when cash crosses below 0.
# Up to MAX_TOASTS per stack; oldest is dropped immediately when exceeded.
# Each toast auto-dismisses (with fade) after TOAST_DURATION seconds.

# Cap per stack. Raised from 4 (owner, 23 Aug): the oldest toast is dropped the INSTANT
# the cap is exceeded, whatever is left of its timer, so on a busy turn — several
# buildings finishing, a loan, a shipment landing — a toast could be gone in a fraction
# of a second. That is a large part of what "the toasts are too short lived" meant; the
# stack simply rises higher now.
const MAX_TOASTS := 6
const TOAST_DURATION := 5.0   # owner, 23 Aug
const FADE_DURATION := 0.35
const TOAST_WIDTH := 380.0
# Bottom-left stack for success toasts, sitting under the Construct panel.
# Right edge is anchored to the left side; toasts grow upward.
const SUCCESS_LEFT_MARGIN := 20.0
const SUCCESS_BOTTOM_OFFSET := -140.0
# Bottom-centre stack for warnings.
const WARNING_BOTTOM_OFFSET := -140.0
# Insufficient-money errors (can't afford a build OR a building purchase) share the bottom-left
# success stack so they sit where the other left-side toasts are, stacking instead of overlapping.

const SUCCESS_BG := Color(0.05, 0.18, 0.32, 0.94)
const SUCCESS_BORDER := Color(0.4, 0.85, 0.4, 0.9)
const SUCCESS_TEXT := Color(0.92, 0.97, 1.0)

const WARNING_BG := Color(0.35, 0.05, 0.05, 0.95)
const WARNING_BORDER := Color(1.0, 0.35, 0.35, 0.95)
const WARNING_TEXT := Color(1.0, 0.92, 0.92)
const CAUTION_BG := Color(0.22, 0.16, 0.03, 0.95)
const CAUTION_BORDER := Color(1.0, 0.78, 0.18, 0.95)
const CAUTION_TEXT := Color(1.0, 0.96, 0.84)
const TOAST_SUCCESS := "success"
const TOAST_WARNING := "warning"
const TOAST_CAUTION := "caution"
const TOAST_ERROR := "error"

var _success_stack: VBoxContainer
var _warning_stack: VBoxContainer
var _prev_money: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_stacks()
	_prev_money = MatchState.money
	MatchState.building_added.connect(_on_building_added)
	Construction.construction_started.connect(_on_construction_started)
	Construction.materials_ordered.connect(_on_materials_ordered)
	Construction.construction_cancelled.connect(_on_construction_cancelled)
	MatchState.money_changed.connect(_on_money_changed)
	MatchState.stockpile_market_sale_completed.connect(_on_stockpile_market_sale_completed)
	MatchState.toast_requested.connect(_on_toast_requested)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)

func _on_build_rejected_no_funds(message: String) -> void:
	_push_toast(_success_stack, message, TOAST_WARNING)  # red styling, bottom-left with the other toasts

func _on_toast_requested(message: String, toast_type: String) -> void:
	if toast_type == TOAST_ERROR:
		_push_toast(_success_stack, message, TOAST_WARNING)  # red styling, bottom-left
		return
	var stack := _warning_stack if toast_type == TOAST_WARNING else _success_stack
	_push_toast(stack, message, toast_type)

func _build_stacks() -> void:
	_success_stack = VBoxContainer.new()
	_success_stack.name = "SuccessStack"
	_success_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_success_stack.add_theme_constant_override("separation", 6)
	_success_stack.alignment = BoxContainer.ALIGNMENT_END
	_success_stack.anchor_left = 0.0
	_success_stack.anchor_right = 0.0
	_success_stack.anchor_top = 1.0
	_success_stack.anchor_bottom = 1.0
	_success_stack.offset_left = SUCCESS_LEFT_MARGIN
	_success_stack.offset_right = SUCCESS_LEFT_MARGIN + TOAST_WIDTH
	_success_stack.offset_top = SUCCESS_BOTTOM_OFFSET
	_success_stack.offset_bottom = SUCCESS_BOTTOM_OFFSET
	_success_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_success_stack)

	_warning_stack = VBoxContainer.new()
	_warning_stack.name = "WarningStack"
	_warning_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_stack.add_theme_constant_override("separation", 6)
	_warning_stack.alignment = BoxContainer.ALIGNMENT_END
	_warning_stack.anchor_left = 0.5
	_warning_stack.anchor_right = 0.5
	_warning_stack.anchor_top = 1.0
	_warning_stack.anchor_bottom = 1.0
	_warning_stack.offset_left = -TOAST_WIDTH / 2.0
	_warning_stack.offset_right = TOAST_WIDTH / 2.0
	_warning_stack.offset_top = WARNING_BOTTOM_OFFSET
	_warning_stack.offset_bottom = WARNING_BOTTOM_OFFSET
	_warning_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_warning_stack)

func _on_building_added(instance: Dictionary) -> void:
	# building_added now fires at completion (promotion), so this is the "built" toast.
	var msg: String = _format_building_message(instance)
	_push_toast(_success_stack, msg, TOAST_SUCCESS)

func _on_materials_ordered(instance_id: String, tile_id: String) -> void:
	var parts: Array = []
	var max_turns: int = 0
	for s in MatchState.get_inbound_transport_shipments(tile_id):
		if str(s.get("construction_instance_id", "")) != instance_id:
			continue
		parts.append("%d %s" % [int(s.get("qty", 0)), Catalog.get_display_name(str(s.get("good_id", "")))])
		max_turns = maxi(max_turns, int(s.get("turns_remaining", 0)))
	if parts.is_empty():
		return
	var msg: String = "Ordered %s — arriving in %d turn%s" % [", ".join(parts), max_turns, "" if max_turns == 1 else "s"]
	_push_toast(_success_stack, msg, TOAST_SUCCESS)

func _on_construction_cancelled(_instance_id: String, tile_id: String) -> void:
	_push_toast(_success_stack, "Construction cancelled on tile %s — build cost refunded" % Catalog.tile_label(tile_id), TOAST_CAUTION)

func _on_construction_started(instance_id: String, tile_id: String) -> void:
	var project: Dictionary = Construction.construction_projects.get(instance_id, {})
	if project.is_empty():
		return  # 0-duration build completed instantly; the "built" toast covers it.
	var building: Dictionary = Catalog.get_building(str(project.get("building_id", "")))
	var b_name: String = str(building.get("display_name", project.get("building_id", "")))
	var recipe: Dictionary = Catalog.get_recipe(str(project.get("recipe_id", "")))
	var recipe_name: String = str(recipe.get("display_name", ""))
	var who: String = b_name if recipe_name == "" else "%s — %s" % [b_name, recipe_name]
	var duration: int = int(project.get("construction_duration", 0))
	var msg: String = "Construction started for %s on tile %s. Will be complete in %d turn%s" % [
		who, Catalog.tile_label(tile_id), duration, "" if duration == 1 else "s"
	]
	_push_toast(_success_stack, msg, TOAST_SUCCESS)

func _on_money_changed(new_amount: float) -> void:
	if _prev_money >= 0.0 and new_amount < 0.0:
		_push_toast(_warning_stack, "!  Cash is in the red: £%.2f" % new_amount, TOAST_WARNING)
	_prev_money = new_amount

func show_error(message: String) -> void:
	_push_toast(_success_stack, message, TOAST_WARNING)

func show_caution(message: String) -> void:
	_push_toast(_success_stack, message, TOAST_CAUTION)

func _format_building_message(instance: Dictionary) -> String:
	var building_id: String = instance.get("building_id", "")
	var recipe_id: String = instance.get("recipe_id", "")
	var building: Dictionary = Catalog.get_building(building_id)
	var b_name: String = building.get("display_name", building_id)
	var cost: float = building.get("base_price", 0.0)

	var line: String = "Built %s" % b_name

	var recipe: Dictionary = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	if not recipe.is_empty():
		var outputs: Array = recipe.get("outputs", [])
		var parts: Array = []
		for o in outputs:
			var iname: String = String(o.get("internal_name", ""))
			var qty: int = int(o.get("qty", 0))
			if iname == "" or qty <= 0:
				continue
			var good: Dictionary = Catalog.get_good_by_internal_name(iname)
			var disp: String = good.get("display_name", iname)
			parts.append("%d %s" % [qty, disp])
		if not parts.is_empty():
			line += " — produces %s/turn" % ", ".join(parts)

	var meta: Array = []
	if cost > 0:
		meta.append("£%.0f" % cost)
	if not meta.is_empty():
		line += "  ·  " + "  ·  ".join(meta)
	return line

func _on_stockpile_market_sale_completed(sale_record: Dictionary) -> void:
	var msg := _format_stockpile_sale_message(sale_record)
	if msg != "":
		_push_toast(_success_stack, msg, TOAST_SUCCESS)

func _format_stockpile_sale_message(sale_record: Dictionary) -> String:
	var items: Array = sale_record.get("items", [])
	if items.is_empty():
		return ""
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("qty", 0)) == int(b.get("qty", 0)):
			return str(a.get("good_id", "")) < str(b.get("good_id", ""))
		return int(a.get("qty", 0)) > int(b.get("qty", 0))
	)
	var first: Dictionary = items[0]
	var first_qty: int = int(first.get("qty", 0))
	var first_good_id: String = first.get("good_id", "")
	var first_revenue: float = float(first.get("revenue", 0.0))
	var message := "%d %s sold to market for £%.2f" % [
		first_qty,
		Catalog.get_display_name(first_good_id),
		first_revenue,
	]
	if items.size() > 1:
		var other_qty := 0
		var other_revenue := 0.0
		for i in range(1, items.size()):
			other_qty += int(items[i].get("qty", 0))
			other_revenue += float(items[i].get("revenue", 0.0))
		var good_word := "good" if items.size() == 2 else "goods"
		message += " and %d units of %d other %s sold for £%.2f" % [
			other_qty,
			items.size() - 1,
			good_word,
			other_revenue,
		]
	message += ". Total sales: £%.2f" % float(sale_record.get("total_revenue", 0.0))
	return message

func _push_toast(stack: VBoxContainer, message: String, toast_type: String) -> void:
	# Nothing that fires while the world is still building behind the loading screen
	# is player-initiated — it is the match-start seeding (NPC ports, start companies,
	# their material orders). Those toasts used to expire unseen under a ~60 s load;
	# now that the build finishes in ~11 s they were still on screen at the reveal.
	# (The `swap loading_screen` cheat keeps them, to reproduce the old load faithfully.)
	if LoadPacing.is_background_build() and not LoadPacing.legacy_load:
		return
	var toast: PanelContainer = _make_toast(message, toast_type)
	stack.add_child(toast)
	# Detach the oldest BEFORE queue_free — queue_free is deferred until
	# end-of-frame, so it does NOT decrement get_child_count(). Without the
	# explicit remove_child, this while loop becomes infinite the moment the
	# cap is first hit, freezing the engine.
	while stack.get_child_count() > MAX_TOASTS:
		var oldest: Node = stack.get_child(0)
		stack.remove_child(oldest)
		oldest.queue_free()
	# Timer is a child of the toast — if the toast is force-removed (cap
	# exceeded), the timer is freed with it and no orphaned callback fires.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = TOAST_DURATION
	toast.add_child(timer)
	timer.timeout.connect(_dismiss_toast.bind(toast))
	timer.start()

func _make_toast(message: String, toast_type: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = _toast_bg_color(toast_type)
	sb.border_color = _toast_border_color(toast_type)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if toast_type == TOAST_WARNING:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _toast_text_color(toast_type))
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	return panel

func _toast_bg_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_BG
		TOAST_CAUTION:
			return CAUTION_BG
		_:
			return SUCCESS_BG

func _toast_border_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_BORDER
		TOAST_CAUTION:
			return CAUTION_BORDER
		_:
			return SUCCESS_BORDER

func _toast_text_color(toast_type: String) -> Color:
	match toast_type:
		TOAST_WARNING:
			return WARNING_TEXT
		TOAST_CAUTION:
			return CAUTION_TEXT
		_:
			return SUCCESS_TEXT

func _dismiss_toast(toast: Node) -> void:
	if not is_instance_valid(toast):
		return
	if toast.has_meta("_dismissing"):
		return
	toast.set_meta("_dismissing", true)
	var tween: Tween = toast.create_tween()
	tween.tween_property(toast, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(toast.queue_free)
