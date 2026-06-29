extends Node
## Profiles per-node _ready cost during main.tscn instantiation: hooks every node's `ready`
## signal with a timestamp; the gap before a node's ready ~= what it (and its just-built
## children) cost.  <godot> --path . res://tools/ready_profile.tscn --quit-after 2500
var _t0 := 0
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_hook(main)
	_t0 = Time.get_ticks_msec()
	add_child(main)
	for _i in range(60):
		await get_tree().process_frame
	get_tree().quit(0)
func _hook(n: Node) -> void:
	n.ready.connect(_log.bind(n))
	for c in n.get_children():
		_hook(c)
func _log(n: Node) -> void:
	print("READY %6d %s" % [Time.get_ticks_msec() - _t0, n.name])
