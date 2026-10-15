extends "res://scripts/ownership_overlay.gd"
## Land price mapmode: every land tile shaded by what its next patch costs for a build (LandPrice.quote, not
## stand-alone), with the price printed on it. The hover plate lists the price's lines.
##
## The shade climbs on a log scale from the cheapest band to PRICE_TOP, so a doubling reads as the same step
## wherever it happens. Read-only against the sim (architecture rule 5).

const LandPrice := preload("res://scripts/land_price.gd")

## The price the hottest shade stands for: a hub city patch with a crowded tile beside a stand-alone purchase.
const PRICE_TOP := 400.0
const SHADES: Array[Color] = [
	Color(0.18, 0.42, 0.30, 0.62),
	Color(0.55, 0.62, 0.22, 0.66),
	Color(0.86, 0.62, 0.16, 0.70),
	Color(0.86, 0.32, 0.14, 0.74),
	Color(0.62, 0.10, 0.12, 0.78),
]
const LABEL_SCALE := 0.16
const LABEL_OUTLINE := Color(0.02, 0.04, 0.08, 0.9)


func _ready() -> void:
	super()
	# A queued build counts toward its tile's price before it stands.
	Construction.construction_started.connect(func(_iid: String, _tile: String) -> void: _queue_rebuild())
	Construction.construction_cancelled.connect(func(_iid: String, _tile: String) -> void: _queue_rebuild())
	BuildingState.building_owner_changed.connect(_queue_rebuild)


func _on_selections_changed(mode: int, _selections: Array) -> void:
	if mode == MapMode.Mode.LAND_PRICE:
		_activate()
	else:
		_deactivate()


func _rebuild() -> void:
	_tiles.clear()
	_by_tile_id.clear()
	if terrain_layer == null:
		return
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var tile_id := str(tile_data.get("id", ""))
		var tile_type := str(tile_data.get("type", ""))
		if tile_id == "" or tile_type == "sea" or tile_type == "deep_sea":
			continue
		var price := LandPrice.patch_price(tile_id, false)
		_tiles.append({
			"center": terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord)),
			"price": price,
			"colour": shade(price),
		})
		_by_tile_id[tile_id] = _tiles.size() - 1
	queue_redraw()


## The shade for a patch price.
static func shade(price: float) -> Color:
	var low := BuildingState.LAND_PATCH_COST * float(EconomyConfig.LAND_BAND_MULT["rest"])
	var t := clampf(log(maxf(price, low) / low) / log(PRICE_TOP / low), 0.0, 1.0)
	var at := t * float(SHADES.size() - 1)
	var i := mini(floori(at), SHADES.size() - 2)
	return SHADES[i].lerp(SHADES[i + 1], at - float(i))


func _build_hover_rows(tile_id: String) -> Array:
	var rows: Array = LandPrice.lines(LandPrice.quote(tile_id, 1, false))
	rows.append(["Bought on its own", LandPrice.pounds(LandPrice.patch_price(tile_id, true))])
	return rows


func _draw() -> void:
	if not _active or _tiles.is_empty():
		return
	var tile_size := _tile_size()
	var hex := _hex_points(tile_size)
	var fs := int(maxf(6.0, tile_size.y * LABEL_SCALE))
	for entry: Dictionary in _tiles:
		draw_set_transform(entry.center)
		draw_colored_polygon(hex, entry.colour)
		var text := LandPrice.pounds(float(entry.price))
		var at := Vector2(-SEMIBOLD_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, fs * 0.35)
		draw_string_outline(SEMIBOLD_FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 6), LABEL_OUTLINE)
		draw_string(SEMIBOLD_FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)
	draw_set_transform(Vector2.ZERO)
	if not _hover_rows.is_empty() and _by_tile_id.has(_hovered_id):
		_draw_hover_plate(_tiles[_by_tile_id[_hovered_id]], tile_size)
