extends Node
## Verify the lazily-built Market panel: it should NOT be built at load, then build correctly the
## first time it's shown.  <godot> --path . res://tools/market_lazy_check.tscn --quit-after 2500
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	while not bool(main.get("build_complete")):
		await get_tree().process_frame
	var mkt: Node = main.find_child("MarketPanel", true, false)
	print("MKT found=%s  built_at_load=%s" % [mkt != null, str(mkt.get("_built")) if mkt else "n/a"])
	mkt.visible = true   # first open → should build
	for _i in range(8):
		await get_tree().process_frame
	var rows: Variant = mkt.get("rows")
	print("MKT after first open: _built=%s rows=%d" % [str(mkt.get("_built")), (rows.size() if rows != null else -1)])
	get_tree().quit(0)
