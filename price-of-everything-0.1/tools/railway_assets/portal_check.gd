extends Node
const Portal := preload("res://scripts/supply_chain_3d/tunnel_portal.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; push_error(message)
func first_color(mesh: ArrayMesh, start: Vector3, end: Vector3) -> Color:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var closest := INF; var result := Color.TRANSPARENT
	for i in range(0,vertices.size(),3):
		var hit: Variant=Geometry3D.segment_intersects_triangle(start,end,vertices[i],vertices[i+1],vertices[i+2])
		if hit!=null and start.distance_to(hit)<closest:
			closest=start.distance_to(hit); result=colors[i]
	return result
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	var flat := func(_p: Vector2) -> float: return 34.0
	var soil := func(_h: float) -> Color: return Color("99875a")
	var portal := {"p":Vector2.ZERO,"dir":Vector2.RIGHT,"half_width":6.0,"h":34.0}
	var batch := Geo.Batch.new(); Portal.append(batch,portal,Vector2.ZERO,flat,soil)
	var mesh := batch.mesh()
	check(first_color(mesh,Vector3(-80,37,0),Vector3(80,37,0)).is_equal_approx(Portal.DARK),"The approach side sees the recessed mouth")
	var back := first_color(mesh,Vector3(80,37,0),Vector3(-80,37,0))
	check(back.a>0 and not back.is_equal_approx(Portal.DARK),"Opaque earth closes the back of the tunnel mouth")
	for sign_v in [-1.0,1.0]:
		var side := first_color(mesh,Vector3(1,37,80*sign_v),Vector3(1,37,-80*sign_v))
		check(side.a>0 and not side.is_equal_approx(Portal.DARK),"Earth wings close both sides of the tunnel")
	# The hood follows the actual slope, not a long triangle suspended above it.
	var hill := func(p: Vector2) -> float: return 34+maxf(0,p.x-8)*2.0
	batch=Geo.Batch.new(); Portal.append(batch,portal,Vector2.ZERO,hill,soil)
	var vertices: PackedVector3Array=batch.mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in vertices:
		if v.x>15:
			check(v.y<=hill.call(Vector2(v.x,v.z))+0.2,"Deep collar vertices meet the hillside")
	print("[portal-check] failures=",failures)
	get_tree().quit(1 if failures else 0)
