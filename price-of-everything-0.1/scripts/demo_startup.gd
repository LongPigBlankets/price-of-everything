extends Control
## Entry point: do not instantiate the menu (or its asset warming) before acceptance.

const Agreement := preload("res://scripts/demo_eula.gd")
const AgreementScreen := preload("res://scripts/eula_screen.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

# Tools/tests can supply an isolated record without touching the player's files.
var acceptance_file: String = ""
var _screen: AgreementScreen
var _entering_menu: bool = false
var _closing: bool = false


func _ready() -> void:
	if Agreement.is_accepted(acceptance_file):
		_enter_menu.call_deferred()
		return
	_screen = AgreementScreen.new()
	_screen.name = "EulaScreen"
	_screen.accept_requested.connect(_on_accept)
	_screen.close_requested.connect(_on_close)
	add_child(_screen)


func _on_accept() -> void:
	if _entering_menu or _closing:
		return
	if Agreement.accept(acceptance_file) != OK:
		_screen.show_save_error()
		return
	_enter_menu.call_deferred()


func _enter_menu() -> void:
	if _entering_menu or _closing:
		return
	_entering_menu = true
	# This only defers the existing launch lifecycle; it is not telemetry consent.
	TelemetryState.start_session()
	var error := get_tree().change_scene_to_file(MENU_SCENE)
	if error != OK:
		_entering_menu = false
		push_error("Could not open the main menu: %s" % error_string(error))


func _on_close() -> void:
	# No exit survey or telemetry upload on declining the agreement.
	if _closing:
		return
	_closing = true
	_screen.close_button.disabled = true
	_screen.accept_button.disabled = true
	Audio.silence_for_quit()
	get_tree().quit.call_deferred()
