extends "res://tests/test_base.gd"
## The DS2 encyclopedia (scripts/encyclopedia_ds2/): what each page lists, how the right page breaks, the views and
## Back, the links, and the old search panel brought back by the flag.

const FEATURE := "encyclopedia"
const Data := preload("res://scripts/encyclopedia_ds2/catalogue.gd")
const STEEL := "g_006"


func _overlay() -> Control:
	var overlay: Control = load("res://scripts/search_overlay.gd").new()
	add_child(overlay)
	return overlay


func _test_encyclopedia_ds2_steel_lists() -> void:
	var made := Data.made_by(STEEL)
	var want := Data.recipes().filter(func(r: Dictionary) -> bool:
		return (r.get("outputs", []) as Array).any(func(o: Dictionary) -> bool: return str(o.get("good_id", "")) == STEEL))
	_check(made.size() == want.size() and made.size() > 0, "encyclopedia ds2: Made by lists every recipe that makes steel (%d)" % made.size())
	_check(made.any(func(row: Dictionary) -> bool: return str(row.id) == "r_003"), "encyclopedia ds2: Steelmaking is among them")
	var groups := Data.used_in_groups(STEEL)
	var total := 0
	var sorted := true
	var only_steel := true
	for i in groups.size():
		var g: Dictionary = groups[i]
		total += (g.rows as Array).size()
		if i > 0 and (g.rows as Array).size() > ((groups[i - 1] as Dictionary).rows as Array).size():
			sorted = false
		for row: Dictionary in g.rows:
			var ins: Array = row.inputs
			if ins.size() != 1 or str(ins[0][0]) != STEEL:
				only_steel = false
			var outs: Array = row.outputs
			if outs.is_empty() or str(outs[0][0]) != str(g.good):
				only_steel = false
	_check(total == Data.used_in_count(STEEL) and total > 0, "encyclopedia ds2: Used in counts every recipe in its groups")
	_check(sorted, "encyclopedia ds2: the largest Used in group comes first")
	_check(only_steel, "encyclopedia ds2: a Used in row shows steel going in and the group's good coming out")
	var makers := Data.makers(STEEL)
	_check(makers.any(func(m: Dictionary) -> bool: return str(m.id) == "b_002"), "encyclopedia ds2: the Furnace is among the buildings that make steel")
	_check(Data.inputs_of(STEEL).has("g_004") and not Data.inputs_of(STEEL).has(STEEL), "encyclopedia ds2: iron ingots go into steel, steel not into itself")
	var facts := Data.good_facts(STEEL)
	var labels := facts.map(func(f: Array) -> String: return str(f[0]))
	_check(labels == ["Freight", "Price impact", "Buyable", "Sellable", "Base price"], "encyclopedia ds2: a good's specification lines, in order")
	_check(str(facts[1][2]) == Data.PRICE_IMPACT_ENTRY and str(facts[2][1]) == "YES", "encyclopedia ds2: Price impact links to Mechanics, Buyable reads YES")
	_check(Data.freight_text("solid_heavy") == "Solid, heavy", "encyclopedia ds2: freight reads as words")


func _test_encyclopedia_ds2_look_up() -> void:
	var found := Data.look_up("steel")
	_check(not (found.recipes as Array).is_empty() and str((found.recipes as Array)[0].id) == "r_003", "encyclopedia ds2: the look up puts Steelmaking first among recipes")
	var best := Data.best_match(found)
	_check(str(best.get("kind", "")) == "good" and str(best.get("id", "")) == STEEL, "encyclopedia ds2: steel's best match is the good")
	_check(Data.entry_count(Data.look_up("")) == 0, "encyclopedia ds2: an empty look up finds nothing")


func _test_encyclopedia_ds2_paging() -> void:
	var parts: Array = [{"h": 66.0, "bar": "MADE BY"}]
	for i in 9:
		parts.append({"h": 120.0, "row": i})
	parts.append({"h": 66.0, "bar": "USED IN"})
	parts.append({"h": 66.0, "head": true, "head_name": "Motor"})
	for i in 9:
		parts.append({"h": 120.0, "row": 100 + i})
	var pages := Data.paginate(parts, func(_i: int) -> float: return 1000.0)
	var fits := true
	var no_dangling := true
	var rows := 0
	for page: Array in pages:
		var h := 0.0
		for p: Dictionary in page:
			h += float(p.h)
			if p.has("row"):
				rows += 1
		if h > 1000.0:
			fits = false
		var last: Dictionary = page[-1]
		if last.has("bar") or last.has("head"):
			no_dangling = false
	_check(pages.size() >= 3 and fits, "encyclopedia ds2: the column breaks into pages that each fit (%d pages)" % pages.size())
	_check(no_dangling, "encyclopedia ds2: a heading never ends a page")
	_check(rows == 18, "encyclopedia ds2: every row lands on a page once")
	var carried := false
	for page_i in range(1, pages.size()):
		var first: Dictionary = (pages[page_i] as Array)[0]
		if first.has("bar") and str(first.bar).ends_with(", continued"):
			carried = true
	_check(carried, "encyclopedia ds2: a section carried over starts the next page under its heading, continued")


func _test_encyclopedia_ds2_views_and_back() -> void:
	var was := UiPrefs.use_encyclopedia_ds2
	# Opening entries records telemetry, which is part of a save: kept off so this test leaves no events behind.
	var telemetry_was: bool = TelemetryState.enabled
	TelemetryState.enabled = false
	UiPrefs.set_use_encyclopedia_ds2(true)
	var overlay := _overlay()
	overlay.call("open_encyclopedia_good", STEEL)
	var book: Control = overlay.call("ds2_book")
	_check(book != null and book.visible and overlay.visible, "encyclopedia ds2: opening a good opens the catalogue")
	_check(str(book.call("current_view").get("kind", "")) == "good", "encyclopedia ds2: it opens on the good's entry")
	_check(int(book.call("page_count")) >= 2, "encyclopedia ds2: steel's right page runs to more than one page")
	book.call("next_page")
	_check(int(book.call("page_index")) == 1, "encyclopedia ds2: Next page turns the page")
	book.call("previous_page")
	_check(int(book.call("page_index")) == 0, "encyclopedia ds2: Previous page turns it back")
	var left: Node = book.get_node("Book/LeftPage")
	var graph: Node = left.get_node_or_null("GoodsGraphLink")
	_check(graph != null and str(graph.get("tip")) == "Go to Steel's Goods Graph", "encyclopedia ds2: the Goods Graph key says where it goes")
	var link: Node = left.get_node_or_null("Link_" + Data.PRICE_IMPACT_ENTRY)
	_check(link != null, "encyclopedia ds2: Price impact is a link")
	if link != null:
		(link as BaseButton).pressed.emit()
	_check(str(book.call("current_view").get("kind", "")) == "mechanic" and str(book.call("current_view").get("id", "")) == Data.PRICE_IMPACT_ENTRY,
		"encyclopedia ds2: the link opens Mechanics at Price impact")
	book.call("go_back")
	_check(str(book.call("current_view").get("kind", "")) == "good", "encyclopedia ds2: Back returns to the good")
	var right: Node = book.get_node("Book/RightPage")
	var plant: Node = right.get_node_or_null("Plant_b_002")
	_check(plant != null and str(plant.get("tip")) == "Furnace", "encyclopedia ds2: a recipe's building mark names it on hover")
	_check(not _has_named(book, "Build"), "encyclopedia ds2: no build key on the page")
	book.call("go_back")
	_check(not overlay.visible, "encyclopedia ds2: Back with nothing to go back to closes the encyclopedia")
	overlay.call("open_encyclopedia")
	_check(str(book.call("current_view").get("kind", "")) == "contents" and int(book.call("history_size")) == 0, "encyclopedia ds2: the encyclopedia opens on its contents, fresh")
	book.call("open_section", "buildings")
	_check(str(book.call("current_view").get("section", "")) == "buildings", "encyclopedia ds2: a tab opens its section")
	overlay.call("open_encyclopedia_entry", "land_prices")
	_check(str(book.call("current_view").get("kind", "")) == "mechanic", "encyclopedia ds2: a mechanic's deep link opens its entry")
	UiPrefs.set_use_encyclopedia_ds2(false)
	overlay.call("open_encyclopedia")
	var stack: Control = overlay.get_node("SearchStack")
	_check(stack.visible and not book.visible, "encyclopedia ds2: with the flag off the old search panel is back")
	UiPrefs.set_use_encyclopedia_ds2(was)
	TelemetryState.enabled = telemetry_was
	overlay.call("close_search")
	overlay.queue_free()


func _has_named(node: Node, prefix: String) -> bool:
	if str(node.name).begins_with(prefix):
		return true
	for child in node.get_children():
		if _has_named(child, prefix):
			return true
	return false


## The Market price mechanics page quotes the live ladder and follows the copy rule.
func _test_encyclopedia_market_price_page() -> void:
	var page: String = load("res://scripts/search_overlay.gd").market_price_page()
	var ladder: Array = EconomyConfig.PRICE_IMPACT_LADDER
	var top: Array = ladder[-1]
	_check(page.contains("top rate of %s%% once you pass %sx" % [String.num(float(top[1]), 2), String.num(float(top[0]), 0)]), "market page: the top step's rate is the ladder's")
	var rows := 0
	for rung: Array in ladder:
		if page.contains("Over %sx base output[/cell][cell padding=0,1,28,1]%s%%/turn[/cell]" % [String.num(float(rung[0]), 0), String.num(float(rung[1]), 2)]):
			rows += 1
	_check(rows == ladder.size(), "market page: a table row for every step (%d of %d)" % [rows, ladder.size()])
	_check(page.contains("never rise above %d%% of its starting price or fall below %d%%" % [100 + int(EconomyConfig.PRICE_IMPACT_CEILING_PCT), 100 + int(EconomyConfig.PRICE_IMPACT_FLOOR_PCT)]),
		"market page: the floor and ceiling are the model's")
	_check(page.contains("last %d turns" % EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS), "market page: the memory is the model's")
	_check(not page.contains("%d") and not page.contains("%s") and not page.contains("%%"), "market page: no format marks left in the text")
	_check(not page.contains("\u2014") and not page.contains("\u2013") and not page.contains(";"), "market page: no dashes or semicolons (copy rule)")
	_check(not page.contains("YOU") and not page.contains("NET") and not page.contains("auto-sell"), "market page: no capitals for emphasis, no retired auto-sell claim")


## The worked example: steel sold over its 3x step, iron ingots bought over their 5x step, rows of the market panel.
func _test_encyclopedia_market_example() -> void:
	var overlay = load("res://scripts/search_overlay.gd")
	var ex: Array = overlay.market_price_example()
	_check(ex.size() == 3, "market example: a passage, the rows and the takeaway")
	if ex.size() != 3:
		return
	var steps_s: PackedInt32Array = MarketState.impact_thresholds("g_006")
	var steps_i: PackedInt32Array = MarketState.impact_thresholds("g_004")
	var sold: Dictionary = overlay._example_trade("g_006", 1, true)
	var bought: Dictionary = overlay._example_trade("g_004", 2, false)
	_check(int(sold.volume) > steps_s[1] and int(sold.volume) <= steps_s[2], "market example: the steel sold sits on the 3x step (%d between %d and %d)" % [int(sold.volume), steps_s[1], steps_s[2]])
	_check(int(bought.volume) > steps_i[2] and int(bought.volume) <= steps_i[3], "market example: the iron bought sits on the 5x step (%d between %d and %d)" % [int(bought.volume), steps_i[2], steps_i[3]])
	var rate_s := EconomyConfig.price_impact_rate(float(sold.volume), Catalog.base_output_for_good("g_006"), EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn)))
	_check(is_equal_approx(rate_s, float(sold.rate)), "market example: the steel rate is the ladder's for that volume")
	var table: String = ex[1]
	_check(table.contains("[b]Buy[/b]") and table.contains("[b]Sell[/b]") and table.contains("[b]Impact[/b]"), "market example: the rows carry the market panel's columns")
	_check(table.contains("%d sold" % int(sold.volume)) and table.contains("%d bought" % int(bought.volume)), "market example: each row says what was traded")
	var page: String = overlay.market_price_page()
	_check(page.contains("To see it at work") and not page.contains("%d") and not page.contains(";"), "market example: on the page, no format marks or semicolons")


## The Building Economics page quotes the model it explains and follows the copy rule.
func _test_encyclopedia_building_economics_page() -> void:
	var page: String = load("res://scripts/search_overlay.gd").building_economics_page()
	_check(page.contains("Tax takes %d%% of each turn's profit above the first £%d" % [roundi(EconomyConfig.TAX_RATE * 100.0), roundi(EconomyConfig.TAX_FREE_PROFIT_FLOOR)]),
		"economics page: the tax rate and the tax free floor are the model's")
	_check(page.contains("dividends then take %d%%" % roundi(EconomyConfig.DIVIDEND_RATE * 100.0)), "economics page: the dividend rate is the model's")
	var econ := preload("res://scripts/building_economics.gd")
	_check(page.contains("under %d%%, turning amber up to %d%%" % [roundi(econ.LAMP_AMBER_SHARE * 100.0), roundi(econ.LAMP_RED_SHARE * 100.0)]), "economics page: the lamp bands are the model's")
	_check(page.contains("does not count those goods twice") and not page.contains("CANNOT"), "economics page: own inputs cancel, the retired double counting warning is gone")
	_check(page.contains("Take an iron furnace making 70"), "economics page: the example uses Pig Iron Smelting's output")
	_check(not page.contains("Turn Summary"), "economics page: no retired panel names")
	_check(not page.contains("%d") and not page.contains("%s") and not page.contains(";") and not page.contains("\u2014"), "economics page: no format marks, semicolons or dashes")

