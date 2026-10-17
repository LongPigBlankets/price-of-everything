extends RefCounted
## Reclaimed ground and low fencing: empty expansion land, not construction sites.
## One batched mesh is included in the shared infrastructure bake at every LOD.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")

static func mesh(plan: Dictionary, origin: Vector2, height: Callable) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for path in plan.get("footpaths",[]):
		var a: Vector2=path[0];var b: Vector2=path[1]
		var n := (b-a).normalized().orthogonal()
		var steps := maxi(1,ceili(a.distance_to(b)/4.0))
		var point := func(p: Vector2) -> Vector3:return Vector3(p.x-origin.x,float(height.call(p))+.32,p.y-origin.y)
		for i in steps:
			var p := a.lerp(b,float(i)/steps);var q := a.lerp(b,float(i+1)/steps)
			batch.quad(point.call(p+n),point.call(p-n),point.call(q-n),point.call(q+n),Color("b7af92"))
	for site in plan.get("brownfields",[]):
		var tangent: Vector2=site.tangent;var n: Vector2=site.normal
		var at := func(p: Vector2, lift: float) -> Vector3:
			var q: Vector2=site.pos+tangent*p.x+n*p.y
			return Vector3(q.x-origin.x,float(height.call(q))+lift,q.y-origin.y)
		# Low-contrast mottling reads as earth/gravel, without a noisy scatter of
		# individual grey stones or a bright slab competing with the buildings.
		for y in 5:
			for x in 7:
				var a := Vector2(-26+x*52.0/7,-20+y*8)
				var b := a+Vector2(52.0/7,8)
				var shade := float(posmod(x*7+y*11,5))*.012
				var color := Color(.48+shade,.43+shade,.32+shade)
				var p0: Vector3=at.call(a,.24);var p1: Vector3=at.call(Vector2(b.x,a.y),.24)
				var p2: Vector3=at.call(b,.24);var p3: Vector3=at.call(Vector2(a.x,b.y),.24)
				if tangent.cross(n)>0: batch.quad(p0,p3,p2,p1,color)
				else: batch.quad(p0,p1,p2,p3,color)
		# An old, narrow foundation trace, retaining a large usable empty centre.
		for edge in [PackedVector2Array([Vector2(-17,10),Vector2(14,10)]),PackedVector2Array([Vector2(-17,-8),Vector2(-17,10)])]:
			batch.tube(at.call(edge[0],.5),at.call(edge[1],.5),.55,Color("aaa28b"),4)
		var sides := [PackedVector2Array([Vector2(-26,-20),Vector2(-26,20)]),PackedVector2Array([Vector2(-26,20),Vector2(26,20)]),
			PackedVector2Array([Vector2(26,20),Vector2(26,-20)]),PackedVector2Array([Vector2(-26,-20),Vector2(-5,-20)]),PackedVector2Array([Vector2(5,-20),Vector2(26,-20)])]
		for side in sides:
			var count := maxi(1,ceili(side[0].distance_to(side[1])/8.0))
			for j in range(count+1):
				var p: Vector2=side[0].lerp(side[1],float(j)/count)
				batch.tube(at.call(p,.3),at.call(p,2.3),.22,Color("73776a"),4)
			for lift in [1.1,2.0]: batch.tube(at.call(side[0],lift),at.call(side[1],lift),.12,Color("939383"),4)
		# A ten-unit opening faces the road. No ornamental driveway pushes the
		# adjacent frontage back, and the plot does not become a gameplay site.
	return batch.mesh()
