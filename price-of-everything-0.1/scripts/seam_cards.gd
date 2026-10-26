extends RefCounted
## A seam running out (docs/pacing-labour-mining-licensing-spec.md §8.7). When a finite site falls to a quarter of
## its starting size, once per site, a decision card offers to sink a deeper shaft, rob the pillars, blast, sell
## with the reserves or carry on. Owned by MatchState (`MatchState.seams`) and saved with its fields: the card
## offered, each site's way of working the rest of its seam, the turns a site stays offline, and its own RNG.
## Ticked in PROCESS before production (the blasting rolls and the robbing accidents), aged in NARRATIVE. The
## site's figures are MiningSites' (scripts/mining_sites.gd), derived, never saved.

signal changed

const MiningSites := preload("res://scripts/mining_sites.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")
const LabourUnrest := preload("res://scripts/labour_unrest.gd")

const CARD_ID := "seam_running_out"
## The card comes once a finite seam is down to this share of its starting size.
const LOW_SHARE := 0.25
const OFFLINE_TURNS := 2
## Sink a deeper shaft: two turns of the site's wages plus a level 1 kit, offline 2 turns, 40% more seam, then
## site labour ×1.4 and power ×1.5 until it ends.
const SHAFT_WAGE_TURNS := 2.0
const SHAFT_ADD := 0.40
const SHAFT_LABOUR := 1.4
const SHAFT_POWER := 1.5
## Rob the pillars: 25% more seam, site labour ×1.5, a 3% accident chance a working a turn (halved under High
## safety, doubled under Minimal), and the workings collapse when the seam ends.
const ROB_ADD := 0.25
const ROB_LABOUR := 1.5
const ROB_ACCIDENT := 0.03
## Heavy blasting, one seeded roll a turn: a double dig, a roof fall (offline 2 turns) or the rest lost.
const BLAST_DOUBLE := 0.25
const BLAST_ROOF := 0.08
const BLAST_LOST := 0.02
## Sell with reserves: the buildings' sale price plus what remains at this share of market.
const SALE_SHARE := 0.5
## An endless seam that collapses stops its mines this many turns (a finite one loses what remains).
const COLLAPSE_OFFLINE_TURNS := 3
## Seeds the seam RNG from the match seed (stable arithmetic, never hash()).
const RNG_SALT := 0x5EA3C4

const SHAFT := "shaft"
const ROBBING := "robbing"
const BLASTING := "blasting"

## Sites the card has been offered for: "tile|token" -> true.
var offered: Dictionary = {}
## How each site works the rest of its seam: "tile|token" -> SHAFT, ROBBING or BLASTING.
var modes: Dictionary = {}
## Sites offline: "tile|token" -> turns left, counting the current one.
var offline: Dictionary = {}
## Blasting sites that dig double this turn. Set in PROCESS, read by production the same turn, never saved.
var double_dig: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rng_seeded := false


static func key(tile_id: String, token: String) -> String:
	return "%s|%s" % [tile_id, token]


func reset() -> void:
	offered.clear()
	modes.clear()
	offline.clear()
	double_dig.clear()
	_rng_seeded = false


func export_fields() -> Dictionary:
	_ensure_rng()
	return {
		"seam_offered": offered.duplicate(true),
		"seam_modes": modes.duplicate(true),
		"seam_offline": offline.duplicate(true),
		"seam_rng_seed": SaveLoad.int64_out(_rng.seed),
		"seam_rng_state": SaveLoad.int64_out(_rng.state),
	}


## Older saves carry none of this and load with no card offered.
func import_fields(d: Dictionary) -> void:
	offered = (d.get("seam_offered", {}) as Dictionary).duplicate(true)
	modes = (d.get("seam_modes", {}) as Dictionary).duplicate(true)
	offline.clear()
	for k in (d.get("seam_offline", {}) as Dictionary):
		offline[str(k)] = int((d.get("seam_offline", {}) as Dictionary)[k])
	double_dig.clear()
	_rng_seeded = d.has("seam_rng_seed")
	if _rng_seeded:
		_rng.seed = SaveLoad.int64_in(d.get("seam_rng_seed"), 0)
		_rng.state = SaveLoad.int64_in(d.get("seam_rng_state"), _rng.state)


func _ensure_rng() -> void:
	if _rng_seeded:
		return
	_rng.seed = int(MatchState.match_rng_seed) ^ RNG_SALT
	_rng_seeded = true


# ── The turn ─────────────────────────────────────────────────────────────────────────────────────

## PROCESS, before production: each seam past its limit may collapse, then each blasting site's roll and each
## robbing working's accident chance.
func tick(turn: int) -> void:
	double_dig.clear()
	_roll_collapses()
	if modes.is_empty():
		return
	_ensure_rng()
	var keys: Array = modes.keys()
	keys.sort()
	for k: String in keys:
		var tile_id := k.get_slice("|", 0)
		var token := k.get_slice("|", 1)
		match str(modes[k]):
			BLASTING:
				if is_offline(tile_id, token):
					continue
				var roll := _rng.randf()
				if roll < BLAST_LOST:
					_bell("seam_lost", "critical", "Seam lost", "Heavy blasting at %s brought down the rest of the seam." % _place(tile_id))
					MatchState.deplete_deposit(tile_id, token, maxi(0, MatchState.deposit_remaining_for(tile_id, token)))
				elif roll < BLAST_LOST + BLAST_ROOF:
					offline[k] = OFFLINE_TURNS
					_bell("roof_fall", "warning", "Roof fall", "A roof fall at %s stops the workings for %d turns." % [_place(tile_id), OFFLINE_TURNS])
				elif roll < BLAST_LOST + BLAST_ROOF + BLAST_DOUBLE:
					double_dig[k] = true
			ROBBING:
				var chance := ROB_ACCIDENT * _safety_factor()
				for iid: String in MiningSites.site(tile_id, token).workings:
					if LabourState.unrest.is_down(iid):
						continue
					if _rng.randf() < chance:
						LabourState.unrest.cause_accident(iid, turn)
	changed.emit()


## A seam worked past its limit may collapse (owner ruling, 26 October 2026): MiningSites' chance a turn, one
## seeded roll a site, in key order.
func _roll_collapses() -> void:
	var sites: Dictionary = MiningSites.player_sites()
	var keys: Array = sites.keys()
	keys.sort()
	for k: String in keys:
		var site: Dictionary = sites[k]
		if float(site.collapse) <= 0.0 or is_offline(str(site.tile_id), str(site.token)):
			continue
		_ensure_rng()
		if _rng.randf() < float(site.collapse):
			collapse(str(site.tile_id), str(site.token))


## A seam collapses: a finite one loses what remains, an endless one stops its mines for COLLAPSE_OFFLINE_TURNS.
func collapse(tile_id: String, token: String) -> void:
	var name := "%s seam at %s" % [str(Catalog.get_good_by_internal_name(token).get("display_name", token)).to_lower(), _place(tile_id)]
	if MiningSites.kind(tile_id, token) == MiningSites.FINITE:
		_bell("seam_collapsed", "critical", "Seam collapsed", "The %s collapsed. What remained is lost." % name)
		MatchState.deplete_deposit(tile_id, token, maxi(0, MatchState.deposit_remaining_for(tile_id, token)))
	else:
		offline[key(tile_id, token)] = COLLAPSE_OFFLINE_TURNS
		_bell("seam_collapsed", "critical", "Seam collapsed",
			"The %s collapsed. Its mines stop for %d turns while it is cleared." % [name, COLLAPSE_OFFLINE_TURNS])
	changed.emit()


## NARRATIVE: offline turns run down.
func age() -> void:
	for k in offline.keys():
		offline[k] = int(offline[k]) - 1
		if int(offline[k]) <= 0:
			offline.erase(k)


## MatchState.deplete_deposit after a finite seam is charged: the card once a site is at a quarter of its start,
## and a seam's end.
func on_charged(tile_id: String, token: String, remaining: int, initial: int) -> void:
	var k := key(tile_id, token)
	if remaining <= 0:
		_seam_ended(tile_id, token)
		return
	if offered.has(k) or initial <= 0 or float(remaining) > float(initial) * LOW_SHARE:
		return
	offered[k] = true
	if MiningSites.site(tile_id, token).workings.is_empty():
		return
	if DecisionState.enabled:
		DecisionState.draw_with_target(CARD_ID, target_for(tile_id, token))
	changed.emit()


func _seam_ended(tile_id: String, token: String) -> void:
	var k := key(tile_id, token)
	if str(modes.get(k, "")) == ROBBING:
		var gone: Array = MiningSites.site(tile_id, token).workings
		for iid: String in gone:
			BuildingState.remove_building(iid)
		if not gone.is_empty():
			_bell("pillars_collapsed", "critical", "Workings collapsed",
				"The robbed pillars at %s gave way. %d working%s lost." % [_place(tile_id), gone.size(), "" if gone.size() == 1 else "s"])
	modes.erase(k)
	offline.erase(k)
	changed.emit()


## The card's target: the site, named as the panels name a seam ("Coal seam at Miney McMineface").
func target_for(tile_id: String, token: String) -> Dictionary:
	var good := Catalog.get_good_by_internal_name(token)
	return {"scope": "tile", "tile_id": tile_id, "token": token,
		"name": "%s seam at %s" % [str(good.get("display_name", token)), _place(tile_id)]}


# ── The card's choices ───────────────────────────────────────────────────────────────────────────

## Carry out a choice for the site. Cash is the card's own cash effect (shaft_cost, sale_value).
func apply(action: String, tile_id: String, token: String) -> void:
	var k := key(tile_id, token)
	var remaining := MatchState.deposit_remaining_for(tile_id, token)
	match action:
		"deeper_shaft":
			MatchState.extend_deposit(tile_id, token, roundi(float(maxi(0, remaining)) * SHAFT_ADD))
			offline[k] = OFFLINE_TURNS
			modes[k] = SHAFT
		"rob_pillars":
			MatchState.extend_deposit(tile_id, token, roundi(float(maxi(0, remaining)) * ROB_ADD))
			modes[k] = ROBBING
		"heavy_blasting":
			modes[k] = BLASTING
		"sell_reserves":
			for iid: String in MiningSites.site(tile_id, token).workings:
				BuildingState.sell_building(iid, 0)
			modes.erase(k)
	changed.emit()


## What a choice does to the site in a few lines, for the card: [{icon (a raised layer), text, tone ("" or "warn"
## for a risk)}]. detail() has the figures.
func brief(action: String, tile_id: String, token: String) -> Array:
	var f := _figures(tile_id, token)
	match action:
		"deeper_shaft":
			return [
				{"icon": "diag_icon_deposit", "text": "Seam lasts longer"},
				{"icon": "econ_icon_outputs", "text": "Mines stop for %s" % _turns(OFFLINE_TURNS)},
				{"icon": "econ_icon_labour", "text": "Labour and power cost more"},
			]
		"rob_pillars":
			return [
				{"icon": "diag_icon_deposit", "text": "Seam lasts a little longer"},
				{"icon": "econ_icon_labour", "text": "Labour costs more"},
				{"icon": "diag_icon_works", "text": "Risks accidents at the mines", "tone": "warn"},
				{"icon": f.emblem, "text": "Mines are lost when it runs out", "tone": "warn"},
			]
		"heavy_blasting":
			return [
				{"icon": "diag_icon_deposit", "text": "Seam runs out sooner"},
				{"icon": "econ_icon_outputs", "text": "Output sometimes doubles"},
				{"icon": "diag_icon_works", "text": "Risks roof falls and seam loss", "tone": "warn"},
			]
		"sell_reserves":
			return [{"icon": f.emblem, "text": "Sells your mines with the seam"}]
		"carry_on":
			if int(f.life) > 0:
				return [{"icon": "diag_icon_deposit", "text": "Seam runs out in %s" % _turns(int(f.life))}]
			return [{"icon": "diag_icon_deposit", "text": "Mine the seam to the end"}]
	return []


## A choice explained in full, for the plate that opens over it: {title, text, phases: [{title, rows: [{icon, label,
## from, to, span (how long it lasts), chance}], note}]}. `from` "" for a figure with no start.
func detail(action: String, tile_id: String, token: String) -> Dictionary:
	var f := _figures(tile_id, token)
	var good := str(f.good)
	var rem := int(f.remaining)
	var dug := int(f.dug)
	var life := int(f.life)
	var lasts := func(turns: int) -> String: return _turns(turns) if turns > 0 else ""
	match action:
		"deeper_shaft":
			var more := rem + roundi(float(rem) * SHAFT_ADD)
			return {"title": "Sink a deeper shaft",
				"text": "Your miners sink a new shaft to reach the %s below the old workings. The mines stop while it is dug, and the deeper %s takes more labour and power to raise." % [good, good],
				"phases": [
					{"title": "Now", "rows": [{"icon": "bar_icon_coin", "label": "Cost", "to": _money(shaft_cost(tile_id, token))}]},
					{"title": "For the next %s" % _turns(OFFLINE_TURNS), "rows": [
						{"icon": "econ_icon_outputs", "label": "Output a turn", "from": _units(dug), "to": "0"}]},
					{"title": "Then, until the seam runs out", "rows": [
						{"icon": "econ_icon_outputs", "label": "Output a turn", "from": "0", "to": _units(dug)},
						{"icon": "diag_icon_deposit", "label": "Left in the seam", "from": _units(rem), "to": _units(more)},
						{"icon": "diag_icon_transit", "label": "Runs out in", "from": lasts.call(life),
							"to": lasts.call(OFFLINE_TURNS + _life_at(more, float(dug)))},
						{"icon": "econ_icon_labour", "label": "Labour a turn", "from": _money(float(f.labour)), "to": _money(float(f.labour) * SHAFT_LABOUR)},
						{"icon": "bar_icon_power", "label": "Power", "from": "%d MW" % int(f.power), "to": "%d MW" % roundi(float(f.power) * SHAFT_POWER)},
					]},
				]}
		"rob_pillars":
			var more := rem + roundi(float(rem) * ROB_ADD)
			var accident := ROB_ACCIDENT * _safety_factor()
			return {"title": "Rob the pillars",
				"text": "Your miners cut away the pillars of %s left standing to hold the roof up. The seam gives a little more, but the workings grow unsafe and are lost when it runs out." % good,
				"phases": [
					{"title": "From now until the seam runs out", "rows": [
						{"icon": "diag_icon_deposit", "label": "Left in the seam", "from": _units(rem), "to": _units(more)},
						{"icon": "diag_icon_transit", "label": "Runs out in", "from": lasts.call(life), "to": lasts.call(_life_at(more, float(dug)))},
						{"icon": "econ_icon_labour", "label": "Labour a turn", "from": _money(float(f.labour)), "to": _money(float(f.labour) * ROB_LABOUR)},
						{"icon": "diag_icon_works", "label": "Accident at each mine, a turn", "chance": "%d%%" % roundi(accident * 100.0)},
					], "note": "An accident stops a mine for %s and costs %s of its wages in compensation." % [
						_turns(LabourUnrest.ACCIDENT_DOWN_TURNS), _turns(LabourUnrest.ACCIDENT_COMPENSATION_TURNS)]},
					{"title": "When the seam runs out", "rows": [
						{"icon": f.emblem, "label": "Your mines here", "from": str(int(f.mines)), "to": "0"}],
						"note": "They collapse with the seam. Nothing is paid for them."},
				]}
		"heavy_blasting":
			var avg := float(dug) * (1.0 + BLAST_DOUBLE) / (1.0 + BLAST_ROOF * float(OFFLINE_TURNS))
			return {"title": "Heavy blasting",
				"text": "Your miners use heavier charges for the rest of the seam. Each turn a blast may bring down twice the %s, bring the roof down on the mines, or bring down the rest of the seam. Most turns nothing changes." % good,
				"phases": [
					{"title": "Each turn, one of these at most", "rows": [
						{"icon": "econ_icon_outputs", "label": "Double dig", "from": _units(dug), "to": _units(dug * 2), "chance": "%d%%" % roundi(BLAST_DOUBLE * 100.0)},
						{"icon": "econ_icon_outputs", "label": "Roof fall", "from": _units(dug), "to": "0", "span": _turns(OFFLINE_TURNS), "chance": "%d%%" % roundi(BLAST_ROOF * 100.0)},
						{"icon": "diag_icon_deposit", "label": "Seam lost", "from": _units(rem), "to": "0", "chance": "%d%%" % roundi(BLAST_LOST * 100.0)},
					], "note": "A double dig takes twice as much from the seam."},
					{"title": "On average", "rows": [
						{"icon": "econ_icon_outputs", "label": "Output a turn", "from": _units(dug), "to": _units(roundi(avg))},
						{"icon": "diag_icon_transit", "label": "Runs out in", "from": lasts.call(life), "to": lasts.call(_life_at(rem, avg))},
					]},
				]}
		"sell_reserves":
			var parts := sale_parts(tile_id, token)
			return {"title": "Sell with reserves",
				"text": "Another company buys your mines here and the %s still in the seam, at half the market price. You are paid now and the mines leave your company." % good,
				"phases": [
					{"title": "Now", "rows": [
						{"icon": f.emblem, "label": "Your %d %s" % [int(f.mines), "mine" if int(f.mines) == 1 else "mines"], "to": _money(float(parts.mines))},
						{"icon": "diag_icon_deposit", "label": "%s left, at half price" % _units(rem), "to": _money(float(parts.reserves))},
						{"icon": "bar_icon_coin", "label": "Paid to you", "to": _money(float(parts.mines) + float(parts.reserves))},
					]},
				]}
		"carry_on":
			var rows: Array = [
				{"icon": "econ_icon_outputs", "label": "Output a turn", "to": _units(dug)},
				{"icon": "diag_icon_deposit", "label": "Left in the seam", "from": _units(rem), "to": "0"},
			]
			if life > 0:
				rows.append({"icon": "diag_icon_transit", "label": "Runs out in", "to": _turns(life)})
			return {"title": "Carry on",
				"text": "Your miners keep digging as they are until the seam is empty.",
				"phases": [
					{"title": "Until the seam runs out", "rows": rows},
					{"title": "Then", "rows": [], "note": "The mines stand idle with nothing to dig."},
				]}
	return {}


## What the card's figures start from: the site's mines, what they dig a turn, what is left and how long it lasts
## at that, their labour and power a turn, and the good's name.
func _figures(tile_id: String, token: String) -> Dictionary:
	var site := MiningSites.site(tile_id, token)
	var labour := 0.0
	var power := 0
	for iid: String in site.workings:
		var b := BuildingState.get_building(iid)
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		labour += Production._calculate_labour_cost(b, recipe)
		power += Production._effective_energy_req(b, recipe)
	var workings: Array = site.workings
	var remaining := maxi(0, MatchState.deposit_remaining_for(tile_id, token))
	return {
		"mines": workings.size(),
		"emblem": "bld_emblem_%s" % str(BuildingState.get_building(str(workings[0])).get("building_id", "b_001")) if not workings.is_empty() else "bld_emblem_b_001",
		"dug": roundi(float(site.units)),
		"remaining": remaining,
		"life": _life_at(remaining, float(site.units)),
		"labour": labour,
		"power": power,
		"good": str(Catalog.get_good_by_internal_name(token).get("display_name", token)).to_lower(),
	}


## The turns `remaining` lasts at `a_turn` dug a turn, 0 when nothing is dug.
static func _life_at(remaining: int, a_turn: float) -> int:
	return ceili(float(remaining) / a_turn) if a_turn > 0.0 else 0


static func _turns(n: int) -> String:
	return "%d %s" % [n, "turn" if n == 1 else "turns"]


static func _units(n: int) -> String:
	return MiningSites.thousands(n)


## Money as the card prints it: pence below £1,000, whole pounds with commas above.
static func _money(v: float) -> String:
	return "£%.2f" % v if absf(v) < 1000.0 else "£%s" % MiningSites.thousands(roundi(v))


## A choice in a few words, for the bell and the toast once it is made.
static func summary(action: String) -> String:
	match action:
		"deeper_shaft":
			return "A deeper shaft is sunk"
		"rob_pillars":
			return "The pillars are robbed"
		"heavy_blasting":
			return "Heavy blasting from now on"
		"sell_reserves":
			return "The workings are sold with the seam"
	return "Mined to the end"


## Sink a deeper shaft: two turns of the site's wages plus a level 1 kit's materials at market.
func shaft_cost(tile_id: String, token: String) -> float:
	var wages := 0.0
	for iid: String in MiningSites.site(tile_id, token).workings:
		var b := BuildingState.get_building(iid)
		wages += Production._base_labour_cost(b) * Production.labour_cost_factor(b)
	var kit := 0.0
	var parts: Dictionary = BuildingLevels.kit_materials()
	for name in parts:
		var good := Catalog.get_good_by_internal_name(str(name))
		kit += float(parts[name]) * MarketState.get_buy_price(str(good.get("id", "")))
	return wages * SHAFT_WAGE_TURNS + kit


## Sell with reserves: what the workings would sell for, plus what remains at half the market price.
func sale_value(tile_id: String, token: String) -> float:
	var parts := sale_parts(tile_id, token)
	return float(parts.mines) + float(parts.reserves)


## The sale in its two parts: {mines (their sale price), reserves (what remains at SALE_SHARE of market)}.
func sale_parts(tile_id: String, token: String) -> Dictionary:
	var mines := 0.0
	for iid: String in MiningSites.site(tile_id, token).workings:
		mines += float(BuildingPrice.sale_price(BuildingState.get_building(iid)))
	var good := Catalog.get_good_by_internal_name(token)
	return {"mines": mines,
		"reserves": float(maxi(0, MatchState.deposit_remaining_for(tile_id, token))) * MarketState.get_price(str(good.get("id", ""))) * SALE_SHARE}


# ── What the rest of the seam costs ──────────────────────────────────────────────────────────────

func is_offline(tile_id: String, token: String) -> bool:
	return offline.has(key(tile_id, token))


func offline_turns_left(tile_id: String, token: String) -> int:
	return int(offline.get(key(tile_id, token), 0))


func mode_of(tile_id: String, token: String) -> String:
	return str(modes.get(key(tile_id, token), ""))


## A working's labour under its site's way of working: ×1.4 after a deeper shaft, ×1.5 while robbing.
func labour_mult(building: Dictionary) -> float:
	match _mode_for(building):
		SHAFT:
			return SHAFT_LABOUR
		ROBBING:
			return ROB_LABOUR
	return 1.0


## A working's power after a deeper shaft: ×1.5.
func power_mult(building: Dictionary) -> float:
	return SHAFT_POWER if _mode_for(building) == SHAFT else 1.0


## A blasting working's dig this turn: ×2 on a double dig.
func dig_mult(building: Dictionary) -> float:
	if double_dig.is_empty():
		return 1.0
	var token := MiningSites.building_token(building)
	return 2.0 if token != "" and double_dig.has(key(str(building.get("tile_id", "")), token)) else 1.0


func _mode_for(building: Dictionary) -> String:
	if modes.is_empty() or not BuildingState.is_player_owned(building):
		return ""
	var token := MiningSites.building_token(building)
	return "" if token == "" else str(modes.get(key(str(building.get("tile_id", "")), token), ""))


## High safety halves the robbing accident chance, Minimal doubles it.
static func _safety_factor() -> float:
	if LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY):
		return 0.5
	if LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY):
		return 2.0
	return 1.0


static func _place(tile_id: String) -> String:
	var named := Catalog.tile_name(tile_id)
	return named if named != "" else Catalog.tile_label(tile_id)


func _bell(kind: String, severity: String, title: String, body: String) -> void:
	EventScheduler.emit_event({"kind": kind, "severity": severity, "title": title, "body": body,
		"source": "mining", "persistent": false, "auto_dismiss_turns": 3})
