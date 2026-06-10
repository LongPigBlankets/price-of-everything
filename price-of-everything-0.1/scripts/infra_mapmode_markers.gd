extends Node2D
## World-space markers for the Infrastructure mapmode: one bare building icon
## per tile that has the selected infrastructure, centred on the tile. Icons
## are 80x80 world px at zoom 1.0 (= 80 screen px). Zooming out grows them
## sub-proportionally (zoom^-GROWTH_EXPONENT) so they stay legible while always
## fitting inside the tile outline; zoomed in they keep the fixed world size.

const BASE_WORLD_SIZE := 80.0
const GROWTH_EXPONENT := 0.6     # 0 = fixed world size, 1 = fixed screen size
const MAX_TILE_FRACTION := 0.55  # hard cap so the icon never outgrows the hex

var texture: Texture2D = null
var tile_size := Vector2(540, 480)

var _sprites: Array[Sprite2D] = []
var _last_world_size := -1.0

func add_marker(world_pos: Vector2) -> void:
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = world_pos
	add_child(sprite)
	_sprites.append(sprite)
	_apply_size(sprite, _current_world_size())

func _process(_delta: float) -> void:
	# The camera lerps its zoom every frame, so resize here (cheap: one pow +
	# a scale write per sprite, skipped while the size is stable).
	var world_size := _current_world_size()
	if absf(world_size - _last_world_size) < 0.25:
		return
	_last_world_size = world_size
	for sprite in _sprites:
		_apply_size(sprite, world_size)

func _current_world_size() -> float:
	var world_size := BASE_WORLD_SIZE
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		var zoom := minf(camera.zoom.x, camera.zoom.y)
		if zoom > 0.0 and zoom < 1.0:
			world_size = BASE_WORLD_SIZE * pow(1.0 / zoom, GROWTH_EXPONENT)
	return minf(world_size, minf(tile_size.x, tile_size.y) * MAX_TILE_FRACTION)

func _apply_size(sprite: Sprite2D, world_size: float) -> void:
	var dim := maxf(1.0, float(maxi(texture.get_width(), texture.get_height())))
	sprite.scale = Vector2.ONE * (world_size / dim)
