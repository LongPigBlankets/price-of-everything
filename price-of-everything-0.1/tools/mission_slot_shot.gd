extends Node
## Captures of the DS2 top bar's mission slot (scripts/ds2/mission_slot.gd) in a Metal Magnate game:
## at rest with a count, then through a completion (mid stroke with steam, full stroke, the next mission
## after the snap back). Crops the bar's left half at the window's pixels.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/mission_slot_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes mission_slot_<view>.png into $MISSION_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"
const CROP_LOGICAL := Vector2(1100.0, 80.0)

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("MISSION_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game(START)
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene = world
	await _settle(200)
	MatchState.ruleset["opener_done"] = true   # these captures are of the missions, not the opening steps
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	# The start's story intro dims the screen until dismissed: close it.
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(30)
	var bar: Node = world.find_child("TopBar", true, false)
	if bar == null:
		push_error("mission_slot_shot: no TopBar")
		get_tree().quit(1)
		return
	await _shot("rest")
	# A count to show: the steel mission's first step done.
	MiniQuest.done["steel"] = [true, false]
	MiniQuest.quest_changed.emit()
	await _settle(10)
	await _shot("count")
	# The completion, timed against the slot's own tween.
	MiniQuest.done["steel"] = [true, true]
	bar.call("_celebrate_mission", "steel")
	await _wait(0.35)
	await _shot("stroke")
	await _wait(0.3)
	await _shot("full")
	await _wait(1.2)
	await _shot("next")
	# A title longer than the key allows: cut short at the cap.
	var slot: Control = bar.get("_mission_slot")
	bar.get("_quest_title").text = "Ship your coal from the new mine to every tile that burns it"
	slot.call("set_mission", "Ship your coal from the new mine to every tile that burns it", Vector2i(3, 10))
	bar.call("_place_quest")
	await _settle(6)
	await _shot("long")
	bar.call("_refresh_quest")
	# Collapsed: the icon and the counter, the text on hover. Set without saving the profile.
	PlayerProfile.mission_bar_collapsed = true
	bar.call("_refresh_quest")
	await _settle(8)
	await _shot("collapsed")
	bar.set("_ds2_hover", bar.get("_quest_btn"))
	bar.call("_ds2_show_readout")
	await _settle(4)
	await _shot("collapsed_hover", 190.0)
	bar.set("_ds2_hover", null)
	(bar.get("_ds2_readout") as Control).visible = false
	PlayerProfile.mission_bar_collapsed = false
	bar.call("_refresh_quest")
	bar.call("_toggle_fly", "quest")
	await _wait(0.6)
	await _shot("panel", 1080.0)
	# The Tutorial part way through, then Metal Magnate's own board. Driven through MiniQuest's state; the
	# panel rebuilds itself from the change.
	var Panel := preload("res://scripts/missions_ds2/missions_panel.gd")
	MiniQuest.board_done["t_open"] = true
	MiniQuest.board_done["t_sell"] = true
	MiniQuest.board_baseline["t_buy"] = 0.0
	Panel.open_board = "tutorial"
	Panel.open_station = "t_buy"
	MiniQuest.quest_changed.emit()
	await _wait(0.8)
	await _shot("board_tutorial", 1080.0)
	Panel.open_board = "magnate"
	Panel.open_station = ""
	MiniQuest.quest_changed.emit()
	await _wait(0.8)
	await _shot("board_magnate", 1080.0)
	get_tree().quit()


func _shot(view: String, height: float = CROP_LOGICAL.y) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var crop := Rect2i(Vector2i.ZERO, Vector2i(Vector2(CROP_LOGICAL.x, height) * k))
	img.get_region(crop).save_png(_out.path_join("mission_slot_%s.png" % view))
	img = null
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
