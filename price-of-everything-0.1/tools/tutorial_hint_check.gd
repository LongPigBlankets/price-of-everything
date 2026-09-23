extends Node
const Paths := preload("res://scripts/app_paths.gd")
const Steps := preload("res://scripts/tutorial/tutorial_steps.gd")
const Authored := preload("res://scripts/authored_map.gd")
var capper := false
var started := false
func _ready() -> void:
	if get_tree().current_scene != self:
		capper = true
		return
	Paths._base = "/tmp/cnc-tutorial-hints"
	RunMetrics.enabled = false
	preload("res://tools/shot_harness.gd").prepare_window(get_window(), Vector2i(1920,1080))
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 120.0)
	var cap: Node = load("res://tools/tutorial_hint_check.gd").new()
	get_tree().root.add_child.call_deferred(cap)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
func _process(_dt: float) -> void:
	if not capper or started: return
	var world := get_tree().current_scene
	if world != null and world.get("build_complete") == true and Tutorial.active:
		started = true
		run()
func settle(frames: int = 35) -> void:
	for i in frames: await get_tree().process_frame
func snap(name: String) -> void:
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/tmp/" + name + ".png")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("[HintProbe] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	await settle()
	var world := get_tree().current_scene
	world.reveal_for_play()
	Tutorial._jump_to("goto_tile")
	await get_tree().create_timer(4.0).timeout
	check(Tutorial._route_highlight == null or Tutorial._route_highlight._tile_centres.is_empty(), "factory cue is absent four seconds into the step")
	await get_tree().create_timer(1.2).timeout
	check(Tutorial._route_highlight != null and Tutorial._route_highlight._tile_centres.has(Steps.WINDOW_TILE), "factory tile flashes after five seconds")
	check(Tutorial._route_highlight._flash_color == Color.WHITE and Tutorial._route_highlight._pulse_count == 10, "factory cue matches the coastal white flash")
	snap("tutorial-factory-delayed-flash")
	Tutorial._jump_to("build_open")
	check(Tutorial._route_highlight._tile_centres.is_empty(), "leaving clears the factory flash")
	Tutorial._run_setup([{"action":"close_tile_panel"}, {"action":"close_construct"}])
	Tutorial._jump_to("goto_tile")
	await get_tree().create_timer(1.0).timeout
	Tutorial._jump_to("build_open")
	await get_tree().create_timer(4.3).timeout
	check(Tutorial._route_highlight._tile_centres.is_empty(), "leaving early cancels the pending cue")
	var fabric := get_tree().get_first_node_in_group("authored_fabric")
	var hidden := 0
	for settlement in Authored.settlements().values():
		for record in settlement.get("specials", []):
			if fabric._tutorial_hides_port_warehouse(record): hidden += 1
	check(hidden == 2, "exactly two dock warehouses hidden in tutorial")
	Tutorial._run_setup([{"action":"close_tile_panel"}, {"action":"close_construct"}])
	var map := get_tree().get_first_node_in_group("hex_map")
	var coord: Vector2i = map.id_to_coord(Steps.PORT_TILE)
	var centre: Vector2 = map.to_global(map.map_to_local(map.map_coord_for_tile_coord(coord)))
	var camera := get_viewport().get_camera_2d()
	if camera._pan_tween != null: camera._pan_tween.kill()
	if camera._intro_tween != null: camera._intro_tween.kill()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.global_position = centre + Vector2(0, 240)
	camera.zoom = Vector2.ONE * 2.0
	camera.force_update_scroll()
	Tutorial._overlay.hide()
	await settle(80)
	snap("tutorial-docks-hidden")
	MatchState.ruleset["tutorial_enabled"] = false
	var visible := 0
	for settlement in Authored.settlements().values():
		for record in settlement.get("specials", []):
			if str(record.get("port", "")) == Steps.PORT_TILE and str(record.get("port_role", "")) == "warehouse" and not fabric._tutorial_hides_port_warehouse(record): visible += 1
	check(visible == 2, "both warehouses remain visible outside tutorial")
	fabric.queue_redraw()
	await settle()
	snap("tutorial-docks-normal-control")
	print("[HintProbe] failures=", failures)
	get_tree().quit(1 if failures else 0)
