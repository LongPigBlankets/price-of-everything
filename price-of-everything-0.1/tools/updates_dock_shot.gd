extends Node2D
## Captures of the bottom-left updates dock (toast_manager.gd) in the real HUD, at 1920 × 1080 with
## two pixels each: the empty dock, rows sliding out on their own, the dock after they collapse
## (bells counting), the slide-out opened from the dock, the dock under an open Construct panel,
## and a map legend stacked on top of it.
##   Godot --path . res://tools/updates_dock_shot.tscn --quit-after 6000 -- --no-telemetry
## Writes updates_dock_*.png into $UPDATES_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
## The bottom-left region each crop takes, in logical px: wide enough for the Construct panel's edge.
const CROP := Rect2(0, 380, 700, 700)

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("UPDATES_SHOT_DIR")
	if dir != "":
		_out = dir
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	var toasts: Control = _wm.get_node("UILayer/HUD/ToastLayer")
	toasts.clear()
	await _settle(10)
	_save("empty")

	MatchState.request_toast("Built Industrial Goods Factory — produces 49 Steel/turn  ·  £10", "success")
	MatchState.request_toast("Ordered 14 Steel, 14 Cement — arriving in 2 turns", "success")
	MatchState.request_toast("Local opposition to density on tile 5,10 will increase material and money costs for new buildings by 50%", "caution")
	MatchState.request_toast("!  Cash is in the red: £-120.00", "warning")
	MatchState.request_toast("There is no more room on that tile. Demolish buildings to make room.", "error")
	await _wait(0.45)
	_save("peek")
	await _wait(toasts.TOAST_DURATION + 0.6)
	_save("collapsed")

	toasts.open_all()
	await _wait(0.45)
	_save("opened")
	toasts.collapse()
	await _wait(0.45)

	var cp: Control = _wm.find_child("ConstructPanelV2", true, false)
	if cp != null and cp.has_method("open_browser"):
		cp.call("open_browser")
		await _settle(20)
		MatchState.request_toast("Construction started for Glass Furnace on tile Stoneshore Docks. Will be complete in 2 turns", "success")
		await _wait(0.45)
		_save("over_construct")
		cp.hide()
		await _wait(toasts.TOAST_DURATION + 0.6)

	MapMode.set_sentinel_mode(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)
	await _settle(30)
	_save("with_legend")
	MapMode.clear_all()
	print("[UPDATES_DOCK_SHOT] done")
	get_tree().quit(0)


func _save(tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var r := Rect2i(Vector2i(CROP.position * k), Vector2i(CROP.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_out.path_join("updates_dock_%s.png" % tag))
	print("[UPDATES_DOCK_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
