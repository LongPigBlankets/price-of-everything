extends Control

## Title screen: a black backdrop with a single New Game button that drops the
## player into the map (which used to be the landing scene). A short "slide into
## slot" cue replays on a timer while this screen is up (main-menu only - the
## player and timer are children of this scene, so they're freed on New Game).

const MAP_SCENE := "res://scenes/main.tscn"
const SLIDE_SOUND: AudioStream = preload("res://assets/audio/ui_sounds/slide_into_slot.wav")
const SLIDE_INTERVAL := 4.0

@onready var new_game_button: Button = $NewGameButton


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	_start_slide_loop()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


func _start_slide_loop() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = SLIDE_SOUND
	add_child(player)
	var timer := Timer.new()
	timer.wait_time = SLIDE_INTERVAL
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func() -> void: player.play())
	player.play()  # play once now, then every SLIDE_INTERVAL seconds
