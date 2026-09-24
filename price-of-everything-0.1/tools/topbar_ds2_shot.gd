extends Node2D
## Captures of the top bar for the DS2 work (docs/top-bar-ds2-plan.md), in the real HUD, in fixed
## SubViewports at two pixels per logical pixel so captures match whatever display runs them:
## 1920 × 1080, 2520 × 1080 (ultrawide) and 1920 × 1200. For each size and each look (v3.1, and DS2
## via UiPrefs.use_topbar_ds2): the bar calm, in crisis (cash below zero after a loss), with long
## numbers, with the Power module hovered, and with the Treasury flyout open.
##   Godot --path . res://tools/topbar_ds2_shot.tscn --quit-after 12000 -- --no-telemetry
## Writes topbar_<look>_<size>_<view>.png into $TOPBAR_SHOT_DIR (or /tmp).

const SIZES := [Vector2i(1920, 1080), Vector2i(2520, 1080), Vector2i(1920, 1200)]
## How much of the screen's top each view keeps, in logical px: the bar alone, or the flyout under it.
const BAR_CROP := 96.0
const FLYOUT_CROP := 520.0

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("TOPBAR_SHOT_DIR")
	if dir != "":
		_out = dir
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	_vp.size_2d_override_stretch = true
	_set_size(SIZES[0])
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	TurnManager.current_turn = 12
	var bar: Control = _wm.get_node("UILayer/HUD/TopBar")
	var was: bool = UiPrefs.use_topbar_ds2
	for logical: Vector2i in SIZES:
		_set_size(logical)
		await _settle(20)
		for look: String in ["v31", "ds2"]:
			UiPrefs.set_use_topbar_ds2(look == "ds2")
			await _settle(10)
			await _views(bar, "%s_%dx%d" % [look, logical.x, logical.y])
	UiPrefs.set_use_topbar_ds2(was)
	print("[TOPBAR_SHOT] done")
	get_tree().quit(0)


func _views(bar: Control, tag: String) -> void:
	_money(5717.0, -555.0)
	await _settle(8)
	_save(tag + "_calm", BAR_CROP)
	_money(-1284.37, -2310.0)
	await _settle(8)
	_save(tag + "_crisis", BAR_CROP)
	_money(12345678.0, 245678.0)
	await _settle(8)
	_save(tag + "_long", BAR_CROP)
	_money(5717.0, -555.0)
	var power: Control = bar.find_child("PowerModule", true, false)
	if power != null:
		power.mouse_entered.emit()
		await _settle(6)
		_save(tag + "_hover", BAR_CROP)
		power.mouse_exited.emit()
	bar.call("_toggle_fly", "treasury")
	await _settle(12)
	_save(tag + "_treasury", FLYOUT_CROP)
	bar.call("_close_fly")
	await _settle(6)


## Cash and last turn's net as the bar reads them.
func _money(cash: float, net: float) -> void:
	MatchState.money = cash
	Production.last_turn_summary = {"money_in": maxf(net, 0.0), "money_out": maxf(-net, 0.0)}
	MatchState.money_changed.emit(cash)


func _set_size(logical: Vector2i) -> void:
	_vp.size = logical * 2
	_vp.size_2d_override = logical


func _save(tag: String, crop_h: float) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(_vp.size_2d_override.x)
	var r := Rect2i(0, 0, img.get_width(), int(crop_h * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_out.path_join("topbar_%s.png" % tag))
	print("[TOPBAR_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
