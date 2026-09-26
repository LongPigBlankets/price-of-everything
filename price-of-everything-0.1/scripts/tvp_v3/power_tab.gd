extends RefCounted
## Tile view v3: the Power tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## The site's meter panel, top to bottom:
##   - POWER BALANCE, a dark instrument plate. While your buildings here produced or consumed power last
##     turn, the meter (power_meter.gd): produced over consumed as two bars on one scale, a slice for each
##     kind of building, the MW in white on dot matrix screens and the net under them, and Build power
##     standing over the PRODUCED figure it adds to (Construct, locked to this tile, on its power buildings).
##     Under it, lamp readouts, each a raised icon, a lamp, a name and a line of words, with the one key that
##     acts on it in a column down the plate's right: the cables (how much of their capacity is used,
##     Upgrade while near their cap), the national grid while the tile is linked (one sentence in the
##     owner's words on what was produced and consumed and what the grid bought or supplied, the power map),
##     and intermittency (how much of the power is wind and solar, how much of it is firmed, on a lamp that
##     flashes between two tones where the owner's rule asks). On an idle tile the meter gives way to two
##     readouts: the cables (the owner's "Cables missing." words and Build, when your buildings here need
##     them), and your power plants here (Build power).
##   - CUT SHORT IN LULLS, the diagnostics' plastic case, while any of your buildings here ran short when
##     the wind or sun fell: the verdict on a glass readout (how much of the consumption was unfirmed) with
##     Reduce intermittency beside it while the tile has no battery storage or it is full, then each
##     building cut short as a module fed from the cable, two lines (its name, then how much of its
##     consumption was unfirmed), its output cut on a dot matrix screen under one OUTPUT CUT caption, and
##     its Go to key. The ledger's key stands in the heading. One rule lights every lamp here, the engine's
##     own cut (EconomyConfig.INTERMITTENCY_DERATE): a building is red when it lost the full cut, amber when
##     it lost less, and the verdict is red when any building here lost the full cut.
##   - BATTERIES, where the tile has battery storage: the bank (the cells loaded, in MW of firming, of the
##     MW the storage takes), what the bank firmed last turn on a lamp readout, and each kind of cell with
##     its stock here on the quantity pill in its icon's corner, how many are loaded, and its keys: Load (or
##     Order, with none in stock here) and Unload.
## Each lamp and the words beside it come from one reading (the *_reading helpers). The grid's lamp takes
## the tone the Power key takes from TileViewData.power_summary, and the cables' lamp the key's red for
## missing cables, so the tab and its key agree. Every figure is the engine's: Power's per-tile MW, cable
## cap, cable networks and settlement, Production's per-plant dispatch, power source attribution and
## intermittency roll-up (what each building and the bank settled last turn), the battery storage's cells.
## Money would stay on the seven segment LED; every other figure on a screen is a dot matrix in white (DS2).
## Copy: every line of words under a name or caption is a sentence with a full stop, as are tooltips; names,
## captions, key labels and the notes printed on the plate in capitals take none. Building names are the
## game's without its hyphens (plain_name).

const Metrics := preload("res://scripts/ds2/metrics.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const FlashLamp := preload("res://scripts/ds2/flash_lamp.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
const CabinetKey := preload("res://scripts/ds2/latch_key.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Cable := preload("res://scripts/bdp_v3_cable.gd")
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
## Every key on the balance plate is one width, so they stand in one column down its right; the cut short
## case's keys are wider, to print Reduce intermittency at the caption size; a cell's two keys share one.
const KEY_W := 140.0
const CASE_KEY_W := 176.0
const CELL_KEY_W := 96.0
## The dot matrix screens' pitch, the tab keys' display's, so every dot on the panel is one size.
const DOT_PITCH := 2.6
## One flash of an intermittency lamp: the whole cycle, in seconds (owner's rule).
const FLASH_CYCLE := 1.5
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
## A module's output cut: the column its screen stands in, under the one OUTPUT CUT caption.
const CUT_W := 84.0
## A module's inner padding (right) and the room between its parts.
const MODULE_PAD_R := 10.0
const MODULE_SEP := 12.0
## The battery cells, in the order the storage lists them.
const CHEMISTRIES := ["lithium_battery", "sodium_battery", "iron_battery"]
const CELL_ICON_PX := Metrics.GOOD_ICON
## Building Detail's navy quantity pill: its height and how far inside the icon's corner it sits.
const PILL_H := 22
const PILL_INSET := 5
## A cable run this full of its cap is near its limit.
const NEAR_CAP := 0.9
## How far in the plastic case stands on each side, so its edges line up with the steel frames' rims.
const PLASTIC_INSET := 2
const DIR := "res://assets/ui/bdp_v3/"


static func build(panel: Control, pane: VBoxContainer) -> void:
	var tile := str(panel.get("_current_tile_id"))
	pane.add_theme_constant_override("separation", SECTION_GAP)
	var power := TileViewData.power_summary(tile)
	var im: Dictionary = Production.get_tile_intermittency(tile)
	pane.add_child(_balance(panel, tile, power, im))
	if not (im.get("affected", []) as Array).is_empty():
		pane.add_child(_inset(_cut_short(panel, tile, im)))
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
	var build := _key("Build power", "PowerBuildKey", "Build a power plant or battery storage on this tile, in Construct.")
	build.pressed.connect(func() -> void: _open_construct(panel, ""))
	var made := int(power.produced)
	var drawn := int(power.consumed)
	var idle := made == 0 and drawn == 0
	var rows := VBoxContainer.new()
	rows.name = "Readouts"
	rows.add_theme_constant_override("separation", 10)
	if idle:
		_add_link_rows(rows, panel, tile, power)
		rows.add_child(_plants_row(tile, build))
	else:
		var meter: Control = Meter.new()
		meter.set("on_open", func(iid: String) -> void: panel.call("_open_building_or_construction", iid))
		meter.call("set_key", build)
		meter.set("notes", [_plants_note(tile) if made == 0 else "", "None of your buildings here consumed power" if drawn == 0 else ""])
		# The figures in white; the net carries the Power key's amber or red mark when it shows one.
		meter.call("set_reading", _makers(tile), _users(tile), made, drawn, int(power.net), status_tone(str(power.status)))
		body.add_child(meter)
		body.add_child(_rule())
		_add_link_rows(rows, panel, tile, power)
	if bool(power.get("connected", false)):
		rows.add_child(_grid_row(panel, tile, power))
		if not idle:
			rows.add_child(_intermittency_row(tile, power, im))
	body.add_child(rows)
	return sec


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
		kinds[key] = {"name": plain_name(tile, iid, bid, rid), "value": 0.0, "count": 0,
			"iid": iid, "building_id": bid, "kind": _kind_name(bid, rid), "short": _short_name(bid, rid)}
		order.append(key)
	var k: Dictionary = kinds[key]
	k.value = float(k.value) + mw
	k.count = int(k.count) + 1
	if int(k.count) > 1:
		k.name = str(k.kind)


## A kind of building by the game's naming, less the letter that tells one from another and the hyphens
## (plain_name's form): "Industrial Goods Factory Steel", "Solar Farm".
static func _kind_name(bid: String, rid: String) -> String:
	var parts := BuildingNaming.without_letter(BuildingNaming.label(bid, rid, 0)).split(" - ")
	if parts.size() == 2 and str(Catalog.get_recipe(rid).get("output_name", "")) == "power":
		parts.remove_at(1)
	return " ".join(parts)


## The name a meter's tag prints: what a building makes (Steel, Motor), or for a power plant, the plant
## (Solar Farm), since they all make power.
static func _short_name(bid: String, rid: String) -> String:
	var recipe: Dictionary = Catalog.get_recipe(rid)
	var out := str(recipe.get("output_name", ""))
	if out != "" and out != "power":
		return str(Catalog.get_good_by_internal_name(out).get("display_name", out))
	return str(Catalog.get_building(bid).get("display_name", bid))


# ── Readings: each lamp's tone and the words that explain it, from one place ─────────────────────────────

## The cables: {tone, words, key}, key "build" (none here and yours need them), "upgrade" (near or at their
## cap with a level left) or "". Their load is the larger of the power produced and consumed here, against
## their cap: green below 90% of it, amber from there, red at it. With none here and your buildings needing
## them, the owner's words and a red lamp, both the Power key's (tile_info_panel_v2.cables_missing_text);
## with none needed, the lamp is off, as the key's is.
static func cables_reading(tile: String, power: Dictionary) -> Dictionary:
	var cap := Power.tile_power_cap(tile)
	if cap <= 0:
		var missing := cables_missing(tile)
		if missing == "":
			return {"tone": "off", "key": "", "words": "No cables here."}
		return {"tone": "bad", "key": "build", "words": missing}
	var load := maxi(int(power.produced), int(power.consumed))
	var share := float(load) / float(cap)
	var words := "Level %d, %d/%d MW capacity used." % [Power.cable_level(tile), load, cap]
	var key := "" if Power.cable_level_is_max(tile) else "upgrade"
	if share >= 1.0:
		return {"tone": "bad", "key": key, "words": words}
	if share >= NEAR_CAP:
		return {"tone": "warn", "key": key, "words": words}
	return {"tone": "ok", "key": "", "words": words}


## The owner's words for a tile with no cables where your buildings produce or consume power ("Cables
## missing. Power consumption not possible."), from the tile view's own helper, which the Power key's mark
## reads too; "" when the tile has cables or nothing of yours needs them.
static func cables_missing(tile: String) -> String:
	var tv: Script = load("res://scripts/tile_info_panel_v2.gd")
	return str(tv.call("cables_missing_text", tile)) if tv != null else ""


## The national grid, while the tile is linked: {tone, words, tip}. What the tile sold to the national grid
## and what it bought from it last turn, a line each, both when it did both (a plant here selling while your
## buildings here buy, as intermittent power is sold): "228 MW sold to the national grid." and "170 MW bought
## from the national grid.". With neither, one line says so. The lamp is the Power key's (amber when the tile
## consumed more than it produced). Where every MW went and came from is its tooltip (grid_tip). Every figure
## is the engine's settlement (grid_split, spare_split).
static func grid_reading(tile: String, power: Dictionary) -> Dictionary:
	var made := int(power.produced)
	var drawn := int(power.consumed)
	if made == 0 and drawn == 0:
		return {"tone": "ok", "words": "Nothing produced or consumed here last turn.", "tip": ""}
	var tone := status_tone(str(power.status))
	var split := grid_split(tile, made, drawn)
	var flows := spare_split(tile, int(split.spare))
	var sold := int(split.sold) + int(flows.sold)
	var bought := int(split.grid)
	var lines: PackedStringArray = []
	if sold > 0:
		lines.append("%d MW sold to the national grid." % sold)
	if bought > 0:
		lines.append("%d MW bought from the national grid." % bought)
	if lines.is_empty():
		lines.append("Nothing sold to or bought from the national grid.")
	return {"tone": tone, "words": "\n".join(lines), "tip": grid_tip(made, drawn, split, flows)}


## Where the power produced here went and where the power consumed here came from, a line each, for the
## national grid row's tooltip.
static func grid_tip(made: int, drawn: int, split: Dictionary, flows: Dictionary) -> String:
	var lines: PackedStringArray = []
	if made > 0:
		lines.append("Produced here: %d MW." % made)
		for part: Array in [["Used here", int(split.own)], ["Used by your buildings on other tiles", int(flows.tiles)],
				["Sold to the national grid", int(split.sold) + int(flows.sold)]]:
			if int(part[1]) > 0:
				lines.append("%s: %d MW." % [part[0], int(part[1])])
	if drawn > 0:
		lines.append("Consumed here: %d MW." % drawn)
		for part: Array in [["From your plants here", int(split.own)], ["From your buildings on other tiles", int(split.network)],
				["From the national grid", int(split.grid)]]:
			if int(part[1]) > 0:
				lines.append("%s: %d MW." % [part[0], int(part[1])])
	lines.append("The lamp is amber when your buildings here consumed more than they produced.")
	return "\n".join(lines)


## Intermittency: {tone, cycle, words, side, intermittent, firmed}, from the engine's figures for the tile
## (intermittency_figures) through the owner's rule (intermittency_verdict).
static func intermittency_reading(tile: String, power: Dictionary, im: Dictionary) -> Dictionary:
	return intermittency_verdict(intermittency_figures(tile, power, im))


## The figures the intermittency row reads, both sides of the tile:
##   produced: made_int, every MW of wind and solar your plants here put on the wire (Production's per plant
##     dispatch); self_int, the part of it running first for you (the rest was sold straight to the grid,
##     which is never firmed); firmed_made, what the bank here firmed of self_int (the engine firms a tile's
##     own wind and solar first, Production._allocate_power_derates, producer side); used_made, whether
##     self_int reached your buildings (here, or over the cables to your other tiles).
##   consumed: drawn_int, the wind and solar your buildings here consumed (Production.get_power_sources, the
##     engine's attribution of each building's draw to the plants that made it, kept between what went
##     unfirmed and all the green they consumed); unfirmed_drawn, the part of it left unfirmed.
static func intermittency_figures(tile: String, power: Dictionary, im: Dictionary) -> Dictionary:
	var made := int(power.produced)
	var drawn := int(power.consumed)
	var made_int := intermittent_made(tile)
	var self_int := clampi(int(im.get("green_intermittent_produced", 0)), 0, made_int)
	var used := false
	if self_int > 0:
		var split := grid_split(tile, made, drawn)
		used = int(split.own) > 0 or int(spare_split(tile, int(split.spare)).tiles) > 0
	var unfirmed := float(im.get("unfirmed_consumed", 0.0))
	var drawn_int := 0.0
	if drawn > 0:
		drawn_int = clampf(intermittent_drawn(tile), unfirmed, maxf(unfirmed, float(im.get("green_consumed", 0.0))))
	return {"made": made, "drawn": drawn, "made_int": made_int, "self_int": self_int,
		"firmed_made": mini(int(im.get("battery_cap", 0)), self_int), "used_made": used,
		"drawn_int": drawn_int, "unfirmed_drawn": unfirmed}


## The owner's rule for the intermittency lamp, on each side the tile has, and the worse of the two shown:
##   steady green: all of it is firmed, or there is none;
##   flashing amber and green: intermittent, but what is not firmed was sold to the national grid (wind and
##     solar sold straight to the grid, or running first for you and reaching none of your buildings);
##   flashing amber and red: partly firmed, and your buildings use what is not;
##   steady red: none of it firmed, and your buildings use it.
## The produced side compares what was firmed with what ran first for you (self_int), never with what was
## sold straight to the grid. The consumed side is always used by your buildings. The words are the shown
## side's: "X MW (P% of power production) is intermittent." and, when any is firmed, "Q MW (R% of
## production) is firmed.", or the same of consumption. On a tie the produced side is shown. `cycle` holds
## the two tones of a flashing lamp, empty for a steady one. Pure: `f` is intermittency_figures' shape.
static func intermittency_verdict(f: Dictionary) -> Dictionary:
	var made := int(f.get("made", 0))
	var drawn := int(f.get("drawn", 0))
	var made_int := int(f.get("made_int", 0))
	var best := {}
	if made_int > 0:
		var self_int := clampi(int(f.get("self_int", 0)), 0, made_int)
		var firmed := clampi(int(f.get("firmed_made", 0)), 0, self_int)
		var left := self_int - firmed
		var sold := made_int - self_int
		var lamp: Array = ["ok"]
		if left <= 0 and sold > 0:
			lamp = ["warn", "ok"]
		elif left > 0 and not bool(f.get("used_made", false)):
			lamp = ["warn", "ok"]
		elif left > 0 and firmed > 0:
			lamp = ["warn", "bad"]
		elif left > 0:
			lamp = ["bad"]
		best = _side("made", "production", made_int, firmed, made, lamp)
	var drawn_int := float(f.get("drawn_int", 0.0))
	var shown := roundi(drawn_int)
	if shown > 0:
		var unfirmed := float(f.get("unfirmed_drawn", 0.0))
		var firmed_in := roundi(maxf(0.0, drawn_int - unfirmed))
		var lamp: Array = ["ok"]
		if unfirmed >= 0.5:
			lamp = ["warn", "bad"] if firmed_in > 0 else ["bad"]
		var side := _side("drawn", "consumption", shown, firmed_in, drawn, lamp)
		if best.is_empty() or _lamp_rank(side) > _lamp_rank(best):
			best = side
	if best.is_empty():
		return {"side": "none", "intermittent": 0, "firmed": 0, "tone": "ok", "cycle": [],
			"words": "None of the power here is intermittent."}
	return best


## One side's reading: its words and its lamp (one tone steady, two a flash).
static func _side(side: String, of: String, intermittent: int, firmed: int, whole: int, lamp: Array) -> Dictionary:
	var lines: PackedStringArray = ["%d MW (%d%% of power %s) is intermittent." % [intermittent, _pct(intermittent, whole), of]]
	if firmed > 0:
		lines.append("%d MW (%d%% of %s) is firmed." % [firmed, _pct(firmed, whole), of])
	return {"side": side, "intermittent": intermittent, "firmed": firmed, "words": "\n".join(lines),
		"tone": str(lamp[0]), "cycle": lamp if lamp.size() > 1 else []}


## How bad a lamp is, for picking the worse side: green, amber and green, amber and red, red.
static func _lamp_rank(r: Dictionary) -> int:
	var cycle: Array = r.get("cycle", [])
	if not cycle.is_empty():
		return 2 if cycle.has("bad") else 1
	return {"ok": 0, "warn": 1, "bad": 3}.get(str(r.get("tone", "ok")), 0) as int


## The intermittency lamp's rule, for its tooltip.
static func intermittency_rule() -> String:
	return "Green when all of it is firmed. Flashing amber and green when what is not firmed is sold to the national grid. " \
		+ "Flashing amber and red when it is partly firmed and your buildings use it. Red when none of it is firmed and your buildings use it."


## The wind and solar your plants here put on the wire last turn, in MW (Production's per-plant dispatch).
static func intermittent_made(tile: String) -> int:
	var total := 0
	var sources: Variant = Production.get("_power_sources_by_tile")
	var recorded: Array = (sources as Dictionary).get(tile, []) if sources is Dictionary else []
	for s: Dictionary in recorded:
		if str(s.get("quality", "")) == "green_intermittent":
			total += int(s.get("qty", 0))
	return total


## The wind and solar your buildings here drew last turn, in MW: each building's draw as the engine
## attributes it to the plants that made it (Production.get_power_sources), summed over the wind and solar
## plants among them.
static func intermittent_drawn(tile: String) -> float:
	var total := 0.0
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if not BuildingState.is_player_owned(b):
			continue
		var iid := str(b.get("instance_id", ""))
		if not bool(Production.last_turn_run.get(iid, false)):
			continue
		var from: Dictionary = Production.get_power_sources(iid).get("green_from", {})
		for src: String in from:
			var sb := BuildingState.get_building(src)
			var internal := str(Catalog.get_building(str(sb.get("building_id", ""))).get("internal_name", ""))
			if internal in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
				total += float(from[src])
	return total


## A share in whole percent, never 0% for a share above nothing.
static func _pct(part: float, whole: float) -> int:
	if whole <= 0.0 or part <= 0.0:
		return 0
	return clampi(roundi(part / whole * 100.0), 1, 100)


## The engine's cut at its fullest, in whole percent: a building whose whole draw was wind and solar with no
## backup loses EconomyConfig.INTERMITTENCY_DERATE of its output, one with part of it a share of that.
static func full_cut_pct() -> int:
	return roundi(EconomyConfig.INTERMITTENCY_DERATE * 100.0)


## Whether a building's cut (Production's derate) is the full one.
static func is_full_cut(derate: float) -> bool:
	return derate >= EconomyConfig.INTERMITTENCY_DERATE - 0.0005


## The one rule the cut short lamps follow, for their tooltips.
static func lamp_rule() -> String:
	return "Red when a building lost the full %d%% of its output, amber when it lost less." % full_cut_pct()


## The verdict on the buildings cut short: {tone, words, fix}. How much of the tile's consumption was wind and
## solar left unfirmed, then what the battery storage here can still do. Red when any building here lost the
## full cut (the modules' rule), amber otherwise. `fix` is "reduce" (build battery storage: there is none,
## or it is full) or "".
static func lull_reading(tile: String, im: Dictionary) -> Dictionary:
	var unbacked := roundi(float(im.get("unfirmed_consumed", 0.0)))
	var total := int(im.get("total_consumed", 0))
	var tone := "warn"
	for a: Dictionary in im.get("affected", []):
		if is_full_cut(float(Production.get_building_intermittency(str(a.get("iid", ""))).get("derate", 0.0))):
			tone = "bad"
	var words := "All %d MW consumed here was unfirmed." % total if unbacked >= total \
		else "%d of the %d MW consumed here was unfirmed." % [unbacked, total]
	var fix := ""
	if _housing_has_room(tile):
		words += " Your battery storage has room for more cells."
	elif Power.tile_battery_slots(tile) > 0:
		words += " Your battery storage is full."
		fix = "reduce"
	else:
		fix = "reduce"
	if not TileViewData.grid_has_intermittent():
		fix = ""
	return {"tone": tone, "words": words, "fix": fix}


## One building cut short: {tone, words, cut}, in one line under its name. Red when it lost the full cut (all
## its consumption was unfirmed wind and solar), amber when it lost less; `cut` is the share of its output
## lost, in whole percent. A partial cut never prints as the full one, nor its consumption as all of it.
static func cut_reading(a: Dictionary) -> Dictionary:
	var im := Production.get_building_intermittency(str(a.get("iid", "")))
	var demand := roundi(float(im.get("demand", a.get("power", 0))))
	var derate := float(im.get("derate", 0.0))
	if is_full_cut(derate):
		return {"tone": "bad", "cut": full_cut_pct(), "words": "All %d MW was unfirmed." % demand}
	var unbacked := clampi(roundi(float(im.get("unfirmed_intermittent", 0.0))), 1, maxi(1, demand - 1))
	var cut := clampi(roundi(derate * 100.0), 1, full_cut_pct() - 1)
	return {"tone": "warn", "cut": cut, "words": "%d of its %d MW was unfirmed." % [unbacked, demand]}


## What the battery bank here did last turn: {tone, words}, in the intermittency readout's word, firmed, one
## fact a line (what it firmed, whether every cell was in use, what it firms from next turn, cells to come). The
## engine spends a tile's firming on the wind and solar produced there first (Production._allocate_power_derates,
## producer side), then on wind and solar its buildings consumed from elsewhere, so while any consumption here
## went unfirmed the bank firmed all it held (im.battery_cap, what its cells held when the turn settled). Amber
## when every cell was in use and a building here was still cut short, green when it firmed what it could
## reach and nothing here was cut, off when there was nothing to firm. Cells loaded or taken out since count
## from next turn, said with the figure they will give.
static func bank_reading(tile: String, im: Dictionary) -> Dictionary:
	var coming := Power.battery_fill_turns_remaining(tile)
	var arriving := "More cells arrive in %d %s." % [coming, "turn" if coming == 1 else "turns"]
	if im.is_empty():
		var idle := "No wind or solar here last turn."
		return {"tone": "off", "words": idle + ("\n" + arriving if coming > 0 else "")}
	var held := int(im.get("battery_cap", 0))
	var made := int(im.get("green_intermittent_produced", 0))
	var unbacked := float(im.get("unfirmed_consumed", 0.0)) >= 0.5
	var cut := not (im.get("affected", []) as Array).is_empty()
	var drew := float(im.get("green_consumed", 0.0)) >= 0.5
	var now := Power.tile_firming_cap(tile)
	var tone := "off"
	var words := ""
	if held <= 0:
		words = "No cells were loaded."
	elif made >= held:
		tone = "warn" if cut else "ok"
		words = "Firmed %d of the %d MW of wind and solar produced here.\nEvery cell was in use." % [held, made]
	elif unbacked:
		tone = "warn" if cut else "ok"
		words = "Firmed %d MW of wind and solar consumed here.\nEvery cell was in use." % held if made <= 0 \
			else "Firmed all %d MW of wind and solar produced here and %d MW from other tiles.\nEvery cell was in use." % [made, held - made]
	elif made > 0:
		# What that did for the buildings here is the balance's intermittency readout.
		tone = "ok"
		words = "Firmed all %d MW of wind and solar produced here." % made
	elif drew:
		tone = "ok"
		words = "Nothing consumed here was unfirmed."
	else:
		words = "No wind or solar here to firm."
	var parts: PackedStringArray = [words]
	if now != held:
		parts.append("From next turn it firms up to %d MW." % now)
	if coming > 0:
		parts.append(arriving)
	return {"tone": tone, "words": "\n".join(parts)}


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


## Where the tile's spare went: {tiles, sold} in MW. The engine settles each cable network on its own
## (Power.settle_grid_transactions): the spare of every tile on it goes into one pool that covers the
## network's other tiles' draw first, and the rest of the pool is sold to the grid. The pool does not say
## whose spare covered what, so this tile's is split in the pool's own proportion.
static func spare_split(tile: String, spare: int) -> Dictionary:
	if spare <= 0:
		return {"tiles": 0, "sold": 0}
	var cabled: Variant = Power.call("_cabled_tile_set") if Power.has_method("_cabled_tile_set") else {}
	if not (cabled is Dictionary) or not (cabled as Dictionary).has(tile) or not Power.has_method("_cable_component"):
		return {"tiles": 0, "sold": spare}
	var network: Array = Power.call("_cable_component", tile, cabled, {})
	var pool := 0
	var short := 0
	for t: String in network:
		var g := int(Power.tile_produced.get(t, 0)) - int(Power.tile_produced_grid_priority.get(t, 0))
		var d := int(Power.tile_drawn.get(t, 0))
		var covered := mini(g, d)
		pool += g - covered
		short += d - covered
	if pool <= 0:
		return {"tiles": 0, "sold": spare}
	var tiles := clampi(roundi(float(spare) * float(mini(pool, short)) / float(pool)), 0, spare)
	return {"tiles": tiles, "sold": spare - tiles}


## "a", "a and b", "a, b and c".
static func _and(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + items[items.size() - 1]


## A building's name as the game gives it on this tile, without the game's separating hyphens (the owner's
## copy rule): its kind, what it makes (unless that is power, which every plant makes) and its letter,
## "Industrial Goods Factory Steel D", "Solar Farm A".
static func plain_name(tile: String, iid: String, bid: String, rid: String) -> String:
	var parts := BuildingNaming.label_for_tile(tile, iid, bid, rid).split(" - ")
	if parts.size() == 3 and str(Catalog.get_recipe(rid).get("output_name", "")) == "power":
		parts.remove_at(1)
	return " ".join(parts)


# ── The balance's readouts ──────────────────────────────────────────────────────────────────────────────

## The links that carry power, as the owner ruled: they live in Transport, and show here only where they are
## built, the cables also where they are missing and your buildings here need them ("Cables missing").
static func _add_link_rows(rows: Control, panel: Control, tile: String, power: Dictionary) -> void:
	if Power.tile_power_cap(tile) > 0 or cables_missing(tile) != "":
		rows.add_child(_cables_row(panel, tile, power))
	var hvdc := _built_link(tile, panel.get("_current_tile_data"), "hvdc")
	if not hvdc.is_empty():
		var key := _key("Upgrade", "PowerHvdcKey", "Upgrade the HVDC link on this tile, in Transport.")
		key.pressed.connect(func() -> void: panel.call("_select_tab", "transport"))
		rows.add_child(_readout("diag_icon_cable", "ok", "HVDC", "Level %d." % int(hvdc.get("level", 1)), key))


## A built link's slot from TileViewData.infrastructure_summary, or {} where it isn't built.
static func _built_link(tile: String, tile_data: Dictionary, key: String) -> Dictionary:
	var data: Dictionary = {}
	for slot: Dictionary in TileViewData.infrastructure_summary(tile, tile_data):
		if str(slot.get("key", "")) == key and str(slot.get("state", "")) == "exists":
			data = slot
	return data


## The cables, and the Transport tab's own key words for them: Build where there are none and your
## buildings need them, Upgrade near or at their cap. Both open Transport, where the cables are laid and
## upgraded, with what it costs.
static func _cables_row(panel: Control, tile: String, power: Dictionary) -> Control:
	var r := cables_reading(tile, power)
	var key: Control = null
	match str(r.key):
		"build":
			key = _key("Build", "PowerCablesKey", "Build cables on this tile, in Transport.")
		"upgrade":
			key = _key("Upgrade", "PowerCablesKey", "Upgrade the cables on this tile, in Transport.")
	if key != null:
		key.pressed.connect(func() -> void: panel.call("_select_tab", "transport"))
	var row := _readout("diag_icon_cable", str(r.tone), "Cables", str(r.words), key)
	if str(r.words) == "No cables here.":
		row.tooltip_text = "Power plants and factories need cables to run."
	return row


static func _grid_row(panel: Control, tile: String, power: Dictionary) -> Control:
	var r := grid_reading(tile, power)
	var map := _key("Power map", "PowerMapKey", "Show where power is produced, consumed and short on the map.")
	map.pressed.connect(func() -> void: panel.call("_on_power_goto"))
	var row := _readout("bar_icon_power", str(r.tone), "National grid", str(r.words), map)
	row.tooltip_text = str(r.get("tip", ""))
	return row


## Intermittency, under the national grid: how much of the power is wind and solar and how much of it is
## firmed, on a lamp that flashes between two tones where the reading gives a cycle.
static func _intermittency_row(tile: String, power: Dictionary, im: Dictionary) -> Control:
	var r := intermittency_reading(tile, power, im)
	var lamp: Control = FlashLamp.new()
	lamp.name = "Lamp"
	lamp.set("lamp_scale", LAMP_SCALE)
	var cycle: Array = r.cycle
	if cycle.is_empty():
		lamp.call("set_tone", str(r.tone))
	else:
		lamp.call("set_cycle", cycle, FLASH_CYCLE)
	var row := _readout("diag_icon_intermittency", str(r.tone), "Intermittency", str(r.words), null, lamp)
	row.tooltip_text = intermittency_rule()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


## On an idle tile: your power plants here, none of which produced power last turn, and Build power.
static func _plants_row(tile: String, build: Control) -> Control:
	var plants := _plant_count(tile)
	var words := "You have no power plant here."
	if plants == 1:
		words = "Your plant here produced no power last turn."
	elif plants > 1:
		words = "Your %d plants here produced no power last turn." % plants
	return _readout("diag_icon_power_supply", "off", "Power plants", words, build)


## The produced bar's note when it is empty (printed on the plate in capitals, a label, so no full stop):
## whether you have a plant here at all.
static func _plants_note(tile: String) -> String:
	var plants := _plant_count(tile)
	if plants == 0:
		return "You have no plant here"
	return "Your plant here produced nothing" if plants == 1 else "Your %d plants here produced nothing" % plants


static func _plant_count(tile: String) -> int:
	var plants := 0
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if BuildingState.is_player_owned(b) \
				and str(Catalog.get_recipe(str(b.get("recipe_id", ""))).get("output_name", "")) == "power":
			plants += 1
	return plants


# ── Cut short ───────────────────────────────────────────────────────────────────────────────────────────

## The buildings cut short in lulls: the verdict on a glass readout with Reduce intermittency beside it,
## then each building as a module fed from the cable, biggest first, under one OUTPUT CUT caption, with the
## ledger's key in the heading.
static func _cut_short(panel: Control, tile: String, im: Dictionary) -> Control:
	var affected: Array = im.get("affected", [])
	var ledger := _key("Show in ledger", "PowerAffectedKey",
		"Your buildings cut short by intermittency, in the Building Ledger.", CASE_KEY_W)
	ledger.pressed.connect(func() -> void: MatchState.building_ledger_filter_requested.emit("green_intermittent"))
	var sec := _section("PowerIntermittency", "plastic", "Cut short in lulls", [ledger])
	var body: VBoxContainer = sec.get("content")
	body.add_theme_constant_override("separation", 12)
	body.add_child(_verdict(panel, tile, im))
	var shown := mini(AFFECTED_SHOWN, affected.size())
	var readings: Array = []
	var chars := 1
	for i in shown:
		var r := cut_reading(affected[i])
		readings.append(r)
		chars = maxi(chars, ("%d%%" % int(r.cut)).length())
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
		var module := _affected_module(tile, affected[i], readings[i], chars)
		list.add_child(module)
		modules.append(module)
	cable.set("taps", modules)
	rack_col.add_child(rack)
	body.add_child(rack_col)
	if affected.size() > AFFECTED_SHOWN:
		body.add_child(_text("%d more in the ledger." % (affected.size() - AFFECTED_SHOWN)))
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
			"Build battery storage on this tile, in Construct, to firm wind and solar in lulls.", CASE_KEY_W)
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
	cap.tooltip_text = "The share of its output each building lost last turn.\n%s" % lamp_rule()
	row.add_child(cap)
	var tail := Control.new()
	tail.custom_minimum_size.x = MODULE_SEP + roundf(SmallKey.control_side(SmallKey.DEFAULT_KEY_PX)) + MODULE_PAD_R
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tail)
	return row


## One building cut short, in two lines: its lamp, its name and how much of its draw was unfirmed, its
## output cut on a dot matrix screen in white, and a key that takes you to it on the map (the cabinet's own
## Location key, at its size). The lamp and the words come from its reading.
static func _affected_module(tile: String, a: Dictionary, r: Dictionary, chars: int) -> Control:
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
	var full_name := plain_name(tile, iid, bid, str(live.get("recipe_id", "")))
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
	module.tooltip_text = "%s.\n%s Its output was cut %d%% last turn.\n%s" % [full_name, str(r.words), int(r.cut), lamp_rule()]
	module.mouse_filter = Control.MOUSE_FILTER_PASS
	# The output lost, on a dot matrix screen in white, unsigned under the OUTPUT CUT caption.
	var fig := CenterContainer.new()
	fig.name = "Cut"
	fig.custom_minimum_size.x = CUT_W
	fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen := _dots("%d%%" % int(r.cut), chars)
	screen.name = "CutFigure"
	fig.add_child(screen)
	row.add_child(fig)
	var go: TextureButton = SmallKey.make("pin")
	go.name = "GoTo"
	go.tooltip_text = "Show it on the map."
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
	# The bank: how full the storage is, then the cells loaded, in MW of firming, of the MW it takes. What it
	# firmed last turn is the readout under it, so the figure here is only ever what is loaded now.
	var bank_row := HBoxContainer.new()
	bank_row.name = "Bank"
	bank_row.add_theme_constant_override("separation", 8)
	bank_row.tooltip_text = "The cells loaded here firm up to %d MW of wind and solar, of the %d MW the storage takes." % [loaded, housing]
	bank_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var bank: Control = Bank.new()
	bank.call("set_charge", float(loaded) / float(housing) if housing > 0 else 0.0)
	bank.mouse_filter = Control.MOUSE_FILTER_PASS
	bank_row.add_child(bank)
	bank_row.add_child(_caption("Loaded"))
	var chars := maxi(str(loaded).length(), str(housing).length())
	var loaded_fig := _dots(str(loaded), chars)
	loaded_fig.name = "LoadedFigure"
	bank_row.add_child(loaded_fig)
	bank_row.add_child(_caption("of"))
	var housing_fig := _dots(str(housing), chars)
	housing_fig.name = "HousingFigure"
	bank_row.add_child(housing_fig)
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
		tips.append("%s needs %s research." % [full, research] if research != "" else "%s is not available yet." % full)
	var words := "%s cells need research." % _and(names)
	if locked.size() == 1:
		var research := str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(locked[0], ""))
		if research != "":
			words = "%s cells need %s research." % [names[0], research]
	var line := _text(words)
	line.name = "LockedCells"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.tooltip_text = "\n".join(tips)
	return line


## One kind of cell: its icon set in a well with its stock here on the quantity pill in the icon's corner (a
## good's quantity is always that pill), its name and how many are loaded, and its two keys, one width.
## Load puts the cells in stock here into the storage; with none in stock and room for them, Order opens
## the storage's own panel to buy them instead; Unload takes them back into stock.
static func _cell_row(panel: Control, tile: String, internal: String) -> Control:
	var good: Dictionary = Catalog.get_good_by_internal_name(internal)
	var gid := str(good.get("id", ""))
	var gname := str(good.get("display_name", internal))
	var loaded := int(Power.get_tile_battery_cells(tile).get(gid, 0))
	var stock := Stockpile.get_at_tile(tile, gid)
	var row := HBoxContainer.new()
	row.name = "Cells_%s" % internal
	row.add_theme_constant_override("separation", 12)
	var icon := _good_in_well(gid, internal, CELL_ICON_PX)
	icon.add_child(_pill(stock))
	# The good's own hover (its name, then the encyclopedia) says what the pill counts.
	icon.set("detail_lines", PackedStringArray(["%d in stock here." % stock]))
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.add_child(_text(gname, true))
	var count := _text("None loaded." if loaded <= 0 else ("1 cell loaded." if loaded == 1 else "%d cells loaded." % loaded))
	count.name = "LoadedCells"
	col.add_child(count)
	row.add_child(col)
	var room := Power.battery_cells_to_fill(tile, gid) > 0
	var storage := _storage_building(tile)
	var first: Control
	if stock <= 0 and room and storage != "":
		first = _key("Order", "Order_%s" % internal, "Order %s cells in your battery storage's own panel." % gname.to_lower(), CELL_KEY_W)
		first.pressed.connect(func() -> void: panel.call("_open_building_or_construction", storage))
	else:
		first = _key("Load", "Load_%s" % internal, "Load the %s cells in stock here." % gname.to_lower(), CELL_KEY_W)
		if stock > 0 and room:
			first.pressed.connect(func() -> void:
				Power.load_battery_cells(tile, gid, stock)
				panel.call("_refresh_pane", "power"))
		else:
			first.set("disabled", true)
			var free_mw := float(Power.tile_battery_slots(tile)) - Power.tile_loaded_firming(tile)
			first.tooltip_text = "No %s cells in stock here." % gname.to_lower() if stock <= 0 \
				else ("The storage is full." if free_mw <= 0.0 else "Too little room left for a %s cell." % gname.to_lower())
	first.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(first)
	var unload := _key("Unload", "Unload_%s" % internal, "Take the %s cells out, back into stock." % gname.to_lower(), CELL_KEY_W)
	unload.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if loaded <= 0:
		unload.set("disabled", true)
		unload.tooltip_text = "No %s cells loaded." % gname.to_lower()
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


## A figure that isn't money on a dot matrix screen in white (DS2: the seven segment LED is for money and
## unit costs only), framed in the mini screen's bezel, padded to `chars` characters with unlit ones so a
## group's screens are one width.
static func _dots(text: String, chars: int) -> Control:
	var dm: Control = DotMatrix.new()
	dm.set("pitch", DOT_PITCH)
	dm.set("align", HORIZONTAL_ALIGNMENT_RIGHT)
	dm.set("text", " ".repeat(maxi(0, chars - text.length())) + text)
	dm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return dm


## Building Detail's navy quantity pill, kept inside the icon's bottom right corner (DS2 rule 7), as the
## other tabs set a good's quantity.
static func _pill(qty: int) -> Control:
	var text := str(qty)
	var w := maxi(PILL_H, text.length() * 9 + 14)
	var p := PanelContainer.new()
	p.name = "QtyPill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(w, PILL_H)
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_left = -w - PILL_INSET
	p.offset_top = -PILL_H - PILL_INSET
	p.offset_right = -PILL_INSET
	p.offset_bottom = -PILL_INSET
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(PILL_H / 2.0))
	st.set_border_width_all(2)
	st.border_color = DS.PALETTE["BORDER_STRONG"]
	p.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.name = "Qty"
	l.theme_type_variation = "Numeric"
	l.text = text
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## A lamp's reading: the raised icon (none for ""), its lamp (`lamp`, or a pilot lamp lit in `tone`), its
## name in a metal label and a line of words under it, and the key that acts on it at the end, in the
## plate's column of keys.
static func _readout(icon: String, tone: String, caption: String, words: String, key: Control, lamp: Control = null) -> Control:
	var row := HBoxContainer.new()
	row.name = "Readout_%s" % caption.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	if icon != "":
		row.add_child(_raised(icon, ICON_PX))
	if lamp == null:
		lamp = Lamp.new()
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


## The plastic case in a margin that lines it up with the steel sections: its render reaches its control's
## edges while the steel frame's rim stands inside its own (1.5 px on the left, 3 on the right, measured on
## the captures), so without it the case sticks out past the frames and touches the body's scrollbar.
static func _inset(sec: Control) -> Control:
	var m := MarginContainer.new()
	m.name = str(sec.name) + "Inset"
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", PLASTIC_INSET)
	m.add_theme_constant_override("margin_right", PLASTIC_INSET)
	m.add_theme_constant_override("margin_top", 0)
	m.add_theme_constant_override("margin_bottom", 0)
	m.add_child(sec)
	return m


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
