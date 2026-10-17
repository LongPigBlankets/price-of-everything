extends RefCounted
## Runtime-only loading dissolve. Baked geometry is unchanged.
const Grid := preload("res://scripts/supply_chain_3d/detail_residency.gd")
const DURATION := 1.5
const EMPTY_END := 0.10
const INK_END := 0.90
const BACKDROP_STEP_MS := 120
const SHADERS := ["ground.gdshader","road_drawing.gdshader","far_sprite.gdshader","building_print.gdshader","building_glass.gdshader","contour.gdshader","water_glints.gdshader"]
var grid := Grid.new()
var active := false
var begun := false
var elapsed := {}
var complete := {}
var materials := {}
var bindings: Array = []
var timeline := []
var _started_at := {}
var _dirty := false
var next_backdrop_msec := 0

func configure(tiles: Dictionary, origin: Vector2) -> void:
	grid.configure(tiles,origin)
	grid.image.fill(Color.WHITE); grid.texture.update(grid.image)

func begin(already_visible: Dictionary) -> void:
	if begun: return
	begun=true; active=true
	complete=already_visible.duplicate()
	grid.image.fill(Color.BLACK)
	for tid in complete: _set_coverage(tid,1.0)
	grid.texture.update(grid.image)
	for material in materials.values(): material.set_shader_parameter("loading_mask",true)

func bind(root: Node) -> void:
	if begun and not active: return
	var nodes: Array = root.find_children("*","GeometryInstance3D",true,false)
	if root is GeometryInstance3D: nodes.append(root)
	for node in nodes:
		if node is MeshInstance3D and node.material_override == null and node.mesh != null:
			# Surface by surface: a building's glass keeps its own (transparent) paint.
			var surfaces: Array = []
			var bound: Array = []
			for i in node.mesh.get_surface_count():
				surfaces.append(node.get_surface_override_material(i))
				var paint: Material = surfaces[i] if surfaces[i] != null else node.mesh.surface_get_material(i)
				var revealed := _revealed(paint)
				bound.append(revealed)
				if revealed != null: node.set_surface_override_material(i,revealed)
			if bound.any(func(m): return m != null): bindings.append({"node":node,"surfaces":surfaces,"bound":bound})
			continue
		var original: Material = node.material_override
		var source: Material = original
		if source == null:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else (node.multimesh.mesh if node is MultiMeshInstance3D else null)
			if mesh != null and mesh.get_surface_count()>0: source=mesh.surface_get_material(0)
		var material := _revealed(source)
		if material == null: continue
		bindings.append({"node":node,"original":original,"material":material})
		node.material_override=material

## The loading copy of `source`, shared by every node that uses it.
func _revealed(source: Material) -> ShaderMaterial:
	if not source is ShaderMaterial or source.shader == null or source.shader.resource_path.get_file() not in SHADERS: return null
	if source.get_meta("tile_reveal_owner",0)==get_instance_id(): return null
	var id := source.get_instance_id()
	if not materials.has(id):
		var material := source.duplicate() as ShaderMaterial
		material.set_meta("tile_reveal_owner",get_instance_id())
		material.set_shader_parameter("loading_mask",active)
		material.set_shader_parameter("loading_tiles",grid.texture)
		material.set_shader_parameter("loading_origin",grid.anchor)
		material.set_shader_parameter("loading_grid",Vector4(grid.low.x,grid.low.y,grid.image.get_width(),grid.image.get_height()))
		materials[id]=material
	return materials[id]

func start(tid: String) -> bool:
	if not active or complete.has(tid) or elapsed.has(tid): return false
	elapsed[tid]=0.0; _started_at[tid]=Time.get_ticks_msec()
	return true

func backdrop_batch(ordered_tiles: Array, now: int, budget: int = 2) -> Array:
	var started: Array = []
	if now<next_backdrop_msec: return started
	for tid in ordered_tiles:
		if start(str(tid)): started.append(tid)
		if started.size()>=budget: break
	next_backdrop_msec=now+BACKDROP_STEP_MS
	return started

func skip(tid: String) -> void:
	if elapsed.has(tid): return
	complete[tid]=true; _set_coverage(tid,1.0)

static func ink_progress(seconds: float) -> float:
	return clampf((seconds-EMPTY_END)/(INK_END-EMPTY_END),0.0,1.0)*3.0

static func detail_progress(seconds: float) -> float:
	return smoothstep(INK_END,DURATION,seconds)

func _set_coverage(tid: String, value: float) -> void:
	if not grid.cells.has(tid): return
	var p: Vector2i = grid.cells[tid]-grid.low
	var stored := roundf(value*255.0)/255.0
	if is_equal_approx(grid.image.get_pixel(p.x,p.y).r,stored): return
	grid.image.set_pixel(p.x,p.y,Color(stored,stored,stored))
	_dirty=true

func advance(delta: float, wall_clock: bool = false) -> void:
	if not active: return
	for tid in elapsed.keys():
		elapsed[tid]=minf(DURATION,(Time.get_ticks_msec()-_started_at[tid])/1000.0 if wall_clock else elapsed[tid]+delta)
		_set_coverage(tid,detail_progress(elapsed[tid]))
		if elapsed[tid]>=DURATION:
			complete[tid]=true
			timeline.append({"tile":tid,"seconds":elapsed[tid],"wall_ms":Time.get_ticks_msec()-_started_at[tid]})
			elapsed.erase(tid); _started_at.erase(tid)
	if _dirty:
		grid.texture.update(grid.image)
		_dirty=false
	if complete.size()==grid.cells.size(): finish()

func finish() -> void:
	active=false
	elapsed.clear(); _started_at.clear()
	for material in materials.values(): material.set_shader_parameter("loading_mask",false)

func restore() -> void:
	# Wait until any two-frame LOD handover has restored these materials first.
	for record in bindings:
		if not is_instance_valid(record.node): continue
		if record.has("surfaces"):
			for i in record.surfaces.size():
				if record.bound[i] != null and record.node.get_surface_override_material(i)==record.bound[i]:
					record.node.set_surface_override_material(i,record.surfaces[i])
		elif record.node.material_override==record.material:
			record.node.material_override=record.original
	bindings.clear(); materials.clear()
