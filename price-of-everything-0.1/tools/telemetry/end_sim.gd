extends Node
## Verifies the end-of-run reasons and the menu quit path: arms a run, emits
## VictoryState.victory_achieved — expect an immediate spool (reason "victory",
## run_complete true) + upload while the app is alive — then quits through
## request_app_quit() (the main-menu Quit wire). Run:
##   TELEMETRY_DEBUG=1 <godot> --headless --path . res://tools/telemetry/end_sim.tscn
## The engine quitting by itself is the pass condition; the bail-out is failure.

func _ready() -> void:
	await get_tree().process_frame
	TelemetryState._on_run_started()
	await get_tree().create_timer(0.2).timeout
	print("END SIM: emitting victory_achieved")
	VictoryState.victory_achieved.emit(5000, 42)
	for i in range(30):
		await get_tree().create_timer(0.5).timeout
		if TelemetryState._uploading.is_empty():
			break
	print("END SIM: quitting via request_app_quit()")
	TelemetryState.request_app_quit()
	await get_tree().create_timer(15.0).timeout
	print("END SIM FAIL: engine did not quit")
	get_tree().quit(1)
