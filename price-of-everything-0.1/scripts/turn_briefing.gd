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
	# 2. Live critical states (self-clearing; dismiss = quiet until worsened).
	var bankruptcy := _bankruptcy_item()
	if not bankruptcy.is_empty():
		out.append(bankruptcy)
	var starved := _starved_item()
	if not starved.is_empty():
		out.append(starved)
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
}

func _event_item(ev: Dictionary) -> Dictionary:
	var kind := str(ev.get("kind", ""))
	var section: String = str(_EVENT_SECTIONS.get(kind, "news"))
	if section == "":
		return {}
	return {
		"id": "ev:%s" % str(ev.id), "kind": "event", "section": section,
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
	_strip.visible = not expanded and not _items.is_empty()
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
