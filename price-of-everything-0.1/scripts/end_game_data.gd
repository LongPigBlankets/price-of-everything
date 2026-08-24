extends RefCounted
## Stateless data layer for the Victory / Defeat end-of-game screen
## (scripts/victory_end_screen.gd), ported from the owner's "Victory Screen.html"
## design. Assembles ONE dict from the live autoloads — VictoryState (score, tracks,
## per-turn history), MatchState (buildings, tiles), Catalog (good names/icons) —
## exactly like tile_view_data.gd feeds the tile panel. UI is read-only against the sim.
##
# tile_view_data owns the building-icon lookup (id_internal.png fallbacks).
const TileViewData := preload("res://scripts/tile_view_data.gd")

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
## The demo runs a different five (VictoryState.DEMO_TRACK_ORDER), so the pennants need
## their own names and colours. Same shape as TRACKS; _track_display() picks between them
## by what the match is actually running rather than by a flag read here.
const DEMO_TRACKS: Array = [
	{"key": "crown",      "name": "Crown",    "color": "#e6b34a", "desc": "Turns atop the ranking"},
	{"key": "tiers",      "name": "Tiers",    "color": "#b9c4d2", "desc": "Every tier producing"},
	{"key": "distance",   "name": "Distance", "color": "#5fa8e0", "desc": "Long-haul shipments"},
	{"key": "green_demo", "name": "Green",    "color": "#4fd0a0", "desc": "Wind and solar in a turn"},
	{"key": "estate",     "name": "Estate",   "color": "#5fbf6b", "desc": "Buildings owned and running"},
]
# Rank palette for the "biggest outputs" bars (rank 0 is drawn gold by the UI).
const TOP_COLORS: Array = ["#e6b34a", "#8f9dae", "#a8b0bc", "#cdd2cb", "#7fd4e8", "#b9c4d2"]

# ── The demo's endings (owner, 23 Aug) ─────────────────────────────────────────
#
# A 100-turn run cannot earn the campaign's track-count titles — "The Magnate" for three
# tracks assumes 300 turns of compounding — so the demo is named by what the run actually
# finished with. Five outcomes, decided in the order below because they overlap: a run with
# 4 tracks also has more than 500 points, and only the FIRST match should name it.
#
#   bankruptcy          the company folded — the only ending that is not about the score
#   full_ledger         4 or more tracks secured
#   jack_of_all_trades  2,000+ points with NO track fully won
#   sequel              more than 500 points
#   lukewarm            500 or fewer
#
# Copy is the owner's, verbatim. `result` is the verdict word for a run that did NOT cross
# the win bar — crossing it makes any ending a victory.
const DEMO_JACK_POINTS := 2000
const DEMO_SEQUEL_POINTS := 500
const DEMO_FULL_LEDGER_TRACKS := 4

const DEMO_ENDINGS := {
	"bankruptcy": {
		"title": "Bankruptcy",
		"result": "defeat",
		"copy": "Nothing more to say. You simply have to pick yourself back up and try again. Your father had his own failings and he'd tell you it was part and parcel of trying to build anything worthwhile.",
	},
	"full_ledger": {
		"title": "The Full Ledger",
		"result": "victory",
		"copy": "No one could have predicted what heights you'd take this business to. Everyone in the country, maybe even a few out there in the world, are watching now. Where could you possibly go after demolishing every obstacle and rewriting the book on business?",
	},
	"jack_of_all_trades": {
		"title": "The Jack of All Trades",
		"result": "continuity",
		"copy": "You've taken a business and expanded in all directions. No one knew your next move. Though you'll always wonder how much more sparkling your story could have been if you'd focused more. Well, time to kick back and enjoy the fruits of your labour. Well earned, too!",
	},
	"sequel": {
		"title": "The Sequel",
		"result": "continuity",
		"copy": "Your father would be proud of you. Not only did you keep the business afloat, but you diversified and expanded. You've well and truly left his shadow and are your own person.",
	},
	"lukewarm": {
		"title": "A lukewarm follow-up",
		"result": "defeat",
		"copy": "Your father had higher hopes. Survival will have to do. But the world moved faster than you and now the company might be a little bit better, but perhaps the next generation will pick up the mantle.",
	},
}

## Is this match running the demo's victory set? The endings follow the tracks — a campaign
## scored against campaign tracks keeps the campaign's titles.
static func demo_endings_apply() -> bool:
	return VictoryState.TRACK_ORDER == VictoryState.DEMO_TRACK_ORDER


## Which ending a demo run earned. Precedence, not a score band lookup: the conditions
## overlap and the first match wins. A run with exactly DEMO_SEQUEL_POINTS is lukewarm —
## the owner's rule is "more than 500" for the sequel and "less than 500" for the lukewarm
## one, and 500 itself has to fall on one side.
static func demo_ending_id(secured: int, total: int, bankrupt: bool) -> String:
	if bankrupt:
		return "bankruptcy"
	if secured >= DEMO_FULL_LEDGER_TRACKS:
		return "full_ledger"
	if total >= DEMO_JACK_POINTS and secured == 0:
		return "jack_of_all_trades"
	if total > DEMO_SEQUEL_POINTS:
		return "sequel"
	return "lukewarm"


## The one-line subhead. The ending's copy is the owner's and says nothing about numbers, so
## this is where the run's actual figures go — the player should not have to read the score
## bar to find out what they finished on.
static func _demo_epithet(id: String, secured: int, total: int, turn: int) -> String:
	if id == "bankruptcy":
		return "The company folded on turn %d" % turn
	var tracks_part := "no track secured"
	if secured == 1:
		tracks_part = "1 track secured"
	elif secured > 1:
		tracks_part = "%d tracks secured" % secured
	return "The books closed on turn %d — %s points, %s" % [turn, _num(total), tracks_part]

# ── Public entry point ─────────────────────────────────────────────────────────
static func gather() -> Dictionary:
	var vs := VictoryState
	var won: bool = vs.won
	var turn: int = vs.won_turn if won else int(TurnManager.current_turn)
	turn = clampi(turn, 1, vs.MAX_TURNS)
	# Three outcomes, not two. Running out of turns having secured NO track is only a defeat if
	# the company was also losing money; a business still in the black at the bell survived, and
	# the screen says so in amber rather than calling in the receivers (owner 2026-08-01).
	# Net/turn comes from the same summary the top bar reads, so the verdict agrees with the
	# figure the player was watching all game.
	var result := "victory" if won else ("continuity" if _net_per_turn() > 0.0 else "defeat")
	var total: int = vs.total_for_turn(turn)
	var threshold: int = vs.win_threshold_for_turn(turn)

	var tracks := _tracks()
	var secured := 0
	for t in tracks:
		if bool(t.done):
			secured += 1

	# The demo names its own endings, and each one carries the verdict word that fits its
	# copy — "The Sequel" reads as a compliment and must not sit under DEFEAT because the
	# last turn happened to close in the red.
	if demo_endings_apply():
		var ending_id := demo_ending_id(secured, total, SolvencyState.is_bankrupt())
		var ending: Dictionary = DEMO_ENDINGS[ending_id]
		# The authored result is the verdict for a run that did NOT cross the bar; `won`
		# upgrades it. Both directions matter: "The Sequel" must never be stamped DEFEAT
		# because the last turn closed in the red, and "The Jack of All Trades" must never say
		# VICTORY over a score bar reading 2,100 / 2,500.
		# Judged on the SCORE against the bar, not only on the latched `won` flag: 4 tracks is
		# 4,000 against a 2,500 bar and reads as a win on the screen either way.
		var cleared: bool = won or total >= threshold
		var ending_result := str(ending.result)
		if cleared:
			ending_result = "victory"
		elif ending_result == "victory":
			ending_result = "continuity"
		return {
			"result": ending_result,
			"won": won,
			"turn": turn,
			"max_turns": vs.MAX_TURNS,
			"total": total,
			"threshold": threshold,
			"secured_count": secured,
			"tracks": tracks,
			"ending_id": ending_id,
			"title": str(ending.title),
			"epithet": _demo_epithet(ending_id, secured, total, turn),
			"copy": [str(ending.copy)],
			"statline": _statline(),
			"company": _company_highlights(),
			"charts": _charts(),
			"empire": _empire(),
		}

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
		"company": _company_highlights(),
		"charts": _charts(),
		"empire": _empire(),
	}

# ── Tracks (pennants) ──────────────────────────────────────────────────────────
static func _tracks() -> Array:
	var vs := VictoryState
	var out: Array = []
	# Driven by the set the match is running, not by TRACKS — a demo match plays five
	# different tracks and its end screen has to show those and not the campaign's.
	for key_variant: Variant in vs.TRACK_ORDER:
		var key := str(key_variant)
		var meta: Dictionary = _track_display(key)
		var pct: float = clampf(float(vs.track_best.get(key, 0.0)), 0.0, 1.0)
		var done := pct >= 0.999
		out.append({
			"key": key, "name": str(meta.get("name", key)), "color": str(meta.get("color", "#b9c4d2")),
			"desc": str(meta.get("desc", "")),
			"done": done, "pct": pct,
			"at": int(vs.track_secured_turn.get(key, -1)),
			"stat": _track_stat(key),
			"sub": _track_sub(key, done),
		})
	return out

## Display metadata for a track key, from whichever table names it. A set with no authored
## row still renders: the name falls back to VictoryState's own, in the default steel.
static func _track_display(key: String) -> Dictionary:
	for table: Array in [TRACKS, DEMO_TRACKS]:
		for meta_variant: Variant in table:
			var meta: Dictionary = meta_variant
			if str(meta.get("key", "")) == key:
				return meta
	return {"key": key, "name": str(VictoryState.TRACK_NAMES.get(key, key)),
		"color": "#b9c4d2", "desc": ""}

static func _track_stat(key: String) -> String:
	var vs := VictoryState
	match key:
		"crown":
			return "%d turns on top" % vs.demo_crown_turns
		"tiers":
			return "%d%% of the tiers" % int(round(100.0 * vs._demo_tiers_progress()))
		"distance":
			return "%d long hauls" % vs.demo_long_hauls
		"green_demo":
			return "%s MW green" % _num(int(round(float(vs._greenest_stats().get("green", 0.0)))))
		"estate":
			return "%d buildings" % int(vs.demo_estate_counts().owned)
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
		"crown":
			return "of %d needed" % vs.DEMO_CROWN_TURNS
		"tiers":
			return "%d units a tier, every tier" % vs.DEMO_TIER_UNITS
		"distance":
			return "of %d over %d turns' travel" % [vs.DEMO_LONG_HAULS, vs.DEMO_LONG_HAUL_TURNS]
		"green_demo":
			return "of %s MW in one turn" % _num(int(vs.DEMO_GREEN_TARGET))
		"estate":
			return "%d running, of %d needed" % [int(vs.demo_estate_counts().running), vs.DEMO_ESTATE_BUILDINGS]
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
# Victory names (owner 2026-07-11):
#   5 tracks → The Full Ledger
#   4 tracks → named by the one that got away (see _FOUR_TRACK_TITLES)
#   3 tracks → The Magnate · 2 tracks → Visionary Industrialist
#   1 track  → named for the winning track (see _SINGLE_TRACK_TITLES)
const _SINGLE_TRACK_TITLES := {
	"crown": "Head of the Table",
	"tiers": "Every Rung",
	"distance": "The Long Way Round",
	"green_demo": "Green and Keen",
	"estate": "Landed Interest",
	"greenest": "Green and Keen",
	"logistics": "I am Speed",
	"richest": "Cash is King",
	"widest": "Big Bang",
	"autarkic": "Independent and Proud",
}
const _FOUR_TRACK_TITLES := {   # keyed by the MISSING track
	"greenest": "Titan of Industry",
	"autarkic": "Green Titan",
	"widest": "Closed Shop",
	"richest": "First and Last Mile",
	"logistics": "Beyond all Limits",
}

## Net cash movement over the last resolved turn — the same figure the top bar prints as
## "+£X / turn" (Production.last_turn_summary money_in - money_out).
static func _net_per_turn() -> float:
	var s: Dictionary = Production.last_turn_summary
	return float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))


static func _title(result: String, secured: int, tracks: Array) -> String:
	if result == "continuity":
		return "Continuity"
	if result == "defeat":
		return "Receivership"
	match secured:
		5:
			return "The Full Ledger"
		4:
			for t in tracks:
				if not bool(t.done):
					return str(_FOUR_TRACK_TITLES.get(str(t.key), "Titan of Industry"))
			return "Titan of Industry"
		3:
			return "The Magnate"
		2:
			return "Visionary Industrialist"
		1:
			for t in tracks:
				if bool(t.done):
					return str(_SINGLE_TRACK_TITLES.get(str(t.key), str(t.name)))
	return "Victory"   # threshold crossed on banked partials — no champion track

static func _epithet(result: String, secured: int, turn: int) -> String:
	if result == "continuity":
		return "The clock ran out on turn %d — no track secured, but the company still turns a profit" % turn
	if result == "defeat":
		return "The clock ran out — no track secured before turn %d" % turn
	var n := "%d track%s secured" % [secured, "" if secured == 1 else "s"]
	if secured >= VictoryState.TRACK_ORDER.size():
		return "Grand-slam victory — every track secured before the clock ran out"
	return "%s — won on turn %d with the time in hand" % [n, turn]

static func _copy(result: String, secured: int, turn: int, tracks: Array) -> Array:
	var names: Array = []
	for t in tracks:
		if bool(t.done):
			names.append(str(t.name).to_lower())
	var lead := "The books closed on turn %d." % turn
	if result == "continuity":
		# Owner's copy, verbatim (2026-08-01).
		return ["You continued your predecessors' task and made this company survive through a lot of change. Although you never reached the crazy heights of success some thought you capable of, there is greatness in maintaining such a steady ship. Few businesses can claim to have survived this long or managed to avoid catastrophe like yours. Raise a glass - but make it a small one, we can't afford the fancy stuff."]
	if result == "defeat":
		return [
			"%s No track ever crossed its gate, and the rising win bar climbed past everything the empire managed to bank." % lead,
			"What remains is real — the buildings still stand, the ports still work — but the ledger fell short and the receivers take it from here.",
		]
	var secured_line := "on the strength of every track it built" if secured >= VictoryState.TRACK_ORDER.size() else ("carried by " + _join_names(names))
	return [
		"%s An empire assembled turn by turn — mines, furnaces and factories feeding the docks — crossed the line %s." % [lead, secured_line],
		"With the win bar already %s points high by turn %d, %d of %d tracks came home, and the ledger closed in the black." % [_num(VictoryState.win_threshold_for_turn(turn)), turn, secured, VictoryState.TRACK_ORDER.size()],
	]

static func _join_names(names: Array) -> String:
	if names.is_empty():
		return "the time in hand"
	if names.size() == 1:
		return "the " + str(names[0]) + " ledger"
	var head: Array = names.slice(0, names.size() - 1)
	return ", ".join(head) + " and " + str(names[-1])

# ── Company highlights (the run's own artefacts, for the showcase row) ─────────
# Superlatives drawn from ledgers the sim already keeps, display-ready, so the screen can
# show THIS run's things — good icons, building art, an advisor portrait — rather than
# abstract numbers alone (owner 2026-08-24).
static func _company_highlights() -> Dictionary:
	var vs := VictoryState
	var top_prod := {"gid": "", "qty": 0, "qty_text": "—"}
	for gid in vs.produced_by_good:
		var q: int = int(vs.produced_by_good[gid])
		if q > int(top_prod.qty):
			top_prod = {"gid": str(gid), "qty": q, "qty_text": _num(q) + " units"}
	var top_sold := {"gid": "", "qty": 0, "qty_text": "—"}
	for g_variant in MatchState.visible_goods():
		var gid := str((g_variant as Dictionary).get("id", ""))
		var q := MarketState.lifetime_sold(gid)
		if q > int(top_sold.qty):
			top_sold = {"gid": gid, "qty": q, "qty_text": _num(q) + " units"}
	# Hardest-working building: the single instance with the most lifetime output. Profit is
	# not ledgered per building, so units out of one machine is the honest superlative.
	var work := {}
	var work_units := 0
	for iid in Production.produced_by_building:
		var per: Dictionary = Production.produced_by_building[iid]
		var total := 0
		for k in per:
			total += int(per[k])
		if total > work_units and MatchState.buildings.has(str(iid)):
			work_units = total
			var b: Dictionary = MatchState.buildings[str(iid)]
			var bd: Dictionary = Catalog.get_building(str(b.get("building_id", "")))
			work = {"name": str(bd.get("display_name", "?")),
				"sub": "%s units · Level %d" % [_num(total), int(b.get("level", 1))],
				"icon": TileViewData._building_icon_tex(bd)}
	# Longest-serving SEATED advisor, by hire turn; the tenure reads in company years.
	var adv := {}
	var earliest := 999999
	for seat in MatchState.advisor_seats:
		var aid := str(MatchState.advisor_seats[seat])
		var t := int(MatchState.advisor_hired_turn.get(aid, 999998))
		if t < earliest:
			earliest = t
			var a: Dictionary = MatchState.get_advisor(aid)
			adv = {"name": str(a.get("name", aid.capitalize())),
				"portrait": str(a.get("portrait_path", "")),
				"since_year": 1 + maxi(0, t - 1) / 12}
	# The chain, tier by tier: the most-produced good in each band, empty where the run
	# never reached — drawn by the screen in the Goods Graph's own chip style.
	var chain: Array = []
	for tier in ["raw", "processed", "intermediate", "finished", "apex"]:
		var best := {"tier": tier, "gid": "", "qty": 0}
		for gid in vs.produced_by_good:
			var good: Dictionary = Catalog.get_good(str(gid))
			if str(good.get("goods_graph_tier", "")) != str(tier):
				continue
			if int(vs.produced_by_good[gid]) > int(best.qty):
				best = {"tier": tier, "gid": str(gid), "qty": int(vs.produced_by_good[gid])}
		chain.append(best)
	return {"top_produced": top_prod, "top_sold": top_sold, "workhorse": work,
		"advisor": adv, "chain": chain}


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
