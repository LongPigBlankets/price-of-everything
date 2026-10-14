extends RefCounted
## Stoneshore pilot: presentation-only street infill, never simulation buildings.
## Seed plots before frontage fitting so all LODs/cache paths share one layout.
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const SPACES := ["civic_park", "civic_plaza", "civic_pond", "civic_grove"]
const DISTRICT_LIMITS := {"civic_u_office": 1, "civic_bauhaus": 1, "civic_commercial": 2, "civic_semi": 4}
const NAMES := {"civic_office": "Offices", "civic_l": "Courtyard offices", "civic_park": "Pocket park", "civic_plaza": "Public square",
	"civic_u_office": "Courtyard tower", "civic_semi": "Semi-detached homes", "civic_bauhaus": "Bauhaus works", "civic_commercial": "Shopping block"}
## Existing full-size houses and towers have 11.8u storeys. Commercial floors
## share that scale; a broad footprint must not shrink the people inside it.
const STOREY := 12.0
static var _options := {}

static func modular_shape(s: Dictionary) -> String:
	if s.get("decor_family", "") == "civic_l": return "l"
	if s.get("decor_family", "") == "civic_office" and int(s.get("level", 1)) == 1: return "long"
	return ""

static func options_for(s: Dictionary) -> Array:
	var shape := modular_shape(s)
	if shape.is_empty(): return []
	if not _options.has(shape):
		var options := Assets.civic_modules(shape)
		for option in options:
			option.side = STOREY / float(option.storey)
			option.bays = Vector2i(int(option.module.columns), int(option.module.return_columns))
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var score_a := int(a.bays.x + a.bays.y)
			var score_b := int(b.bays.x + b.bays.y)
			return score_a > score_b if score_a != score_b else a.bays.x > b.bays.x)
		_options[shape] = options
	return _options[shape]

static func catalog_signature() -> Array:
	# Include every available size so a new/changed module invalidates fitting.
	return [options_for({"decor_family": "civic_l"}), options_for({"decor_family": "civic_office", "level": 1})]

static func side_for(family: String, level: int) -> float:
	if family in SPACES: return 48.0
	if family == "civic_semi": return preload("res://scripts/supply_chain_3d/building_scale.gd").semi_side()
	var key := Assets.key_for(family, level)
	return STOREY / maxf(Assets.storey_height(key), 0.01)

static func is_space(s: Dictionary) -> bool:
	return str(s.get("decor_family", "")) in SPACES

static func populate(model: Dictionary, scope: Array = []) -> void:
	if scope.is_empty(): scope = Region.tile_ids()
	var existing := {}
	for s in model.standing: existing[str(s.iid)] = true
	for tid in scope:
		if not model.tiles.has(tid): continue
		var tile: Dictionary = model.tiles[tid]
		if str(tile.type) != "urban": continue
		# Fill street fronts, retaining space around works, ports, rivers and slopes.
		# Original houses/NPCs fit first; new plots are omitted if no safe space exists.
		var index := 0
		var variant_counts := {}
		for y in range(-180, 181, 60):
			for x in range(-180, 181, 60):
				var variant := (index + int(str(tid).get_slice("_", 1))) % 16
				var family := "civic_office"
				var level := 1 + index % 2
				if variant == 0 or variant == 8:
					family = "civic_park" if variant == 0 else "civic_plaza"
					level = 1
				elif variant == 1:
					family = "civic_u_office"; level = 1
				elif variant in [5, 11]:
					family = "civic_semi"; level = 1
				elif variant in [2, 9]:
					family = "civic_commercial"; level = 1
				elif variant == 10:
					family = "civic_bauhaus"; level = 1
				elif variant % 3 == 0:
					family = "civic_l"; level = 1
				var side := side_for(family, level)
				# Give each building shape a turn at the available sites, beginning
				# with the broad L. Public spaces fill gaps after all three shapes.
				var variant_key := "%s:%d" % [family, level]
				var ordinal := int(variant_counts.get(variant_key, 0))
				variant_counts[variant_key] = ordinal + 1
				var order := ["civic_u_office", "civic_bauhaus", "civic_commercial", "civic_l", "civic_office", "civic_semi"].find(family)
				var priority := 1000 + index if family in SPACES else ordinal * 7 + maxi(order, 0)
				var id := "z_civic:%s:%04d:%02d" % [tid, priority, index]
				index += 1
				if existing.has(id): continue
				model.standing.append({"iid": id, "kind": "house", "tile": tid,
					"pos": tile.center + Vector2(x, y), "side": side, "pad": side,
					"level": level, "decor_family": family, "sprite": null, "polluting": false,
					"name": NAMES[family],
					"max_relief": 2.0 if family in SPACES else 6.0})
