extends Node2D
## Phase 4's screens (docs/pacing-labour-mining-licensing-spec.md §8.8): a finite coal seam worked past its free
## cap (a level 1 mine and two level 2 mines on tile_6_8, digging 300 a turn against 180 free, M 3), seen in the tile view's
## Goods tab, Building Detail's visual diagnostics (the Seam check in the Plant stage), the upgrade dialog's seam
## row, and the seam card in the Turn Briefing.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/mining_shot.tscn --quit-after 6000 -- --no-telemetry
## Writes mining_*.png into $MINING_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_6_8"

var _wm
var _out := "/tmp"


func _ready() -> void:
	if OS.get_environment("MINING_SHOT_DIR") != "":
		_out = OS.get_environment("MINING_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 300.0)
	ShotHarness.prepare_window(get_window(), LOGICAL)
	TelemetryState.enabled = false
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	MatchState.mark_tile_surveyed(TILE)
	BuildingState.tile_land_owned[TILE] = 200
	var first := _mine(1)
	_mine(2)
	_mine(2)
	MatchState.deposit_remaining[TILE] = {"coal": 4120}
	print("[MINING_SHOT] %s" % preload("res://scripts/mining_sites.gd").seam_words(TILE, "coal"))

	# The tile view, on Goods.
	var coord: Vector2i = _wm.terrain_layer.id_to_coord(TILE)
	var tile_data: Dictionary = _wm.terrain_layer.tiles.get(coord, {})
	_wm.info_panel.show_tile(tile_data, "prod")
	await _settle(16)
	var row: Control = _wm.info_panel.find_child("Deposit_coal", true, false)
	var body_scroll: ScrollContainer = _wm.info_panel.get("_body_scroll")
	if row != null and body_scroll != null:
		body_scroll.ensure_control_visible(row)
		await _settle(6)
	_save(_wm.info_panel.get_global_rect(), "mining_tile_view")

	# Building Detail, diagnostics thrown to Visual.
	_wm._open_building_detail(BuildingState.get_building(first))
	await _settle(24)
	var panel: Control = _wm.building_panel_v2
	var toggle: Control = panel.find_child("ViewSwitch", true, false).find_child("BdpV3Toggle", false, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	toggle._gui_input(click)
	await _settle(8)
	var view: Control = panel.find_child("DiagnosticsVisual", true, false)
	if view != null:
		panel._scroll.ensure_control_visible(view.get_parent().get_parent())
		await _settle(6)
		for ind: Node in view.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n.get_script() == load("res://scripts/bdp_v3_indicator.gd")):
			if str(ind.stage) == "Plant":
				print("[MINING_SHOT] check %s · %s [%s] %s" % [ind.stage, ind.label, ind.tone, ind.detail])
	_save(panel.get_global_rect(), "mining_bdp_diag")
	_wm.building_panel_v2.visible = false

	# The upgrade dialog for the level 1 mine.
	var gate := preload("res://scripts/building_levels.gd").research_gate("mine", 2)
	if gate != "":
		ResearchState.grant_unlock(gate)
	var dialog: Node = _wm.find_child("UpgradeDialog", true, false)
	if dialog == null:
		dialog = load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd").new()
		var layer: Node = _wm.get_node_or_null("UILayer")
		(layer if layer != null else _wm).add_child(dialog)
		(dialog as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _settle(5)
	dialog.call("open", first)
	await _settle(30)
	_save(Rect2(Vector2.ZERO, Vector2(LOGICAL)), "mining_upgrade")
	if dialog.has_method("close"):
		dialog.call("close")
	await _settle(6)

	# The seam card, in the Turn Briefing, with the side panels out of its way.
	_wm.info_panel.visible = false
	TurnBriefing.enabled = true
	DecisionState.enabled = true
	DecisionState.auto_resolve = false
	DecisionState.pending_queue.clear()
	MatchState.money = 2000.0
	DecisionState.draw_with_target("seam_running_out", MatchState.seams.target_for(TILE, "coal"))
	TurnBriefing.expand()
	await _settle(30)
	var brief: Control = TurnBriefing.get("_panel")
	if brief != null:
		_save(brief.get_global_rect(), "mining_seam_card_panel")
	_save(Rect2(Vector2.ZERO, Vector2(LOGICAL)), "mining_seam_card")
	print("[MINING_SHOT] done")
	get_tree().quit(0)


func _mine(level: int) -> String:
	var iid: String = BuildingState.add_building("b_001", "r_001", TILE, MatchState.LOCAL_PLAYER, "")
	var b := BuildingState.get_building(iid)
	b.erase("staff_fill")
	b["level"] = level
	return iid


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := img.get_width() / get_viewport().get_visible_rect().size.x
	var px := Rect2i(Vector2i(r.grow(6.0).position * k), Vector2i(r.grow(6.0).size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[MINING_SHOT] saved %s" % tag)
