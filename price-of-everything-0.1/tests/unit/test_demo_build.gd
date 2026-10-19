extends "res://tests/test_base.gd"
## The demo build: the Demo export presets track the regular ones, shipped code never
## preloads a file the demo leaves out, and the demo runtime keeps only its allow-lists.

const FEATURE := "demo_build"
const DemoBuild := preload("res://scripts/demo_build.gd")
const DemoDataFilter := preload("res://addons/demo_export/demo_data_filter.gd")
const PRESETS := "res://export_presets.cfg"
const EXCLUDES := "res://tools/demo_build/excludes.txt"
const BASE_PRESETS := ["macOS", "Windows Desktop", "Linux"]


func _preset_sections(cfg: ConfigFile) -> Dictionary:
	var out := {}
	for section in cfg.get_sections():
		if section.begins_with("preset.") and section.count(".") == 1:
			out[str(cfg.get_value(section, "name", ""))] = section
	return out


func _manifest_globs() -> PackedStringArray:
	var out := PackedStringArray()
	var file := FileAccess.open(EXCLUDES, FileAccess.READ)
	if file == null:
		return out
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if trimmed != "" and not trimmed.begins_with("#"):
			out.append(trimmed)
	file.close()
	return out


func _demo_excludes() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS) != OK:
		return PackedStringArray()
	var sections := _preset_sections(cfg)
	if not sections.has("Linux Demo"):
		return PackedStringArray()
	return str(cfg.get_value(sections["Linux Demo"], "exclude_filter", "")).split(",", false)


func _test_demo_presets_track_regular_presets() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load(PRESETS) == OK, "demo presets: export_presets.cfg loads")
	var sections := _preset_sections(cfg)
	var manifest := _manifest_globs()
	_check(manifest.size() > 5, "demo presets: excludes.txt lists the demo's exclusions")
	var hint := " (run python3 tools/demo_build/build_demo.py sync)"
	for base_name in BASE_PRESETS:
		var demo_name: String = base_name + " Demo"
		_check(sections.has(base_name), "demo presets: regular preset '%s' exists" % base_name)
		_check(sections.has(demo_name), "demo presets: '%s' exists%s" % [demo_name, hint])
		if not (sections.has(base_name) and sections.has(demo_name)):
			continue
		var base: String = sections[base_name]
		var demo: String = sections[demo_name]
		_check(str(cfg.get_value(demo, "custom_features", "")) == DemoBuild.FEATURE,
			"demo presets: '%s' carries the demo feature tag" % demo_name)
		_check(str(cfg.get_value(base, "custom_features", "")).find(DemoBuild.FEATURE) == -1,
			"demo presets: regular '%s' does not carry the demo tag" % base_name)
		for key in cfg.get_section_keys(base):
			if key in ["name", "custom_features", "exclude_filter", "export_path"]:
				continue
			_check(cfg.get_value(demo, key) == cfg.get_value(base, key),
				"demo presets: '%s' %s matches the regular preset%s" % [demo_name, key, hint])
		var base_options := base + ".options"
		var demo_options := demo + ".options"
		var options_match := cfg.has_section(demo_options)
		for key in cfg.get_section_keys(base_options):
			if not cfg.has_section_key(demo_options, key) \
					or cfg.get_value(demo_options, key) != cfg.get_value(base_options, key):
				options_match = false
		_check(options_match, "demo presets: '%s' options match the regular preset%s" % [demo_name, hint])
		var demo_excludes := str(cfg.get_value(demo, "exclude_filter", "")).split(",", false)
		var missing := PackedStringArray()
		for glob in str(cfg.get_value(base, "exclude_filter", "")).split(",", false) + manifest:
			if not demo_excludes.has(glob):
				missing.append(glob)
		_check(missing.is_empty(), "demo presets: '%s' excludes everything the regular preset and excludes.txt do (%s)%s"
			% [demo_name, ", ".join(missing), hint])
		for start_id in DemoBuild.START_IDS:
			_check(not demo_excludes.has("data/starts/%s.json" % start_id),
				"demo presets: '%s' ships the %s start" % [demo_name, start_id])
		_check(demo_excludes.has("data/starts/open_field.json"),
			"demo presets: '%s' leaves out a start the demo locks" % demo_name)


func _test_shipped_code_avoids_demo_excluded_paths() -> void:
	# A shipped script or scene that preloads a demo-excluded file breaks the demo build at
	# parse time. Reach such a file by a path string guarded by ResourceLoader.exists instead.
	var globs := _demo_excludes()
	_check(globs.size() > 20, "demo isolation: the Linux Demo exclude list was read (%d globs)" % globs.size())
	var offenders := PackedStringArray()
	var scanned := 0
	# A scene node whose script the demo leaves out is dropped from the staged scene
	# (build_demo.py strip_scene), so a Script ext_resource is not a dangling reference.
	var path_re := RegEx.create_from_string("(?:preload\\(|\\[ext_resource type=\"(?!Script)[^\"]*\"[^\\]]*path=)\"res://([^\"]+)\"")
	for directory in ["res://scripts", "res://scenes"]:
		var files: Array = _files_with_ext(directory, ".gd") + _files_with_ext(directory, ".tscn")
		for file_path in files:
			if _excluded(file_path.trim_prefix("res://"), globs):
				continue
			var text := FileAccess.get_file_as_string(file_path)
			scanned += 1
			for m in path_re.search_all(text):
				var target := m.get_string(1)
				if _excluded(target, globs):
					offenders.append("%s -> %s" % [file_path.get_file(), target])
	_check(scanned > 50, "demo isolation: the scan read the shipped scripts and scenes (%d files)" % scanned)
	_check(offenders.is_empty(),
		"demo isolation: nothing shipped preloads a demo-excluded file (%s)" % ", ".join(offenders))


func _excluded(path: String, globs: PackedStringArray) -> bool:
	for glob in globs:
		if path.match(glob):
			return true
	return false


func _files_with_ext(directory: String, ext: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files_with_ext(directory.path_join(sub), ext))
	for file in dir.get_files():
		if file.ends_with(ext):
			out.append(directory.path_join(file))
	return out


func _test_demo_terminal_keeps_cash_and_unlock_all() -> void:
	var term: Node = load("res://scripts/debug_terminal.gd").new()
	add_child(term)
	await get_tree().process_frame
	var was_unlocked: bool = term._cheats_unlocked
	DemoBuild.forced = true
	term._cheats_unlocked = false
	_check(term._run_command("cash 10") == "invalid operation", "demo terminal: locked before debug CandC")
	_check("enabled" in term._run_command("debug CandC"), "demo terminal: debug CandC still unlocks")
	var before: float = MatchState.money
	term._run_command("cash 40")
	_check(absf(MatchState.money - (before + 40.0)) < 0.001, "demo terminal: cash still works")
	_check(DemoBuild.allows_cheat("unlock all"), "demo terminal: unlock all is kept")
	_check(term._run_command("help") == term.DEMO_HELP, "demo terminal: help lists only the demo commands")
	for blocked in ["unlock demo", "unlock recycling", "unlock hidden_buildings", "unlock advisors",
			"unlock hydro", "research all", "skip 5", "win all", "toggle heightmap", "swap song",
			"survey all", "bankrupt", "enable procedural all", "sellmode market", "save x", "load x"]:
		_check("not available in the demo" in term._run_command(blocked),
			"demo terminal: '%s' is refused" % blocked)
	_check(not term.demo_is_unlocked(), "demo terminal: the demo locks cannot be lifted")
	DemoBuild.forced = false
	if not DemoBuild.active():
		_check(DemoBuild.allows_cheat("toggle heightmap"), "full build: every command is allowed")
	term._cheats_unlocked = was_unlocked
	term.queue_free()


func _test_demo_runtime_gates() -> void:
	DemoBuild.forced = true
	for arg in DemoBuild.user_args():
		_check(DemoBuild.USER_ARGS.has(arg), "demo args: '%s' is on the demo allow-list" % arg)
	_check(DemoBuild.version_label().ends_with("-demo"), "demo telemetry: the version is tagged -demo")
	var menu: Control = load("res://scripts/main_menu.gd").new()
	_check(not menu.call("_map_editor_available"), "demo menu: the map editor is never offered")
	menu.free()
	DemoBuild.forced = false
	if not DemoBuild.active():
		_check(not DemoBuild.version_label().ends_with("-demo"), "full telemetry: the version is untagged")


func _ids(path: String, text: String, column: String) -> Dictionary:
	var out := {}
	for row in DemoDataFilter._rows(text):
		var id := str(row.fields.get(column, "")).strip_edges()
		if id != "":
			out[id] = true
	return out


func _test_demo_data_filter_drops_gated_rows() -> void:
	var gated_recipes := ["r_105", "r_106", "r_107", "r_108", "r_110", "r_111", "r_113", "r_166", "r_167"]
	var cases := [
		[DemoDataFilter.BUILDINGS, "ID", DemoBuild.HIDDEN_BUILDING_IDS.keys() + DemoBuild.RECYCLING_BUILDING_IDS.keys()],
		[DemoDataFilter.GOODS, "ID", DemoBuild.RECYCLING_GOOD_IDS.keys()],
		[DemoDataFilter.RECIPES, "recipe_id", gated_recipes],
		[DemoDataFilter.RESEARCH, "research_node_id", ["research_recyc_001", "research_recyc_006", "research_biochem_004",
			"research_petro_020", "research_mining_008", "research_mining_009"]],
	]
	var waste := DemoDataFilter.gated_good_names()
	for c in cases:
		var path: String = c[0]
		var source := FileAccess.get_file_as_string(path)
		var filtered := DemoDataFilter.filter(path, source)
		var before := _ids(path, source, c[1])
		var after := _ids(path, filtered, c[1])
		for id in c[2]:
			_check(before.has(id) and not after.has(id), "demo data: %s drops %s" % [path.get_file(), id])
		var lost := 0
		for row in DemoDataFilter._rows(filtered):
			if row.fields.is_empty():
				continue
			if not source.contains(row.raw):
				lost += 1
			for value in row.fields.values():
				if waste.has(str(value).strip_edges()):
					_check(false, "demo data: %s row %s still names %s" % [path.get_file(), row.values[0], value])
		var rewritten := 9 if path == DemoDataFilter.RECIPES else 0   # the farm recipes lose their Waste Water
		_check(lost == rewritten, "demo data: %s keeps its other rows byte for byte (%d rewritten, want %d)"
			% [path.get_file(), lost, rewritten])
		_check(after.size() > before.size() * 0.8, "demo data: %s keeps most rows (%d of %d)" % [path.get_file(), after.size(), before.size()])
		_check(filtered.split("\n")[0] == source.split("\n")[0], "demo data: %s keeps its header" % path.get_file())
	var research := FileAccess.get_file_as_string(DemoDataFilter.RESEARCH)
	for row in DemoDataFilter._rows(DemoDataFilter.filter(DemoDataFilter.RESEARCH, research)):
		if DemoBuild.is_gated_research(str(row.fields.get("category", "")), str(row.fields.get("Action", ""))):
			_check(false, "demo data: no gated research row survives (%s)" % row.fields.get("research_node_id", ""))
	var presentation: Dictionary = JSON.parse_string(DemoDataFilter.filter(DemoDataFilter.PRESENTATION,
		FileAccess.get_file_as_string(DemoDataFilter.PRESENTATION)))
	_check(not presentation.has("research_recyc_001") and presentation.has("research_mining_001"),
		"demo data: research presentation drops the gated nodes only")


## Run the suite with `-- --as-demo` to load the catalog as the demo does. In that run the
## loaded catalog must equal the filtered files; in a normal run the gated rows must load.
func _test_demo_run_loads_what_the_demo_ships() -> void:
	var recipes := _ids(DemoDataFilter.RECIPES, DemoDataFilter.filter(DemoDataFilter.RECIPES,
		FileAccess.get_file_as_string(DemoDataFilter.RECIPES)), "recipe_id")
	var research := _ids(DemoDataFilter.RESEARCH, DemoDataFilter.filter(DemoDataFilter.RESEARCH,
		FileAccess.get_file_as_string(DemoDataFilter.RESEARCH)), "research_node_id")
	if not DemoBuild.active():
		_check(not Catalog.get_building("b_036").is_empty(), "full run: the Recycling Plant loads")
		return
	for b in Catalog.all_buildings():
		_check(not DemoBuild.is_gated_building(str(b.get("id", ""))), "demo run: %s is not loaded" % b.get("id", ""))
	var extra := PackedStringArray()
	for r in Catalog._all_recipes:
		if not recipes.has(str(r.get("recipe_id", ""))):
			extra.append(str(r.get("recipe_id", "")))
	_check(extra.is_empty(), "demo run: every loaded recipe ships in the demo file (%s)" % ", ".join(extra))
	var extra_research := PackedStringArray()
	for d in ResearchState._unlock_defs:
		if not research.has(str(d.get("research_node_id", ""))):
			extra_research.append(str(d.get("research_node_id", "")))
	_check(extra_research.is_empty(), "demo run: every loaded research node ships (%s)" % ", ".join(extra_research))


## Every `# demo:strip` region closes, holds no other region, and its demo:keep lines are
## `#|` lines (build_demo.py strip_source enforces the same at stage time).
func _test_demo_strip_regions_are_well_formed() -> void:
	var marked := 0
	for directory in ["res://scripts", "res://scenes", "res://addons"]:
		for file_path in _files_with_ext(directory, ".gd"):
			var text := FileAccess.get_file_as_string(file_path)
			if not text.contains("# demo:"):
				continue
			marked += 1
			var state := ""
			var problem := ""
			var n := 0
			for line in text.split("\n"):
				n += 1
				var t := line.strip_edges()
				if t.begins_with("# demo:strip"):
					if state != "":
						problem = "line %d: nested demo:strip" % n
					state = "strip"
				elif t.begins_with("# demo:keep"):
					if state != "strip":
						problem = "line %d: demo:keep outside a region" % n
					state = "keep"
				elif t.begins_with("# demo:end"):
					if state == "":
						problem = "line %d: demo:end without demo:strip" % n
					state = ""
				elif state == "keep" and t != "" and not t.begins_with("#|"):
					problem = "line %d: demo:keep line without #|" % n
				if problem != "":
					break
			if problem == "" and state != "":
				problem = "a region is never closed"
			_check(problem == "", "demo regions: %s is well formed %s" % [file_path.get_file(), problem])
	_check(marked >= 10, "demo regions: the marked scripts were found (%d)" % marked)
