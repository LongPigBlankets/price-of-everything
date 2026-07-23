extends Node2D
## Map-wide parchment grain (docs/building-visuals-ink-spec.md §2.4): ONE
## world-anchored seamless noise texture multiplied over the whole plate —
## terrain, roads, buildings — so fills sit *in* the paper instead of on it.
## Lives in the world (under the UI CanvasLayer), so panels/labels stay clean.
## The texture is generated at runtime (no assets); it never touches sim state.

const PARCHMENT_Z := 90            # above hills/roads/buildings/ports, below UI layers
const NOISE_SEED := 7              # fixed — purely visual, stable between runs
# Grain ramp colors live in MapStyle ('toggle ink' deepens the multiply floor).

var _tex: NoiseTexture2D = null
var _rect := Rect2()
var _ramp: Gradient = null

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
	_ramp = Gradient.new()
	_ramp.offsets = PackedFloat32Array([0.0, 1.0])
	_apply_ramp()
	_tex.color_ramp = _ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat
	# NoiseTexture2D fills asynchronously — redraw once the pixels exist.
	_tex.changed.connect(queue_redraw)
	if not MapStyle.style_changed.is_connected(_on_style_changed):
		MapStyle.style_changed.connect(_on_style_changed)
	queue_redraw()

func _apply_ramp() -> void:
	_ramp.colors = PackedColorArray([MapStyle.parchment_darkest(), MapStyle.parchment_lightest()])

func _on_style_changed() -> void:
	# In-place Gradient edit fires its changed signal (NoiseTexture2D listens
	# and regenerates); the reassign is belt-and-braces for setter early-outs.
	_apply_ramp()
	_tex.color_ramp = _ramp
	queue_redraw()

func _draw() -> void:
	if _tex != null and _rect.size.x > 0.0:
		draw_texture_rect(_tex, _rect, true)
