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
var _noise: FastNoiseLite = null

func setup(world_rect: Rect2) -> void:
	_rect = world_rect
	z_index = PARCHMENT_Z
	_noise = FastNoiseLite.new()
	_noise.seed = NOISE_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tex = NoiseTexture2D.new()
	_tex.seamless = true
	_tex.noise = _noise
	_ramp = Gradient.new()
	_apply_ramp()
	_apply_scale()
	_tex.color_ramp = _ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat
	# NoiseTexture2D fills asynchronously — redraw once the pixels exist.
	_tex.changed.connect(queue_redraw)
	if not MapStyle.style_changed.is_connected(_on_style_changed):
		MapStyle.style_changed.connect(_on_style_changed)
	queue_redraw()

## Offsets first: a Gradient must never be left with more colors than offsets,
## and the plate ramp has four stops where classic and ink have two.
func _apply_ramp() -> void:
	_ramp.offsets = MapStyle.parchment_offsets()
	_ramp.colors = MapStyle.parchment_colors()

## Grain scale — how coarse the blotches are, and how far apart the tiling
## repeats (the texture is drawn 1 texel to 1 world unit).
func _apply_scale() -> void:
	_noise.frequency = MapStyle.parchment_noise_frequency()
	_noise.fractal_octaves = MapStyle.parchment_noise_octaves()
	var px := MapStyle.parchment_tile_px()
	_tex.width = px
	_tex.height = px

func _on_style_changed() -> void:
	# In-place Gradient edit fires its changed signal (NoiseTexture2D listens
	# and regenerates); the reassign is belt-and-braces for setter early-outs.
	_apply_ramp()
	_apply_scale()
	_tex.color_ramp = _ramp
	queue_redraw()

func _draw() -> void:
	if _tex != null and _rect.size.x > 0.0:
		draw_texture_rect(_tex, _rect, true)
