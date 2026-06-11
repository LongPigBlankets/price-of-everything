extends Node2D
## Draws the baked hill contours (data/hills_baked.json) as stacked OS-relief
## bands. Pure playback: polygons arrive in paint order (descending area, fill
## colour pre-resolved per loop), so holes from sinks/ravines render correctly
## without any clipping. Sits between TerrainLayer and RiverLayer — rivers
## always draw over the hills.

## band = level + 1: [0] = lv -1 sub-sea depressions (deep green);
## [1] = lv 0 coastal cream; [2..6] = lv 1-5 vibrant green -> pastel yellow;
## [7..10] = lv 6-9 golds into dark umber; [11] = lv 10 DS off-white snow.
const BAND_COLORS: Array[Color] = [
	Color("194008"),
	Color("ffeeb8"),
	Color("4cbb17"),
	Color("79ca34"),
	Color("a6d951"),
	Color("d2e86d"),
	Color("fff78a"),
	Color("ffd95c"),
	Color("d1a000"),
	Color("755a00"),
	Color("473700"),
	Color(1.0, 1.0, 1.0),
]
const OUTLINE_DARKEN := 0.22
const OUTLINE_WIDTH := 1.5
## Same blue as RiverVisuals.RIVER_COLOR — lakes and the coastal shelf read
## as river water.
const WATER_COLOR := Color(0.17647059, 0.40784314, 0.76862745, 1.0)
## Sea band fills, indexed by the baked sea band: lv -6 (DS navy BG_PANEL)
## up to the shelf, then the beige land base the terrain bands sit on.
const SEA_COLORS: Array[Color] = [
	Color("000d94"),
	Color("000dc2"),
	Color("194ba9"),
	Color("24549e"),
	Color(0.17647059, 0.40784314, 0.76862745),
	Color("ffeeb8"),
]

var _polys: Array = []
var _lakes: Array = []
var _sea: Array = []

func _enter_tree() -> void:
	# the 'toggle heightmap' debug cheat flips visibility on this group
	add_to_group("hill_visuals")

func _ready() -> void:
	_polys = HillBaked.polys()
	_lakes = HillBaked.lakes()
	_sea = HillBaked.sea()
	queue_redraw()

func _draw() -> void:
	for entry in _sea:
		var spts: PackedVector2Array = entry.p
		if spts.size() < 3:
			continue
		var sband: int = clampi(entry.b, 0, SEA_COLORS.size() - 1)
		draw_colored_polygon(spts, SEA_COLORS[sband])
	for entry in _polys:
		var pts: PackedVector2Array = entry.p
		if pts.size() < 3:
			continue
		var band: int = clampi(entry.b, 0, BAND_COLORS.size() - 1)
		var color: Color = BAND_COLORS[band]
		draw_colored_polygon(pts, color)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, color.darkened(OUTLINE_DARKEN), OUTLINE_WIDTH, true)
	for lake_entry in _lakes:
		var lake_pts: PackedVector2Array = lake_entry
		if lake_pts.size() < 3:
			continue
		draw_colored_polygon(lake_pts, WATER_COLOR)
		var shore: PackedVector2Array = lake_pts.duplicate()
		shore.append(lake_pts[0])
		draw_polyline(shore, WATER_COLOR.darkened(0.25), 2.0, true)
