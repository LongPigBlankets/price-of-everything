extends Node2D
# Deposits mapmode. While active it draws each surveyed tile's deposit as a
# world-space icon (sized 150px when fully zoomed in, 450px when fully zoomed
# out). Unsurveyed tiles instead show a question mark — navy on land, off-white
# on the sea — which is swapped for the real icon the moment the tile is
# surveyed (including mid-turn, while the mapmode stays open). Hovering a
# surveyed deposit floats the recipe-diagram quantity pill above it (the amount,
# ∞ for a permanent deposit, or ??? while only partially surveyed).

const GoodIcons := preload("res://scripts/good_icons.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const QUESTION_FONT: Font = preload("res://assets/fonts/BebasNeue-Regular.ttf")

const ICON_WORLD_ZOOMED_IN := 150.0   # world px at full zoom-in
const ICON_WORLD_ZOOMED_OUT := 450.0  # world px at full zoom-out
const PILL_HEIGHT := 28
const PILL_TEXT_SIZE := 16
const PILL_GAP := 6.0                  # screen px between icon top and pill bottom
const PILL_CENTER_INSET := 10.0        # screen px the pill is pulled toward the icon centre
const INFINITY_GLYPH := "∞"

# Unsurveyed-tile question marks.
const QUESTION_GLYPH := "?"
const QUESTION_LAND_COLOR := Color(0.0, 0.119856, 0.243095, 1.0)  # navy
const QUESTION_SEA_COLOR := Color(0.995234, 0.930806, 0.763265, 1.0)  # off-white
const QUESTION_SHADOW := Color(0.0, 0.0, 0.0, 0.5)
const QUESTION_FONT_FRACTION := 0.95   # glyph size vs the icon box

const EXHAUSTED_GREY := Color(0.66, 0.68, 0.70, 0.95)  # placeholder disc for mined-out deposits

const BUILDING_ICON_DIR := "res://assets/icons/buildings"
const OVERLAY_BUILDING_FRACTION := 1.0 / 3.0   # building badge size vs the icon

# Deposits with no good art of their own borrow another good's icon (and may
# stamp a small building badge). Shale oil shows the crude-oil icon with the
# hydraulic-fracking derrick (b_034) superimposed on its bottom-left corner.
const DEPOSIT_ICON_OVERRIDE := {
	"shale_oil": {"good_id": "g_026", "internal": "crude_oil", "building": "b_034"},
}

# Cluster offsets (fraction of tile) when a tile holds several deposits.
const CLUSTER_OFFSETS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-0.22, 0), Vector2(0.22, 0)],
	3: [Vector2(0, -0.22), Vector2(-0.22, 0.18), Vector2(0.22, 0.18)],
	4: [Vector2(-0.22, -0.22), Vector2(0.22, -0.22), Vector2(-0.22, 0.22), Vector2(0.22, 0.22)],
}

@onready var terrain_layer: HexMap = %TerrainLayer

var _active := false
var _deposit_tiles: Array = []        # entries: unknown {kind,center,is_sea} or deposit {kind,center,deposits}
var _deposits_by_id := {}             # tile_id -> entry above
var _texture_cache := {}              # good_id -> Texture2D / null
var _building_cache := {}             # building_id -> Texture2D / null
var _grey_cache := {}                 # cache_key -> desaturated Texture2D / null
var _last_zoom := -1.0                # redraw only when the zoom (and so icon size) changes

# HUD root used to detect when a panel is under the cursor (it must swallow the
# hover so no pill appears over the TVP, building details, mapmodes panel, etc.).
var _hud_content: Control = null
var _hud_resolved := false

var _pill_layer: CanvasLayer = null
var _pills: Array = []                # [{pill: Control, world_pos: Vector2}]
var _hovered_id := ""

func _ready() -> void:
	_pill_layer = CanvasLayer.new()
	_pill_layer.layer = 50              # above the map, below nothing in particular
	add_child(_pill_layer)
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	Production.turn_processed.connect(_on_turn_processed)
	# Survey completing mid-turn must swap a "?" for the real icon without the
	# player having to reopen the mapmode.
	MatchState.surveyed_tiles_changed.connect(_on_survey_changed)
	# A deposit reaching 0 mid-turn must grey out right away.
	MatchState.deposits_changed.connect(_on_deposits_changed)
	# Un-ticking a deposit in the Deposits panel hides it.
	MapMode.deposit_filter_changed.connect(func() -> void: _on_deposits_changed(""))

func _on_selections_changed(mode: int, _selections: Array) -> void:
	if mode == MapMode.Mode.DEPOSITS:
		_activate()
	else:
		_deactivate()

func _on_mode_cleared() -> void:
	_deactivate()

func _on_turn_processed(_summary: Dictionary) -> void:
	if _active:
		_rebuild_tiles()       # deposits can deplete / get mined out
		queue_redraw()

func _on_survey_changed() -> void:
	if _active:
		_rebuild_tiles()       # a tile became (partially) surveyed — reveal its icon
		queue_redraw()

func _on_deposits_changed(_tile_id: String) -> void:
	if _active:
		_rebuild_tiles()       # a deposit depleted — grey it / update its size
		queue_redraw()

func _activate() -> void:
	_active = true
	_rebuild_tiles()
	queue_redraw()

func _deactivate() -> void:
	_active = false
	_hovered_id = ""
	_clear_pills()
	_deposit_tiles.clear()
	_deposits_by_id.clear()
	queue_redraw()

# ── Tile / deposit collection (static per turn) ───────────────────────────────

func _rebuild_tiles() -> void:
	_deposit_tiles.clear()
	_deposits_by_id.clear()
	if terrain_layer == null:
		return
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var tile_id: String = tile_data.get("id", "")
		if tile_id == "":
			continue
		var tile_type := str(tile_data.get("type", ""))
		var unsurveyed := MatchState.survey_status(tile_id, tile_type) == "unsurveyed"
		# On unsurveyed tiles only individually-revealed deposits are shown.
		var deposits := _visible_deposits(tile_id, tile_data, unsurveyed)
		var entry: Dictionary
		if unsurveyed and deposits.is_empty():
			# Nothing revealed — a question mark stands in for the deposit.
			entry = {
				"tile_id": tile_id,
				"kind": "unknown",
				"center": _tile_world_pos(coord),
				"is_sea": tile_type == "sea" or tile_type == "deep_sea",
			}
		elif deposits.is_empty():
			continue
		else:
			entry = {
				"tile_id": tile_id,
				"kind": "deposits",
				"center": _tile_world_pos(coord),
				"deposits": deposits,
			}
		_deposit_tiles.append(entry)
		_deposits_by_id[tile_id] = entry

# Returns the deposits to show on a tile: each as {good_id, internal_name,
# building, token, size_text}. Water is excluded (it has its own Water mapmode)
# and mined-out deposits are dropped.
func _visible_deposits(tile_id: String, tile_data: Dictionary, revealed_only: bool = false) -> Array:
	var out: Array = []
	for r in TileViewData.deposits_summary(tile_id, tile_data):
		var token := str(r.get("deposit_token", ""))
		if token == "water":
			continue  # pure water now lives in the Water mapmode
		if revealed_only and not MatchState.is_deposit_revealed(tile_id, token):
			continue  # unsurveyed tile — only individually-revealed deposits show
		# Mined-out deposits stay on the map but go grey (rather than vanishing).
		var exhausted := MatchState.deposit_remaining_for(tile_id, token) == 0
		var good_id := str(r.get("good_id", ""))
		var internal := str(r.get("internal_name", ""))
		var building := ""
		if DEPOSIT_ICON_OVERRIDE.has(token):
			var ov: Dictionary = DEPOSIT_ICON_OVERRIDE[token]
			good_id = ov.good_id
			internal = ov.internal
			building = ov.building
		if MapMode.is_deposit_hidden(good_id):
			continue  # un-ticked in the Deposits panel
		out.append({
			"good_id": good_id,
			"internal_name": internal,
			"building": building,
			"token": token,
			"exhausted": exhausted,
			"size_text": _size_text(tile_id, tile_data, r, exhausted),
		})
	return out

# Surveyed amount (0 when exhausted), ∞ for permanent, or ??? while unknown.
func _size_text(tile_id: String, tile_data: Dictionary, row: Dictionary, exhausted: bool) -> String:
	if exhausted:
		return "0"  # mined out — the amount is known to be zero
	var status: String = MatchState.survey_status(tile_id, str(tile_data.get("type", "")))
	if status != "surveyed":
		return "???"
	var remaining: int = MatchState.deposit_remaining_for(tile_id, str(row.get("deposit_token", "")))
	var n := remaining if remaining > 0 else int(row.get("qty", -1))
	return str(n) if n >= 0 else INFINITY_GLYPH

# ── Drawing the icons (world space, scales with zoom) ──────────────────────────

func _draw() -> void:
	if not _active:
		return
	var icon := _icon_world_size()
	var tile := _tile_size()
	for entry in _deposit_tiles:
		if entry.kind == "unknown":
			_draw_question_mark(entry.center, bool(entry.is_sea), icon)
			continue
		var deposits: Array = entry.deposits
		var positions := _icon_positions(entry.center, deposits.size(), tile)
		var sz := icon if deposits.size() <= 1 else icon * 0.72
		var h := sz * 0.5
		for i in deposits.size():
			var pos: Vector2 = positions[i]
			var dep: Dictionary = deposits[i]
			var exhausted := bool(dep.get("exhausted", false))
			var good_id := str(dep.good_id)
			var tex := _texture_for(good_id, str(dep.internal_name))
			# Mined-out deposits show a desaturated light-grey icon.
			if exhausted and tex != null:
				tex = _grey_texture(tex, "g_" + good_id)
			if tex != null:
				# Preserve the texture's aspect ratio inside the sz×sz box.
				var rect := _fitted_rect(tex, pos, sz)
				draw_texture_rect(tex, rect, false)
				if str(dep.building) != "":
					_draw_building_badge(str(dep.building), rect, exhausted)
			else:
				# No art for this deposit good — draw an on-theme placeholder disc.
				var disc: Color = EXHAUSTED_GREY if exhausted else UIHelpers.PILL_NAVY
				draw_circle(pos, h * 0.8, disc)
				draw_arc(pos, h * 0.8, 0.0, TAU, 28, UIHelpers.PILL_PAPER, maxf(2.0, h * 0.06))

# A centred question mark (navy on land, off-white on sea) with a drop shadow so
# it reads against low-contrast terrain. Stands in for an unsurveyed deposit.
func _draw_question_mark(center: Vector2, is_sea: bool, icon_world: float) -> void:
	var font_size := int(maxf(8.0, icon_world * QUESTION_FONT_FRACTION))
	var sz := QUESTION_FONT.get_string_size(QUESTION_GLYPH, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := QUESTION_FONT.get_ascent(font_size)
	# Baseline so the glyph's bounding box is centred on the tile.
	var baseline := center - sz * 0.5 + Vector2(0.0, ascent)
	var shadow_off := Vector2(1.0, 1.0) * (icon_world * 0.04)
	var color := QUESTION_SEA_COLOR if is_sea else QUESTION_LAND_COLOR
	draw_string(QUESTION_FONT, baseline + shadow_off, QUESTION_GLYPH,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, QUESTION_SHADOW)
	draw_string(QUESTION_FONT, baseline, QUESTION_GLYPH,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

# Centred rect that fits a texture inside a square box, keeping its aspect ratio.
func _fitted_rect(tex: Texture2D, center: Vector2, box: float) -> Rect2:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var s := box / maxf(1.0, maxf(tw, th))
	var size := Vector2(tw * s, th * s)
	return Rect2(center - size * 0.5, size)

# Small building icon stamped into the bottom-left corner of a deposit icon.
func _draw_building_badge(building_id: String, base_rect: Rect2, exhausted: bool = false) -> void:
	var tex := _building_texture(building_id)
	if tex == null:
		return
	if exhausted:
		tex = _grey_texture(tex, "b_" + building_id)
	var box := maxf(base_rect.size.x, base_rect.size.y) * OVERLAY_BUILDING_FRACTION
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var s := box / maxf(1.0, maxf(tw, th))
	var size := Vector2(tw * s, th * s)
	var origin := Vector2(base_rect.position.x, base_rect.end.y - size.y)
	draw_texture_rect(tex, Rect2(origin, size), false)

# Desaturated, lightened copy of a texture (a "greyed-out" look), cached by key.
func _grey_texture(src: Texture2D, key: String) -> Texture2D:
	if _grey_cache.has(key):
		return _grey_cache[key]
	var result: Texture2D = src
	var img := src.get_image() if src != null else null
	if img != null:
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		# Cap the working size so the pixel loop stays cheap (icons draw small).
		var w := img.get_width()
		var h := img.get_height()
		var cap := 256
		if maxi(w, h) > cap:
			var sc := float(cap) / float(maxi(w, h))
			img.resize(maxi(1, int(w * sc)), maxi(1, int(h * sc)), Image.INTERPOLATE_BILINEAR)
		img.clear_mipmaps()  # so get_data() returns only the base level
		var data := img.get_data()  # RGBA8 bytes
		var i := 0
		while i < data.size():
			var lum := 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
			# Map luminance into a light-grey band [0.5, 0.92] of 255.
			var g := int(clampf(lum * 0.42 + 128.0, 0.0, 255.0))
			data[i] = g
			data[i + 1] = g
			data[i + 2] = g
			i += 4
		result = ImageTexture.create_from_image(
			Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data))
	_grey_cache[key] = result
	return result

func _building_texture(building_id: String) -> Texture2D:
	if _building_cache.has(building_id):
		return _building_cache[building_id]
	var internal := str(Catalog.get_building(building_id).get("internal_name", ""))
	var tex: Texture2D = null
	var stems := [building_id]
	if internal != "":
		stems = ["%s_%s" % [building_id, internal], building_id]
	for stem in stems:
		for ext in [".png", ".PNG"]:
			var path := "%s/%s%s" % [BUILDING_ICON_DIR, stem, ext]
			if ResourceLoader.exists(path):
				tex = load(path) as Texture2D
				break
		if tex != null:
			break
	_building_cache[building_id] = tex
	return tex

func _icon_positions(center: Vector2, count: int, tile: Vector2) -> Array:
	var n: int = clampi(count, 1, 4)
	var offsets: Array = CLUSTER_OFFSETS.get(n, CLUSTER_OFFSETS[1])
	var out: Array = []
	for i in count:
		var off: Vector2 = offsets[i] if i < offsets.size() else Vector2.ZERO
		out.append(center + off * tile)
	return out

func _texture_for(good_id: String, internal_name: String) -> Texture2D:
	if _texture_cache.has(good_id):
		return _texture_cache[good_id]
	var tex := GoodIcons.texture_for(good_id, internal_name, false)
	_texture_cache[good_id] = tex
	return tex

# ── Hover pills (screen space) ────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _active:
		return
	# Icons/marks are world-space, so panning needs no redraw — only a zoom change
	# (which rescales them) does. Avoids redrawing hundreds of "?" every frame.
	var z := _zoom()
	if not is_equal_approx(z, _last_zoom):
		_last_zoom = z
		queue_redraw()
	# A panel (TVP / building details) over the cursor swallows the hover.
	var hovered := ""
	if terrain_layer != null and not _mouse_over_blocking_panel():
		hovered = terrain_layer.tile_id_under_mouse()
	if hovered != _hovered_id:
		_hovered_id = hovered
		_rebuild_pills()
	_reposition_pills()

# True when the cursor sits over any visible HUD panel — those swallow the hover.
func _mouse_over_blocking_panel() -> bool:
	_resolve_hud()
	if _hud_content == null:
		return false
	var mp := get_viewport().get_mouse_position()
	for child in _hud_content.get_children():
		if child is PanelContainer and (child as Control).visible \
				and (child as Control).get_global_rect().has_point(mp):
			return true
	return false

func _resolve_hud() -> void:
	if _hud_resolved:
		return
	_hud_resolved = true
	if owner != null:
		_hud_content = owner.find_child("HUDContent", true, false)

func _rebuild_pills() -> void:
	_clear_pills()
	if _hovered_id == "" or not _deposits_by_id.has(_hovered_id):
		return
	var entry: Dictionary = _deposits_by_id[_hovered_id]
	if entry.kind != "deposits":
		return  # unsurveyed "?" tiles have no size to show
	var deposits: Array = entry.deposits
	var positions := _icon_positions(entry.center, deposits.size(), _tile_size())
	for i in deposits.size():
		var pill := UIHelpers.make_quantity_pill(str(deposits[i].size_text), PILL_HEIGHT, PILL_TEXT_SIZE)
		_pill_layer.add_child(pill)
		_pills.append({"pill": pill, "world_pos": positions[i]})

func _reposition_pills() -> void:
	if _pills.is_empty():
		return
	var xform := get_viewport().get_canvas_transform()
	# Pull the corner anchor 10px toward the icon centre (fixed at every zoom).
	var icon_screen_half: float = _icon_world_size() * 0.5 * _zoom() - PILL_CENTER_INSET
	for p in _pills:
		var pill: Control = p.pill
		var screen: Vector2 = xform * p.world_pos
		var psize: Vector2 = pill.custom_minimum_size
		# Overlap the icon's bottom-right corner (mostly on the icon).
		var corner := screen + Vector2(icon_screen_half, icon_screen_half)
		pill.position = corner - psize * 0.6

func _clear_pills() -> void:
	for p in _pills:
		if is_instance_valid(p.pill):
			p.pill.queue_free()
	_pills.clear()

# ── Zoom / geometry helpers ───────────────────────────────────────────────────

func _icon_world_size() -> float:
	# Lerp world size between the full-zoom-in and full-zoom-out endpoints.
	var t := _zoom_t()
	return lerpf(ICON_WORLD_ZOOMED_OUT, ICON_WORLD_ZOOMED_IN, t)

func _zoom_t() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	var zmin := 1.0
	var zmax := 4.0
	var zn = cam.get("zoom_min")
	var zx = cam.get("zoom_max")
	if zn != null:
		zmin = float(zn)
	if zx != null:
		zmax = float(zx)
	if zmax <= zmin:
		return 1.0
	return clampf((cam.zoom.x - zmin) / (zmax - zmin), 0.0, 1.0)

func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam != null else 1.0

func _tile_world_pos(coord: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)
