extends RefCounted
## Runtime reader for the baked far-zoom hill texture (tools/bake_hill_texture.tscn).
## Same idiom as `authored_bake.gd` and `hill_baked.gd`: a cached manifest, a staleness
## tripwire, and a fallback that is slower but never wrong.
##
## WHY IT EXISTS. HillVisuals draws the whole relief as ONE texture whenever enough of the
## map is on screen (its far-zoom LOD), and that texture used to be rendered at every game
## start: a single-frame SubViewport pass over ~1,300 contours, ~5 s on the load. The
## contours come off disk (data/hills_baked.json) and the palette is a constant, so the
## result is identical on every run of a given build — precisely the shape of thing that
## should be rendered once, offline, and loaded thereafter.
##
## ABSENCE IS NORMAL. With no bake on disk `texture()` returns null and HillVisuals falls
## back to rendering it live, exactly as it did before. The bake is an optimisation, never
## a dependency, which is what makes it safe to delete and re-make.
##
## IT IS PALETTE-SPECIFIC. The texture holds baked-in colours, so it is only valid for the
## style it was rendered in. The style key is stored beside it and compared on load; the
## `toggle ink` cheat moves off the baked style and takes the live path.

const MANIFEST_PATH := "res://data/hills_texture_bake.json"
const TEXTURE_PATH := "res://assets/baked/hills_far_zoom.png"
const REBAKE_HINT := "rerun tools/bake_hill_texture.tscn"
## Bumped when the bake's meaning changes (painter, scale, what goes into the picture) so
## an old file on disk is rejected rather than believed.
const BAKE_VERSION := 1
## Tolerance, world units, on the stored bake rect. It is recomputed from the same baked
## polygons every run, so it should match to the bit; this only guards float formatting.
const RECT_EPSILON := 0.5

static var _cache: Dictionary = {}
static var _loaded := false
static var _texture: Texture2D = null
static var _texture_tried := false
static var _warned := false


## The palette identity a bake is valid for. Called by HillVisuals (live style) and by the
## baker (the style it rendered in) so the two spellings cannot drift.
static func style_key(ink: bool, plate: bool, midcentury: bool) -> String:
	return "ink=%s|plate=%s|mid=%s" % [str(ink), str(plate), str(midcentury)]


## The parsed manifest, or an empty dictionary when there is no bake.
static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _cache   # no bake yet: the live render handles it
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("HillTextureBaked: %s did not parse — %s." % [MANIFEST_PATH, REBAKE_HINT])
		return _cache
	_cache = parsed
	return _cache


## The baked texture for this style and this bake rect, or null when there is no usable
## bake — in which case the caller renders its own, as it always did.
##
## Every mismatch below means the picture on disk is NOT a picture of the map we are about
## to draw, so it is refused rather than shown: wrong contours, wrong palette or wrong
## framing would each put a visibly wrong relief under the whole map.
static func texture(style: String, bake_rect: Rect2) -> Texture2D:
	var doc := data()
	if doc.is_empty():
		return null
	if int(doc.get("bake_version", -1)) != BAKE_VERSION:
		_warn("HillTextureBaked: bake is version %s, this build wants %d — %s."
			% [str(doc.get("bake_version", "?")), BAKE_VERSION, REBAKE_HINT])
		return null
	if str(doc.get("source_hash", "")) != HillBaked.source_hash():
		_warn("HillTextureBaked: the hills have changed since the texture was baked — %s."
			% REBAKE_HINT)
		return null
	if str(doc.get("style", "")) != style:
		# Not a fault: the `toggle ink` cheat legitimately moves off the baked palette.
		return null
	var stored := _rect_of(doc.get("rect", []))
	if not _rects_match(stored, bake_rect):
		_warn("HillTextureBaked: baked framing %s does not match this map's %s — %s."
			% [str(stored), str(bake_rect), REBAKE_HINT])
		return null
	return _load_texture()


static func _load_texture() -> Texture2D:
	if _texture_tried:
		return _texture
	_texture_tried = true
	if not ResourceLoader.exists(TEXTURE_PATH):
		# Baked but never imported: Godot only sees a PNG under res:// once it has an
		# .import sidecar. Say so precisely, because "run --import" is the whole fix.
		_warn("HillTextureBaked: %s is not loadable — run `--headless --import`, or %s."
			% [TEXTURE_PATH, REBAKE_HINT])
		return null
	_texture = load(TEXTURE_PATH) as Texture2D
	return _texture


static func _rect_of(value: Variant) -> Rect2:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 4:
		return Rect2()
	var a: Array = value
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func _rects_match(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) <= RECT_EPSILON \
		and absf(a.position.y - b.position.y) <= RECT_EPSILON \
		and absf(a.size.x - b.size.x) <= RECT_EPSILON \
		and absf(a.size.y - b.size.y) <= RECT_EPSILON


## Drop the cached manifest + texture so a re-bake is picked up (tools/tests).
static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false
	_texture = null
	_texture_tried = false
	_warned = false


static func _warn(message: String) -> void:
	if _warned:
		return   # once per run: this is called from a draw path
	_warned = true
	push_warning(message)
	print(message)
