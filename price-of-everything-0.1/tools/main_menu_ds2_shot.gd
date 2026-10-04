extends Node
## Captures of the main menu at 1920 × 1080, at rest after its goods board has filled.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/main_menu_ds2_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes main_menu.png into $MENU_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("MENU_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 120.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(2.0).timeout
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("main_menu.png"))
	get_tree().quit()
