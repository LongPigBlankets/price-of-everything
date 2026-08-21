extends RefCounted
## Draws authored ground and fabric: farm parcels, woodland, parks and decorative masses.
##
## SHARED by the editor's preview, the runtime layers and (in P4) the bake painter, for the
## same reason the road geometry is: three renderers of one thing drift, and the drift is
## only ever discovered by someone comparing a screenshot with the editor.
##
## Everything is deterministic. Fills are seeded through `RoadHash` by the object's stable
## id, so a wood looks the same on every load and in every process, and moving one polygon
## cannot reshuffle its neighbours.
##
## Deliberately has NO `class_name` (the headless global-class-cache trap; see
## `scripts/mass_form_shapes.gd`).

const MidcenturyStyle := preload("res://scripts/map_midcentury_style.gd")
const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")
const TreeShapesRef := preload("res://scripts/tree_shapes.gd")
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")
const InkBuildingGen := preload("res://scripts/ink_building_gen.gd")

## Nominal spacing between trees, world units — a JITTERED GRID rather than random points.
##
## Rejection sampling looked obvious and was wrong: successive keys fed to `RoadHash.pick`
## repeat in their low bits, so consecutive samples landed within a unit of each other on a
## three-step cycle and the wood came out as two thin diagonal lines instead of a fill. A
## grid also gives even coverage, which random points do not — clumps and bare patches read
## as a mistake in a wood of only a few dozen trees.
const TREE_SPACING := 19.0
## Hard ceiling per polygon, so an accidentally enormous outline cannot stall a frame.
const TREE_LIMIT := 900
## Trees are rejected outside the outline, so the fill never spills onto neighbouring
## buildings — the owner's rule for authored woodland. The canopy radius is included in the
## test, since a crown centred just inside the edge still overhangs it.
const TREE_EDGE_INSET := 1.0

## Farm parcel strips, in world units. Mirrors the procedural farm fabric's proportions so an
## authored field sits beside a generated one without announcing itself.
const PARCEL_MIN := 34.0
const PARCEL_MAX := 58.0
const PARCEL_INSET := 2.2

## The map's one light is NW, so every mass offsets its shadow SE exactly like a building
## prism does. Matches the fabric's own BLOCK_SHADOW_OFFSET.
const SHADOW_OFFSET := Vector2(2.2, 2.8)


## A farm: the outline filled with parcel strips in its own long-axis frame, each tinted from
## the farm palette. The strips are what make a field read as worked ground rather than a
## green blob.
static func draw_farm(canvas: CanvasItem, area: Dictionary) -> void:
	var outline := _outline_of(area)
	if outline.size() < 3:
		return
	var id := str(area.get("id", ""))
	canvas.draw_colored_polygon(outline, MapStyle.farm_field_variant(id))
	var index := 0
	for strip in _parcels(outline, id):
		if strip.size() < 3:
			continue
		canvas.draw_colored_polygon(strip, MapStyle.farm_parcel_tint(index))
		canvas.draw_polyline(_closed(strip), MapStyle.farm_parcel_outline(), 1.0, true)
		index += 1


## A wood: individual trees, clipped to the outline. Crowns AND their shadows stay inside the
## polygon — the boundary is hard, because the whole point of authoring a wood is that it
## stops where the designer said it stops.
static func draw_forest(canvas: CanvasItem, area: Dictionary) -> void:
	var id := str(area.get("id", ""))
	for point in woodland_points(area):
		var key := "%s|tree|%.0f|%.0f" % [id, point.x, point.y]
		TreeShapesRef.draw_tree(canvas, TreeShapesRef.pick_kind(key, [55, 25, 20]), point, key)


## Where a wood's trees stand. Split out from the drawing so it can be measured without a
## canvas — the scatter has already been wrong once in a way only a screenshot revealed.
##
## A JITTERED GRID, not random points. Rejection sampling looked obvious and was wrong:
## successive keys fed to `RoadHash.pick` repeat in their low bits, so consecutive samples
## landed within a unit of each other on a three-step cycle and a wood came out as two thin
## diagonal lines. A grid also gives even coverage, which random points do not — clumps and
## bare patches read as a mistake in a wood of a few dozen trees.
static func woodland_points(area: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var outline := _outline_of(area)
	if outline.size() < 3:
		return out
	var id := str(area.get("id", ""))
	var bounds := _bounds(outline)
	var spacing := TREE_SPACING / clampf(float(area.get("density", 1.0)), 0.25, 2.0)
	var salt := RoadHash.fnv1a(id) & 0xFFFF
	var columns := int(bounds.size.x / spacing) + 1
	var rows := int(bounds.size.y / spacing) + 1
	for ix in columns:
		for iy in rows:
			if out.size() >= TREE_LIMIT:
				return out
			# Coordinates come from the CELL INDICES, so nothing depends on the order the
			# samples are generated in.
			var point := bounds.position + Vector2(
				(float(ix) + 0.5 + RoadHash.jitter01(ix, iy, salt) * 0.9) * spacing,
				(float(iy) + 0.5 + RoadHash.jitter01(ix, iy, salt + 977) * 0.9) * spacing)
			var key := "%s|tree|%.0f|%.0f" % [id, point.x, point.y]
			var reach: float = TreeShapesRef.radius(
				TreeShapesRef.pick_kind(key, [55, 25, 20])) + TREE_EDGE_INSET
			if _inside_by(outline, point, reach):
				out.append(point)
	return out


## A parametric primitive. Drawn like a mass — same wash, same SE micro-shadow, same ink —
## because it IS one; only how its shape is arrived at differs.
static func draw_special(canvas: CanvasItem, special: Dictionary,
		keep_out: Array = []) -> void:
	# The DRAWN polygon, which for a ring is a band around the four corners the designer
	# edits — see AuthoredSpecialShapes.render_polygon.
	var outline := AuthoredSpecialShapes.render_polygon(special)
	if outline.size() < 3:
		return
	var colour := MidcenturyStyle.urban_block(str(special.get("id", "")), 0.6)
	for piece_value in _subtract(outline, keep_out):
		_block(canvas, piece_value as PackedVector2Array, colour)


## A HARBOUR, from the shapes a port was imported as (`port: <tile_id>`).
##
## Drawn as a GROUP rather than one special at a time, for the same reason the planner's own
## renderer does: a dock and its arms are one poured deck, so they are filled in one colour and
## outlined ONCE around their merged silhouette. Outlining each imported shape separately would
## put an ink seam across every junction — which is exactly the seam that was removed from the
## planner's harbours, and it would come straight back the moment a port was authored.
##
## The quay tone is keyed off the tile, so every shape of one harbour agrees and two harbours
## still differ slightly, exactly as `industrial_yard` intends.
static func draw_port_group(canvas: CanvasItem, records: Array, tile_id: String,
		keep_out: Array = []) -> void:
	var colour := MidcenturyStyle.industrial_yard("port|%s" % tile_id)
	var pieces: Array = []
	var sheds: Array = []
	for record_value in records:
		var record: Dictionary = record_value
		var outline := AuthoredSpecialShapes.render_polygon(record)
		# A warehouse is a BUILDING standing on the quay, not part of the deck: it keeps its own
		# brick roof and its own outline, drawn after the quay so it reads on top. Folding it
		# into the merged silhouette (as the first import did) painted the office the same
		# colour as the ground it stands on, which is to say painted it out.
		if str(record.get("port_role", "quay")) == "warehouse":
			for piece_value in _subtract(outline, keep_out):
				sheds.append(piece_value)
			continue
		for piece_value in _subtract(outline, keep_out):
			pieces.append(piece_value)
	for piece_value in pieces:
		var piece: PackedVector2Array = piece_value
		var shadow := PackedVector2Array()
		for point in piece:
			shadow.append(point + SHADOW_OFFSET)
		canvas.draw_colored_polygon(shadow, MidcenturyStyle.SHADOW)
	for piece_value in pieces:
		canvas.draw_colored_polygon(piece_value as PackedVector2Array, colour)
	for ring_value in merged_rings(pieces):
		canvas.draw_polyline(_closed(ring_value as PackedVector2Array),
			MidcenturyStyle.INK, 1.05, true)
	for shed_value in sheds:
		var shed: PackedVector2Array = shed_value
		if shed.size() < 3:
			continue
		var shadow := PackedVector2Array()
		for point in shed:
			shadow.append(point + SHADOW_OFFSET)
		canvas.draw_colored_polygon(shadow, MidcenturyStyle.SHADOW)
		canvas.draw_colored_polygon(shed, MidcenturyStyle.gameplay_block_top("brick"))
		canvas.draw_polyline(_closed(shed), MidcenturyStyle.INK, 1.05, true)
		# The roof cap: a smaller concentric plate in the roof red, the same read the planner
		# gives its sheds so an authored office and a planned one are the same building.
		var centre := Vector2.ZERO
		for point in shed:
			centre += point
		centre /= float(shed.size())
		var cap := PackedVector2Array()
		var scale := 0.72 + float(RoadHash.pick("%s|warehouse-cap" % tile_id, 9)) * 0.012
		for point in shed:
			cap.append(centre + (point - centre) * scale)
		var cap_shadow := PackedVector2Array()
		for point in cap:
			cap_shadow.append(point + SHADOW_OFFSET)
		canvas.draw_colored_polygon(cap_shadow, MidcenturyStyle.SHADOW)
		canvas.draw_colored_polygon(cap, Color("a6634f"))
		canvas.draw_polyline(_closed(cap), MidcenturyStyle.INK, 1.05, true)


## The decoration that belongs to an imported harbour: container stacks and gantry cranes.
##
## It rides in the document beside the structure (`port_decor`) rather than being regenerated,
## because the planner's own decoration is positioned from the seat it searched for — and that
## seat moves with the player's buildings. Regenerating it against a hand-placed quay would put
## the cranes somewhere else entirely. Moving the quay in the editor means moving these too;
## they are ordinary records with ordinary coordinates.
static func draw_port_decor(canvas: CanvasItem, records: Array, keep_out: Array = []) -> void:
	for record_value in records:
		var record: Dictionary = record_value
		match str(record.get("kind", "")):
			"container":
				var poly := _points_of(record, "outline")
				if poly.size() < 3:
					continue
				var index := RoadHash.pick("port|container|%s" % str(poly[0]),
					InkBuildingGen.CONTAINER_COLS.size())
				for piece_value in _subtract(poly, keep_out):
					canvas.draw_colored_polygon(piece_value as PackedVector2Array,
						InkBuildingGen.CONTAINER_COLS[index])
			"crane":
				_draw_crane(canvas, record)


## One gantry crane: base block, rail across the quay, two legs, and the jib reaching over the
## basin. Mirrors `port_visuals._draw_crane` — the planner's harbours and the authored ones must
## put the same machine on the same quay.
static func _draw_crane(canvas: CanvasItem, crane: Dictionary) -> void:
	var position := _vector_of(crane.get("position", null))
	var direction := _vector_of(crane.get("direction", null))
	var cross := _vector_of(crane.get("cross", null))
	var span := float(crane.get("gantry_span", 0.0))
	var jib := float(crane.get("jib_length", 0.0))
	if span <= 0.0 or jib <= 0.0:
		return
	var basin_direction := -cross if str(crane.get("arm", "")) == "left" else cross
	var base := _points_of(crane, "base_polygon")
	if base.size() >= 3:
		var shadow := PackedVector2Array()
		for point in base:
			shadow.append(point + SHADOW_OFFSET)
		canvas.draw_colored_polygon(shadow, MidcenturyStyle.SHADOW)
		canvas.draw_colored_polygon(base, MidcenturyStyle.gameplay_block_top("mustard"))
		canvas.draw_polyline(_closed(base), MidcenturyStyle.INK, 1.05, true)
	var rail_a := position - cross * span * 0.5
	var rail_b := position + cross * span * 0.5
	canvas.draw_line(rail_a + SHADOW_OFFSET, rail_b + SHADOW_OFFSET,
		Color(MidcenturyStyle.SHADOW, 0.72), 4.8, true)
	canvas.draw_line(rail_a, rail_b, MidcenturyStyle.INK, 3.2, true)
	for side in [-1.0, 1.0]:
		var leg := position + cross * float(side) * span * 0.40
		canvas.draw_circle(leg, 2.8, MidcenturyStyle.gameplay_block_top("mustard"))
		canvas.draw_arc(leg, 2.8, 0.0, TAU, 12, MidcenturyStyle.INK, 1.1, true)
	var jib_end := position + basin_direction * jib + direction * 4.0
	canvas.draw_line(position + SHADOW_OFFSET, jib_end + SHADOW_OFFSET,
		Color(MidcenturyStyle.SHADOW, 0.72), 4.6, true)
	canvas.draw_line(position, jib_end, MidcenturyStyle.gameplay_block_top("mustard"), 3.0, true)
	canvas.draw_line(position, jib_end, MidcenturyStyle.INK, 1.0, true)
	canvas.draw_circle(jib_end, 2.1, MidcenturyStyle.INK)


static func _points_of(record: Dictionary, key: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var value: Variant = record.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in (value as Array):
		if typeof(entry) == TYPE_ARRAY and (entry as Array).size() >= 2:
			out.append(Vector2(float((entry as Array)[0]), float((entry as Array)[1])))
	return out


## Outer boundaries of a set of touching polygons, merged into as few rings as possible.
## `merge_polygons` is pairwise, so the accumulator is folded through every piece; clockwise
## rings are holes and are dropped, because a quay never encloses water it does not own.
static func merged_rings(polygons: Array) -> Array:
	var merged: Array = []
	for poly_value in polygons:
		var poly: PackedVector2Array = poly_value
		if poly.size() < 3:
			continue
		if merged.is_empty():
			merged.append(poly)
			continue
		var next: Array = []
		var absorbed := false
		for existing_value in merged:
			var existing: PackedVector2Array = existing_value
			var union := Geometry2D.merge_polygons(existing, poly)
			if union.size() == 1 and not absorbed:
				poly = union[0]
				absorbed = true
			else:
				next.append(existing)
		next.append(poly)
		merged = next
	var out: Array = []
	for poly_value in merged:
		var poly: PackedVector2Array = poly_value
		if poly.size() >= 3 and not Geometry2D.is_polygon_clockwise(poly):
			out.append(poly)
	return out


## A plaza: paved cream ground. The same paper the streets are drawn in, so a square reads as
## an opening in the fabric rather than as another kind of green.
static func draw_plaza(canvas: CanvasItem, plaza: Dictionary) -> void:
	var outline := _outline_of(plaza)
	if outline.size() < 3:
		return
	canvas.draw_colored_polygon(outline, MidcenturyStyle.PAPER)
	canvas.draw_polyline(_closed(outline), MidcenturyStyle.INK, 1.0, true)


static func draw_park(canvas: CanvasItem, park: Dictionary) -> void:
	var outline := _outline_of(park)
	if outline.size() < 3:
		return
	canvas.draw_colored_polygon(outline, MidcenturyStyle.park(str(park.get("id", ""))))


## A decorative mass from the 17-form vocabulary, with the map's SE micro-shadow under it.
static func draw_mass(canvas: CanvasItem, mass: Dictionary,
		keep_out: Array = []) -> void:
	var id := str(mass.get("id", ""))
	var colour := MidcenturyStyle.urban_block(id, 0.6)
	for polygon in mass_polygons(mass):
		for piece_value in _subtract(polygon as PackedVector2Array, keep_out):
			_block(canvas, piece_value as PackedVector2Array, colour)


## One built block: SE micro-shadow, fill, ink outline. Shared so a mass and a special that
## have been cut by a keep-out region are finished exactly like one that has not.
static func _block(canvas: CanvasItem, polygon: PackedVector2Array, colour: Color) -> void:
	if polygon.size() < 3:
		return
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + SHADOW_OFFSET)
	canvas.draw_colored_polygon(shadow, MidcenturyStyle.SHADOW)
	canvas.draw_colored_polygon(polygon, colour)
	canvas.draw_polyline(_closed(polygon), MidcenturyStyle.INK, 1.0, true)


## `polygon` minus every keep-out region, as the pieces that survive.
##
## KEEP-OUT CUTS BUILDINGS, IT DOES NOT DELETE THEM. A harbour is dropped onto a town that was
## drawn without knowing it was coming, so the terrace it lands on should stop at the quay the
## way a real street does — not vanish, which leaves a hole in the fabric where a block used to
## be. A piece cut to nothing simply does not draw, so a mass wholly inside the region still
## disappears without a special case.
##
## Clockwise rings are holes (a region entirely inside one block) and are dropped: the fill
## call takes no holes, and a ring drawn as if solid would be worse than the small overdraw.
static func surviving_pieces(polygon: PackedVector2Array, keep_out: Array) -> Array:
	return _subtract(polygon, keep_out)


static func _subtract(polygon: PackedVector2Array, keep_out: Array) -> Array:
	if polygon.size() < 3:
		return []
	if keep_out.is_empty():
		return [polygon]
	var pieces: Array = [polygon]
	for region_value in keep_out:
		var region: PackedVector2Array = region_value
		if region.size() < 3:
			continue
		var next: Array = []
		for piece_value in pieces:
			for result_value in Geometry2D.clip_polygons(piece_value as PackedVector2Array, region):
				var result: PackedVector2Array = result_value
				if result.size() >= 3 and not Geometry2D.is_polygon_clockwise(result):
					next.append(result)
		pieces = next
		if pieces.is_empty():
			return []
	return pieces


## The world-space polygons of a stamped mass. Built through `MassFormShapes`, which owns
## the vocabulary's geometry AND its safety rules: a form that cannot be built at the
## requested proportions descends its own fallback ladder to something simple rather than
## emitting a sliver or a self-touching outline.
##
## The stamp is stored as centre/rotation/size, and the parcel the constructors expect is
## derived from those — the designer drags a box, not a parcel polygon. `frontage_index` 0
## means the box's first edge is the frontage, which is the edge rotation points along.
static func mass_polygons(mass: Dictionary) -> Array:
	var parcel := mass_parcel(mass)
	if parcel.size() < 3:
		return []
	var built: Dictionary = MassFormShapes.build_form(
		str(mass.get("form", "solid")), parcel, 0, str(mass.get("id", "")))
	return built.get("polys", []) as Array


## The oriented box a stamp occupies — its footprint for hit-testing and selection, and the
## parcel the form is fitted into.
static func mass_parcel(mass: Dictionary) -> PackedVector2Array:
	# An explicit parcel wins: once a corner has been dragged the box is no longer a
	# rectangle, and centre/rotation/size cannot describe it. Same rule as the primitives —
	# a shape reshaped by hand stops being defined by its numbers.
	if mass.has("parcel"):
		var explicit := PackedVector2Array()
		for entry in (mass.get("parcel", []) as Array):
			var values: Array = entry as Array
			if values != null and values.size() >= 2:
				explicit.append(Vector2(float(values[0]), float(values[1])))
		if explicit.size() >= 3:
			return explicit
	var size := _vector_of(mass.get("size", [40.0, 30.0]))
	if size.x < 1.0 or size.y < 1.0:
		return PackedVector2Array()
	var centre := _vector_of(mass.get("pos", [0.0, 0.0]))
	var rotation := float(mass.get("rot", 0.0))
	var half := size * 0.5
	var out := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(centre + corner.rotated(rotation))
	return out


## Parcel strips across the polygon's long axis, the same construction the procedural farm
## fabric uses: cut the outline with a run of bands, keep what lands inside.
static func _parcels(outline: PackedVector2Array, id: String) -> Array:
	var out: Array = []
	var bounds := _bounds(outline)
	var horizontal := bounds.size.x >= bounds.size.y
	var span: float = bounds.size.x if horizontal else bounds.size.y
	var walked := 0.0
	var index := 0
	while walked < span and index < 40:
		var width: float = PARCEL_MIN + (PARCEL_MAX - PARCEL_MIN) \
			* (float(RoadHash.pick("%s|parcel|%d" % [id, index], 1000)) / 1000.0)
		var band := PackedVector2Array()
		if horizontal:
			var x0 := bounds.position.x + walked
			var x1 := minf(x0 + width, bounds.end.x)
			band = PackedVector2Array([
				Vector2(x0, bounds.position.y - 4.0), Vector2(x1, bounds.position.y - 4.0),
				Vector2(x1, bounds.end.y + 4.0), Vector2(x0, bounds.end.y + 4.0)])
		else:
			var y0 := bounds.position.y + walked
			var y1 := minf(y0 + width, bounds.end.y)
			band = PackedVector2Array([
				Vector2(bounds.position.x - 4.0, y0), Vector2(bounds.end.x + 4.0, y0),
				Vector2(bounds.end.x + 4.0, y1), Vector2(bounds.position.x - 4.0, y1)])
		for piece in Geometry2D.intersect_polygons(outline, band):
			var inset := Geometry2D.offset_polygon(piece, -PARCEL_INSET)
			for shrunk in inset:
				if shrunk.size() >= 3:
					out.append(shrunk)
		walked += width
		index += 1
	return out


## Point-in-polygon with clearance: true only when the point is inside AND at least `reach`
## from every edge, so a canopy centred near the boundary cannot overhang it.
static func _inside_by(outline: PackedVector2Array, point: Vector2, reach: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, outline):
		return false
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < reach:
			return false
	return true


static func _outline_of(source: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (source.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


static func _vector_of(value: Variant) -> Vector2:
	var values: Array = value as Array
	if values == null or values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


static func _bounds(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() >= 2:
		out.append(out[0])
	return out
