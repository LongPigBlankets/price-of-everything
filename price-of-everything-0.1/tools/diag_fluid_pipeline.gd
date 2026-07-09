extends Node2D
## Diagnostic: shipment lifecycle for the owner's tile_14_2 corridor scenario.
## Builds the reinf_pipes + rails corridor tile_14_2..tile_24_7 directly into the
## router, quotes + queues buys of the exact goods from the owner's log (steel,
## plastics, CPU, fuels, industrial acids), then steps turns and dumps every
## pending shipment's ETA, the overflow-held list, and tile stock — to find why
## fluid/plastics shipments sat "in transit" for 20+ turns in real play.
##   <godot> --headless --path . res://tools/diag_fluid_pipeline.tscn

const TILE := "tile_14_2"
const CORRIDOR := ["tile_14_2", "tile_15_3", "tile_16_3", "tile_17_4", "tile_18_4",
	"tile_19_5", "tile_20_5", "tile_20_6", "tile_21_7", "tile_22_7", "tile_23_8", "tile_24_7"]
const GOODS := {
	"g_006": 30,   # steel (solid_heavy)      — control, arrived fine in real play
	"g_027": 39,   # plastics (solid_light)   — froze at 190 in transit
	"g_041": 4,    # cpu (solid_light)        — churny but flowing
	"g_031": 84,   # fuels (liquid)           — froze at 84 for 22 turns
	"g_065": 7,    # industrial_acids (hazard_liquid) — froze at 7
}
const TURNS := 10

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var wm := packed.instantiate()
	add_child(wm)
	for _i in 16:
		await get_tree().process_frame
	MatchState.money = 100000.0
	var prefill := OS.get_environment("PREFILL").to_int() if OS.get_environment("PREFILL") != "" else 0
	if prefill > 0:
		Stockpile.add(TILE, "g_028", prefill)  # junk (rubber) to squeeze the tile toward its cap
		print("[DIAG] prefilled %s with %d junk -> used %d/%d" % [TILE, prefill, Stockpile.get_used_capacity(TILE), Stockpile.get_capacity(TILE)])

	var port := TransportService.nearest_port_tile(TILE)
	print("[DIAG] nearest port for %s = %s (hex dist %d)" % [TILE, port, TransportService.tile_distance(port, TILE)])

	_print_quotes("BEFORE corridor infra")
	for t in CORRIDOR:
		Catalog.add_tile_infrastructure(t, "reinf_pipes")
		Catalog.add_tile_infrastructure(t, "rail")
	_print_quotes("AFTER corridor infra")

	for gid in GOODS:
		var res: Dictionary = MatchState.queue_buy(TILE, str(gid), int(GOODS[gid]))
		print("[DIAG] queue_buy %s x%d -> %s" % [gid, int(GOODS[gid]),
			("qty=%d turns=%d cost=%.0f" % [int(res.get("qty", 0)), int(res.get("turns", 0)), float(res.get("cost", 0.0))]) if not res.is_empty() else "EMPTY (order refused)"])

	for _t in TURNS:
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		print("[DIAG] ---- end of turn %d ----" % TurnManager.current_turn)
		for s in MatchState.pending_transport_shipments:
			if bool(s.get("is_sale", false)):
				continue
			print("[DIAG]   pending %s x%d dest=%s eta=%d (of %d) src=%s" % [
				str(s.get("good_id", "")), int(s.get("qty", 0)), str(s.get("destination_tile", "")),
				int(s.get("turns_remaining", 0)), int(s.get("transport_turns", 0)), str(s.get("source_tile", ""))])
		for r in MatchState.overflow_shipments:
			print("[DIAG]   OVERFLOW %s x%d dest=%s waiting=%d" % [
				str(r.get("good_id", "")), int(r.get("qty", 0)), str(r.get("destination_tile", "")), int(r.get("turns_waiting", 0))])
		var stock_desc := ""
		for gid2 in GOODS:
			stock_desc += "%s=%d " % [gid2, Stockpile.get_at_tile(TILE, str(gid2))]
		print("[DIAG]   stock@%s: %s(used %d/%d)" % [TILE, stock_desc, Stockpile.get_used_capacity(TILE), Stockpile.get_capacity(TILE)])
		print("[DIAG]   pipeline-visible inbound fuels(g_031)=%d acids(g_065)=%d  (in-flight + overflow-held)" % [
			Production._inbound_qty(TILE, "g_031"), Production._inbound_qty(TILE, "g_065")])
	get_tree().quit(0)

func _print_quotes(label: String) -> void:
	print("[DIAG] quotes %s:" % label)
	for gid in GOODS:
		var q: Dictionary = TransportService.quote_market_buy(TILE, str(gid), int(GOODS[gid]), false)
		if q.is_empty():
			print("[DIAG]   %s: NO QUOTE (unreachable/no pipe at port)" % gid)
		else:
			var route: Dictionary = q.get("route", {})
			var legs: Array = route.get("legs", [])
			var modes := ""
			for l in legs:
				modes += str(l.get("mode", "")) + ","
			print("[DIAG]   %s: turns=%d cost=%.0f legs=[%s]" % [gid, int(q.get("turns", 0)), float(q.get("cost", 0.0)), modes])
