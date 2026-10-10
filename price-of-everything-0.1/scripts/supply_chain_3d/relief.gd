extends RefCounted
## Display-only relief for the 3D supply-chain board. Shared map geography and
## the source 2D board retain their original heights.
const Source := preload("res://scripts/empire_board_relief.gd")
# Band 0 is map level -1. Grow each successive rise: 2x into L5, 3x into
# L6, up to 7x into L10. Interpolation remains continuous at every boundary.
const UPPER_DATUM: float = Source.BAND_LEVEL[5]
const STEP := 11.0

static func height(source_height: float) -> float:
	if source_height <= UPPER_DATUM: return source_height
	var band := clampi(floori((source_height - UPPER_DATUM) / STEP), 0, 5)
	var complete := STEP * band * (band + 3.0) * 0.5
	return UPPER_DATUM + complete + (source_height - UPPER_DATUM - STEP * band) * (band + 2)

static func slope_scale(source_height: float) -> float:
	if source_height <= UPPER_DATUM: return 1.0
	return float(clampi(floori((source_height - UPPER_DATUM) / STEP), 0, 5) + 2)
