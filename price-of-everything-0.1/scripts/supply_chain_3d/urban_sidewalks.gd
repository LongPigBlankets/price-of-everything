extends RefCounted
## Presentation-only footways. Driveways remain access paths, not public streets.
const WIDTH := 2.0
const EDGE := Color("aaa99a")
const PAVING := Color("c1bdad")

static func apply(roads: Array, tiles: Dictionary) -> void:
	for road in roads:
		var urban: bool=str(tiles.get(str(road.get("tile","")),{}).get("type",""))=="urban"
		var access := str(road.get("source","")).begins_with("access:")
		road.sidewalk=WIDTH if urban and not access and road.get("paved",true) and not road.get("tunnel",false) else 0.0

static func width(road: Dictionary) -> float:
	return 0.0 if road.get("tunnel",false) else float(road.get("sidewalk",0.0))
