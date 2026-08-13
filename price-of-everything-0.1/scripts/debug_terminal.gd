extends CanvasLayer
## In-game debug / cheat terminal. Toggle with the backtick key ( ` ); Esc closes.
## Type a command and press Enter. Add new cheats in _run_command().
##
## Every command is locked until `debug CandC` is entered (case-sensitive); before
## that, anything typed answers "invalid operation". The unlock lasts for the app
## run (static var), surviving scene reloads from the `load` cheat.
##
## Commands:
##   debug CandC                      unlock the commands below
##   cash <int>                       add that much cash (negative allowed)
##   sellmode <stockpile|market|building>  set the global production sell mode
##   logs                             toggle verbose production / CostSolver logs
##   swap tvp                         toggle between the classic and alternate Tile View Panel
##   swap bdp                         toggle to the classic v1 building-detail panel (v2 is default)
##   swap construct_panel             toggle the construct-panel redesign
##   swap loading_screen              toggle the slow pre-optimization new-game build (for recordings)
##   swap goods_graph                 toggle the legacy no-swimlane/fixed-card Goods Graph
##   swap empire view sprite          toggle the empire view sprite style (big 2.5D sprites, no backdrop)
##   swap port badge                 gold port hex on selling buildings <-> lines to the port row
##   swap empire button               toggle the Empire View button's two icon treatments
##   research all                     unlock every research node (alias of `unlock all`)
##   unlock hidden_buildings          enable the three hidden prototype buildings
##   swap song                       advance to the next music track
##   help                             list commands

const TOGGLE_KEY := KEY_QUOTELEFT  # the ` / ~ key
const UNLOCK_WORD := "CandC"  # case-sensitive pass-phrase for `debug <word>`

# In the main menu there is no match, so only commands that don't touch match state
# are allowed (`debug` runs before this gate; `swap loading_screen`/`swap song` are the
# useful ones — e.g. arm the slow-load recording before starting a game). Everything
# else would poke a not-yet-started MatchState or a missing map scene.
const MENU_SAFE_COMMANDS := {"swap": true, "help": true}
# Commands that only look at the game or change presentation, so they leave the run
# honest for telemetry. Everything else sets MatchState.cheats_used.
const READ_ONLY_COMMANDS := {
	"help": true, "logs": true, "saves": true, "save": true, "load": true,
	"swap": true, "toggle": true, "anim": true,
}

# Set true when this terminal is instantiated on the main menu (main_menu.gd).
var menu_mode := false

# Survives scene reloads (e.g. the `load` cheat) but resets on app restart.
static var _cheats_unlocked := false

var _panel: PanelContainer
var _cmd: LineEdit
var _output: RichTextLabel

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = 240.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.93)
	sb.border_color = Color(0.4, 0.9, 0.5, 0.6)
	sb.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.bbcode_enabled = true
	_output.add_theme_color_override("default_color", Color(0.7, 1.0, 0.75))
	vbox.add_child(_output)

	_cmd = LineEdit.new()
	_cmd.placeholder_text = "cheat…  e.g.  cash 1000        ( ` to close )" if _cheats_unlocked else "…        ( ` to close )"
	_cmd.text_submitted.connect(_on_submit)
	vbox.add_child(_cmd)

	if _cheats_unlocked:
		_print_line("[b]Debug terminal[/b] — type 'help'. Toggle with the ` key.")
	else:
		_print_line("[b]Terminal[/b] — toggle with the ` key.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			_set_open(not _panel.visible)
			get_viewport().set_input_as_handled()
		elif _panel.visible and event.keycode == KEY_ESCAPE:
			_set_open(false)
			get_viewport().set_input_as_handled()

func _set_open(open: bool) -> void:
	_panel.visible = open
	if open:
		_cmd.clear()
		_cmd.grab_focus()
	else:
		_cmd.release_focus()

func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		_print_line("[color=#9fcaff]> %s[/color]" % t)
		_print_line(_run_command(t))
	_cmd.clear()
	_cmd.grab_focus()

func _print_line(s: String) -> void:
	if s != "":
		_output.append_text(s + "\n")

func _run_command(text: String) -> String:
	var parts := text.split(" ", false)
	if parts.is_empty():
		return ""
	if parts[0].to_lower() == "debug":
		if parts.size() >= 2 and parts[1] == UNLOCK_WORD:
			if _cheats_unlocked:
				return "debug mode already enabled"
			_cheats_unlocked = true
			_cmd.placeholder_text = "cheat…  e.g.  cash 1000        ( ` to close )"
			return "Debug mode enabled — type 'help' for commands."
		return "invalid operation"
	if not _cheats_unlocked:
		return "invalid operation"
	var cmd := parts[0].to_lower()
	if menu_mode and not MENU_SAFE_COMMANDS.has(cmd):
		return "'%s' is only available during a match  (main menu: swap loading_screen | swap song | help)" % cmd
	# Anything that can move the sim taints the run for telemetry: an unflagged cheat run
	# silently poisons aggregate balance data. Commands not on the read-only list — including
	# any added later — taint by default, because under-flagging is the costlier mistake.
	if not READ_ONLY_COMMANDS.has(cmd):
		MatchState.note_cheat_used()
	match cmd:
		"cash":
			if parts.size() < 2 or not parts[1].is_valid_int():
				return "usage: cash <integer>"
			var amount := int(parts[1])
			MatchState.cheat_add_cash(float(amount))
			return "Added £%d  (balance now £%.2f)" % [amount, MatchState.money]
		"research":
			# Alias for `unlock all` (testing muscle memory: `research all`).
			var count: int = MatchState.cheat_unlock_all_research()
			return "Unlocked ALL research (%d nodes)." % count
		"unlock":
			if parts.size() < 2:
				return "usage: unlock <research title>  (e.g. 'unlock hydro')  |  unlock all | hidden_buildings"
			if parts[1].to_lower() == "all":
				var unlocked_count: int = MatchState.cheat_unlock_all_research()
				return "Unlocked ALL research (%d nodes)." % unlocked_count
			if parts[1].to_lower() == "hidden_buildings":
				MatchState.cheat_unlock_hidden_buildings()
				return "Hidden buildings enabled for this match."
			var title := " ".join(parts.slice(1))
			MatchState.grant_unlock(title)
			return "Unlocked '%s'." % title
		"sellmode":
			if parts.size() < 2:
				return "usage: sellmode <stockpile|market|building>  (current: %s)" % _sell_mode_name()
			match parts[1].to_lower():
				"stockpile":
					MatchState.set_sell_mode(MatchState.SellMode.STOCKPILE_ALL)
				"market":
					MatchState.set_sell_mode(MatchState.SellMode.SELL_ALL)
				"building":
					MatchState.set_sell_mode(MatchState.SellMode.BUILDING_BY_BUILDING)
				_:
					return "usage: sellmode <stockpile|market|building>"
			return "sell mode → %s" % _sell_mode_name()
		"logs":
			return _toggle_debug_logs()
		"swap":
			if parts.size() >= 2 and parts[1].to_lower() == "song":
				return "Now playing: %s" % Audio.swap_song()
			if parts.size() >= 2 and parts[1].to_lower() == "bdp":
				MatchState.toggle_use_bdp_v2()
				return "Building Detail panel → %s" % ("v2 (redesign)" if MatchState.use_bdp_v2 else "v1 (classic)")
			if parts.size() >= 2 and parts[1].to_lower() == "construct_panel":
				MatchState.toggle_use_construct_panel_v2()
				return "Construct panel → %s" % ("v2 (redesign)" if MatchState.use_construct_panel_v2 else "v1 (classic)")
			if parts.size() >= 2 and parts[1].to_lower() == "loading_screen":
				var legacy: bool = LoadPacing.toggle_legacy_load()
				return "New-game load → %s  (takes effect on the next New Game)" % (
					"LEGACY slow build (one building/frame)" if legacy else "fast build (default)")
			if parts.size() >= 2 and parts[1].to_lower() == "goods_graph":
				var view := get_tree().current_scene.find_child("GoodsGraphView", true, false) if get_tree().current_scene != null else null
				if view == null:
					return "Goods Graph view not found (start a match first)"
				var legacy_graph: bool = bool(view.call("toggle_legacy_goods_graph"))
				return "Goods Graph → %s" % ("LEGACY arrows/no-swimlanes/fixed cards" if legacy_graph else "current swimlanes/focus")
			if " ".join(parts.slice(1)).to_lower() == "empire button":
				var badge_icon_on: bool = MatchState.toggle_use_empire_button_badge()
				return "Empire button → %s" % ("badge-centre icon" if badge_icon_on else "bevelled skyline icon")
			if " ".join(parts.slice(1)).to_lower() == "port badge":
				var badge_on: bool = MatchState.toggle_show_port_badge()
				var ev2 := get_tree().current_scene.find_child("EmpireView", true, false) if get_tree().current_scene != null else null
				if ev2 != null:
					ev2.call("refresh_graph")
				return "Port marking → %s" % ("GOLD HEX badge on the sprite" if badge_on else "lines to the port row")
			if " ".join(parts.slice(1)).to_lower() == "empire view sprite":
				var sprite_view_on: bool = MatchState.toggle_use_empire_sprite_view()
				var empire := get_tree().current_scene.find_child("EmpireView", true, false) if get_tree().current_scene != null else null
				if empire != null:
					empire.call("refresh_graph")
				return "Empire view → %s" % ("SPRITE style (big sprites, plates below, no backdrop)" if sprite_view_on else "classic cards")
			return "usage: swap song  |  swap bdp  |  swap construct_panel  |  swap loading_screen  |  swap goods_graph  |  swap empire button  |  swap empire view sprite  |  swap port badge"
		"survey":
			if parts.size() >= 2 and parts[1].to_lower() == "limit":
				MatchState.cheat_survey_within_limits()
				return "Surveyed all tiles within the current survey limit."
			if parts.size() >= 2 and parts[1].to_lower() == "all":
				MatchState.cheat_survey_all()
				return "Surveyed the whole map."
			return "usage: survey limit  |  survey all"
		"p_survey":
			if parts.size() >= 2 and parts[1].to_lower() == "limit":
				MatchState.cheat_partial_within_limits()
				return "Partially surveyed all tiles within the current survey limit."
			if parts.size() >= 2 and parts[1].to_lower() == "all":
				MatchState.cheat_partial_all()
				return "Partially surveyed the whole map."
			return "usage: p_survey limit  |  p_survey all"
		"save":
			if parts.size() < 2:
				return "usage: save <name>"
			var save_err: String = SaveLoad.save_slot(parts[1])
			return "saved '%s'" % parts[1] if save_err == "" else save_err
		"load":
			if parts.size() < 2:
				return "usage: load <name>"
			var load_err: String = SaveLoad.load_slot(parts[1])
			# On success the map scene reloads and the save applies once it's ready.
			return "loading '%s'…" % parts[1] if load_err == "" else load_err
		"saves":
			var slots: Array = SaveLoad.list_slots()
			if slots.is_empty():
				return "no saves yet  (try: save <name>)"
			var lines: Array = []
			for s in slots:
				lines.append("%s — turn %d, £%.2f  (%s)" % [s.slot, int(s.turn), float(s.money), str(s.timestamp)])
			return "\n".join(lines)
		"bankrupt":
			SolvencyState.force_bankruptcy()
			return "Forced bankruptcy — game over."
		"distressed":
			if MatchState.get_advisor_in_seat("cfo") == "":
				return "The distressed program needs a seated CFO."
			DecisionState.enabled = true
			var d_err: String = DecisionState.force_draw("distressed_asset")
			return "Distressed Asset Program offered." if d_err == "" else d_err
		"trigger":
			# Alias for `decision fire` — draws the decision and presents it NOW.
			if parts.size() < 2:
				return "usage: trigger <decision_id>   (see: decision list)"
			DecisionState.enabled = true
			var trig_err: String = DecisionState.force_draw(parts[1])
			return "drew '%s' — it presents now" % parts[1] if trig_err == "" else trig_err
		"decision":
			if parts.size() >= 2 and parts[1].to_lower() == "list":
				var lines2: Array = []
				for def_id in DecisionState.DECISION_DEFINITIONS:
					lines2.append(str(def_id))
				if DecisionState.has_pending():
					lines2.append("pending: %s" % str(DecisionState.pending.get("def_id", "")))
				return "\n".join(lines2)
			if parts.size() >= 3 and parts[1].to_lower() == "fire":
				DecisionState.enabled = true
				var fire_err: String = DecisionState.force_draw(parts[2])
				return "drew '%s' — it presents now" % parts[2] if fire_err == "" else fire_err
			if parts.size() >= 3 and parts[1].to_lower() == "resolve":
				var res_err: String = DecisionState.resolve(parts[2])
				return "resolved → %s" % parts[2] if res_err == "" else res_err
			return "usage: decision list | decision fire <id> | decision resolve <choice_id>"
		"roads":
			if parts.size() >= 4 and parts[1].to_lower() == "route":
				return _roads_route(parts[2], parts[3])
			if parts.size() >= 3 and parts[1].to_lower() == "connect":
				# exercise the Phase-3 RoadWorks queue (budgeted planning + reveal)
				if not RoadCrossings.is_built():
					var maps := get_tree().get_nodes_in_group("hex_map")
					if not maps.is_empty():
						RoadCrossings.build(maps[0])
				var oid := RoadWorks.enqueue_for_tile(parts[2])
				if oid >= 0:
					return "roadworks: order %d queued for %s (pending %d)" % [oid, parts[2], RoadWorks.pending_count()]
				return "roadworks: could not queue %s (no map or empty network?)" % parts[2]
			return "usage: roads route <tile_a> <tile_b> | roads connect <tile>"
		"toggle":
			if parts.size() >= 2 and parts[1].to_lower() == "logs":
				return _toggle_debug_logs()
			if parts.size() >= 2 and parts[1].to_lower() in ["roads", "roadsv2"]:
				# Phase-5 cutover: roads-v2 is the only system. This just shows/hides
				# the road VISUALS — the network/logic runs regardless.
				RoadNetwork.roads_visible = not RoadNetwork.roads_visible
				return "roads %s" % ("shown" if RoadNetwork.roads_visible else "hidden")
			if parts.size() >= 2 and parts[1].to_lower() == "roadocc":
				TileOccupancy.OCCUPANCY_ROADS_ENABLED = not TileOccupancy.OCCUPANCY_ROADS_ENABLED
				RoadWorks.rebuild_occupancy()
				return "road/forest occupancy → %s" % ("on" if TileOccupancy.OCCUPANCY_ROADS_ENABLED else "off")
			if parts.size() >= 2 and parts[1].to_lower() == "heightmap":
				var layers := get_tree().get_nodes_in_group("hill_visuals")
				if layers.is_empty():
					return "heightmap layer not found (not in a match scene?)"
				var now_visible := false
				for layer in layers:
					layer.visible = not layer.visible
					now_visible = layer.visible
				return "heightmap → %s" % ("on" if now_visible else "off (plain map + rivers)")
			if parts.size() >= 2 and parts[1].to_lower() == "ink":
				MapStyle.set_ink(not MapStyle.ink)
				return "map style → %s" % _style_name()
			if parts.size() >= 2 and parts[1].to_lower() == "plate":
				MapStyle.set_plate(not MapStyle.plate)
				return "map style → %s" % _style_name()
			if parts.size() >= 2 and parts[1].to_lower() == "midcentury":
				MapStyle.set_midcentury(not MapStyle.is_midcentury())
				return "map style → %s" % _style_name()
			return "usage: toggle logs | heightmap | roads | roadocc | ink | plate | midcentury"
		"anim":
			# Cheat: cycle the Empire-view hex-field animation (1->2->3->4->1), or set it with `anim <n>`.
			var bg := get_tree().get_first_node_in_group("empire_hex_bg")
			if bg == null:
				return "empire view not open (press Tab first)"
			if parts.size() >= 2 and parts[1].is_valid_int():
				return "empire animation → %s" % bg.call("set_animation", int(parts[1]))
			return "empire animation → %s" % bg.call("cycle_animation")
		"labour":
			MatchState.cheat_labour_discount()
			return "Applied debug labour -60% for 10 turns (clamps at 40% of base cost)."
		"skip":
			# QOL fast-forward: resolve N turns back-to-back (fast_mode, decisions
			# auto-resolved to their default so the loop never blocks).
			var n := 10
			if parts.size() >= 2:
				if not parts[1].is_valid_int() or int(parts[1]) < 1:
					return "usage: skip <turns>   (e.g. 'skip 10'; default 10, max 50)"
				n = clampi(int(parts[1]), 1, 50)
			_skip_turns(n)
			return "Skipping %d turn%s…" % [n, "" if n == 1 else "s"]
		"loyalty":
			if parts.size() < 3 or not parts[2].is_valid_float():
				return "usage: loyalty <advisor_id> <delta>   (e.g. 'loyalty vera -10'; clamped -10..+10)"
			var aid := parts[1].to_lower()
			if MatchState._roster_entry(aid).is_empty():
				return "unknown advisor '%s'" % aid
			MatchState.cheat_set_loyalty(aid, float(parts[2]))
			return "%s loyalty now %.1f" % [aid, MatchState.advisor_loyalty_value(aid)]
		"win":
			# Grant a full victory track (1000 pts / secured). One of:
			# greenest / logistics / richest / autarkic / widest, or 'all'.
			if parts.size() < 2:
				return "usage: win <greenest|logistics|richest|autarkic|widest|all>"
			return _cheat_win_track(parts[1].to_lower())
		"ban":
			# Engage the coal prohibition from THIS turn, exactly as a scheduled ban
			# would: coal mining halts (running mines included) and coal cannot be
			# bought by any route. 'ban coal off' lifts it.
			if parts.size() < 2 or parts[1].to_lower() != "coal":
				return "usage: ban coal  |  ban coal off"
			var ban_turn: int = TurnManager.current_turn
			if parts.size() >= 3 and parts[2].to_lower() == "off":
				PolicyState.cheat_set_coal_ban(false, ban_turn)
				return "Coal prohibition LIFTED — mining and imports are legal again."
			PolicyState.cheat_set_coal_ban(true, ban_turn)
			return "Coal BANNED from turn %d: mining halts, imports refused on every route. 'ban coal off' to lift." % ban_turn
		"help":
			return "commands:  cash <int>   |   unlock <title>|all|hidden_buildings   |   research all   |   skip <turns>   |   win <track>|all   |   sellmode <stockpile|market|building>   |   logs   |   swap song   |   swap bdp   |   swap construct_panel   |   swap loading_screen   |   swap goods_graph   |   swap empire button   |   swap empire view sprite   |   swap port badge   |   survey limit|all   |   p_survey limit|all   |   toggle logs|heightmap|roads|roadocc|ink|plate|midcentury   |   roads route <a> <b> | roads connect <tile>   |   anim [1-4]   |   labour   |   ban coal [off]   |   save <name>   |   load <name>   |   saves   |   help"
		_:
			return "unknown command: '%s'  (try 'help')" % parts[0]

# Fast-forward N turns (the `skip` cheat). Runs as an async fire-and-forget loop:
# fast_mode drops the inter-phase pacing, decisions auto-resolve to their default so the
# commit never blocks, and each turn awaits full resolution before the next commits.
func _skip_turns(n: int) -> void:
	var was_fast := TurnManager.fast_mode
	var was_auto := DecisionState.auto_resolve
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for i in n:
		if TurnManager.game_ended:
			_print_line("skip: game over — stopped after %d turn%s." % [i, "" if i == 1 else "s"])
			break
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	TurnManager.fast_mode = was_fast
	DecisionState.auto_resolve = was_auto
	_print_line("skip: done — now on turn %d." % TurnManager.current_turn)

# `win <track>|all` cheat: fully secure a victory track (best progress → 1.0, +1000
# points) and record the turn it was secured, then latch the overall win if the
# turn's rising threshold is now cleared. Republishes the score to every panel.
func _cheat_win_track(track: String) -> String:
	var keys: Array = VictoryState.TRACK_ORDER
	if track != "all" and not (track in keys):
		return "unknown track '%s'  (greenest|logistics|richest|autarkic|widest|all)" % track
	var targets: Array = keys if track == "all" else [track]
	var turn := int(TurnManager.current_turn)
	for k in targets:
		VictoryState.track_best[k] = 1.0
		if not VictoryState.track_secured_turn.has(k):
			VictoryState.track_secured_turn[k] = turn
	var total := VictoryState.total_for_turn(turn)
	var thr := VictoryState.win_threshold_for_turn(turn)
	if not VictoryState.won and total >= thr:
		VictoryState.won = true
		VictoryState.won_turn = turn
		VictoryState.victory_achieved.emit(total, turn)
	VictoryState._emit_refresh()
	var what := "ALL tracks" if track == "all" else "'%s' (+1000)" % track
	return "Secured %s — score %d / %d (%s)." % [what, total, thr, "WON" if VictoryState.won else "not yet won"]

func _roads_route(tile_a: String, tile_b: String) -> String:
	var maps := get_tree().get_nodes_in_group("hex_map")
	if maps.is_empty():
		return "no map loaded"
	var terrain: HexMap = maps[0]
	var ca: Vector2i = terrain.id_to_coord(tile_a)
	var cb: Vector2i = terrain.id_to_coord(tile_b)
	if not terrain.tiles.has(ca) or not terrain.tiles.has(cb):
		return "unknown tile id(s)"
	if not RoadCrossings.is_built():
		RoadCrossings.build(terrain)
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return "navgrid missing — re-run tools/bake_hills.tscn"
	var network := RoadNetwork.instance()
	var pa: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(ca))
	var pb: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(cb))
	var identity: String = RoadRegions.identity_for_tile(tile_a)
	var realizer := RoadRealizer.new()
	var started := Time.get_ticks_usec()
	var result := realizer.route(nav, network, pa, pb, {
		"identity": identity,
		"salt": RoadHash.pick(tile_a + "|" + tile_b, 1 << 30),
	})
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	if not result.ok:
		return "route failed: %s (%.1f ms)" % [str(result.reason), elapsed]
	var na := network.ensure_node("dbg:" + tile_a, RoadNetwork.KIND_JUNCTION, pa, ca)
	var nb := network.ensure_node("dbg:" + tile_b, RoadNetwork.KIND_JUNCTION, pb, cb)
	var tier := RoadNetwork.TIER_TRUNK if pa.distance_to(pb) > 1500.0 else RoadNetwork.TIER_LOCAL
	realizer.commit(network, na.id, nb.id, tier, result, TurnManager.current_turn)
	RoadNetwork.roads_visible = true
	return "routed %s→%s: %d pts, %d bridges, %d expansions, %.1f ms (%s)" % [
		tile_a, tile_b, result.geometry.size(), result.bridges.size(),
		result.expansions, elapsed, identity]

func _toggle_debug_logs() -> String:
	var enabled: bool = MatchState.toggle_debug_turn_logs()
	return "verbose turn logs → %s" % ("on" if enabled else "off")

func _style_name() -> String:
	if MapStyle.is_midcentury():
		return "inhabited mid-century"
	if MapStyle.is_plate():
		return "city plate"
	return "ink & wash" if MapStyle.ink else "classic"

func _sell_mode_name() -> String:
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			return "stockpile"
		MatchState.SellMode.SELL_ALL:
			return "market"
		MatchState.SellMode.BUILDING_BY_BUILDING:
			return "building"
		_:
			return "unknown"
