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

## PROCESS, before production: each blasting site's roll and each robbing working's accident chance.
func tick(turn: int) -> void:
	double_dig.clear()
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
	var total := 0.0
	for iid: String in MiningSites.site(tile_id, token).workings:
		total += float(BuildingPrice.sale_price(BuildingState.get_building(iid)))
	var good := Catalog.get_good_by_internal_name(token)
	return total + float(maxi(0, MatchState.deposit_remaining_for(tile_id, token))) * MarketState.get_price(str(good.get("id", ""))) * SALE_SHARE


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
