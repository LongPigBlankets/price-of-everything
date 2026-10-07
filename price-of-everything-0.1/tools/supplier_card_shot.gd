extends Node
## Captures the card asked before goods leave Local Suppliers, for an output going to a stockpile and to the
## market, in a Metal Magnate game.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/supplier_card_shot.tscn -- --no-telemetry
## Writes supplier_card_<destination>.png into $CARD_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const Confirmation := preload("res://scripts/logistics_confirmation.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("CARD_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await _settle(200)
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(20)
	var host: Node = main.find_child("HUDContent", true, false)
	for destination: String in ["stockpile", "market"]:
		Confirmation.request(host, "managed", func() -> bool: return true, Callable(), {"side": "output", "destination": destination})
		await _settle(6)
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(_out.path_join("supplier_card_%s.png" % destination))
		var card: Node = main.find_child("TransportSupplierConfirmation", true, false)
		(card.find_child("CancelSupplierChange", true, false) as Button).pressed.emit()
		await _settle(4)
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
