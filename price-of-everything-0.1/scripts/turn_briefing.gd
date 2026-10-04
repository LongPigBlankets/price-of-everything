extends Node
## TurnBriefing: the turn-start digest (docs/turn-briefing-panel-spec.md).
##
## One surface for what the player must act on this turn: the decision queue and the live
## alerts (bankruptcy runway, starved buildings, cables, stockpile, deposits, cash for
## inputs), shown as the mid-screen panel. Owner rulings: decisions can NOT be dismissed
## (resolve-only; they block End Turn via the commit_turn guard), an alert silenced never
## lights again that game (its window stays dark); the panel auto-expands only on CRITICAL turns (an unresolved decision,
## or a new / newly-worsened critical alert) and otherwise stays closed. One-off news
## (research, construction done, a decision answered, the bridge loan, policy news,
## forewarnings) is a row in the updates dock only, and a full tile shows on the top bar's
## storage lamp only (docs/briefing-ds2-plan.md, docs/ds2-owner-decisions.md "Briefing").
##
## This autoload is a VIEW over DecisionState / EventScheduler / SolvencyState /
## Production — it owns no sim state beyond dismissal signatures for the live alerts
## (so a dismissed alert re-surfaces only if the condition worsens).

# No class_name on building_status.gd, so an autoload must preload it to reach the helpers.
const BuildingStatus := preload("res://scripts/building_status.gd")
const StripScript := preload("res://scripts/turn_briefing_strip.gd")
const PanelScript := preload("res://scripts/turn_briefing_panel.gd")
const PanelDs2Script := preload("res://scripts/briefing_ds2/briefing_ds2.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

# A dismissed live alert re-surfaces when its magnitude worsens by at least this much
# (starved: +1 building; bankruptcy: runway drops by another £50 band).
const BANKRUPTCY_RESURFACE_BAND := 50.0
const STARVED_LIST_ROWS := 4

# Shared by the strip + panel: decision-category tints and severity colours
# (severity keys mirror EventScheduler's).
const CATEGORY_COLORS := {
	"labour": Color("#D96AA0"), "market": Color("#E6B34A"),
	"environment": Color("#5FBF6B"), "infrastructure": Color("#7FA8CC"),
	"land": Color("#B08D57"), "tech": Color("#6BC7C7"), "story": Color("#CDB98A"),
}
# Off-white used for non-critical strip/menu icons (critical items keep their colour).
const OFF_WHITE := Color("#DCE3EC")
const CATEGORY_ICONS := {
	"labour": "users", "market": "coin", "environment": "leaf",
	"infrastructure": "gauge", "land": "box", "tech": "beaker", "story": "flag",
}
const ICON_GLYPHS := {
	"warn": "⚠", "box": "▦", "beaker": "⚗", "coin": "£", "truck": "➤",
	"flag": "⚑", "hammer": "⚒", "users": "☰", "leaf": "❧", "gauge": "◔", "scale": "⚖",
}
static func severity_color(severity: String) -> Color:
	match severity:
		"critical": return DS.PALETTE["DANGER"]
		"warning": return DS.PALETTE["WARN"]
		_: return DS.PALETTE["TEXT_MUTED"]
static func category_color(category: String) -> Color:
	return CATEGORY_COLORS.get(category, Color("#CDB98A"))

# An item is "critical" (coloured icon) if it's a decision, a live alert, or a news
# announcement; routine info (research, sales, completions) is off-white.
static func item_is_critical(it: Dictionary) -> bool:
	return str(it.get("kind", "")) == "decision" \
		or str(it.get("section", "")) == "alerts" or str(it.get("section", "")) == "news"
static func item_glyph(it: Dictionary) -> String:
	var icon := str(it.get("icon", ""))
	if icon == "" and str(it.get("kind", "")) == "decision":
		icon = str(CATEGORY_ICONS.get(str(it.get("category", "")), "scale"))
	return str(ICON_GLYPHS.get(icon, "◆"))
static func item_display_color(it: Dictionary) -> Color:
	if not item_is_critical(it):
		return OFF_WHITE
	if str(it.get("kind", "")) == "decision":
		return category_color(str(it.get("category", "")))
	return severity_color(str(it.get("severity", "info")))

## Silencing an alert turns its kind off for the rest of the game (the owner): it is not closing the
## panel, so its key says so, and the words beside it say it is for good.
const SILENCE_LABEL := "Silence alert"
const SILENCE_HINT := "This will not trigger again."

signal items_changed()
signal expanded_changed(expanded: bool)

var enabled: bool = false
var expanded: bool = false

var _items: Array = []                 # assembled BriefingItem dicts (view objects)
var _alert_dismissed: Dictionary = {}  # alert_id -> magnitude at dismissal (persisted)
var _silenced_windows: Dictionary = {}  # window kind (WINDOWS) -> true: never lit again this game (persisted)
var _last_alert_ids: Dictionary = {}   # alert ids present last evaluation (new-alert detect)
var _layer: CanvasLayer = null
var _strip: Control = null
## The top bar's Briefing module replaces the collapsed strip; the bar
## sets this false at ready so the strip never mounts alongside it.
var strip_enabled := true
var _panel: Control = null
var _refresh_queued := false
var _select_on_expand := ""


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	await get_tree().process_frame
	MatchState.state_reset.connect(reset)
	DecisionState.pending_changed.connect(_queue_refresh)
	DecisionState.decision_drawn.connect(_on_decision_drawn)
	EventScheduler.active_events_changed.connect(_queue_refresh)
	EventScheduler.event_fired.connect(_on_event_fired)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.commit_blocked_by_decisions.connect(_on_commit_blocked)
	MatchState.money_changed.connect(_queue_refresh)
	LoanState.loans_updated.connect(_queue_refresh)
	SaveLoad.match_loaded.connect(_on_match_loaded)
	UiPrefs.briefing_ds2_changed.connect(_on_ds2_changed)

func reset() -> void:
	_alert_dismissed.clear()
	_silenced_windows.clear()
	_last_alert_ids.clear()
	_select_on_expand = ""
	expanded = false
	_rebuild_items()
	_sync_ui()


# ---------------------------------------------------------------------------
# Item assembly (spec §3, §5, §6) — a fresh view over the live sources.
# ---------------------------------------------------------------------------

func items() -> Array:
	return _items

func unresolved_decisions() -> Array:
	return _items.filter(func(it) -> bool: return str(it.kind) == "decision")

func critical_alerts() -> Array:
	return _items.filter(func(it) -> bool:
		return str(it.section) == "alerts" and str(it.severity) == "critical")

## True while a tutorial match is running. Defensive lookup: the Tutorial autoload
## is always present, but treat a missing/renamed singleton as "not active".
func _tutorial_active() -> bool:
	var t := get_node_or_null("/root/Tutorial")
	return t != null and bool(t.get("active"))

func _rebuild_items() -> void:
	var out: Array = []
	# 1. Decisions — queue order; blocking; never dismissible.
	for view: Dictionary in DecisionState.pending_views():
		var def: Dictionary = DecisionState.DECISION_DEFINITIONS.get(_def_id_for_uid(str(view.uid)), {})
		out.append({
			"id": "dec:%s" % str(view.uid), "kind": "decision", "section": "decisions",
			"severity": "critical", "dismissible": false,
			"title": str(view.title), "uid": str(view.uid),
			"category": str(def.get("category", "")),
			"view": view,
		})
	# During the tutorial, show ONLY decisions — the live-state updates (a factory
	# starved until it's powered, an empty stockpile) fire mid-lesson and confuse
	# players before they've learned what they mean. The Diagnostics card on the
	# building still surfaces the same faults where the tutorial points them out.
	if _tutorial_active():
		_items = out
		return
	# 2. Live critical states (self-clearing; silencing one turns its kind off for good, below).
	var bankruptcy := _bankruptcy_item()
	if not bankruptcy.is_empty():
		out.append(bankruptcy)
	var starved := _starved_item()
	if not starved.is_empty():
		out.append(starved)
	var undersized := _storage_undersized_item()
	if not undersized.is_empty():
		out.append(undersized)
	var power_capped := _power_capped_item()
	if not power_capped.is_empty():
		out.append(power_capped)
	var refused := _intermediary_refused_item()
	if not refused.is_empty():
		out.append(refused)
	var deposit_low := _deposit_running_out_item()
	if not deposit_low.is_empty():
		out.append(deposit_low)
	var cash_short := _input_cash_short_item()
	if not cash_short.is_empty():
		out.append(cash_short)
	var spliced := _input_splice_item()
	if not spliced.is_empty():
		out.append(spliced)
	# 3. Bell events that are live alerts (a deposit exhausted) join them (single source of
	# truth: dismissing here dismisses in the bell too). Every other event is one-off news,
	# a row in the updates dock (_on_event_fired). Only the LATEST turn's events show:
	# resolution-phase events are stamped current_turn-1, post-resolution ones the current
	# turn, so the window is [current_turn-1, current_turn].
	for ev: Dictionary in _recent_events():
		var item := _event_item(ev)
		if not item.is_empty():
			out.append(item)
	# A silenced kind of alert never shows again (its window stays dark).
	out = out.filter(func(it) -> bool: return not _silenced_windows.has(window_kind_for(str((it as Dictionary).get("id", "")))))
	# Order: decisions, then alerts by severity, then info.
	var rank := {"decisions": 0, "alerts": 1, "news": 2, "info": 3}
	var sev_rank := {"critical": 0, "warning": 1, "info": 2}
	out.sort_custom(func(a, b) -> bool:
		if int(rank.get(a.section, 9)) != int(rank.get(b.section, 9)):
			return int(rank.get(a.section, 9)) < int(rank.get(b.section, 9))
		if a.section == "alerts" and a.severity != b.severity:
			return int(sev_rank.get(a.severity, 9)) < int(sev_rank.get(b.severity, 9))
		return false)
	_items = out

func _def_id_for_uid(uid: String) -> String:
	for d in DecisionState.pending_queue:
		if str(d.get("uid", "")) == uid:
			return str(d.get("def_id", ""))
	return ""

# Bankruptcy looming: runway (cash + borrowing room) under the top bar's threshold.
func _bankruptcy_item() -> Dictionary:
	var runway: float = float(MatchState.money) + LoanState.available_capacity()
	if runway >= 100.0 or TurnManager.game_ended:
		_alert_dismissed.erase("alert:bankruptcy")   # recovered → forget the dismissal
		return {}
	if _alert_dismissed.has("alert:bankruptcy") \
			and runway > float(_alert_dismissed["alert:bankruptcy"]) - BANKRUPTCY_RESURFACE_BAND:
		return {}
	var net := 0.0
	if not SolvencyState.history.is_empty():
		net = float((SolvencyState.history.back() as Dictionary).get("profit", 0.0))
	return {
		"id": "alert:bankruptcy", "kind": "critical", "section": "alerts",
		"severity": "critical", "dismissible": true, "magnitude": runway,
		"title": "Bankruptcy near", "icon": "warn",
		"body": "Cash and loan capacity together are under £100. Cut losses or raise cash.",
		"rows": [
			["Cash", "£%.0f" % MatchState.money, "bad" if MatchState.money < 0.0 else ""],
			["Loan capacity", "£%.0f" % LoanState.available_capacity(), ""],
			["Net last turn", "%s£%.0f" % ["+" if net >= 0.0 else "-", absf(net)], "bad" if net < 0.0 else "ok"],
		],
		"figures": [
			{"caption": "Cash", "kind": "cash", "value": float(MatchState.money)},
			{"caption": "Loan capacity", "kind": "cash", "value": LoanState.available_capacity()},
			{"caption": "Net last turn", "kind": "cash", "value": net},
		],
	}

## Player power PRODUCERS whose "missing: power" is really the tile cable export cap refusing
## their dispatch, not a supply failure. Production reports them exactly like a starved consumer,
## so without this split they surface as "starved of power" — advice that is the opposite of what
## the player must do. building_readout already special-cases it; the briefing did not.
## Returns instance_id -> {tile_id, mw}.
func _cable_capped_producers() -> Dictionary:
	var out: Dictionary = {}
	for iid in Production.missing_by_building.keys():
		var b: Dictionary = BuildingState.get_building(str(iid))
		if b.is_empty() or not BuildingState.is_player_owned(b):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		if recipe.is_empty() or str(recipe.get("output_name", "")) != "power":
			continue
		for m in (Production.missing_by_building[iid] as Array):
			if str((m as Dictionary).get("internal_name", "")) == "power":
				out[str(iid)] = {
					"tile_id": str(b.get("tile_id", "")),
					"mw": BuildingStatus.effective_power_output(b, recipe),
				}
				break
	return out

## Generation the player is paying for and cannot sell, because the tile's cables are full.
## Fires as a WARNING: nothing is broken, but the plant earns nothing while costing maintenance.
func _power_capped_item() -> Dictionary:
	var capped := _cable_capped_producers()
	if capped.is_empty():
		_alert_dismissed.erase("alert:power_capped")
		return {}
	var tiles: Dictionary = {}
	var mw_idle := 0
	var listed: Array = []
	for iid in capped:
		var d: Dictionary = capped[iid]
		tiles[str(d["tile_id"])] = true
		mw_idle += int(d["mw"])
	var at_max := 0
	for t in tiles:
		if Power.cable_level_is_max(str(t)):
			at_max += 1
	for iid2 in capped:
		if listed.size() >= STARVED_LIST_ROWS:
			break
		var d2: Dictionary = capped[iid2]
		listed.append({
			"instance_id": str(iid2), "tile_id": str(d2["tile_id"]), "good_id": good_id_of("power"),
			"why": "Cables full. No power sold.",
		})
	var total := capped.size()
	if _alert_dismissed.has("alert:power_capped") and total <= int(_alert_dismissed["alert:power_capped"]):
		return {}
	var advice := "Upgrade the cables on those tiles, or build generation on another tile."
	if at_max == tiles.size():
		advice = "Those tiles have the highest cable level. Build generation on another tile."
	var rows: Array = [["Plants blocked", "%d" % total, "warn"]]
	if mw_idle > 0:
		rows.append(["Generation blocked", "%d MW/turn" % mw_idle, "warn"])
	if at_max > 0:
		rows.append(["Tiles at the highest cable level", "%d of %d" % [at_max, tiles.size()], "bad"])
	return {
		"id": "alert:power_capped", "kind": "critical", "section": "alerts",
		"severity": "warning", "dismissible": true, "magnitude": total, "icon": "bolt",
		"title": "%s blocked by full cables" % _count(total, "power plant"),
		"body": "Full cables stopped these plants selling power. Their upkeep was still paid. " + advice,
		"rows": rows,
		"list": listed,
		"list_more": maxi(0, total - listed.size()),
	}

## Buildings whose batch the intermediary refused last turn (no cash or borrowing room, prohibited imports,
## full cables), so they made nothing. Production records these apart from starved buildings, and only the
## building's diagnostics showed them. A building paused or retooling by the player's choice isn't listed.
func _intermediary_refused_item() -> Dictionary:
	var listed: Array = []
	var total := 0
	for iid in Production.blocked_reason_by_building.keys():
		var block: Dictionary = Production.blocked_reason_by_building[iid]
		if str(block.get("code", "")) != "middleman" or Production.last_turn_run.has(iid):
			continue
		var b: Dictionary = BuildingState.get_building(str(iid))
		if b.is_empty() or not BuildingState.is_player_owned(b):
			continue
		var why: String = preload("res://scripts/building_readout.gd").intermediary_reason(str(block.get("message", "")))
		if why == "The building is paused or its recipe changed.":
			continue
		total += 1
		if listed.size() < STARVED_LIST_ROWS:
			listed.append({"instance_id": str(iid), "tile_id": str(b.get("tile_id", "")), "why": why})
	if total == 0:
		_alert_dismissed.erase("alert:intermediary_refused")
		return {}
	if _alert_dismissed.has("alert:intermediary_refused") and total <= int(_alert_dismissed["alert:intermediary_refused"]):
		return {}
	return {
		"id": "alert:intermediary_refused", "kind": "critical", "section": "alerts",
		"severity": "warning", "dismissible": true, "magnitude": total, "icon": "truck",
		"title": ("1 batch" if total == 1 else "%d batches" % total) + " refused by Local Suppliers",
		"body": "Local Suppliers bought no inputs for these buildings, so they made nothing last turn. Their upkeep was still paid.",
		"rows": [],
		"list": listed,
		"list_more": maxi(0, total - listed.size()),
	}


# N buildings starved (power vs inputs), with deep-link rows to the worst offenders.
func _starved_item() -> Dictionary:
	var power_starved: Array = []
	var input_starved: Array = []
	# A generator blocked by the cable cap reports "missing: power" identically to a consumer
	# with no supply. It belongs to the power-capped alert, not here — counting it as starved
	# tells the player to find power for a building that is drowning in it.
	var cable_capped := _cable_capped_producers()
	for iid in Production.missing_by_building.keys():
		var b: Dictionary = BuildingState.get_building(str(iid))
		if b.is_empty() or not BuildingState.is_player_owned(b) or cable_capped.has(str(iid)):
			continue
		var lacks_power := false
		var missing: Array = Production.missing_by_building[iid]
		var names: PackedStringArray = []
		var first_good := ""
		for m in missing:
			var iname := str((m as Dictionary).get("internal_name", ""))
			if iname == "power":
				lacks_power = true
			var gid := str((m as Dictionary).get("good_id", "")) if str((m as Dictionary).get("good_id", "")) != "" else good_id_of(iname)
			if first_good == "":
				first_good = gid
			names.append(Catalog.get_display_name(gid) if gid != "" else iname.replace("_", " "))
		var why := "No power." if lacks_power else "Missing %s." % ", ".join(names).to_lower()
		var row := {"instance_id": str(iid), "tile_id": str(b.get("tile_id", "")), "why": why,
			"good_id": good_id_of("power") if lacks_power else first_good}
		if lacks_power:
			power_starved.append(row)
		else:
			input_starved.append(row)
	var total := power_starved.size() + input_starved.size()
	if total == 0:
		_alert_dismissed.erase("alert:starved")
		return {}
	if _alert_dismissed.has("alert:starved") and total <= int(_alert_dismissed["alert:starved"]):
		return {}
	var listed: Array = (power_starved + input_starved).slice(0, STARVED_LIST_ROWS)
	# The split only says something when both kinds are starved; one kind is the title again.
	var rows: Array = []
	if not power_starved.is_empty() and not input_starved.is_empty():
		rows.append(["Without power", _count(power_starved.size(), "building"), "bad"])
		rows.append(["Without inputs", _count(input_starved.size(), "building"), "warn"])
	return {
		"id": "alert:starved", "kind": "critical", "section": "alerts",
		"severity": "critical" if not power_starved.is_empty() else "warning",
		"dismissible": true, "magnitude": total, "icon": "box",
		"title": "%s starved" % _count(total, "building"),
		"body": "Power or inputs were missing, so they made nothing last turn. Their upkeep was still paid.",
		"rows": rows,
		"list": listed,
		"list_more": maxi(0, total - listed.size()),
	}


## "1 building", "3 buildings".
static func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


## A good's id from its internal name ("power" → its id), "" when there is none.
static func good_id_of(internal_name: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal_name).get("id", "")) if internal_name != "" else ""

## STRUCTURAL storage shortfall (Production.last_turn_summary.storage_overcommitted):
## the tile's warehouse is smaller than its buildings' steady-state working set —
## import buffers, locally-made intermediates and outputs together beat capacity, so
## the tile will jam no matter how orders are throttled. Fires before the acute
## "storage full" alert, so the player can expand ahead of the deadlock.
func _storage_undersized_item() -> Dictionary:
	var rows: Array = Production.last_turn_summary.get("storage_overcommitted", [])
	if rows.is_empty():
		_alert_dismissed.erase("alert:storage_undersized")
		return {}
	var shortfall := 0
	var listed: Array = []
	for r in rows:
		var d: Dictionary = r
		shortfall += maxi(0, int(d.get("required", 0)) - int(d.get("capacity", 0)))
		if listed.size() < STARVED_LIST_ROWS:
			listed.append({
				"instance_id": "", "tile_id": str(d.get("tile_id", "")),
				"why": "Needs %d. Holds %d." % [int(d.get("required", 0)), int(d.get("capacity", 0))],
			})
	if _alert_dismissed.has("alert:storage_undersized") and shortfall <= int(_alert_dismissed["alert:storage_undersized"]):
		return {}
	var first_tile := str((rows[0] as Dictionary).get("tile_id", ""))
	var title := "%s needs more stockpile" % place_name(first_tile) if rows.size() == 1 \
		else "%d tiles need more stockpile" % rows.size()
	var body := "Its buildings' inputs and outputs need more stockpile than the tile holds." if rows.size() == 1 \
		else "Their buildings' inputs and outputs need more stockpile than the tiles hold."
	# One tile's row already says what it needs and holds; several tiles add up.
	var stat_rows: Array = []
	if rows.size() > 1:
		stat_rows = [["Short by", _count(shortfall, "unit"), "bad"], ["Tiles", "%d" % rows.size(), ""]]
	return {
		"id": "alert:storage_undersized", "kind": "critical", "section": "alerts",
		"severity": "critical", "dismissible": true, "magnitude": shortfall, "icon": "box",
		"title": title,
		"body": body + " Expand storage in the Stockpile tab, sell surplus goods or move production to another tile.",
		"rows": stat_rows,
		"list": listed,
		"list_more": maxi(0, rows.size() - listed.size()),
	}

## Mines within Production.DEPOSIT_WARNING_TURNS of exhausting their deposit. A WARNING,
## not a critical: the mine is still producing normally today, and the player has a few
## turns to site a replacement. Dismissible, and re-raises if a further mine drops in.
func _deposit_running_out_item() -> Dictionary:
	var rows: Array = Production.last_turn_summary.get("deposits_running_out", [])
	if rows.is_empty():
		_alert_dismissed.erase("alert:deposit_running_out")
		return {}
	var soonest: Dictionary = rows[0]
	for r in rows:
		if int((r as Dictionary).get("turns_left", 99)) < int(soonest.get("turns_left", 99)):
			soonest = r
	# Magnitude is the COUNT of warning mines, so dismissing one warning doesn't silence a
	# second mine that starts running out later.
	if _alert_dismissed.has("alert:deposit_running_out") \
			and rows.size() <= int(_alert_dismissed["alert:deposit_running_out"]):
		return {}
	var token := str(soonest.get("token", "")).replace("_", " ")
	var turns := int(soonest.get("turns_left", 0))
	var listed: Array = []
	for r in rows:
		var d: Dictionary = r
		if listed.size() >= STARVED_LIST_ROWS:
			break
		listed.append({
			"instance_id": str(d.get("instance_id", "")), "tile_id": str(d.get("tile_id", "")),
			"good_id": str(d.get("good_id", "")),
			"why": "%s left of %s." % [_count(int(d.get("turns_left", 0)), "turn"), str(d.get("token", "")).replace("_", " ")],
		})
	var title := "%s deposit runs out in %s" % [token.capitalize(), _count(turns, "turn")] if rows.size() == 1 \
		else "%d deposits running out" % rows.size()
	return {
		"id": "alert:deposit_running_out", "kind": "warning", "section": "alerts",
		"severity": "warning", "dismissible": true, "magnitude": rows.size(),
		"icon": "warn", "icon_good_id": str(soonest.get("good_id", "")),
		"title": title,
		"body": "The %s deposit at %s runs out in %s. Build a replacement mine." % [
			token, place_name(str(soonest.get("tile_id", ""))), _count(turns, "turn")],
		"rows": [
			["Turns left", "%d" % turns, "warn"],
			["Remaining", _count(int(soonest.get("remaining", 0)), "unit"), ""],
			["Mined", "%d/turn" % int(soonest.get("per_turn", 0)), ""],
		],
		"list": listed,
		"list_more": maxi(0, rows.size() - listed.size()),
	}

## A tile as the player knows it: its name, never its coordinates or id.
static func place_name(tile_id: String) -> String:
	var label := str(Catalog.tile_name(tile_id))
	return label if label != "" else "Unnamed tile"


## A row's own name: the building's name when the row is a building, else the place.
static func row_title(entry: Dictionary) -> String:
	var iid := str(entry.get("instance_id", ""))
	if iid != "":
		var b: Dictionary = BuildingState.get_building(iid)
		if not b.is_empty():
			return BuildingNaming.of(b)
	return place_name(str(entry.get("tile_id", "")))


## A row's line under its name: where a building stands, then why it is listed.
static func row_detail(entry: Dictionary) -> String:
	var why := str(entry.get("why", ""))
	if str(entry.get("instance_id", "")) != "" and not BuildingState.get_building(str(entry.get("instance_id", ""))).is_empty():
		return "%s. %s" % [place_name(str(entry.get("tile_id", ""))), why]
	return why

## Input orders the market pipeline could not fully place for CASH last turn
## (Production.last_turn_summary.input_orders_short). Without this item
## a remote building's (lead+1)-turn pipeline order is clipped or skipped silently and
## the player only sees the starvation days later.
func _input_cash_short_item() -> Dictionary:
	var short: Array = Production.last_turn_summary.get("input_orders_short", [])
	if short.is_empty():
		_alert_dismissed.erase("alert:input_cash")
		return {}
	var skipped := 0
	var short_cost := 0.0
	var listed: Array = []
	for s in short:
		var d: Dictionary = s
		if int(d.get("bought", 0)) == 0:
			skipped += 1
		short_cost += float(d.get("short_cost", 0.0))
		if listed.size() < STARVED_LIST_ROWS:
			listed.append({
				"instance_id": "", "tile_id": str(d.get("tile_id", "")), "good_id": str(d.get("good_id", "")),
				"why": "%s. Bought %d of %d." % [Catalog.get_display_name(str(d.get("good_id", ""))),
					int(d.get("bought", 0)), int(d.get("requested", 0))],
			})
	if _alert_dismissed.has("alert:input_cash") and short.size() <= int(_alert_dismissed["alert:input_cash"]):
		return {}
	var stat_rows: Array = []
	if skipped > 0:
		stat_rows.append(["Orders skipped", "%d" % skipped, "bad"])
	stat_rows.append(["Cash needed", "£%d" % int(ceil(short_cost)), "warn"])
	return {
		"id": "alert:input_cash", "kind": "critical", "section": "alerts",
		"severity": "critical" if skipped > 0 else "warning",
		"dismissible": true, "magnitude": short.size(), "icon": "coin",
		"title": "%s short of cash" % _count(short.size(), "input order"),
		"body": "Cash ran short for inputs last turn. £%d more was needed. Production stops when the stock runs out." % int(ceil(short_cost)),
		"rows": stat_rows,
		"figures": [{"caption": "Cash needed", "kind": "cost", "value": ceilf(short_cost)}],
		"list": listed,
		"list_more": maxi(0, short.size() - listed.size()),
	}

## Inputs fed from same-tile production AND market top-up at once
## (Production.last_turn_summary.input_splices). Informational: if the local
## producer dips, the market top-up lags by the transport lead before bigger
## orders arrive — a hidden fragility worth knowing about.
func _input_splice_item() -> Dictionary:
	var splices: Array = Production.last_turn_summary.get("input_splices", [])
	if splices.is_empty():
		_alert_dismissed.erase("alert:input_splice")
		return {}
	if _alert_dismissed.has("alert:input_splice") and splices.size() <= int(_alert_dismissed["alert:input_splice"]):
		return {}
	var listed: Array = []
	for s in splices.slice(0, STARVED_LIST_ROWS):
		var d: Dictionary = s
		listed.append({
			"instance_id": "", "tile_id": str(d.get("tile_id", "")), "good_id": str(d.get("good_id", "")),
			"why": "%s. %d/turn made here, %d/turn bought." % [Catalog.get_display_name(str(d.get("good_id", ""))),
				int(d.get("local", 0)), int(d.get("market", 0))],
		})
	return {
		"id": "alert:input_splice", "kind": "info", "section": "info",
		"severity": "info",
		"dismissible": true, "magnitude": splices.size(), "icon": "truck",
		"title": "%s partly bought" % _count(splices.size(), "input"),
		"body": "These inputs are partly made on the tile and partly bought. What is bought takes time to arrive.",
		"rows": [],
		"list": listed,
		"list_more": maxi(0, splices.size() - listed.size()),
	}

# Bell events that are live alerts in the briefing, by kind → section. Every other kind is
# one-off news and stays out of the briefing.
const _EVENT_SECTIONS := {
	"deposit_exhausted": "alerts",
	"discount_repaid": "alerts",
}
# Event kinds that never become a dock row from here: superseded by a live alert or the top
# bar's storage lamp, too noisy, or already posted to the dock by their own source (the
# research unlock by the top bar, the finished building, the answered decision, the bridge
# loan, the tutorial top up and the survey by their own toasts).
const _NO_DOCK_ROW := {
	"deposit_exhausted": true, "tile_at_capacity": true, "sales_aggregate": true,
	"bankruptcy_warning": true, "building_starved": true, "research_unlocked": true,
	"construction_completed": true, "decision_resolved": true, "bridge_loan": true,
	"tutorial_rescue": true, "survey_completed": true, "sales_arrived": true,
}
# Kind → icon glyph key (see ICON_GLYPHS). Announcement kinds we don't know fall back
# to the flag in _event_item.
const _EVENT_ICONS := {
	"research_unlocked": "beaker",
	"sales_aggregate": "truck",
	"construction_completed": "hammer",
	"decision_resolved": "scale",
	"decision_incoming": "scale",
	"bridge_loan": "coin",
	"discount_repaid": "coin",
	"deposit_exhausted": "warn",
	"tile_at_capacity": "gauge",
	"policy_enacted": "scale",
	"forewarn": "flag",
	"advisor_tip": "users",
}

func _event_item(ev: Dictionary) -> Dictionary:
	var kind := str(ev.get("kind", ""))
	var section: String = str(_EVENT_SECTIONS.get(kind, ""))
	if section == "":
		return {}
	var dl: Dictionary = ev.get("deeplink", {})
	var listed: Array = []
	if str(dl.get("tile_id", "")) != "":
		listed.append({"instance_id": "", "tile_id": str(dl.tile_id),
			"good_id": good_id_of(str(ev.get("token", ""))), "why": "Mining has stopped."})
	return {
		"id": "ev:%s" % str(ev.id), "kind": "event", "event_kind": kind, "section": section,
		"list": listed, "list_more": 0,
		"severity": str(ev.get("severity", "info")),
		"dismissible": true, "event_id": str(ev.id),
		"icon": str(_EVENT_ICONS.get(kind, "flag")),
		"title": str(ev.get("title", "")),
		"body": str(ev.get("body", "")),
		"deeplink": ev.get("deeplink", {}),
	}


## Bell events of the latest turn (see _rebuild_items for the window).
func _recent_events() -> Array:
	var min_turn: int = maxi(1, int(TurnManager.current_turn) - 1)
	return EventScheduler.active_events().filter(func(ev) -> bool:
		return int((ev as Dictionary).get("turn_fired", 0)) >= min_turn)


## The research unlocked in the latest turn, one {name, reward, condition} each: the top bar
## posts each to the updates dock once.
func recent_research() -> Array:
	var list: Array = []
	for ev: Dictionary in _recent_events():
		if str(ev.get("kind", "")) != "research_unlocked":
			continue
		list.append({
			"name": str(ev.get("research_name", "")),
			"reward": str(ev.get("research_reward", "")),
			"condition": str(ev.get("research_condition", "")),
		})
	return list


## One-off news goes to the updates dock as a row, once, as it fires: its colour by its
## severity, its words the event's title and body.
func _on_event_fired(ev: Dictionary) -> void:
	var text := news_row_text(ev)
	if text == "":
		return
	MatchState.request_toast(text, news_row_type(str(ev.get("severity", "info"))))


## The dock row's words for a one-off event, "" for a kind that makes no row.
static func news_row_text(ev: Dictionary) -> String:
	if _NO_DOCK_ROW.has(str(ev.get("kind", ""))) or _EVENT_SECTIONS.has(str(ev.get("kind", ""))):
		return ""
	var title := str(ev.get("title", "")).strip_edges()
	var body := str(ev.get("body", "")).strip_edges()
	if title == "":
		return body
	if body == "":
		return title
	if not (title.ends_with(".") or title.ends_with("!") or title.ends_with("?")):
		title += "."
	return "%s %s" % [title, body]


## The toast type a one-off event's severity posts as: critical red, warning amber, else green.
static func news_row_type(severity: String) -> String:
	match severity:
		"critical": return "warning"
		"warning": return "caution"
		_: return "info"


# ---------------------------------------------------------------------------
# Player actions (the panel calls these; sim mutations go through the sources).
# ---------------------------------------------------------------------------

func dismiss(item_id: String) -> void:
	var item := _item_by_id(item_id)
	if item.is_empty() or not bool(item.get("dismissible", false)):
		return   # decisions land here too — never dismissible
	# The alert's whole kind is silenced for good: "This will not trigger again."
	var kind := window_kind_for(item_id)
	if kind != "":
		_silenced_windows[kind] = true
	if item.has("magnitude"):
		_alert_dismissed[item_id] = item.magnitude   # quiet until it worsens
	elif item.has("event_id"):
		EventScheduler.dismiss(str(item.event_id))   # bell syncs (one source of truth)
	_queue_refresh()

## Whether the turn can end, in one line: the count `commit_turn` refuses on.
func gate_line() -> String:
	var n := unresolved_decisions().size()
	if n == 0:
		return "No decisions waiting. You can end the turn."
	return "Answer %s before you end the turn." % _count(n, "decision")


## The annunciator's windows, in their fixed order (docs/briefing-ds2-plan.md §4): one per kind of alert, the
## legend it prints, and the items that light it.
const WINDOWS := [
	["starved", "STARVED", "alert:starved"],
	["cash_short", "CASH SHORT", "alert:input_cash"],
	["bankruptcy", "BANKRUPTCY", "alert:bankruptcy"],
	["cables_full", "CABLES FULL", "alert:power_capped"],
	["stockpile_small", "STOCKPILE SMALL", "alert:storage_undersized"],
	["deposit_low", "DEPOSIT LOW", "alert:deposit_running_out"],
	["deposit_out", "DEPOSIT OUT", "ev:deposit_exhausted:"],
	["mixed_inputs", "MIXED INPUTS", "alert:input_splice"],
]


## The annunciator window an item lights ("" for none: decisions, news).
static func window_kind_for(item_id: String) -> String:
	for w: Array in WINDOWS:
		if item_id == str(w[2]) or (str(w[2]).ends_with(":") and item_id.begins_with(str(w[2]))):
			return str(w[0])
	return ""


## Whether a kind of alert has been silenced for the rest of the game.
func is_silenced(kind: String) -> bool:
	return _silenced_windows.has(kind)


## Each window as the items light it: {kind, legend, tone ("bad" red, "warn" amber, "ok" green for
## information, "" dark), count (the places its rows name, 0 for none shown), items (the item ids)}.
## The pen's lamp and the panel read the same, so they cannot disagree.
func alert_windows() -> Array:
	var out: Array = []
	for w: Array in WINDOWS:
		var ids: Array = []
		var tone := ""
		var count := 0
		for it: Dictionary in _items:
			var id := str(it.get("id", ""))
			if not (id == str(w[2]) or (str(w[2]).ends_with(":") and id.begins_with(str(w[2])))):
				continue
			ids.append(id)
			count += (it.get("list", []) as Array).size() + int(it.get("list_more", 0))
			tone = _worse_tone(tone, _severity_tone(str(it.get("severity", "info"))))
		out.append({"kind": str(w[0]), "legend": str(w[1]), "tone": tone, "count": count, "items": ids})
	return out


## The worst tone lit on the annunciator: "bad", "warn", "ok" or "" with every window dark.
func worst_window_tone() -> String:
	var worst := ""
	for w: Dictionary in alert_windows():
		worst = _worse_tone(worst, str(w.tone))
	return worst


static func _severity_tone(severity: String) -> String:
	match severity:
		"critical": return "bad"
		"warning": return "warn"
		_: return "ok"


static func _worse_tone(a: String, b: String) -> String:
	var rank := {"": 0, "ok": 1, "warn": 2, "bad": 3}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b


## What a choice's loan covers when the cash is short, from DecisionState.loan_needed_for.
static func shortfall_line(shortfall: float) -> String:
	if float(MatchState.money) < 0.0:
		return "Cash is below zero. A loan covers the full £%.0f." % shortfall
	return "Short £%.0f. A loan covers it." % shortfall


func _item_by_id(item_id: String) -> Dictionary:
	for it in _items:
		if str(it.id) == item_id:
			return it
	return {}


# ---------------------------------------------------------------------------
# Expand / collapse state machine (spec §4)
# ---------------------------------------------------------------------------

func expand(item_id: String = "") -> void:
	if DecisionState.hide_updates:
		return
	_rebuild_items()
	_select_on_expand = item_id
	expanded = true
	_sync_ui()
	expanded_changed.emit(true)

func collapse() -> void:
	expanded = false
	_sync_ui()
	expanded_changed.emit(false)

## A critical turn auto-expands: any unresolved decision, or a critical alert that is
## NEW since the last evaluation (chronic conditions don't nag every turn).
func _on_turn_advanced(_new_turn: int) -> void:
	_rebuild_items()
	var critical := not unresolved_decisions().is_empty()
	var new_critical_alert := false
	var alert_ids := {}
	for it in critical_alerts():
		alert_ids[str(it.id)] = true
		if not _last_alert_ids.has(str(it.id)):
			new_critical_alert = true
	_last_alert_ids = alert_ids
	if enabled and (critical or new_critical_alert):
		expand()
	else:
		if _strip != null and is_instance_valid(_strip) and new_critical_alert:
			_strip.pulse()
		_sync_ui()
	items_changed.emit()

func _on_decision_drawn(_d: Dictionary) -> void:
	# A decision reaching the board makes the turn critical immediately (story beats
	# and cheats draw mid-DECIDE) — expand right away rather than waiting a turn.
	if enabled and not TurnManager.is_resolving:
		_rebuild_items()
		expand()
		items_changed.emit()

func _on_commit_blocked() -> void:
	# The player tried to end the turn with decisions outstanding: expand + flash.
	if not enabled:
		return
	_rebuild_items()
	expand()
	if _panel != null and is_instance_valid(_panel):
		_panel.flash()

func _on_match_loaded() -> void:
	_rebuild_items()
	if enabled and not unresolved_decisions().is_empty():
		expand()
	else:
		_sync_ui()
	items_changed.emit()

func _queue_refresh(_a: Variant = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	_rebuild_items()
	_sync_ui()
	items_changed.emit()


# ---------------------------------------------------------------------------
# UI mounting (strip + panel live on one CanvasLayer)
# ---------------------------------------------------------------------------

func _sync_ui() -> void:
	if DecisionState.hide_updates:
		expanded = false
		if is_instance_valid(_strip):
			_strip.hide()
		if is_instance_valid(_panel):
			_panel.hide()
		return
	if not enabled or DisplayServer.get_name() == "headless":
		return
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 120
		add_child(_layer)
		_strip = StripScript.new()
		_layer.add_child(_strip)
	if _panel == null or not is_instance_valid(_panel):
		_panel = panel_script().new()
		_layer.add_child(_panel)
	# Today's panel has nothing to show when empty; the DS2 panel still says the turn can end and
	# shows the annunciator dark, so the pen opens it either way.
	if _items.is_empty() and not UiPrefs.use_briefing_ds2:
		expanded = false
	_strip.visible = strip_enabled and not expanded and not _items.is_empty()
	if _strip.visible:
		_strip.refresh()
	if expanded and (not _items.is_empty() or UiPrefs.use_briefing_ds2):
		_panel.open(_select_on_expand)
		_select_on_expand = ""
	else:
		_panel.visible = false


## The panel the briefing shows: the DS2 clipboard with UiPrefs.use_briefing_ds2 on, today's otherwise.
static func panel_script() -> GDScript:
	return PanelDs2Script if UiPrefs.use_briefing_ds2 else PanelScript


## The switch flipped: the open panel is replaced by the other look, open on the same state.
func _on_ds2_changed(_on: bool) -> void:
	if _panel != null and is_instance_valid(_panel):
		var was_open := expanded
		expanded = false   # the old panel's hide must not read as the player closing it
		_panel.visible = false
		_panel.get_parent().remove_child(_panel)
		_panel.queue_free()
		_panel = null
		expanded = was_open
	_sync_ui()


# ---------------------------------------------------------------------------
# Save / load — the dismissal signatures and the silenced kinds persist (additive keys, tolerant).
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	return {"alert_dismissed": _alert_dismissed.duplicate(true), "silenced_windows": _silenced_windows.duplicate(true)}

func import_state(d: Dictionary) -> void:
	_alert_dismissed = (d.get("alert_dismissed", {}) as Dictionary).duplicate(true)
	# Saves from before permanent silencing have none: every alert can still light.
	_silenced_windows = (d.get("silenced_windows", {}) as Dictionary).duplicate(true)
	_queue_refresh()
