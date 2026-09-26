extends RefCounted
## Tile view v3, Buildings tab: what the tab says about each of your buildings, all from the engine.
## - The lamp: Building Detail's diagnostics rolled up (BuildingReadout.diagnostics, diagnostic_led_tone).
## - The words beside it, from the same rows, so the two cannot disagree: while the lamp is green, what the
##   first green row says ("Operating normally"); while it is amber or red, the cause of each row at that
##   tone in a few words ("Grid power, market inputs").
## - A building the engine's run state calls stalled makes nothing this turn, so its output reads 0. When
##   no diagnostics row says why (a generator on a tile with no cables: its rows say only that it
##   generates), a row for the stall goes first, in Building Detail's own words for it (its header's
##   "Stalled" and its power checks' sentence), so the lamp, the words and the 0 agree. A paused building
##   gets a row saying so.
## - The hover readout's check: the worst row (the first red, else the first amber, else the first), as
##   Building Detail's readout picks it, with the engine's sentence in full.
## - This turn's output (BuildingReadout.flow with this_turn: levels, ramp and intermittency applied) and what
##   a unit of it costs to make against the market (BuildingReadout.cost_to_produce).
## The diagnostics take about 3 ms a building, and the tab is rebuilt on every refresh, so readings are kept
## on the panel for the turn and shown from there; buildings_recheck.gd works them out again over the next
## frames and refreshes the panel if anything shown has changed.

const BuildingReadout := preload("res://scripts/building_readout.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")

const META_READINGS := "tvp_bl_readings"
const RANK := {"ok": 0, "warn": 1, "bad": 2}
## Diagnostics rows that already say why a building makes nothing.
const STALL_EXPLAINED := ["Deposit exhausted", "Critical fault", "Cannot run", "Unpowered", "Starved of inputs",
	"Middleman service"]
const STALLED_DETAIL := "It makes nothing this turn."
const PAUSED_DETAIL := "Paused. It makes nothing until it is resumed."


## One of your buildings as the tab shows it:
## {tone, causes (the words' parts), check {name, detail, tone}, runs, outputs [{good_id, qty}], cost {}}.
## `runs` is false while the engine's run state says it is stalled (BuildingReadout.run_state: no cables,
## short of inputs, its deposit worked out) or the player has paused it: it makes nothing this turn, so
## its outputs are read as 0. A battery's well shows the cells it holds, not output, so it always "runs".
static func reading(b: Dictionary) -> Dictionary:
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	var bd: Dictionary = Catalog.get_building(str(b.get("building_id", "")))
	var category := str(bd.get("category", "")).to_lower()
	var infra := category == "infrastructure"
	var rows: Array = BuildingReadout.diagnostics(b, recipe, bd, infra)
	var outs: Array = []
	var runs := true
	if category == "battery":
		var chem := _battery_chem(str(b.get("tile_id", "")))
		if not chem.is_empty():
			outs.append(chem)
	elif not recipe.is_empty():
		var paused := BuildingWorks.is_building_paused(str(b.get("instance_id", "")))
		var stalled := BuildingReadout.run_state(b, recipe, infra) == "stalled"
		runs = not stalled and not paused
		if paused:
			# Said whatever else is wrong: the player's pause is why it makes nothing this turn.
			rows.push_front({"tone": "warn", "label": "Paused", "detail": PAUSED_DETAIL, "cause": "paused", "always": true})
		elif stalled and not stall_explained(rows):
			rows.push_front(stall_row(b, recipe, infra))
		for o: Dictionary in BuildingReadout.flow(b, recipe, true).get("outputs", []):
			if str(o.get("good_id", "")) != "":
				outs.append({"good_id": str(o.get("good_id", "")), "qty": int(o.get("qty", 0)) if runs else 0})
	var r := status_of(rows)
	r["runs"] = runs
	r["outputs"] = outs
	var cost: Dictionary = {}
	if category != "battery" and category != "infrastructure":
		for c: Dictionary in BuildingReadout.cost_to_produce(b):
			if cost.is_empty() or (not outs.is_empty() and str(c.get("good_id", "")) == str(outs[0].get("good_id", ""))):
				cost = c
	r["cost"] = cost
	return r


## True when a red diagnostics row already says why the building makes nothing.
static func stall_explained(rows: Array) -> bool:
	for row: Dictionary in rows:
		var label := str(row.get("label", ""))
		if STALL_EXPLAINED.has(label) or (str(row.get("tone", "")) == "bad" and label.begins_with("No transport route")):
			return true
	return false


## The row for a stall no other row explains, as Building Detail says it: its header's "Stalled", and why
## from the checks the run state reads. With no cables on the tile (Power.is_supplied: power can neither
## reach it nor leave it), the sentence is its power checks' own ("No cables on this tile...").
static func stall_row(b: Dictionary, recipe: Dictionary, infra: bool) -> Dictionary:
	if not Power.is_supplied(str(b.get("tile_id", ""))):
		for c: Dictionary in BuildingReadout.power_checks(b, recipe, infra):
			if str(c.get("key", "")) == "cable" and str(c.get("tone", "")) == "bad":
				return {"tone": "bad", "label": "Stalled", "detail": str(c.get("detail", "")),
					"cause": "stalled with no cables"}
	return {"tone": "bad", "label": "Stalled", "detail": STALLED_DETAIL, "cause": "stalled"}


## The lamp, the words' parts and the readout's check from Building Detail's diagnostics rows. A row marked
## "always" (the player's pause) is in the words whatever the lamp's tone.
static func status_of(rows: Array) -> Dictionary:
	var tone := BuildingReadout.diagnostic_led_tone(rows)
	var causes: Array = []
	if tone == "ok":
		for row: Dictionary in rows:
			if str(row.get("tone", "")) == "ok":
				causes.append(_ok_words(row))
				break
	else:
		for row: Dictionary in rows:
			if str(row.get("tone", "")) == tone or bool(row.get("always", false)):
				var c := cause(row)
				if c != "" and not causes.has(c):
					causes.append(c)
	var worst: Dictionary = {}
	for want in ["bad", "warn"]:
		for row: Dictionary in rows:
			if str(row.get("tone", "")) == want:
				worst = row
				break
		if not worst.is_empty():
			break
	if worst.is_empty() and not rows.is_empty():
		worst = rows[0]
	var check := {"name": plain(str(worst.get("label", ""))), "detail": plain(str(worst.get("detail", ""))),
		"tone": str(worst.get("tone", ""))}
	return {"tone": tone, "causes": causes, "check": check}


## A green row's words: the all-clear row says what it found ("Operating normally", "Ready to run"); any
## other green row is named by its label.
static func _ok_words(row: Dictionary) -> String:
	var detail := plain(str(row.get("detail", ""))).trim_suffix(".")
	if str(row.get("label", "")) == "No critical faults" and detail != "":
		return detail
	return plain(str(row.get("label", "")))


## An amber or red row's cause, in the few words the line beside the lamp has room for. The engine's own
## label where it says enough; where the label only names the check ("Powered", "Input sourcing"), what
## made it amber or red. The hover readout carries the engine's full sentence.
static func cause(row: Dictionary) -> String:
	if row.has("cause"):
		return str(row.cause)
	var label := str(row.get("label", ""))
	var detail := str(row.get("detail", ""))
	var tone := str(row.get("tone", ""))
	match label:
		"Powered":
			return "grid power"
		"Ready to draw power":
			return "not drawing power yet"
		"Input sourcing":
			return "short of inputs" if tone == "bad" else "market inputs"
		"Starting":
			return "starts next turn" if detail.begins_with("All inputs") else "starts when inputs land"
		"Critical fault":
			return "no power" if detail.contains("power") else "missing inputs"
		"Cannot run", "Unpowered":
			return "short of inputs" if label == "Cannot run" else "no power"
		"Stockpile over-utilised":
			return "warehouse full"
		"Outputs cannot reach destination":
			return "output cannot ship"
		"Even with market":
			return "cost near market price"
		"Power output capped":
			return "output capped by cables"
		"Intermittent generation":
			return "output not firmed"
		"Partly firmed generation":
			return "output partly firmed"
		"Middleman service":
			return "intermediary cannot supply it"
	if label.begins_with("Output destination"):
		return "slow route out"
	if label.begins_with("Transport to destination is "):
		return label.trim_prefix("Transport to destination is ") + " freight out"
	if label.begins_with("Transport could be cheaper using "):
		return label.trim_prefix("Transport could be cheaper using ").to_lower() + " would be cheaper"
	if label.begins_with("Intermittent power"):
		return "derated in lulls"
	if label.begins_with("Partly intermittent"):
		return "partly derated in lulls"
	return lower_first(plain(label))


## The words for `causes` beside a lamp whose line is `width` wide in body type, on at most two lines:
## - all of them ("Grid power, market inputs"), wrapping onto a second line if they need it;
## - else as many as fit two lines and how many more ("Grid power and 2 more"), else the first alone.
## `lead` goes before them ("4 buildings: ", the first cause then in lower case). When the lead and the
## causes don't fit one line, the lead has the first line and the causes the second ("4 buildings:" over
## "Grid power, market inputs"), so a line never breaks inside the list.
static func fit(causes: Array, width: float, lead := "") -> String:
	if causes.is_empty():
		return lead.trim_suffix(": ")
	var all := ", ".join(causes)
	if lead != "":
		var one: String = lead + lower_first(all)
		if width <= 0.0 or Parts.body_width(one) <= width:
			return one
		return lead.strip_edges() + "\n" + _fit_line(causes, width)
	if width <= 0.0 or Parts.body_width(sentence(all)) <= width * 1.8:
		return sentence(all)
	return _fit_line(causes, width * 1.8)


## As many of `causes` as fit `width` and how many more, sentence case; else the first alone.
static func _fit_line(causes: Array, width: float) -> String:
	var all := sentence(", ".join(causes))
	if Parts.body_width(all) <= width:
		return all
	for n in range(causes.size() - 1, 0, -1):
		var s := sentence("%s and %d more" % [", ".join(causes.slice(0, n)), causes.size() - n])
		if Parts.body_width(s) <= width:
			return s
	return sentence(str(causes[0]))


## A group's reading, from its members' readings:
## - tone: the worst member's lamp.
## - causes: the words that explain it. All at one tone: what most of the members say (all of them, when
##   they agree). At different tones: how many are at each ("1 fault, 3 warnings").
## - extra: per member, the causes its row on the cable adds to the head's: none for a member that says
##   what the head says, only the rest for one that says more, all of its own at different tones.
## - outputs: what the members that run make this turn (a stalled one adds 0), and runs: whether any runs.
## - cost: its dearest unit; check: the worst member's check for the readout.
static func group_reading(readings: Array, names: Array) -> Dictionary:
	var worst := "ok"
	var worst_at := 0
	var counts := {"bad": 0, "warn": 0, "ok": 0}
	var one_tone := true
	var runs := false
	var said := {}
	var said_order: Array = []
	for i in readings.size():
		var r: Dictionary = readings[i]
		var t := str(r.tone)
		counts[t] = int(counts.get(t, 0)) + 1
		runs = runs or bool(r.get("runs", true))
		if int(RANK.get(t, 0)) > int(RANK.get(worst, 0)):
			worst = t
		if t != str((readings[0] as Dictionary).tone):
			one_tone = false
		var words := str(r.causes)
		if not said.has(words):
			said[words] = 0
			said_order.append(words)
		said[words] = int(said[words]) + 1
	# The readout: the first member at the worst tone.
	for i in readings.size():
		if str((readings[i] as Dictionary).tone) == worst:
			worst_at = i
			break
	var usual := ""
	for words: String in said_order:
		if usual == "" or int(said[words]) > int(said[usual]):
			usual = words
	var causes: Array = []
	if one_tone:
		for r: Dictionary in readings:
			if str(r.causes) == usual:
				causes = r.causes
				break
	else:
		for t in ["bad", "warn", "ok"]:
			var n := int(counts.get(t, 0))
			if n == 0:
				continue
			match t:
				"bad": causes.append("%d %s" % [n, "fault" if n == 1 else "faults"])
				"warn": causes.append("%d %s" % [n, "warning" if n == 1 else "warnings"])
				"ok": causes.append("%d normal" % n)
	var extra: Array = []
	for r: Dictionary in readings:
		var own: Array = []
		for c in r.causes:
			if not one_tone or not causes.has(c):
				own.append(c)
		extra.append(own)
	var totals := {}
	var order: Array = []
	var dearest: Dictionary = {}
	for r: Dictionary in readings:
		for o: Dictionary in r.outputs:
			var gid := str(o.good_id)
			if not totals.has(gid):
				totals[gid] = 0
				order.append(gid)
			totals[gid] = int(totals[gid]) + int(o.qty)
		var c: Dictionary = r.cost
		if not c.is_empty() and (dearest.is_empty() or float(c.unit_cost) > float(dearest.unit_cost)):
			dearest = c
	var outs: Array = []
	for gid: String in order:
		outs.append({"good_id": gid, "qty": int(totals[gid])})
	var check: Dictionary = ((readings[worst_at] as Dictionary).check as Dictionary).duplicate()
	check["stage"] = str(names[worst_at]) if worst_at < names.size() else ""
	return {"tone": worst, "lead": "%d buildings: " % readings.size(), "causes": causes, "outputs": outs,
		"runs": runs, "cost": dearest, "check": check, "extra": extra}


## The worst of several checks ({stage, name, detail, tone}): the first red, else the first amber, else the
## first, as Building Detail's readout picks among its indicators.
static func worst_check(checks: Array) -> Dictionary:
	for want in ["bad", "warn"]:
		for c: Dictionary in checks:
			if str(c.get("tone", "")) == want:
				return c
	return checks[0] if not checks.is_empty() else {}


## Readings for `buildings` (instance id -> reading). One kept on the panel from this turn is shown as it
## is, and its building goes in `recheck`, to be worked out again after this refresh; anything else is
## worked out now. Only this tile's readings are kept.
static func readings_for(panel: Control, buildings: Array) -> Dictionary:
	var old: Dictionary = panel.get_meta(META_READINGS, {})
	var turn := int(TurnManager.current_turn)
	var kept := {}
	var out := {}
	var recheck: Array = []
	for b: Dictionary in buildings:
		var iid := str(b.get("instance_id", ""))
		var stamp := "%d|%s|%d" % [turn, str(b.get("recipe_id", "")), int(b.get("level", 1))]
		var hit: Dictionary = old.get(iid, {})
		if not hit.is_empty() and str(hit.get("stamp", "")) == stamp:
			out[iid] = hit.r
			recheck.append(b)
		else:
			out[iid] = reading(b)
		kept[iid] = {"stamp": stamp, "r": out[iid]}
	panel.set_meta(META_READINGS, kept)
	return {"readings": out, "recheck": recheck}


## What a reading shows, to tell whether working it out again changed anything on screen.
static func digest(r: Dictionary) -> String:
	var c: Dictionary = r.get("cost", {})
	return str([r.get("tone", ""), r.get("causes", []), r.get("runs", true), r.get("outputs", []), r.get("check", {}),
		"%.2f" % float(c.get("unit_cost", -1.0)), "%.2f" % float(c.get("market_price", -1.0)), str(c.get("color", ""))])


## The chemistry most loaded in the tile's batteries, as the v2 card shows it.
static func _battery_chem(tile_id: String) -> Dictionary:
	var cells: Dictionary = Power.get_tile_battery_cells(tile_id)
	var best := ""
	var qty := 0
	for gid in cells:
		if int(cells[gid]) > qty:
			qty = int(cells[gid])
			best = str(gid)
	return {} if best == "" else {"good_id": best, "qty": qty}


## The engine's sentences, in the house copy: no dashes or middle dots, and no doubled spaces.
static func plain(text: String) -> String:
	var t := text.replace(" — ", ", ").replace(" – ", ", ").replace(" · ", ", ").replace("—", ", ").replace("·", ",")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.replace(" ,", ",").strip_edges()


static func sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


## Lower-cases the first letter, unless the first word is an acronym or a name that stays capitalised.
static func lower_first(text: String) -> String:
	if text.length() < 2 or text.substr(1, 1) == text.substr(1, 1).to_upper():
		return text
	return text.substr(0, 1).to_lower() + text.substr(1)
