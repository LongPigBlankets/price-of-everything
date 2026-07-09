extends Node2D
## Diagnostic: market-input pipeline behavior for remote buildings (Arinnal).
## Places player factories on Arinnal tiles, feeds inputs from the market, runs
## N turns headless and logs the full pipeline per turn: stock, inbound
## shipments, power, money, starvation records. DIAG_MONEY env sets cash.
##   <godot> --headless --path . res://tools/diag_arinnal.tscn
const TURNS := 30
const SPECS := [
	{"tile": "tile_15_5", "building": "b_007", "recipe": "r_008", "energy": 80},
	{"tile": "tile_16_4", "building": "b_007", "recipe": "r_009", "energy": 30},
	# splice test: local wiring producer + a second consumer on the same tile —
	# local 32/turn < combined need 64/turn, so wiring is local+market spliced.
	{"tile": "tile_16_4", "building": "b_007", "recipe": "r_008", "energy": 80},
	{"tile": "tile_16_4", "building": "b_007", "recipe": "r_009", "energy": 30},
]
var _wm
var _starved_this_turn: Array = []

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	for _i in 16:
		await get_tree().process_frame
	var money := float(OS.get_environment("DIAG_MONEY").to_int()) if OS.get_environment("DIAG_MONEY") != "" else -1.0
	if money > 0.0:
		MatchState.money = money
	Production.building_starved.connect(func(rec: Dictionary) -> void: _starved_this_turn.append(rec))
	var terrain = _wm.get_node("%TerrainLayer")
	var bv = _wm.get_node("%BuildingVisuals")
	for si in SPECS.size():
		var s: Dictionary = SPECS[si]
		var coord: Vector2i = terrain.id_to_coord(str(s.tile))
		var iid: String = MatchState.add_building(str(s.building), str(s.recipe), str(s.tile), "player_1", "diag_%d" % si)
		bv.on_building_placed(str(s.tile), str(s.building), str(s.recipe), iid, coord)
	if OS.get_environment("DIAG_SELL") == "1":
		for s4 in SPECS:
			MatchState.enable_sell_surplus(str(s4.tile))
		print("[DIAG] sell-all-surplus ENABLED on spec tiles")
	print("[DIAG] money_start=%.0f specs=%d" % [MatchState.money, SPECS.size()])
	var inputs_by_tile: Dictionary = {}
	for s3 in SPECS:
		var rec: Dictionary = Catalog.get_recipe(str(s3.recipe))
		var gids: Array = []
		for inp in (rec.get("inputs", []) as Array):
			gids.append([str(inp.good_id), str(inp.get("internal_name", ""))])
		inputs_by_tile[str(s3.tile)] = gids
	print("[DIAG] turn|tile|good|stock|inbound_total|shipments(qty@eta)|power|money|starved")
	for t in TURNS:
		_starved_this_turn.clear()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var summ: Dictionary = Production.last_turn_summary
		for rec2 in (summ.get("input_orders_short", []) as Array):
			print("[DIAG] SHORT %s %s req=%d got=%d cost=%.0f" % [str(rec2.tile_id), str(rec2.good_id), int(rec2.requested), int(rec2.bought), float(rec2.short_cost)])
		for rec3 in (summ.get("input_splices", []) as Array):
			print("[DIAG] SPLICE %s %s need=%d local=%d market=%d" % [str(rec3.tile_id), str(rec3.good_id), int(rec3.need), int(rec3.local), int(rec3.market)])
		for s2 in SPECS:
			var tile := str(s2.tile)
			var powered := Power.is_supplied(tile, int(s2.energy))
			for pair in (inputs_by_tile[tile] as Array):
				var gid := str(pair[0])
				var stock: int = maxi(Stockpile.get_at_tile(tile, gid), Stockpile.get_at_tile(tile, str(pair[1])))
				var ships := MatchState.get_inbound_transport_shipments(tile, gid)
				var inbound := 0
				var ship_desc := ""
				for sh in ships:
					inbound += int(sh.get("qty", 0))
					ship_desc += "%d@%d," % [int(sh.get("qty", 0)), int(sh.get("turns_remaining", 0))]
				var starved := ""
				for rec in _starved_this_turn:
					if str(rec.get("tile_id", "")) == tile:
						starved = str(rec.get("missing", rec.get("good_id", "starved")))
				print("[DIAG] %d|%s|%s|%d|%d|%s|%s|%.0f|%s" % [
					TurnManager.current_turn, tile, gid, stock, inbound, ship_desc,
					"Y" if powered else "N", MatchState.money, starved])
	get_tree().quit(0)
