extends Node
## Jumps the LIVE tutorial to each new step and reports whether its spotlight target
## actually resolves in the tree — a step whose ref never resolves shows no highlight and
## the player is left with a card pointing at nothing.
const STEPS := ["capital_motor_open", "capital_motor_route", "capital_money_transport",
	"capital_fluids", "capital_port_open", "capital_port_costs",
	"money_open", "money_primer", "money_take_loan", "money_loan_terms",
	"advisors_intro", "advisors_explain", "advisors_hire", "advisors_effect"]
var _t := 0.0
var _built := false
var _i := -1
var _next := 0.0
var _fails := 0
func _process(delta: float) -> void:
	_t += delta
	if not _built:
		var scene := get_tree().current_scene
		if scene != null and bool(scene.get("build_complete")):
			_built = true
			_next = _t + 1.5
			for iid in MatchState.buildings:   # own the seeded factory so panels open
				var inst: Dictionary = MatchState.buildings[iid]
				if str(inst.get("tile_id", "")) == "tile_5_9":
					inst["owner"] = MatchState.LOCAL_PLAYER
		return
	if _t < _next:
		return
	_next = _t + 1.2
	if _i >= 0 and _i < STEPS.size():
		_report(STEPS[_i])
	_i += 1
	if _i >= STEPS.size():
		print("==== TUT SPOTLIGHTS %s ====" % ("PASS" if _fails == 0 else "%d UNRESOLVED" % _fails))
		get_tree().quit(0 if _fails == 0 else 1)
		return
	var idx := _index_of(STEPS[_i])
	if idx >= 0:
		Tutorial._enter(idx)

func _index_of(id: String) -> int:
	for i in Tutorial._steps.size():
		if str((Tutorial._steps[i] as Dictionary).get("id", "")) == id:
			return i
	return -1

func _report(id: String) -> void:
	var idx := _index_of(id)
	if idx < 0:
		print("  FAIL  %s: not in the live step list" % id); _fails += 1; return
	var step: Dictionary = Tutorial._steps[idx]
	var spot: Dictionary = step.get("spotlight", {})
	var ref := str(spot.get("ref", ""))
	var kind := str(spot.get("kind", "none"))
	var mode := str(step.get("mode", ""))
	var ok := true
	var detail := ""
	if kind == "node_name" and ref != "":
		var n = get_tree().root.find_child(ref, true, false)
		ok = n != null and n is Control and (n as Control).is_visible_in_tree()
		detail = "spotlight '%s' %s" % [ref, "resolved+visible" if ok else "NOT RESOLVED"]
	else:
		detail = "spotlight kind=%s (nothing to resolve)" % kind
	# annotate steps must also resolve their leader-line targets
	var missing: Array = []
	for t in step.get("targets", []):
		var tref := str((t as Dictionary).get("ref", ""))
		var tn = get_tree().root.find_child(tref, true, false)
		if tn == null:
			missing.append(tref)
	if not missing.is_empty():
		ok = false
		detail += " · UNRESOLVED targets: %s" % str(missing)
	elif mode == "annotate":
		detail += " · all %d annotate targets resolved" % (step.get("targets", []) as Array).size()
	if not ok:
		_fails += 1
	print("  %s  %-18s %s" % ["PASS" if ok else "FAIL", id, detail])
