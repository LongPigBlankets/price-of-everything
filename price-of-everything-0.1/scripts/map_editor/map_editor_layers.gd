extends RefCounted
## Which of the game's map layers the editor shows.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## THE DEFAULT IS A BARE MAP: relief, sea and land, rivers, and the paper. Everything the
## game draws ON that ground — roads, buildings, settlement fabric, ports, woodland — is
## hidden, because it is exactly what the authored document replaces. Authoring over the
## procedural map would mean drawing on top of the thing being superseded and reading the
## result through it.
##
## Every layer stays one click away: tracing an existing settlement is a real workflow (the
## P2 import command automates it), and the relief alone is not always enough to judge where
## a street belongs.
##
## Layers are found BY NAME under the instantiated world, and a missing one is skipped
## rather than fatal — a scene rename should cost a toggle, not the editor.

## `key: {node: String, label: String, on: bool}`. `node` is the node name directly under the
## world root, or "" for the entries resolved specially in [method _resolve].
const LAYERS := [
	{"key": "relief", "node": "HillVisuals", "label": "Relief · sea & land", "on": true},
	{"key": "terrain", "node": "TerrainLayer", "label": "Terrain tiles", "on": true},
	{"key": "rivers", "node": "RiverVisuals", "label": "Rivers & lakes", "on": true},
	{"key": "paper", "node": "", "label": "Paper grain", "on": true},
	{"key": "forests", "node": "ForestVisuals", "label": "Woodland (procedural)", "on": false},
	{"key": "roads", "node": "RoadNetworkVisuals", "label": "Roads (procedural)", "on": false},
	{"key": "buildings", "node": "BuildingVisuals", "label": "Buildings", "on": false},
	{"key": "fabric", "node": "UrbanFabricVisuals", "label": "Settlement fabric", "on": false},
	{"key": "ports", "node": "", "label": "Ports", "on": false},
	{"key": "authored", "node": "AuthoredRoadVisuals", "label": "Authored roads (saved)", "on": false},
	# The editor previews the WORKING document itself; this layer draws the SAVED one, so
	# leaving it on shows both at once — which reads as an opened map heaped on the old one.
	{"key": "authored_fabric", "node": "AuthoredFabricVisuals", "label": "Authored fabric (saved)", "on": false},
]

var _world: Node = null
var _state: Dictionary = {}
## node instance id -> whether it was processing when the editor took over. A hidden layer
## also has its `_process` stopped, because some layers re-assert their own visibility every
## frame — `road_network_visuals` sets `visible = RoadNetwork.roads_visible` in `_process`,
## so a plain `visible = false` was reverted before the next draw and the procedural roads
## stayed on screen. Restoring the ORIGINAL state (rather than assuming true) keeps layers
## that were deliberately idle idle.
var _was_processing: Dictionary = {}


## Bind to a world and push the default visibility. Safe to call TWICE on the same world, and
## the editor does: once the moment the scene is added, so the layers it is going to hide
## anyway are not rendering through the whole build, and again once the build has finished,
## because the ports and the farm underlay are created DURING it and did not exist the first
## time. The recorded processing state is dropped on each bind — recording it mid-build would
## remember "was idle" for a layer that had simply not started yet, and restore that when the
## designer later switched the layer on.
func bind(world: Node) -> void:
	_world = world
	_was_processing.clear()
	for entry in LAYERS:
		_state[str(entry["key"])] = bool(entry["on"])
	apply()


func is_on(key: String) -> bool:
	return bool(_state.get(key, false))


func toggle(key: String) -> bool:
	_state[key] = not is_on(key)
	apply()
	return is_on(key)


## Push the whole state onto the scene. Cheap, and idempotent, so callers never have to
## track which layer changed.
func apply() -> void:
	if _world == null:
		return
	for entry in LAYERS:
		var key := str(entry["key"])
		var on := is_on(key)
		for node in _resolve(key, str(entry["node"])):
			var id: int = node.get_instance_id()
			if not _was_processing.has(id):
				_was_processing[id] = node.is_processing()
			if node is CanvasItem:
				(node as CanvasItem).visible = on
			elif node is CanvasLayer:
				(node as CanvasLayer).visible = on
			node.set_process(bool(_was_processing[id]) if on else false)


## Nodes for a layer key. Most are a direct child of the world root; the two exceptions are
## added at RUNTIME as children of the terrain layer (ports, the paper multiply) or spliced
## in beside the forest canopy (the farm underlay), so they cannot be named in the table.
func _resolve(key: String, node_name: String) -> Array:
	var out: Array = []
	if node_name != "":
		var direct := _world.get_node_or_null(NodePath(node_name))
		if direct != null:
			out.append(direct)
		# The farm fields ride with the buildings: they are gameplay content drawn on a
		# separate underlay so a field can run under a wood.
		if key == "buildings":
			var underlay := _find_by_script(_world, "farm_underlay.gd")
			if underlay != null:
				out.append(underlay)
		return out
	match key:
		"paper":
			var parchment := _find_by_script(_world, "parchment_overlay.gd")
			if parchment != null:
				out.append(parchment)
		"ports":
			var ports := _find_by_script(_world, "port_visuals.gd")
			if ports != null:
				out.append(ports)
	return out


## Runtime-added layers have no fixed node name, so they are identified by their script —
## stabler than a name a future refactor may change.
func _find_by_script(node: Node, script_file: String) -> Node:
	var script: Variant = node.get_script()
	if script != null and str(script.resource_path).ends_with(script_file):
		return node
	for child in node.get_children():
		var found := _find_by_script(child, script_file)
		if found != null:
			return found
	return null
