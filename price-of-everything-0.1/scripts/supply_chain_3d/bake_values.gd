extends RefCounted
## Store large value dictionaries as one binary block; retain native mesh/texture
## resources separately. Decoding never instantiates objects from byte data.
const VERSION := 1

static func pack(value: Dictionary) -> Dictionary:
	var resources: Array[Resource] = []
	var links: Array = []
	var plain: Dictionary = _values(value, [], resources, {}, links)
	return {"version":VERSION,"values":var_to_bytes([plain,links]),"resources":resources}

static func _values(value: Variant, path: Array, resources: Array[Resource], ids: Dictionary, links: Array) -> Variant:
	if value is Resource:
		var id: int = value.get_instance_id()
		if not ids.has(id):
			ids[id]=resources.size(); resources.append(value)
		links.append([path,ids[id]])
		return null
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=_values(value[key],path+[key],resources,ids,links)
		return result
	if value is Array:
		var result: Array = []
		for i in value.size(): result.append(_values(value[i],path+[i],resources,ids,links))
		return result
	assert(not value is Object, "Bake values may contain resources, never live scene objects")
	return value

static func unpack(payload: Dictionary) -> Dictionary:
	if payload.get("version",-1)!=VERSION or not payload.get("values") is PackedByteArray or not payload.get("resources") is Array: return {}
	var decoded: Variant = bytes_to_var(payload.values)
	if not decoded is Array or decoded.size()!=2 or not decoded[0] is Dictionary or not decoded[1] is Array: return {}
	var result: Dictionary = decoded[0]
	# Restore only resource leaves. Walking the entire layout in GDScript again
	# would throw away the benefit of the native Variant decoder.
	for link in decoded[1]:
		if not link is Array or link.size()!=2 or not link[0] is Array or link[0].is_empty(): return {}
		var index := int(link[1])
		if index<0 or index>=payload.resources.size() or not payload.resources[index] is Resource: return {}
		var target: Variant = result
		var path: Array = link[0]
		for i in path.size():
			var key: Variant = path[i]
			if target is Dictionary:
				if not target.has(key): return {}
			elif target is Array:
				if not key is int or key<0 or key>=target.size(): return {}
			else: return {}
			if i==path.size()-1: target[key]=payload.resources[index]
			else: target=target[key]
	return result
