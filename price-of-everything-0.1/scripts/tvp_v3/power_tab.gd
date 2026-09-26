extends RefCounted
## Tile view v3: the Power tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The site's meter panel, top to bottom:
##   - POWER BALANCE, a dark instrument plate. While your buildings here made or drew power last turn, the
##     meter (power_meter.gd): made over drawn as two bars on one scale, a slice for each kind of building,
##     the MW on LED screens and the net under them, and Build power standing over the MADE figure it adds
##     to (Construct, locked to this tile, on its power buildings). Under it, lamp readouts, each a raised
##     icon, a lamp, a name and a line of words, with the one key that acts on it in a column down the
##     plate's right: the cables (Transport, while near their cap), the national grid while the tile is
##     linked (the power map), and wind and solar while the tile touches them and nothing ran short. On an
##     idle tile the meter gives way to two readouts: the cables, naming the building of yours that cannot
##     run without them (Add cables), and your power plants here (Build power).
##   - CUT SHORT IN LULLS, the diagnostics' plastic case, while any of your buildings here ran short when
##     the wind or sun fell: the verdict on a glass readout (how much of the draw had no backup) with
##     Reduce intermittency beside it while the tile has no battery storage or it is full, then each
##     building cut short as a module fed from the cable, two lines (its name, then how much of its draw
##     had no backup), its output cut on an LED under one OUTPUT CUT caption, and its Go to key. The
##     ledger's key stands in the heading. One rule lights every lamp here, the engine's own cut
##     (EconomyConfig.INTERMITTENCY_DERATE): a building is red when it lost the full cut, amber when it
##     lost less, and the verdict is red when any building here lost the full cut.
##   - BATTERIES, where the tile has battery storage: the bank (the cells loaded, in MW of backup, of the
##     MW the storage takes), what the bank backed up last turn on a lamp readout, and each kind of cell
##     with its count on a drum and its keys: Load (or Order, with none in stock here) and Unload.
## Each lamp and the words beside it come from one reading (the *_reading helpers). The grid's lamp and the
## idle tile's take the tone the Power key takes from TileViewData.power_summary, so the tab and its key
## agree. Every figure is the engine's: Power's per-tile MW, cable cap and settlement, Production's
## per-plant dispatch and intermittency roll-up (what each building and the bank settled last turn), the
## battery storage's cells.

const Section := preload("res://scripts/bdp_v3_section.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
const CabinetKey := preload("res://scripts/tile_cabinet_key.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Cable := preload("res://scripts/bdp_v3_cable.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Readout := preload("res://scripts/bdp_v3_readout.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const Meter := preload("res://scripts/tvp_v3/power_meter.gd")
const Bank := preload("res://scripts/tvp_v3/power_bank.gd")

const BODY_PX := 14
const CAPTION_PX := 15
const SECTION_GAP := 14
## A lamp beside words, as the diagnostics' rows have (a share of the status lamp).
const LAMP_SCALE := 0.72
## A raised icon beside its lamp.
const ICON_PX := 30.0
## Every key on the balance plate is one width, so they stand in one column down its right; the cut-short
## case's keys are wider, to print Reduce intermittency at the caption size.
const KEY_W := 140.0
const CASE_KEY_W := 176.0
## Building Detail's diagnostics module (layout.json diag_module) and the icon well (icon_well).
const MODULE: Texture2D = preload("res://assets/ui/bdp_v3/diag_module.png")
const MODULE_MARGIN := 10.0 / 1.875
const MODULE_CORNER := 26.0 * 2.0 / 1.875
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
## The cable down the cut-short modules, and the room its taps take (as the diagnostics').
const CABLE_X := 10.0
const GUTTER := CABLE_X + Cable.TAP_LENGTH
const AFFECTED_SHOWN := 3
## A module's output cut: the column its LED and % stand in, under the one OUTPUT CUT caption.
const CUT_W := 84.0
## A module's inner padding (right) and the room between its parts.
const MODULE_PAD_R := 10.0
const MODULE_SEP := 12.0
## The battery cells, in the order the storage lists them.
const CHEMISTRIES := ["lithium_battery", "sodium_battery", "iron_battery"]
const CELL_ICON_PX := 44
## A cable run this full of its cap is near its limit.
const NEAR_CAP := 0.9
const DIR := "res://assets/ui/bdp_v3/"


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile := str(panel.get("_current_tile_id"))
	pane.add_theme_constant_override("separation", SECTION_GAP)
	var power := TileViewData.power_summary(tile)
	var im: Dictionary = Production.get_tile_intermittency(tile)
	pane.add_child(_balance(panel, tile, power, im))
	if not (im.get("affected", []) as Array).is_empty():
		pane.add_child(_cut_short(panel, tile, im))
	if _has_bank(tile):
		pane.add_child(_batteries(panel, tile, im))


## Construct, locked to this tile, showing its power buildings (the Power filter), or those matching
## `search`.
static func _open_construct(panel: Control, search: String) -> void:
	panel.call("_on_bl_build_pressed")
	var cp_name := "ConstructPanelV2" if UiPrefs.use_construct_panel_v2 else "ConstructPanel"
	var cp := panel.get_tree().root.find_child(cp_name, true, false)
	if cp == null or not (cp as CanvasItem).visible:
		return
	if cp.has_method("_on_filter_toggled"):
		cp.call("_on_filter_toggled", true, "power")
	if search != "" and cp.has_method("_on_search_changed"):
		var field: Variant = cp.get("_search_input")
		if field is LineEdit:
			(field as LineEdit).text = search
		cp.call("_on_search_changed", search)


## The lamp the Power key shows for a power_summary status (tile_info_panel_v2._refresh_keys_v3: amber for
## warn, red for problem), with the tab's green for ok. The key and the tab read the one status.
static func status_tone(status: String) -> String:
	return {"ok": "ok", "warn": "warn", "problem": "bad"}.get(status, "off") as String


# ── The balance ─────────────────────────────────────────────────────────────────────────────────────────

static func _balance(panel: Control, tile: String, power: Dictionary, im: Dictionary) -> Control:
	var sec := _section("PowerBalance", "dark", "Power balance")
	var body: VBoxContainer = sec.get("content")
	body.add_theme_constant_override("separation", 12)
	var build := _key("Build power", "PowerBuildKey", "Build a power plant or battery storage on this tile, in Construct")
	build.pressed.connect(func() -> void: _open_construct(panel, ""))
	var made := int(power.produced)
	var drawn := int(power.consumed)
	var idle := made == 0 and drawn == 0
	var rows := VBoxContainer.new()
	rows.name = "Readouts"
	rows.add_theme_constant_override("separation", 10)
	if idle:
		rows.add_child(_cables_row(panel, tile, power))
		rows.add_child(_plants_row(tile, build))
	else:
		var net := int(power.net)
		var digits := 1
		for f: int in [made, drawn, net]:
			digits = maxi(digits, Led.cells_for(str(f)).size())
		var meter: Control = Meter.new()
		meter.set("on_open", func(iid: String) -> void: panel.call("_open_building_or_construction", iid))
		meter.call("set_key", build)
		meter.set("notes", [_plants_note(tile) if made == 0 else "", "Nothing of yours drew power here" if drawn == 0 else ""])
		# Made is lit green; drawn red and unsigned, as Building Detail's costs; the net in the key's status.
		meter.call("set_reading", _makers(tile), _users(tile), made, drawn, net, digits,
			[DS.PALETTE.OK if made > 0 else DS.PALETTE.TEXT, DS.PALETTE.DANGER if drawn > 0 else DS.PALETTE.TEXT,
			_net_ink(str(power.status), net)])
		body.add_child(meter)
		body.add_child(_rule())
		rows.add_child(_cables_row(panel, tile, power))
	if bool(power.get("connected", false)):
		rows.add_child(_grid_row(panel, tile, power))
	if not idle and _touches_green(im) and (im.get("affected", []) as Array).is_empty():
		var calm := calm_reading(im)
		rows.add_child(_readout("diag_icon_intermittency", str(calm.tone), "Wind and solar", str(calm.words), null))
	body.add_child(rows)
	return sec


## The net's ink: the tab key's status, green when the tile has power to spare.
static func _net_ink(status: String, net: int) -> Color:
	match status:
		"warn":
			return DS.PALETTE.WARN
		"problem":
			return DS.PALETTE.DANGER
		"ok":
			return DS.PALETTE.OK if net > 0 else DS.PALETTE.TEXT
	return DS.PALETTE.TEXT


## Your buildings that made power here last turn, one entry per kind (building and recipe), at what the
## engine dispatched (each plant's cable-capped output, as Production recorded it).
static func _makers(tile: String) -> Array:
	var kinds := {}
	var order: Array = []
	var sources: Variant = Production.get("_power_sources_by_tile")
	var recorded: Array = (sources as Dictionary).get(tile, []) if sources is Dictionary else []
	for s: Dictionary in recorded:
		var iid := str(s.get("iid", ""))
		var b := BuildingState.get_building(iid)
		if b.is_empty() or not BuildingState.is_player_owned(b):
			continue
		_add_kind(kinds, order, tile, b, float(s.get("qty", 0)))
	return order.map(func(k: String) -> Dictionary: return kinds[k])


## Your buildings that drew power here last turn, one entry per kind, at the draw the engine recorded,
## biggest first.
static func _users(tile: String) -> Array:
	var kinds := {}
	var order: Array = []
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if not BuildingState.is_player_owned(b):
			continue
		var iid := str(b.get("instance_id", ""))
		if not bool(Production.last_turn_run.get(iid, false)):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		if recipe.is_empty() or str(recipe.get("output_name", "")) == "power":
			continue
		var draw := int(Production.call("_effective_energy_req", b, recipe)) if Production.has_method("_effective_energy_req") \
			else BuildingStatus.effective_energy_req(b, recipe)
		if draw > 0:
			_add_kind(kinds, order, tile, b, float(draw))
	order.sort_custom(func(a: String, c: String) -> bool: return float(kinds[a].value) > float(kinds[c].value))
	return order.map(func(k: String) -> Dictionary: return kinds[k])


static func _add_kind(kinds: Dictionary, order: Array, tile: String, b: Dictionary, mw: float) -> void:
	var bid := str(b.get("building_id", ""))
	var rid := str(b.get("recipe_id", ""))
	var key := bid + "|" + rid
	var iid := str(b.get("instance_id", ""))
	if not kinds.has(key):
		kinds[key] = {"name": BuildingNaming.label_for_tile(tile, iid, bid, rid), "value": 0.0, "count": 0,
			"iid": iid, "building_id": bid, "kind": _kind_name(bid, rid), "short": _short_name(bid, rid)}
		order.append(key)
	var k: Dictionary = kinds[key]
	k.value = float(k.value) + mw
	k.count = int(k.count) + 1
	if int(k.count) > 1:
		k.name = str(k.kind)


## A kind of building by the game's naming, less the letter that tells one from another.
static func _kind_name(bid: String, rid: String) -> String:
	var full := BuildingNaming.label(bid, rid, 0)
	return full.substr(0, full.length() - 4) if full.ends_with(" - A") else full


## The name a meter's tag prints: what a building makes (Steel, Motor), or for a power plant, the plant
## (Solar Farm), since they all make power.
static func _short_name(bid: String, rid: String) -> String:
	var recipe: Dictionary = Catalog.get_recipe(rid)
	var out := str(recipe.get("output_name", ""))
	if out != "" and out != "power":
		return str(Catalog.get_good_by_internal_name(out).get("display_name", out))
	return str(Catalog.get_building(bid).get("display_name", bid))


# ── Readings: each lamp's tone and the words that explain it, from one place ─────────────────────────────

## The cables: {tone, words, key}, key "add" (none here and yours need them), "upgrade" (near or at their cap
## with a level left) or "". With none here the lamp takes the Power key's tone: TileViewData.power_summary
## calls a tile where nothing ran "muted", so the lamp is off, as the key's is.
static func cables_reading(tile: String, power: Dictionary) -> Dictionary:
	var cap := Power.tile_power_cap(tile)
	if cap <= 0:
		var stuck := _needs_cables(tile)
		if stuck.is_empty():
			return {"tone": "off", "key": "",
				"words": "None here, and a plant or a factory built here would need them"}
		# The name held together (no break inside it), so the line wraps after it.
		var who := str(stuck[0]).replace(" ", "\u00a0") if stuck.size() == 1 else "%d of your buildings here" % stuck.size()
		return {"tone": status_tone(str(power.status)), "key": "add", "words": "%s cannot run without them" % who}
	var worst := maxi(int(power.produced), int(power.consumed))
	var share := float(worst) / float(cap)
	var key := "" if Power.cable_level_is_max(tile) else "upgrade"
	if share >= 1.0:
		return {"tone": "bad", "key": key, "words": "Full at %d MW, so power here is held back" % cap}
	if share >= NEAR_CAP:
		return {"tone": "warn", "key": key, "words": "Carrying %d of the %d MW they can" % [worst, cap]}
	return {"tone": "ok", "key": "", "words": "Level %d, carrying up to %d MW each way" % [Power.cable_level(tile), cap]}


## The national grid, while the tile is linked: {tone, words}. The lamp is the Power key's; amber means the
## tile drew more than it made, and the words say so first. Then where the draw came from (your plants here,
## your other tiles over the cables, the grid), which adds up to the drawn figure, and what went out: power
## sold straight to the grid (plants set to sell first, the top bar's power switch) and the spare your plants
## here put on the cables.
static func grid_reading(tile: String, power: Dictionary) -> Dictionary:
	var made := int(power.produced)
	var drawn := int(power.consumed)
	if made == 0 and drawn == 0:
		return {"tone": "ok", "words": "Linked, so buildings here can draw from it"}
	var tone := status_tone(str(power.status))
	var split := grid_split(tile, made, drawn)
	var parts: PackedStringArray = []
	if drawn > made:
		parts.append("Draws %d MW more than it makes" % (drawn - made))
	if drawn > 0:
		var sources: PackedStringArray = []
		if int(split.own) > 0:
			sources.append("%d MW from your plants here" % int(split.own))
		if int(split.network) > 0:
			sources.append("%d MW from your other tiles" % int(split.network))
		if int(split.grid) > 0:
			sources.append("%d MW from the grid" % int(split.grid))
		if sources.size() > 1:
			parts.append("The draw came " + _and(sources))
		elif int(split.own) > 0:
			parts.append("Your plants here covered the draw")
		elif int(split.network) > 0:
			parts.append("Your other tiles covered the draw")
		else:
			parts.append("The grid covered the draw")
	if int(split.sold) > 0:
		parts.append("%d MW made here was sold straight to the grid" % int(split.sold))
	if int(split.spare) > 0:
		parts.append("%d MW spare went out on the cables" % int(split.spare))
	return {"tone": tone, "words": ". ".join(parts)}


## Wind and solar on a tile where nothing ran short: {tone, words}. What the batteries did is the bank's
## reading, in Batteries.
static func calm_reading(_im: Dictionary) -> Dictionary:
	return {"tone": "ok", "words": "Nothing here ran short when the wind or sun fell"}


## The engine's cut at its fullest, in whole percent: a building whose whole draw was wind and solar with no
## backup loses EconomyConfig.INTERMITTENCY_DERATE of its output, one with part of it a share of that.
static func full_cut_pct() -> int:
	return roundi(EconomyConfig.INTERMITTENCY_DERATE * 100.0)


## Whether a building's cut (Production's derate) is the full one.
static func is_full_cut(derate: float) -> bool:
	return derate >= EconomyConfig.INTERMITTENCY_DERATE - 0.0005


## The one rule the cut short lamps follow, for their tooltips.
static func lamp_rule() -> String:
	return "Red when a building lost the full %d%% of its output, amber when it lost less" % full_cut_pct()


## The verdict on the buildings cut short: {tone, words, fix}. How much of the tile's draw was wind and solar
## with no backup, then what the battery storage here can still do. Red when any building here lost the
## full cut (the modules' rule), amber otherwise. `fix` is "reduce" (build battery storage: there is none,
## or it is full) or "".
static func lull_reading(tile: String, im: Dictionary) -> Dictionary:
	var unbacked := roundi(float(im.get("unfirmed_consumed", 0.0)))
	var total := int(im.get("total_consumed", 0))
	var tone := "warn"
	for a: Dictionary in im.get("affected", []):
		if is_full_cut(float(Production.get_building_intermittency(str(a.get("iid", ""))).get("derate", 0.0))):
			tone = "bad"
	var words := "All %d MW drawn here had no backup" % total if unbacked >= total \
		else "%d of the %d MW drawn here had no backup" % [unbacked, total]
	var fix := ""
	if _housing_has_room(tile):
		words += ". Your battery storage here has room for more cells"
	elif Power.tile_battery_slots(tile) > 0:
		words += ". Your battery storage here is full"
		fix = "reduce"
	else:
		fix = "reduce"
	if not TileViewData.grid_has_intermittent():
		fix = ""
	return {"tone": tone, "words": words, "fix": fix}


## One building cut short: {tone, words, cut}, in one line under its name. Red when it lost the full cut (all
## its draw was wind and solar with no backup), amber when it lost less; `cut` is the share of its output
## lost, in whole percent. A partial cut never prints as the full one, nor its draw as all of it.
static func cut_reading(a: Dictionary) -> Dictionary:
	var im := Production.get_building_intermittency(str(a.get("iid", "")))
	var demand := roundi(float(im.get("demand", a.get("power", 0))))
	var derate := float(im.get("derate", 0.0))
	if is_full_cut(derate):
		return {"tone": "bad", "cut": full_cut_pct(), "words": "All %d MW had no backup" % demand}
	var unbacked := clampi(roundi(float(im.get("unfirmed_intermittent", 0.0))), 1, maxi(1, demand - 1))
	var cut := clampi(roundi(derate * 100.0), 1, full_cut_pct() - 1)
	return {"tone": "warn", "cut": cut, "words": "%d of its %d MW had no backup" % [unbacked, demand]}


## What the battery bank here did last turn: {tone, words}. The engine spends a tile's backup on the wind
## and solar made there first (Production._allocate_power_derates, producer side), then on wind and solar
## its buildings drew from elsewhere, so while any draw here went unbacked the bank backed all it held
## (im.battery_cap, what its cells held when the turn settled). Amber when it backed all it held and a
## building here was still cut short, green when it backed what it could reach and nothing here was cut,
## off when there was nothing to back. Cells loaded or taken out since count from next turn, said with the
## figure they will give.
static func bank_reading(tile: String, im: Dictionary) -> Dictionary:
	var coming := Power.battery_fill_turns_remaining(tile)
	var arriving := "More cells arrive in %d %s" % [coming, "turn" if coming == 1 else "turns"]
	if im.is_empty():
		var idle := "Nothing here made or drew wind or solar last turn"
		return {"tone": "off", "words": idle + (". " + arriving if coming > 0 else "")}
	var held := int(im.get("battery_cap", 0))
	var made := int(im.get("green_intermittent_produced", 0))
	var unbacked := float(im.get("unfirmed_consumed", 0.0)) >= 0.5
	var cut := not (im.get("affected", []) as Array).is_empty()
	var drew := float(im.get("green_consumed", 0.0)) >= 0.5
	var now := Power.tile_firming_cap(tile)
	var tone := "off"
	var words := ""
	if held <= 0:
		words = "No cells loaded last turn"
	elif made >= held:
		tone = "warn" if cut else "ok"
		words = "Backed %d of the %d MW of wind and solar made here, all its cells could" % [held, made]
	elif unbacked:
		tone = "warn" if cut else "ok"
		words = "Backed %d MW of wind and solar drawn here, all its cells could" % held if made <= 0 \
			else "Backed all %d MW of wind and solar made here and %d MW drawn from elsewhere, all its cells could" % [made, held - made]
	elif made > 0:
		# What that did for the buildings here is the balance's wind and solar readout.
		tone = "ok"
		words = "Backed all %d MW of wind and solar made here" % made
	elif drew:
		tone = "ok"
		words = "Nothing drawn here went unbacked"
	else:
		words = "No wind or solar here to back up"
	var parts: PackedStringArray = [words]
	if now != held:
		parts.append("From next turn it backs up %d MW" % now)
	if coming > 0:
		parts.append(arriving)
	return {"tone": tone, "words": ". ".join(parts)}


## The engine's settlement of the tile's draw: {own, network, grid, sold, spare} in MW. Your plants here that
## run first for you cover the tile's draw first; what is left came over the cables from your other tiles or
## from the grid (Power's per-tile import, settled in _mark_network_supply), so own + network + grid is the
## drawn figure. `sold` went straight to the grid, `spare` is what your plants here had left over.
static func grid_split(tile: String, made: int, drawn: int) -> Dictionary:
	var sold := int(Power.tile_produced_grid_priority.get(tile, 0))
	var own_made := maxi(0, made - sold)
	var own := mini(own_made, drawn)
	var rest := drawn - own
	var from_grid := 0 if Power.is_self_supplied(tile) else rest
	var settled: Variant = Power.get("_tile_grid_draw")
	if settled is Dictionary and (settled as Dictionary).has(tile):
		from_grid = clampi(int((settled as Dictionary)[tile]), 0, rest)
	return {"own": own, "network": rest - from_grid, "grid": from_grid, "sold": sold, "spare": own_made - own}


## "a", "a and b", "a, b and c".
static func _and(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + items[items.size() - 1]


## Your buildings here that make or draw power, by name: with no cables none of them can run (Power:
## cables are needed to draw or to make).
static func _needs_cables(tile: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if not BuildingState.is_player_owned(b):
			continue
		var rid := str(b.get("recipe_id", ""))
		var recipe: Dictionary = Catalog.get_recipe(rid)
		if int(recipe.get("energy_req", 0)) > 0 or str(recipe.get("output_name", "")) == "power":
			out.append(BuildingNaming.label_for_tile(tile, str(b.get("instance_id", "")), str(b.get("building_id", "")), rid))
	return out


# ── The balance's readouts ──────────────────────────────────────────────────────────────────────────────

static func _cables_row(panel: Control, tile: String, power: Dictionary) -> Control:
	var r := cables_reading(tile, power)
	var key: Control = null
	match str(r.key):
		"add":
			key = _key("Add cables", "PowerCablesKey", "Cables are laid in Transport")
		"upgrade":
			key = _key("Transport", "PowerCablesKey", "Upgrade the cables in Transport")
	if key != null:
		key.pressed.connect(func() -> void: panel.call("_select_tab", "transport"))
	return _readout("diag_icon_cable", str(r.tone), "Cables", str(r.words), key)


static func _grid_row(panel: Control, tile: String, power: Dictionary) -> Control:
	var r := grid_reading(tile, power)
	var map := _key("Power map", "PowerMapKey", "Show where power is made, drawn and short on the map")
	map.pressed.connect(func() -> void: panel.call("_on_power_goto"))
	return _readout("bar_icon_power", str(r.tone), "National grid", str(r.words), map)


## On an idle tile: your power plants here, none of which made power last turn, and Build power.
static func _plants_row(tile: String, build: Control) -> Control:
	var plants := _plant_count(tile)
	var words := "None of yours here"
	if plants == 1:
		words = "Yours here made no power last turn"
	elif plants > 1:
		words = "Your %d here made no power last turn" % plants
	return _readout("diag_icon_power_supply", "off", "Power plants", words, build)


## The made bar's note when it is empty: whether you have a plant here at all.
static func _plants_note(tile: String) -> String:
	var plants := _plant_count(tile)
	if plants == 0:
		return "No plant of yours here"
	return "Your plant here made nothing" if plants == 1 else "Your %d plants here made nothing" % plants


static func _plant_count(tile: String) -> int:
	var plants := 0
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if BuildingState.is_player_owned(b) \
				and str(Catalog.get_recipe(str(b.get("recipe_id", ""))).get("output_name", "")) == "power":
			plants += 1
	return plants


## The tile touches green power: it made or drew some, holds batteries, or had buildings cut short.
static func _touches_green(im: Dictionary) -> bool:
	if im.is_empty():
		return false
	return int(im.get("green_produced", 0)) > 0 or float(im.get("green_consumed", 0.0)) >= 0.5 \
		or int(im.get("battery_cap", 0)) > 0 or not (im.get("affected", []) as Array).is_empty()


# ── Cut short ───────────────────────────────────────────────────────────────────────────────────────────

## The buildings cut short in lulls: the verdict on a glass readout with Reduce intermittency beside it,
## then each building as a module fed from the cable, biggest first, under one OUTPUT CUT caption, with the
## ledger's key in the heading.
static func _cut_short(panel: Control, tile: String, im: Dictionary) -> Control:
	var affected: Array = im.get("affected", [])
	var ledger := _key("Show in ledger", "PowerAffectedKey",
		"Every building of yours cut short by intermittency, in the Building Ledger", CASE_KEY_W)
	ledger.pressed.connect(func() -> void: MatchState.building_ledger_filter_requested.emit("green_intermittent"))
	var sec := _section("PowerIntermittency", "plastic", "Cut short in lulls", [ledger])
	var body: VBoxContainer = sec.get("content")
	body.add_theme_constant_override("separation", 12)
	body.add_child(_verdict(panel, tile, im))
	var shown := mini(AFFECTED_SHOWN, affected.size())
	var readings: Array = []
	var digits := 1
	for i in shown:
		var r := cut_reading(affected[i])
		readings.append(r)
		digits = maxi(digits, Led.cells_for(str(int(r.cut))).size())
	var rack_col := VBoxContainer.new()
	rack_col.name = "CutShortRack"
	rack_col.add_theme_constant_override("separation", 2)
	rack_col.add_child(_cut_caption())
	var rack := PanelContainer.new()
	rack.name = "CutShort"
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = GUTTER
	bare.content_margin_top = 2
	bare.content_margin_bottom = 2
	rack.add_theme_stylebox_override("panel", bare)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	rack.add_child(list)
	# The cable after the modules, so its taps' glands sit over the modules' ends.
	var cable: Control = Cable.new()
	cable.set("centre_x", CABLE_X - GUTTER)
	rack.add_child(cable)
	var modules: Array[Control] = []
	for i in shown:
		var module := _affected_module(tile, affected[i], readings[i], digits)
		list.add_child(module)
		modules.append(module)
	cable.set("taps", modules)
	rack_col.add_child(rack)
	body.add_child(rack_col)
	if affected.size() > AFFECTED_SHOWN:
		body.add_child(_text("%d more in the ledger" % (affected.size() - AFFECTED_SHOWN)))
	return sec


## The verdict: Building Detail's diagnostics readout (a glass screen, its lamp inside), and Reduce
## intermittency beside it when battery storage here would help: Construct on this tile, searched to Battery.
static func _verdict(panel: Control, tile: String, im: Dictionary) -> Control:
	var r := lull_reading(tile, im)
	var row := HBoxContainer.new()
	row.name = "Verdict"
	row.add_theme_constant_override("separation", 12)
	var screen: Control = Readout.new()
	screen.name = "VerdictScreen"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.call("show_check", "", "Wind and solar", str(r.words), str(r.tone))
	screen.tooltip_text = lamp_rule()
	row.add_child(screen)
	if str(r.fix) == "reduce":
		var key := _key("Reduce intermittency", "PowerReduceKey",
			"Build battery storage on this tile, in Construct, to back up wind and solar in lulls", CASE_KEY_W)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.pressed.connect(func() -> void: _open_construct(panel, "Battery"))
		row.add_child(key)
	return row


## The modules' one caption, printed on the case over their output cut column: the room right of it is a
## module's Go to key, its gap and its padding, so the caption stands over the LEDs.
static func _cut_caption() -> Control:
	var row := HBoxContainer.new()
	row.name = "CutCaption"
	row.add_theme_constant_override("separation", 0)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var cap := _caption("Output cut")
	cap.custom_minimum_size.x = CUT_W
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.tooltip_text = "The share of its output each building lost last turn. %s" % lamp_rule()
	row.add_child(cap)
	var tail := Control.new()
	tail.custom_minimum_size.x = MODULE_SEP + roundf(SmallKey.control_side(SmallKey.DEFAULT_KEY_PX)) + MODULE_PAD_R
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tail)
	return row


## One building cut short, in two lines: its lamp, its name and how much of its draw had no backup, its
## output cut on an LED in the lamp's colour, and a key that takes you to it on the map (the cabinet's own
## Location key, at its size). The lamp and the words come from its reading.
static func _affected_module(tile: String, a: Dictionary, r: Dictionary, digits: int) -> Control:
	var iid := str(a.get("iid", ""))
	var live := BuildingState.get_building(iid)
	var bid := str(a.get("building_id", ""))
	var module := _module()
	module.name = "CutShort_%s" % iid
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MODULE_SEP)
	module.add_child(row)
	var lamp: Control = Lamp.new()
	lamp.name = "Lamp"
	lamp.set("lamp_scale", LAMP_SCALE)
	lamp.call("set_tone", str(r.tone))
	row.add_child(lamp)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	var full_name := BuildingNaming.label_for_tile(tile, iid, bid, str(live.get("recipe_id", "")))
	var title := _text(full_name, true)
	title.name = "Title"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	col.add_child(title)
	var words := _text(str(r.words))
	words.name = "Words"
	words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.clip_text = true
	col.add_child(words)
	row.add_child(col)
	# The name in full, what the words mean, and the rule the lamp follows, on hover anywhere on the module.
	module.tooltip_text = "%s. %s. Its output was cut %d%% last turn. %s" % [full_name, str(r.words), int(r.cut), lamp_rule()]
	module.mouse_filter = Control.MOUSE_FILTER_PASS
	# The output lost, on an LED in the lamp's colour, unsigned under the OUTPUT CUT caption.
	var fig := HBoxContainer.new()
	fig.name = "Cut"
	fig.custom_minimum_size.x = CUT_W
	fig.alignment = BoxContainer.ALIGNMENT_CENTER
	fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fig.add_theme_constant_override("separation", 3)
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fig.add_child(_led(str(int(r.cut)), DS.PALETTE.DANGER if str(r.tone) == "bad" else DS.PALETTE.WARN, digits))
	fig.add_child(_caption("%"))
	row.add_child(fig)
	var go: TextureButton = SmallKey.make("pin")
	go.name = "GoTo"
	go.tooltip_text = "Show it on the map"
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void: MatchState.focus_building_requested.emit(iid))
	row.add_child(go)
	return module


# ── Batteries ───────────────────────────────────────────────────────────────────────────────────────────

static func _has_bank(tile: String) -> bool:
	return Power.tile_battery_slots(tile) > 0 or Power.tile_battery_cells_loaded(tile) > 0 \
		or Power.battery_fill_turns_remaining(tile) > 0


static func _batteries(panel: Control, tile: String, im: Dictionary) -> Control:
	var sec := _section("PowerBatteries", "steel", "Batteries")
	var body: VBoxContainer = sec.get("content")
	body.add_theme_constant_override("separation", 12)
	var housing := Power.tile_battery_slots(tile)
	var loaded := Power.tile_firming_cap(tile)
	# The bank: how full the storage is, then the cells loaded, in MW of backup, of the MW it takes. What it
	# backed last turn is the readout under it, so the figure here is only ever what is loaded now.
	var bank_row := HBoxContainer.new()
	bank_row.name = "Bank"
	bank_row.add_theme_constant_override("separation", 8)
	bank_row.tooltip_text = "The cells loaded here give %d MW of backup for wind and solar, of the %d MW the storage takes" % [loaded, housing]
	bank_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var bank: Control = Bank.new()
	bank.call("set_charge", float(loaded) / float(housing) if housing > 0 else 0.0)
	bank.mouse_filter = Control.MOUSE_FILTER_PASS
	bank_row.add_child(bank)
	bank_row.add_child(_caption("Loaded"))
	var digits := maxi(Led.cells_for(str(loaded)).size(), Led.cells_for(str(housing)).size())
	var loaded_led := _led(str(loaded), DS.PALETTE.OK if loaded > 0 else DS.PALETTE.TEXT, digits)
	loaded_led.name = "LoadedFigure"
	bank_row.add_child(loaded_led)
	bank_row.add_child(_caption("of"))
	var housing_led := _led(str(housing), DS.PALETTE.TEXT, digits)
	housing_led.name = "HousingFigure"
	bank_row.add_child(housing_led)
	bank_row.add_child(_caption("MW"))
	body.add_child(bank_row)
	var r := bank_reading(tile, im)
	var last := _readout("", str(r.tone), "Last turn", str(r.words), null)
	last.name = "Readout_Bank"
	body.add_child(last)
	var locked: Array = []
	for internal: String in CHEMISTRIES:
		var gid := str(Catalog.get_good_by_internal_name(internal).get("id", ""))
		if Power.battery_type_loadable(gid):
			body.add_child(_cell_row(panel, tile, internal))
		else:
			locked.append(internal)
	if not locked.is_empty():
		body.add_child(_locked_line(locked))
	return sec


## Whether the storage here could take one more cell of a kind you have researched.
static func _housing_has_room(tile: String) -> bool:
	if Power.tile_battery_slots(tile) <= 0:
		return false
	for internal: String in CHEMISTRIES:
		var gid := str(Catalog.get_good_by_internal_name(internal).get("id", ""))
		if gid != "" and Power.battery_type_loadable(gid) and Power.battery_cells_to_fill(tile, gid) > 0:
			return true
	return false


## Your battery storage building here, whose own panel orders cells from the market or your other tiles.
static func _storage_building(tile: String) -> String:
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if BuildingState.is_player_owned(b) and str(Catalog.get_building(str(b.get("building_id", ""))).get("category", "")) == "battery":
			return str(b.get("instance_id", ""))
	return ""


## The kinds of cell still to research, in one line; its tooltip names each research.
static func _locked_line(locked: Array) -> Control:
	var names: PackedStringArray = []
	var tips: PackedStringArray = []
	for internal: String in locked:
		var full := str(Catalog.get_good_by_internal_name(internal).get("display_name", internal))
		var research := str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(internal, ""))
		names.append(full.trim_suffix(" Battery"))
		tips.append("%s needs %s research" % [full, research] if research != "" else "%s is not available yet" % full)
	var words := "%s cells need research" % _and(names)
	if locked.size() == 1:
		var research := str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(locked[0], ""))
		if research != "":
			words = "%s cells need %s research" % [names[0], research]
	var line := _text(words)
	line.name = "LockedCells"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.tooltip_text = ". ".join(tips)
	return line


## One kind of cell: its icon set in a well, its name and stock, how many are loaded on a drum counter, and
## its keys. Load puts the cells in stock here into the storage; with none in stock and room for them, Order
## opens the storage's own panel to buy them instead; Unload takes them back into stock.
static func _cell_row(panel: Control, tile: String, internal: String) -> Control:
	var good: Dictionary = Catalog.get_good_by_internal_name(internal)
	var gid := str(good.get("id", ""))
	var gname := str(good.get("display_name", internal))
	var row := HBoxContainer.new()
	row.name = "Cells_%s" % internal
	row.add_theme_constant_override("separation", 12)
	row.add_child(_good_in_well(gid, internal, CELL_ICON_PX))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.add_child(_text(gname, true))
	var loaded := int(Power.get_tile_battery_cells(tile).get(gid, 0))
	var stock := Stockpile.get_at_tile(tile, gid)
	col.add_child(_text("%d in stock here" % stock))
	row.add_child(col)
	var meta := "tvp_power_cells_%s" % gid
	var count_col := VBoxContainer.new()
	count_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_col.add_theme_constant_override("separation", 2)
	var count_cap := _caption("Cells")
	count_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_col.add_child(count_cap)
	var counter: Control = Counter.new()
	counter.call("configure", Counter.drums_for(float(loaded), 0, 3), 0)
	counter.call("set_value", float(loaded), float(panel.get_meta(meta)) if panel.has_meta(meta) else NAN)
	panel.set_meta(meta, loaded)
	counter.tooltip_text = "%s cells loaded into the storage" % gname
	counter.mouse_filter = Control.MOUSE_FILTER_PASS
	counter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	count_col.add_child(counter)
	row.add_child(count_col)
	var room := Power.battery_cells_to_fill(tile, gid) > 0
	var storage := _storage_building(tile)
	var first: Control
	if stock <= 0 and room and storage != "":
		first = _key("Order", "Order_%s" % internal, "Order %s cells in your battery storage's own panel" % gname.to_lower(), 84.0)
		first.pressed.connect(func() -> void: panel.call("_open_building_or_construction", storage))
	else:
		first = _key("Load", "Load_%s" % internal, "Load the %s cells in stock here" % gname.to_lower(), 84.0)
		if stock > 0 and room:
			first.pressed.connect(func() -> void:
				Power.load_battery_cells(tile, gid, stock)
				panel.call("_refresh_pane", "power"))
		else:
			first.set("disabled", true)
			var free_mw := float(Power.tile_battery_slots(tile)) - Power.tile_loaded_firming(tile)
			first.tooltip_text = "No %s cells in stock here" % gname.to_lower() if stock <= 0 \
				else ("The storage is full" if free_mw <= 0.0 else "Too little room left for a %s cell" % gname.to_lower())
	first.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(first)
	var unload := _key("Unload", "Unload_%s" % internal, "Take the %s cells out, back into stock" % gname.to_lower(), 96.0)
	unload.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if loaded <= 0:
		unload.set("disabled", true)
		unload.tooltip_text = "No %s cells loaded" % gname.to_lower()
	else:
		unload.pressed.connect(func() -> void:
			Power.unload_battery_cells(tile, gid, loaded)
			panel.call("_refresh_pane", "power"))
	row.add_child(unload)
	return row


# ── Parts ───────────────────────────────────────────────────────────────────────────────────────────────

## A framed section with its heading in raised letters: "steel" (the frame over the sheet), "dark" (a dark
## instrument plate in the frame) or "plastic" (the diagnostics' case). `trailing` controls stand at the
## right end of the heading's line, as Building Detail's diagnostics set their switch.
static func _section(node_name: String, style: String, heading: String, trailing: Array = []) -> MarginContainer:
	var sec: MarginContainer = Section.new()
	sec.name = node_name
	sec.set("style", style)
	var body: VBoxContainer = sec.get("content")
	var head: Control
	if Heading.can_show(heading):
		var h: Control = Heading.new()
		h.set("text", heading)
		h.name = "Heading"
		head = h
	else:
		head = _caption(heading)
	if trailing.is_empty():
		body.add_child(head)
		return sec
	var row := HBoxContainer.new()
	row.name = "HeadingRow"
	row.add_theme_constant_override("separation", 10)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	for c: Control in trailing:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(c)
	body.add_child(row)
	return sec


## Words in white on the dark metal: body 14 px IBM Plex Sans Medium, or semibold for a row's own title,
## with a dark shadow so they stand off the plate.
static func _text(text: String, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI if title else UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", BODY_PX)
	_emboss(l)
	return l


## A metal label: Barlow Condensed SemiBold 15 px in capitals.
static func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_emboss(l)
	return l


static func _emboss(l: Label) -> void:
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_PASS


## A figure on an LED screen, padded to `digits` cells so a group's screens are one width.
static func _led(text: String, ink: Color, digits: int) -> Control:
	var led: Control = Led.new()
	led.call("set_figure", " ".repeat(maxi(0, digits - Led.cells_for(text).size())) + text, ink)
	return led


## A lamp's reading: the raised icon (none for ""), its lamp, its name in a metal label and a line of words
## under it, and the key that acts on it at the end, in the plate's column of keys.
static func _readout(icon: String, tone: String, caption: String, words: String, key: Control) -> Control:
	var row := HBoxContainer.new()
	row.name = "Readout_%s" % caption.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	if icon != "":
		row.add_child(_raised(icon, ICON_PX))
	var lamp: Control = Lamp.new()
	lamp.name = "Lamp"
	lamp.set("lamp_scale", LAMP_SCALE)
	lamp.call("set_tone", tone)
	row.add_child(lamp)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.add_child(_caption(caption))
	var w := _text(words)
	w.name = "Words"
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(w)
	row.add_child(col)
	if key != null:
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(key)
	return row


## A raised icon from the renders (its shadow under it), sized by its art, not its frame, standing on the
## foot of a `px` box.
static func _raised(layer: String, px: float) -> Control:
	var face := Plate.tex(layer)
	var shadow: Texture2D = Plate.tex(layer + "_shadow") if ResourceLoader.exists(DIR + layer + "_shadow.png") else null
	var c := Control.new()
	c.name = "Icon_" + layer
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		if face == null:
			return
		var art := Indicator.art_rect(face)
		var k := px / maxf(art.size.x, art.size.y)
		var art_size := art.size * k
		var at := Vector2((c.size.x - art_size.x) * 0.5, (c.size.y - px) * 0.5 + px - art_size.y)
		var rect := Rect2(at - art.position * k, face.get_size() * k)
		if shadow != null:
			c.draw_texture_rect(shadow, rect, false)
		c.draw_texture_rect(face, rect, false))
	return c


## A cabinet key (the fixed part's cream key), its name printed on it, `width` wide.
static func _key(text: String, node_name: String, tip: String, width := KEY_W) -> Control:
	var key: Control = CabinetKey.new()
	key.name = node_name
	key.set("text", text)
	key.tooltip_text = tip
	key.custom_minimum_size.x = width
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	return key


## A faint engraved line across a plate.
static func _rule() -> Control:
	var r := Control.new()
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(func() -> void:
		r.draw_line(Vector2(0, 0.5), Vector2(r.size.x, 0.5), Color(0, 0, 0, 0.55), 1.0)
		r.draw_line(Vector2(0, 1.5), Vector2(r.size.x, 1.5), Color(1, 1, 1, 0.08), 1.0))
	return r


## Building Detail's raised black module, set in a case.
static func _module() -> PanelContainer:
	var module := PanelContainer.new()
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 12
	pad.content_margin_right = MODULE_PAD_R
	pad.content_margin_top = 8
	pad.content_margin_bottom = 8
	module.add_theme_stylebox_override("panel", pad)
	module.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	module.draw.connect(func() -> void:
		Nine.paint(module, MODULE, Rect2(Vector2.ZERO, module.size).grow(MODULE_MARGIN), MODULE_CORNER))
	return module


## A good's cream tile set into a thin gunmetal well, as Building Detail sets a good standing alone.
static func _good_in_well(gid: String, internal: String, px: int) -> Control:
	var icon := UIHelpers.make_plain_good_icon(gid, internal, px)
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	icon.add_child(well)
	icon.move_child(well, mini(2, icon.get_child_count() - 1))
	return icon
