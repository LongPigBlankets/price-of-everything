extends CanvasLayer
## One-time Metal Magnate start intro, mounted over the HUD by world_map on a fresh
## metal_magnate start: an iron-ingots hero icon + the "Metal Magnate" title, the
## founding lore, the Legacy of Metal bonus line, and a Begin button.

signal begin_pressed

const GoodIcons := preload("res://scripts/good_icons.gd")
const PipeFrame := preload("res://scripts/pipe_frame.gd")
const TITLE_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const BONUS_FONT := preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")

const LORE_PARAGRAPHS := [
	"Your father always told you there's truth in metal. He was a hard working sort, always by the bellows or the forge, always shoulder to shoulder with his workers. He had big dreams and bigger hands. Working on his steel mill, saving up for a motors factory. He wanted to go big.",
	"But then he couldn't quite reach it. So he's pinned his hopes on you.",
	"You've saved what little remained of his old company after he had to sell the steel mill. The coal mines are running out, the iron mines too. But every time you look down the shaft you can see there's more potential there.",
	"Maybe you can succeed where your father couldn't. After all, you hear what they're saying in the furnace halls now, how they whisper when you walk past. They look up to you. They call you the Metal Magnate. You tell yourself you shouldn't let it go to your head. It would be too easy to rest on your laurels.",
	"So... what will you make of yourself and your business. How will you leave your mark?",
]
const BONUS := "Legacy of Metal Bonus: +10% iron ingots, copper ingots, alloy metal ingots and steel output."

var _input_blocked_parent: Node = null

func _ready() -> void:
	layer = 150
	_build()
	# Modal: suspend the map's own input (Tab → Empire View, X → Search, map clicks)
	# while the intro is up. The scrim only blocks the mouse; hotkeys reach world_map
	# via _input / _unhandled_input, so disable those on the parent and restore on exit.
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
	# The tile-view dark-brown pipe frame (navy fill + brown pipe, no coloured outline).
	card.add_theme_stylebox_override("panel", PipeFrame.dark_brown_stylebox(34.0))
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	card.add_child(col)

	# Header: iron-ingots icon + the big title to its right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 22)
	col.add_child(header)
	var icon := TextureRect.new()
	icon.texture = GoodIcons.texture_for("g_004", "iron_ingots", false)
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(icon)
	var title := Label.new()
	title.text = "Metal Magnate"
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
