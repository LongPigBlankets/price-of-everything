extends RefCounted
## Per-world resource cache. No scene nodes or active physics bodies are retained.
## Visible/recent/nearby tiles can exceed the soft target; speculative loads cannot.
const DEFAULT_TARGET_BYTES := 700 * 1024 * 1024
const MIN_UNUSED_MSEC := 10000
var target_bytes := DEFAULT_TARGET_BYTES
var entries: Dictionary = {}
var bytes := 0
var hits := 0
var evictions := 0

func put(tid: String, data: Dictionary, chunk: Dictionary, now: int) -> void:
	var last_used: int = entries.get(tid, {}).get("last_used", now)
	bytes -= int(entries.get(tid, {}).get("bytes", 0))
	var cost := estimate(data, chunk)
	entries[tid] = {"data": data, "chunk": chunk, "bytes": cost, "last_used": last_used}
	bytes += cost

func restore(tid: String) -> Dictionary:
	if not entries.has(tid): return {}
	hits += 1
	return entries[tid]

func touch(tid: String, now: int) -> void:
	if entries.has(tid): entries[tid].last_used = now

func erase(tid: String) -> void:
	if not entries.has(tid): return
	bytes -= int(entries[tid].bytes)
	entries.erase(tid)
	evictions += 1

func trim(now: int, active: Dictionary, nearby: Dictionary, distances: Dictionary = {}) -> void:
	if bytes <= target_bytes: return
	var eligible: Array = []
	for tid in entries:
		if active.has(tid) or nearby.has(tid) or now - int(entries[tid].last_used) < MIN_UNUSED_MSEC: continue
		eligible.append(tid)
	eligible.sort_custom(func(a: String, b: String) -> bool:
		if entries[a].last_used != entries[b].last_used: return entries[a].last_used < entries[b].last_used
		return float(distances.get(a, INF)) > float(distances.get(b, INF)))
	for tid in eligible:
		if bytes <= target_bytes: break
		erase(tid)

func can_prefetch(estimated_bytes: int = 8 * 1024 * 1024) -> bool:
	# Reserve a fifth of the target for foreground work and estimation error.
	return bytes + estimated_bytes <= int(target_bytes * 0.8)

static func estimate(data: Dictionary, chunk: Dictionary) -> int:
	# Conservative decoded payload accounting, including retained collision faces.
	# The common continent atlas and shared asset atlases are accounted separately.
	var total := 0
	var seen := {}
	for texture in data.get("textures", []).slice(1):
		if texture == null or seen.has(texture.get_instance_id()): continue
		seen[texture.get_instance_id()] = true
		var width: int = texture.get_width()
		var height: int = texture.get_height()
		while true:
			total += width * height * 4
			if width == 1 and height == 1: break
			width = maxi(1, width / 2)
			height = maxi(1, height / 2)
	var meshes: Array = data.get("meshes", []).duplicate()
	for value in chunk.values():
		if value is Mesh: meshes.append(value)
	var detail: Dictionary = chunk.get("local_detail", {})
	for value in detail.values():
		if value is Mesh: meshes.append(value)
	for cards in detail.get("tree_cards", {}).values(): total += cards.size() * 48
	for mesh in meshes:
		if mesh == null or seen.has(mesh.get_instance_id()): continue
		seen[mesh.get_instance_id()] = true
		for surface in mesh.get_surface_count():
			var counts := _mesh_counts(mesh, surface)
			total += counts.x * 48 + counts.y * 4
	for i in data.get("shapes", []).size():
		if data.shapes[i] == null or data.meshes[i] == null: continue
		# Faces plus a BVH allowance; native physics allocations are platform-dependent.
		for surface in data.meshes[i].get_surface_count():
			var mesh: Mesh = data.meshes[i]
			var counts := _mesh_counts(mesh, surface)
			total += maxi(counts.x, counts.y) * 24
	return total

static func _mesh_counts(mesh: Mesh, surface: int) -> Vector2i:
	# Production bakes are ArrayMeshes: query lengths without reading GPU arrays.
	if mesh is ArrayMesh:
		return Vector2i(mesh.surface_get_array_len(surface), mesh.surface_get_array_index_len(surface))
	var arrays := mesh.surface_get_arrays(surface)
	return Vector2i(arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX] != null else 0,
		arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0)
