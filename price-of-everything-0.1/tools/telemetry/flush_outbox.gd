extends Node
## Drains the telemetry outbox: boots, lets TelemetryState's _ready retry run,
## and quits 0 once the outbox is empty (or 1 after 20 s). Run:
##   TELEMETRY_DEBUG=1 <godot> --headless --path . res://tools/telemetry/flush_outbox.tscn

const AppPaths := preload("res://scripts/app_paths.gd")


func _ready() -> void:
	for i in range(40):
		await get_tree().create_timer(0.5).timeout
		if _pending() == 0:
			print("TELEMETRY OUTBOX EMPTY")
			get_tree().quit(0)
			return
	print("TELEMETRY OUTBOX NOT EMPTY: %d file(s) left" % _pending())
	get_tree().quit(1)


func _pending() -> int:
	var n := 0
	for fname in DirAccess.get_files_at(AppPaths.telemetry_outbox_dir()):
		if fname.ends_with(".json"):
			n += 1
	return n
