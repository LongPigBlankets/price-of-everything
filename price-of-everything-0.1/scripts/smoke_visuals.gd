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
const PEAK_ALPHA := 0.50
const STEAM_ALPHA_SCALE := 0.82

## A puff is a CLUSTER of overlapping discs, not one circle — that is what makes it read as
## a cloud instead of a bubble. Six is enough for a lumpy silhouette and cheap enough to run
## on every chimney in view.
const LOBES := 8
## Lobe centres, as fractions of the puff radius. Hand-placed rather than random so the
## silhouette is a known good shape: a broad base with two smaller lobes riding above it.
## Eight lobes (owner, 2026-08-27), up from six: the extra two fill the diagonals, which is
## where a six-lobe cluster showed its ring.
const LOBE_OFFSETS: Array[Vector2] = [
	Vector2(0.00, 0.00), Vector2(-0.52, 0.10), Vector2(0.50, 0.06),
	Vector2(-0.26, -0.46), Vector2(0.32, -0.40), Vector2(0.02, 0.46),
	Vector2(-0.40, 0.36), Vector2(0.44, -0.14),
]
const LOBE_SCALES: Array[float] = [1.00, 0.66, 0.64, 0.56, 0.52, 0.48, 0.50, 0.54]
## Per-lobe alpha. Uniform lobes stack into one flat disc; letting the outer ones sit
## lighter than the core is what gives the puff a billowed edge instead of a soft blur.
const LOBE_ALPHA: Array[float] = [1.00, 0.90, 0.90, 0.80, 0.80, 0.74, 0.76, 0.82]

## A puff leaves the stack a little wider than the flue and swells as it cools, both as
## multiples of the stack radius. The end figure is deliberately large: the puff travels
## DRIFT (100 u) over its life, roughly two building-widths, and a cloud that stayed near
## the size of its chimney would be a speck lost against that journey. At these numbers a
## furnace (r 3.2) ends about 29 u across and a power plant (r 4.6) about 41 — a plume that
## reads as weather over the building rather than a dot beside it.
## Both raised 25% (owner, 2026-08-27) from 1.4 / 9.0.
const START_SCALE := 1.75
const END_SCALE := 11.25
## Below this many pixels across, a puff is a smudge nobody can read and every one of its
## six discs still costs a draw call — so the whole layer stands down when zoomed out.
const MIN_PUFF_PX := 3.0
## Keep drawing a little beyond the screen edge, so a puff drifting in from off-screen does
## not pop into existence at the border.
const CULL_MARGIN := 160.0

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
	var view := _visible_world_rect()
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
		_draw_puff(at, base_r, _phase(float(stack["seed"])), bool(stack.get("carbon", true)))


## Age of this stack's current puff, 0 at emission and 1 at the end of its life. The seeded
## offset is what stops every chimney on the map breathing in time with every other.
func _phase(seed_val: float) -> float:
	return fposmod(_clock + seed_val * PERIOD, PERIOD) / PERIOD


func _draw_puff(origin: Vector2, base_r: float, p: float, carbon: bool) -> void:
	# Drift eases OUT: a puff leaves the stack briskly and slows as it spreads and cools.
	var travelled := 1.0 - pow(1.0 - p, 1.7)
	var centre := origin + NE * DRIFT * travelled
	# Growth eases IN: smoke holds together as it leaves the flue and spreads once it is
	# clear of it, rather than ballooning off the chimney top.
	var radius := base_r * lerpf(START_SCALE, END_SCALE, pow(p, 0.75))
	# Alpha rises fast then falls away to nothing. The quick rise is what hides the seam
	# where one puff dies and the next is born on the same frame; the gentle exponent keeps
	# the cloud readable through mid-life instead of washing out as soon as it spreads.
	var alpha := PEAK_ALPHA * (minf(p / 0.10, 1.0) if p < 0.10 else pow(1.0 - p, 1.15))
	if not carbon:
		alpha *= STEAM_ALPHA_SCALE
	if alpha <= 0.004:
		return
	var tint := SMOKE if carbon else STEAM
	# Lobes spread apart as the puff grows, so it frays rather than swelling as a rigid
	# shape — the difference between smoke dispersing and a balloon inflating.
	var spread := lerpf(0.35, 1.0, p)
	for i in LOBES:
		draw_circle(centre + LOBE_OFFSETS[i] * radius * spread,
			radius * LOBE_SCALES[i] * 0.70,
			Color(tint.r, tint.g, tint.b, alpha * LOBE_ALPHA[i]))


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
