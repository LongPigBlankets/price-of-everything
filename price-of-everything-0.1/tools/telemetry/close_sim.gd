extends Node
## Simulates a window close: arms a run, then delivers WM_CLOSE_REQUEST to
## TelemetryState — expect spool + close-time upload + engine quit. Run:
##   TELEMETRY_DEBUG=1 <godot> --headless --path . res://tools/telemetry/close_sim.tscn
## The engine quitting by itself (via TelemetryState) is the pass condition;
## the 15 s bail-out below only fires on failure.

func _ready() -> void:
	await get_tree().process_frame
	TelemetryState._on_run_started()
	await get_tree().create_timer(0.2).timeout
	print("CLOSE SIM: delivering WM_CLOSE_REQUEST")
	TelemetryState.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().create_timer(15.0).timeout
	print("CLOSE SIM FAIL: engine did not quit within 15 s")
	get_tree().quit(1)
