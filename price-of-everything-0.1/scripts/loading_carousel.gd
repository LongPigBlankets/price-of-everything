extends Control
## Offline capsule renders: only the current and next day/night pair stay resident.

const DIRECTORY := "res://assets/loading/carousel/"
const BUILDINGS := ["industrial_factory", "furnace", "power_plant", "petro_refinery", "farm", "offshore_wind_farm"]
const SECONDS_PER_TILE := 5.0
const SLIDE_START := 4.3
const BACKGROUND := Color("#040f1b")
const BLEND_SHADER := """shader_type canvas_item;
uniform sampler2D night_texture : source_color, filter_linear;
uniform float night_mix = 0.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    COLOR = mix(texture(TEXTURE, UV), texture(night_texture, UV), night_mix) * tint;
}
"""

var current_index := 0
var phase := 0.0
var _current: TextureRect
var _next: TextureRect
var _pending := PackedStringArray()
var _next_ready := false
var _failed := false
var _shader: Shader
var _last_visual := Vector4(-1, -1, -1, -1)
var _last_index := -1


static func night_mix_at(seconds: float) -> float:
	return smoothstep(1.35, 2.85, seconds)


static func slide_at(seconds: float) -> float:
	return smoothstep(SLIDE_START, SECONDS_PER_TILE, seconds)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_shader = Shader.new()
	_shader.code = BLEND_SHADER
	_current = _make_tile()
	_next = _make_tile()
	_set_pair(_current, 0)
	_request_next()
	resized.connect(_layout_tiles)
	_layout_tiles()


func _make_tile() -> TextureRect:
	var tile := TextureRect.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var blend := ShaderMaterial.new()
	blend.shader = _shader
	tile.material = blend
	add_child(tile)
	return tile


func _path(index: int, look: String) -> String:
	return DIRECTORY + BUILDINGS[index] + "-" + look + ".png"


func _assign_pair(tile: TextureRect, day: Texture2D, night: Texture2D) -> void:
	tile.texture = day
	(tile.material as ShaderMaterial).set_shader_parameter("night_texture", night)


func _set_pair(tile: TextureRect, index: int) -> void:
	_assign_pair(tile, load(_path(index, "day")) as Texture2D, load(_path(index, "night")) as Texture2D)


func _request_next() -> void:
	_next_ready = false
	_failed = false
	var index := (current_index + 1) % BUILDINGS.size()
	for look in ["day", "night"]:
		var path := _path(index, look)
		if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
			_pending.append(path)
		else:
			_failed = true


func _poll_next() -> void:
	if _pending.is_empty():
		return
	for path in _pending:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
	var textures: Array[Texture2D] = []
	for path in _pending:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			textures.append(ResourceLoader.load_threaded_get(path) as Texture2D)
		else:
			_failed = true
	_pending.clear()
	if not _failed and textures.size() == 2:
		_assign_pair(_next, textures[0], textures[1])
		_next_ready = true


func _process(delta: float) -> void:
	_poll_next()
	phase += delta
	# A slow asset read holds the still, rather than sliding toward an empty tile.
	if not _next_ready:
		phase = minf(phase, SLIDE_START)
	elif phase >= SECONDS_PER_TILE:
		phase = fmod(phase, SECONDS_PER_TILE)
		current_index = (current_index + 1) % BUILDINGS.size()
		var previous := _current
		_current = _next
		_next = previous
		_assign_pair(_next, null, null)  # release the previous pair before prefetching
		_request_next()
	_layout_tiles()


func _layout_tiles() -> void:
	if _current == null:
		return
	var slide := slide_at(phase) if _next_ready else 0.0
	var night := night_mix_at(phase)
	var visual := Vector4(size.x, size.y, night, slide)
	if visual == _last_visual and current_index == _last_index:
		return
	_last_visual = visual
	_last_index = current_index
	# About half as large again, bounded vertically so smoke and the Begin key stay clear.
	var side := minf(minf(size.x * 0.88, size.y * 0.78) * 1.5, size.y * 1.10)
	var centre := Vector2(size.x * 0.5, size.y * 0.49)
	var step := maxf(side * 1.14, size.x * 0.60)
	_current.size = Vector2.ONE * side
	_current.position = centre - _current.size * 0.5 - Vector2.RIGHT * step * slide
	(_current.material as ShaderMaterial).set_shader_parameter("night_mix", night)
	_next.size = _current.size
	_next.position = _current.position + Vector2.RIGHT * step
	_next.visible = _next_ready and slide > 0.0
	(_next.material as ShaderMaterial).set_shader_parameter("night_mix", 0.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


## Deterministic visual review; normal loading never calls this or waits for a full loop.
func seek(seconds: float) -> void:
	_drain_pending()
	current_index = int(maxf(seconds, 0.0) / SECONDS_PER_TILE) % BUILDINGS.size()
	phase = fposmod(seconds, SECONDS_PER_TILE)
	_set_pair(_current, current_index)
	_set_pair(_next, (current_index+1) % BUILDINGS.size())
	_next_ready = true
	_layout_tiles()


func _drain_pending() -> void:
	# A request must be consumed even if the player starts during its short prefetch.
	for path in _pending:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()


func _exit_tree() -> void:
	_drain_pending()
