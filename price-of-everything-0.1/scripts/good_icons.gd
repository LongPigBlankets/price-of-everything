## Shared goods-icon loader. The same path pattern was duplicated in
## building_detail_panel.gd and search_overlay.gd. Returns a Texture2D for a
## good (preferring the medium art, falling back to small), or null if no icon
## exists yet. Most goods have no art, so callers must handle null.
##
## Icons are stored ready-to-display: any chroma-key background and watermark
## are baked out ahead of time (see tools/bake_good_icons.gd), and mipmaps are
## generated at import, so loading is just a plain resource load.

const _DIRS := ["res://assets/icons/goods/medium", "res://assets/icons/goods/small"]
const _DIRS_SMALL_FIRST := ["res://assets/icons/goods/small", "res://assets/icons/goods/medium"]
const _EXTS := [".png", ".svg", ".PNG", ".SVG"]


## Returns the icon for a good. Pass prefer_small=true from the dense requirement
## diagrams (recipe rows, construction material grids) so they use the lightweight
## ~256px "small" variant when one exists, falling back to the medium master.
static func texture_for(good_id: String, internal_name: String, prefer_small := false) -> Texture2D:
	for dir in (_DIRS_SMALL_FIRST if prefer_small else _DIRS):
		if good_id != "" and internal_name != "":
			var t := _try(dir, "%s_%s" % [good_id, internal_name])
			if t != null:
				return t
		if good_id != "":
			var t2 := _try(dir, good_id)
			if t2 != null:
				return t2
	return null


static func _try(dir: String, stem: String) -> Texture2D:
	for ext in _EXTS:
		var path := "%s/%s%s" % [dir, stem, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null
