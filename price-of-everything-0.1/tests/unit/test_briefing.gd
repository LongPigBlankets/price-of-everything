extends "res://tests/test_base.gd"
## The turn briefing: the owner's rulings (one way to close it, one-off news to the updates dock, a full tile on the
## top bar's storage lamp only, the dock's timing) and its DS2 look behind UiPrefs.use_briefing_ds2
## (docs/briefing-ds2-plan.md).

const FEATURE := "briefing"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_briefing_ds2_switch": ["briefing", "ui"],
	"_test_briefing_one_close_path": ["briefing", "ui"],
	"_test_updates_dock_timing_rule": ["briefing", "ui"],
	"_test_tile_jam_on_storage_lamp_only": ["briefing", "stockpile", "transport", "events"],
	"_test_one_off_news_goes_to_the_dock": ["briefing", "events"],
	"_test_choice_figures_match_the_effects": ["briefing", "decisions"],
	"_test_briefing_ds2_panel": ["briefing", "decisions", "ui"],
	"_test_briefing_copy": ["briefing", "decisions"],
}

const DS2_SCRIPT := "res://scripts/briefing_ds2/briefing_ds2.gd"
const OLD_SCRIPT := "res://scripts/turn_briefing_panel.gd"


## A founder decision waiting and one building starved of inputs, as TurnBriefing assembles them.
func _seed_board() -> Dictionary:
	var snap := _decision_board_snapshot()
	snap["missing"] = Production.missing_by_building.duplicate(true)
	snap["summary"] = Production.last_turn_summary
	Production.last_turn_summary = {}
	MatchState.money = 100000.0
	DecisionState.reset()
	TurnBriefing.reset()
	DecisionState.pending_queue = [{"uid": "tb_f1", "def_id": "family_friend",
		"target": {"scope": "company", "name": "the company"}, "turn_drawn": 3}]
	BuildingState.buildings["tb_ds2_starved"] = {"instance_id": "tb_ds2_starved", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_10_3", "owner": MatchState.LOCAL_PLAYER}
	Production.missing_by_building = {"tb_ds2_starved": [{"internal_name": "coal"}]}
	TurnBriefing._rebuild_items()
	return snap


func _restore_board(snap: Dictionary) -> void:
	BuildingState.buildings.erase("tb_ds2_starved")
	Production.missing_by_building = snap["missing"]
	Production.last_turn_summary = snap["summary"]
	DecisionState.pending_queue = []
	TurnBriefing.reset()
	_decision_board_restore(snap)


## The DS2 clipboard is the default (owner, 29 September); switched off, TurnBriefing shows today's panel; on
## again, the clipboard.
func _test_briefing_ds2_switch() -> void:
	var was: bool = UiPrefs.use_briefing_ds2
	_check(was, "briefing ds2: on by default")
	UiPrefs.set_use_briefing_ds2(false)
	_check(TurnBriefing.panel_script().resource_path == OLD_SCRIPT, "briefing ds2: switched off, today's panel")
	UiPrefs.set_use_briefing_ds2(true)
	_check(TurnBriefing.panel_script().resource_path == DS2_SCRIPT, "briefing ds2: on, the DS2 panel")
	UiPrefs.set_use_briefing_ds2(false)
	_check(TurnBriefing.panel_script().resource_path == OLD_SCRIPT, "briefing ds2: off again, today's panel back")
	var snap := _seed_board()
	var old: Control = load(OLD_SCRIPT).new()
	add_child(old)
	await get_tree().process_frame
	old.open("")
	await get_tree().process_frame
	_check(old.get("_card") != null and old.find_child("Card", true, false) == null,
		"briefing ds2: off, today's navy card with its list and detail")
	_check(_tree_has_label_text(old, "This Turn") and old.find_child("Letter", true, false) == null,
		"briefing ds2: off, today's title and no clipboard")
	old.visible = false
	old.queue_free()
	_restore_board(snap)
	UiPrefs.set_use_briefing_ds2(was)
	await get_tree().process_frame


## Exactly one way to close the panel with the mouse, its Close key, in both looks; the pen only opens it.
func _test_briefing_one_close_path() -> void:
	var snap := _seed_board()
	for path: String in [OLD_SCRIPT, DS2_SCRIPT]:
		var panel: Control = load(path).new()
		add_child(panel)
		await get_tree().process_frame
		panel.open("alert:starved")
		await get_tree().process_frame
		await get_tree().process_frame
		var closers: Array = []
		for b: Node in panel.find_children("*", "BaseButton", true, false):
			var words := str(b.get("text")) + " " + str(b.get("title")) + " " + str((b as Control).tooltip_text)
			if b.name == "CloseKey" or words.contains("Collapse") or words.contains("Close") \
					or words.contains("▴") or words.contains("✕") or words.contains("Dismiss"):
				closers.append(str(b.name))
		_check(closers == ["CloseKey"], "%s: one way to close, the Close key (%s)" % [path.get_file(), ", ".join(closers)])
		var silence := panel.find_child("SilenceKey", true, false)
		_check(silence != null and (str(silence.get("text")) + str(silence.get("title"))).contains("Silence alert"),
			"%s: quieting an alert is labelled Silence alert, not a close" % path.get_file())
		panel.visible = false
		panel.queue_free()
		await get_tree().process_frame
	# The pen only opens the briefing: pressed again with it up, it stays up.
	var toasts: Control = load("res://scripts/toast_manager.gd").new()
	add_child(toasts)
	await get_tree().process_frame
	var saved_hide: bool = DecisionState.hide_updates
	DecisionState.hide_updates = false
	TurnBriefing.expanded = true
	toasts.call("_open_decisions")
	_check(TurnBriefing.expanded, "updates dock: the pen with the briefing up leaves it up")
	TurnBriefing.expanded = false
	DecisionState.hide_updates = saved_hide
	toasts.queue_free()
	_restore_board(snap)


## Rows are timed only when they first appear; opened by the player, the slide-out stays until a click lands
## outside it and the dock. Clicks on the rows, the dock, its bells or its pen leave it open.
func _test_updates_dock_timing_rule() -> void:
	var toasts: Control = load("res://scripts/toast_manager.gd").new()
	add_child(toasts)
	await get_tree().process_frame
	var saved_hide: bool = DecisionState.hide_updates
	DecisionState.hide_updates = false
	var clicked := [0]
	toasts._on_toast_requested("Built a steel furnace", "success")
	_check(toasts.is_open() and not toasts._timer.is_stopped(), "updates timing: a new row shows timed")
	toasts._on_timer()
	_check(not toasts.is_open(), "updates timing: the first showing runs out")
	toasts.push_row("Unlocked: Test", "green", "tb_link", func() -> void: clicked[0] += 1, true)
	toasts.collapse(false)
	toasts.open_all()
	_check(toasts.is_open() and toasts._timer.is_stopped() and toasts.countdown() == 0.0,
		"updates timing: opened by the player, no timer and no countdown")
	toasts._on_timer()
	_check(toasts.is_open(), "updates timing: opened by the player, time never closes it")
	toasts._on_toast_requested("Ordered 5 Steel", "success")
	_check(toasts.is_open() and toasts._timer.is_stopped(), "updates timing: a row arriving while it is open starts no timer")
	var press := func(at: Vector2) -> void:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.global_position = at
		mb.position = at
		toasts.call("_input", mb)
	var dock: Control = toasts.find_child("UpdatesDock", true, false)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	press.call(dock.get_global_rect().get_center())
	_check(toasts.is_open(), "updates timing: a click on the dock leaves it open")
	var pen: Control = toasts.find_child("Decisions", true, false)
	press.call(pen.get_global_rect().get_center())
	_check(toasts.is_open(), "updates timing: a click on the pen leaves it open")
	var link: Control = null
	for r: Node in toasts.find_child("RowList", true, false).get_children():
		if str(r.get_meta("key", "")) == "tb_link":
			link = r
	press.call(link.get_global_rect().get_center())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	toasts.call("_on_row_input", click, link)
	_check(toasts.is_open() and clicked[0] == 1, "updates timing: a click on a row runs it and leaves the rows open")
	toasts.find_child("Bell_green", true, false).gui_input.emit(click)
	toasts.find_child("Bell_green", true, false).gui_input.emit(click)
	_check(toasts.is_open() and toasts.filter() == "green", "updates timing: the same bell twice leaves its rows open")
	var vp := toasts.get_viewport_rect().size
	press.call(Vector2(vp.x * 0.75, vp.y * 0.3))
	_check(not toasts.is_open(), "updates timing: a click anywhere else puts the rows away")
	DecisionState.hide_updates = saved_hide
	toasts.queue_free()


## A full tile is shown by the top bar's storage lamp only: no briefing item, no dock row, no dialog.
func _test_tile_jam_on_storage_lamp_only() -> void:
	const Status := preload("res://scripts/top_bar_status.gd")
	var snap := _decision_board_snapshot()
	var saved_summary: Dictionary = Production.last_turn_summary
	var saved_overflow: Array = TransportState.overflow_shipments.duplicate(true)
	EventScheduler.reset()
	TurnBriefing.reset()
	var toasts: Array = []
	var on_toast := func(m: String, _t: String) -> void: toasts.append(m)
	MatchState.toast_requested.connect(on_toast)
	var t := "tile_5_5"
	TransportState.overflow_shipments = [{"destination_tile": t, "qty": 40}]
	Production.last_turn_summary = {"input_orders_capped": [{"tile_id": t, "wanted": 50, "placed": 20}]}
	EventScheduler._on_tile_reached_capacity(t)
	TurnBriefing._rebuild_items()
	var jam_items := TurnBriefing.items().filter(func(it) -> bool:
		var id := str((it as Dictionary).get("id", ""))
		return id.contains("storage_full") or id.contains("capacity"))
	_check(jam_items.is_empty(), "tile jam: no briefing item for a full tile or its waiting goods")
	_check(toasts.is_empty(), "tile jam: no dock row for a tile at capacity (%s)" % ", ".join(toasts))
	var storage: Dictionary = Status.transport().storage
	_check(Status.lit(storage), "tile jam: input orders cut to fit storage light the storage lamp (%s)" % str(storage.name))
	_check(Status.transport().freight.tone == "bad", "tile jam: goods waiting to unload light the freight lamp")
	Production.last_turn_summary = {}
	TransportState.overflow_shipments = []
	var gid := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var cap: int = Stockpile.get_capacity(t)
	var before: int = Stockpile.get_at_tile(t, gid)
	var room: int = cap - Stockpile.get_used_capacity(t)
	Stockpile.add(t, gid, room)
	var full: Dictionary = Status.transport().storage
	_check(full.tone == "bad" and str(full.name) == "Storage full", "tile jam: a tile at capacity lights the storage lamp red")
	Stockpile.consume(t, gid, Stockpile.get_at_tile(t, gid) - before)
	var world_map := FileAccess.get_file_as_string("res://scripts/world_map.gd")
	_check(not world_map.contains("capacity_dialog.gd\").new()"), "tile jam: the capacity dialog is not mounted")
	MatchState.toast_requested.disconnect(on_toast)
	Production.last_turn_summary = saved_summary
	TransportState.overflow_shipments = saved_overflow
	EventScheduler.reset()
	TurnBriefing.reset()
	_decision_board_restore(snap)


## One-off news is a dock row, once, and never a briefing item; a deposit running dry stays a live alert.
func _test_one_off_news_goes_to_the_dock() -> void:
	var snap := _decision_board_snapshot()
	EventScheduler.reset()
	TurnBriefing.reset()
	var toasts: Array = []
	var on_toast := func(m: String, ty: String) -> void: toasts.append([m, ty])
	MatchState.toast_requested.connect(on_toast)
	EventScheduler.emit_event({"id": "tb_news", "kind": "policy_enacted", "severity": "warning",
		"title": "Markets Party wins the election", "body": "It plans changes to energy policy.", "persistent": true})
	EventScheduler.emit_event({"id": "tb_res", "kind": "research_unlocked", "title": "Unlocked: Test",
		"body": "x", "persistent": false, "research_name": "Test", "research_reward": "R", "research_condition": "C"})
	EventScheduler.emit_event({"id": "tb_done", "kind": "decision_resolved", "title": "Decision: X", "body": "Y"})
	EventScheduler.emit_event({"id": "deposit_exhausted:tile_7_7:coal", "kind": "deposit_exhausted",
		"severity": "critical", "title": "Coal deposit exhausted", "body": "Mining has stopped.", "token": "coal",
		"deeplink": {"panel": "tile", "tile_id": "tile_7_7"}})
	TurnBriefing._rebuild_items()
	var ids: Array = TurnBriefing.items().map(func(it) -> String: return str((it as Dictionary).id))
	_check(not ids.has("ev:tb_news") and not ids.has("ev:tb_res") and not ids.has("ev:tb_done")
		and not ids.has("research_unlocked_agg"), "one-off news: no briefing item for news, research or an answered decision")
	_check(toasts.size() == 1 and str(toasts[0][0]) == "Markets Party wins the election. It plans changes to energy policy."
		and str(toasts[0][1]) == "caution", "one-off news: the news is one amber dock row, title then body")
	_check(TurnBriefing.recent_research().size() == 1 and str(TurnBriefing.recent_research()[0].name) == "Test",
		"one-off news: the top bar reads the research to post it")
	_check(ids.has("ev:deposit_exhausted:tile_7_7:coal"), "one-off news: a deposit exhausted stays a live alert")
	var out: Dictionary = {}
	for w: Dictionary in TurnBriefing.alert_windows():
		if str(w.kind) == "deposit_out":
			out = w
	_check(str(out.get("tone", "")) == "bad" and int(out.get("count", 0)) == 1, "one-off news: it lights the DEPOSIT OUT window")
	TurnBriefing.dismiss("ev:deposit_exhausted:tile_7_7:coal")
	_check(not EventScheduler._active.has("deposit_exhausted:tile_7_7:coal"), "silencing it clears it in the bell too")
	MatchState.toast_requested.disconnect(on_toast)
	EventScheduler.reset()
	TurnBriefing.reset()
	_decision_board_restore(snap)


## A choice's screens read the same effects resolve applies: the founder's CFO chair brings a £200 loan at 5%, his
## COO chair 1000 freight units, the licence costs £150; the words carry only what has no figure.
func _test_choice_figures_match_the_effects() -> void:
	var t := {"scope": "company", "name": "the company"}
	var cfo: Array = DecisionState.choice_figures("family_friend", "cfo", t)
	_check(cfo.size() == 1 and str(cfo[0].kind) == "loan" and is_equal_approx(float(cfo[0].value), 200.0)
		and is_equal_approx(float(cfo[0].rate), 0.05) and str(cfo[0].caption) == "Loan at 5%",
		"choice figures: the CFO chair is a £200 loan at 5%")
	var coo: Array = DecisionState.choice_figures("family_friend", "coo", t)
	_check(coo.size() == 1 and str(coo[0].kind) == "units" and int(coo[0].value) == 1000,
		"choice figures: the COO chair is 1000 freight units")
	var lic: Array = DecisionState.choice_figures("government_import_export_license", "understood", t)
	_check(lic.size() == 1 and str(lic[0].kind) == "cost" and is_equal_approx(float(lic[0].value), 150.0),
		"choice figures: the licence costs £150")
	var ok := true
	for def_id: String in DecisionState.DECISION_DEFINITIONS:
		for choice: Dictionary in (DecisionState.DECISION_DEFINITIONS[def_id] as Dictionary).get("choices", []):
			for f: Dictionary in DecisionState.choice_figures(def_id, str(choice.id), t):
				var found := false
				for eff: Dictionary in choice.get("effects", []):
					var v := float(eff.get("amount", eff.get("units", eff.get("turns", NAN))))
					if absf(v) == absf(float(f.value)) or str(eff.get("kind", "")) in ["sell_land", "cash"]:
						found = true
				ok = ok and found
	_check(ok, "choice figures: every figure is an effect's own amount")
	var words: Array = DecisionState.choice_words("family_friend", "cfo", t)
	_check(words == ["The CFO's chair for 30 turns, unpaid."], "choice words: the seat in words, the loan left to its screen (%s)" % str(words))


## The DS2 panel: one width, the letter and its answer keys, figures on screens, the annunciator's eight windows,
## the readout shut while a decision waits and a picked window's detail.
func _test_briefing_ds2_panel() -> void:
	var snap := _seed_board()
	var panel: Control = load(DS2_SCRIPT).new()
	add_child(panel)
	await get_tree().process_frame
	panel.open("")
	for _i in 3:
		await get_tree().process_frame
	var card: Control = panel.call("card")
	var vp := panel.get_viewport_rect().size
	_check(is_equal_approx(card.size.x, minf(540.0, vp.x - 32.0)), "briefing ds2: one width, 540")
	_check(card.position.y >= 72.0 and card.get_rect().end.y <= vp.y, "briefing ds2: under the top bar, on the screen")
	_check(absf(card.get_rect().get_center().x - vp.x * 0.5) <= 1.0, "briefing ds2: in the middle of the screen")
	var title: Label = panel.find_child("LetterTitle", true, false)
	var count: Label = panel.find_child("LetterCount", true, false)
	_check(title != null and title.text == "A Retired Man Who Misses the Work" and count != null and count.text == "1 of 1",
		"briefing ds2: the decision is a letter, 1 of 1")
	var cfo: Node = panel.find_child("Answer_cfo", true, false)
	var coo: Node = panel.find_child("Answer_coo", true, false)
	_check(cfo is Button and coo is Button and str(cfo.get("title")) == "Give him the CFO's chair",
		"briefing ds2: each choice is a cream key with its label")
	var cfo_row: Node = panel.find_child("Choice_cfo", true, false)
	var led: Node = cfo_row.find_child("Led", true, false) if cfo_row != null else null
	_check(led != null and str(led.call("figure")).strip_edges() == "200.0", "briefing ds2: the CFO's loan on an LED screen, 200.0")
	var coo_row: Node = panel.find_child("Choice_coo", true, false)
	_check(coo_row != null and coo_row.find_child("Drum", true, false) != null, "briefing ds2: the COO's freight units on a drum")
	var wins: Array = panel.call("windows")
	var lit := wins.filter(func(w) -> bool: return str(w.tone) != "")
	_check(wins.size() == 8 and lit.size() == 1 and str(lit[0].kind) == "starved", "briefing ds2: eight windows, STARVED lit")
	_check(str(panel.call("picked")) == "" and panel.find_child("Readout", true, false) == null
		and panel.find_child("AnnunciatorLine", true, false) != null, "briefing ds2: with a decision waiting the readout stays shut")
	var gate: Label = panel.find_child("GateLine", true, false)
	_check(gate != null and gate.text == "Answer 1 decision before you end the turn.", "briefing ds2: the gate says the turn is blocked")
	lit[0].pressed.emit("starved")
	for _i in 3:
		await get_tree().process_frame
	var name_line: Label = panel.find_child("ReadoutName", true, false)
	var row_title: Label = panel.find_child("RowTitle", true, false)
	_check(name_line != null and name_line.text == "1 building starved" and row_title != null,
		"briefing ds2: a picked window shows its readout and its rows")
	var body: Control = panel.find_child("Body", true, false)
	_check(body.get_combined_minimum_size().x <= panel.call("body_width") + 0.5, "briefing ds2: nothing widens the body")
	panel.visible = false
	panel.queue_free()
	_restore_board(snap)
	await get_tree().process_frame


## The briefing's own words: brief and factual, no dashes, semicolons, middle dots or ellipses, no coordinates or
## tile ids, and white on the panel's navy.
func _test_briefing_copy() -> void:
	var snap := _seed_board()
	var summary_was: Dictionary = Production.last_turn_summary
	Production.last_turn_summary = {
		"storage_overcommitted": [{"tile_id": "tile_10_3", "required": 816, "capacity": 800}],
		"input_orders_short": [{"tile_id": "tile_10_3", "good_id": "g_001", "bought": 0, "requested": 20, "short_cost": 40.0}],
		"deposits_running_out": [{"tile_id": "tile_10_3", "instance_id": "", "token": "coal", "good_id": "g_001",
			"remaining": 90, "per_turn": 30, "turns_left": 3}],
		"input_splices": [{"tile_id": "tile_10_3", "good_id": "g_001", "local": 5, "market": 3}],
	}
	TurnBriefing._rebuild_items()
	var bad: Array = []
	var texts: Array = [TurnBriefing.gate_line(), TurnBriefing.SILENCE_HINT, TurnBriefing.shortfall_line(20.0)]
	for it: Dictionary in TurnBriefing.items():
		if str(it.kind) == "decision":
			for c: Dictionary in (it.view as Dictionary).choices:
				texts.append(str(c.consequence))
				texts.append_array(c.get("words", []))
			continue
		texts.append(str(it.get("title", "")))
		texts.append(str(it.get("body", "")))
		for r: Array in it.get("rows", []):
			texts.append("%s %s" % [str(r[0]), str(r[1])])
			if str(r[1]).begins_with("0 "):
				bad.append("zero row: %s" % str(r[0]))
		for e: Dictionary in it.get("list", []):
			texts.append(TurnBriefing.row_title(e) + ". " + TurnBriefing.row_detail(e))
	for s: String in texts:
		for mark in ["—", "–", " - ", ";", "·", "…", "≈", "tile_", "(1", "(2", "(3", "(4", "(5", "(6", "(7", "(8", "(9"]:
			if s.contains(mark):
				bad.append("%s in \"%s\"" % [mark, s])
	_check(bad.is_empty(), "briefing copy: plain, no dashes or coordinates (%s)" % "; ".join(bad))
	var panel: Control = load(DS2_SCRIPT).new()
	add_child(panel)
	await get_tree().process_frame
	panel.open("alert:starved")
	for _i in 3:
		await get_tree().process_frame
	var grey: Array = []
	for l: Node in panel.find_children("*", "Label", true, false):
		var c: Color = (l as Label).get_theme_color("font_color")
		if c.is_equal_approx(DS.PALETTE["TEXT_MUTED"]) or c.is_equal_approx(DS.PALETTE["TEXT_DIM"]):
			grey.append((l as Label).text)
	_check(grey.is_empty(), "briefing ds2: no grey text on the navy (%s)" % ", ".join(grey))
	panel.visible = false
	panel.queue_free()
	Production.last_turn_summary = summary_was
	_restore_board(snap)
	await get_tree().process_frame


## Silence alert turns the alert's kind off for the rest of the game (owner, 28 September): it does not come
## back when it worsens or after it clears, it survives a save, and the words beside the key say so.
func _test_silence_alert_is_for_good() -> void:
	_check(TurnBriefing.SILENCE_HINT == "This will not trigger again.", "silence: the hint says it will not trigger again")
	var saved: Dictionary = TurnBriefing.export_state()
	TurnBriefing.reset()
	_check(TurnBriefing.window_kind_for("alert:starved") == "starved" and TurnBriefing.window_kind_for("ev:deposit_exhausted:7") == "deposit_out"
		and TurnBriefing.window_kind_for("decision:abc") == "", "silence: items map to their annunciator window")
	# A starved alert, as the briefing assembles it, silenced through the player's key.
	TurnBriefing._items = [{"id": "alert:starved", "kind": "alert", "section": "alerts", "severity": "warning",
		"dismissible": true, "magnitude": 1, "list": [], "list_more": 0}]
	TurnBriefing.dismiss("alert:starved")
	_check(TurnBriefing.is_silenced("starved"), "silence: the starved kind is silenced")
	# Worse and cleared-then-back both stay dark: the silenced kind is filtered however big it gets.
	TurnBriefing._alert_dismissed.erase("alert:starved")
	var kept: Array = [{"id": "alert:starved"}, {"id": "alert:input_cash"}].filter(
		func(it) -> bool: return not TurnBriefing.is_silenced(TurnBriefing.window_kind_for(str(it.id))))
	_check(kept.size() == 1 and str(kept[0].id) == "alert:input_cash", "silence: a worse starved alert stays dark, others still light")
	var state: Dictionary = TurnBriefing.export_state()
	TurnBriefing.reset()
	TurnBriefing.import_state(state)
	_check(TurnBriefing.is_silenced("starved"), "silence: it survives a save and load")
	TurnBriefing.import_state({"alert_dismissed": {}})
	_check(not TurnBriefing.is_silenced("starved"), "silence: an older save silences nothing")
	TurnBriefing.import_state(saved)
