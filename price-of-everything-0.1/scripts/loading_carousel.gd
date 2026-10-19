extends Control
## Offline capsule renders: only current/next still pairs and cropped smoke atlases stay resident.

const DIRECTORY := "res://assets/loading/carousel/"
const BUILDINGS := ["industrial_factory", "furnace", "power_plant", "petro_refinery", "farm", "offshore_wind_farm"]
const SECONDS_PER_TILE := 5.0
const NIGHT_FADE_START := 0.5
const NIGHT_FADE_SECONDS := 3.0
const SLIDE_START := 4.3
const BACKGROUND := Color("#040f1b")
const BLEND_SHADER := """shader_type canvas_item;
uniform sampler2D night_texture : source_color, filter_linear;
uniform float night_mix = 0.0;
uniform sampler2D smoke_day_atlas : source_color, filter_linear, repeat_disable;
uniform sampler2D smoke_night_atlas : source_color, filter_linear, repeat_disable;
uniform bool smoke_enabled = false;
uniform vec4 smoke_rect = vec4(0.0);
uniform float smoke_frame = 0.0;
varying vec4 tint;
vec4 alpha_mix(vec4 a, vec4 b, float t) {
    float alpha = mix(a.a, b.a, t);
    vec3 rgb = mix(a.rgb * a.a, b.rgb * b.a, t);
    return vec4(rgb / max(alpha, 0.00001), alpha);
}
vec2 frame_uv(vec2 uv, float frame) {
    vec2 cell = vec2(mod(frame, 4.0), floor(frame / 4.0));
    return (cell + clamp(uv, vec2(0.5 / 256.0), vec2(255.5 / 256.0))) / vec2(4.0, 3.0);
}
vec4 animated_smoke(sampler2D atlas, vec2 uv) {
    float frame = floor(smoke_frame);
    return alpha_mix(texture(atlas, frame_uv(uv, frame)),
        texture(atlas, frame_uv(uv, mod(frame + 1.0, 12.0))), fract(smoke_frame));
}
void vertex() { tint = COLOR; }
void fragment() {
    vec4 base = alpha_mix(texture(TEXTURE, UV), texture(night_texture, UV), night_mix);
    vec2 local_uv = (UV - smoke_rect.xy) / max(smoke_rect.zw, vec2(0.00001));
    if (smoke_enabled && all(greaterThanEqual(local_uv, vec2(0.0))) && all(lessThanEqual(local_uv, vec2(1.0)))) {
        vec4 smoke = alpha_mix(animated_smoke(smoke_day_atlas, local_uv),
            animated_smoke(smoke_night_atlas, local_uv), night_mix);
        float alpha = smoke.a + base.a * (1.0 - smoke.a);
        base = vec4((smoke.rgb * smoke.a + base.rgb * base.a * (1.0 - smoke.a)) / max(alpha, 0.00001), alpha);
    }
    COLOR = base * tint;
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
var _smoke_layouts: Dictionary = {}
var _animation_seconds := 0.0


static func night_mix_at(seconds: float) -> float:
	return smoothstep(NIGHT_FADE_START, NIGHT_FADE_START + NIGHT_FADE_SECONDS, seconds)


static func slide_at(seconds: float) -> float:
	return smoothstep(SLIDE_START, SECONDS_PER_TILE, seconds)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var layouts: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "smoke-layouts.json"))
	if layouts is Dictionary:
		_smoke_layouts = layouts
	else:
		push_error("Loading smoke layouts are missing or invalid")
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


func _assign_pair(tile: TextureRect, day: Texture2D, night: Texture2D,
		smoke_day: Texture2D = null, smoke_night: Texture2D = null, index: int = -1) -> void:
	tile.texture = day
	var material := tile.material as ShaderMaterial
	material.set_shader_parameter("night_texture", night)
	material.set_shader_parameter("smoke_day_atlas", smoke_day)
	material.set_shader_parameter("smoke_night_atlas", smoke_night)
	var enabled := smoke_day != null and smoke_night != null and index >= 0
	material.set_shader_parameter("smoke_enabled", enabled)
	tile.set_meta("has_smoke", enabled)
	if enabled:
		var rect: Array = _smoke_layouts[BUILDINGS[index]].rect
		material.set_shader_parameter("smoke_rect", Vector4(rect[0],rect[1],rect[2],rect[3]))


func _set_pair(tile: TextureRect, index: int) -> void:
	var smoke_day: Texture2D
	var smoke_night: Texture2D
	if _smoke_layouts.has(BUILDINGS[index]):
		smoke_day = load(_path(index, "smoke-day")) as Texture2D
		smoke_night = load(_path(index, "smoke-night")) as Texture2D
	_assign_pair(tile, load(_path(index, "day")) as Texture2D, load(_path(index, "night")) as Texture2D,
		smoke_day, smoke_night, index)


func _request_next() -> void:
	_next_ready = false
	_failed = false
	var index := (current_index + 1) % BUILDINGS.size()
	var looks := ["day", "night"]
	if _smoke_layouts.has(BUILDINGS[index]):
		looks.append_array(["smoke-day", "smoke-night"])
	for look in looks:
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
	var index := (current_index + 1) % BUILDINGS.size()
	var has_smoke := _smoke_layouts.has(BUILDINGS[index])
	if not _failed and textures.size() == (4 if has_smoke else 2):
		_assign_pair(_next, textures[0], textures[1], textures[2] if has_smoke else null,
			textures[3] if has_smoke else null, index)
		_next_ready = true


func _process(delta: float) -> void:
	_poll_next()
	phase += delta
	_animation_seconds += delta
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
	_animate_smoke()


func _animate_smoke() -> void:
	# The GPU interpolates two baked frames. No live particles, puff nodes or image uploads.
	for tile in [_current, _next]:
		if tile != null and tile.visible and bool(tile.get_meta("has_smoke", false)):
			(tile.material as ShaderMaterial).set_shader_parameter("smoke_frame", fposmod(_animation_seconds * 8.0, 12.0))


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
	_animation_seconds = seconds
	_set_pair(_current, current_index)
	_set_pair(_next, (current_index+1) % BUILDINGS.size())
	_next_ready = true
	_layout_tiles()
	_animate_smoke()


func _drain_pending() -> void:
	# A request must be consumed even if the player starts during its short prefetch.
	for path in _pending:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()


func _exit_tree() -> void:
	_drain_pending()
