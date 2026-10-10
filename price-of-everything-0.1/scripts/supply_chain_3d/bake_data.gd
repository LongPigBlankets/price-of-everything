extends Resource
## One self-contained bake. Lossless storage may be raw or compressed; no live state.
@export var schema: int = 1
@export var key: String = ""
@export var data: Dictionary = {}
