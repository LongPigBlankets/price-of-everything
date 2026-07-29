extends Node
## Which tiles carry a given deposit, ranked by hex distance from a start tile — so a
## chain whose deposit will exhaust knows where its 2nd (and 3rd) mine has to go.
##   <godot> --headless --path . res://tools/deposit_survey.tscn --quit-after 6000
const MAIN_SCENE := "res://scenes/main.tscn"
const QUERIES := [
	{"label": "MAGNATE coal  (start tile_6_8)",   "from": "tile_6_8",  "token": "coal"},
	{"label": "MAGNATE iron  (start tile_7_10)",  "from": "tile_7_10", "token": "iron_ore"},
	{"label": "MOTOR   coal  (start tile_22_3)",  "from": "tile_22_3", "token": "coal"},
	{"label": "MOTOR   iron  (start tile_26_5)",  "from": "tile_26_5", "token": "iron_ore"},
]
var _main: Node = null
var _started := false
var _frames := 0

func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _started: return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 6000:
		get_tree().quit(1)

func _run() -> void:
	for q in QUERIES:
		var from := str(q["from"])
		var token := str(q["token"])
		var rows: Array = []
		for t in Catalog.all_tiles():
			var tid := str(t.get("id", ""))
			var qty := MatchState.deposit_remaining_for(tid, token)
			if qty == 0:
				continue   # tile has no such deposit
			rows.append({"tile": tid, "d": Catalog.tile_hex_distance(from, tid), "qty": qty,
				"type": str(t.get("type", "")), "nick": str(t.get("nickname", ""))})
		rows.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]) if int(a["d"]) != int(b["d"]) else str(a["tile"]) < str(b["tile"]))
		print("\n=== %s : %d tiles carry %s ===" % [str(q["label"]), rows.size(), token])
		for i in range(mini(6, rows.size())):
			var r: Dictionary = rows[i]
			print("  %s dist %-3d %-12s qty %-8s %-10s %s" % [
				"START  " if int(r["d"]) == 0 else "  #%-4d" % i, int(r["d"]), str(r["tile"]),
				("unbounded" if int(r["qty"]) < 0 else str(int(r["qty"]))), str(r["type"]), str(r["nick"])])
	get_tree().quit(0)
