extends RefCounted
## Presentation roads stop at the coast. The coast mask includes inland rivers
## and lakes, so their existing bridge engineering is retained.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Water := preload("res://scripts/supply_chain_3d/water_geography.gd")

static func clip(paths: Array, centers: Dictionary, masks: Dictionary = {}) -> Dictionary:
	var land := masks.duplicate()
	if land.is_empty():
		for tid in centers:land[tid]=Water.for_tile(tid).land
	var index := Index.tiles(centers)
	var result: Array=[];var removed: Array=[]
	for path in paths:
		var runs: Array=[];var run := PackedVector2Array();var lost := 0.0
		for i in range(1,path.points.size()):
			var a: Vector2=path.points[i-1];var b: Vector2=path.points[i]
			var delta := b-a;var length := delta.length()
			if length<.001:continue
			var intervals: Array=[]
			for tid in Index.query(index,Index.bounds(a,b,.01),Index.TILE_CELL):
				for poly in land.get(tid,[]):
					for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a,b]),poly):
						if piece.size()<2:continue
						var lo := clampf((piece[0]-a).dot(delta)/delta.length_squared(),0,1)
						var hi := clampf((piece[-1]-a).dot(delta)/delta.length_squared(),0,1)
						intervals.append(Vector2(minf(lo,hi),maxf(lo,hi)))
			intervals.sort_custom(func(x,y):return x.x<y.x)
			var merged: Array=[]
			for interval in intervals:
				if not merged.is_empty() and interval.x<=merged[-1].y+.001/length:
					merged[-1].y=maxf(merged[-1].y,interval.y)
				else:merged.append(interval)
			var kept := 0.0
			for interval in merged:
				var first: Vector2=a+delta*interval.x;var last: Vector2=a+delta*interval.y
				kept+=last.distance_to(first)
				if not run.is_empty() and run[-1].distance_to(first)>.002:
					if run.size()>1:runs.append(run)
					run=PackedVector2Array()
				if run.is_empty():run.append(first)
				run.append(last)
			if merged.is_empty() or merged[-1].y<1.0-.001/length:
				if run.size()>1:runs.append(run)
				run=PackedVector2Array()
			lost+=maxf(0,length-kept)
		if run.size()>1:runs.append(run)
		# Preserve unchanged points and source IDs exactly, including tile joins.
		if lost<.01:result.append(path);continue
		removed.append({"source":path.id,"sea_length":lost,"parts":runs.size()})
		for i in runs.size():
			var part: Dictionary=path.duplicate(true)
			part.id=str(path.id)+":coast:%d" % i;part.points=runs[i]
			result.append(part)
	return {"paths":result,"removed":removed}
