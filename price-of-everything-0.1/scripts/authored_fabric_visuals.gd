extends Node2D
## Draws authored ground and fabric in the game: farmland, woodland, parks and decorative
## masses (`data/map_authored/<active>.json`).
##
## Sits at `UrbanFabricVisuals`' place in `scenes/main.tscn` — sibling order is the whole
## layering system here — so rivers, buildings and roads all draw over it, exactly as they do
## over the procedural fabric it replaces.
##
## DRAW ORDER WITHIN THE LAYER is ground first, then things standing on it: farmland, parks,
## masses, woodland. Woodland last because a canopy overhangs what it grows beside, and a
## tree drawn under a mass would read as the mass sitting in a hole.
##
## Unlike roads, none of this is unlockable: ground and fabric are simply there. Only roads
## carry the connection rule, because only roads are something the player builds.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredPortCraneLayer := preload("res://scripts/authored_port_crane_layer.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")
const AuthoredBake := preload("res://scripts/authored_bake.gd")
const ViewStream := preload("res://scripts/view_stream.gd")
const BakeLayout := preload("res://scripts/authored_bake_layout.gd")
const BakePainter := preload("res://scripts/authored_bake_painter.gd")

## How far beyond the camera to keep baked textures resident, world units — a little over one
## tile, so a tile is loaded before it scrolls in rather than popping.
const STREAM_MARGIN := 600.0

var _sacrificed: Dictionary = {}
## Regions the fabric is CUT AROUND rather than deleted inside — the harbours, each grown by a
## clearance so the town stops a little short of the quay instead of touching it. Set by
## PortVisuals once its plans are built.
var _keep_out: Array = []
## Last view rect the baked path drew for; a change means recull and redraw.
var _view_rect := Rect2()
## Baked tiles whose texture no longer matches the document because a mass on them was
## evicted, and the repainted textures that replace them. See _repair_evicted_tiles.
var _dirty_tiles: Dictionary = {}
var _repainted: Dictionary = {}
var _repair_running := false


func _ready() -> void:
	# Findable by the placement path, which evicts a mass when a gameplay building takes the
	# ground it stands on. Same shape as `building_footprints`, and the only coupling between
	# the two — placement reads no fabric geometry from here, it measures the document.
	add_to_group("authored_fabric")
	MapStyle.style_changed.connect(func() -> void: queue_redraw())


## Hide a decorative mass because a gameplay building has taken its ground (the eviction rule
## — only masses marked `sacrificial` in the editor are ever passed here).
func evict(mass_id: String) -> void:
	if _sacrificed.has(mass_id):
		return
	_sacrificed[mass_id] = true
	_mark_tiles_of_mass(mass_id)
	queue_redraw()


## Replace the keep-out regions (world polygons). Cheap and idempotent: a redraw only happens
## when the set actually changes, because PortVisuals recomputes its plans on every footprint
## change on a port tile and would otherwise repaint the whole fabric each time.
func set_keep_out(regions: Array) -> void:
	if regions.size() == _keep_out.size():
		var same := true
		for i in regions.size():
			if (regions[i] as PackedVector2Array) != (_keep_out[i] as PackedVector2Array):
				same = false
				break
		if same:
			return
	_keep_out = regions.duplicate()
	# The cut is baked INTO the textures, so changing where a harbour stands makes every tile
	# the old and new regions touch stale. Repainting them is what keeps a baked map agreeing
	# with a vector one about where the town stops.
	if AuthoredBake.is_available():
		for region_value in (regions + _keep_out):
			var region: PackedVector2Array = region_value
			if region.size() < 3:
				continue
			var bounds := Rect2(region[0], Vector2.ZERO)
			for point in region:
				bounds = bounds.expand(point)
			for tile_id in AuthoredBake.tiles_in_rect(bounds.grow(BakeLayout.CULL_MARGIN)):
				_dirty_tiles[str(tile_id)] = true
	queue_redraw()


## Authored woods that have been felled, by AREA ID. Keyed by id rather than by tile because
## most woods in the document predate the editor's `tiles` field — world_map owns the
## tile->area mapping, since placing a wood on a tile needs the hex geometry.
##
## Session-only and deliberately unsaved: a reloaded match re-seeds its forest buildings from
## the document, so the felled set is derived again from what is actually standing.
## NOTE: the felled set itself lives on AuthoredFabricPainter, because BOTH painters (this
## layer's vector path and the SubViewport that repaints a baked tile) have to honour it.
## Keeping a second copy here is what let a repaint faithfully redraw a demolished wood.


## Stop drawing these woods, and repaint the baked tiles their canopies reach.
func forget_forests(area_ids: Array) -> void:
	var changed := false
	for area_value in area_ids:
		var area_id := str(area_value)
		if area_id == "" or AuthoredFabricPainter.felled_forests.has(area_id):
			continue
		AuthoredFabricPainter.felled_forests[area_id] = true
		# The layer draws the felled set live as well as through the bake. Without this the
		# flag was set, `changed` stayed false, and an unbaked map kept drawing the wood.
		changed = true
		# The bake blits a texture per tile, so a felled wood stays on screen until its tiles
		# repaint — and a canopy can overhang its neighbours, so mark everything it reaches.
		if AuthoredBake.is_available():
			var outline: Array = _outline_of_area(area_id)
			if outline.size() >= 3:
				var bounds := Rect2(_point_of(outline[0]), Vector2.ZERO)
				for entry in outline:
					bounds = bounds.expand(_point_of(entry))
				for touched in AuthoredBake.tiles_in_rect(bounds.grow(BakeLayout.CULL_MARGIN)):
					_dirty_tiles[str(touched)] = true
	if changed:
		queue_redraw()


func _outline_of_area(area_id: String) -> Array:
	for area_value in AuthoredMap.forest_areas():
		var area: Dictionary = area_value
		if str(area.get("id", "")) == area_id:
			return area.get("outline", []) as Array
	return []


static func _point_of(entry: Variant) -> Vector2:
	var values: Array = entry as Array
	if values == null or values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


func restore_all() -> void:
	if _sacrificed.is_empty():
		return
	for mass_id in _sacrificed:
		_mark_tiles_of_mass(str(mass_id))
	_sacrificed.clear()
	queue_redraw()


func _draw() -> void:
	var _lpd := Time.get_ticks_usec()
	_cranes_this_pass = []
	_lp_draw_inner()
	# The cranes gathered during the pass go to their own layer, above the ships. Deferred
	# because set_cranes queues a redraw on a sibling and this one is mid-draw.
	_publish_cranes.call_deferred()
	var _lpms := float(Time.get_ticks_usec() - _lpd) / 1000.0
	if _lpms > 50.0 and OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF-DRAW %s %.0f ms   abs=%d" % [name, _lpms, Time.get_ticks_msec()])


func _lp_draw_inner() -> void:
	if not AuthoredMap.is_active():
		return
	# Baked textures when they exist and match the document; vectors otherwise. The vector path
	# below stays the reference picture — it is what the bake is rendered FROM and what the game
	# falls back to when the bake is stale or missing.
	if AuthoredBake.is_available():
		AuthoredBake.draw_layer(self, "fabric",
			AuthoredBake.visible_world_rect(self, STREAM_MARGIN), _repainted)
		_draw_dynamic()
		return
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()   # stable draw order, so overlaps stack the same way every run
	var ordered: Array = []   # valid settlements in stable key order
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) == TYPE_DICTIONARY:
			ordered.append(settlement_value)

	# LAYER-MAJOR, not settlement-major. Every settlement's GROUND (plazas, then parks, then
	# worked land) is laid down before ANY settlement's standing things, so a plaza or park in
	# one settlement can never cover the decorative buildings of a neighbour it overlaps. This
	# map is exactly that case: two settlements share the same ground — one holds the building
	# masses, the other the greens laid over them — and a per-settlement loop (draw one whole,
	# then the next) painted the greens on top of the buildings. This mirrors the editor, which
	# mounts GROUND below STANDING as two separate nodes for the very same reason
	# (see map_editor_fabric.gd). The node itself still sits before BuildingVisuals in
	# main.tscn, so all of this stays under the gameplay buildings.

	# GROUND: paving lowest, then greens, then worked land — surfaces everything stands on.
	for settlement in ordered:
		for plaza in _list(settlement, "plazas"):
			AuthoredFabricPainter.draw_plaza(self, plaza)
	for settlement in ordered:
		for park in _list(settlement, "parks"):
			AuthoredFabricPainter.draw_park(self, park)
	for settlement in ordered:
		for area in _list(settlement, "farms"):
			AuthoredFabricPainter.draw_farm(self, area)
	# STANDING: decorative masses, then specials. Woodland is drawn last of all (a canopy
	# overhangs what it grows beside, so a tree under a mass would read as the mass in a hole).
	for settlement in ordered:
		for mass in _list(settlement, "decor"):
			if not _sacrificed.has(str(mass.get("id", ""))):
				AuthoredFabricPainter.draw_mass(self, mass, _keep_out)
	for settlement in ordered:
		# Imported harbours draw as ONE grouped structure (draw_port_group): a dock and
		# its arms are one deck, so outlining each imported shape on its own would put
		# an ink seam across every junction. Everything else draws on its own.
		var harbours: Dictionary = {}
		for special in _list(settlement, "specials"):
			if _sacrificed.has(str(special.get("id", ""))):
				continue
			var port_tile := str(special.get("port", ""))
			if port_tile != "":
				if not harbours.has(port_tile):
					harbours[port_tile] = []
				(harbours[port_tile] as Array).append(special)
				continue
			AuthoredFabricPainter.draw_special(self, special, _keep_out)
		var harbour_keys := harbours.keys()
		harbour_keys.sort()
		for port_tile in harbour_keys:
			AuthoredFabricPainter.draw_port_group(self, harbours[port_tile],
				str(port_tile), _keep_out)
			# Containers and cranes ride in the document with the quay they belong to, and
			# draw over it — the planner stacks its own harbours the same way.
			var decor: Array = []
			for record in _list(settlement, "port_decor"):
				if str(record.get("tile", "")) == str(port_tile):
					decor.append(record)
			if not decor.is_empty():
				AuthoredFabricPainter.draw_port_decor(self, decor, _keep_out, true)
				_collect_cranes(decor)
	for settlement in ordered:
		for area in _list(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)
		AuthoredFabricPainter.draw_trees(self, _list(settlement, "trees"))


## Every baked tile whose texture contains `mass_id` needs repainting. A mass can straddle a
## seam, and the bake draws anything reaching a rect, so this asks the same question the bake
## asked: which rects does this record touch, with the same margin.
func _mark_tiles_of_mass(mass_id: String) -> void:
	if not AuthoredBake.is_available():
		return
	var record := _record_by_id(mass_id)
	if record.is_empty():
		return
	var bounds := BakeLayout.bounds_of(record).grow(BakeLayout.CULL_MARGIN)
	for tile_id in AuthoredBake.tiles_in_rect(bounds):
		_dirty_tiles[str(tile_id)] = true


## The decor/special record with this id, or an empty dictionary. Only ever called on eviction
## (a handful of times a match), so it walks rather than holding an index.
func _record_by_id(mass_id: String) -> Dictionary:
	var settlements := AuthoredMap.settlements()
	for key in settlements:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for kind in ["decor", "specials"]:
			for record in _list(settlement_value as Dictionary, kind):
				if str(record.get("id", "")) == mass_id:
					return record
	return {}


## Repaint the tiles an eviction (or a moved harbour) invalidated, through the SAME painter the
## export tool uses, so a repaired tile is indistinguishable from a freshly baked one. This is
## why a mass can be evicted at all under a bake: the texture is re-rendered without it rather
## than patched. One 540x640 render per affected tile, only when something actually changes.
func _repair_evicted_tiles() -> void:
	if _repair_running or _dirty_tiles.is_empty() or not AuthoredBake.is_available():
		return
	# HEADLESS NEVER DRAWS, so there is no repaint to do and no frame to wait for — the
	# handshake below would suspend forever holding a SubViewport, which then dies badly at
	# shutdown (a segfault in the unit suite, which places start buildings and so evicts).
	if DisplayServer.get_name() == "headless":
		_dirty_tiles.clear()
		return
	_repair_running = true
	var pending := _dirty_tiles.keys()
	_dirty_tiles.clear()
	var viewport := SubViewport.new()
	viewport.size = BakeLayout.texture_size()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var painter := BakePainter.new()
	viewport.add_child(painter)
	var settlements := AuthoredMap.settlements()
	for tile_value in pending:
		var tile_id := str(tile_value)
		var rect := AuthoredBake.tile_rect(tile_id)
		if rect.size.x <= 0.0:
			continue
		var records := BakeLayout.records_for_rect(settlements, rect)
		for kind in ["decor", "specials"]:
			var kept: Array = []
			for record in (records[kind] as Array):
				if not _sacrificed.has(str((record as Dictionary).get("id", ""))):
					kept.append(record)
			records[kind] = kept
		# The repaint must apply the SAME cut the bake applied, or a repaired tile would put
		# the town back against the quay while its neighbours still stand clear of it.
		painter.configure("fabric", records, BakeLayout.bake_transform(rect), _keep_out)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			_repainted[tile_id] = ImageTexture.create_from_image(image)
	viewport.queue_free()
	_repair_running = false
	queue_redraw()


## True while any tile whose decorative masses were demolished is still waiting to be re-rendered
## without them. world_map waits on this before revealing the map, so the first frame the player
## sees is already the repaired one.
func has_pending_repairs() -> bool:
	return _repair_running or not _dirty_tiles.is_empty()


## Baked mode streams by camera, so the layer has to notice the camera moving. Costs one rect
## compare per frame when a bake is present, and nothing at all when it isn't.
func _process(_delta: float) -> void:
	if not AuthoredBake.is_available():
		return
	# The repair renders into its OWN SubViewport, so it does not need this layer to be on
	# screen — and it must not wait for that. The loading screen hides the world for the length
	# of the build, and a repair that only started at the reveal would show the player a few
	# frames of town standing where a factory has just been built, then pop.
	if not _dirty_tiles.is_empty():
		_repair_evicted_tiles()
	if not visible:
		return
	var view := AuthoredBake.visible_world_rect(self, STREAM_MARGIN)
	# Not `!=` — see view_stream.gd. This layer is the most expensive of the four.
	if not ViewStream.settled(view, _view_rect, STREAM_MARGIN):
		_view_rect = view
		queue_redraw()


## What the bake deliberately leaves out, drawn as vectors over the textures.
##
## Two kinds, for the same reason — their picture is not fixed at bake time:
##   * masses marked `sacrificial`, which vanish when a gameplay building takes their ground;
##   * HARBOURS and their cargo, cranes and plumbing, which are positioned from a port plan
##     that re-seats with the player's buildings, and whose containers move when a quay does.
## Baking either would freeze a thing that moves. Both are small — the current document marks
## no sacrificial masses and carries one authored harbour — so drawing them live costs nothing
## and keeps eviction and the harbour fit-out working exactly as they do unbaked.
func _draw_dynamic() -> void:
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for mass in _list(settlement, "decor"):
			if bool(mass.get("sacrificial", false)) and not _sacrificed.has(str(mass.get("id", ""))):
				AuthoredFabricPainter.draw_mass(self, mass, _keep_out)
		var harbours: Dictionary = {}
		for special in _list(settlement, "specials"):
			if _sacrificed.has(str(special.get("id", ""))):
				continue
			var port_tile := str(special.get("port", ""))
			if port_tile != "":
				if not harbours.has(port_tile):
					harbours[port_tile] = []
				(harbours[port_tile] as Array).append(special)
			elif bool(special.get("sacrificial", false)):
				AuthoredFabricPainter.draw_special(self, special, _keep_out)
		var harbour_keys := harbours.keys()
		harbour_keys.sort()
		for port_tile in harbour_keys:
			AuthoredFabricPainter.draw_port_group(self, harbours[port_tile],
				str(port_tile), _keep_out)
			var decor: Array = []
			for record in _list(settlement, "port_decor"):
				if str(record.get("tile", "")) == str(port_tile):
					decor.append(record)
			if not decor.is_empty():
				AuthoredFabricPainter.draw_port_decor(self, decor, _keep_out, true)
				_collect_cranes(decor)


## READ-ONLY SEAM FOR AUDITS. Every decorative mass and special this layer is CURRENTLY
## drawing, as world polygons with their ids. Evicted masses are absent, so an audit asking
## "is anything still standing under this port" gets the same answer the screen shows —
## which is the whole point: comparing a plan against the document would keep reporting
## masses that were cleared, and comparing screenshots would mistake a stale frame for a pass.
func visible_mass_polygons() -> Array:
	var out: Array = []
	if not AuthoredMap.is_active():
		return out
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for record in _list(settlement, "decor"):
			if _sacrificed.has(str(record.get("id", ""))):
				continue
			for poly_value in AuthoredFabricPainter.mass_polygons(record):
				for piece in AuthoredFabricPainter.surviving_pieces(
						poly_value as PackedVector2Array, _keep_out):
					_append_visible(out, piece as PackedVector2Array, record)
		for record in _list(settlement, "specials"):
			if _sacrificed.has(str(record.get("id", ""))):
				continue
			for piece in AuthoredFabricPainter.surviving_pieces(
					AuthoredSpecialShapes.render_polygon(record), _keep_out):
				_append_visible(out, piece as PackedVector2Array, record)
	return out


func _append_visible(out: Array, poly: PackedVector2Array, record: Dictionary) -> void:
	if poly.size() < 3:
		return
	var bb := Rect2(poly[0], Vector2.ZERO)
	for point in poly:
		bb = bb.expand(point)
	out.append({"id": str(record.get("id", "")), "poly": poly, "bb": bb})


func _list(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	for value in (settlement.get(key, []) as Array):
		if typeof(value) == TYPE_DICTIONARY:
			out.append(value)
	return out


## The gantry cranes of every authored harbour, gathered while the docks are painted and
## handed to a layer that draws them ABOVE the ships. See authored_port_crane_layer.gd.
var _crane_layer: Node2D = null
var _cranes_this_pass: Array = []


func _collect_cranes(decor: Array) -> void:
	for record_value in decor:
		if str((record_value as Dictionary).get("kind", "")) == "crane":
			_cranes_this_pass.append(record_value)


## Called at the end of a draw pass: publish what was gathered, building the layer on first
## need. A pass that painted no harbour publishes an empty list, which clears the last one.
func _publish_cranes() -> void:
	if _crane_layer == null or not is_instance_valid(_crane_layer):
		_crane_layer = AuthoredPortCraneLayer.new()
		_crane_layer.name = "AuthoredPortCranes"
		add_child(_crane_layer)
	_crane_layer.call("set_cranes", _cranes_this_pass.duplicate())
	_cranes_this_pass = []
