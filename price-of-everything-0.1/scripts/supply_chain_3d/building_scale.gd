extends RefCounted
## Presentation only: keep fitted footprints while giving residential houses a
## common base-to-roof height. Towers and civic/industrial assets retain theirs.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const HOUSE_HEIGHT := 50.0
const TERRACE_ROW_SIDE := 72.0
const TERRACE_HOMES := 3.0
const SEMI_HOME_WIDTHS := 2.5
const SEMI_HEIGHT := HOUSE_HEIGHT * 1.1

static func semi_side() -> float:
	var terrace := Assets.key_for("house", 1)
	var semi := Assets.key_for("civic_semi", 1)
	# house_lvl1 is three terraced homes. Size the complete mirrored pair
	# against one home's share of that frontage, including its roof overhang.
	return Assets.dimensions(terrace).x * TERRACE_ROW_SIDE / TERRACE_HOMES * SEMI_HOME_WIDTHS / Assets.dimensions(semi).x

static func for_asset(key: String, side: float, decor_scale: float = 1.0) -> Vector3:
	var scale := Vector3.ONE * side
	if key.begins_with("civic_semi_lvl"):
		scale.y = SEMI_HEIGHT * decor_scale / Assets.dimensions(key).y
	elif key.begins_with("house_lvl"):
		scale.y = HOUSE_HEIGHT * decor_scale / Assets.dimensions(key).y
	return scale
