extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Green := preload("res://scripts/supply_chain_3d/rail_vegetation.gd")
const Trees := preload("res://scripts/supply_chain_3d/tree_layout.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func _rail_art(level: Callable = Callable(), roads: Array = []) -> Dictionary:
	var flat := func(_p: Vector2) -> float: return 34.0
	var low := func(_p: Vector2) -> float: return 1.0
	return Rail.build([{"mode": "rails", "level": 3, "pts": [{"p": Vector2(-240, 0)}, {"p": Vector2(240, 0)}]}],
		roads, flat, level if level.is_valid() else low)

func _test_rail_vegetation_clearance_and_tunnel_roofs() -> void:
	var mountain := func(p: Vector2) -> float: return 7.0 if absf(p.x) < 85 else 1.0
	var art := _rail_art(mountain)
	var green := Green.new()
	green.configure(art, [], [], [], {}, func(_p): return 34.0)
	_check(not green.clear(Vector2(-160, 0), 10), "Rail vegetation: open tracks exclude the entire tree crown")
	_check(not green.clear(Vector2(-160, 15), 10) and green.clear(Vector2(-160, 30), 10), "Rail vegetation: canopy clearance includes a verge without clearing distant trees")
	_check(green.clear(Vector2.ZERO, 10), "Rail vegetation: fully covered tunnel roofs retain vegetation")
	for portal in art.portals:
		_check(not green.clear(portal.p - portal.dir * 16, 8) and not green.clear(portal.p + portal.dir * 12, 8),
			"Rail vegetation: portal approach and collar remain clear")
	var fresh := Green.new()
	fresh.restore(green.packed())
	_check(fresh.clear(Vector2.ZERO, 10) and not fresh.clear(Vector2(-160, 0), 10), "Rail vegetation: cached clearance restores without generating track geometry")
	_check(fresh.beside_rail(Vector2(-160, 40)) and not fresh.beside_rail(Vector2(-160, 80)), "Rail vegetation: cached rail belt selects only nearby trees for half sizing")
	green.configure({}, [{"a": Vector2(-40, 0), "b": Vector2(40, 0), "half": 8, "bridge": true}],
		[{"p": Vector2(80, 0), "dir": Vector2.RIGHT, "half_width": 10, "depth": 7}],
		[{"pos": Vector2(400, 0), "yaw": PI/4}], {}, func(_p): return 34.0)
	_check(not green.clear(Vector2(0, 15), 8), "Rail vegetation: road bridges reserve canopy clearance too")
	_check(not green.clear(Vector2(80, 15), 8), "Rail vegetation: road tunnel wings remain clear")
	_check(not green.clear(Vector2(400, 0), 8), "Rail vegetation: depot tracks and sidings stay clear")

func _test_rail_vegetation_rural_rows() -> void:
	var art := _rail_art()
	var flat := func(_p): return 34.0
	var green := Green.new()
	var tiles := {"test": {"type": "rural", "center": Vector2.ZERO}}
	green.configure(art, [], [], [], tiles, flat)
	var rows := {}
	var valid := true
	for tree in green.rows.test:
		rows[Vector2i(tree.row, int(tree.side))] = true
		valid = valid and green.clear(tree.pos, Trees.canopy(tree)) and tree.height >= 8.5 and tree.height <= 10.5 and tree.size_scale == 0.5
	_check(valid and rows.size() in [4, 6], "Rail vegetation: two or three half-size tree rows follow both sides of rural track")
	var positive_first_row: Array = green.rows.test.filter(func(tree): return tree.row == 0 and tree.side == 1.0)
	var closest := INF
	for i in range(1, positive_first_row.size()): closest = minf(closest, positive_first_row[i-1].pos.distance_to(positive_first_row[i].pos))
	_check(closest >= 12.5 and closest < 13.5, "Rail vegetation: half-size rows use twice the previous planting density along the track")
	var extents := {}
	var starts := {}; var ends := {}
	for tree in green.rows.test:
		var key := Vector2i(tree.row, int(tree.side))
		var extent: Vector2 = extents.get(key, Vector2(INF, -INF))
		extents[key] = Vector2(minf(extent.x, tree.pos.x), maxf(extent.y, tree.pos.x))
		if tree.row == 0:
			var crown := Trees.canopy(tree)
			var track_edge := Rail.CORRIDOR_WIDTH * 0.5
			valid = valid and absf((absf(tree.pos.y) - crown - track_edge) - (Green.FIRST_ROW - crown - track_edge) / 3.0) <= 0.501
	for extent in extents.values():
		starts[snappedf(extent.x, 0.1)] = true
		ends[snappedf(extent.y, 0.1)] = true
	_check(valid, "Rail vegetation: visible track-to-canopy gap is one third of its previous size, within planting jitter")
	_check(starts.size() > 2 and ends.size() > 2, "Rail vegetation: rows start and finish at independently staggered stations")
	var first := green.packed().duplicate(true)
	green.configure(art, [], [], [], tiles, flat)
	_check(green.rows == first.rows, "Rail vegetation: positions and species are deterministic")
	var farm := {"kind": "building", "internal_name": "farm", "tile": "test", "pos": Vector2(-100, 70), "side": 60,
		"footprint": PackedVector2Array([Vector2(-240, 15),Vector2(0, 15),Vector2(0, 125),Vector2(-240, 125)])}
	var trees := Trees.placements("test", tiles.test, {}, [farm], [], [], [], green, flat)
	var planted := 0
	for tree in trees:
		if tree.get("source", "") != "rail_row": continue
		planted += 1
		valid = valid and not Geometry2D.is_point_in_polygon(tree.pos, farm.footprint) and green.clear(tree.pos, Trees.canopy(tree))
	_check(valid and planted > 5, "Rail vegetation: planted rows leave field footprints clear")
	tiles.test.type = "urban"
	green.configure(art, [], [], [], tiles, flat)
	_check(green.rows.is_empty(), "Rail vegetation: no automatic rows in towns")
	tiles.test.type = "rural"
	for prof in art.corridor_profiles:
		for sample in prof.samples: sample.bridge = true
	green.configure(art, [], [], [], tiles, flat)
	_check(green.rows.is_empty(), "Rail vegetation: bridge decks do not sprout tree rows")

func _test_rail_vegetation_tree_size_variation() -> void:
	var tile := {"type": "rural", "center": Vector2.ZERO}
	var trees := Trees.placements("size-check", tile, {}, [], [], [], [])
	var sizes := {}
	var valid := true
	var source := Trees.Legacy._tree_spots("size-check", "rural")
	for tree in trees:
		sizes[tree.size_scale] = true
		var original: Array = source.filter(func(spot): return spot.p == tree.pos and spot.kind == tree.kind)
		valid = valid and original.size() == 1
		if original.size() == 1:
			valid = valid and is_equal_approx(tree.height, Trees.Legacy._TREE_HEIGHT[tree.kind] * original[0].scale * tree.size_scale)
	_check(valid and sizes.has(1.0) and sizes.has(0.75) and sizes.has(0.5) and sizes.size() == 3, "3D trees: use all three requested sizes relative to the original placement")
	_check(trees == Trees.placements("size-check", tile, {}, [], [], [], []), "3D trees: size variation remains deterministic")
	var green := Green.new()
	green.configure(_rail_art(), [], [], [], {"size-check": tile}, func(_p): return 34.0)
	valid = true
	for tree in Trees.placements("size-check", tile, {}, [], [], [], [], green):
		if green.beside_rail(tree.pos): valid = valid and tree.size_scale == 0.5
	_check(valid, "3D trees: existing trees inside rail belts also use only the half-size tier")

func _test_rail_vegetation_medium_linework() -> void:
	var art := _rail_art()
	var overview_colors: PackedColorArray = art.overview.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check(not overview_colors.has(Rail.STEEL) and not overview_colors.has(Rail.CONCRETE), "Rail medium: no bright steel strips or sleeper dots")
	_check(art.overview.get_faces().size() < art.detail.get_faces().size(), "Rail medium: simple continuous bands replace subpixel fittings")
	var builder := Builder.new()
	var root := Node3D.new()
	builder.add_detail(root, art.overview, 0, 1)
	builder.add_detail(root, art.detail, 2)
	for tier in range(3):
		builder.set_detail(tier, false)
		_check(root.get_child(0).visible == (tier < 2) and root.get_child(1).visible == (tier == 2),
			"Rail LOD: medium and detailed track never overlap at tier %s" % tier)
	root.free()
