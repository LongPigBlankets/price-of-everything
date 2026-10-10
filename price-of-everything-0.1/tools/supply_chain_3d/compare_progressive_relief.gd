extends "res://tools/supply_chain_3d/compare_relief_variants.gd"
## Progressive entry: 2×, 3×, 4×, 5×, then continue 6×/7× to levels 9/10.
## Scale 0 selects this candidate; positive scales preserve the earlier previews.

func _profiles() -> Array:
	return [{"name": "current", "scale": 2.0}, {"name": "4x", "scale": 4.0}, {"name": "progressive", "scale": 0.0}]

func _output_folder() -> String:
	return "res://../outputs/supply-chain-3d/mountain-progressive/"

func _height(h: float, first_scale: float) -> float:
	if first_scale != 0.0: return super._height(h, first_scale)
	if h <= L4: return h
	# Sum complete band increments, then linearly interpolate the current band.
	# Beyond the highest authored band, continue its 7× slope rather than grow unbounded.
	var band := clampi(floori((h - L4) / 11.0), 0, 5)
	var complete := 11.0 * band * (band + 3.0) * 0.5
	return L4 + complete + (h - L4 - 11.0 * band) * (band + 2.0)

func _slope(h: float, first_scale: float) -> float:
	if first_scale != 0.0: return super._slope(h, first_scale)
	if h <= L4: return 1.0
	return float(clampi(floori((h - L4) / 11.0), 0, 5) + 2)

func _validate_profiles() -> void:
	super._validate_profiles()
	for h in [25.0, 34.0, 50.0, 66.0, 77.0]: assert(is_equal_approx(_height(h, 0.0), h))
	var expected := [77.0, 99.0, 132.0, 176.0, 231.0, 297.0, 374.0]
	for i in expected.size():
		var h := L4 + 11.0 * i
		assert(is_equal_approx(_height(h, 0.0), expected[i]))
		assert(_height(h + 0.001, 0.0) - _height(h - 0.001, 0.0) < 0.016)
		if i == 0: continue
		assert(is_equal_approx(expected[i] - expected[i - 1], 11.0 * (i + 1)))
		var mid := h - 5.5
		var derivative := (_height(mid + 0.01, 0.0) - _height(mid - 0.01, 0.0)) / 0.02
		assert(absf(derivative - _slope(mid, 0.0)) < 0.001)
	assert(is_equal_approx(_slope(160.0, 0.0), 7.0))
	print("[PROGRESSIVE RELIEF] exact 2×/3×/4×/5×/6×/7× steps, continuity and slope derivatives validated")
