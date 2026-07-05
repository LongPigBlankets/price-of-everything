extends Node
## SaveLoad: one snapshot format and one apply path for saves, loads and (later)
## scenario starts. Each system owns its own export_state()/import_state(); this
## autoload orchestrates them and handles JSON I/O plus slot management.
## See docs/save_load_spec.md for the full design and progress tracker.
##
## Phase 1 (current): in-place snapshot/apply + debug-terminal slots. Phase 2 adds
## scene-reload sequencing (main-menu Load Game) and on-map visual rebuild.

const SAVE_DIR := "user://saves"
# Version history (migrations in _migrate): 1 = initial format; 2 = adds `ruleset`
# (match.ruleset + meta.ruleset) so future rule variants can key off saves;
# 3 = adds special order state; 4 = advisor seats/acquisition; 5 = structured
# infrastructure snapshot with per-tile levels.
const SAVE_VERSION := 5
const MAIN_SCENE := "res://scenes/main.tscn"
const DEFAULT_START := "res://data/starts/default.json"
const BuildingLevels := preload("res://scripts/building_levels.gd")   # start-building levels
# Start-config instance ids count from here so they can never collide with the
# ids the fresh scene hands to NPC buildings (ports/ruins) before the start applies.
const START_COUNTER_BASE := 1000

# Autosave: after every Nth turn resolves, rotating through a few slots so one
# corrupted/ill-timed autosave never costs the whole session.
const AUTOSAVE_EVERY_TURNS := 10
const AUTOSAVE_SLOTS := 3

## Fired after a snapshot has been applied and the refresh signals re-emitted.
signal match_loaded

var autosave_enabled := true
var _autosave_index := 0

# A parsed save waiting for the main scene to (re)build. world_map calls
# apply_pending() at the very end of its _ready, once the terrain exists.
var _pending_snapshot: Dictionary = {}

func _ready() -> void:
	# Registered last in [autoload], so TurnManager exists. resolution_completed
	# fires with the turn counter already advanced and DECIDE restored — the one
	# moment per turn the save guard is guaranteed to pass.
	TurnManager.turn_resolution_completed.connect(_on_turn_resolution_completed)

func _on_turn_resolution_completed() -> void:
	if not autosave_enabled or TurnManager.game_ended:
		return
	var finished_turn: int = TurnManager.current_turn - 1
	if finished_turn < AUTOSAVE_EVERY_TURNS or finished_turn % AUTOSAVE_EVERY_TURNS != 0:
		return
	_autosave_index = (_autosave_index % AUTOSAVE_SLOTS) + 1
	if save_slot("autosave_%d" % _autosave_index) == "":
		MatchState.request_toast("Autosaved.", "info")

# --- Snapshot in memory ---

func export_snapshot() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"meta": {
			"turn": TurnManager.current_turn,
			"money": MatchState.money,
			"ruleset": str(MatchState.ruleset.get("name", "standard")),
			"timestamp": Time.get_datetime_string_from_system(),
		},
		"turn": TurnManager.export_state(),
		"match": MatchState.export_state(),
		"stockpile": Stockpile.export_state(),
		"loans": LoanState.export_state(),
		"construction": Construction.export_state(),
		"market": MarketState.export_state(),
		"special_orders": SpecialOrderState.export_state(),
		"production": Production.export_state(),
		"events": EventScheduler.export_state(),
		"modifiers": Modifiers.export_state(),
		"victory": VictoryState.export_state(),
		"infrastructure": _collect_infrastructure(),
		"roads": {
			"network": RoadNetwork.instance().export_state(),
			"works": RoadWorks.export_state(),
		},
	}

func import_snapshot(snap: Dictionary) -> void:
	# Clean slate first: reset() emits state_reset so listeners that hold derived
	# state (e.g. Construction clearing its projects) flush before new data lands.
	MatchState.reset()
	Stockpile.clear_all()
	_restore_infrastructure_for_snapshot(snap)
	TurnManager.import_state(snap.get("turn", {}))
	MatchState.import_state(snap.get("match", {}))
	Stockpile.import_state(snap.get("stockpile", {}))
	LoanState.import_state(snap.get("loans", {}))
	Construction.import_state(snap.get("construction", {}))
	MarketState.import_state(snap.get("market", {}))
	SpecialOrderState.import_state(snap.get("special_orders", {}))
	Production.import_state(snap.get("production", {}))
	EventScheduler.import_state(snap.get("events", {}))
	Modifiers.import_state(snap.get("modifiers", {}))
	# Advisor-seat modifiers are derived, not saved: re-register them AFTER
	# Modifiers.import_state (which replaces the registry wholesale and would
	# otherwise wipe an earlier reconcile). See advisor-system-spec.md §12.1.
	MatchState.reconcile_advisor_modifiers()
	# Permanent advisor-mission rewards (perm slices + capstones) are also derived from
	# advisor_missions_completed, so re-apply them after the Modifiers registry reload.
	MatchState.reapply_mission_modifiers()
	# Missing "victory" key (old saves) -> import_state({}) leaves a fresh zero state.
	VictoryState.import_state(snap.get("victory", {}))
	# roads-v2: BUILT geometry restores verbatim; planning orders resume
	# deterministically; mid-reveal orders restart their reveal (cosmetic).
	# Old saves carry no "roads" key — the network stays empty here and
	# world_map bootstraps the baked anchor spine instead.
	var roads: Dictionary = snap.get("roads", {})
	RoadNetwork.reset()
	RoadWorks.reset()
	if not (roads.get("network", {}) as Dictionary).is_empty():
		RoadNetwork.instance().import_state(roads.get("network", {}))
	RoadWorks.import_state(roads.get("works", {}))
	_emit_refresh()
	match_loaded.emit()

# Imports run silently; the UI is told once, here, at the end. Per-building
# building_added is deliberately NOT re-emitted (it would toast "X built" for every
# building) — on-map visual rebuild is the Phase 2 load-sequencing work.
func _emit_refresh() -> void:
	MatchState.money_changed.emit(MatchState.money)
	MatchState.surveyed_tiles_changed.emit()
	MatchState.surveying_in_progress_changed.emit()
	MatchState.transport_shipments_changed.emit()
	MatchState.labour_multiplier_changed.emit(MatchState.labour_multiplier)
	MatchState.sell_mode_changed.emit(MatchState.sell_mode)
	MatchState.route_objective_changed.emit(MatchState.route_objective)
	Stockpile.stockpile_changed.emit()
	MarketState.prices_updated.emit()
	LoanState.loans_updated.emit()

# --- Slot I/O ---
# These return "" on success or a human-readable error (the debug terminal and,
# later, the save UI print it verbatim).

func save_slot(slot: String) -> String:
	if TurnManager.is_resolving or TurnManager.current_phase != TurnManager.Phase.DECIDE:
		return "can only save during the Decide phase"
	var path := _slot_path(slot)
	if path == "":
		return "invalid save name '%s'" % slot
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Write to a temp file and rename over the slot so a crash/power loss
	# mid-write can never destroy both the old and the new copy of the save.
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(export_snapshot(), "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		DirAccess.remove_absolute(tmp_path)
		return "cannot finalise %s (%s)" % [path, error_string(err)]
	return ""

func load_slot(slot: String, restart_scene: bool = true) -> String:
	# Default path: park the snapshot, reload the main scene, and apply once the
	# map exists (world_map calls apply_pending() at the end of its _ready) — this
	# rebuilds terrain-coupled state and visuals cleanly from anywhere, including
	# the main menu. restart_scene=false applies in place (tests; no visual rebuild).
	if TurnManager.is_resolving:
		# TurnManager is an autoload: its suspended resolution coroutine would
		# survive the scene change and resume over the freshly imported snapshot,
		# advancing a phantom turn. The save/load UI disables itself during
		# resolution; this is the backstop for every other entry point.
		return "cannot load while the turn is resolving"
	var path := _slot_path(slot)
	if path == "" or not FileAccess.file_exists(path):
		return "no save called '%s'" % slot
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "cannot read %s" % path
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return "corrupt save '%s'" % slot
	var snap: Dictionary = normalize_jsonish(parsed)
	if int(snap.get("save_version", 0)) > SAVE_VERSION:
		return "save '%s' is from a newer game version" % slot
	snap = _migrate(snap)
	if not restart_scene:
		import_snapshot(snap)
		return ""
	_pending_snapshot = snap
	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		_pending_snapshot = {}
		return "cannot open the map scene (%s)" % error_string(err)
	return ""

func has_pending() -> bool:
	return not _pending_snapshot.is_empty()

func pending_is_start() -> bool:
	return bool(_pending_snapshot.get("start", false))

## Called by world_map at the very end of _ready, after the terrain is built and
## the default match seeding (NPC ports, deposits) ran. Returns true when a
## pending save was applied — the caller then rebuilds its visuals.
func apply_pending() -> bool:
	if _pending_snapshot.is_empty():
		return false
	var snap: Dictionary = _pending_snapshot
	_pending_snapshot = {}
	if bool(snap.get("start", false)):
		_merge_npc_buildings(snap)
	import_snapshot(snap)
	return true

# A start config lists only the PLAYER's holdings; the NPC buildings the fresh
# scene just seeded (ports, ruins) must survive the import's full overwrite of
# MatchState.buildings, so they're folded into the snapshot first.
func _merge_npc_buildings(snap: Dictionary) -> void:
	var match_d: Dictionary = snap.get("match", {})
	var bld: Dictionary = match_d.get("buildings", {})
	for instance_id in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[instance_id]
		if not MatchState.is_player_owned(inst):
			bld[instance_id] = inst.duplicate(true)
	match_d["buildings"] = bld
	snap["match"] = match_d

# --- Start configurations (Phase 3; docs/save_load_spec.md) ---
# A "start" is a small, hand-authorable JSON expanded into a full snapshot, so New
# Game, Load Game and scenarios all flow through the same apply path.

## Build the pending start snapshot WITHOUT changing scene, so the caller can drive
## a non-blocking (threaded) transition to MAIN_SCENE itself and keep a loading
## screen animating during the heavy scene load. See LoadingScreen.begin_load.
func prepare_new_game(start_path: String = DEFAULT_START) -> void:
	var cfg := _read_json_file(start_path)
	if cfg.is_empty():
		# No/corrupt start file: a plain fresh match (today's behaviour).
		push_warning("[SaveLoad] start config missing or corrupt: %s — starting fresh" % start_path)
		_pending_snapshot = {}
	else:
		_pending_snapshot = expand_start_config(cfg)


func start_new_game(start_path: String = DEFAULT_START) -> String:
	prepare_new_game(start_path)
	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		_pending_snapshot = {}
		return "cannot open the map scene (%s)" % error_string(err)
	return ""

## Expand the authoring shape (see data/starts/*.json) into a full snapshot.
## Anything omitted falls back to new-game defaults at import. Loans become
## outstanding debt WITHOUT disbursing principal — `money` is what you start with.
func expand_start_config(cfg: Dictionary) -> Dictionary:
	# Surveyed set: the NPC port tiles (as seed_surveyed_ports does), the tiles
	# under starting buildings (you can see what you own), plus any listed extras.
	var surveyed: Dictionary = {}
	for port in Catalog.all_ports():
		var port_tile := str(port.get("tile_id", ""))
		if port_tile != "":
			surveyed[port_tile] = true

	var buildings: Dictionary = {}
	var counter := START_COUNTER_BASE
	for entry in cfg.get("buildings", []):
		var building_id := str(entry.get("building_id", ""))
		var tile_id := str(entry.get("tile_id", ""))
		if building_id == "" or tile_id == "":
			continue
		counter += 1
		var instance_id := "inst_%s_%06x" % [building_id, counter]
		buildings[instance_id] = {
			"instance_id": instance_id,
			"building_id": building_id,
			"recipe_id": str(entry.get("recipe_id", "")),
			"tile_id": tile_id,
			"owner": str(entry.get("owner", MatchState.LOCAL_PLAYER)),
			# Optional starting upgrade level (1..3); production reads building.level.
			"level": clampi(int(entry.get("level", 1)), 1, BuildingLevels.MAX_LEVEL),
		}
		surveyed[tile_id] = true
	for tile in cfg.get("surveyed_tiles", []):
		surveyed[str(tile)] = true

	# Debt: amortised exactly like LoanState.take_loan, but no cash lands.
	var loans: Array = []
	for entry in cfg.get("loans", []):
		var principal := float(entry.get("principal", 0.0))
		if principal <= 0.0:
			continue
		var rate := float(entry.get("interest_rate", EconomyConfig.LOAN_INTEREST_RATE))
		var term: int = maxi(1, int(entry.get("term_turns", EconomyConfig.LOAN_TERM_TURNS)))
		var total := principal * (1.0 + rate)
		loans.append({
			"id": loans.size() + 1,
			"principal_initial": principal,
			"principal_remaining": total,
			"payment_per_turn": total / float(term),
			"turns_remaining": term,
			"interest_paid": 0.0,
		})

	var unlocked: Dictionary = {}
	for title in cfg.get("unlocks", []):
		unlocked[str(title)] = true

	var recurring: Dictionary = cfg.get("recurring", {})
	var ruleset := _normalize_ruleset(cfg.get("ruleset", MatchState.DEFAULT_RULESET))
	return {
		"save_version": SAVE_VERSION,
		"start": true,
		"meta": {
			"turn": 1,
			"money": float(cfg.get("money", EconomyConfig.STARTING_MONEY)),
			"ruleset": str(ruleset.get("name", "standard")),
			"scenario": str(cfg.get("name", "")),
		},
		"turn": {"current_turn": 1, "game_ended": false},
		"match": {
			"money": float(cfg.get("money", EconomyConfig.STARTING_MONEY)),
			"ruleset": ruleset,
			"next_instance_counter": counter,
			"buildings": buildings,
			"tile_land_owned": (cfg.get("land", {}) as Dictionary).duplicate(true),
			"surveyed_tiles": surveyed,
			"unlocked_titles": unlocked,
			"recurring_moves": _stamped_orders(recurring.get("moves", [])),
			"recurring_sells": _stamped_orders(recurring.get("sells", [])),
			"recurring_bulk_sells": _stamped_orders(recurring.get("bulk_sells", [])),
			"recurring_buys": _stamped_orders(recurring.get("buys", [])),
		},
		"stockpile": {"by_tile": (cfg.get("stockpile", {}) as Dictionary).duplicate(true)},
		"loans": {"loans": loans, "next_loan_id": loans.size() + 1},
		"infrastructure": (cfg.get("infrastructure", {}) as Dictionary).duplicate(true),
	}

# Authoring convenience: `"ruleset": "hardcore"` and `"ruleset": {"name": "hardcore",
# ...per-rule keys}` are both accepted; the dict form is what gets stored.
func _normalize_ruleset(value: Variant) -> Dictionary:
	if value is Dictionary:
		var d: Dictionary = (value as Dictionary).duplicate(true)
		if str(d.get("name", "")) == "":
			d["name"] = "standard"
		return d
	if value is String and str(value) != "":
		return {"name": str(value)}
	return MatchState.DEFAULT_RULESET.duplicate(true)

func _stamped_orders(entries: Variant) -> Array:
	# Recurring orders run from turn 1; the ledger tabs show turn_started.
	var out: Array = []
	if not (entries is Array):
		return out
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = (entry as Dictionary).duplicate(true)
		if not d.has("turn_started"):
			d["turn_started"] = 1
		out.append(d)
	return out

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	return normalize_jsonish(parsed)

# --- Infrastructure (lives on the scene's hex map + the Catalog routing graph) ---

func _hex_map() -> Node:
	return get_tree().get_first_node_in_group("hex_map")

func _restore_infrastructure_for_snapshot(snap: Dictionary) -> void:
	var has_infrastructure := snap.has("infrastructure")
	if bool(snap.get("start", false)) or not has_infrastructure:
		Catalog.reset_runtime_infrastructure()
		_apply_infrastructure(_collect_infrastructure())
		if has_infrastructure:
			_apply_infrastructure(snap.get("infrastructure", {}))
		return
	Catalog.clear_tile_infrastructure()
	_clear_scene_infrastructure()
	_apply_infrastructure(snap.get("infrastructure", {}))

func _collect_infrastructure() -> Dictionary:
	# {tile_id: {present: ["roads", ...], levels: {"roads": 2}}} for every tile
	# with infrastructure (CSV-seeded or runtime-built). The tile-facing keys are
	# preserved as stored by HexMap/UI; Catalog normalises them when routes sync.
	var out: Dictionary = {}
	var hex_map := _hex_map()
	if hex_map == null:
		return out
	for coord in hex_map.tiles:
		var tile: Dictionary = hex_map.tiles[coord]
		var infra: Array = _string_array(tile.get("infrastructure_present", []))
		var levels: Dictionary = _level_dict(tile.get("infrastructure_levels", {}))
		for infra_key in levels.keys():
			if not infra.has(str(infra_key)):
				infra.append(str(infra_key))
		var tile_id := str(tile.get("id", ""))
		if tile_id != "" and (not infra.is_empty() or not levels.is_empty()):
			out[tile_id] = {"present": infra, "levels": levels}
	return out

func _apply_infrastructure(infra_by_tile: Dictionary) -> void:
	# Mirror of world_map._apply_built_infrastructure, applied in bulk: the tile
	# dict drives the mapmodes/panels, the Catalog drives routing.
	var hex_map := _hex_map()
	if hex_map == null:
		return
	var normalized := _normalize_infrastructure_snapshot(infra_by_tile)
	for tile_id in normalized:
		var coord: Vector2i = hex_map.id_to_coord(str(tile_id))
		if not hex_map.tiles.has(coord):
			continue
		var tile: Dictionary = hex_map.tiles[coord]
		var infra: Array = _string_array(tile.get("infrastructure_present", []))
		var levels: Dictionary = _level_dict(tile.get("infrastructure_levels", {}))
		var entry: Dictionary = normalized[tile_id]
		for infra_type in entry.get("present", []):
			if not infra.has(str(infra_type)):
				infra.append(str(infra_type))
			Catalog.add_tile_infrastructure(str(tile_id), str(infra_type))
		var entry_levels: Dictionary = entry.get("levels", {})
		for infra_type in entry_levels:
			var key := str(infra_type)
			if not infra.has(key):
				infra.append(key)
				Catalog.add_tile_infrastructure(str(tile_id), key)
			levels[key] = clampi(int(entry_levels[infra_type]), 1, BuildingLevels.MAX_LEVEL)
		tile["infrastructure_present"] = infra
		tile["infrastructure_levels"] = levels
		hex_map.tiles[coord] = tile

func _clear_scene_infrastructure() -> void:
	var hex_map := _hex_map()
	if hex_map == null:
		return
	for coord in hex_map.tiles:
		var tile: Dictionary = hex_map.tiles[coord]
		tile["infrastructure_present"] = []
		tile["infrastructure_levels"] = {}
		hex_map.tiles[coord] = tile

func _normalize_infrastructure_snapshot(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	var raw_dict: Dictionary = raw as Dictionary
	for tile_key in raw_dict:
		var tile_id := str(tile_key)
		var entry: Variant = raw_dict[tile_key]
		var present: Array = []
		var levels: Dictionary = {}
		if entry is Array:
			present = _string_array(entry)
		elif entry is Dictionary:
			var d: Dictionary = entry as Dictionary
			present = _string_array(d.get("present", d.get("infrastructure_present", [])))
			levels = _level_dict(d.get("levels", d.get("infrastructure_levels", {})))
		for infra_key in levels.keys():
			if not present.has(str(infra_key)):
				present.append(str(infra_key))
		if tile_id != "" and (not present.is_empty() or not levels.is_empty()):
			out[tile_id] = {"present": present, "levels": levels}
	return out

func _string_array(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for item in (value as Array):
		var key := str(item).strip_edges()
		if key != "" and not out.has(key):
			out.append(key)
	return out

func _level_dict(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	var dict: Dictionary = value as Dictionary
	for key in dict:
		var infra_key := str(key).strip_edges()
		if infra_key == "":
			continue
		out[infra_key] = clampi(int(dict[key]), 1, BuildingLevels.MAX_LEVEL)
	return out

func list_slots() -> Array:
	# [{slot, turn, money, timestamp}] sorted by name; meta read without full parse cost
	# is not worth the complexity at this scale, so we parse each file.
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var slot := file.trim_suffix(".json")
		var f := FileAccess.open("%s/%s" % [SAVE_DIR, file], FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			continue
		var meta: Dictionary = (parsed as Dictionary).get("meta", {})
		out.append({
			"slot": slot,
			"turn": int(meta.get("turn", 0)),
			"money": float(meta.get("money", 0.0)),
			"ruleset": str(meta.get("ruleset", "standard")),
			"timestamp": str(meta.get("timestamp", "")),
		})
	out.sort_custom(func(a, b): return str(a.slot) < str(b.slot))
	return out

func _slot_path(slot: String) -> String:
	var name := slot.strip_edges().validate_filename()
	if name == "":
		return ""
	return "%s/%s.json" % [SAVE_DIR, name]

# --- Version migrations ---
# Older saves step up one version at a time; each rung only knows the shape of the
# version directly below it. Add a `N: snap = _migrate_vN_to_vN1(snap)` arm per bump.

func _migrate(snap: Dictionary) -> Dictionary:
	var version := int(snap.get("save_version", 1))
	while version < SAVE_VERSION:
		match version:
			1:
				snap = _migrate_v1_to_v2(snap)
			2:
				snap = _migrate_v2_to_v3(snap)
			3:
				snap = _migrate_v3_to_v4(snap)
			4:
				snap = _migrate_v4_to_v5(snap)
			_:
				break
		version += 1
		snap["save_version"] = version
	return snap

func _migrate_v1_to_v2(snap: Dictionary) -> Dictionary:
	# v2 adds `ruleset`. v1 saves all played under the standard rules.
	var match_d: Dictionary = snap.get("match", {})
	if not match_d.has("ruleset"):
		match_d["ruleset"] = MatchState.DEFAULT_RULESET.duplicate(true)
	snap["match"] = match_d
	var meta: Dictionary = snap.get("meta", {})
	if not meta.has("ruleset"):
		meta["ruleset"] = str(match_d["ruleset"].get("name", "standard"))
	snap["meta"] = meta
	return snap

func _migrate_v2_to_v3(snap: Dictionary) -> Dictionary:
	# v3 adds special orders. Old saves simply start with no active orders.
	if not snap.has("special_orders"):
		snap["special_orders"] = {}
	return snap

func _migrate_v3_to_v4(snap: Dictionary) -> Dictionary:
	# v4 adds the advisor seat framework + acquisition (seats, slots, rng, milestones).
	# Old saves default to empty seats / 2 slots / a fresh rng. Legacy advisor ids
	# (natasha/dan/...) no longer exist in the roster, so clear the hired list
	# (pre-release saves are disposable) rather than let _sanitize silently drop them.
	var m: Dictionary = snap.get("match", {})
	m["permanent_advisor_ids"] = []
	if not m.has("advisor_seats"):
		m["advisor_seats"] = {}
	if not m.has("max_advisor_slots"):
		m["max_advisor_slots"] = 2
	if not m.has("advisor_rng_seed"):
		m["advisor_rng_seed"] = MatchState.DEFAULT_MATCH_RNG_SEED
	if not m.has("advisor_crossed_milestones"):
		m["advisor_crossed_milestones"] = []
	if not m.has("recruited_advisor_ids"):
		m["recruited_advisor_ids"] = []
	snap["match"] = m
	return snap

func _migrate_v4_to_v5(snap: Dictionary) -> Dictionary:
	if snap.has("infrastructure"):
		snap["infrastructure"] = _normalize_infrastructure_snapshot(snap.get("infrastructure", {}))
	return snap

# --- JSON helpers ---

## JSON.parse_string returns every number as a float. The game's state stores
## counts/turns/ids as ints (and int()-casts on read), so integral floats are
## folded back to ints recursively. Typed float vars (money, multipliers) accept
## ints on assignment, so this is safe across the board.
func normalize_jsonish(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			return int(f) if f == floorf(f) and absf(f) < 9.0e15 else f
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			for k in (value as Dictionary):
				d[k] = normalize_jsonish(value[k])
			return d
		TYPE_ARRAY:
			var a: Array = []
			for v in (value as Array):
				a.append(normalize_jsonish(v))
			return a
		_:
			return value
