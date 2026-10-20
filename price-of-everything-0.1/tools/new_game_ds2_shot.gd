extends Node
## Captures of the New Game settings screen as the company registry (scripts/new_game_ds2/new_game_ds2.gd), the panel
## alone at its width of 1396 on a dark backdrop, in a SubViewport at two pixels a logical pixel so every capture has
## the same pixels whatever the display. States: the full game with the recommended start, the full game with the
## Troubled Carmaker open (a building pointed at, Hard stamped, a 200 turn charter), and the demo with its lockboxes.
## Needs a window:
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/new_game_ds2_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes <state>.png into $NEW_GAME_SHOT_DIR (default artifacts/new_game_ds2/ds2_v1).

const ShotHarness := preload("res://tools/shot_harness.gd")
const DebugTerminal := preload("res://scripts/debug_terminal.gd")
const PANEL_SCRIPT := "res://scripts/new_game_ds2/new_game_ds2.gd"
const PANEL := Vector2(1396, 966)
const MARGIN := 20.0

var _vp: SubViewport
var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("NEW_GAME_SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://artifacts/new_game_ds2/ds2_v1")
	DirAccess.make_dir_recursive_absolute(_dir)
	ShotHarness.arm_watchdog(self, 240.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1600, 1000))
	TelemetryState.enabled = false
	var logical := Vector2i(PANEL + Vector2(MARGIN, MARGIN) * 2.0)
	_vp = SubViewport.new()
	_vp.size = logical * 2
	_vp.size_2d_override = logical
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	_vp.transparent_bg = false
	add_child(_vp)
	var back := ColorRect.new()
	back.color = Color("#121820")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(back)
	UiPrefs.set_use_new_game_ds2(true)

	DebugTerminal._demo_unlocked = true
	var panel: Control = await _open()
	await _shot("01_full_default")
	var files: Array = panel.get("_card_buttons")
	for i in files.size():
		if str((panel.get("_starts")[i] as Dictionary).get("id", "")) == "troubled_carmaker":
			(files[i] as Button).button_pressed = true
	await _settle(4)
	panel.call("_hover", 1)
	panel.call("_choose_grade", "hard")
	panel.call("_step_speed", -1)
	await _settle(90)
	await _shot("02_full_carmaker")
	panel.queue_free()
	await _settle(2)

	DebugTerminal._demo_unlocked = false
	panel = await _open()
	await _shot("03_demo_lockboxes")
	panel.queue_free()
	await _settle(2)
	print("[NEW_GAME_SHOT] done, %s" % _dir)
	get_tree().quit(0)


func _open() -> Control:
	var panel: Control = (load(PANEL_SCRIPT) as GDScript).new()
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = PANEL
	_vp.add_child(panel)
	await _settle(12)
	return panel


func _settle(frames: int) -> void:
	for _i in frames:
		RenderingServer.force_draw(false)
		await get_tree().process_frame


func _shot(state: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	img.save_png(_dir.path_join(state + ".png"))
	print("[NEW_GAME_SHOT] %s %s" % [state, img.get_size()])
