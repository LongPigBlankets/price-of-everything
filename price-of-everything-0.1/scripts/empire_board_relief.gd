extends RefCounted
## Supply chain board — how high its ground stands.
##
## The board takes its heights from the world map's own: the baked height bands (HillBaked, the
## field the map paints its contours from, read here through its routing grid). Every band stands
## at one height wherever it lies, BAND_LEVEL. A tile's own height is the average of those levels
## over its land, snapped to the nearest band's level (tile_level); the ground drawn on it stands
## there except where the map's relief steps up or down from it (empire_board_ground.gd).
##
## The tile heights are then settled over the whole map at once, so a tile stands at the same
## height whichever other tiles the board shows:
##   - no tile stands more than STEP_CAP above a neighbour, so no step drops several levels;
##   - a river never climbs: followed up from its mouth, every tile stands at least as high as
##     the one below it. Which way a river drains is read off the map (river_flows).
## Both are met by lowering only: lowland keeps its level and high ground gives way, so a hill a
## river runs down into from lowland stands at the lowland's level. Open water is not settled: it
## stands at SEA_LEVEL.
##
## Pure data: nothing here reads the sim.

## The height each band stands at, in map units, from band 0 (the map's level -1) to band 11
## (snow). Bands 0 to 2 are lowland. A lowland step is a full one; above the hills' band the steps
## are smaller, so mountains stand clear of hills without towering over them.
const BAND_LEVEL: Array[float] = [34.0, 34.0, 34.0, 43.0, 52.0, 58.0, 64.0, 70.0, 76.0, 82.0, 88.0, 94.0]
## The most one tile stands above a neighbour: short of three lowland steps, so a mountain beside
## lowland still stands clear of a hill (52) and no step drops several levels at once.
const STEP_CAP := 24.0
## Open water, one lowland step below the lowland, so a river can run to the sea in a valley.
const SEA_LEVEL := 25.0
## Tiles of open water.
const WATER_TILES := ["sea", "deep_sea"]
const HEX_HALF := Vector2(270.0, 240.0)
## Every second cell of the routing grid is enough to tell a tile's average.
const SAMPLE_STRIDE := 2
## A river's end this close to a tile edge crosses into the neighbour there.
const EDGE_REACH := 2.0
## Finding which way a river drains: a step up river onto a band lower than the one below it
## costs this many tiles of length.
const CLIMB_COST := 100.0

static var _plates: Dictionary = {}          # tile_id -> settled tile height
static var _plates_for := 0                  # the terrain they were settled for


static func band_level(band: int) -> float:
	return BAND_LEVEL[clampi(band, 0, BAND_LEVEL.size() - 1)]


## The settled height of every tile on the map, open water included, worked out once per map.
## `terrain` gives tile centres (id_to_coord etc.); `rivers_by_tile` is tile_id -> [PackedVector2Array]
## in map space, every river on the map.
static func plates(terrain: Object, rivers_by_tile: Dictionary) -> Dictionary:
	if _plates_for == terrain.get_instance_id() and not _plates.is_empty():
		return _plates
	var centers: Dictionary = {}
	var raw: Dictionary = {}
	for tid in Catalog.all_tile_ids():
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		centers[str(tid)] = c
		if WATER_TILES.has(str(Catalog.tile_type(str(tid)))):
			continue
		raw[str(tid)] = tile_level(c)
	var neighbours: Dictionary = {}
	for tid in raw:
		var near: Array = []
		for nb in Catalog.tile_neighbours(str(tid)):
			if raw.has(str(nb)):
				near.append(str(nb))
		neighbours[tid] = near
	_plates = settle(raw, neighbours, river_flows(rivers_by_tile, centers))
	for tid in centers:
		if not _plates.has(tid):
			_plates[tid] = SEA_LEVEL
	_plates_for = terrain.get_instance_id()
	return _plates


## A tile's own height: the average level of the bands over the land of the hex centred at
## `center` (open water left out), read off every SAMPLE_STRIDE-th cell of the map's routing grid
## and snapped to the nearest band's level. Lowland where the grid is missing or the hex holds no land.
static func tile_level(center: Vector2) -> float:
	return snap_level(land_average(center))


## The average band level over the land of the hex centred at `center`, unsnapped.
static func land_average(center: Vector2) -> float:
	var grid := NavGrid.instance()
	if not grid.is_ready():
		return band_level(2)
	var sum := 0.0
	var count := 0
	var lo := grid.cell_of(center - HEX_HALF)
	var hi := grid.cell_of(center + HEX_HALF)
	for iy in range(lo.y, hi.y + 1, SAMPLE_STRIDE):
		for ix in range(lo.x, hi.x + 1, SAMPLE_STRIDE):
			var d := grid.world_of(ix, iy) - center
			if absf(d.y) > HEX_HALF.y or absf(d.x) > HEX_HALF.x - absf(d.y) * 0.5625:
				continue
			var w := grid.water(ix, iy)
			if w == NavGrid.WATER_SEA or w == NavGrid.WATER_LAKE:
				continue
			sum += band_level(grid.band(ix, iy))
			count += 1
	return sum / float(count) if count > 0 else band_level(2)


## Does the hex centred at `center` hold any open water (sea or lake) on the routing grid, or within
## a cell of its edge. True where the grid is missing.
static func hex_has_water(center: Vector2) -> bool:
	var grid := NavGrid.instance()
	if not grid.is_ready():
		return true
	var reach := HEX_HALF + Vector2(grid.step, grid.step)
	var lo := grid.cell_of(center - reach)
	var hi := grid.cell_of(center + reach)
	for iy in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var w := grid.water(ix, iy)
			if w != NavGrid.WATER_SEA and w != NavGrid.WATER_LAKE:
				continue
			var d := grid.world_of(ix, iy) - center
			if absf(d.y) <= reach.y and absf(d.x) <= reach.x - absf(d.y) * 0.5625:
				return true
	return false


## The band level nearest a height.
static func snap_level(h: float) -> float:
	var best := BAND_LEVEL[0]
	for lv in BAND_LEVEL:
		if absf(lv - h) < absf(best - h):
			best = lv
	return best


## The map's own level at a point, as its band stands (band_level); lowland off the grid.
static func map_level(p: Vector2) -> float:
	var grid := NavGrid.instance()
	if not grid.is_ready():
		return band_level(2)
	var cell := grid.cell_of(p)
	return band_level(grid.band(cell.x, cell.y))


## Which way the rivers flow from tile to tile: [[upstream, downstream]], found by following
## each river network up from its mouths (an end that runs out past its tile into the sea, or
## onto a sea tile). A network with no mouth gives nothing. `centers` is tile_id -> centre for
## every tile of the map, the sea's included, or a mouth onto a sea tile goes unseen.
static func river_flows(rivers_by_tile: Dictionary, centers: Dictionary) -> Array:
	var net: Dictionary = river_links(rivers_by_tile, centers)
	var links: Dictionary = net["links"]
	# A network can reach the sea by more than one mouth. Each tile drains by the way to a mouth
	# that climbs least on the map's own river bands, then by the shortest: Dijkstra up from
	# every mouth, where a step up river onto a lower band costs far more than any length.
	var level: Dictionary = {}
	for t in links:
		level[t] = river_band(centers.get(t, Vector2.ZERO))
	var cost: Dictionary = {}
	var down_of: Dictionary = {}
	var open: Array = []
	for m in net["mouths"]:
		if not cost.has(m):
			cost[m] = 0.0
			open.append(m)
	var done: Dictionary = {}
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if float(cost[open[i]]) < float(cost[open[best]]) - 0.001 \
					or (absf(float(cost[open[i]]) - float(cost[open[best]])) <= 0.001 and str(open[i]) < str(open[best])):
				best = i
		var cur: String = open[best]
		open.remove_at(best)
		if done.has(cur):
			continue
		done[cur] = true
		for up in links.get(cur, {}):
			var step := 1.0 + CLIMB_COST * float(maxi(0, int(level.get(cur, 0)) - int(level.get(up, 0))))
			var c := float(cost[cur]) + step
			if not done.has(up) and (not cost.has(up) or c < float(cost[up]) - 0.001):
				cost[up] = c
				down_of[up] = cur
				open.append(up)
	var flows: Array = []
	var ups: Array = down_of.keys()
	ups.sort()
	for up in ups:
		flows.append([str(up), str(down_of[up])])
	return flows


## The band the rivers on the tile centred at `center` run on in the map's own field: the middle of
## the routing grid's river cells there. -1 where the grid has none.
static func river_band(center: Vector2) -> int:
	var grid := NavGrid.instance()
	if not grid.is_ready():
		return -1
	var bands: Array = []
	var lo := grid.cell_of(center - HEX_HALF)
	var hi := grid.cell_of(center + HEX_HALF)
	for iy in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			if grid.water(ix, iy) != NavGrid.WATER_RIVER:
				continue
			var d := grid.world_of(ix, iy) - center
			if absf(d.y) > HEX_HALF.y or absf(d.x) > HEX_HALF.x - absf(d.y) * 0.5625:
				continue
			bands.append(grid.band(ix, iy))
	if bands.is_empty():
		return -1
	bands.sort()
	return int(bands[bands.size() / 2])


## The river network as tiles: {links: tile -> {neighbour: true} for each edge a river crosses,
## mouths: [tile] for each tile a river leaves for the sea}.
static func river_links(rivers_by_tile: Dictionary, centers: Dictionary) -> Dictionary:
	var links: Dictionary = {}               # tile -> {neighbour: true}
	var mouths: Array = []
	var by_center: Dictionary = {}
	for tid in centers:
		by_center[Vector2i((centers[tid] as Vector2).round())] = str(tid)
	for tid in rivers_by_tile:
		if not centers.has(tid):
			continue
		var c: Vector2 = centers[tid]
		var hexp := hex_points(c)
		for line in rivers_by_tile[tid]:
			var pts: PackedVector2Array = line
			if pts.size() < 2:
				continue
			for end in [pts[0], pts[pts.size() - 1]]:
				var p: Vector2 = end
				var edge := -1
				for i in range(6):
					if Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_to(p) < EDGE_REACH:
						edge = i
				if edge < 0:
					if not Geometry2D.is_point_in_polygon(p, hexp):
						mouths.append(str(tid))     # it runs on out over the sea
					continue
				var mid := (hexp[edge] + hexp[(edge + 1) % 6]) * 0.5
				var nb: Variant = by_center.get(Vector2i((c + (mid - c) * 2.0).round()))
				if nb == null:
					continue
				if WATER_TILES.has(str(Catalog.tile_type(str(nb)))):
					mouths.append(str(tid))
					continue
				(links.get_or_add(str(tid), {}) as Dictionary)[str(nb)] = true
				(links.get_or_add(str(nb), {}) as Dictionary)[str(tid)] = true
	return {"links": links, "mouths": mouths}


## Settle raw tile heights: each at most its raw height, at most STEP_CAP above any neighbour,
## and never above the tile upstream of it on a river. The highest heights that meet all three,
## found by lowering until nothing changes. `neighbours` is tile -> [tile]; `flows` is
## [[upstream, downstream]].
static func settle(raw: Dictionary, neighbours: Dictionary, flows: Array, cap: float = STEP_CAP) -> Dictionary:
	var h: Dictionary = raw.duplicate()
	var downs: Dictionary = {}                # upstream -> [downstream]
	for f in flows:
		if h.has(str(f[0])) and h.has(str(f[1])):
			(downs.get_or_add(str(f[0]), []) as Array).append(str(f[1]))
	var queue: Array = h.keys()
	queue.sort()
	var queued: Dictionary = {}
	for t in queue:
		queued[t] = true
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		queued.erase(cur)
		var lowered: Array = []
		for nb in neighbours.get(cur, []):
			if h.has(nb) and float(h[nb]) > float(h[cur]) + cap + 0.001:
				h[nb] = float(h[cur]) + cap
				lowered.append(nb)
		for d in downs.get(cur, []):
			if float(h[d]) > float(h[cur]) + 0.001:
				h[d] = float(h[cur])
				lowered.append(d)
		for t in lowered:
			if not queued.has(t):
				queued[t] = true
				queue.append(t)
	return h


static func hex_points(center: Vector2) -> PackedVector2Array:
	var hh := HEX_HALF
	return PackedVector2Array([
		center + Vector2(hh.x, 0.0), center + Vector2(hh.x * 0.5, hh.y),
		center + Vector2(-hh.x * 0.5, hh.y), center + Vector2(-hh.x, 0.0),
		center + Vector2(-hh.x * 0.5, -hh.y), center + Vector2(hh.x * 0.5, -hh.y),
	])
