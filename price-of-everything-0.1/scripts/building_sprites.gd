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


static var _npc_cache: Dictionary = {}

## Below this lightness a sprite pixel is linework, drawn in the map's ink.
const _NPC_INK_BELOW := 0.24
## How far a pixel's lightness from the sprite's middle tone moves it along the NPC tone ramp, and the ramp's
## ends: the map's NPC masses run from the base darkened 0.28 (the deepest shade) to lightened 0.20 (lit roofs).
const _NPC_RAMP_GAIN := 1.4
const _NPC_DARKEST := -0.28
const _NPC_LIGHTEST := 0.20


## The sprite as an NPC building: recoloured the way the map colours NPC masses (BuildingVisuals._wash_for and
## InkBuildingGen._remap). The fill is the style's NPC block top (MapStyle.block_top("npc"), paper white); each
## pixel keeps its tone's role, its lightness against the sprite's middle tone placing it on the same ramp the
## map uses (lit faces lightened, shaded faces darkened), and linework stays in the map's ink. Built once per
## sprite at half size and cached; null when the building has no sprite.
static func npc_texture_for(internal_name: String, level: int = 1) -> Texture2D:
	var src := texture_for(internal_name, level)
	if src == null:
		return null
	var key := "%s|%s" % [src.resource_path, str(MapStyle.block_top("npc"))]
	if _npc_cache.has(key):
		return _npc_cache[key]
	var img: Image = src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	var base: Color = MapStyle.block_top("npc")
	var ink: Color = InkBuildingGen._ink()
	var w := img.get_width()
	var h := img.get_height()
	# The sprite's middle tone: the median lightness of its opaque, non-ink pixels.
	var counts := PackedInt32Array()
	counts.resize(256)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.get_luminance() >= _NPC_INK_BELOW:
				counts[int(c.get_luminance() * 255.0)] += 1
	var total := 0
	for n in counts:
		total += n
	var mid := 0.5
	var seen := 0
	for i in 256:
		seen += counts[i]
		if seen * 2 >= total:
			mid = float(i) / 255.0
			break
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := c.get_luminance()
			var out: Color
			if l < _NPC_INK_BELOW:
				out = ink
			else:
				var f := clampf((l - mid) * _NPC_RAMP_GAIN, _NPC_DARKEST, _NPC_LIGHTEST)
				out = base.lightened(f) if f >= 0.0 else base.darkened(-f)
			out.a = c.a
			img.set_pixel(x, y, out)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_npc_cache[key] = tex
	return tex
