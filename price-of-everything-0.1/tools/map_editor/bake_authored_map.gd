extends Node
## Bakes an authored-map document into per-tile textures — the repeatable "extract the JSON,
## cut it into tiles, render each one" step. EDITOR/TOOL ONLY, and WINDOWED ONLY: `--headless`
## draws nothing, so a headless run would write transparent PNGs over good ones (it refuses).
##
##   <godot> --path . res://tools/map_editor/bake_authored_map.tscn --quit-after 600000 \
##       -- --doc=stoneshore-procedural
##
## Options
##   --doc=<name>     document to bake (default: whichever `active.txt` names)
##   --tiles=a,b,c    bake only these tiles (incremental — everything else is left alone)
##   --layers=a,b     subset of {fabric,roads} (default: both)
##   --dry-run        report the partition and what WOULD be written, render nothing
##
## What it writes
##   assets/authored_map/<doc>/<layer>/<tile_id>.png   one texture per tile per layer
##   data/map_authored_bake.json                       the manifest the runtime reads
##
## THE BAKE IS DERIVED; THE JSON IS THE SOURCE OF TRUTH. Never hand-edit the output. The
## manifest carries the document's md5 so the game can warn when the bake trails the document
## (the `roads_baked` staleness idiom).
##
## MODULAR BY DOCUMENT. Output is namespaced per document name and the manifest records which
## one it came from, so a second region is baked by pointing `--doc` at its file — no shared
## global index to merge and nothing to renumber.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const BakeLayout := preload("res://scripts/authored_bake_layout.gd")
const FabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const RoadPainter := preload("res://scripts/authored_road_painter.gd")
const BakePainter := preload("res://scripts/authored_bake_painter.gd")

const OUT_ROOT := "res://assets/authored_map"
const MANIFEST_PATH := "res://data/map_authored_bake.json"
const MANIFEST_VERSION := 1
const ALL_LAYERS: Array[String] = ["fabric", "roads"]

var _doc_name := ""
var _only_tiles: Dictionary = {}
var _layers: Array[String] = ALL_LAYERS.duplicate()
var _dry_run := false


func _ready() -> void:
	_parse_options()
	if DisplayServer.get_name() == "headless":
		push_error("[BAKE] windowed only — a headless run renders nothing. Drop --headless.")
		get_tree().quit(1)
		return
	# The painters read live style getters (road bridge colour, midcentury palettes), so the
	# bake has to run in the style the game draws the authored map in, not whatever the tool
	# scene happens to boot with.
	MapStyle.set_midcentury(true)

	if _doc_name != "":
		AuthoredMap.set_override(_doc_name)
	var name := AuthoredMap.active_name()
	if name == "":
		push_error("[BAKE] no document selected — pass --doc=<name> or set active.txt")
		get_tree().quit(1)
		return
	var settlements := AuthoredMap.settlements()
	if settlements.is_empty():
		# Empty means the loader REJECTED the document (it warns why) or it authors nothing.
		push_error("[BAKE] '%s' loaded as empty — nothing to bake (see any warning above)" % name)
		get_tree().quit(1)
		return
	print("[BAKE] document '%s'" % name)

	var centres := _tile_centres(settlements)
	if centres.is_empty():
		push_error("[BAKE] could not resolve tile centres from the terrain layer")
		get_tree().quit(1)
		return
	await _bake_all(name, settlements, centres)
	get_tree().quit(0)


## Tile centres straight from the engine. The terrain layer is the coordinate authority
## (docs/map-editor-plan.md §2 — never digit arithmetic on tile ids), but building the world
## costs ~90 s, and none of it is needed to ask where a cell is. So the scene is INSTANTIATED
## AND NEVER ADDED TO THE TREE: `_ready` (the whole world build) never runs, while
## `map_to_local` works off the TileSet the scene file already carries.
func _tile_centres(settlements: Dictionary) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		return {}
	var scene := packed.instantiate()
	var terrain: Node = scene.get_node_or_null(NodePath("TerrainLayer"))
	var out: Dictionary = {}
	if terrain != null:
		# EVERY tile, not just the ones the settlements declare.
		#
		# A settlement's `tiles` list says what it is made OF; it does not bound where its
		# geometry goes. A connector road is authored precisely to run from one settlement's
		# tiles out towards a neighbour, and records_for_rect culls with CULL_MARGIN of slack
		# besides. Tiles beyond the declared list were never offered to the baker, so they got
		# no texture — and the runtime only ever iterates the manifest, so the stroke stopped
		# dead at the last declared tile's edge. That straight cut is the road clipping the
		# owner reported (25 Aug): 33 of 323 road strokes had points on no baked tile, one of
		# them every point it had.
		#
		# Offering all of them costs nothing in output: _bake_all already skips a tile whose
		# layers all come back empty, so the manifest still holds exactly the tiles with
		# content on them. It costs one records_for_rect per world tile at bake time.
		# Straight off the terrain's own cells, which is the coordinate authority the plan
		# names (docs/map-editor-plan.md §2) and is already in the scene file, so this still
		# needs nothing built.
		for cell_value: Variant in terrain.call("get_used_cells"):
			var map_coord: Vector2i = cell_value
			var coord: Vector2i = terrain.call("tile_coord_for_map_coord", map_coord)
			var tile_id := "tile_%d_%d" % [coord.x + 1, coord.y + 1]
			if out.has(tile_id):
				continue
			out[tile_id] = terrain.call("map_to_local", map_coord)
	scene.free()
	return out


func _bake_all(doc_name: String, settlements: Dictionary, centres: Dictionary) -> void:
	var tex_size := BakeLayout.texture_size()
	var tile_ids := centres.keys()
	tile_ids.sort()   # deterministic order, so two runs write the same bytes in the same order

	# One viewport reused for every render: creating 278 of them is pure overhead, and
	# UPDATE_ONCE + an explicit frame handshake per tile keeps them independent anyway.
	var viewport := SubViewport.new()
	viewport.size = tex_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var painter := BakePainter.new()
	viewport.add_child(painter)

	# The harbours' keep-out is baked IN, straight from the document, so a fresh bake already
	# shows the town stopping short of the quay instead of waiting for the runtime repaint.
	var keep_out := BakeLayout.port_keep_out(settlements)
	if not keep_out.is_empty():
		print("[BAKE] cutting fabric around %d harbour region(s)" % keep_out.size())

	var manifest_tiles: Dictionary = {}
	var written := 0
	var skipped := 0
	var bytes := 0
	for tile_value in tile_ids:
		var tile_id := str(tile_value)
		if not _only_tiles.is_empty() and not _only_tiles.has(tile_id):
			continue
		var rect: Rect2 = BakeLayout.pitch_rect(centres[tile_id])
		var records := BakeLayout.records_for_rect(settlements, rect)
		var entry: Dictionary = {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "layers": {}}
		for layer in _layers:
			var layer_records := _records_for_layer(records, layer)
			if BakeLayout.is_empty(layer_records):
				skipped += 1
				continue   # nothing static reaches this tile on this layer — no texture, no entry
			var path := "%s/%s/%s/%s.png" % [OUT_ROOT, doc_name, layer, tile_id]
			if not _dry_run:
				var size := await _render(viewport, painter, layer, layer_records, rect, path,
					keep_out)
				if size < 0:
					push_warning("[BAKE] %s failed to write" % path)
					continue
				bytes += size
			(entry["layers"] as Dictionary)[layer] = path
			written += 1
		if not (entry["layers"] as Dictionary).is_empty():
			manifest_tiles[tile_id] = entry
	viewport.queue_free()

	print("[BAKE] %d texture(s) %s, %d empty layer(s) skipped, %.1f MB" % [
		written, "planned" if _dry_run else "written", skipped, float(bytes) / 1048576.0])
	if _dry_run:
		print("[BAKE] dry run — no files written, no manifest")
		return
	_write_manifest(doc_name, manifest_tiles)


## Render one layer of one tile and save it. Returns the file size in bytes, or -1 on failure.
func _render(viewport: SubViewport, painter: Node2D, layer: String, records: Dictionary,
		rect: Rect2, path: String, keep_out: Array = []) -> int:
	painter.configure(layer, records, BakeLayout.bake_transform(rect), keep_out)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The handshake `hill_visuals._bake_to_texture` uses: let the viewport run its single
	# frame, then take the pixels only after the draw has actually landed.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return -1
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return int(size)


## Split the tile's record bundle into just the kinds one layer draws. Fabric and roads mount
## at different depths in the scene (buildings and rivers draw between them), so they cannot
## share a texture however tempting the halved file count is.
func _records_for_layer(records: Dictionary, layer: String) -> Dictionary:
	var out: Dictionary = {}
	if layer == "roads":
		out["roads"] = records.get("roads", [])
		return out
	for kind in BakeLayout.FABRIC_ORDER:
		out[kind] = records.get(kind, [])
	return out


func _write_manifest(doc_name: String, tiles: Dictionary) -> void:
	var doc: Dictionary = {
		"version": MANIFEST_VERSION,
		"document": doc_name,
		"source_md5": FileAccess.get_md5(AuthoredMap.path_for(doc_name)),
		"hills_hash": HillBaked.source_hash(),
		"bake_scale": BakeLayout.BAKE_SCALE,
		"texture_size": [BakeLayout.texture_size().x, BakeLayout.texture_size().y],
		"tiles": tiles,
	}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[BAKE] could not write %s" % MANIFEST_PATH)
		return
	file.store_string(JSON.stringify(doc, "  ", true))
	file.close()
	print("[BAKE] wrote %s (%d tile(s))" % [MANIFEST_PATH, tiles.size()])


func _parse_options() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--doc="):
			_doc_name = text.substr(6)
		elif text.begins_with("--tiles="):
			for tile in text.substr(8).split(",", false):
				_only_tiles[str(tile).strip_edges()] = true
		elif text.begins_with("--layers="):
			_layers = []
			for layer in text.substr(9).split(",", false):
				var name := str(layer).strip_edges()
				if ALL_LAYERS.has(name):
					_layers.append(name)
		elif text == "--dry-run":
			_dry_run = true
