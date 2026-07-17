extends Node
## Windowed shot of the tile-at-capacity dialog (capacity_dialog.gd) after wiring the
## Expand button to the real warehouse upgrade. Captures two states:
##   _market : player has cash but not the materials -> "£N at market", Expand enabled
##   _empire : materials are in stock              -> "from your stockpiles"
## and one where the tile is already maxed so Expand is disabled.
##   <godot> --path . res://tools/capacity_dialog_shot.tscn --quit-after 3000

const MAIN_SCENE := "res://scenes/main.tscn"
const DIALOG := "res://scripts/capacity_dialog.gd"
const TILE := "tile_16_4"

var _main: Node = null
var _dlg: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 3000:
		get_tree().quit(1)


func _run() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.set("edge_pan_enabled", false)

	# Own instance in a full-screen holder so the dialog's centre anchors resolve.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(holder)
	_dlg = load(DIALOG).new()
	holder.add_child(_dlg)
	await get_tree().process_frame

	# A) cash but no materials -> market payment line, Expand enabled.
	MatchState.money = 100000.0
	_dlg._on_tile_reached_capacity(TILE)
	await _settle()
	_capture("capacity_dialog_market.png")

	# B) materials on hand -> empire payment line. Add the L1->L2 bill to stock and
	# refresh the tile that's already showing.
	Stockpile.add(TILE, "g_023", 40)
	Stockpile.add(TILE, "g_071", 40)
	Stockpile.add(TILE, "g_027", 40)
	_dlg._refresh_for_tile()
	await _settle()
	_capture("capacity_dialog_empire.png")

	get_tree().quit(0)


func _settle() -> void:
	for _i in 8:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
