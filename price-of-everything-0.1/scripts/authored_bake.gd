extends RefCounted
## Runtime reader for the baked authored-map textures (`tools/map_editor/bake_authored_map.gd`).
## Follows the `roads_baked.gd` idiom: a cached manifest, a staleness tripwire, and
## `reset_for_tests()`.
##
## ABSENCE IS NORMAL. With no bake on disk every getter returns empty and `is_available()` is
## false, so the renderers keep drawing vectors exactly as they do today. The bake is an
## optimisation, never a dependency — which is also what makes it safe to delete and re-make.
##
## STALENESS FALLS BACK, IT DOES NOT SHIP THE WRONG PICTURE. If the manifest names a different
## document than the one the game is loading, or the document's md5 has moved since the bake,
## the textures are ignored and the vector path draws instead. Slow and right beats fast and
## wrong, and the warning says exactly which command fixes it.
##
## TEXTURES ARE STREAMED, NOT RESIDENT. 209 tiles at 540×640 RGBA is ~289 MB of VRAM if it were
## all held at once, so callers load only what the camera can see (`texture_for`) and drop the
## rest (`trim`). On disk the same set is ~6.6 MB — flat art over transparency compresses hard —
## so disk size is not the constraint here; VRAM is.

const AuthoredMap := preload("res://scripts/authored_map.gd")

const MANIFEST_PATH := "res://data/map_authored_bake.json"
const REBAKE_HINT := "rerun tools/map_editor/bake_authored_map.tscn"

static var _cache: Dictionary = {}
static var _loaded := false
static var _warned := false
## Cached answer to is_available(). It is asked every frame by both layers, and answering it
## honestly means md5-ing a ~1 MB document — which at 60 fps would burn more time than the whole
## bake saves. The document is read once per run and cannot change under a running match, so the
## verdict is computed once and held (reset_for_tests clears it).
static var _available := -1   # -1 unknown, 0 no, 1 yes
## Resolved texture cache, path -> Texture2D, trimmed to what the camera needs.
static var _textures: Dictionary = {}


## The parsed manifest, or an empty dictionary when there is no bake.
static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _cache   # no bake yet: the vector path handles it
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AuthoredBake: %s did not parse — %s." % [MANIFEST_PATH, REBAKE_HINT])
		return _cache
	_cache = parsed
	return _cache


## True when a usable, current bake exists for the document the game is actually loading.
## Everything that decides between textures and vectors asks this one question.
static func is_available() -> bool:
	if _available >= 0:
		return _available == 1
	_available = 1 if _compute_available() else 0
	return _available == 1


static func _compute_available() -> bool:
	var doc := data()
	if doc.is_empty():
		return false
	var active := AuthoredMap.active_name()
	if active == "":
		return false
	if str(doc.get("document", "")) != active:
		_warn("AuthoredBake: bake is for '%s' but '%s' is active — %s."
			% [str(doc.get("document", "")), active, REBAKE_HINT])
		return false
	var path := AuthoredMap.path_for(active)
	if str(doc.get("source_md5", "")) != FileAccess.get_md5(path):
		_warn("AuthoredBake: '%s' has changed since the bake — drawing vectors instead. %s."
			% [active, REBAKE_HINT])
		return false
	return true


## tile_id -> {"rect": [x, y, w, h], "layers": {layer: res:// path}}. Only tiles with at least
## one non-empty layer appear, so "no entry" and "nothing authored here" are the same case.
static func tiles() -> Dictionary:
	var value: Variant = data().get("tiles", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## The world rect a tile's textures occupy (its pitch rect), or a zero rect when unbaked.
static func tile_rect(tile_id: String) -> Rect2:
	var entry: Variant = tiles().get(tile_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return Rect2()
	var values: Variant = (entry as Dictionary).get("rect", [])
	if typeof(values) != TYPE_ARRAY or (values as Array).size() < 4:
		return Rect2()
	var r: Array = values
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## The texture for one layer of one tile, loaded on demand and held until `trim`. Returns null
## when this tile has nothing on this layer — a normal, common answer, not a failure.
static func texture_for(tile_id: String, layer: String) -> Texture2D:
	var entry: Variant = tiles().get(tile_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	var layers: Variant = (entry as Dictionary).get("layers", {})
	if typeof(layers) != TYPE_DICTIONARY:
		return null
	var path := str((layers as Dictionary).get(layer, ""))
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	if not ResourceLoader.exists(path):
		# A manifest entry whose texture cannot be loaded (deleted, or baked but never
		# `--import`ed) must not leave a HOLE in the map while every other tile draws. One
		# missing texture disables the whole bake for the session, so the vector fallback
		# takes over wholesale — slow and right, exactly like the staleness path.
		_available = 0
		_warn("AuthoredBake: %s is in the manifest but not loadable — falling back to vectors. Run `--headless --import`, or %s." % [path, REBAKE_HINT])
		return null
	var texture: Texture2D = load(path)
	_textures[path] = texture
	return texture


## Drop every held texture whose tile is not in `keep`. Called by the renderers after they have
## drawn, so the resident set tracks the camera instead of growing to the whole map.
static func trim(keep_tile_ids: Dictionary) -> void:
	if _textures.is_empty():
		return
	var wanted: Dictionary = {}
	var all := tiles()
	for tile_id in keep_tile_ids:
		var entry: Variant = all.get(tile_id, null)
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var layers: Variant = (entry as Dictionary).get("layers", {})
		if typeof(layers) != TYPE_DICTIONARY:
			continue
		for layer in (layers as Dictionary):
			wanted[str((layers as Dictionary)[layer])] = true
	for path in _textures.keys():
		if not wanted.has(path):
			_textures.erase(path)


## Preload the textures for a set of tiles — the loading screen calls this for the tiles the
## opening camera will see, so the first frame of play is not a burst of disk reads.
static func warm(tile_ids: Array, layers: Array = ["fabric", "roads"]) -> int:
	if not is_available():
		return 0
	var loaded := 0
	for tile_value in tile_ids:
		for layer in layers:
			if texture_for(str(tile_value), str(layer)) != null:
				loaded += 1
	return loaded


## Every baked tile whose rect meets `world_rect`. The renderers grow the camera rect by a ring
## before asking, so a tile is resident slightly before it is needed rather than popping in.
static func tiles_in_rect(world_rect: Rect2) -> Dictionary:
	var out: Dictionary = {}
	for tile_id in tiles():
		if world_rect.intersects(tile_rect(str(tile_id))):
			out[str(tile_id)] = true
	return out


## The world rect the camera can currently see, grown by `margin` so a tile becomes resident
## slightly before it is needed. Zero-size when there is no viewport yet (during the build).
static func visible_world_rect(canvas: CanvasItem, margin: float) -> Rect2:
	var viewport := canvas.get_viewport()
	if viewport == null:
		return Rect2()
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	return (viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(margin)


## Draw one layer's baked textures for everything inside `view`, then release whatever fell
## outside it. Shared by the fabric and road layers so the streaming rule has one definition.
## Each texture is blitted at its own world rect, so the tiles reassemble exactly as they were
## cut — no scaling, no offsets to get wrong.
## `overrides` (tile_id -> Texture2D) wins over the file for that tile: it is how a tile
## repainted in-match after an eviction replaces the one that shipped.
static func draw_layer(canvas: CanvasItem, layer: String, view: Rect2,
		overrides: Dictionary = {}) -> void:
	if view.size.x <= 0.0:
		return
	var visible := tiles_in_rect(view)
	for tile_id in visible:
		var id := str(tile_id)
		var texture: Texture2D = overrides.get(id, null) if overrides.has(id) else texture_for(id, layer)
		if texture != null:
			canvas.draw_texture_rect(texture, tile_rect(id), false)
	trim(visible)


static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false
	_warned = false
	_available = -1
	_textures = {}


## One warning per run. A stale bake would otherwise print on every redraw of every layer.
static func _warn(message: String) -> void:
	if _warned:
		return
	_warned = true
	push_warning(message)
