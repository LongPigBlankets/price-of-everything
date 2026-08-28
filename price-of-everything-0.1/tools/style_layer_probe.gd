extends Node2D
## Diagnostic: which map LAYERS are alive in which style?
##
## The question this answers is "does making midcentury the default turn anything off" --
## and the layer that matters is UrbanFabricVisuals, the PROCEDURAL decorative fabric, which
## gates on both the style and on whether an authored document is active.
##   <godot> --headless --path . res://tools/style_layer_probe.tscn --quit-after 900

const ShotHarness := preload("res://tools/shot_harness.gd")
const AuthoredMapData := preload("res://scripts/authored_map.gd")

const WATCH := ["UrbanFabricVisuals", "AuthoredFabricVisuals", "AuthoredRoadVisuals",
	"ForestVisuals", "PortVisuals", "HillVisuals", "ParchmentOverlay",
	"RoadNetworkVisuals", "RiverVisuals", "BuildingVisuals",
	"SmokeVisuals", "ConstructionVisuals", "PortShipVisuals", "BirdVisuals"]

var _wm: Node


func _layers() -> String:
	var line := ""
	for layer_name in WATCH:
		var node := _wm.find_child(layer_name, true, false) as CanvasItem
		if node == null:
			line += " %s=MISSING" % layer_name
		else:
			line += " %s=%s" % [layer_name, "on" if node.visible else "OFF"]
	return line


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 300.0)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 200:
		await get_tree().process_frame
	print("[LAYER] AuthoredMapData.is_active() = %s  (settlements: %d)"
		% [AuthoredMapData.is_active(), AuthoredMapData.settlements().size()])
	print("[LAYER] shipped default: ink=%s plate=%s midcentury=%s"
		% [MapStyle.ink, MapStyle.plate, MapStyle.is_midcentury()])
	print("[LAYER] %-11s%s" % ["AT BOOT", _layers()])
	for mode in ["classic", "ink", "plate", "midcentury"]:
		MapStyle.set_midcentury(false)
		MapStyle.set_plate(false)
		MapStyle.set_ink(mode != "classic")
		if mode == "plate":
			MapStyle.set_plate(true)
		if mode == "midcentury":
			MapStyle.set_midcentury(true)
		for _i in 30:
			await get_tree().process_frame
		print("[LAYER] %-11s%s" % [mode, _layers()])
	print("[LAYER] done")
	get_tree().quit(0)
