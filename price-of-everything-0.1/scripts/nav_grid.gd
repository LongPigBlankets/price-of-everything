class_name NavGrid
extends RefCounted
## Runtime view of the baked routing navgrid (roads-v2 spec 1.2).
## Decodes data/hills_baked.json's "navgrid" once: per 12u cell a band
## (0..11 = level+1), a water class, and a quantized distance-to-water.
## Also builds a 3x-downsampled coarse grid (36u) for the hierarchical
## router — gate G3 measured ~16 us/expansion in GDScript, so trunk-length
## jobs MUST route coarse-first.

const WATER_LAND := 0
const WATER_SEA := 1
const WATER_LAKE := 2
const WATER_RIVER := 3
const COARSE_FACTOR := 3

static var _inst: NavGrid = null

var origin := Vector2.ZERO
var step := 12.0
var gw := 0
var gh := 0
var cells := PackedByteArray()      # band | water<<4
var dist4 := PackedByteArray()      # distance to water / 4, clamped 255

var coarse_gw := 0
var coarse_gh := 0
var coarse_step := 36.0
## coarse cell byte: 0xFF = no land in block; else min land band in block
var coarse := PackedByteArray()

static func instance() -> NavGrid:
	if _inst == null:
		_inst = NavGrid.new()
		_inst._load()
	return _inst

static func reset_for_tests() -> void:
	_inst = null

func _load() -> void:
	var doc := HillBaked.navgrid()
	if doc.is_empty():
		push_warning("NavGrid: bake has no navgrid — re-run tools/bake_hills.tscn")
		return
	var o: Array = doc.get("origin", [0, 0])
	origin = Vector2(float(o[0]), float(o[1]))
	step = float(doc.get("step", 12.0))
	gw = int(doc.get("gw", 0))
	gh = int(doc.get("gh", 0))
	cells = Marshalls.base64_to_raw(str(doc.get("cells_b64", "")))
	dist4 = Marshalls.base64_to_raw(str(doc.get("dist_b64", "")))
	if cells.size() != gw * gh:
		push_warning("NavGrid: cell payload size mismatch (%d != %d)" % [cells.size(), gw * gh])
		gw = 0
		gh = 0
		return
	_build_coarse()

func is_ready() -> bool:
	return gw > 0 and gh > 0

func band(ix: int, iy: int) -> int:
	return cells[iy * gw + ix] & 0x0F

func level(ix: int, iy: int) -> int:
	return (cells[iy * gw + ix] & 0x0F) - 1

func water(ix: int, iy: int) -> int:
	return cells[iy * gw + ix] >> 4

func water_distance(ix: int, iy: int) -> float:
	return float(dist4[iy * gw + ix]) * 4.0

func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(round((world.x - origin.x) / step)), 0, gw - 1),
		clampi(int(round((world.y - origin.y) / step)), 0, gh - 1),
	)

func world_of(ix: int, iy: int) -> Vector2:
	return origin + Vector2(ix * step, iy * step)

## Coarse grid: a block is passable when ANY of its fine cells is land
## (optimistic — the fine refinement pass is the authority on water); its
## band is the MINIMUM land band in the block so coarse routes prefer
## valleys exactly like fine routes do.
func _build_coarse() -> void:
	coarse_step = step * COARSE_FACTOR
	coarse_gw = int(ceil(float(gw) / COARSE_FACTOR))
	coarse_gh = int(ceil(float(gh) / COARSE_FACTOR))
	coarse = PackedByteArray()
	coarse.resize(coarse_gw * coarse_gh)
	for cy in coarse_gh:
		for cx in coarse_gw:
			var best := 0xFF
			for dy in COARSE_FACTOR:
				var iy := cy * COARSE_FACTOR + dy
				if iy >= gh:
					break
				var row := iy * gw
				for dx in COARSE_FACTOR:
					var ix := cx * COARSE_FACTOR + dx
					if ix >= gw:
						break
					var b := cells[row + ix]
					if (b >> 4) == WATER_LAND:
						best = mini(best, b & 0x0F)
			coarse[cy * coarse_gw + cx] = best

func coarse_cell_of(world: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(round((world.x - origin.x) / coarse_step)), 0, coarse_gw - 1),
		clampi(int(round((world.y - origin.y) / coarse_step)), 0, coarse_gh - 1),
	)

func coarse_world_of(ix: int, iy: int) -> Vector2:
	return origin + Vector2(ix * coarse_step, iy * coarse_step)
