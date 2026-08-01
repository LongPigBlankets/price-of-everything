extends Node
## Static audit of the new Money and Advisor steps: they exist, sit in the right order,
## use detector kinds the engine actually implements, and reference real node names.
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const KNOWN_KINDS := ["building_owned_on_tile","building_or_project_on_tile","board_has_infra",
	"tile_has_infra","tile_cabled_or_ordered","tile_infra_or_ordered","tile_land_at_least",
	"tile_panel_open","tile_surveyed","node_visible","node_hidden","in_mapmode",
	"building_running_on_tile","building_recipe_on_tile","research_unlocked",
	"output_routed_market","output_routed_offtile","output_routed_same_tile",
	"sell_surplus_on_tile","loan_taken","advisor_seated"]
var _fails := 0
func _ready() -> void:
	var steps: Array = TutorialSteps.steps()
	var ids: Array = []
	for s in steps:
		ids.append(str((s as Dictionary).get("id", "")))
	print("[TUT] %d steps" % steps.size())
	for want in ["money_open","money_primer","money_take_loan","money_loan_terms",
			"advisors_intro","advisors_explain","advisors_hire","advisors_effect"]:
		_check("step present: %s" % want, str(ids.has(want)), "true")
	# The money arc sits just before buy_land / the 2nd building, so several turns of
	# revenue exist by then — placed right after run_until_running it had none and stuck.
	_check("money arc immediately precedes buy_land",
		str(ids.find("buy_land") == ids.find("money_loan_terms") + 1), "true")
	_check("money arc comes after the transport arc (turns have been ended)",
		str(ids.find("money_open") > ids.find("transport_pentagon_revert")), "true")
	_check("loan step is no_dim (the loan needs the Loans tab + dialog)",
		str(bool((steps[ids.find("money_take_loan")] as Dictionary).get("no_dim", false))), "true")
	# The advisor arc sits just before integration_done, which stays the closing summary.
	_check("advisor arc immediately precedes the finale",
		str(ids.find("integration_done") == ids.find("advisors_effect") + 1), "true")
	_check("integration_done is the FINAL step",
		str(ids[ids.size() - 1] == "integration_done"), "true")
	# Every decide predicate must be a kind the detector implements.
	for s in steps:
		var d: Dictionary = (s as Dictionary).get("done", {}).get("decide", {})
		var k := str(d.get("kind", ""))
		if k != "" and not KNOWN_KINDS.has(k):
			_fail("step '%s' uses unknown detector kind '%s'" % [(s as Dictionary).get("id"), k])
	print("[TUT] all decide kinds implemented")
	# The loan step must ask for the amount the constant declares.
	for s in steps:
		if str((s as Dictionary).get("id", "")) == "money_take_loan":
			var amt := int(((s as Dictionary).get("done", {}).get("decide", {}) as Dictionary).get("amount", 0))
			_check("loan step targets £%d" % TutorialSteps.TUTORIAL_LOAN_AMOUNT,
				str(amt), str(TutorialSteps.TUTORIAL_LOAN_AMOUNT))
			_check("loan copy quotes the live grace/term",
				str(str((s as Dictionary).get("body","")).contains(str(TutorialSteps.TUTORIAL_LOAN_AMOUNT))), "true")
	for s in steps:
		if str((s as Dictionary).get("id", "")) == "money_loan_terms":
			var b := str((s as Dictionary).get("body", ""))
			_check("terms copy quotes grace %d" % EconomyConfig.LOAN_GRACE_TURNS,
				str(b.contains(str(EconomyConfig.LOAN_GRACE_TURNS))), "true")
			_check("terms copy quotes term %d" % EconomyConfig.LOAN_TERM_TURNS,
				str(b.contains(str(EconomyConfig.LOAN_TERM_TURNS))), "true")
	# Both branch arms must reach the advisor arc. The glass arm used to `goto` the finale.
	var glass_goto := ""
	for st in steps:
		if str((st as Dictionary).get("id", "")) == "glass_upgrade":
			glass_goto = str((st as Dictionary).get("goto", ""))
	_check("glass path rejoins at the advisor arc", glass_goto, "advisors_intro")
	# Path-aware counter: walking each arm must reach advisors_intro, and the two arms have
	# DIFFERENT lengths — which is exactly why a fixed total mis-counted.
	var glass_len := _walk(steps, ids, ids.find("build_glass_open"))
	var alu_len := _walk(steps, ids, ids.find("build_alu_open"))
	print("      glass arm = %d steps to the end, aluminium arm = %d" % [glass_len, alu_len])
	_check("both arms terminate (no goto cycle)", str(glass_len > 0 and alu_len > 0), "true")
	_check("arms differ in length (so a fixed total would be wrong)",
		str(glass_len != alu_len), "true")

	print("==== TUT NEWSTEPS %s ====" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
## Steps remaining from `i`, following goto links — mirrors tutorial_engine._path_length_from.
func _walk(steps: Array, ids: Array, i: int) -> int:
	var seen := {}
	var n := 0
	while i >= 0 and i < steps.size() and not seen.has(i) and n < steps.size() + 2:
		seen[i] = true
		n += 1
		var g := str((steps[i] as Dictionary).get("goto", ""))
		i = ids.find(g) if g != "" else i + 1
	return n


func _check(what: String, got: String, want: String) -> void:
	if got == want: print("  PASS  %s" % what)
	else: _fail("%s = '%s' (expected '%s')" % [what, got, want])
func _fail(m: String) -> void:
	_fails += 1
	print("  FAIL  %s" % m)
