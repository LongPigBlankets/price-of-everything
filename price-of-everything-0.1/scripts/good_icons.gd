## Shared goods-icon loader. The same path pattern was duplicated in
## building_detail_panel.gd and search_overlay.gd. Returns a Texture2D for a
## good (preferring the small art for normal UI thumbnails, falling back to
## medium), or null if no icon exists yet. Most goods have no art, so callers
## must handle null.
##
## Icons are stored ready-to-display: any chroma-key background and watermark
## are baked out ahead of time (see tools/bake_good_icons.gd), and mipmaps are
## generated at import, so loading is just a plain resource load.

const MEDIUM_MIN_DISPLAY_SIZE := 128.0

const _DIRS := ["res://assets/icons/goods/medium", "res://assets/icons/goods/small"]
const _DIRS_SMALL_FIRST := ["res://assets/icons/goods/small", "res://assets/icons/goods/medium"]
const _EXTS := [".png", ".svg", ".PNG", ".SVG"]

static var _texture_cache: Dictionary = {}


## Returns the icon for a good. Normal UI thumbnails default to the lightweight
## "small" variant. Pass prefer_small=false only for displays larger than 128px,
## such as encyclopedia detail images or zoomed-out map/deposit effects.
static func texture_for(good_id: String, internal_name: String, prefer_small := true) -> Texture2D:
	var cache_key := "%s|%s|%s" % ["small" if prefer_small else "medium", good_id, internal_name]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	for dir in (_DIRS_SMALL_FIRST if prefer_small else _DIRS):
		if good_id != "" and internal_name != "":
			var t := _try(dir, "%s_%s" % [good_id, internal_name])
			if t != null:
				_texture_cache[cache_key] = t
				return t
		if good_id != "":
			var t2 := _try(dir, good_id)
			if t2 != null:
				_texture_cache[cache_key] = t2
				return t2
	_texture_cache[cache_key] = null
	return null


static func prefer_small_for_size(display_size: float) -> bool:
	return display_size <= MEDIUM_MIN_DISPLAY_SIZE


static func texture_for_size(good_id: String, internal_name: String, display_size: float) -> Texture2D:
	return texture_for(good_id, internal_name, prefer_small_for_size(display_size))


static func _try(dir: String, stem: String) -> Texture2D:
	for ext in _EXTS:
		var path := "%s/%s%s" % [dir, stem, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## The on-disk path a texture_for(good_id, internal, prefer_small) lookup resolves to,
## or "" if the good has no art. Same search order as texture_for so warming and drawing
## agree on which file each good uses.
static func resolve_path(good_id: String, internal_name: String, prefer_small := true) -> String:
	for dir in (_DIRS_SMALL_FIRST if prefer_small else _DIRS):
		for stem in ([("%s_%s" % [good_id, internal_name]) if (good_id != "" and internal_name != "") else "", good_id]):
			if stem == "":
				continue
			for ext in _EXTS:
				var path := "%s/%s%s" % [dir, stem, ext]
				if ResourceLoader.exists(path):
					return path
	return ""


## Kick off background (worker-thread) loads of these goods' icons so they are ready
## in the ResourceLoader cache before first use. The Goods Graph draws MEDIUM art for
## every good (69 PNGs, ~47 ms each = ~3.2 s of main-thread stall on first open); calling
## this during the loading screen lets the workers load them in parallel with the map
## build so the first open is instant. Then call warm() to populate _texture_cache.
static func warm_async(goods: Array, prefer_small := false) -> void:
	for g in goods:
		var path := resolve_path(str((g as Dictionary).get("id", "")),
			str((g as Dictionary).get("internal_name", "")), prefer_small)
		if path != "":
			ResourceLoader.load_threaded_request(path)


## Populate _texture_cache for these goods (blocking, but fast once warm_async's worker
## loads have landed). Safe to call every load; a fully warmed run is a dictionary scan.
static func warm(goods: Array, prefer_small := false) -> void:
	for g in goods:
		texture_for(str((g as Dictionary).get("id", "")),
			str((g as Dictionary).get("internal_name", "")), prefer_small)
