extends RefCounted
## Stateless data layer for the Victory / Defeat end-of-game screen
## (scripts/victory_end_screen.gd), ported from the owner's "Victory Screen.html"
## design. Assembles ONE dict from the live autoloads — VictoryState (score, tracks,
## per-turn history), MatchState (buildings, tiles), Catalog (good names/icons) —
## exactly like tile_view_data.gd feeds the tile panel. UI is read-only against the sim.
##
## Adapts the design to the LIVE victory model: no base time score (you start at 0),
## the win threshold RISES over the game (win_threshold_for_turn), and the score bar is
## pure track contributions.

# Track display metadata (the design's exact order + colours + one-line descriptions).
const TRACKS: Array = [
	{"key": "autarkic",  "name": "Autarkic",  "color": "#e6b34a", "desc": "Buy nothing — the streak"},
	{"key": "logistics", "name": "Logistics", "color": "#b9c4d2", "desc": "One-turn deliveries"},
	{"key": "richest",   "name": "Richest",   "color": "#5fbf6b", "desc": "Retained profit / turn"},
	{"key": "widest",    "name": "Widest",    "color": "#5fa8e0", "desc": "Tiles occupied"},
	{"key": "greenest",  "name": "Greenest",  "color": "#4fd0a0", "desc": "Renewable supply"},
]
# Rank palette for the "biggest outputs" bars (rank 0 is drawn gold by the UI).
const TOP_COLORS: Array = ["#e6b34a", "#8f9dae", "#a8b0bc", "#cdd2cb", "#7fd4e8", "#b9c4d2"]

# ── Public entry point ─────────────────────────────────────────────────────────
static func gather() -> Dictionary:
	var vs := VictoryState
	var won: bool = vs.won
	var turn: int = vs.won_turn if won else int(TurnManager.current_turn)
	turn = clampi(turn, 1, vs.MAX_TURNS)
	var result := "victory" if won else "defeat"
	var total: int = vs.total_for_turn(turn)
	var threshold: int = vs.win_threshold_for_turn(turn)

	var tracks := _tracks()
	var secured := 0
	for t in tracks:
		if bool(t.done):
			secured += 1

	return {
		"result": result,
		"won": won,
		"turn": turn,
		"max_turns": vs.MAX_TURNS,
		"total": total,
		"threshold": threshold,
		"secured_count": secured,
		"tracks": tracks,
		"title": _title(result, secured, tracks),
		"epithet": _epithet(result, secured, turn),
		"copy": _copy(result, secured, turn, tracks),
		"statline": _statline(),
		"charts": _charts(),
		"empire": _empire(),
	}

# ── Tracks (pennants) ──────────────────────────────────────────────────────────
static func _tracks() -> Array:
	var vs := VictoryState
	var out: Array = []
	for meta in TRACKS:
		var key := str(meta.key)
		var pct: float = clampf(float(vs.track_best.get(key, 0.0)), 0.0, 1.0)
		var done := pct >= 0.999
		out.append({
			"key": key, "name": str(meta.name), "color": str(meta.color), "desc": str(meta.desc),
			"done": done, "pct": pct,
			"at": int(vs.track_secured_turn.get(key, -1)),
			"stat": _track_stat(key),
			"sub": _track_sub(key, done),
		})
	return out

static func _track_stat(key: String) -> String:
	var vs := VictoryState
	match key:
		"autarkic":
			return "%d-turn streak" % vs.autarkic_streak
		"logistics":
			var eff := 0
			if vs.logistics_total > 0:
				eff = int(round(100.0 * float(vs.logistics_efficient) / float(vs.logistics_total)))
			return "%d%% one-turn" % eff
		"richest":
			return "£%.1fk / turn" % (vs._richest_metric() / 1000.0)
		"widest":
			return "%d tiles" % _widest_tiles()
		"greenest":
			var g: Dictionary = vs._greenest_stats()
			return "%d%% renewable" % int(round(100.0 * float(g.get("share", 0.0))))
	return ""

static func _track_sub(key: String, done: bool) -> String:
	var vs := VictoryState
	match key:
		"autarkic":
			return "self-supplied at scale" if done else "%s / %s units produced" % [_num(vs.produced_units_lifetime), _num(vs.AUTARKIC_MIN_UNITS)]
		"logistics":
			return "%s moves this turn" % _num(vs.logistics_total)
		"richest":
			return "5-turn retained profit"
		"widest":
			return "of %d needed" % vs.WIDEST_HI
		"greenest":
			var g: Dictionary = vs._greenest_stats()
			return "of %s MW supplied" % _num(int(g.get("total", 0)))
	return ""

# ── Narrative title / epithet / copy (generated from the actual result) ─────────
# Single-track wins are NAMED FOR THE WINNING TRACK (owner's victory types:
# greenest / logistics / richest / autarkic / widest — richest keeps the design's
# "Cash is King"); multi-track wins keep the design's count titles.
const _SINGLE_TRACK_TITLES := {
	"autarkic": "Autarkic", "logistics": "Logistics", "richest": "Cash is King",
	"widest": "Widest", "greenest": "Greenest",
}

static func _title(result: String, secured: int, tracks: Array) -> String:
	if result == "defeat":
		return "Receivership"
	if secured <= 1:
		for t in tracks:
			if bool(t.done):
				return str(_SINGLE_TRACK_TITLES.get(str(t.key), str(t.name)))
		return "Victory"   # threshold crossed on banked partials — no single champion track
	return ["", "", "Visionary Industrialist", "The Magnate", "Titan of Industry", "The Full Ledger"][clampi(secured, 2, 5)]

static func _epithet(result: String, secured: int, turn: int) -> String:
	if result == "defeat":
		return "The clock ran out — no track secured before turn %d" % turn
	var n := "%d track%s secured" % [secured, "" if secured == 1 else "s"]
	if secured >= 5:
		return "Grand-slam victory — every track secured before the clock ran out"
	return "%s — won on turn %d with the time in hand" % [n, turn]

static func _copy(result: String, secured: int, turn: int, tracks: Array) -> Array:
	var names: Array = []
	for t in tracks:
		if bool(t.done):
			names.append(str(t.name).to_lower())
	var lead := "The books closed on turn %d." % turn
	if result == "defeat":
		return [
			"%s No track ever crossed its gate, and the rising win bar climbed past everything the empire managed to bank." % lead,
			"What remains is real — the buildings still stand, the ports still work — but the ledger fell short and the receivers take it from here.",
		]
	var secured_line := "on the strength of every track it built" if secured >= 5 else ("carried by " + _join_names(names))
	return [
		"%s An empire assembled turn by turn — mines, furnaces and factories feeding the docks — crossed the line %s." % [lead, secured_line],
		"With the win bar already %s points high by turn %d, %d of five tracks came home, and the ledger closed in the black." % [_num(VictoryState.win_threshold_for_turn(turn)), turn, secured],
	]

static func _join_names(names: Array) -> String:
	if names.is_empty():
		return "the time in hand"
	if names.size() == 1:
		return "the " + str(names[0]) + " ledger"
	var head: Array = names.slice(0, names.size() - 1)
	return ", ".join(head) + " and " + str(names[-1])

# ── Statline (four headline figures) ───────────────────────────────────────────
static func _statline() -> Array:
	var vs := VictoryState
	var revenue := 0.0
	for v in vs.history_revenue:
		revenue += float(v)
	var buildings := 0
	for v in vs.history_buildings:
		buildings = maxi(buildings, int(v))
	var shipped := 0
	for g in vs.produced_by_good:
		shipped += int(vs.produced_by_good[g])
	return [
		{"k": "Total revenue",  "v": _money(revenue)},
		{"k": "Buildings built", "v": _num(maxi(buildings, vs._count_player_buildings()))},
		{"k": "Tiles held",     "v": _num(_widest_tiles())},
		{"k": "Goods shipped",  "v": _num(shipped)},
	]

# ── Charts ─────────────────────────────────────────────────────────────────────
static func _charts() -> Dictionary:
	var vs := VictoryState
	var rev: Array = vs.history_revenue.duplicate()
	var outp: Array = vs.history_output.duplicate()
	var bld: Array = vs.history_buildings.duplicate()
	var peak_rev := 0.0
	for v in rev:
		peak_rev = maxf(peak_rev, float(v))
	var peak_out := 0
	var peak_out_turn := 0
	for i in outp.size():
		if int(outp[i]) > peak_out:
			peak_out = int(outp[i])
			peak_out_turn = i + 1
	var standing := int(bld[-1]) if not bld.is_empty() else vs._count_player_buildings()

	# Biggest outputs — top 5 goods by lifetime production.
	var goods: Array = []
	for g in vs.produced_by_good:
		goods.append({"good_id": str(g), "units": int(vs.produced_by_good[g])})
	goods.sort_custom(func(a, b): return int(a.units) > int(b.units))
	var top: Array = []
	var top_total := 0
	for i in mini(5, goods.size()):
		var gid := str(goods[i].good_id)
		top_total += int(goods[i].units)
		top.append({
			"good_id": gid,
			"internal": str(Catalog.get_internal_name(gid)),
			"label": str(Catalog.get_display_name(gid)),
			"units": int(goods[i].units),
			"color": str(TOP_COLORS[i % TOP_COLORS.size()]),
		})

	return {
		"revenue": rev, "output": outp, "buildings": bld,
		"revenue_big": _money(peak_rev), "revenue_sub": "peak revenue / turn",
		"output_big": _num(peak_out), "output_sub": "units — biggest turn (%d)" % peak_out_turn,
		"buildings_big": _num(standing), "buildings_sub": "standing at game end",
		"top": top, "top_total": top_total,
	}

# ── Empire network (columns of the strategic view + ports) ──────────────────────
static func _empire() -> Dictionary:
	var mines := 0
	var furn_a := 0   # metallurgy (furnaces / steel)
	var furn_b := 0   # refinery + electrochemistry + water
	var factories := 0
	var port_tiles: Dictionary = {}
	for inst in MatchState.buildings.values():
		if not MatchState.is_player_owned(inst):
			continue
		var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		var types: Array = bd.get("building_type", [])
		var cat := str(bd.get("category", ""))
		if types.has("extraction"):
			mines += 1
		elif types.has("metallurgy"):
			furn_a += 1
		elif types.has("refinery") or types.has("electrochemistry") or types.has("water"):
			furn_b += 1
		elif types.has("manufacturing"):
			factories += 1
		if cat == "port" or types.has("port") or str(bd.get("internal_name", "")) in ["port", "seaport"]:
			port_tiles[str(inst.get("tile_id", ""))] = Catalog.tile_label(str(inst.get("tile_id", "")))
	var ports: Array = port_tiles.values()
	if ports.is_empty():
		ports = ["Capital Port"]
	return {"mines": mines, "furn_a": furn_a, "furn_b": furn_b, "factories": factories, "ports": ports}

# ── Helpers ────────────────────────────────────────────────────────────────────
static func _widest_tiles() -> int:
	var tiles: Dictionary = {}
	for inst in MatchState.buildings.values():
		if not MatchState.is_player_owned(inst):
			continue
		var b: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		if str(b.get("category", "")) == "infrastructure":
			continue
		tiles[str(inst.get("tile_id", ""))] = true
	return tiles.size()

static func _num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

static func _money(v: float) -> String:
	var a := absf(v)
	var sign := "-" if v < 0 else ""
	if a >= 1_000_000.0:
		return "%s£%.2fM" % [sign, a / 1_000_000.0]
	if a >= 1_000.0:
		return "%s£%.0fk" % [sign, a / 1_000.0]
	return "%s£%d" % [sign, int(round(a))]
