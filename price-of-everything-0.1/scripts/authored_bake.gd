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
const Layout := preload("res://scripts/authored_bake_layout.gd")

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
static var _lp_load_us := 0
static var _lp_load_n := 0
## Set by world_map once the world is revealed: from then on missing textures are requested
## from the loader's worker threads rather than decoded on the render frame (see texture_for).
static var stream_async := false
## Threaded requests in flight (path -> true), drained by texture_for and settle_pending.
static var _pending: Dictionary = {}
## The subset of _pending a draw skipped a tile for: their landing repaints (prefetch alone does not).
static var _wanted: Dictionary = {}
## Textures handed to the GPU per settle_pending call — the upload cost stays inside a frame.
const LANDINGS_PER_FRAME := 6
## Threaded requests issued per prefetch call (see prefetch).
const PREFETCH_PER_CALL := 48
## The tier currently being drawn, and the px/unit band that switches it. Entering at the far
## tier's own resolution (BAKE_SCALE) means the near set is fetched exactly when the far one
## would start to be magnified; leaving well below that keeps a camera nudged around the
## threshold from repainting and re-streaming on alternate frames.
static var _tier := Layout.TIER_FAR
const NEAR_ENTER_PPU := 1.333
const NEAR_EXIT_PPU := 1.05
## -1 unknown, 0 no, 1 yes — whether this manifest carries near-tier textures at all.
static var _near_available := -1
## Harness override: "far" or "near" pins the tier; "" lets the zoom decide. See tier_for.
static var force_tier := ""
static var _force_env_read := false
## Bumped whenever a threaded request lands; the streaming layers repaint when it moves.
static var texture_generation := 0
## How far beyond the rect a layer drew its textures are kept resident and prefetched. A
## crossing repaints after a quarter of the layer's own margin, so a ring this wide has had
## several crossings' worth of frames to land before it is asked to draw.
const PREFETCH_RING := 900.0


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
static func texture_for(tile_id: String, layer: String, tier: String = Layout.TIER_FAR) -> Texture2D:
	var path := path_for(tile_id, layer, tier)
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
	# IN PLAY, NEVER DECODE ON THE RENDER FRAME. A stream crossing (the camera drifting a
	# quarter-margin) used to pull a whole band of new tiles through `load()` inside `_draw`
	# — ~30 PNG decodes at once, an 850 ms hitch every few dozen frames of panning. Once the
	# world is revealed the request goes to the loader's worker threads instead; the tile is
	# skipped this frame and drawn when it lands (settle_pending below bumps the generation
	# the streaming layers watch). The loading screen keeps the synchronous path: its first
	# frame must be whole, and nobody is watching it decode.
	if stream_async:
		if _pending.has(path):
			match ResourceLoader.load_threaded_get_status(path):
				ResourceLoader.THREAD_LOAD_LOADED:
					_pending.erase(path)
					_wanted.erase(path)
					var landed: Texture2D = ResourceLoader.load_threaded_get(path)
					_textures[path] = landed
					return landed
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					_pending.erase(path)   # fall through to the synchronous load below
				_:
					_wanted[path] = true   # a draw is waiting on it: its landing must repaint
					return null
		else:
			ResourceLoader.load_threaded_request(path)
			_pending[path] = true
			_wanted[path] = true
			return null
	var _lpt := Time.get_ticks_usec()
	var texture: Texture2D = load(path)
	_lp_load_us += Time.get_ticks_usec() - _lpt
	_lp_load_n += 1
	if _lp_load_n % 25 == 0 and OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF-BAKE %d textures loaded, %.0f ms total   abs=%d" % [_lp_load_n, _lp_load_us / 1000.0, Time.get_ticks_msec()])
	_textures[path] = texture
	return texture


## Collect every threaded texture request that has landed since the last call, and bump
## `texture_generation` when any did. The streaming layers call this once a frame and repaint
## when the generation moves, which is how a tile skipped as "not yet loaded" appears.
static func settle_pending() -> bool:
	if _pending.is_empty():
		return false
	# Only a landing some draw actually WAITED for moves the generation. Prefetched tiles
	# land silently — repainting both streaming layers for a texture nobody has asked to see
	# yet turned a ring prefetch into a repaint every frame for as long as it kept landing.
	# And at most LANDINGS_PER_FRAME are collected per call: load_threaded_get hands the
	# texture to the GPU, and a burst of them is a hitch of its own.
	var landed_wanted := false
	var collected := 0
	for path in _pending.keys():
		if collected >= LANDINGS_PER_FRAME:
			break
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_pending.erase(path)
				_textures[path] = ResourceLoader.load_threaded_get(path)
				collected += 1
				if _wanted.has(path):
					_wanted.erase(path)
					landed_wanted = true
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(path)   # texture_for retries it synchronously next time it is asked
				_wanted.erase(path)
			_:
				pass
	if landed_wanted:
		texture_generation += 1
	return landed_wanted


## Ask the worker threads for every texture of every tile inside `world_rect` that is not
## resident yet. Cheap when nothing is missing — a dictionary walk — so the streaming layers
## call it on every repaint with a ring beyond what they drew, and the band the camera is
## heading into is on the GPU before the next crossing asks for it.
static func prefetch(world_rect: Rect2, layers: Array = ["fabric", "roads"],
		tier: String = Layout.TIER_FAR) -> void:
	if not stream_async or world_rect.size.x <= 0.0:
		return
	# Bounded per call: a zoomed-out view's ring is the whole island, and asking for ~900
	# textures at once was measured as seconds of 5 fps while they streamed onto the GPU.
	# The next repaint asks again, so a large ring fills over a few crossings instead.
	var requested := 0
	for tile_id in tiles_in_rect(world_rect):
		if requested >= PREFETCH_PER_CALL:
			break
		var entry: Variant = tiles().get(str(tile_id), null)
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for layer in layers:
			var path := path_for(str(tile_id), str(layer), tier)
			if path == "" and tier != Layout.TIER_FAR:
				path = path_for(str(tile_id), str(layer))
			if path != "" and not _textures.has(path) and not _pending.has(path) \
					and ResourceLoader.exists(path):
				ResourceLoader.load_threaded_request(path)
				_pending[path] = true
				requested += 1


## Where one tier of one layer of one tile lives, or "" when the bake does not hold it. The
## near tier is a separate map (`layers_near`) rather than a suffixed key, so a manifest
## written before the tier existed reads correctly and simply has no near textures.
static func path_for(tile_id: String, layer: String, tier: String = Layout.TIER_FAR) -> String:
	var entry: Variant = tiles().get(tile_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var key := "layers_near" if tier == Layout.TIER_NEAR else "layers"
	var layers: Variant = (entry as Dictionary).get(key, {})
	if typeof(layers) != TYPE_DICTIONARY:
		return ""
	return str((layers as Dictionary).get(layer, ""))


## Every path this tile holds, across both tiers — what `trim` must keep resident for a tile
## the camera can still see, whichever tier is being drawn.
static func paths_for_tile(tile_id: String) -> Array:
	var out: Array = []
	var entry: Variant = tiles().get(tile_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return out
	for key in ["layers", "layers_near"]:
		var layers: Variant = (entry as Dictionary).get(key, {})
		if typeof(layers) != TYPE_DICTIONARY:
			continue
		for layer in (layers as Dictionary):
			var path := str((layers as Dictionary)[layer])
			if path != "":
				out.append(path)
	return out


## LOGICAL pixels per world unit — the camera's canvas scale, deliberately WITHOUT the
## window stretch.
##
## `stretch/mode="canvas_items"` draws the whole canvas at the base viewport size and then
## scales that image to the window, so a texture is magnified (or not) against the LOGICAL
## resolution; the window stretch blurs the result equally whatever tier was chosen. Including
## it here would have entered the near tier at roughly half the intended zoom on any window
## bigger than the base — loading four times the texture for a mid-zoom view that cannot show
## the detail.
static func pixels_per_unit(canvas: CanvasItem) -> float:
	var viewport := canvas.get_viewport()
	if viewport == null:
		return 0.0
	return viewport.get_canvas_transform().get_scale().x


## Which tier to draw, with hysteresis so a camera resting on the threshold does not swap
## every frame — each swap is a repaint of the whole layer AND a band of texture loads.
##
## The near tier costs 4x the pixels of the far one, so it is entered only where the far
## texture would actually be magnified (its 1.333 px/u), and left again well below that.
static func tier_for(canvas: CanvasItem) -> String:
	# A/B seam for the shot harness. Settable in-process (`force_tier`) as well as by
	# POE_FORCE_TIER, because the honest comparison shoots BOTH tiers in ONE run: two runs get
	# two window sizes out of this engine, and the canvas scale rides on the window, so a pair
	# shot across two processes compares two framings while reporting one camera zoom.
	if force_tier == "" and not _force_env_read:
		_force_env_read = true
		var env := OS.get_environment("POE_FORCE_TIER")
		if Layout.TIERS.has(env):
			force_tier = env
	if force_tier != "" and Layout.TIERS.has(force_tier):
		return force_tier
	if not near_available():
		return Layout.TIER_FAR
	var ppu := pixels_per_unit(canvas)
	if _tier == Layout.TIER_NEAR:
		if ppu < NEAR_EXIT_PPU:
			_tier = Layout.TIER_FAR
	elif ppu >= NEAR_ENTER_PPU:
		_tier = Layout.TIER_NEAR
	return _tier


## Does this bake carry near-tier textures at all? A manifest from before the tier — or a bake
## run with `--tiers=far` — simply draws the far tier everywhere, which is the old behaviour.
static func near_available() -> bool:
	if _near_available >= 0:
		return _near_available == 1
	_near_available = 0
	if is_available():
		for tile_id in tiles():
			var entry: Variant = tiles()[tile_id]
			if typeof(entry) == TYPE_DICTIONARY \
					and typeof((entry as Dictionary).get("layers_near", null)) == TYPE_DICTIONARY \
					and not ((entry as Dictionary)["layers_near"] as Dictionary).is_empty():
				_near_available = 1
				break
	return _near_available == 1


## Drop every held texture whose tile is not in `keep`. Called by the renderers after they have
## drawn, so the resident set tracks the camera instead of growing to the whole map.
static func trim(keep_tile_ids: Dictionary) -> void:
	if _textures.is_empty():
		return
	var wanted: Dictionary = {}
	for tile_id in keep_tile_ids:
		for path in paths_for_tile(str(tile_id)):
			wanted[str(path)] = true
	for path in _textures.keys():
		if not wanted.has(path):
			_textures.erase(path)


## Preload the textures for a set of tiles — the loading screen calls this for the tiles the
## opening camera will see, so the first frame of play is not a burst of disk reads.
## Ask the worker threads to read these tiles NOW, and return immediately.
##
## Reading the opening view off disk is 0.8-2.8 s depending on what the OS has cached, and on
## the main thread every millisecond of that is a frozen loading screen. It is pure I/O plus a
## PNG decode, which is what ResourceLoader's threaded path is for. Kick this early; `warm`
## below then collects the results, and a request that has already landed costs a dictionary
## lookup. Same pattern as good_icons.warm_async.
static func warm_async(tile_ids: Array, layers: Array = ["fabric", "roads"]) -> void:
	if not is_available():
		return
	for tile_value in tile_ids:
		var entry: Variant = tiles().get(str(tile_value), null)
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_layers: Variant = (entry as Dictionary).get("layers", {})
		if typeof(entry_layers) != TYPE_DICTIONARY:
			continue
		for layer in layers:
			var path := str((entry_layers as Dictionary).get(str(layer), ""))
			if path != "" and not _textures.has(path) and ResourceLoader.exists(path):
				ResourceLoader.load_threaded_request(path)


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
		overrides: Dictionary = {}, tier: String = Layout.TIER_FAR) -> void:
	if view.size.x <= 0.0:
		return
	var visible := tiles_in_rect(view)
	for tile_id in visible:
		var id := str(tile_id)
		var texture: Texture2D = null
		if overrides.has(id):
			texture = overrides.get(id, null)   # a tile repainted in-match wins at either tier
		else:
			texture = texture_for(id, layer, tier)
			if texture == null and tier != Layout.TIER_FAR:
				texture = texture_for(id, layer)   # near not baked for this tile: far still reads
		if texture != null:
			canvas.draw_texture_rect(texture, tile_rect(id), false)
	# Resident set = what was drawn plus a ring the camera is heading into; the ring is also
	# what gets prefetched, so a crossing finds its new band already on the GPU.
	var ring := view.grow(PREFETCH_RING)
	prefetch(ring, [layer], tier)
	trim(tiles_in_rect(ring))


static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false
	_warned = false
	_available = -1
	_textures = {}
	_pending = {}
	_wanted = {}
	stream_async = false
	texture_generation = 0
	_tier = Layout.TIER_FAR
	_near_available = -1
	force_tier = ""
	_force_env_read = false


## One warning per run. A stale bake would otherwise print on every redraw of every layer.
static func _warn(message: String) -> void:
	if _warned:
		return
	_warned = true
	push_warning(message)
