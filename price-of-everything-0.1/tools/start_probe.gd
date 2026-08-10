extends Node2D
## Run a start config headlessly for N turns and print its per-turn economics.
##
## The e2e harness plays open_field_1 with a scripted optimal build-out; this answers a
## different question — what does a SHIPPED START do if the player just runs it? That is the
## experience a new player actually has, and it is what the delivered telemetry showed going
## wrong. Existing to make "how would metal_magnate behave now" measurable instead of estimated.
##
##   Godot --headless --path . res://tools/start_probe.tscn -- metal_magnate 40 [andrew=coo]
##
## The optional third argument seats the founder (spec §5.4) so his gift and modifiers are in
## play from turn 1 rather than turn 3 — the point is the steady state, not the arrival.

const START_DIR := "res://data/starts/%s.json"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var start_name := str(args[0]) if args.size() > 0 else "metal_magnate"
	var turns := int(args[1]) if args.size() > 1 else 40
	var andrew := ""
	for a in args:
		if str(a).begins_with("andrew="):
			andrew = str(a).split("=")[1]

	await get_tree().process_frame
	if not FileAccess.file_exists(START_DIR % start_name):
		print("[PROBE] cannot read start '%s'" % start_name)
		get_tree().quit(1)
		return
	# The start must be applied through the REAL boot path: importing a snapshot without the
	# map leaves no terrain or deposits, so every mine yields nothing and the probe measures a
	# company that cannot produce. prepare_new_game + the main scene is how the game does it.
	SaveLoad.prepare_new_game(START_DIR % start_name)
	var world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in range(160):
		await get_tree().process_frame

	if andrew != "":
		MatchState.seat_founder(andrew)
		if andrew == "cfo":
			LoanState.take_founder_loan(200.0, 0.05)
		else:
			MatchState.add_freight_credit(1000)
			Modifiers.add({"id": "andrew_transport", "domain": "transport_cost", "pct": -20.0,
				"label": "Andrew Keeler: -20% transport costs", "source": "advisor"})

	print("[PROBE] start=%s turns=%d andrew=%s labour_mult=%.2f pressure=%.1f" % [
		start_name, turns, andrew if andrew != "" else "none",
		MatchState.labour_multiplier, MatchState.labour_output_pressure_pct])
	print("[PROBE] %4s %10s %9s %9s %9s %8s %8s %8s %8s %6s" % [
		"turn", "money", "revenue", "profit", "transport", "inputs", "labour", "maint", "power", "bldgs"])

	for i in range(turns):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var s: Dictionary = Production.last_turn_summary
		if s.is_empty():
			continue
		var revenue := float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0))
		var profit := float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
		print("[PROBE] %4d %10.2f %9.2f %9.2f %9.2f %8.2f %8.2f %8.2f %8.2f %6d" % [
			TurnManager.current_turn - 1, MatchState.money, revenue, profit,
			float(s.get("transport_paid", 0.0)), float(s.get("goods_purchased_cost", 0.0)),
			float(s.get("labour_paid", 0.0)), float(s.get("maintenance_paid", 0.0)),
			float(s.get("power_purchase_cost", 0.0)), MatchState.player_building_count()])

	print("[PROBE] freight_credit_left=%d loans=%.2f" % [
		MatchState.freight_credit_units, LoanState.total_outstanding()])
	get_tree().quit()
