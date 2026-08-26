extends Node
## Do the named rival firms stay in their own industries?
##
## Sweeps many match seeds and reports every appearance of a themed firm in a good it has no
## business in, plus how often the goods table ends up thin or empty — the cost of filtering a
## nine-strong roster is that some goods run out of eligible rivals, and that has to stay rare.
##
##   <godot> --headless --path . res://tools/rival_theme_check.tscn --quit-after 600
##
## A SCENE, not --script: GDScript resolves autoload names at compile time and there are no
## autoloads under --script, so Catalog/CompanyRankings would not even compile (see CLAUDE.md).

const CompanyNames := preload("res://scripts/company_names.gd")
const SEEDS := 200


func _ready() -> void:
	await get_tree().process_frame
	var goods: Array = Catalog.all_goods()
	var violations: Dictionary = {}     # "firm -> good" -> count
	var appearances: Dictionary = {}    # firm -> count
	var thin := 0
	var empty := 0
	var rows := 0
	for s in range(SEEDS):
		var match_seed := 1000 + s * 7919
		var names: Array = CompanyRankings._rival_names_for(match_seed)
		for g in goods:
			var good: Dictionary = g
			var good_id := str(good.get("id", ""))
			if str(good.get("goods_graph_tier", "")) == "apex":
				continue
			if Catalog.base_output_for_good(good_id) <= 0:
				continue
			rows += 1
			var picked: Array = CompanyRankings._competitors_for_good(match_seed, good_id)
			if picked.is_empty():
				empty += 1
			elif picked.size() < 3:
				thin += 1
			for idx in picked:
				var firm := str(names[idx])
				appearances[firm] = int(appearances.get(firm, 0)) + 1
				if not CompanyNames.competes_in(firm, good):
					var key := "%s -> %s" % [firm, str(good.get("display_name", good_id))]
					violations[key] = int(violations.get(key, 0)) + 1
	print("[RIVALS] %d seeds, %d good-rows" % [SEEDS, rows])
	print("[RIVALS] out-of-industry appearances: %d distinct (want 0)" % violations.size())
	var shown := 0
	for k in violations:
		if shown < 12:
			print("   VIOLATION %s x%d" % [k, violations[k]])
			shown += 1
	print("[RIVALS] rows with fewer than 3 rivals: %d (%.1f%%)  with none: %d (%.2f%%)" %
		[thin, 100.0 * thin / maxf(1.0, rows), empty, 100.0 * empty / maxf(1.0, rows)])
	# A themed firm should still appear a fair amount — a filter that silences one is a bug too.
	var keys: Array = appearances.keys()
	keys.sort()
	for k in keys:
		print("   %-24s %d" % [k, appearances[k]])
	get_tree().quit()
