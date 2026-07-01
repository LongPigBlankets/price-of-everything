extends PanelContainer
## "Unlocked …" popup, shown when a research unlock is earned by meeting its
## condition (never for a free-chosen unlock). Shows the unlock name, its reward
## (the CSV description), and a Continue button.

var _title_label: Label
var _reward_label: Label
var _unlock_scroll: ScrollContainer
var _unlock_list: VBoxContainer

const _UNLOCK_CARD_MIN_HEIGHT := 92.0
const _UNLOCK_LIST_WIDTH := 560.0
const _UNLOCK_LIST_MAX_HEIGHT := 340.0

func _ready() -> void:
	theme = DS.theme
	visible = false
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(420.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name = "UnlockDialog"

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	_title_label = Label.new()
	_title_label.theme_type_variation = "Title"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title_label)

	_reward_label = Label.new()
	_reward_label.theme_type_variation = "Section"
	_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_label.add_theme_color_override("font_color", DS.PALETTE.OK)
	vb.add_child(_reward_label)

	_unlock_scroll = ScrollContainer.new()
	_unlock_scroll.name = "UnlockScroll"
	_unlock_scroll.visible = false
	_unlock_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unlock_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vb.add_child(_unlock_scroll)

	_unlock_list = VBoxContainer.new()
	_unlock_list.name = "UnlockList"
	_unlock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unlock_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_unlock_list.add_theme_constant_override("separation", 10)
	_unlock_scroll.add_child(_unlock_list)

	var cont := Button.new()
	cont.theme_type_variation = "Primary"
	cont.text = "Continue"
	cont.size_flags_horizontal = Control.SIZE_SHRINK_END
	cont.pressed.connect(_close)
	vb.add_child(cont)

func show_unlock(title: String, description: String) -> void:
	_clear_unlock_cards()
	_title_label.text = "Unlocked  %s" % title
	_reward_label.text = description if description != "" else "New technology available."
	_reward_label.visible = true
	_unlock_scroll.visible = false
	visible = true
	PanelStack.push(self)

func show_unlocks(unlocks: Array) -> void:
	var cards := _normalised_unlocks(unlocks)
	if cards.size() <= 1:
		var only: Dictionary = {}
		if not cards.is_empty():
			only = cards[0]
		show_unlock(str(only.get("title", "")), str(only.get("description", "")))
		return
	_clear_unlock_cards()
	_title_label.text = "%d unlocks" % cards.size()
	_reward_label.visible = false
	_unlock_scroll.visible = true
	var visible_count := mini(cards.size(), 3)
	var list_height := minf(
		_UNLOCK_LIST_MAX_HEIGHT,
		float(visible_count) * _UNLOCK_CARD_MIN_HEIGHT + float(maxi(0, visible_count - 1)) * 10.0
	)
	_unlock_scroll.custom_minimum_size = Vector2(_UNLOCK_LIST_WIDTH, list_height)
	_unlock_list.custom_minimum_size = Vector2(_UNLOCK_LIST_WIDTH, list_height)
	for unlock in cards:
		_unlock_list.add_child(_make_unlock_card(unlock))
	visible = true
	PanelStack.push(self)

func _make_unlock_card(unlock: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "UnlockCard"
	card.theme_type_variation = "Outlined"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, _UNLOCK_CARD_MIN_HEIGHT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	var title := Label.new()
	title.name = "UnlockTitle"
	title.theme_type_variation = "BuildingName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = str(unlock.get("title", "")).strip_edges()
	if title.text == "":
		title.text = "Research unlocked"
	vb.add_child(title)

	var reward := Label.new()
	reward.name = "UnlockReward"
	reward.theme_type_variation = "Section"
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward.add_theme_color_override("font_color", DS.PALETTE.OK)
	reward.text = str(unlock.get("description", "")).strip_edges()
	if reward.text == "":
		reward.text = "New technology available."
	vb.add_child(reward)
	return card

func _normalised_unlocks(unlocks: Array) -> Array:
	var normalised: Array = []
	for unlock in unlocks:
		if unlock is Dictionary:
			normalised.append({
				"title": str(unlock.get("title", "")).strip_edges(),
				"description": str(unlock.get("description", "")).strip_edges(),
			})
		else:
			var title := str(unlock).strip_edges()
			if title != "":
				normalised.append({"title": title, "description": ""})
	return normalised

func _clear_unlock_cards() -> void:
	if _unlock_list == null:
		return
	for child in _unlock_list.get_children():
		_unlock_list.remove_child(child)
		child.queue_free()

func _close() -> void:
	visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)
