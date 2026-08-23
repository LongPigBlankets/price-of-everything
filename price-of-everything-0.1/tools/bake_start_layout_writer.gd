extends Node
## The half of tools/bake_start_layout.gd that has to outlive the scene change: it is parented
## to the tree root, waits for the map's build_complete, and writes the layout the placement
## passes just produced. See bake_start_layout.gd for the workflow.

const StartLayoutBaked := preload("res://scripts/start_layout_baked.gd")

var _t0 := 0
var _done := false


func _ready() -> void:
	_t0 = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if _done:
		return
	var cur := get_tree().current_scene
	if cur == null or cur.get("build_complete") == null or not bool(cur.get("build_complete")):
		return
	_done = true
	_write_bake(cur)


func _write_bake(main: Node) -> void:
	var bv: Node = main.get("building_visuals")
	if bv == null or not bv.has_method("export_layout_state"):
		push_error("bake_start_layout: no BuildingVisuals to export from.")
		get_tree().quit(1)
		return
	var layout: Dictionary = bv.export_layout_state()
	# The harbour plans belong to the same "this is the start world" answer, and cost 3.3 s of
	# coastline search to reproduce, so they ride along in the same file.
	var terrain: Node = main.get("terrain_layer")
	var ports: Node = terrain.get_node_or_null("PortVisuals") if terrain != null else null
	if ports != null and ports.has_method("export_plans"):
		layout["port_plans"] = ports.export_plans()
	var placements: Array = layout.get("_placements", [])
	var subcomponents: Array = layout.get("_subcomponents", [])
	var owned: Dictionary = layout.get("owned", {})
	if placements.is_empty():
		push_error("bake_start_layout: the build produced no placements — refusing to write an empty bake.")
		get_tree().quit(1)
		return
	if not StartLayoutBaked.save(layout):
		get_tree().quit(1)
		return
	var handle := FileAccess.open(StartLayoutBaked.BAKE_PATH, FileAccess.READ)
	var size := handle.get_length() if handle != null else 0
	print("bake_start_layout: %d placements, %d subcomponents, %d owned instances, %d harbour plans" % [
		placements.size(), subcomponents.size(), owned.size(),
		(layout.get("port_plans", {}) as Dictionary).size()])
	print("bake_start_layout: %.1f KB -> %s (%.1f s)" % [
		float(size) / 1024.0, StartLayoutBaked.BAKE_PATH,
		float(Time.get_ticks_msec() - _t0) / 1000.0])
	print("bake_start_layout: content_hash %s" % StartLayoutBaked.content_hash().left(12))
	get_tree().quit(0)
