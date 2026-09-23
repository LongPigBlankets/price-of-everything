extends Node
## Headless test runner for price-of-everything.
##
## Discovers every tests/unit/test_*.gd file, instantiates it (the file extends
## tests/test_base.gd), and runs each `func _test_*()` it defines, in source order.
## Runs as a SCENE (not --script) so the project autoloads are available.
##
## Fast path (exit code 0 = all pass, 1 = a failure):
##     <godot> --headless --path . res://tests/test_runner.tscn --quit-after 100000
## Or via tools/run_tests.py, which also fails the run on any SCRIPT ERROR line.
##
## Filtering (user args go after `--` on the command line):
##     -- --tags production            run tests tagged production
##     -- --tags production,market     any of these tags
##     -- --tags production+stockpile  all of these tags
##     -- --test <substring>           only tests whose name contains this
##     -- --list                       print files, tests and tags; run nothing
##
## Tag rules (see test_base.gd): a test carries its file's FEATURE unless the file's
## TAGS map lists it; an EMPTY tag list is a wildcard and matches every filter.

const UNIT_DIR := "res://tests/unit/"

## Files run in this order (smoke first, sim core, then views); anything not listed
## runs afterwards alphabetically.
const RUN_ORDER := [
	"test_smoke.gd",
	"test_map.gd",
	"test_production.gd",
	"test_stockpile.gd",
	"test_market.gd",
	"test_power.gd",
	"test_transport.gd",
	"test_construction.gd",
	"test_research.gd",
	"test_finance.gd",
	"test_advisors.gd",
	"test_decisions.gd",
	"test_events.gd",
	"test_special_orders.gd",
	"test_victory.gd",
	"test_save_load.gd",
	"test_tutorial.gd",
	"test_telemetry.gd",
	"test_goods_views.gd",
	"test_ui.gd",
]

var _passed := 0
var _failed := 0
var _failed_names: Array[String] = []
var _ran := 0
var _skipped := 0

var _filter_any: Array[String] = []
var _filter_all: Array[String] = []
var _name_filter := ""
var _list_only := false


func _ready() -> void:
	_parse_args(OS.get_cmdline_user_args())
	print("\n==== price-of-everything tests ====")
	if not _filter_any.is_empty():
		print("tags (any of): ", ", ".join(_filter_any))
	if not _filter_all.is_empty():
		print("tags (all of): ", ", ".join(_filter_all))
	if _name_filter != "":
		print("test name contains: ", _name_filter)
	var files := _unit_files()
	if files.is_empty():
		printerr("No test files found under ", UNIT_DIR)
		get_tree().quit(1)
		return
	# Leave the tree's setup frame before the first test: a test that parents a fixture to
	# the root during this node's own _ready gets "Parent node is busy setting up children".
	await get_tree().process_frame
	for file_name in files:
		await _run_file(file_name)
	if _list_only:
		get_tree().quit(0)
		return
	if not _failed_names.is_empty():
		print("FAILED TESTS:")
		for failed_name in _failed_names:
			print("  - ", failed_name)
	print("(%d tests run, %d filtered out)" % [_ran, _skipped])
	print("==== %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _parse_args(args: PackedStringArray) -> void:
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--tags":
				if i + 1 < args.size():
					var spec := args[i + 1]
					if "+" in spec:
						for t in spec.split("+", false):
							_filter_all.append(t.strip_edges())
					else:
						for t in spec.split(",", false):
							_filter_any.append(t.strip_edges())
					i += 1
			"--test":
				if i + 1 < args.size():
					_name_filter = args[i + 1]
					i += 1
			"--list":
				_list_only = true
		i += 1


func _unit_files() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			found.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	found.sort()
	var ordered: Array[String] = []
	for name in RUN_ORDER:
		if found.has(name):
			ordered.append(name)
	for name in found:
		if not ordered.has(name):
			ordered.append(name)
	return ordered


func _run_file(file_name: String) -> void:
	var script: GDScript = load(UNIT_DIR + file_name)
	if script == null:
		printerr("  FAIL  could not load ", file_name)
		_failed += 1
		_failed_names.append(file_name + " (load)")
		return
	var consts := script.get_script_constant_map()
	var feature := str(consts.get("FEATURE", ""))
	var tag_map: Dictionary = consts.get("TAGS", {})
	var tests: Array[String] = []
	for m in script.get_script_method_list():
		var n := str(m.name)
		if n.begins_with("_test_") and not tests.has(n):
			tests.append(n)
	if _list_only:
		print("\n-- %s  (FEATURE=%s, %d tests)" % [file_name, feature if feature != "" else "<wildcard>", tests.size()])
		for n in tests:
			var tg := _tags_for(n, feature, tag_map)
			print("   %-60s %s" % [n, ", ".join(tg) if not tg.is_empty() else "*"])
		return
	var selected: Array[String] = []
	for n in tests:
		if _selected(n, _tags_for(n, feature, tag_map)):
			selected.append(n)
		else:
			_skipped += 1
	if selected.is_empty():
		return
	print("\n-- %s (%d of %d tests)" % [file_name, selected.size(), tests.size()])
	var inst: Node = script.new()
	add_child(inst)
	for n in selected:
		var p0: int = inst._passed
		var f0: int = inst._failed
		var t0 := Time.get_ticks_msec()
		await inst.call(n)
		# Isolation between tests: let queue_free'd fixtures actually die (a stale node in
		# the "hex_map" group is otherwise found first by the next test), and let a turn
		# resolution a test kicked off with commit_turn() run to completion rather than
		# straddling the tests that follow it.
		await get_tree().process_frame
		while TurnManager.is_resolving:
			await get_tree().process_frame
		var dt := Time.get_ticks_msec() - t0
		var dp: int = inst._passed - p0
		var df: int = inst._failed - f0
		_ran += 1
		if df > 0:
			print("  ## %s: %d checks, %d FAILED (%d ms)" % [n, dp + df, df, dt])
		elif dt >= 250:
			print("  ## %s: %d checks (%d ms)" % [n, dp, dt])
	_passed += inst._passed
	_failed += inst._failed
	for fn in inst._failed_names:
		_failed_names.append(fn)


static func _tags_for(test_name: String, feature: String, tag_map: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if tag_map.has(test_name):
		for t in tag_map[test_name]:
			out.append(str(t))
		return out
	if feature != "":
		out.append(feature)
	return out


func _selected(test_name: String, tags: Array[String]) -> bool:
	if _name_filter != "" and not test_name.contains(_name_filter):
		return false
	if _filter_any.is_empty() and _filter_all.is_empty():
		return true
	if tags.is_empty():
		return true  # wildcard: relevant to every feature
	for t in _filter_all:
		if not tags.has(t):
			return false
	if not _filter_any.is_empty():
		for t in _filter_any:
			if tags.has(t):
				return true
		return false
	return true
