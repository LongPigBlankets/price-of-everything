extends CanvasLayer
## One-time Glass Merchant start intro, mounted over the HUD by world_map on a fresh
## glass_merchant start: a glass hero icon + the "Glass Merchant" title, the lore,
## the Vandel Glassworks bonus line, and a Begin button. Mirrors metal_magnate_intro.gd.

signal begin_pressed

const GoodIcons := preload("res://scripts/good_icons.gd")
const PipeFrame := preload("res://scripts/pipe_frame.gd")
const TITLE_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const BONUS_FONT := preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")

# Owner copy (2026-08-29).
const LORE_PARAGRAPHS := [
	"Nobody in Vandel thought there was money in sand. The dunes were where people walked dogs and dumped rubbish. But you stood in a furnace hall once and watched the harsh sand melt and turn red hot, then clear. You could never look at the sand dunes the same way again.",
	"You saw what sand could become. So you borrowed. Heavily. Everyone doubted you. The quarry went up first, then the furnaces. Now they don't doubt you any longer. Now everyone you know whispers how they always saw the potential in you, how they knew you had it in you. You ignore the whispers and focus on the work.",
	"Glass is an honest trade. It doesn't rust and it doesn't lie. But one flaw, and a sheet that survived a thousand degrees shatters into a thousand pieces. The weight of that work hangs heavy over you.",
	"They've started calling you the Glass Merchant. In Vandel that isn't entirely a compliment. It means someone so plain you can see straight through. Fine. Let them look. The furnaces are lit and so are your eyes when you look to the future.",
	"Where will you take this next? Will you stun everyone a second time?",
]
const BONUS := "Vandel Glassworks Bonus: +5% glass output and +5% window output."

var _input_blocked_parent: Node = null

func _ready() -> void:
	layer = 150
	_build()
	# Modal: suspend the map's own input while the intro is up (see metal_magnate_intro).
	_input_blocked_parent = get_parent()
	if _input_blocked_parent != null:
		_input_blocked_parent.set_process_input(false)
		_input_blocked_parent.set_process_unhandled_input(false)

func _exit_tree() -> void:
	if _input_blocked_parent != null and is_instance_valid(_input_blocked_parent):
		_input_blocked_parent.set_process_input(true)
		_input_blocked_parent.set_process_unhandled_input(true)

func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.01, 0.03, 0.06, 0.85)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(780, 0)
	card.add_theme_stylebox_override("panel", PipeFrame.dark_brown_stylebox(34.0))
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	card.add_child(col)

	# Header: glass icon + the big title to its right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 22)
	col.add_child(header)
	var icon := TextureRect.new()
	icon.texture = GoodIcons.texture_for("g_038", "glass")
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(icon)
	var title := Label.new()
	title.text = "Glass Merchant"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color("#F2E6C8"))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)

	var rule := HSeparator.new()
	col.add_child(rule)

	# Lore (scrolls if the viewport is short).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 336)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var lore := Label.new()
	lore.text = "\n\n".join(LORE_PARAGRAPHS)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.add_theme_font_size_override("font_size", 16)
	lore.add_theme_color_override("font_color", Color("#C6D4E4"))
	lore.custom_minimum_size = Vector2(716, 0)
	scroll.add_child(lore)

	# Bonus line — bold, green, matching the reward palette.
	var bonus := Label.new()
	bonus.text = BONUS
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus.add_theme_font_override("font", BONUS_FONT)
	bonus.add_theme_font_size_override("font_size", 16)
	bonus.add_theme_color_override("font_color", Color("#5BD180"))
	col.add_child(bonus)

	# Begin button.
	var begin := Button.new()
	begin.text = "Begin"
	begin.theme_type_variation = &"Primary"
	begin.custom_minimum_size = Vector2(170, 42)
	begin.size_flags_horizontal = Control.SIZE_SHRINK_END
	begin.focus_mode = Control.FOCUS_NONE
	begin.pressed.connect(_on_begin)
	col.add_child(begin)

func _on_begin() -> void:
	begin_pressed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_on_begin()
		get_viewport().set_input_as_handled()
