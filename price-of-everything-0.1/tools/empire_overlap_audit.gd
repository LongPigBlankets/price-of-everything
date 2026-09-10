extends Node
## THE OVERLAP AUDIT (owner 2026-09-10: "measure it"). Boots the real game headless, seeds the
## same thirteen buildings the sprite-swap shot uses, opens the supply-chain view, runs its
## frame-geometry pass and reads the occupancy registry: how many sprites, plumes, plates,
## badges, ports, lines and chips collide, by kind pair. Prints the report, then gates on
## BASELINE — any pair class above its frozen count fails the run. Lower a number when a
## change earns it; never raise one without saying why in the commit.
##   <godot> --headless --path . res://tools/empire_overlap_audit.tscn --quit-after 900
## Exit 0 = within baseline, 1 = a class regressed (or the view could not be built).

## Frozen counts (kind pairs sorted alphabetically, "a|b"). Missing key = 0 allowed.
## 2026-09-10 freeze after the FLOW layout (buy ports left, sell ports right): 13 nodes /
## 38 routes / 23 chips, 2 collisions — two buy-line chips with no free slot in the port
## gutter. Was 39 before the occupancy model and 9 with the top/bottom port rows.
const BASELINE := {
	"chip|chip": 0,
	"chip|sprite": 0,
	"chip|plate": 0,
	"chip|port": 0,
	"chip|route": 2,
	"plate|plate": 0,
	"sprite|sprite": 0,
	"plate|sprite": 0,
	"fx|sprite": 0,
	"fx|plate": 0,
	"fx|fx": 0,
	"badge|sprite": 0,
	"port|sprite": 0,
	"route|sprite": 0,
	"route|plate": 0,
	"route|fx": 0,
	"route|port": 0,
	"route|badge": 0,
	"fx|port": 0,
	"badge|fx": 0,
	"badge|route": 0,
	"badge|chip": 0,
	"chip|fx": 0,
}


func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	_seed()
	await _settle(4)
	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	if ev == null:
		push_error("EmpireView not found")
		get_tree().quit(1)
		return
	ev.call("toggle")
	await _settle(16)
	var gw: Node = ev.get_node_or_null("GraphWorld")
	if gw == null:
		push_error("GraphWorld not found")
		get_tree().quit(1)
		return
	gw.call("_reposition_panels")
	var rep: Dictionary = gw.call("audit")
	print("AUDIT items: ", JSON.stringify(rep["items"]))
	print("AUDIT counts: ", JSON.stringify(rep["counts"]))
	for line in rep["named"]:
		print("AUDIT pair: ", line)
	var failed := 0
	var counts: Dictionary = rep["counts"]
	for k in counts:
		var allowed := int(BASELINE.get(k, 0))
		if int(counts[k]) > allowed:
			print("AUDIT REGRESSION %s: %d > baseline %d" % [k, int(counts[k]), allowed])
			failed += 1
	print("AUDIT total collisions: ", int(rep["total"]), "  regressed classes: ", failed)
	get_tree().quit(1 if failed > 0 else 0)


## The sprite-swap shot's seed: factories, furnaces, mines and power plants at L1/L2/L3 plus
## an arc furnace — every effect family (plume, glow, bay, licks) and every route family.
func _seed() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	var bids := ["b_007", "b_007", "b_007", "b_002", "b_002", "b_002",
			"b_001", "b_001", "b_001", "b_003", "b_003", "b_003", "b_008"]
	var levels := [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1]
	for k in range(bids.size()):
		var recs: Array = Catalog.get_recipes_for_building(bids[k])
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var iid := "aud_%d" % k
		MatchState.add_building(bids[k], rid, tiles[(k * 3) % tiles.size()], "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
