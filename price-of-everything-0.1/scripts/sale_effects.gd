extends CanvasLayer
## Floating "£" that rises from a port tile each time a market sale is finalised
## there. To keep it tied to the shipment animation, arrivals that land during turn
## resolution are queued and fired together once resolution (and the gliding shipment
## tags) finish; instant sales pop immediately.

const FONT_SIZE := 32
const RISE_PX := 200.0
const RISE_TIME := 1.0
const FADE_TIME := 0.5
const POUND_COLOUR := Color(0.99, 0.86, 0.30)  # warm gold

var terrain_layer: Node = null
var _resolving := false
var _pending: Array = []  # [port_tile_id]

func _ready() -> void:
	layer = 40  # above the world, below HUD panels
	MatchState.market_sale_arrived_at_port.connect(_on_sale_arrived)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)

func _on_resolution_started() -> void:
	_resolving = true
	_pending.clear()

func _on_resolution_completed() -> void:
	_resolving = false
	for tile_id in _pending:
		_spawn_rise(str(tile_id))
	_pending.clear()

func _on_sale_arrived(port_tile_id: String, _revenue: float) -> void:
	if port_tile_id == "":
		return
	if _resolving:
		_pending.append(port_tile_id)  # wait for the arrival animation to finish
	else:
		_spawn_rise(port_tile_id)

func _spawn_rise(port_tile_id: String) -> void:
	if terrain_layer == null or not terrain_layer.has_method("id_to_coord"):
		return
	var coord: Vector2i = terrain_layer.id_to_coord(port_tile_id)
	if coord == Vector2i(-1, -1):
		return
	var world: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	var screen: Vector2 = terrain_layer.get_viewport().get_canvas_transform() * world

	var label := Label.new()
	label.text = "£"
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", POUND_COLOUR)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.058, 0.105))
	label.add_theme_constant_override("outline_size", 6)
	label.position = screen - Vector2(FONT_SIZE * 0.3, FONT_SIZE * 0.5)
	label.pivot_offset = Vector2(FONT_SIZE * 0.3, FONT_SIZE * 0.5)
	add_child(label)

	# 2.5d feel: a quick pop-in scale, an eased rise, then a fade.
	var pop := create_tween()
	pop.tween_property(label, "scale", Vector2.ONE, 0.18).from(Vector2(0.55, 0.55)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - RISE_PX, RISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(label.queue_free)
