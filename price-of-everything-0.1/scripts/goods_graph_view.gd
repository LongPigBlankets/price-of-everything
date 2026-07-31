extends Control
## Goods Graph — full-screen goods-web view (G to toggle).
##
## The production web of the whole economy: every good as a card in tier columns
## (raw sources left -> finished goods right), connected by the input->output flows
## of each good's BASE recipe — the simplest recipe available at game start (see
## scripts/goods_flow_graph.gd). Clicking a good traces its supply chain. Phase 2
## adds the zoom/focus mode with alternate-recipe swapping.
##
## Same lifecycle as the empire view (scripts/empire_view.gd): a full-rect Control
## created in code by world_map, driven entirely by `visible` so any opener/closer
## (G, the top-bar module, the Resources-panel button, PanelStack Esc) runs the same
## enter/leave side-effects. Presentation only — never mutates the sim (CLAUDE.md #5),
## no per-frame economic work (#2).

const _ACCENT := Color(0.995234, 0.930806, 0.763265, 1.0)   # DS.PALETTE["ACCENT"] gold
const _NAVY := Color(0.015686, 0.058824, 0.105882, 1.0)     # DS.PALETTE["BG_PANEL"]

const GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const GraphWorldScript := preload("res://scripts/goods_graph_world.gd")

var _map_camera: Node = null                   # the map Camera2D (group "camera"); gated while open
var _hidden_layers: Array[CanvasItem] = []     # world layers hidden on enter, restored on leave
var _graph_world: Control
var _legacy_goods_graph := false               # session-only; current presentation is default


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks so they don't fall through to the map
	_build_ui()
	_map_camera = get_tree().get_first_node_in_group("camera")
	visibility_changed.connect(_on_visibility_changed)


## Toggle open/closed. Called from world_map on the `toggle_goods_graph` (G) action,
## the top-bar Goods Graph module and the Resources panel's Goods Graph button.
func toggle() -> void:
	visible = not visible


## Debug cheat: switch the full Goods Graph presentation between current and legacy.
## The normal default remains the current swimlane/focus presentation.
func toggle_legacy_goods_graph() -> bool:
	_legacy_goods_graph = not _legacy_goods_graph
	_rebuild_graph()
	return _legacy_goods_graph


func _build_ui() -> void:
	# Opaque navy base FIRST: it is what actually blanks the screen (the world-hide
	# only covers map layers — HUD siblings below this view are hidden by this fill,
	# exactly the role the hex bg's own fill plays in the empire view).
	var base := ColorRect.new()
	base.name = "NavyBase"
	base.color = _NAVY
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)

	_graph_world = GraphWorldScript.new()
	_graph_world.name = "GraphWorld"
	_graph_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph_world.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_graph_world)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "GOODS GRAPH  ·  base recipes at game start · dashed = research-locked  ·  click a good: trace its chain, see alternate recipes, open its encyclopedia entry  ·  drag to pan · scroll to zoom · G to return"
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


## Hand the graph world the shared layout. GoodsFlowGraph.build() is a pure function of
## the Catalog (research unlocks do NOT change it — the "gated" flag is the static
## tech_unlock_req column), so it is computed once and cached: world_map warms that
## cache under the loading screen, and every open — this one included — returns the
## cached layout instantly instead of re-running the ~120 ms Sugiyama pass.
func _rebuild_graph() -> void:
	if _graph_world == null:
		return
	_graph_world.set_graph(GoodsFlowGraph.build(false, _legacy_goods_graph))


func _leave() -> void:
	_show_world()
	_set_camera_blocked(false)
	PanelStack.remove(self)


## Hide every world render layer so the navy view fully replaces the map (identical
## to empire_view.gd: only previously-visible layers are recorded, the Camera2D is
## skipped, and the UILayer is a CanvasLayer so the HUD stays visible).
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
