extends RefCounted
## A recessed opening with a solid, terrain-coloured cover behind it. The back
## and wings are earth, so the mouth is visible only from the approach side.
const CONCRETE := Color("9b9f94")
const DARK := Color("20292a")

static func v(p: Vector2, h: float, origin: Vector2) -> Vector3:
	return Vector3(p.x-origin.x,h,p.y-origin.y)

static func append(batch: RefCounted, portal: Dictionary, origin: Vector2, terrain: Callable, earth := Callable()) -> void:
	var p: Vector2=portal.p; var dir: Vector2=portal.dir; var side := dir.orthogonal()
	var h: float=portal.h; var half: float=portal.half_width
	var wall: float=portal.get("wall",5.5); var rise: float=portal.get("rise",3.0)
	var thickness := 1.25; var depth: float=portal.get("depth",22.0)
	var front := p-dir*0.35; var back := p-dir*0.2
	var arch := PackedVector3Array()
	var base_left := v(p-side*(half+thickness),h,origin)
	var base_right := v(p+side*(half+thickness),h,origin)
	arch.append(base_right)
	# The dark recess sits behind the rails/road end, inside the opaque hood.
	batch.quad(v(back-side*half,h,origin),v(back+side*half,h,origin),
		v(back+side*half,h+wall,origin),v(back-side*half,h+wall,origin),DARK)
	for i in 16:
		var a := PI*float(i)/16; var b := PI*float(i+1)/16
		var ia := v(front+side*cos(a)*half,h+wall+sin(a)*rise,origin)
		var ib := v(front+side*cos(b)*half,h+wall+sin(b)*rise,origin)
		var oa := v(p+side*cos(a)*(half+thickness),h+wall+sin(a)*(rise+thickness),origin)
		var ob := v(p+side*cos(b)*(half+thickness),h+wall+sin(b)*(rise+thickness),origin)
		batch.quad(ia,ib,ob,oa,CONCRETE)
		var recess := Vector3(dir.x,0,dir.y)*0.15
		batch.triangle(v(back,h+wall,origin),ia+recess,ib+recess,DARK)
		batch.quad(ia,ia+recess,ib+recess,ib,CONCRETE.darkened(0.3))
		if i==0: arch.append(oa)
		arch.append(ob)
	arch.append(base_left)
	for sign_v in [-1.0,1.0]:
		var a: Vector2=front+side*half*sign_v; var b: Vector2=p+side*(half+thickness)*sign_v
		batch.quad(v(a,h,origin),v(b,h,origin),v(b,h+wall,origin),v(a,h+wall,origin),CONCRETE)
	# Sample the hill along the hood instead of stretching a single sloping
	# quad to a distant, much higher point on the mountain. Sink the collar
	# into the hill instead of overlaying its surface (which causes z-fighting).
	var steps := maxi(4,ceili(depth/2.0))
	for j in steps:
		var d0 := depth*float(j)/steps; var d1 := depth*float(j+1)/steps
		for i in range(1,arch.size()):
			var a := _cover(arch[i-1],dir,d0,depth,h,origin,terrain)
			var b := _cover(arch[i],dir,d0,depth,h,origin,terrain)
			var c := _cover(arch[i-1],dir,d1,depth,h,origin,terrain)
			var d := _cover(arch[i],dir,d1,depth,h,origin,terrain)
			var color: Color=earth.call((a.y+b.y+c.y+d.y)*0.25) if earth.is_valid() else Color("9b925e")
			batch.quad(a,b,d,c,color)
		for sign_v in [-1.0,1.0]:
			for k in 3:
				var x0 := float(k)*2; var x1 := float(k+1)*2
				var a := _wing(p,dir,side,sign_v,half+thickness,x0,d0,depth,h,wall,origin,terrain)
				var b := _wing(p,dir,side,sign_v,half+thickness,x1,d0,depth,h,wall,origin,terrain)
				var c := _wing(p,dir,side,sign_v,half+thickness,x0,d1,depth,h,wall,origin,terrain)
				var d := _wing(p,dir,side,sign_v,half+thickness,x1,d1,depth,h,wall,origin,terrain)
				var color: Color=earth.call((a.y+b.y+c.y+d.y)*0.25) if earth.is_valid() else Color("9b925e")
				batch.quad(a,b,d,c,color)
	for sign_v in [-1.0,1.0]:
		var edge: Vector2=p+side*(half+thickness)*sign_v
		var outside: Vector2=edge+side*6.0*sign_v
		batch.triangle(v(edge,h+wall,origin),v(edge,h,origin),v(outside,float(terrain.call(outside))-2.0,origin),CONCRETE.darkened(0.08))

static func _cover(front: Vector3, dir: Vector2, distance: float, depth: float, base: float, origin: Vector2, terrain: Callable) -> Vector3:
	if distance==0: return front
	var p := Vector2(front.x+origin.x,front.z+origin.y)+dir*distance
	var buried := minf(base-2.0,float(terrain.call(p))-2.0)
	var roof := lerpf(front.y,buried,smoothstep(0.0,depth,distance))
	return v(p,roof,origin)

static func _wing(p: Vector2, dir: Vector2, side: Vector2, sign_v: float, radius: float, outside: float, distance: float, depth: float, base: float, wall: float, origin: Vector2, terrain: Callable) -> Vector3:
	var q := p+dir*distance+side*(radius+outside)*sign_v
	var ground := float(terrain.call(q))-2.0
	var edge := lerpf(base+wall,minf(base-2.0,ground),smoothstep(0.0,depth,distance))
	return v(q,lerpf(edge,ground,smoothstep(0.0,6.0,outside)),origin)
