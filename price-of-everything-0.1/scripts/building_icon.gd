extends RefCounted
## Runtime cleaner for the building-type icons (assets/icons/buildings/*). Mirrors the goods
## icon bake's colour-keying (tools/bake_good_icons.gd): keys the dark navy background out to
## transparent, trims to the off-white artwork, and centres it in a square so every building
## icon is uniformly square-bounded by its content. Results are cached per building_id.
##
## BAKED, WITH THE RUNTIME CLEAN AS THE FALLBACK. The clean is a per-pixel pass over every
## building icon and measured 2.6 s for the set of 36 — paid on the first Construct-menu open,
## in front of the player, once per session. It is a deterministic image transform over art
## that changes rarely, which is the definition of something to do once, offline:
## tools/bake_building_icons.tscn writes the cleaned PNGs and a manifest of the SOURCE md5s.
##
## Staleness is per icon, not per set. A source PNG whose md5 has moved (or one the bake never
## saw) is cleaned at runtime exactly as before, so adding a building costs that one icon and
## never the wrong picture. The source PNGs — shared with the infrastructure mapmode — are
## left untouched either way. Consumers preload this as
## `const BuildingIcon := preload("res://scripts/building_icon.gd")`.

const InfraIcons := preload("res://scripts/infra_icons.gd")

const BAKE_DIR := "res://assets/icons/buildings/cleaned"
const BAKE_MANIFEST := "res://data/building_icons_bake.json"

static var _manifest: Dictionary = {}
static var _manifest_loaded := false


## building_id -> md5 of the source PNG the bake was made from.
static func manifest() -> Dictionary:
	if _manifest_loaded:
		return _manifest
	_manifest_loaded = true
	if not FileAccess.file_exists(BAKE_MANIFEST):
		return _manifest
	var file := FileAccess.open(BAKE_MANIFEST, FileAccess.READ)
	if file == null:
		return _manifest
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_manifest = parsed
	return _manifest


## The md5 of the source art for this building, or "" when it has none.
static func source_md5(building_id: String, internal_name: String) -> String:
	var path := InfraIcons.source_path_for(building_id, internal_name)
	return FileAccess.get_md5(path) if path != "" else ""


static func baked_path(building_id: String) -> String:
	return "%s/%s.png" % [BAKE_DIR, building_id]


## The baked clean for this building, or null when there is none for THIS source art.
static func _baked(building_id: String, internal_name: String) -> Texture2D:
	var want := str(manifest().get(building_id, ""))
	if want == "" or want != source_md5(building_id, internal_name):
		return null
	var path := baked_path(building_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func reset_for_tests() -> void:
	_cache = {}
	_manifest = {}
	_manifest_loaded = false

# A pixel whose brightest channel is below this is treated as navy background (the icons are
# off-white line art on a ~#001739 navy; off-white sits ~230+, the navy ~60, so this cleanly
# separates them and clears the dark half of the anti-aliased fringe).
const _DARK_MAX := 110

static var _cache: Dictionary = {}

static func clean_texture(building_id: String, internal_name: String) -> Texture2D:
	if _cache.has(building_id):
		return _cache[building_id]
	var tex := _baked(building_id, internal_name)
	if tex == null:
		tex = _bake(building_id, internal_name)   # no bake, or the art moved under it
	_cache[building_id] = tex
	return tex

static func _bake(building_id: String, internal_name: String) -> Texture2D:
	var src := InfraIcons.texture_for(building_id, internal_name)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()  # else get_data() returns base + mipmap levels and the size won't match
	var w := img.get_width()
	var h := img.get_height()

	# Chroma-key the navy background → transparent (byte-array pass, like the goods bake).
	var data := img.get_data()
	var n := w * h
	for idx in n:
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		var maxc := maxi(maxi(int(data[o]), int(data[o + 1])), int(data[o + 2]))
		if maxc < _DARK_MAX:
			data[o + 3] = 0
	var keyed := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)

	# Trim to the artwork's bounding box, then centre it in a square sized by its longest side.
	var used := keyed.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return src
	var sub := keyed.get_region(used)
	var side := maxi(sub.get_width(), sub.get_height())
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ox := int(floor(float(side - sub.get_width()) / 2.0))
	var oy := int(floor(float(side - sub.get_height()) / 2.0))
	out.blit_rect(sub, Rect2i(0, 0, sub.get_width(), sub.get_height()), Vector2i(ox, oy))
	out.fix_alpha_edges()
	out.generate_mipmaps()  # crisp when the ~300px art is shown at the row's icon size
	return ImageTexture.create_from_image(out)
