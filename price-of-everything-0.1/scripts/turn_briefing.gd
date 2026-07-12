extends Node
## TurnBriefing: the turn-start digest (docs/turn-briefing-panel-spec.md).
##
## One surface for everything the player must act on this turn — the decision queue,
## live critical states (bankruptcy runway, starved buildings), news announcements and
## info updates — shown either as the collapsed ~300x50 strip centred under the top bar
## or as the expanded mid-screen panel. Owner rulings: decisions can NOT be dismissed
## (resolve-only; they block End Turn via the commit_turn guard), everything else can;
## the panel auto-expands only on CRITICAL turns (an unresolved decision, or a new /
## newly-worsened critical alert) and otherwise stays collapsed.
##
## This autoload is a VIEW over DecisionState / EventScheduler / SolvencyState /
## Production — it owns no sim state beyond dismissal signatures for the live alerts
## (so a dismissed alert re-surfaces only if the condition worsens).

const StripScript := preload("res://scripts/turn_briefing_strip.gd")
const PanelScript := preload("res://scripts/turn_briefing_panel.gd")

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

signal items_changed()
signal expanded_changed(expanded: bool)

var enabled: bool = false
var expanded: bool = false

var _items: Array = []                 # assembled BriefingItem dicts (view objects)
var _alert_dismissed: Dictionary = {}  # alert_id -> magnitude at dismissal (persisted)
var _acked: Dictionary = {}            # event id -> true (session-scoped ack for news)
var _last_alert_ids: Dictionary = {}   # alert ids present last evaluation (new-alert detect)
var _layer: CanvasLayer = null
var _strip: Control = null
## Top Bar v2 replaces the collapsed strip with its Briefing module; the bar
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
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.commit_blocked_by_decisions.connect(_on_commit_blocked)
	MatchState.money_changed.connect(_queue_refresh)
	LoanState.loans_updated.connect(_queue_refresh)
	SaveLoad.match_loaded.connect(_on_match_loaded)

func reset() -> void:
	_alert_dismissed.clear()
	_acked.clear()
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
	# 1. Decisions — queue order; blocking; never dismissible (owner ruling).
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
	# 2. Live critical states (self-clearing; dismiss = quiet until worsened).
	var bankruptcy := _bankruptcy_item()
	if not bankruptcy.is_empty():
		out.append(bankruptcy)
	var starved := _starved_item()
	if not starved.is_empty():
		out.append(starved)
	var overflow := _storage_full_item()
	if not overflow.is_empty():
		out.append(overflow)
	var undersized := _storage_undersized_item()
	if not undersized.is_empty():
		out.append(undersized)
	var cash_short := _input_cash_short_item()
	if not cash_short.is_empty():
		out.append(cash_short)
	var spliced := _input_splice_item()
	if not spliced.is_empty():
		out.append(spliced)
	# 3+4. Bell events mapped into alerts / news / info (single source of truth:
	# dismissing here dismisses in the bell too). Only the LATEST turn's events show —
	# the briefing is a turn digest, not a running log (that's the bell's job).
	# Resolution-phase events are stamped current_turn-1; post-resolution ones (bridge
	# loan) the current turn — so the window is [current_turn-1, current_turn].
	var min_turn: int = maxi(1, int(TurnManager.current_turn) - 1)
	for ev: Dictionary in EventScheduler.active_events():
		if int(ev.get("turn_fired", 0)) < min_turn:
			continue
		var item := _event_item(ev)
		if not item.is_empty():
			out.append(item)
	# Order: decisions, then alerts by severity, then news, then info (newest first).
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
		"title": "Bankruptcy looming", "icon": "warn",
		"body": "Cash plus remaining borrowing capacity is nearly exhausted. A shortfall can no longer be bridged past this — if money and credit run out while profit stays negative, the company fails.",
		"rows": [
			["Cash on hand", "£%.0f" % MatchState.money, "bad" if MatchState.money < 0.0 else ""],
			["Borrowing capacity left", "£%.0f" % LoanState.available_capacity(), ""],
			["Net last turn", "%s£%.0f" % ["+" if net >= 0.0 else "−", absf(net)], "bad" if net < 0.0 else "ok"],
			["Runway", "£%.0f" % runway, "bad"],
		],
	}

# N buildings starved (power vs inputs), with deep-link rows to the worst offenders.
func _starved_item() -> Dictionary:
	var power_starved: Array = []
	var input_starved: Array = []
	for iid in Production.missing_by_building.keys():
		var b: Dictionary = MatchState.get_building(str(iid))
		if b.is_empty() or not MatchState.is_player_owned(b):
			continue
		var lacks_power := false
		var missing: Array = Production.missing_by_building[iid]
		for m in missing:
			if str((m as Dictionary).get("internal_name", "")) == "power":
				lacks_power = true
		var why := "no power" if lacks_power else "missing " + ", ".join(PackedStringArray(
			missing.map(func(m) -> String: return str((m as Dictionary).get("internal_name", "?")))))
		var row := {"instance_id": str(iid), "tile_id": str(b.get("tile_id", "")), "why": why}
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
	return {
		"id": "alert:starved", "kind": "critical", "section": "alerts",
		"severity": "critical" if not power_starved.is_empty() else "warning",
		"dismissible": true, "magnitude": total, "icon": "box",
		"title": "%d building%s starved" % [total, "" if total == 1 else "s"],
		"body": "Starved buildings ran nothing this turn but still pay maintenance%s." % \
			(" — %d lack power, %d are missing inputs" % [power_starved.size(), input_starved.size()] if power_starved.size() > 0 and input_starved.size() > 0 else ""),
		"rows": [
			["Starved of power", "%d building%s" % [power_starved.size(), "" if power_starved.size() == 1 else "s"], "bad" if power_starved.size() > 0 else ""],
			["Starved of inputs", "%d building%s" % [input_starved.size(), "" if input_starved.size() == 1 else "s"], "warn" if input_starved.size() > 0 else ""],
		],
		"list": listed,
		"list_more": maxi(0, total - listed.size()),
	}

## Tile storage full: arrived shipments waiting in overflow-hold (they retry each
## turn but occupy no stockpile until space frees) and/or pipeline orders clipped
## because the tile can't physically hold its input buffers. This was THE silent
## deadlock diagnosed 2026-07-09: a jammed tile starves its buildings while goods
## bounce outside. Fix: sell surplus, expand the warehouse, or spread buildings.
func _storage_full_item() -> Dictionary:
	var held_by_tile: Dictionary = {}   # tile_id -> units waiting
	var held_total := 0
	for r in MatchState.overflow_shipments:
		var tile := str(r.get("destination_tile", ""))
		var qty := int(r.get("qty", 0))
		held_by_tile[tile] = int(held_by_tile.get(tile, 0)) + qty
		held_total += qty
	var capped: Array = Production.last_turn_summary.get("input_orders_capped", [])
	var capped_units := 0
	var capped_tiles: Dictionary = {}
	for c in capped:
		var d: Dictionary = c
		capped_units += int(d.get("wanted", 0)) - int(d.get("placed", 0))
		capped_tiles[str(d.get("tile_id", ""))] = true
	if held_total == 0 and capped_units == 0:
		_alert_dismissed.erase("alert:storage_full")
		return {}
	var magnitude := held_total + capped_units
	if _alert_dismissed.has("alert:storage_full") and magnitude <= int(_alert_dismissed["alert:storage_full"]):
		return {}
	var listed: Array = []
	for tile in held_by_tile:
		if listed.size() >= STARVED_LIST_ROWS:
			break
		listed.append({
			"instance_id": "", "tile_id": str(tile),
			"why": "%d unit%s waiting to unload" % [int(held_by_tile[tile]), "" if int(held_by_tile[tile]) == 1 else "s"],
		})
	for tile2 in capped_tiles:
		if listed.size() >= STARVED_LIST_ROWS or held_by_tile.has(tile2):
			continue
		listed.append({"instance_id": "", "tile_id": str(tile2), "why": "input orders reduced to fit storage"})
	var tiles_affected: Dictionary = capped_tiles.duplicate()
	for tile3 in held_by_tile:
		tiles_affected[tile3] = true
	return {
		"id": "alert:storage_full", "kind": "critical", "section": "alerts",
		"severity": "critical" if held_total > 0 else "warning",
		"dismissible": true, "magnitude": magnitude, "icon": "gauge",
		"title": "Storage full on %d tile%s" % [tiles_affected.size(), "" if tiles_affected.size() == 1 else "s"],
		"body": "Deliveries can't unload into a full stockpile — they wait outside and retry each turn while buildings starve. Free space (sell surplus, move goods) or expand the warehouse from the tile's Stockpile tab.",
		"rows": [
			["Goods waiting to unload", "%d unit%s" % [held_total, "" if held_total == 1 else "s"], "bad" if held_total > 0 else ""],
			["Orders reduced to fit storage", "%d unit%s" % [capped_units, "" if capped_units == 1 else "s"], "warn" if capped_units > 0 else ""],
		],
		"list": listed,
		"list_more": maxi(0, tiles_affected.size() - listed.size()),
	}

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
				"why": "needs ≈%d, holds %d" % [int(d.get("required", 0)), int(d.get("capacity", 0))],
			})
	if _alert_dismissed.has("alert:storage_undersized") and shortfall <= int(_alert_dismissed["alert:storage_undersized"]):
		return {}
	var first_tile := str((rows[0] as Dictionary).get("tile_id", ""))
	var title := "%s lacks stockpile for its buildings" % _tile_display(first_tile) if rows.size() == 1 \
		else "%d tiles lack stockpile for their buildings" % rows.size()
	var body := "%s lacks the stockpile to support all the inputs and outputs for its buildings." % _tile_display(first_tile) if rows.size() == 1 \
		else "These tiles lack the stockpile to support all the inputs and outputs of their buildings."
	return {
		"id": "alert:storage_undersized", "kind": "critical", "section": "alerts",
		"severity": "critical", "dismissible": true, "magnitude": shortfall, "icon": "box",
		"title": title,
		"body": body + " Input buffers, local intermediates and outputs need more room than the warehouse holds, so deliveries will jam. Expand the warehouse (Stockpile tab), enable Sell all Surplus, or split the chain across tiles.",
		"rows": [
			["Working set over capacity", "%d unit%s" % [shortfall, "" if shortfall == 1 else "s"], "bad"],
			["Tiles affected", "%d" % rows.size(), ""],
		],
		"list": listed,
		"list_more": maxi(0, rows.size() - listed.size()),
	}

func _tile_display(tile_id: String) -> String:
	var label := str(Catalog.tile_name(tile_id))
	return label if label != "" else tile_id

## Input orders the market pipeline could not fully place for CASH last turn
## (Production.last_turn_summary.input_orders_short). Silent before 2026-07-09:
## a remote building's (lead+1)-turn pipeline order was clipped or skipped and
## the player only saw the starvation days later.
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
				"instance_id": "", "tile_id": str(d.get("tile_id", "")),
				"why": "%s ×%d of %d bought" % [Catalog.get_display_name(str(d.get("good_id", ""))),
					int(d.get("bought", 0)), int(d.get("requested", 0))],
			})
	if _alert_dismissed.has("alert:input_cash") and short.size() <= int(_alert_dismissed["alert:input_cash"]):
		return {}
	return {
		"id": "alert:input_cash", "kind": "critical", "section": "alerts",
		"severity": "critical" if skipped > 0 else "warning",
		"dismissible": true, "magnitude": short.size(), "icon": "coin",
		"title": "%d input order%s short on cash" % [short.size(), "" if short.size() == 1 else "s"],
		"body": "The market pipeline couldn't afford full input orders — remote tiles need (transport lead + 1) turns of inputs as working capital. Buildings will starve when the shortfall reaches them (≈£%d more needed)." % int(ceil(short_cost)),
		"rows": [
			["Orders skipped entirely", "%d" % skipped, "bad" if skipped > 0 else ""],
			["Extra cash needed", "£%d" % int(ceil(short_cost)), "warn"],
		],
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
			"instance_id": "", "tile_id": str(d.get("tile_id", "")),
			"why": "%s: %d/turn local + %d/turn market" % [Catalog.get_display_name(str(d.get("good_id", ""))),
				int(d.get("local", 0)), int(d.get("market", 0))],
		})
	return {
		"id": "alert:input_splice", "kind": "info", "section": "info",
		"severity": "info",
		"dismissible": true, "magnitude": splices.size(), "icon": "truck",
		"title": "%d input%s spliced: local production + market" % [splices.size(), "" if splices.size() == 1 else "s"],
		"body": "These inputs are partly covered by same-tile production, with the market topping up the rest. If local output dips, the top-up takes the full transport lead to catch up.",
		"rows": [],
		"list": listed,
		"list_more": maxi(0, splices.size() - listed.size()),
	}

# Map a bell event into a briefing item. Kind → section; the bell stays the log.
# "" = not shown in the briefing (still in the bell).
const _EVENT_SECTIONS := {
	"research_unlocked": "info",
	"construction_completed": "info",
	"decision_resolved": "info",
	"decision_incoming": "info",
	"bridge_loan": "info",
	"deposit_exhausted": "alerts",
	"tile_at_capacity": "alerts",
	"sales_aggregate": "",        # too noisy for the briefing — bell only
	"bankruptcy_warning": "",     # superseded by the live runway alert
	"building_starved": "",       # superseded by the aggregated live alert
	"policy_enacted": "news",     # CO2 tax / green subsidy now in effect (PolicyState)
	"forewarn": "news",           # "coming in N turns" advance notice of a scheduled event
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
	"deposit_exhausted": "warn",
	"tile_at_capacity": "gauge",
	"policy_enacted": "scale",
	"forewarn": "flag",
	"advisor_tip": "users",
}

func _event_item(ev: Dictionary) -> Dictionary:
	var kind := str(ev.get("kind", ""))
	var section: String = str(_EVENT_SECTIONS.get(kind, "news"))
	if section == "":
		return {}
	return {
		"id": "ev:%s" % str(ev.id), "kind": "event", "event_kind": kind, "section": section,
		"severity": str(ev.get("severity", "info")),
		"dismissible": true, "event_id": str(ev.id),
		"icon": str(_EVENT_ICONS.get(kind, "flag")),
		"title": str(ev.get("title", "")),
		"body": str(ev.get("body", "")),
		"deeplink": ev.get("deeplink", {}),
		"acked": _acked.has(str(ev.id)),
		"ackable": section == "news",
	}


# ---------------------------------------------------------------------------
# Player actions (the panel calls these; sim mutations go through the sources).
# ---------------------------------------------------------------------------

func dismiss(item_id: String) -> void:
	var item := _item_by_id(item_id)
	if item.is_empty() or not bool(item.get("dismissible", false)):
		return   # decisions land here too — never dismissible (owner ruling)
	if item.has("magnitude"):
		_alert_dismissed[item_id] = item.magnitude   # quiet until it worsens
	elif item.has("event_id"):
		EventScheduler.dismiss(str(item.event_id))   # bell syncs (one source of truth)
	_queue_refresh()

func acknowledge(item_id: String) -> void:
	var item := _item_by_id(item_id)
	if not item.is_empty() and item.has("event_id"):
		_acked[str(item.event_id)] = true
		_queue_refresh()

func _item_by_id(item_id: String) -> Dictionary:
	for it in _items:
		if str(it.id) == item_id:
			return it
	return {}


# ---------------------------------------------------------------------------
# Expand / collapse state machine (spec §4)
# ---------------------------------------------------------------------------

func expand(item_id: String = "") -> void:
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
	if not enabled or DisplayServer.get_name() == "headless":
		return
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 120
		add_child(_layer)
		_strip = StripScript.new()
		_layer.add_child(_strip)
		_panel = PanelScript.new()
		_layer.add_child(_panel)
	if _items.is_empty():
		expanded = false
	_strip.visible = strip_enabled and not expanded and not _items.is_empty()
	if _strip.visible:
		_strip.refresh()
	if expanded and not _items.is_empty():
		_panel.open(_select_on_expand)
		_select_on_expand = ""
	else:
		_panel.visible = false


# ---------------------------------------------------------------------------
# Save / load — only the dismissal signatures persist (additive key, tolerant).
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	return {"alert_dismissed": _alert_dismissed.duplicate(true)}

func import_state(d: Dictionary) -> void:
	_alert_dismissed = (d.get("alert_dismissed", {}) as Dictionary).duplicate(true)
	_acked.clear()
	_queue_refresh()
