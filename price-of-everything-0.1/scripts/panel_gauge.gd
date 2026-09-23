extends Control
## Panel gauge built from the pre-rendered layers in res://assets/ui/gauge/ (rendered by
## tools/gauge_render). Stacking layers rather than baking frames lets the needle point
## anywhere and the green / amber / red zones take any size. The scale sweeps 300° clockwise
## from 7 o'clock, over the top, to 5 o'clock; the LED sits in the gap at the bottom.
##
## Layer order, bottom to top: base (bezel, blank dial, LED socket, drop shadow), the three
## zone bands trimmed by a shader, the tick scale, the LED glow (additive, tinted) and lens,
## the needle's shadow, the needle, and the glass glare (additive).
##
## Presentation only: it shows the values it is given and holds no game state.

enum LedMode { AUTO, GREEN, AMBER, RED, OFF }

const ZONES: Array[String] = ["green", "amber", "red"]
const LED_COLOURS := {
	"green": Color("#2fe46c"),
	"amber": Color("#ffb21f"),
	"red": Color("#ff3b2f"),
}
const LAYER_BASE := preload("res://assets/ui/gauge/gauge_base.png")
const LAYER_BANDS := {
	"green": preload("res://assets/ui/gauge/gauge_band_green.png"),
	"amber": preload("res://assets/ui/gauge/gauge_band_amber.png"),
	"red": preload("res://assets/ui/gauge/gauge_band_red.png"),
}
const LAYER_SCALE := preload("res://assets/ui/gauge/gauge_scale.png")
const LAYER_NEEDLE := preload("res://assets/ui/gauge/gauge_needle.png")
const LAYER_NEEDLE_SHADOW := preload("res://assets/ui/gauge/gauge_needle_shadow.png")
const LAYER_LED := {
	"green": preload("res://assets/ui/gauge/gauge_led_green.png"),
	"amber": preload("res://assets/ui/gauge/gauge_led_amber.png"),
	"red": preload("res://assets/ui/gauge/gauge_led_red.png"),
	"off": preload("res://assets/ui/gauge/gauge_led_off.png"),
}
const LAYER_LED_GLOW := preload("res://assets/ui/gauge/gauge_led_glow.png")
const LAYER_GLARE := preload("res://assets/ui/gauge/gauge_glare.png")

## Layer frame size in pixels, and how far the needle's shadow sits from the needle in that
## frame (the key light's slant at blade height), as printed by the exporter.
const LAYER_SIZE := 1024.0
const NEEDLE_SHADOW_OFFSET := Vector2(24.97, 24.97)
## The scale's sweep in degrees. The zone shader below hardcodes the same geometry: it starts
## at 240° (7 o'clock) and runs 300° clockwise.
const SCALE_SWEEP_DEG := 300.0
## LED blink rate when flashing, in blinks per second, and the share of each blink it is lit.
const FLASH_HZ := 1.5
const FLASH_ON := 0.56

## Trims a full-sweep zone band to [from_v, to_v] of the scale, where v runs 0..1 clockwise
## from 7 o'clock. Neighbouring zones share their boundary and each fades over one pixel,
## so no seam shows between them. Built in code so there is no shader asset to ship.
const ZONE_SHADER := """shader_type canvas_item;
uniform float from_v = 0.0;
uniform float to_v = 1.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float a = degrees(atan(-d.y, d.x));
	if (a < -90.0) { a += 360.0; }
	float v = (240.0 - a) / 300.0;
	float aa = fwidth(v);
	float inside = smoothstep(from_v - aa, from_v, v) * (1.0 - smoothstep(to_v, to_v + aa, v));
	if (to_v <= from_v) { inside = 0.0; }
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * inside);
}
"""

## Drawn width and height of the gauge, in pixels.
@export var gauge_size: float = 180.0:
	set(v):
		gauge_size = maxf(v, 16.0)
		custom_minimum_size = Vector2(gauge_size, gauge_size)
		_layout()
## Needle position on the scale, 0..1.
@export_range(0.0, 1.0) var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		if not animate_needle:
			_shown_value = value
		_refresh()
## Share of the scale that is green, from the start, in percent.
@export_range(0.0, 100.0) var green_percent: float = 37.5:
	set(v):
		green_percent = clampf(v, 0.0, 100.0)
		_refresh()
## Share of the scale that is amber, after the green, in percent. Red takes the rest.
@export_range(0.0, 100.0) var amber_percent: float = 29.2:
	set(v):
		amber_percent = clampf(v, 0.0, 100.0)
		_refresh()
@export var led_mode: LedMode = LedMode.AUTO:
	set(v):
		led_mode = v
		_refresh()
## Blink the LED. In AUTO the LED always blinks while the needle is in the red zone.
@export var flash: bool = false:
	set(v):
		flash = v
		_refresh()
## Ease the needle towards `value` with a slight overshoot, like a real movement.
@export var animate_needle: bool = true

var _shown_value := 0.0
var _needle_velocity := 0.0
var _time := 0.0
var _layers := {}          # name -> TextureRect
var _zone_materials := {}  # zone -> ShaderMaterial


# --- Pure rules (static so tests can check them without a scene) -------------------------

## Each zone's stretch of the scale as Vector2(from, to) in 0..1. Amber is clamped so the
## three always add up to the whole scale.
static func zone_bounds(green_pct: float, amber_pct: float) -> Dictionary:
	var g := clampf(green_pct, 0.0, 100.0) / 100.0
	var a := clampf(amber_pct, 0.0, 100.0 - g * 100.0) / 100.0
	return {"green": Vector2(0.0, g), "amber": Vector2(g, g + a), "red": Vector2(g + a, 1.0)}


## The zone the needle is in. A value on a boundary belongs to the lower zone; empty zones
## are skipped.
static func zone_at(v: float, green_pct: float, amber_pct: float) -> String:
	var bounds := zone_bounds(green_pct, amber_pct)
	for zone: String in ZONES:
		var b: Vector2 = bounds[zone]
		if b.y > b.x and clampf(v, 0.0, 1.0) <= b.y:
			return zone
	return "red"


## The LED colour to show: "green", "amber", "red" or "off".
static func led_colour(mode: LedMode, v: float, green_pct: float, amber_pct: float) -> String:
	match mode:
		LedMode.GREEN: return "green"
		LedMode.AMBER: return "amber"
		LedMode.RED: return "red"
		LedMode.OFF: return "off"
	return zone_at(v, green_pct, amber_pct)


static func led_flashes(mode: LedMode, flash_on: bool, v: float, green_pct: float, amber_pct: float) -> bool:
	if mode == LedMode.OFF:
		return false
	return flash_on or (mode == LedMode.AUTO and zone_at(v, green_pct, amber_pct) == "red")


## Needle rotation in radians, clockwise from 12 o'clock (the pose the needle layer is drawn in).
static func needle_rotation(v: float) -> float:
	return deg_to_rad(clampf(v, 0.0, 1.0) * SCALE_SWEEP_DEG - SCALE_SWEEP_DEG * 0.5)


# --- Scene ---------------------------------------------------------------------------------

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(gauge_size, gauge_size)
	var shader := Shader.new()
	shader.code = ZONE_SHADER
	_add_layer("base", LAYER_BASE)
	for zone: String in ZONES:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_zone_materials[zone] = mat
		_add_layer("band_" + zone, LAYER_BANDS[zone]).material = mat
	_add_layer("scale", LAYER_SCALE)
	_add_layer("led_glow", LAYER_LED_GLOW).material = _additive()
	_add_layer("led", LAYER_LED["off"])
	_add_layer("needle_shadow", LAYER_NEEDLE_SHADOW)
	_add_layer("needle", LAYER_NEEDLE)
	_add_layer("glare", LAYER_GLARE).material = _additive()
	_shown_value = value
	_layout()
	_refresh()


## Jump the needle straight to `value`, skipping the easing.
func snap_needle() -> void:
	_shown_value = value
	_needle_velocity = 0.0
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	if animate_needle and (not is_equal_approx(_shown_value, value) or absf(_needle_velocity) > 0.0005):
		var dt := minf(delta, 0.05)
		_needle_velocity += ((value - _shown_value) * 180.0 - _needle_velocity * 16.0) * dt
		_shown_value += _needle_velocity * dt
		if absf(value - _shown_value) < 0.0005 and absf(_needle_velocity) < 0.0005:
			_shown_value = value
			_needle_velocity = 0.0
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _add_layer(layer_name: String, texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = layer_name
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	_layers[layer_name] = rect
	return rect


func _additive() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func _layout() -> void:
	if _layers.is_empty():
		return
	# Square, centred in whatever rect a container gives us.
	var side := minf(size.x, size.y) if size.x > 0.0 and size.y > 0.0 else gauge_size
	var origin := (size - Vector2(side, side)) * 0.5 if size.x > 0.0 else Vector2.ZERO
	for rect: TextureRect in _layers.values():
		rect.position = origin
		rect.size = Vector2(side, side)
		rect.pivot_offset = Vector2(side, side) * 0.5
	# The shadow turns about the point under the pivot, offset by the light's slant.
	(_layers["needle_shadow"] as TextureRect).pivot_offset += NEEDLE_SHADOW_OFFSET * (side / LAYER_SIZE)


func _refresh() -> void:
	if _layers.is_empty():
		return
	var bounds := zone_bounds(green_percent, amber_percent)
	for zone: String in ZONES:
		var b: Vector2 = bounds[zone]
		(_zone_materials[zone] as ShaderMaterial).set_shader_parameter("from_v", b.x)
		(_zone_materials[zone] as ShaderMaterial).set_shader_parameter("to_v", b.y)
		(_layers["band_" + zone] as TextureRect).visible = b.y > b.x

	var angle := needle_rotation(_shown_value)
	(_layers["needle"] as TextureRect).rotation = angle
	(_layers["needle_shadow"] as TextureRect).rotation = angle

	# The LED follows the settled value, not the swinging needle, so it doesn't flicker
	# between zones while the needle overshoots.
	var colour := led_colour(led_mode, value, green_percent, amber_percent)
	var lit := colour != "off"
	if lit and led_flashes(led_mode, flash, value, green_percent, amber_percent):
		lit = fposmod(_time * FLASH_HZ, 1.0) < FLASH_ON
	(_layers["led"] as TextureRect).texture = LAYER_LED[colour if lit else "off"]
	var glow := _layers["led_glow"] as TextureRect
	glow.visible = lit
	if lit:
		glow.modulate = LED_COLOURS[colour]


## The LED colour currently drawn ("off" while a flash is in its dark phase).
func shown_led() -> String:
	var tex: Texture2D = (_layers["led"] as TextureRect).texture if not _layers.is_empty() else null
	for colour: String in LAYER_LED:
		if LAYER_LED[colour] == tex:
			return colour
	return ""
