extends Control
## Empire view — Milestone 1 (the shell).
##
## A full-screen navy "command screen" toggled with Tab that replaces the relief map.
## Later milestones add the building node-graph, supply lines, ports and the animated
## amber hex-field background (see docs/empire_view_plan.md); for now this is the navy
## backdrop plus all the toggle / lifecycle plumbing those milestones build on.
##
## The lifecycle is driven entirely by `visible`: flipping it (Tab via world_map) or
## having PanelStack.close_top() hide it (Esc) both run through `_on_visibility_changed`,
## so the enter/leave side-effects fire no matter who opened or closed the view.
##
## Architecture notes (CLAUDE.md): this is presentation only — it never mutates the sim
## (rule #5) and does no per-frame economic work (rule #2). It is built in code rather
## than added to main.tscn so the whole feature stays self-contained in one script.

# Navy backdrop colour — DS.PALETTE["BG_PANEL"] (#040F1B). Kept as a literal so the shell
# renders even before DS is queried; the hex-field shader replaces this in a later milestone.
const _NAVY := Color(0.015686, 0.058824, 0.105882, 1.0)
# DS.PALETTE["ACCENT"] gold, used for the placeholder label.
const _ACCENT := Color(0.995234, 0.930806, 0.763265, 1.0)

const EmpireGraphScript := preload("res://scripts/empire_graph.gd")
const EmpireLayout := preload("res://scripts/empire_layout.gd")
const GraphWorldScript := preload("res://scripts/empire_graph_world.gd")
const HexBgScript := preload("res://scripts/empire_hex_bg.gd")

var _map_camera: Node = null                   # the map Camera2D (group "camera"); gated while we own the screen
var _hidden_layers: Array[CanvasItem] = []     # world layers hidden on enter, restored on leave
var _graph_world: Control                      # the node-graph drawing layer (empire_graph_world.gd)
var _bg: Control                               # the animated hex-field background (empire_hex_bg.gd)


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks so they don't fall through to the map
	_build_ui()
	_map_camera = get_tree().get_first_node_in_group("camera")
	visibility_changed.connect(_on_visibility_changed)


## Toggle open/closed. Called from world_map on the `toggle_empire_view` (Tab) action.
func toggle() -> void:
	visible = not visible


func _build_ui() -> void:
	_bg = HexBgScript.new()
	_bg.name = "HexFieldBg"
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# The node-graph drawing layer (drawn above the backdrop, below the hint).
	# MOUSE_FILTER_STOP so it receives drag-pan / scroll-zoom input.
	_graph_world = GraphWorldScript.new()
	_graph_world.name = "GraphWorld"
	_graph_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph_world.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_graph_world)

	# Let the background's building-origin pulse (anim 1) ripple out of the live building positions.
	_bg.call("set_graph_world", _graph_world)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "EMPIRE VIEW  ·  drag to pan · scroll to zoom · Tab to return"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.theme_type_variation = &"Caption"
	hint.modulate = Color(_ACCENT.r, _ACCENT.g, _ACCENT.b, 0.6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -36.0
	add_child(hint)


func _on_visibility_changed() -> void:
	if visible:
		_enter()
	else:
		_leave()


func _enter() -> void:
	move_to_front()
	_hide_world()
	_set_camera_blocked(true)
	PanelStack.push(self)
	_rebuild_graph()


## Build the node/edge graph from the live sim and pack it. Cheap for ~50 buildings; rebuilt on
## each open (Milestone 2). Later milestones cache on the graph signature and rebuild on change.
func _rebuild_graph() -> void:
	if _graph_world == null:
		return
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var g: Dictionary = EmpireGraphScript.build(terrain)
	# Lay buildings out as supply-chain columns (input sources beside their consumers, crossings
	# minimized), then drop the ports into a fixed-order row beneath the block.
	EmpireLayout.solve(g["nodes"], g["edges"])
	EmpireLayout.place_ports(g["ports"], EmpireLayout.bbox_of(g["nodes"]))
	_graph_world.set_graph(g["nodes"], g["edges"], g["ports"], g["sell_edges"])


func _leave() -> void:
	_show_world()
	_set_camera_blocked(false)
	PanelStack.remove(self)


## Hide every world render layer (terrain, visuals, overlays) so the navy view fully
## replaces the map. Only layers that were visible are recorded, so we restore the exact
## prior state. The map Camera2D is skipped (hiding it would not stop it being current),
## and the UILayer is a CanvasLayer (not a CanvasItem) so the whole HUD stays visible.
func _hide_world() -> void:
	_hidden_layers.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for child in root.get_children():
		if child is Camera2D:
			continue
		if child is CanvasItem and (child as CanvasItem).visible:
			var layer := child as CanvasItem
			layer.visible = false
			_hidden_layers.append(layer)


func _show_world() -> void:
	for layer in _hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_layers.clear()


func _set_camera_blocked(blocked: bool) -> void:
	if _map_camera != null and is_instance_valid(_map_camera):
		_map_camera.set("input_blocked", blocked)
