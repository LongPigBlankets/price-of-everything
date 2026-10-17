extends Resource
## One self-contained bake. Lossless storage may be raw or compressed; no live state.
const Values := preload("res://scripts/supply_chain_3d/bake_values.gd")
@export var schema: int = 1
@export var key: String = ""
## Older native dictionaries remain readable, including existing user caches.
@export var data: Dictionary = {}
@export var encoded_values: Dictionary = {}
var _decoded := {}
var _decode_mutex := Mutex.new()

func values(private_copy: bool = false) -> Dictionary:
	if not data.is_empty() and not encoded_values.is_empty(): return {}
	if private_copy:
		# A background world must not share mutable layout containers with an
		# already active reader. Resources remain shared and immutable.
		return Values.unpack(encoded_values) if not encoded_values.is_empty() else data.duplicate(true)
	if encoded_values.is_empty(): return data
	_decode_mutex.lock()
	if _decoded.is_empty(): _decoded=Values.unpack(encoded_values)
	var result := _decoded
	_decode_mutex.unlock()
	return result
