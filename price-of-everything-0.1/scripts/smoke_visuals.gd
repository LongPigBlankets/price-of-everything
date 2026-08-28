extends Node2D
## Chimney smoke: one puff every PERIOD seconds from every stack on the map, drifting
## north-east and fading out as it goes.
##
## WHY THIS IS ITS OWN NODE. `BuildingVisuals` repaints only when the view SETTLES — that is
## deliberate and load-bearing, because repainting several hundred buildings per frame is
## what the far-LOD batching exists to avoid. Smoke has to move every frame. Drawing it on
## the building canvas would force that canvas to repaint every frame too, dragging every
## building, mass, tank and service lane along with it. So the animated part lives here, on
## a canvas that holds nothing but smoke, and the static part (the chimney disc itself) stays
## with the building where it costs nothing.
##
## Sits ABOVE the road layers in `main.tscn`: smoke is in the air, and smoke that slid under
## a road would read as painted on the ground.

const CanvasBatch := preload("res://scripts/canvas_batch.gd")

const NE := Vector2(0.70710678, -0.70710678)   # +x east, -y north (y is down in 2D)

## One puff every 2 s, each puff living exactly as long (owner spec). Life == period means
## precisely one puff is alive per stack at any moment: the next is born as the last dies,
## which is what keeps this cheap. The alpha envelope below hides that seam.
const PERIOD := 2.0
## How far a puff travels over its life, world units.
const DRIFT := 100.0

## Two plumes (owner, 2026-08-27). GREY where the recipe burns something the carbon levy
## bites; near-white STEAM where it does not. The classification comes from BuildingVisuals,
## which reads the same `co2_tax_multiplier` production levies on — so the map and the ledger
## cannot disagree about which chimneys are dirty.
##
## The grey is deliberately a touch warm, so it sits with the map's sepia ink instead of
## reading as a blue-grey hole in the page. The steam is cooled very slightly the other way:
## pure white would look like a gap in the paper rather than vapour.
const SMOKE := Color(0.44, 0.435, 0.42)
const STEAM := Color(0.93, 0.945, 0.95)
## Steam is thinner than smoke — it is water, and at the grey's opacity a white plume reads
## as a solid cloud sitting on the map rather than as something you can see through.
## FULLY OPAQUE at birth, gone by the end (owner, 2026-08-27). Because a puff lives exactly
## as long as the gap between puffs, the new one appears at full strength the instant the old
## one reaches zero -- which reads as a fresh burst out of the stack rather than a seam.
const PEAK_ALPHA := 1.0
## Steam is left at full strength too, per the same instruction. Drop this if white vapour
## ends up reading heavier than the grey.
const STEAM_ALPHA_SCALE := 1.0

## THE PUFF SILHOUETTE, traced from the owner's own drawing (`puff smoke.PNG`,
## `tools/trace_puff_smoke.py`). The drawing carries two thin stem lines below the cloud that
## are not part of the shape; a morphological OPENING removes anything narrower than its
## kernel, which takes the stems and leaves the body untouched. What is left is sampled by
## ray-casting from the centroid — the right representation for a puff, which is star-convex
## about its middle — and normalised so the longest reach is 1.0.
##
## This REPLACED a cluster of eight overlapping circles. It is both a truer shape and cheaper:
## one triangulated polygon per puff instead of eight discs, and because they are triangles
## every puff on screen batches into a SINGLE draw call.
## `static var`, not `const`: GDScript will not accept a PackedVector2Array of Vector2
## constructors as a constant expression. Never mutated — treat it as one.
static var PUFF_SHAPE := PackedVector2Array([
	Vector2(0.8654, 0.0000),
	Vector2(0.9188, 0.1455),
	Vector2(0.9094, 0.2955),
	Vector2(0.8173, 0.4164),
	Vector2(0.6336, 0.4603),
	Vector2(0.5721, 0.5721),
	Vector2(0.4908, 0.6756),
	Vector2(0.3752, 0.7363),
	Vector2(0.2393, 0.7366),
	Vector2(0.1029, 0.6496),
	Vector2(0.0000, 0.7788),
	Vector2(-0.1360, 0.8590),
	Vector2(-0.2848, 0.8765),
	Vector2(-0.4282, 0.8404),
	Vector2(-0.5417, 0.7456),
	Vector2(-0.6088, 0.6088),
	Vector2(-0.6266, 0.4552),
	Vector2(-0.8019, 0.4086),
	Vector2(-0.9382, 0.3048),
	Vector2(-1.0000, 0.1584),
	Vector2(-0.9908, 0.0000),
	Vector2(-0.9017, -0.1428),
	Vector2(-0.7366, -0.2393),
	Vector2(-0.7209, -0.3673),
	Vector2(-0.7036, -0.5112),
	Vector2(-0.6180, -0.6180),
	Vector2(-0.4934, -0.6791),
	Vector2(-0.3320, -0.6515),
	Vector2(-0.2380, -0.7325),
	Vector2(-0.1306, -0.8248),
	Vector2(-0.0000, -0.8783),
	Vector2(0.1388, -0.8761),
	Vector2(0.2701, -0.8312),
	Vector2(0.3732, -0.7325),
	Vector2(0.4680, -0.6441),
	Vector2(0.6272, -0.6272),
	Vector2(0.7631, -0.5544),
	Vector2(0.8597, -0.4380),
	Vector2(0.9176, -0.2982),
	Vector2(0.9188, -0.1455),
])


## A puff leaves the stack a little wider than the flue and swells as it cools, both as
## multiples of the stack radius. The end figure is deliberately large: the puff travels
## DRIFT (100 u) over its life, roughly two building-widths, and a cloud that stayed near
## the size of its chimney would be a speck lost against that journey. At these numbers a
## furnace (r 3.2) ends about 29 u across and a power plant (r 4.6) about 41 — a plume that
## reads as weather over the building rather than a dot beside it.
## Raised 25% twice (owner, 2026-08-27): 1.4 / 9.0 -> 1.75 / 11.25 -> these.
const START_SCALE := 2.19
const END_SCALE := 14.06
## Below this many pixels across, a puff is a smudge nobody can read and every one of its
## six discs still costs a draw call — so the whole layer stands down when zoomed out.
## A puff rolls a QUARTER TURN over its life (owner, 2026-08-27), left or right depending on
## the stack's own seed -- so neighbouring chimneys do not all wind the same way.
const SPIN := PI * 0.5
const MIN_PUFF_PX := 3.0
## Keep drawing a little beyond the screen edge, so a puff drifting in from off-screen does
## not pop into existence at the border.
const CULL_MARGIN := 160.0

## The silhouette triangulated once, in unit space. Scaled and shifted per puff at draw time.
static var _puff_tris := PackedVector2Array()

var _visuals: Node = null
var _stacks: Array = []
var _known_version := -1
var _clock := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	# Wall-clock independent of the sim: smoke keeps drifting while the game is paused
	# between turns, which is most of the time a player spends looking at the map.
	_clock += delta
	if _clock > 86400.0:
		_clock = 0.0   # a day's worth; wraps on a PERIOD boundary is not required, see _phase
	if _refresh_stacks() or not _stacks.is_empty():
		queue_redraw()


## Re-ask BuildingVisuals for the chimney list, but only when the footprint version has
## actually moved — a build, a demolition or a load. Returns true if the list changed.
func _refresh_stacks() -> bool:
	if _visuals == null or not is_instance_valid(_visuals):
		_visuals = get_tree().get_first_node_in_group("building_footprints")
		if _visuals == null:
			return false
		_known_version = -1
	var version := int(_visuals.get("footprint_version"))
	if version == _known_version:
		return false
	_known_version = version
	_stacks = _visuals.call("smoke_stacks") if _visuals.has_method("smoke_stacks") else []
	return true


func _draw() -> void:
	if _stacks.is_empty():
		return
	var ppu := _pixels_per_unit()
	if ppu <= 0.0:
		return
	if _puff_tris.is_empty():
		_puff_tris = CanvasBatch.polygon_soup(PUFF_SHAPE)
		if _puff_tris.is_empty():
			return   # the silhouette would not triangulate; draw nothing rather than a mess
	var view := _visible_world_rect()
	# Every puff on screen goes into one triangle array, so the whole layer is ONE command
	# however many chimneys are in view.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for stack_value in _stacks:
		var stack: Dictionary = stack_value
		var base_r: float = stack["r"]
		# Per stack, NOT once for the layer: stack radii differ by more than 2x (a power
		# plant's 4.6 against an EAF's 2.1), so bailing out of the whole loop on the first
		# small chimney would silently stop a large plume nearby from drawing at all.
		if base_r * END_SCALE * 2.0 * ppu < MIN_PUFF_PX:
			continue
		var at: Vector2 = stack["pos"]
		# Cull against the whole path the puff can travel, not just its origin.
		if not view.has_point(at) and not view.has_point(at + NE * DRIFT):
			continue
		var seed_val := float(stack["seed"])
		_append_puff(pts, cols, at, base_r, _phase(seed_val),
			bool(stack.get("carbon", true)), 1.0 if seed_val < 0.5 else -1.0)
	CanvasBatch.flush(self, pts, cols)


## Age of this stack's current puff, 0 at emission and 1 at the end of its life. The seeded
## offset is what stops every chimney on the map breathing in time with every other.
func _phase(seed_val: float) -> float:
	return fposmod(_clock + seed_val * PERIOD, PERIOD) / PERIOD


func _append_puff(pts: PackedVector2Array, cols: PackedColorArray, origin: Vector2,
		base_r: float, p: float, carbon: bool, spin_dir: float) -> void:
	# Drift eases OUT: a puff leaves the stack briskly and slows as it spreads and cools.
	var travelled := 1.0 - pow(1.0 - p, 1.7)
	var centre := origin + NE * DRIFT * travelled
	# Growth eases IN: smoke holds together as it leaves the flue and spreads once it is
	# clear of it, rather than ballooning off the chimney top.
	var radius := base_r * lerpf(START_SCALE, END_SCALE, pow(p, 0.75))
	# Alpha rises fast then falls away to nothing. The quick rise is what hides the seam
	# where one puff dies and the next is born on the same frame; the gentle exponent keeps
	# the cloud readable through mid-life instead of washing out as soon as it spreads.
	# No ramp-in any more: full strength at birth, fading to nothing by the end.
	var alpha := PEAK_ALPHA * pow(1.0 - p, 1.15)
	if not carbon:
		alpha *= STEAM_ALPHA_SCALE
	if alpha <= 0.004:
		return
	var tint := SMOKE if carbon else STEAM
	# The silhouette turns slowly as it drifts, so consecutive puffs from one chimney are not
	# rubber stamps of each other.
	var spin := p * SPIN * spin_dir
	var col := Color(tint.r, tint.g, tint.b, alpha)
	var base := pts.size()
	pts.resize(base + _puff_tris.size())
	cols.resize(base + _puff_tris.size())
	for i in _puff_tris.size():
		pts[base + i] = centre + _puff_tris[i].rotated(spin) * radius
		cols[base + i] = col


func _pixels_per_unit() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	return vp.get_canvas_transform().get_scale().x


func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)
