extends Node2D
## Map-wide parchment grain (docs/building-visuals-ink-spec.md §2.4): ONE
## world-anchored seamless noise texture multiplied over the whole plate —
## terrain, roads, buildings — so fills sit *in* the paper instead of on it.
## Lives in the world (under the UI CanvasLayer), so panels/labels stay clean.
## The texture is generated at runtime (no assets); it never touches sim state.

const PARCHMENT_Z := 90            # above hills/roads/buildings/ports, below UI layers
const NOISE_SEED := 7              # fixed — purely visual, stable between runs
const GRAIN_DARKEST := Color(0.86, 0.81, 0.72)   # multiply floor: ~15% warm darkening (spec: 12-18%)
const GRAIN_LIGHTEST := Color(1.0, 0.99, 0.96)

var _tex: NoiseTexture2D = null
var _rect := Rect2()

func setup(world_rect: Rect2) -> void:
	_rect = world_rect
	z_index = PARCHMENT_Z
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	_tex = NoiseTexture2D.new()
	_tex.width = 256
	_tex.height = 256
	_tex.seamless = true
	_tex.noise = noise
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([GRAIN_DARKEST, GRAIN_LIGHTEST])
	_tex.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat
	# NoiseTexture2D fills asynchronously — redraw once the pixels exist.
	_tex.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if _tex != null and _rect.size.x > 0.0:
		draw_texture_rect(_tex, _rect, true)
