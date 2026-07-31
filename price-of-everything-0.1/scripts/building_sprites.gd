extends RefCounted
## Loader for the 2.5D isometric building sprites (assets/icons/buildings/sprites/),
## rendered from Blender (see .claude/skills/blender-building-sprites). Files are named
## `<internal_name>_lvl<level>.png`, one per building level, 800x800 with mipmaps.
##
## Coverage is partial while the sprite set is being produced: `texture_for` returns null
## for buildings without a sprite yet, and callers fall back to the classic glyph icons.
## Consumers preload this as `const BuildingSprites := preload("res://scripts/building_sprites.gd")`.

const _DIR := "res://assets/icons/buildings/sprites/"

static var _cache: Dictionary = {}


## The sprite for `internal_name` at `level` (clamped 1..3), falling back to lower
## levels if the exact one is missing; null when the building has no sprites at all.
static func texture_for(internal_name: String, level: int = 1) -> Texture2D:
	if internal_name == "":
		return null
	var lv := clampi(level, 1, 3)
	while lv >= 1:
		var key := "%s_lvl%d" % [internal_name, lv]
		if _cache.has(key):
			if _cache[key] != null:
				return _cache[key]
		else:
			var path := _DIR + key + ".png"
			var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
			_cache[key] = tex
			if tex != null:
				return tex
		lv -= 1
	return null


static var _content_cache: Dictionary = {}


## The texture's opaque CONTENT rect in texture pixels, cached per texture.
##
## The sprites are 800x800 with the building centred inside a transparent margin (the export
## pads to an exact 6px on the long axis, so the SHORT axis carries a lot of empty space). The
## empire view routes lines through that margin but never across the building, so it needs the
## content box, not the texture box. `Image.get_used_rect()` is exactly this, and it is only
## paid once per texture.
static func content_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _content_cache.has(key):
		return _content_cache[key]
	var img: Image = tex.get_image()
	var r := Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			r = Rect2(used.position, used.size)
	_content_cache[key] = r
	return r
