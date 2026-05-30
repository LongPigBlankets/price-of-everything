## Shared goods-icon loader. The same path pattern was duplicated in
## building_detail_panel.gd and search_overlay.gd. Returns a Texture2D for a
## good (preferring the medium art, falling back to small), or null if no icon
## exists yet. Most goods have no art, so callers must handle null.

const _DIRS := ["res://assets/icons/goods/medium", "res://assets/icons/goods/small"]
const _EXTS := [".png", ".svg", ".PNG", ".SVG"]


static func texture_for(good_id: String, internal_name: String) -> Texture2D:
	for dir in _DIRS:
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
