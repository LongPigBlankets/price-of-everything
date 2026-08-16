extends Node
## Headless Phase-B gate probe: no screenshots, only final renderer diagnostics.

func _ready() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 180:
		await get_tree().process_frame
	MapStyle.set_midcentury(true)
	for _i in 30:
		await get_tree().process_frame
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var metrics := fabric.metrics()
	var record := {
		"capital": metrics.get("settlement_plan_capital", {}),
		"silkstown": metrics.get("settlement_plan_silkstown", {}),
		"settlements": metrics.get("settlements", {}),
	}
	var file := FileAccess.open("/tmp/poe_relief_gate_probe.json",
		FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	print("[RELIEF GATE] wrote /tmp/poe_relief_gate_probe.json")
	MapStyle.set_midcentury(false)
	get_tree().quit(0)
