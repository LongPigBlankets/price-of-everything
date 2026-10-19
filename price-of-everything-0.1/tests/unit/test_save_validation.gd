extends "res://tests/test_base.gd"
const FEATURE := "save_validation"
const Validator := preload("res://scripts/save_validation.gd")


func _test_save_validation_accepts_current_snapshot() -> void:
	var snapshot := SaveLoad.export_snapshot()
	var error: String = Validator.new().validate(snapshot, SaveLoad.SAVE_VERSION, false)
	_check(error == "", "save validation: current exported snapshot remains compatible: " + error)
	snapshot.stockpile["fill_history"] = {"tile_6_8": [10, 20]}
	snapshot.market["net_history"] = {"g_001": [2.0, -3.0]}
	snapshot.decisions["recent_draws"] = [{"turn": 1, "id": "test", "category": "finance"}]
	snapshot.match["ghost_holdings"] = {&"interned": {Vector2i(1, 2): &"value"}}
	_check(Validator.new().validate(snapshot, SaveLoad.SAVE_VERSION, false) == "", "save validation: numeric stock and market histories remain compatible")
	_check(Validator.new().validate({"infrastructure": {"tile_6_8": {"levels": {"roads": 1.5}}}}, SaveLoad.SAVE_VERSION, false) != "", "save validation: fractional infrastructure levels are rejected")
	_check(Validator.new().validate({"match": {"deposit_remaining": []}}, SaveLoad.SAVE_VERSION, false) != "", "save validation: deposit ledger must be an object before import")
	_check(Validator.new().validate({"match": {"ruleset": {"speed_turns": []}}}, SaveLoad.SAVE_VERSION, false) != "", "save validation: ruleset values checked before applying them")
	_check(Validator.new().validate({"modifiers": {"modifiers": {"bad": {"domain": "labour", "pct": []}}}}, SaveLoad.SAVE_VERSION, false) != "", "save validation: malformed modifier rejected before live refresh")


func _test_save_validation_rejects_before_state_changes() -> void:
	var before := SaveLoad.export_snapshot()
	for malformed in [{"match": []}, {"match": {"ruleset": []}}, {"match": {"buildings": {"bad": 7}}}, {"loans": {"loans": ["bad"]}}, {"stockpile": {"by_tile": {"tile_1_1": 7}}}, {"roads": {"network": {"nodes": {"bad": {}}}}}, {"match": {"money": INF}}, {"match": {"middleman_service": {"buildings": {"bad": {"inputs": []}}}}}]:
		var error := SaveLoad.import_snapshot(malformed)
		_check(error != "", "save validation: malformed input has a readable error")
		_check(SaveLoad.export_snapshot() == before, "save validation: invalid import leaves every subsystem unchanged")


func _test_save_validation_limits_and_versions() -> void:
	var validator := Validator.new()
	_check(validator.validate({"save_version": SaveLoad.SAVE_VERSION + 1}, SaveLoad.SAVE_VERSION, false).contains("newer"), "save validation: future versions are rejected")
	_check(validator.validate({"save_version": "17"}, SaveLoad.SAVE_VERSION, false) != "", "save validation: version must be numeric")
	_check(validator.validate({"turn": {"current_turn": -1}}, SaveLoad.SAVE_VERSION, false) != "", "save validation: turn counter cannot be negative")
	_check(validator.validate({"start": []}, SaveLoad.SAVE_VERSION, false) != "", "save validation: malformed start flag cannot reach the scene import")
	for block in ["match", "special_orders", "decisions"]:
		var bad := {block: {"advisor_rng_state" if block == "match" else "rng_state": []}}
		_check(validator.validate(bad, SaveLoad.SAVE_VERSION, false) != "", "save validation: RNG conversion receives a safe scalar (" + block + ")")
	var deep := {}
	var child := deep
	for i in range(Validator.MAX_DEPTH + 1):
		child["next"] = {}
		child = child.next
	_check(validator.validate(deep, SaveLoad.SAVE_VERSION, false).contains("nested"), "save validation: over-deep data is bounded before normalization")


func _test_save_validation_file_boundary_and_slot_listing() -> void:
	DirAccess.make_dir_recursive_absolute(AppPaths.saves_dir())
	var slot := "__test_invalid_snapshot_" + str(Time.get_ticks_usec())
	var path := AppPaths.saves_dir().path_join(slot + ".json")
	var before := SaveLoad.export_snapshot()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"save_version":17,"match":[],"turn":{},"meta":[]}')
	file.close()
	_check(SaveLoad.load_slot(slot, false) != "", "save validation: malformed on-disk save is rejected")
	_check(SaveLoad.export_snapshot() == before, "save validation: rejected file does not reset the current match")
	var listed := false
	for entry in SaveLoad.list_slots():
		if entry.slot == slot: listed = true
	_check(not listed, "save validation: malformed slot metadata does not crash the load menu")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.seek(Validator.MAX_FILE_BYTES)
	file.store_8(0)
	file.close()
	_check(SaveLoad.load_slot(slot, false).contains("too large"), "save validation: oversized file rejected before reading JSON")
	DirAccess.remove_absolute(path)


func _test_save_validation_demo_policy_and_legacy_defaults() -> void:
	var validator := Validator.new()
	for start in ["metal_magnate", "glass_merchant", "tutorial", "default"]:
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/" + start + ".json"))
		var expanded := SaveLoad.expand_start_config(config, {"ruleset": {"speed_turns": 100, "difficulty": "normal", "victory_set": "demo_itch"}})
		var error := validator.validate(expanded, SaveLoad.SAVE_VERSION, true)
		_check(error == "", "save validation: shipped demo start remains compatible (" + start + "): " + error)
	var snapshot := {"save_version": SaveLoad.SAVE_VERSION, "turn": {"current_turn": 10}, "match": {"scenario_name": "metal_magnate", "buildings": {}, "ruleset": {"name": "standard"}}}
	_check(validator.validate(snapshot, SaveLoad.SAVE_VERSION, true) == "", "save validation: older demo save can omit additive rules")
	var normalized := Validator.normalize_demo(snapshot)
	_check(normalized.match.ruleset.speed_turns == 100 and normalized.match.ruleset.difficulty == "normal", "save validation: legacy demo rules get Normal and the 100-turn cap")
	_check(not snapshot.match.ruleset.has("speed_turns"), "save validation: demo normalization does not mutate caller data")
	for change in [{"scenario_name": "pepper_valley_motors"}, {"ruleset": {"speed_turns": 400}}, {"ruleset": {"difficulty": "hard"}}, {"max_advisor_slots": 1000}, {"advisor_seats": {"hr": "andrew"}}, {"recruited_advisor_ids": ["vera", "anita"]}, {"buildings": {"bad": {"building_id": "b_022", "tile_id": "tile_6_8", "level": 1}}}]:
		var bad := snapshot.duplicate(true)
		bad.match.merge(change, true)
		_check(validator.validate(bad, SaveLoad.SAVE_VERSION, true) != "", "save validation: demo-incompatible content or rules rejected")
	var forged := snapshot.duplicate(true)
	forged.match.all_seats_unlocked = true
	forged.match.max_advisor_slots = 5
	var safe := Validator.normalize_demo(forged)
	_check(not safe.match.all_seats_unlocked and safe.match.max_advisor_slots <= 3, "save validation: loaded flags cannot open full-only advisor capacity")
