extends Node2D
## Ownership mapmode — how much of each tile you hold, and how much of that you have built on.
##
## Every land tile is a gauge that fills from the BOTTOM:
##
##   dark grey     land you do not own
##   medium blue   owned, still empty — full-width bands stacked bottom to top
##   light blue    owned AND built on — HALF-width, climbing the left of the owned stack first
##                 and only spilling into the right half once the left column is full
##
## The band count is not arbitrary: land is bought in patches of MatchState.LAND_PATCH_SIZE
## (10 units) out of MatchState.MAX_TILE_LAND (200), so a tile is exactly 20 patches and each
## band is one of them — 5% of the tile. A half-cell is half a patch, so the built area is
## still true to the land it represents; drawing it half-width just makes it climb twice as
## high, which is the point (owner call: a small estate was too easy to miss).
##
## Infrastructure never counts — roads, rail, pipes and cables that came with the map have no
## building instance at all, and any that do carry the "infrastructure" category, which the
## hover count filters out.
##
## Read-only against the sim (architecture rule 5).

const SEMIBOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")

const DARK_GREY := Color(0.10, 0.11, 0.13, 0.55)
const MEDIUM_BLUE := Color(0.16, 0.40, 0.72, 0.70)
const LIGHT_BLUE := Color(0.47, 0.78, 0.98, 0.80)
const CHUNK_GAP := 0.14          # fraction of a band left blank, so the bands read as bands

# Hover plate, in SCREEN pixels — divided by the canvas scale at draw time so it stays the same
# size at every zoom. Same navy-plate-with-cream-bevel treatment as the Logistics mapmode's hover
# panel (logistics_overlay._draw_stockpile_panel), which is the visual reference for these.
const PANEL_W := 268.0
const PANEL_PAD := 13.0
const PANEL_ROW_H := 21.0
const PANEL_HEAD_H := 26.0
const PANEL_FS := 14
const PANEL_HEAD_FS := 17
const PANEL_RADIUS := 7.0
const PANEL_BORDER := 3.0
const PANEL_GAP_ABOVE_TILE := 0.30   # fraction of a tile width between plate bottom and tile top

@onready var terrain_layer: HexMap = %TerrainLayer

var _active := false
var _rebuild_queued := false
var _tiles: Array = []           # [{center, bands_owned, halves_built}]
var _by_tile_id := {}            # tile_id -> index into _tiles
var _hover_rows: Array = []      # [[label, value], …] for the hovered tile, built on hover change
var _band_polys: Array = []      # 20 hex-clipped horizontal bands, bottom-up, origin-centred
var _half_polys: Array = []      # per band: [left half, right half]
var _chunk_tile_size := Vector2.ZERO
var _hovered_id := ""
var _hud_content: Control = null
var _hud_resolved := false

func _ready() -> void:
	set_process(false)
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_deactivate)
	# Coalesced (the notification-bell pattern): building_added fires in bursts during a
	# build-out, and each one would otherwise re-walk every tile.
	MatchState.building_added.connect(_queue_rebuild)
	MatchState.building_removed.connect(_queue_rebuild)
	MatchState.tile_land_owned_changed.connect(_queue_rebuild)
	Production.turn_processed.connect(_queue_rebuild)

func _on_selections_changed(mode: int, _selections: Array) -> void:
	if mode == MapMode.Mode.OWNERSHIP:
		_activate()
	else:
		_deactivate()

func _activate() -> void:
	_active = true
	set_process(true)
	_rebuild()

func _deactivate() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	_tiles.clear()
	_by_tile_id.clear()
	_hovered_id = ""
	_hover_rows.clear()
	queue_redraw()

func _queue_rebuild(_arg: Variant = null) -> void:
	if not _active or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_apply_rebuild")

func _apply_rebuild() -> void:
	_rebuild_queued = false
	if _active:
		_rebuild()

func _rebuild() -> void:
	_tiles.clear()
	_by_tile_id.clear()
	if terrain_layer == null:
		return
	var chunks: int = MatchState.MAX_TILE_LAND / MatchState.LAND_PATCH_SIZE
	var patch := float(MatchState.LAND_PATCH_SIZE)
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var tile_id := str(tile_data.get("id", ""))
		var tile_type := str(tile_data.get("type", ""))
		if tile_id == "" or tile_type == "sea" or tile_type == "deep_sea":
			continue      # no land to own at sea
		var owned := float(MatchState.get_tile_land_owned(tile_id))
		# The player's ESTATE, which is what the game's own owned-land gate measures against:
		# owned buildings plus construction and upgrade reservations. Land a build has already
		# claimed is not free land, so showing it as empty would contradict the build dialog.
		var built := MatchState.get_tile_player_space_used(tile_id)
		# Ceil, not round: a part-used patch is a used patch, and the point of the mode is to
		# see that a tile is touched at all. built <= owned always, so ceil keeps that order.
		var bands := clampi(int(ceil(owned / patch)), 0, chunks)
		_tiles.append({
			"center": terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord)),
			"bands_owned": bands,
			# Half a patch per half-cell, so area still equals land — it just stacks twice as high.
			"halves_built": clampi(int(ceil(built / (patch * 0.5))), 0, bands * 2),
		})
		_by_tile_id[tile_id] = _tiles.size() - 1
	queue_redraw()

## Buildings only — infrastructure is excluded twice over: map-seeded road/rail/pipe/cable has
## no building instance at all, and anything that does exist as one carries the category.
func _building_count(tile_id: String, player_owned: bool) -> int:
	var n := 0
	for inst in MatchState.get_buildings_on_tile(tile_id):
		if not (inst is Dictionary) or MatchState.is_player_owned(inst) != player_owned:
			continue
		var bd: Dictionary = Catalog.get_building(str((inst as Dictionary).get("building_id", "")))
		if str(bd.get("category", "")).to_lower() == "infrastructure":
			continue
		n += 1
	return n

## The hover plate's contents. Built once when the cursor enters a tile rather than stored for
## all ~400 — only one tile is ever shown, and every figure here walks that tile's buildings.
func _build_hover_rows(tile_id: String) -> Array:
	return [
		["Your buildings", str(_building_count(tile_id, true))],
		["NPC buildings", str(_building_count(tile_id, false))],
		["Land owned by you", "%d / %d" % [
			MatchState.get_tile_land_owned(tile_id), MatchState.MAX_TILE_LAND]],
		# What is still PURCHASABLE: the cap less what you hold and less the land NPC buildings
		# sit on, which is never for sale.
		["Land left to buy", str(MatchState.get_tile_land_units_available(tile_id))],
		["Your buildings occupy", str(int(round(MatchState.get_tile_player_space_used(tile_id))))],
	]

# ── Hover ─────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# Visual only — no sim logic in a frame callback (architecture rule 2).
	var hovered := ""
	if terrain_layer != null and not _mouse_over_blocking_panel():
		hovered = terrain_layer.tile_id_under_mouse()
	if hovered != _hovered_id:
		_hovered_id = hovered
		_hover_rows = _build_hover_rows(hovered) if _by_tile_id.has(hovered) else []
		queue_redraw()

## A visible HUD panel under the cursor swallows the hover, so no count appears under a panel.
func _mouse_over_blocking_panel() -> bool:
	if not _hud_resolved:
		_hud_resolved = true
		if owner != null:
			_hud_content = owner.find_child("HUDContent", true, false)
	if _hud_content == null:
		return false
	var mp := get_viewport().get_mouse_position()
	for child in _hud_content.get_children():
		if child is PanelContainer and (child as Control).visible \
				and (child as Control).get_global_rect().has_point(mp):
			return true
	return false

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _active or _tiles.is_empty():
		return
	var tile_size := _tile_size()
	_ensure_chunks(tile_size)
	var hex := _hex_points(tile_size)
	# draw_set_transform rather than translating the point arrays: a redraw fires on every hover
	# change, i.e. whenever the cursor crosses a tile, and building ~400 fresh PackedVector2Arrays
	# each time is a lot of garbage for a mouse sweep. The polygons stay origin-centred and the
	# canvas moves instead.
	for entry: Dictionary in _tiles:
		draw_set_transform(entry.center)
		# One grey hex for the whole tile, then the owned bands over it. Every blue cell sits on
		# exactly one grey layer, so they all blend identically — cheaper than clipping the
		# unowned remainder per tile, and visually uniform.
		draw_colored_polygon(hex, DARK_GREY)
		var owned: int = mini(entry.bands_owned, _band_polys.size())
		for i in owned:
			draw_colored_polygon(_band_polys[i], MEDIUM_BLUE)
		# The built estate on top, in half-width cells: up the LEFT of the owned stack first,
		# then up the right. Half-width doubles the height a given estate reaches, which is the
		# whole reason for the split.
		var built: int = entry.halves_built
		for i in mini(built, owned):
			draw_colored_polygon((_half_polys[i] as Array)[0], LIGHT_BLUE)
		for i in clampi(built - owned, 0, owned):
			draw_colored_polygon((_half_polys[i] as Array)[1], LIGHT_BLUE)
	draw_set_transform(Vector2.ZERO)
	if not _hover_rows.is_empty() and _by_tile_id.has(_hovered_id):
		_draw_hover_plate(_tiles[_by_tile_id[_hovered_id]], tile_size)

## A small plate above the hovered tile: labels ranged left, values ranged right. Drawn in world
## space but divided through by the canvas scale, so it holds the same size on screen whatever
## the zoom.
func _draw_hover_plate(entry: Dictionary, tile_size: Vector2) -> void:
	var z: float = maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var w := PANEL_W / z
	var pad := PANEL_PAD / z
	var row_h := PANEL_ROW_H / z
	var head_h := PANEL_HEAD_H / z
	var border := PANEL_BORDER / z
	var h := head_h + row_h * float(_hover_rows.size()) + pad * 2.0
	var origin: Vector2 = (entry.center as Vector2) \
		- Vector2(w * 0.5, h + tile_size.x * PANEL_GAP_ABOVE_TILE)
	var rect := Rect2(origin, Vector2(w, h))

	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_CARD
	sb.set_corner_radius_all(int(PANEL_RADIUS / z))
	sb.set_border_width_all(int(maxf(1.0, border)))
	sb.border_color = DS.PALETTE.BORDER
	draw_style_box(sb, rect)
	_draw_diag_light(rect, Color(1, 1, 1, 0.10), Color(0, 0, 0, 0.16))
	_draw_bevel(rect, border, PANEL_RADIUS / z, Color(1, 1, 1, 0.40), Color(0.10, 0.07, 0.02, 0.40))

	var head_fs := int(maxf(6.0, PANEL_HEAD_FS / z))
	var row_fs := int(maxf(5.0, PANEL_FS / z))
	var head_y := origin.y + pad + head_h * 0.72
	_plate_text(SEMIBOLD_FONT, Catalog.tile_label(_hovered_id),
		Vector2(origin.x + w * 0.5, head_y), head_fs, DS.PALETTE.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	var div_y := origin.y + pad + head_h
	draw_line(Vector2(origin.x + pad, div_y), Vector2(origin.x + w - pad, div_y),
		DS.PALETTE.BORDER_SOFT, maxf(1.0, 1.5 / z))

	var font := ThemeDB.fallback_font
	for i in _hover_rows.size():
		var row: Array = _hover_rows[i]
		var y := div_y + row_h * (float(i) + 0.72)
		_plate_text(font, str(row[0]), Vector2(origin.x + pad, y),
			row_fs, DS.PALETTE.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		_plate_text(SEMIBOLD_FONT, str(row[1]), Vector2(origin.x + w - pad, y),
			row_fs, DS.PALETTE.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)

## `anchor` is the baseline point; the string is placed left of / centred on / right of it.
func _plate_text(font: Font, text: String, anchor: Vector2, fs: int, color: Color, align: int) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := anchor.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= tw * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= tw
	draw_string(font, Vector2(x, anchor.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func _draw_diag_light(rect: Rect2, light: Color, dark: Color) -> void:
	var mid := light.lerp(dark, 0.5)
	draw_polygon(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([light, mid, dark, mid]))

## Inner highlight/shadow lines so the cream outline catches the light.
func _draw_bevel(rect: Rect2, bw: float, radius: float, hi: Color, lo: Color) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var hgt := rect.size.y
	var lw := maxf(1.0, bw * 0.45)
	draw_line(Vector2(x + radius, y + bw), Vector2(x + w - radius, y + bw), hi, lw)
	draw_line(Vector2(x + bw, y + radius), Vector2(x + bw, y + hgt - radius), hi, lw)
	draw_line(Vector2(x + radius, y + hgt - bw), Vector2(x + w - radius, y + hgt - bw), lo, lw)
	draw_line(Vector2(x + w - bw, y + radius), Vector2(x + w - bw, y + hgt - radius), lo, lw)

## The band polygons, built once per tile size: the hex intersected with a horizontal slice,
## bottom band first, each inset by CHUNK_GAP so the bands read as separate bars rather than one
## block. Each band also gets its left and right halves, for the built overlay.
func _ensure_chunks(tile_size: Vector2) -> void:
	if not _band_polys.is_empty() and _chunk_tile_size == tile_size:
		return
	_chunk_tile_size = tile_size
	_band_polys.clear()
	_half_polys.clear()
	var hex := _hex_points(tile_size)
	var count: int = MatchState.MAX_TILE_LAND / MatchState.LAND_PATCH_SIZE
	var step := tile_size.y / float(count)
	var gap := step * CHUNK_GAP * 0.5
	var wide := tile_size.x
	for i in count:
		# i = 0 is the BOTTOM band: y grows downward, so band i sits step*(i+1) above the floor.
		var y1 := tile_size.y * 0.5 - i * step - gap
		var y0 := y1 - step + gap * 2.0
		_band_polys.append(_clip(hex, -wide, y0, wide, y1))
		_half_polys.append([
			_clip(hex, -wide, y0, 0.0, y1),
			_clip(hex, 0.0, y0, wide, y1),
		])

func _clip(hex: PackedVector2Array, x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	var pieces := Geometry2D.intersect_polygons(hex, PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
	]))
	return pieces[0] if not pieces.is_empty() else PackedVector2Array()

## Same flat-top hex the other tile masks use, so an ownership tint lines up with a power one.
func _hex_points(tile_size: Vector2) -> PackedVector2Array:
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	var shoulder_x := tile_size.x * 0.25
	return PackedVector2Array([
		Vector2(-shoulder_x, -half_h),
		Vector2(shoulder_x, -half_h),
		Vector2(half_w, 0),
		Vector2(shoulder_x, half_h),
		Vector2(-shoulder_x, half_h),
		Vector2(-half_w, 0),
	])

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)
