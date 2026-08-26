extends Node2D

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var building_panel: PanelContainer = %BuildingDetailPanel
## Redesigned Building Detail v2 — toggled by `swap bdp`. Built ON FIRST USE, not during
## the load: a 2,400-line panel whose shell cost ~330 ms of the build to construct something
## the player cannot see until they click a building. Read it through the
## `building_panel_v2` property, which builds it; test whether it EXISTS with `_bdp_v2`.
## True once the deferred dialog/effect set has been built (see _build_dialogs_and_fx).
var _dialogs_built := false
var _bdp_v2: PanelContainer = null
var building_panel_v2: PanelContainer:
	get:
		if _bdp_v2 == null:
			_build_building_panel_v2()
		return _bdp_v2
## The building most recently shown in the detail panel, kept so a live v1↔v2 swap re-renders it.
var _last_detail_building: Dictionary = {}
## The tabbed Tile View Panel. Built ON FIRST USE (same reasoning as the detail panel
## above: ~740 ms of the load for a panel nobody sees until they click a tile). Read it
## through the property; test for existence with `_info_panel`.
var _info_panel: PanelContainer = null
var info_panel: PanelContainer:
	get:
		if _info_panel == null:
			_build_info_panel()
		return _info_panel
## The most recently selected tile, kept so a live TVP swap can re-render it.
var _last_selected_tile: Dictionary = {}
## True while the v2 stockpile "Move/Sell" flow is picking a destination tile.
var _v2_picking_dest: bool = false
@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var turn_counter: Label = %TurnCounter
@onready var encyclopedia_button: Button = %EncyclopediaButton
@onready var building_visuals: Node2D = %BuildingVisuals
@onready var building_connection_visuals: Node2D = %BuildingConnectionVisuals
@onready var search_overlay: Control = %SearchOverlay
# Sibling under the WorldMap root; it is not a unique_name node, so fetch it by path.
@onready var map_overlay: Node2D = get_node_or_null("MapOverlay")
@onready var river_layer: TileMapLayer = $RiverLayer
@onready var hud_content: Control = $UILayer/HUD/HUDContent
# Transport (logistics) panel — built on first open, see _on_transport_panel_requested.
var _transport_panel: Control = null
@onready var _hud: Control = $UILayer/HUD
@onready var _toast_layer: Control = $UILayer/HUD/ToastLayer
@onready var forest_visuals: Node2D = %ForestVisuals

# Empire view — full-screen node-graph alternative to the map (Tab to toggle).
# Created in code in _ready() and parented under HUDContent. See scripts/empire_view.gd.
# Typed via a preload const (not a class_name) to avoid global-class registration-order
# parse errors when this script is reloaded by the test harness.
const EmpireViewScript := preload("res://scripts/empire_view.gd")
var empire_view: EmpireViewScript

# Goods Graph — full-screen goods-web view (G to toggle; also reachable from the
# top bar and the Resources panel). See scripts/goods_graph_view.gd.
const GoodsGraphViewScript := preload("res://scripts/goods_graph_view.gd")
const GoodsFlowGraphScript := preload("res://scripts/goods_flow_graph.gd")
const GoodIconsScript := preload("res://scripts/good_icons.gd")
const AuthoredBakeScript := preload("res://scripts/authored_bake.gd")
const StartLayoutBakedScript := preload("res://scripts/start_layout_baked.gd")
## How far past the opening view to preload baked tiles, world units — two tiles of slack so
## the first pan does not have to hit the disk.
const WARM_MARGIN := 1000.0
var goods_graph_view: GoodsGraphViewScript

const DENSITY_SOFT_CAPACITY := 100.0
const InfraIcons := preload("res://scripts/infra_icons.gd")
const OLD_GROWTH_FOREST_BUILDING_ID := "b_016"
const OLD_GROWTH_FOREST_OWNER := "tile_data"
const NORTH_OLD_GROWTH_MAX_ROW := 6
const OLD_GROWTH_TILE_TYPES := ["rural", "hill"]

signal building_placed(tile_id: String, building_id: String, recipe_id: String, instance_id: String, coord: Vector2i)
## A tile gained infrastructure of some type. Emitted for EVERY route that sets the flag —
## a completed construction, the tutorial's free reveal, the baked start flags — because a
## flag flip is invisible to renderers that watch edge counts: the geometry is unchanged,
## only which of it qualifies to draw. Authored roads (`authored_road_visuals.gd`) reveal on
## this; the baked network still relies on its own counters plus a manual repaint.
signal tile_infrastructure_changed(tile_id: String, infra_type: String)

var _survey_dialog: PanelContainer = null
var _special_order_resolution_dialog: Control = null
var _stockpile_select_prompt: PanelContainer = null
var _pending_stockpile_selection: Dictionary = {}
var _dim_overlay: ColorRect = null
var _stockpile_legend: PanelContainer = null
var _picking_buy_tile := false  # true while picking a Purchases-tab delivery tile
var _special_order_reroute_picking := false
# --- Market "Move" transfer flow ---
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const _TR_LIGHT_GREEN := Color(0.50, 0.90, 0.50)
const _TR_DARK_GREEN := Color(0.12, 0.50, 0.18)
const _TR_RED := Color(0.86, 0.32, 0.32)
var _transfer: Dictionary = {}  # {good, origin, qty, dest, state}
var _transfer_dialog: PanelContainer = null
var _tr_title: Label = null
var _tr_origin: Label = null
var _tr_qty: SpinBox = null
var _tr_dest: Label = null
var _tr_cost: Label = null
var _tr_recurring: CheckBox = null
var _tr_cta: Button = null
var _tr_cap: Label = null
var _tr_legend: VBoxContainer = null
var _tr_legend_panel: PanelContainer = null
var _tr_modal: PanelContainer = null
var _tr_modal_label: Label = null
const _TR_YELLOW := Color(1.0, 1.0, 0.45)
const LEGEND_LEFT := 12.0
const LEGEND_BOTTOM := 24.0

# Per-good BUY flow (market is the implicit origin; ships via nearest port).
var _buy: Dictionary = {}  # {good, qty, tiles: Array, state}
var _buy_dialog: PanelContainer = null
var _buy_title: Label = null
var _buy_qty: SpinBox = null
var _buy_dest: Label = null
var _buy_cost: Label = null
var _buy_recurring: CheckBox = null
var _buy_cta: Button = null
var _buy_legend: VBoxContainer = null
var _buy_legend_panel: PanelContainer = null
var _buy_modal: PanelContainer = null
var _buy_modal_label: Label = null
var _credit_dialog: PanelContainer = null
var _construction_dialog: PanelContainer = null
var _deposit_dialog: Control = null  # reused "no deposit" / "deposit exhausted" modal
var _deposit_dialog_target: Dictionary = {}  # building the current deposit dialog acts on

## False until _ready has finished building the world. On a fresh start the heavy
## building-visual placement is spread across frames (so the loading screen can keep
## animating its slideshow), so "the scene exists" is NOT the same as "the world is
## ready" — the loading screen waits on this flag before offering "Begin".
var build_complete := false

## LOAD_PROF=1 (env): print a wall-clock breakdown of the new-game build — one line per
## phase (delta since the previous mark + cumulative + absolute ticks, so stall logs from
## other watchers can be correlated). Zero cost when the env var is unset.
var _prof_t0 := 0
var _prof_last := 0
## Wall cost of ONE call, in isolation. _prof measures the gap between marks, which
## includes any frame awaited in between — fine for phases, misleading for a single
## synchronous call sitting after a yield.
func _prof_us(label: String, t0_us: int) -> void:
	_prof_total(label, Time.get_ticks_usec() - t0_us)


## Wall cost already accumulated by the caller (a running total across many calls).
func _prof_total(label: String, us: int) -> void:
	if OS.get_environment("LOAD_PROF") == "":
		return
	print("LOADPROF-CALL %-30s %8.1f ms" % [label, float(us) / 1000.0])


func _prof(label: String) -> void:
	if OS.get_environment("LOAD_PROF") == "":
		return
	var now := Time.get_ticks_msec()
	if _prof_t0 == 0:
		_prof_t0 = now
		_prof_last = now
	print("LOADPROF %-36s +%6d ms   t=%7d ms   abs=%d" % [label, now - _prof_last, now - _prof_t0, now])
	_prof_last = now


func _ready() -> void:
	_prof("world_map._ready enter")
	# Nothing the build produces is visible until "Begin" is pressed — the loading screen
	# is opaque and covers the window — but the renderer does not know that, and was
	# submitting the whole map every frame for the length of the build. See _hide_world_for_load.
	_hide_world_for_load()
	# Advisor agenda: any building placement/completion counts as "a building built".
	building_placed.connect(func(_t: String, _b: String, _r: String, _i: String, _c: Vector2i) -> void:
		MatchState.note_building_built())
	if not MatchState.advisor_walked.is_connected(_on_advisor_walked):
		MatchState.advisor_walked.connect(_on_advisor_walked)
	await _build_base()
	_hide_world_for_load()   # _build_base parents a couple of effect layers onto us
	_prof("_build_base (HUD scaffold)")
	# A fresh new game with a loading screen up animates its build (it yields between steps to keep
	# the loading animation live); tests / e2e / load-game (no loading screen) build synchronously.
	await finish_build(_loading_screen_active())

# An advisor whose loyalty stayed critically low has resigned — surface a popup.
func _on_advisor_walked(advisor_id: String) -> void:
	if _hud == null:
		return
	var name_str := str(MatchState.get_advisor(advisor_id).get("name", advisor_id))
	var dlg := AcceptDialog.new()
	if DS and DS.theme:
		dlg.theme = DS.theme
	dlg.title = "Advisor Resigned"
	dlg.dialog_text = "%s has resigned.\n\nTheir loyalty stayed critically low for too long, so they've walked. Their seat is now vacant and they will sit out before they can be re-hired." % name_str
	_hud.add_child(dlg)
	dlg.confirmed.connect(func() -> void: dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


# Build the config-independent visual scaffold: theme, signal wiring, the HUD panels, the terrain
# + visual layers — no simulation, no MatchState mutation. The per-start sim + buildings come in
# finish_build(). Split out so the two phases read clearly and each can yield to the loading screen.
func _build_base() -> void:
	# DS assigns its Theme to the root Window, but Controls do not inherit a
	# Window's theme — so apply it to the HUD Control subtree (where every panel
	# lives) for DS fonts / type variations / button styles to actually resolve.
	_hud.theme = DS.theme
	river_layer.clear()
	terrain_layer.tile_selected.connect(_on_tile_selected)
	terrain_layer.stockpile_destination_selected.connect(_on_stockpile_destination_selected)
	terrain_layer.survey_tile_clicked.connect(_on_survey_tile_clicked)
	MatchState.buy_tile_pick_requested.connect(_on_buy_tile_pick_requested)
	MatchState.transfer_for_good_requested.connect(_on_transfer_requested)
	MatchState.purchase_for_good_requested.connect(_on_purchase_requested)
	BuildMode.build_attempted.connect(_on_build_attempted)
	BuildMode.infrastructure_attempted.connect(_on_infrastructure_attempted)  # NEW
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	encyclopedia_button.pressed.connect(_on_encyclopedia_pressed)
	if search_overlay.has_signal("recipe_build_requested"):
		search_overlay.recipe_build_requested.connect(_on_search_recipe_build_requested)
	MatchState.encyclopedia_entry_requested.connect(_on_encyclopedia_entry_requested)
	MatchState.goods_graph_requested.connect(_on_goods_graph_requested)
	MatchState.goods_graph_good_requested.connect(_on_goods_graph_good_requested)
	MatchState.empire_view_requested.connect(_on_empire_view_requested)
	MatchState.encyclopedia_good_requested.connect(_on_encyclopedia_good_requested)
	MatchState.focus_tile_requested.connect(_on_focus_tile_requested)
	MatchState.focus_building_requested.connect(_on_focus_building_requested)
	MatchState.transport_panel_requested.connect(_on_transport_panel_requested)
	MatchState.tile_stockpile_requested.connect(_on_go_to_tile_stockpile)
	MatchState.research_search_requested.connect(_on_research_search_requested)

	TurnManager.phase_started.connect(_on_phase_started)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)
	MatchState.output_stockpile_selection_started.connect(_on_output_stockpile_selection_started)
	MatchState.output_stockpile_selection_cancelled.connect(_on_output_stockpile_selection_cancelled)
	MatchState.hidden_buildings_enabled.connect(_on_hidden_buildings_enabled)

	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)
	_build_stockpile_select_prompt()
	_build_dim_overlay()
	_build_stockpile_legend()
	_prof("base: wiring+prompts")
	# Hand a frame to the loading screen here (right after the scene instantiated) so its
	# animation + the OS window stay live while the rest of the world builds. No-op without
	# a loading screen (tests / e2e / load-game run the build synchronously, as before).
	await _build_yield()

	# Infrastructure mapmode panel: shows/hides itself with the mapmode.
	hud_content.add_child(load("res://scripts/infrastructure_panel.gd").new())
	_apply_demo_infra_levels()
	_prof("base: infra panel")

	# Empire view: full-screen node-graph alternative to the map (Tab to toggle).
	empire_view = EmpireViewScript.new()
	empire_view.name = "EmpireView"
	empire_view.visible = false
	hud_content.add_child(empire_view)
	_prof("base: empire view")

	# Goods Graph: full-screen goods-web view (G to toggle).
	goods_graph_view = GoodsGraphViewScript.new()
	goods_graph_view.name = "GoodsGraphView"
	goods_graph_view.visible = false
	hud_content.add_child(goods_graph_view)
	_prof("base: goods graph view")

	# Wire visuals to react to building placements
	building_placed.connect(building_visuals.on_building_placed)
	building_placed.connect(forest_visuals.on_building_placed)
	# A cancelled construction site removes its hex icon (it was never a real building).
	Construction.construction_cancelled.connect(_on_construction_cancelled)
	Construction.building_tab_opened.connect(_show_building_credit_dialog)
	# Deposit feedback: reveal/popup when a blind (unsurveyed) build finishes, and a
	# centre-screen prompt when a deposit runs out under a working building.
	Construction.construction_completed.connect(_on_construction_completed_deposit_check)
	# Infrastructure joins the tile / routing network only when its build completes.
	Construction.construction_completed.connect(_on_construction_completed_infra)
	MatchState.deposit_exhausted.connect(_on_deposit_exhausted)

	# Wire building connection visuals to building detail panel
	building_panel.building_connections_changed.connect(
		building_connection_visuals.on_building_connections_changed
	)

	# Building Detail v2 — the default panel since Phase 3 (MatchState.use_bdp_v2, default true).
	# The classic v1 panel (%BuildingDetailPanel) stays as a fallback, reachable via `swap bdp`.
	# See docs/building-detail-v2-plan.md. BUILT LAZILY — see _build_building_panel_v2.
	MatchState.bdp_v2_changed.connect(_on_bdp_v2_changed)

	# Research unlocks no longer pop a dialog — they are aggregated into a single
	# Turn Briefing "Research unlocked" update (see turn_briefing._research_aggregate_item).
	#
	# The dialogs, the debug terminal and the two effect layers are built AFTER the build,
	# one per frame — see _build_dialogs_and_fx. The tabbed Tile View Panel lives under
	# HUDContent, named "TileInfoPanel" so building_detail_panel's panel-stacking lookups
	# find it, and is built on first use (_build_info_panel).
	await _build_yield()


# Apply this start's (or a loaded save's) simulation and place its buildings on top of the base
# scaffold. `animate` (true when a loading screen is up) spreads building placement one-per-frame
# so the loading animation keeps running; false builds synchronously (tests / e2e / load-game).
func finish_build(animate: bool) -> void:
	_prof("finish_build enter")
	# Kick off worker-thread loads of the Goods Graph's MEDIUM good icons NOW, so they
	# stream in parallel with the ~5 s map build below instead of stalling the main
	# thread ~3.2 s on first Goods Graph open (69 medium PNGs at ~47 ms each). Only under
	# a loading screen — tests / e2e / load-game don't open the graph and shouldn't pay it.
	if _loading_screen_active():
		GoodIconsScript.warm_async(Catalog.all_goods())
		# And the baked map tiles the opening camera will want. Both are worker-thread reads
		# kicked off here so they run alongside the ~4 s of build below instead of being paid
		# as a frozen frame at the end of it.
		_request_opening_bake_tiles()
	# The port tiles start surveyed (the Surveying mapmode reveals them on turn 1).
	MatchState.seed_surveyed_ports()
	# Track depletable-deposit yields so mining can run them down over time.
	MatchState.seed_deposits(terrain_layer)
	_prof("seed ports+deposits")
	# NOTE: the game-start BUILDINGS (NPC ports, the ruins, the start companies — and any future player
	# start buildings) are placed LATER, AFTER the baked road network exists, so they lay out against
	# real streets. See the "roads → buildings" sequence below.

	var pending_start := SaveLoad.pending_is_start()
	# Captured BEFORE apply_pending() clears the snapshot: a tutorial match seeds none
	# of the NPC start companies / ruins / old-growth forests (the player stays confined
	# to the small board), keeping only the ports so the coast + docks still render.
	var pending_tutorial := SaveLoad.pending_is_tutorial()
	# A loaded save applies only now, once the terrain and default seeding exist;
	# it overwrites the fresh-match state above (docs/save_load_spec.md).
	var loaded_pending := SaveLoad.apply_pending()
	_prof("apply_pending snapshot")
	# A normal loaded save must restore its existing visual state immediately. A
	# start snapshot is different: its player buildings need to wait for the baked
	# road network below, otherwise they use the roadless fallback and sit under
	# turn-one streets. They are emitted in the post-road pass instead.
	if loaded_pending and not pending_start:
		_rebuild_after_load()
	# Advanced Setting "All tiles surveyed at game start": reveal every tile now that
	# the terrain (and any pending ruleset) exists.
	if bool(MatchState.ruleset.get("survey_all_tiles", false)):
		var all_ids: Array = []
		for coord in terrain_layer.tiles:
			var tid := str((terrain_layer.tiles[coord] as Dictionary).get("id", ""))
			if tid != "":
				all_ids.append(tid)
		MatchState.mark_tiles_surveyed(all_ids)
	await _build_yield()
	# Forests are a TERRAIN feature (the land mask + block templates read them), so they come before
	# roads. The buildings that used to follow here are deferred until after the roads exist.
	if (not loaded_pending or pending_start) and not pending_tutorial:
		_place_northern_old_growth_forests()
	_prof("old-growth forests")

	# roads-v2: the predetermined river crossings must exist before any runtime
	# routing — the realizer whitelists river cells near these gates, so without
	# them a road can never cross a river (it was only ever built by the bake and
	# debug cheats, so river roads silently failed in normal play). Cheap (~123
	# river tiles), static for the match.
	if not RoadCrossings.is_built():
		var t_rc := Time.get_ticks_usec()
		RoadCrossings.build(terrain_layer)
		_prof_us("RoadCrossings.build", t_rc)
	_prof("road crossings")
	# A loaded save restores its as-built network + work orders
	# (SaveLoad.import_snapshot); anything else starts from the baked anchor
	# spine (spec 4.5b). bootstrap_from_bake no-ops when edges were imported.
	if not loaded_pending or pending_start:
		RoadNetwork.reset()
		RoadWorks.reset()
	RoadNetwork.bootstrap_from_bake()
	_prof("road bootstrap_from_bake")
	# roads-v3: every tile the baked network crosses carries "roads" infrastructure
	# from turn 0 (geometry == gameplay — anchors AND the corridor tiles a trunk
	# passes through). Fresh start only; a loaded save restores its own flags.
	# When a loading screen is up, placements batch into ~PLACE_SLICE_MS time slices
	# (see _place_yield) so the loading animation stays live, and the visual layers
	# coalesce their redraws into one shot at end_bulk — per-building frames + full
	# per-placement redraws were most of the ~60 s new-game load. Without a loading
	# screen (tests, e2e, load-game) `animate` is false and placement runs
	# synchronously, exactly as before.
	if not loaded_pending or pending_start:
		# The tutorial's opening lesson deliberately starts with a five-hop freight
		# route that has no transport infrastructure. Keep the baked RoadNetwork
		# geometry available so the coach can reveal its road later, but do not make
		# every baked corridor tile gameplay-active at turn zero in this ruleset.
		if not pending_tutorial:
			_apply_baked_road_flags()
		await _build_yield()
		# The bulk window coalesces the per-placement redraws (the fast path). The
		# `swap loading_screen` cheat leaves it off so each placement redraws the whole
		# layer, reproducing the old slow build for a recording.
		var bulk_place := not LoadPacing.legacy_load
		if bulk_place:
			building_visuals.begin_bulk()
			forest_visuals.begin_bulk()
		# THE START LAYOUT COMES OFF DISK. Every emit below still runs — the sim half of a
		# start building is 4.5 ms for the whole set, and the passes stay the single source of
		# truth for WHAT gets placed — but BuildingVisuals answers each one from the bake
		# instead of searching the tile for a spot it has already found on every previous run.
		# A building the bake does not hold is laid out live against the baked world;
		# reconcile below removes any the bake holds that this match never emitted.
		_install_baked_layout()
		_place_slice_t0 = Time.get_ticks_msec()
		# BUILDINGS now — after the baked road network — so they lay out against real
		# streets (NPC ports, the ruins, the start companies, + future player start builds).
		await _place_npc_ports(animate)
		_prof("place npc_ports")
		# Tutorial keeps the ports (coast/docks) but drops the ruins + NPC start
		# companies so the board is a clean slate around the seeded window factory.
		if not pending_tutorial:
			if MatchState.is_building_available("b_031"):
				await _place_ruins("tile_23_16", animate)
			await _place_start_buildings(animate)
			_prof("place ruins+start buildings")
			_prof_total("  of which MatchState.add_building", _place_add_us)
			_prof_total("  of which building_placed.emit", _place_emit_us)
		if pending_start:
			await _place_pending_start_buildings(animate)
			_prof("place pending_start buildings")
		var dropped: int = building_visuals.reconcile_baked_layout()
		if dropped > 0:
			print("StartLayout: dropped %d baked placement(s) this match does not emit" % dropped)
		if bulk_place:
			building_visuals.end_bulk()
			forest_visuals.end_bulk()
		_prof("end_bulk (coalesced redraw queued)")
	_prof("pre-occupancy")
	RoadWorks.rebuild_occupancy()   # no-op until OCCUPANCY_ROADS_ENABLED

	# Port dockhouses: white harbour slabs + pier fingers on the sea edge of
	# every port tile (draws above the tilemap as a terrain_layer child).
	var port_visuals: Node2D = load("res://scripts/port_visuals.gd").new()
	port_visuals.name = "PortVisuals"
	port_visuals.z_index = 60   # above hills/roads decoration, below UI
	terrain_layer.add_child(port_visuals)
	if not _baked_port_plans.is_empty():
		port_visuals.install_baked_plans(_baked_port_plans)
	var t_pv := Time.get_ticks_usec()
	port_visuals.setup(terrain_layer)
	_prof_us("port_visuals.setup", t_pv)
	_prof("port_visuals (harbour plan)")

	# Parchment grain: one world-anchored multiply texture over the whole plate
	# (terrain + roads + buildings; UI lives on CanvasLayers above and stays clean).
	var parchment: Node2D = load("res://scripts/parchment_overlay.gd").new()
	parchment.name = "ParchmentOverlay"
	terrain_layer.add_child(parchment)
	var pmin := Vector2(1e9, 1e9)
	var pmax := Vector2(-1e9, -1e9)
	for pcoord in terrain_layer.tiles:
		var pc: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(pcoord))
		pmin = pmin.min(pc)
		pmax = pmax.max(pc)
	# Pad well past the tile grid so the open sea at minimum zoom sits in the same paper.
	parchment.setup(Rect2(pmin - Vector2(2400, 2400), (pmax - pmin) + Vector2(4800, 4800)))
	_prof("parchment overlay")

	# Re-gravitate every building once (deterministic, idempotent): a loaded save re-emitted its buildings
	# before its imported road network was in hand, and this also re-fills the enclosure chunk grids now that
	# the templates + rings all exist. Fresh-start buildings were already laid out against roads above.
	# A fresh start (pending_start) already laid its buildings out against the finished
	# roads + rings above, so relayout() would just redo identical work (~7 s of
	# layout). Only a genuine LOADED save needs it — its buildings were re-emitted by
	# _rebuild_after_load before the imported road network was in hand, so they must be
	# re-packed against it now.
	if loaded_pending and not pending_start and building_visuals.has_method("relayout"):
		building_visuals.relayout()
	_prof("relayout (loaded save only)")

	# The Goods Graph layout is NOT built here any more. It is a pure function of the
	# Catalog and `GoodsFlowGraph.build()` caches it for the app run, so the view builds
	# it on its first open (goods_graph_view._rebuild_graph) — off the load's critical
	# path, and never paid at all by a player who does not press G. The deferred warm
	# below still builds it before they can, whenever the build finishes ahead of the
	# player's click on "Begin".
	if _loading_screen_active():
		# Baked authored-map tiles the opening camera will see. Streaming loads the rest as it
		# scrolls; paying for the first screenful here means play does not open on a burst of
		# disk reads. No-op without a bake, and cheap (a handful of small textures).
		var t_ab := Time.get_ticks_usec()
		_warm_authored_bake()
		_prof_us("_warm_authored_bake (collect)", t_ab)

	_audit_start_visuals()
	_prof("audit_start_visuals")
	# The two big panels are lazy, and under a loading screen they are built after "Begin" is
	# offered (see _warm_deferred_ui). WITHOUT one — tests, the e2e harness, the screenshot
	# tools — there is no such "after": those callers watch build_complete and then reach
	# straight for world.info_panel or look up "TileInfoPanel" under HUDContent, so a finished
	# world has to have them in it by the time that flag flips. Same work, same order as before
	# this was made lazy; only the interactive path defers.
	if not _loading_screen_active():
		await _build_dialogs_and_fx(false)
		_build_info_panel()
		_build_building_panel_v2()
	# Paint the finished world UNDER the still-opaque loading screen. Every layer's first
	# paint (and the hills' far-zoom LOD switch) is an expensive frame; it has to land here
	# rather than on the fade-out, or the reveal stutters on the frame the player is
	# watching. No-op when the world was never hidden (tests / e2e / load-game).
	# Optionally paint the warm frame at the zoom the player will actually be at, rather than
	# fully zoomed out. See LoadingScreen.START_AT_PLAY_ZOOM.
	#
	# ONLY under a loading screen. This is about what the loading screen hands over, and the
	# reveal it pairs with is itself loading-screen-only. Tests, the e2e harness and the
	# screenshot tools have no such handover and DO have expectations about where the camera
	# is; moving it for them would be changing their world to tune ours.
	if LoadingScreen.START_AT_PLAY_ZOOM and _loading_screen_active():
		_place_camera_at_play_zoom()
	await _reveal_world_for_play()
	# ...and then take it away again until "Begin".
	#
	# A revealed map is ~26,000 draw calls a frame, and the loading screen is opaque, so while
	# it is up those are 26,000 draw calls of nothing. That is affordable against a hex lattice
	# and fatal against a film: measured, the film ran at 0.6-4 fps behind the revealed world
	# and advanced 1.7 s of footage in 9.5 s of wall clock. The paint above has done its job —
	# the expensive first frame is paid, the textures are resident, the shaders are compiled —
	# so it goes back under until the player asks for it, and comes back in a frame nobody is
	# looking at because the screen is fading out over it.
	_hide_world_after_warm()

	# EVERYTHING ELSE ALSO HAPPENS BEFORE "Begin" IS OFFERED. It used to run after, on the
	# theory that the player's read-and-click was dead time — but with the load down to ~10 s
	# the button now arrives while they are still watching, they click straight through, and
	# the work lands on the map instead. "Ready" has to mean ready.
	await _warm_deferred_ui()
	build_complete = true   # the loading screen may now offer "Begin"
	print("WorldMap ready, signals connected")
	print("MatchState ready. Money: ", MatchState.money, ". Buildings: ", MatchState.buildings.size())

	# Fresh scripted start: pin the camera on the start's hub and show the once-only founding
	# intro. Gated on pending_start so a loaded save (which keeps ruleset.start_id) never re-shows it.
	if pending_start:
		match String(MatchState.ruleset.get("start_id", "")):
			"metal_magnate":
				_show_metal_magnate_intro()
			"glass_merchant":
				_show_glass_merchant_intro()


func _show_metal_magnate_intro() -> void:
	# Wait for the loading screen (if any) to dismiss first, so the modal sits over the
	# game board — not over the loading slideshow and its own "Begin" button.
	while _loading_screen_active():
		await get_tree().process_frame
	_focus_camera_on_tile("tile_5_10")   # centre on Stoneshore Docks (the start's hub)
	var intro: CanvasLayer = load("res://scripts/metal_magnate_intro.gd").new()
	add_child(intro)


func _show_glass_merchant_intro() -> void:
	while _loading_screen_active():
		await get_tree().process_frame
	_focus_camera_on_tile("tile_22_16")   # centre on Vandel's Skip (the start's hub)
	var intro: CanvasLayer = load("res://scripts/glass_merchant_intro.gd").new()
	add_child(intro)


## Preload the baked authored-map textures the opening camera will see. The rest stream in as
## the player scrolls (authored_bake.gd), so this is deliberately a screenful and not the whole
## map — 209 tiles resident at once would be ~289 MB of VRAM for ~7 MB of disk.
## Ask the worker threads for the baked tiles the opening camera will need. Called at the top
## of the build so the reads overlap everything else; _warm_authored_bake collects them at the
## end. Slicing the reads across frames was tried instead and is worse — the disk time is the
## same and each yielded frame adds ~90 ms, so it only spreads the cost while raising it.
func _request_opening_bake_tiles() -> void:
	if not AuthoredBakeScript.is_available():
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var extent := get_viewport().get_visible_rect().size / maxf(0.001, camera.zoom.x)
	var view := Rect2(camera.global_position - extent * 0.5, extent).grow(WARM_MARGIN)
	AuthoredBakeScript.warm_async(AuthoredBakeScript.tiles_in_rect(view).keys())


func _warm_authored_bake() -> void:
	if not AuthoredBakeScript.is_available():
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return   # no camera yet: streaming will load the first screenful on the first frame
	var extent := get_viewport().get_visible_rect().size / maxf(0.001, camera.zoom.x)
	var view := Rect2(camera.global_position - extent * 0.5, extent).grow(WARM_MARGIN)
	# Collection, not loading: request_opening_bake_tiles asked the worker threads for these
	# at the top of the build, so by now this is mostly a cache scan. Any straggler blocks
	# here — under the screen — rather than on the frame that reveals the map.
	var warmed := AuthoredBakeScript.warm(AuthoredBakeScript.tiles_in_rect(view).keys())
	if warmed > 0:
		print("AuthoredBake: warmed %d texture(s) for the opening view" % warmed)


## Harbour plans from the start-layout bake, held between the restore and the point later in
## the build where PortVisuals is created. See port_visuals.install_baked_plans.
var _baked_port_plans: Dictionary = {}

## Install the baked start layout, if there is a usable one. Skipped entirely when
## NO_LAYOUT_BAKE is set in the environment — that is how the bake tool (and an A/B check)
## forces the live placement path in a build that would otherwise restore.
func _install_baked_layout() -> void:
	if OS.get_environment("NO_LAYOUT_BAKE") != "":
		print("StartLayout: NO_LAYOUT_BAKE set — placing live.")
		return
	var t := Time.get_ticks_usec()
	var baked := StartLayoutBakedScript.layout()
	if baked.is_empty():
		return
	if not building_visuals.import_layout_state(baked):
		return
	_baked_port_plans = baked.get("port_plans", {})
	_prof_us("baked start layout restored", t)
	print("StartLayout: restored %d baked placement(s)" % (baked.get("owned", {}) as Dictionary).size())


# ── The world is not rendered while the loading screen covers it ───────────────
#
# HALF of a new-game load was spent RENDERING a map nobody could see: the loading screen
# is opaque and full-screen, yet every build frame still submitted the whole plate —
# terrain tilemap, hills, fabric, roads, buildings — at 9.5-17k draw calls and 150-210 ms
# a frame (measured with tools/frame_anatomy_watcher.gd: frame_end 52% of wall clock).
# The build yields a frame between slices to keep the loading animation alive, so it paid
# that tax hundreds of times over.
#
# Hiding the layers removes the cost outright, and it also removes the load's worst freeze
# for free: HillVisuals' cold `_draw` (the one that triangulates every contour before its
# mesh cache is warm) was an 8.9 s single frame, and a hidden CanvasItem is never drawn.
#
# Same idiom as goods_graph_view._hide_world / empire_view: the Camera2D is skipped (it is
# not a drawn thing and the intro zoom needs it), only layers that were ALREADY visible are
# recorded, and UILayer is a CanvasLayer so the HUD is untouched.
var _hidden_for_load: Array[CanvasItem] = []

func _hide_world_for_load() -> void:
	if not _loading_screen_active():
		return   # tests / e2e / load-game render normally, exactly as before
	for child in get_children():
		if child is Camera2D:
			continue
		if child is CanvasItem and (child as CanvasItem).visible:
			(child as CanvasItem).visible = false
			_hidden_for_load.append(child as CanvasItem)


## Put the map back and let it paint while the plate is still up. The frames matter: the
## first paint of the finished world is expensive (every layer's first draw, plus the hills
## switching to their far-zoom LOD), and it must be spent HERE, not on the fade-out.
const REVEAL_WARM_FRAMES := 4

## Frames the reveal will wait for the fabric layer to finish re-rendering the tiles whose
## decorative masses a building demolished. One tile per frame; a cap so a stuck repair delays
## the match rather than stopping it.
const REPAIR_WAIT_FRAMES := 180

func _reveal_world_for_play() -> void:
	if _hidden_for_load.is_empty():
		return
	# Those repairs run while the world is hidden (see authored_fabric_visuals._process), but
	# they are paced one tile a frame, so a fast build can reach here before they finish.
	var fabric := get_tree().get_first_node_in_group("authored_fabric")
	if fabric != null and fabric.has_method("has_pending_repairs"):
		var waited := 0
		while bool(fabric.call("has_pending_repairs")) and waited < REPAIR_WAIT_FRAMES:
			waited += 1
			await get_tree().process_frame
		if waited > 0:
			_prof_total("waited for fabric repairs (frames)", waited * 1000)
	# ALL AT ONCE, deliberately. Revealing one layer per frame to spread the first paint was
	# measured and is WORSE: each frame re-renders everything revealed so far, so twenty
	# frames cost far more than the one big frame they replace (reveal 1.8 s -> ~4 s, and the
	# film lost 5.9 s of stream time instead of 4.1 s). The first paint of a world is not
	# divisible by hiding part of it.
	for layer in _hidden_for_load:
		if is_instance_valid(layer):
			layer.visible = true
			layer.queue_redraw()   # a redraw queued while hidden must not be lost
	_prof("world revealed")
	for i in REVEAL_WARM_FRAMES:
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		_prof_us("  reveal frame %d (draws=%d)" % [i, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))], t)
	_prof("reveal warm frames")


## Put the warmed world back under the loading screen until "Begin". `_hidden_for_load` is
## deliberately NOT cleared by the warm reveal, so this is the same list going back the way it
## came; reveal_for_play() is what finally clears it.
func _hide_world_after_warm() -> void:
	if _hidden_for_load.is_empty():
		return
	for layer in _hidden_for_load:
		if is_instance_valid(layer):
			layer.visible = false


## Show the world for good. Called by the loading screen as it starts fading out, and cheap by
## then: the layers painted once already, so this is a repaint with everything warm.
func reveal_for_play() -> void:
	for layer in _hidden_for_load:
		if is_instance_valid(layer):
			layer.visible = true
			# NO queue_redraw HERE. Godot keeps a hidden CanvasItem's recorded commands, so
			# showing it again costs nothing — while forcing a repaint throws away the paint
			# the warm frame did under the plates and does the whole thing a second time. That
			# was measured at ~1.2 s on the frame the player clicks Begin, which is exactly the
			# frame this hide/warm/reveal dance exists to protect.
			#
			# Correctness does not depend on this call: every layer's own _process compares the
			# live view against the one it painted and asks for a repaint when the camera has
			# moved far enough to need one (see view_stream.gd). Repainting them all
			# unconditionally only pre-empts a decision they already make for themselves.
			# Measured, interleaved: 1229 -> 496 ms and 1309 -> 519 ms on the worst frame
			# after the click, with the resulting map pixel-for-pixel the same.
	_hidden_for_load.clear()
	# And start the one warm that is too big for a load. 8.6 s of contour triangulation, in
	# slices small enough to disappear into a play frame, for a picture the player only needs
	# if they zoom all the way in — and which _draw_fill will build on demand if they get there
	# first. Fire and forget: nothing waits on it.
	var hills := get_node_or_null("HillVisuals")
	if hills != null and hills.has_method("warm_meshes_deferred"):
		hills.warm_meshes_deferred()


## Build, before "Begin" is offered, the things a match does not need in order to
## start: the two big HUD panels and the Goods Graph layout. Each is behind a lazy
## accessor, so this is a WARM and not a requirement — if the player gets there first the
## accessor builds it, and if they never open a building or press G it is never built at
## all. A frame is handed back between items so the plate keeps animating and a Begin
## click is still processed promptly.
func _warm_deferred_ui() -> void:
	if not _loading_screen_active():
		return   # tests / e2e / tools: leave the lazy accessors to do it on demand
	# Every step below yields, and this runs at the very end of the build — where a harness
	# (or a player pressing alt-F4 on the Begin plate) can tear the tree down underneath it.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# The listeners first: they are what a gameplay event will look for, and the panels are
	# only wanted when the player opens something.
	await _build_dialogs_and_fx(true)
	if not is_inside_tree():
		return
	var t := Time.get_ticks_usec()
	_build_info_panel()
	_prof_us("warm tile info panel", t)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	t = Time.get_ticks_usec()
	_build_building_panel_v2()
	_prof_us("warm building detail v2", t)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	t = Time.get_ticks_usec()
	GoodsFlowGraphScript.build()
	_prof_us("warm goods graph layout", t)
	t = Time.get_ticks_usec()
	GoodIconsScript.warm(Catalog.all_goods())
	_prof_us("warm good icons join", t)
	# The hill contours ARE pre-warmed here now, on worker threads.
	#
	# They used to be left until after Begin, on the reasoning that the zoomed-in LOD is only
	# needed if the player zooms in. It is not: _on_begin_pressed starts the camera intro
	# zoom, which crosses the LOD threshold on its own, so _draw_fill triangulated every
	# visible contour inside a single draw call and the map opened on a 7.1 s frozen frame —
	# 11.3 s of stall across the two frames after the click. Measured, before and after, with
	# tools/begin_click_probe.tscn.
	#
	# It costs the LOAD nothing: triangulation is pure computation, so it runs on the thread
	# pool while the film keeps the main thread, and it lands inside the slack that
	# BEGIN_MIN_WALL already holds the button for. Nothing is awaited here — the button is not
	# waiting on it, and _draw_fill still builds anything unfinished on demand.
	#
	# HillVisuals._ready starts this itself, as early as the contours exist. This call is the
	# backstop for the path where that did not happen, and is a no-op when it did. Starting it
	# HERE alone is not enough: this runs at the end of the build, ~1.3 s before the button can
	# be pressed, against several seconds of work.
	var hills_node := get_node_or_null("HillVisuals")
	if hills_node != null and hills_node.has_method("warm_meshes_async"):
		hills_node.warm_meshes_async()


## A loading screen (parented to the tree root, surviving the scene change) is up
## iff one of the root's children is a LoadingScreen — only then do we spread the
## build across frames.
func _loading_screen_active() -> bool:
	for c in get_tree().root.get_children():
		if c is LoadingScreen:
			return true
	return false


# Yield a frame during the new-game build so the loading screen keeps animating and the OS
# window stays responsive between heavy steps. No-op (synchronous) when no loading screen is
# up — tests, the e2e harness and Load Game build the world in one pass, exactly as before.
func _build_yield() -> void:
	if _loading_screen_active():
		await get_tree().process_frame

const PLACE_SLICE_MS := 30
var _place_slice_t0 := 0
## LOAD_PROF accounting for the start-building loop: the sim half (MatchState.add_building)
## against the visual half (the building_placed fan-out, i.e. BuildingVisuals + ForestVisuals).
var _place_add_us := 0
var _place_emit_us := 0

# Time-budget yield for the start-building placement passes: batch ~PLACE_SLICE_MS of
# placements per frame, yielding only when the slice is spent, so the loading screen
# keeps animating (~30 fps) without paying a frame per building — one-per-frame across
# ~475 buildings (each frame also redrawing the whole layer) was most of the ~60 s
# new-game load. Yield timing never feeds layout (all placement is seeded), so where
# the frame boundaries fall cannot change geometry. No-op without a loading screen
# (tests / e2e stay fully synchronous).
func _place_yield(animate: bool) -> void:
	if not animate:
		return
	if LoadPacing.legacy_load:
		await get_tree().process_frame   # cheat: the slow pre-optimization one-per-frame build
		return
	if Time.get_ticks_msec() - _place_slice_t0 < PLACE_SLICE_MS:
		return
	await get_tree().process_frame
	_place_slice_t0 = Time.get_ticks_msec()

## roads-v3: apply "roads" infrastructure to every tile the baked starting
## network crosses (anchors AND corridor tiles — the bake's flagged_tiles list),
## mirroring what a settled player road does. Infrastructure is free: it never
## counts against build capacity. Fresh start only; loads restore their own flags.
func _apply_baked_road_flags() -> void:
	for tid in RoadsBaked.flagged_tiles():
		var tile_id := str(tid)
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if not terrain_layer.tiles.has(coord):
			continue
		var td: Dictionary = terrain_layer.tiles[coord]
		var infra: Array = (td.get("infrastructure_present", []) as Array)
		if infra.has("roads"):
			continue
		infra = infra.duplicate()
		infra.append("roads")
		td["infrastructure_present"] = infra
		Catalog.add_tile_infrastructure(tile_id, "roads")

func _rebuild_after_load() -> void:
	# Redraw per-building visuals from the imported state: clear everything placed
	# during _ready (NPC ports, ruins) and re-emit building_placed for every live
	# building and in-progress construction project. Toasts stay silent — they
	# listen to building_added / construction_started, which are not re-emitted.
	if building_visuals.has_method("clear_all"):
		building_visuals.clear_all()
	if forest_visuals.has_method("clear_all"):
		forest_visuals.clear_all()
	for instance_id in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[instance_id]
		var tile_id := str(inst.get("tile_id", ""))
		building_placed.emit(tile_id, str(inst.get("building_id", "")),
			str(inst.get("recipe_id", "")), str(instance_id), terrain_layer.id_to_coord(tile_id))
	for instance_id in Construction.construction_projects:
		var proj: Dictionary = Construction.construction_projects[instance_id]
		var tile_id := str(proj.get("tile_id", ""))
		building_placed.emit(tile_id, str(proj.get("building_id", "")),
			str(proj.get("recipe_id", "")), str(instance_id), terrain_layer.id_to_coord(tile_id))
	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)

func _on_tile_selected(tile_data: Dictionary) -> void:
	_last_selected_tile = tile_data
	info_panel.show_tile(tile_data)

# While a tutorial is active, map interaction is confined to the board tiles. Returns
# true (and nudges the player) when tile_id is off-board. A no-op in normal play.
func _tutorial_blocks(tile_id: String) -> bool:
	if not Tutorial.active or Tutorial.tile_allowed(tile_id):
		return false
	MatchState.request_toast("Let's stay on the tutorial area for now.", "info")
	return true

func _on_survey_tile_clicked(tile_data: Dictionary) -> void:
	# Clicking a tile in the Surveying mapmode opens its survey dialog. Fully
	# surveyed tiles (and ones already being surveyed) trigger no dialog.
	var tile_id := str(tile_data.get("id", ""))
	if _tutorial_blocks(tile_id):
		return
	if MatchState.is_survey_in_progress(tile_id):
		MatchState.request_toast("Survey already in progress (%d turns)." % MatchState.survey_turns_left(tile_id), "info")
		return
	var status := MatchState.survey_status(tile_id, str(tile_data.get("type", "")))
	if status == "surveyed":
		return  # already surveyed — no dialog
	if not MatchState.is_tile_surveyable(tile_id):
		MatchState.request_toast("That tile is beyond the survey range.", "warning")
		return
	var tile_name := str(tile_data.get("nickname", ""))
	if tile_name == "":
		tile_name = str(tile_data.get("city_name", ""))
	if tile_name == "":
		tile_name = tile_id
	_survey_dialog.open_for(tile_id, tile_name, status == "partial")

func _on_v2_building_clicked(building: Dictionary) -> void:
	_open_building_detail(building)

## Open the building detail panel for `building`, routing to whichever panel the `swap bdp`
## dev-toggle selects. Both panels sit in HUDContent after later-added siblings, so
## move_to_front() must precede show — otherwise a re-sort undoes the positioning, leaving
## an empty-looking panel until the next click.
func _open_building_detail(building: Dictionary, empire_dock: bool = false) -> void:
	if building.is_empty():
		return
	_last_detail_building = building
	var panel := _active_building_panel()
	panel.set("empire_dock", empire_dock)
	panel.move_to_front()
	panel.show_building(building)

## Build the Tile View Panel. Called by the `info_panel` property the first time anything
## asks for it — a tile click, a stockpile flow, a tool. Everything it needs (HUDContent,
## the DS theme, the signals it connects to) exists from _build_base onward, and the panel
## anchors itself in its own _ready, so building it late is indistinguishable from building
## it early except in when the ~740 ms is paid.
func _build_info_panel() -> void:
	if _info_panel != null:
		return
	_info_panel = load("res://scripts/tile_info_panel_v2.gd").new()
	_info_panel.name = "TileInfoPanel"
	hud_content.add_child(_info_panel)
	_info_panel.building_clicked.connect(_on_v2_building_clicked)
	_info_panel.pick_destination_requested.connect(_on_v2_pick_destination)
	_info_panel.survey_requested.connect(_on_survey_tile_clicked)


## Dialogs, the debug terminal and the two effect layers.
##
## Every one of these is a LISTENER — it exists so that some later gameplay event has
## something to pop, animate or print. None of them is needed to start a match, and building
## the set cost 0.7 s in one frame of the load. Under a loading screen that is a frozen frame,
## which used to be invisible and is not any more: the screen may be playing a film.
##
## `paced` hands a frame back between each, so the cost lands as a run of ordinary frames
## rather than one stall. It is false for tests / e2e / tools, which build the set inline at
## the end of _build_base exactly as before and expect it present the moment the world is.
func _build_dialogs_and_fx(paced: bool) -> void:
	if _dialogs_built:
		return
	_dialogs_built = true
	var t := Time.get_ticks_usec()

	# Prompts the player when a tile first hits max storage.
	_hud.add_child(load("res://scripts/capacity_dialog.gd").new())
	_prof_us("  dialog: capacity", t)
	if paced:
		await get_tree().process_frame

	# Prompts when construction materials arrive at a full tile.
	t = Time.get_ticks_usec()
	var overflow_dialog: Node = load("res://scripts/overflow_dialog.gd").new()
	_hud.add_child(overflow_dialog)
	overflow_dialog.go_to_stockpile_requested.connect(_on_go_to_tile_stockpile)
	_prof_us("  dialog: overflow", t)
	if paced:
		await get_tree().process_frame

	# Over-delivery and tagged shipments still in flight after a premium order is gone.
	t = Time.get_ticks_usec()
	_special_order_resolution_dialog = load("res://scripts/special_order_resolution_dialog.gd").new()
	_hud.add_child(_special_order_resolution_dialog)
	_special_order_resolution_dialog.reroute_requested.connect(_on_special_order_reroute_requested)
	_prof_us("  dialog: special order", t)
	if paced:
		await get_tree().process_frame

	# Opened by clicking a tile in the Surveying mapmode.
	t = Time.get_ticks_usec()
	_survey_dialog = load("res://scripts/survey_dialog.gd").new()
	_hud.add_child(_survey_dialog)
	_prof_us("  dialog: survey", t)
	if paced:
		await get_tree().process_frame

	# Debug cheat terminal (toggle with the ` key).
	t = Time.get_ticks_usec()
	add_child(load("res://scripts/debug_terminal.gd").new())
	_prof_us("  debug terminal", t)
	if paced:
		await get_tree().process_frame

	# Floating £ that rises from a port whenever a market sale lands there.
	t = Time.get_ticks_usec()
	var sale_fx: CanvasLayer = load("res://scripts/sale_effects.gd").new()
	sale_fx.terrain_layer = terrain_layer
	add_child(sale_fx)
	_prof_us("  sale effects", t)
	if paced:
		await get_tree().process_frame

	# Collapsing-hex + rising-deposit-icon animation when a tile finishes surveying.
	t = Time.get_ticks_usec()
	var survey_fx: Node2D = load("res://scripts/survey_effects.gd").new()
	survey_fx.name = "SurveyEffects"
	survey_fx.terrain_layer = terrain_layer
	add_child(survey_fx)
	_prof_us("  survey effects", t)


## Build the Building Detail v2 panel — same lazy contract as _build_info_panel.
func _build_building_panel_v2() -> void:
	if _bdp_v2 != null:
		return
	_bdp_v2 = load("res://scripts/building_detail_panel_v2.gd").new()
	_bdp_v2.name = "BuildingDetailPanelV2"
	hud_content.add_child(_bdp_v2)
	_bdp_v2.hide()
	_bdp_v2.building_connections_changed.connect(
		building_connection_visuals.on_building_connections_changed
	)


## The building-detail panel currently selected by the `swap bdp` dev-toggle.
func _active_building_panel() -> PanelContainer:
	if MatchState.use_bdp_v2:
		return building_panel_v2   # property: builds it on the first building click
	return building_panel

## Hide whichever detail panel(s) may be open (both, to survive a mid-open swap).
## Uses the backing field, not the property: hiding a panel that was never built must
## not build it.
func _hide_building_detail() -> void:
	building_panel.hide()
	if _bdp_v2 != null:
		_bdp_v2.hide()

## `swap bdp` flipped: drop both panels, re-render the last building in the now-active one.
func _on_bdp_v2_changed(_enabled: bool) -> void:
	var was_open := building_panel.visible or (_bdp_v2 != null and _bdp_v2.visible)
	_hide_building_detail()
	if was_open and not _last_detail_building.is_empty():
		_open_building_detail(_last_detail_building)

func _on_output_stockpile_selection_started(selection: Dictionary) -> void:
	_pending_stockpile_selection = selection.duplicate()
	var good_id: String = selection.get("good_id", "")
	terrain_layer.begin_stockpile_destination_selection(good_id)
	_show_stockpile_select_prompt(selection)
	_enter_stockpile_ui_mode()

func _on_output_stockpile_selection_cancelled() -> void:
	_pending_stockpile_selection.clear()
	terrain_layer.end_stockpile_destination_selection()
	_hide_stockpile_select_prompt()
	_exit_stockpile_ui_mode()

func _logistics_overlay() -> Node:
	return get_tree().get_first_node_in_group("logistics_overlay")

func _on_transfer_requested(good_id: String) -> void:
	_build_transfer_dialog()
	_transfer = {"good": good_id, "origin": "", "qty": 0, "dest": "", "state": "origin"}
	_tr_title.text = "Transfer %s" % Catalog.get_display_name(good_id)
	_tr_origin.text = "From: pick a green tile"
	_tr_dest.text = "To: —"
	_tr_cost.text = ""
	_tr_recurring.set_pressed_no_signal(false)
	_tr_cta.text = "Transfer"
	_tr_cta.disabled = true
	_transfer_dialog.visible = true
	if _tr_legend_panel != null:
		_tr_legend_panel.visible = true
	_enter_transfer_ui()
	_update_transfer_highlights()
	_update_transfer_legend()
	_update_transfer_modal()
	var _ov := _logistics_overlay()
	if _ov != null and _ov.has_method("set_hover_good"):
		_ov.set_hover_good(good_id)
	terrain_layer.begin_stockpile_destination_selection("", false)  # capture clicks, no terrain overlays

func _on_transfer_tile_picked(tile_data: Dictionary) -> void:
	var tile_id := str(tile_data.get("id", ""))
	if tile_id == "":
		return
	var good := str(_transfer.get("good", ""))
	if str(_transfer.get("state", "")) == "origin":
		# Reject tiles with neither stock nor production of the good.
		if Stockpile.get_at_tile(tile_id, good) <= 0 and not MatchState.tiles_producing(good).has(tile_id):
			MatchState.request_toast("Cannot select tile. No %s available to be transferred." % Catalog.get_display_name(good), "warning")
			terrain_layer.call_deferred("begin_stockpile_destination_selection", "", false)  # re-arm
			return
		_transfer["origin"] = tile_id
		var stock := Stockpile.get_at_tile(tile_id, good)
		_transfer["qty"] = stock if stock > 0 else _tile_production_per_turn(tile_id, good)
		_tr_origin.text = "From: %s" % Catalog.tile_label(tile_id)
		_tr_qty.set_value_no_signal(float(maxi(1, int(_transfer["qty"]))))
		_tr_qty.grab_focus()
		_transfer["state"] = "dest"
		_update_transfer_highlights()
		_update_transfer_cost()
		_update_transfer_cap()
		_update_transfer_legend()
		_update_transfer_modal()
		terrain_layer.call_deferred("begin_stockpile_destination_selection", "", false)  # re-arm for destination
	elif str(_transfer.get("state", "")) == "dest":
		if tile_id == str(_transfer.get("origin", "")):
			terrain_layer.call_deferred("begin_stockpile_destination_selection", "", false)
			return
		_transfer["dest"] = tile_id
		_tr_dest.text = "To: %s" % Catalog.tile_label(tile_id)
		_transfer["state"] = "ready"
		terrain_layer.end_stockpile_destination_selection()
		_update_transfer_highlights()
		_update_transfer_cost()
		_update_transfer_modal()
		_tr_cta.disabled = false

func _relevant_transfer_tiles() -> Array:
	var s: Dictionary = {}
	for t in MatchState.tile_buildings.keys():
		s[str(t)] = true
	for t in Stockpile.tiles_with_stock():
		if str(t).begins_with("tile_"):
			s[str(t)] = true
	return s.keys()

func _update_transfer_highlights() -> void:
	if _transfer.is_empty():
		return
	var good := str(_transfer.get("good", ""))
	var producing := MatchState.tiles_producing(good)
	var consuming := MatchState.tiles_consuming(good)
	var origin := str(_transfer.get("origin", ""))
	var highlights: Dictionary = {}
	if str(_transfer.get("state", "")) == "origin":
		for tid in _relevant_transfer_tiles():
			if Stockpile.get_at_tile(tid, good) > 0:
				highlights[tid] = _TR_LIGHT_GREEN
			elif producing.has(tid):
				highlights[tid] = _TR_DARK_GREEN
			else:
				highlights[tid] = _TR_RED
	else:
		var qty := int(_transfer.get("qty", 0))
		for tid in _relevant_transfer_tiles():
			if tid == origin:
				continue
			var consumes: bool = consuming.has(tid)
			var produces: bool = producing.has(tid)
			if consumes and not produces:
				highlights[tid] = _TR_LIGHT_GREEN
			elif consumes and produces:
				highlights[tid] = _TR_DARK_GREEN
			elif Stockpile.get_free_capacity(tid) < qty:
				highlights[tid] = _TR_RED
	var ov := _logistics_overlay()
	if ov != null and ov.has_method("set_transfer_state"):
		ov.set_transfer_state(true, highlights, origin, str(_transfer.get("dest", "")))

func _update_transfer_cost() -> void:
	if _transfer.is_empty() or _tr_cost == null:
		return
	var origin := str(_transfer.get("origin", ""))
	var dest := str(_transfer.get("dest", ""))
	var good := str(_transfer.get("good", ""))
	var qty := int(_transfer.get("qty", 0))
	var recurring: bool = _tr_recurring != null and _tr_recurring.button_pressed
	if origin != "" and dest != "" and qty > 0:
		var prev: Dictionary = MatchState.preview_move(origin, dest, {good: qty})
		var cost := float(prev.get("cost", 0.0))
		_tr_cost.text = ("Transport cost: £%.2f every turn" % cost) if recurring else ("Transport cost: £%.2f, one off" % cost)
	else:
		_tr_cost.text = ""
	if _tr_cta != null:
		_tr_cta.text = "Transfer %d %s%s" % [qty, Catalog.get_display_name(good), " every turn" if recurring else ""]

func _on_transfer_qty_changed(value: float) -> void:
	if _transfer.is_empty():
		return
	_transfer["qty"] = int(value)
	if str(_transfer.get("state", "")) != "origin":
		_update_transfer_highlights()
	_update_transfer_cost()
	_update_transfer_cap()

func _on_transfer_recurring_toggled(_pressed: bool) -> void:
	_update_transfer_cost()

func _on_transfer_confirm() -> void:
	if _transfer.is_empty():
		return
	var origin := str(_transfer.get("origin", ""))
	var dest := str(_transfer.get("dest", ""))
	var good := str(_transfer.get("good", ""))
	var qty := int(_transfer.get("qty", 0))
	if origin == "" or dest == "" or qty <= 0:
		return
	var summary: Dictionary = MatchState.queue_move(origin, dest, {good: qty})
	if not summary.is_empty():
		MatchState.request_toast("Transferring %d %s from %s to %s" % [
			qty, Catalog.get_display_name(good), Catalog.tile_label(origin), Catalog.tile_label(dest)], "success")
	if _tr_recurring != null and _tr_recurring.button_pressed:
		MatchState.add_recurring_move(origin, dest, {good: qty})
	_close_transfer()

func _close_transfer() -> void:
	_transfer = {}
	terrain_layer.end_stockpile_destination_selection()
	var ov := _logistics_overlay()
	if ov != null and ov.has_method("clear_transfer"):
		ov.clear_transfer()
	if _transfer_dialog != null:
		_transfer_dialog.visible = false
	if _tr_legend_panel != null:
		_tr_legend_panel.visible = false
	if _tr_modal != null:
		_tr_modal.visible = false
	_exit_transfer_ui()

func _enter_transfer_ui() -> void:
	if _info_panel != null:
		_info_panel.hide()
	_hide_building_detail()
	if _hud.has_method("hide_bottom_menu"):
		_hud.hide_bottom_menu()

func _exit_transfer_ui() -> void:
	if _hud.has_method("show_bottom_menu"):
		_hud.show_bottom_menu()

func _build_transfer_dialog() -> void:
	if _transfer_dialog != null:
		return
	_transfer_dialog = PanelContainer.new()
	_transfer_dialog.theme = DS.theme
	_transfer_dialog.anchor_left = 1.0
	_transfer_dialog.anchor_right = 1.0
	_transfer_dialog.offset_left = -340.0
	_transfer_dialog.offset_right = -20.0
	_transfer_dialog.offset_top = 80.0
	_transfer_dialog.offset_bottom = 440.0
	_transfer_dialog.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_transfer_dialog.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	_tr_title = Label.new()
	_tr_title.add_theme_font_size_override("font_size", 18)
	vb.add_child(_tr_title)
	_tr_origin = Label.new()
	vb.add_child(_tr_origin)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	var qlbl := Label.new()
	qlbl.text = "Quantity (scroll to change)"
	qlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(qlbl)
	_tr_qty = SpinBox.new()
	_tr_qty.min_value = 1
	_tr_qty.max_value = 99999
	_tr_qty.step = 1
	_tr_qty.value = 1
	_tr_qty.value_changed.connect(_on_transfer_qty_changed)
	qrow.add_child(_tr_qty)
	vb.add_child(qrow)
	_tr_cap = Label.new()
	_tr_cap.add_theme_font_size_override("font_size", 12)
	_tr_cap.add_theme_color_override("font_color", Color.WHITE)
	_tr_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tr_cap.visible = false
	vb.add_child(_tr_cap)
	_tr_dest = Label.new()
	vb.add_child(_tr_dest)
	var transfer_legend := _make_bottom_left_legend("TransferLegend", "Tile colours", 250.0, 132.0)
	_tr_legend_panel = transfer_legend["panel"]
	_tr_legend = transfer_legend["entries"]
	_tr_cost = Label.new()
	_tr_cost.add_theme_font_size_override("font_size", 13)
	vb.add_child(_tr_cost)
	_tr_recurring = UIHelpers.make_custom_checkbox()
	_tr_recurring.toggled.connect(_on_transfer_recurring_toggled)
	vb.add_child(UIHelpers.make_setting_row("Make recurring every turn", _tr_recurring))
	_tr_cta = Button.new()
	_tr_cta.text = "Transfer"
	_tr_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tr_cta.pressed.connect(_on_transfer_confirm)
	vb.add_child(_tr_cta)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_transfer)
	vb.add_child(cancel)
	_hud.add_child(_transfer_dialog)
	# Bottom step modal (above the bottom menu).
	_tr_modal = PanelContainer.new()
	_tr_modal.theme = DS.theme
	_tr_modal.anchor_left = 0.5
	_tr_modal.anchor_right = 0.5
	_tr_modal.anchor_top = 1.0
	_tr_modal.anchor_bottom = 1.0
	_tr_modal.offset_left = -180.0
	_tr_modal.offset_right = 180.0
	_tr_modal.offset_top = -156.0
	_tr_modal.offset_bottom = -112.0
	_tr_modal.visible = false
	var mmargin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mmargin.add_theme_constant_override("margin_" + side, 10)
	_tr_modal.add_child(mmargin)
	_tr_modal_label = Label.new()
	_tr_modal_label.add_theme_font_size_override("font_size", 16)
	_tr_modal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mmargin.add_child(_tr_modal_label)
	_hud.add_child(_tr_modal)

func _tile_production_per_turn(tile: String, good: String) -> int:
	var total := 0
	for iid in MatchState.tile_buildings.get(tile, []):
		var b: Dictionary = MatchState.get_building(str(iid))
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		total += Catalog.recipe_output_qty(recipe, good)
	return total

func _update_transfer_cap() -> void:
	if _tr_cap == null or _transfer.is_empty():
		return
	var origin := str(_transfer.get("origin", ""))
	var good := str(_transfer.get("good", ""))
	var qty := int(_transfer.get("qty", 0))
	if origin == "":
		_tr_cap.visible = false
		return
	var avail := Stockpile.get_at_tile(origin, good) + _tile_production_per_turn(origin, good)
	if qty > avail and avail >= 0:
		_tr_cap.text = "Only %d %s available — the transfer will move the maximum." % [avail, Catalog.get_display_name(good)]
		_tr_cap.visible = true
	else:
		_tr_cap.visible = false

func _update_transfer_modal() -> void:
	if _tr_modal == null:
		return
	match str(_transfer.get("state", "")):
		"origin":
			_tr_modal_label.text = "Select origin tile"
			_tr_modal.visible = true
		"dest":
			_tr_modal_label.text = "Set quantity, then select destination tile"
			_tr_modal.visible = true
		_:
			_tr_modal.visible = false

func _legend_row(swatch: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = swatch
	rect.custom_minimum_size = Vector2(14, 14)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rect)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return row

func _make_bottom_left_legend(panel_name: String, title: String, width: float, height: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.theme = DS.theme
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(width, height)
	_pin_bottom_left_legend(panel, width, height)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.92)
	style.border_color = Color(0.995, 0.93, 0.76, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", Color(0.995, 0.93, 0.76, 0.7))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_label)

	var entries := VBoxContainer.new()
	entries.add_theme_constant_override("separation", 2)
	entries.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(entries)
	hud_content.add_child(panel)
	return {"panel": panel, "entries": entries}

func _pin_bottom_left_legend(panel: Control, width: float, height: float) -> void:
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = LEGEND_LEFT
	panel.offset_right = LEGEND_LEFT + width
	panel.offset_top = -(height + LEGEND_BOTTOM)
	panel.offset_bottom = -LEGEND_BOTTOM

func _update_transfer_legend() -> void:
	if _tr_legend == null:
		return
	for c in _tr_legend.get_children():
		c.queue_free()
	if str(_transfer.get("state", "")) == "origin":
		_tr_legend.add_child(_legend_row(_TR_LIGHT_GREEN, "Has it in stockpile"))
		_tr_legend.add_child(_legend_row(_TR_DARK_GREEN, "Produces it"))
	else:
		_tr_legend.add_child(_legend_row(_TR_YELLOW, "Selected origin"))
		_tr_legend.add_child(_legend_row(_TR_LIGHT_GREEN, "Consumes it"))
		_tr_legend.add_child(_legend_row(_TR_DARK_GREEN, "Consumes & produces"))
		_tr_legend.add_child(_legend_row(_TR_RED, "Can't fit this quantity"))

# ===== Per-good BUY flow (market origin; Shift-click multiplies the order) =====

func _on_purchase_requested(good_id: String) -> void:
	_build_buy_dialog()
	_buy = {"good": good_id, "qty": 10, "tiles": [], "state": "dest"}
	_buy_title.text = "Buy %s" % Catalog.get_display_name(good_id)
	_buy_dest.text = "Deliver to: pick a tile"
	_buy_cost.text = ""
	_buy_recurring.set_pressed_no_signal(false)
	_buy_qty.set_value_no_signal(10.0)
	_buy_cta.text = "Buy"
	_buy_cta.disabled = true
	_buy_dialog.visible = true
	if _buy_legend_panel != null:
		_buy_legend_panel.visible = true
	_enter_transfer_ui()
	_update_buy_highlights()
	_update_buy_legend()
	_update_buy_modal()
	var _ov := _logistics_overlay()
	if _ov != null and _ov.has_method("set_hover_good"):
		_ov.set_hover_good(good_id)
	terrain_layer.begin_stockpile_destination_selection("", false)

func _on_buy_tile_picked(tile_data: Dictionary) -> void:
	var tile_id := str(tile_data.get("id", ""))
	if tile_id == "":
		return
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var tiles: Array = _buy.get("tiles", [])
	if not tiles.has(tile_id):
		tiles.append(tile_id)
	_buy["tiles"] = tiles
	_update_buy_dest_label()
	_update_buy_highlights()
	_update_buy_cost()
	if _buy_cta != null:
		_buy_cta.disabled = tiles.is_empty()
	if shift:
		_buy["state"] = "multi"
		_update_buy_modal()
		terrain_layer.call_deferred("begin_stockpile_destination_selection", "", false)
	else:
		_buy["state"] = "ready"
		terrain_layer.end_stockpile_destination_selection()
		_update_buy_modal()

func _update_buy_dest_label() -> void:
	if _buy_dest == null:
		return
	var tiles: Array = _buy.get("tiles", [])
	if tiles.is_empty():
		_buy_dest.text = "Deliver to: pick a tile"
	elif tiles.size() == 1:
		_buy_dest.text = "Deliver to: %s" % Catalog.tile_label(str(tiles[0]))
	else:
		_buy_dest.text = "Deliver to: %d tiles" % tiles.size()

func _update_buy_highlights() -> void:
	if _buy.is_empty():
		return
	var good := str(_buy.get("good", ""))
	var producing := MatchState.tiles_producing(good)
	var consuming := MatchState.tiles_consuming(good)
	var qty := int(_buy.get("qty", 0))
	var highlights: Dictionary = {}
	for tid in _relevant_transfer_tiles():
		var consumes: bool = consuming.has(tid)
		var produces: bool = producing.has(tid)
		if consumes and not produces:
			highlights[tid] = _TR_LIGHT_GREEN
		elif consumes and produces:
			highlights[tid] = _TR_DARK_GREEN
		elif Stockpile.get_free_capacity(tid) < qty:
			highlights[tid] = _TR_RED
	for tid in _buy.get("tiles", []):
		highlights[str(tid)] = _TR_YELLOW
	var ov := _logistics_overlay()
	if ov != null and ov.has_method("set_transfer_state"):
		ov.set_transfer_state(true, highlights, "", "")

func _update_buy_cost() -> void:
	if _buy.is_empty() or _buy_cost == null:
		return
	var good := str(_buy.get("good", ""))
	var qty := int(_buy.get("qty", 0))
	var tiles: Array = _buy.get("tiles", [])
	var recurring: bool = _buy_recurring != null and _buy_recurring.button_pressed
	if tiles.is_empty() or qty <= 0:
		_buy_cost.text = ""
	else:
		var total := 0.0
		var goods := 0.0
		var transport := 0.0
		var max_turns := 0
		for tid in tiles:
			var prev: Dictionary = MatchState.preview_buy(str(tid), good, qty)
			total += float(prev.get("cost", 0.0))
			goods += float(prev.get("goods_cost", 0.0))
			transport += float(prev.get("transport_cost", 0.0))
			max_turns = maxi(max_turns, int(prev.get("turns", 0)))
		var suffix := " every turn" if recurring else ", one off"
		_buy_cost.text = "Cost: £%.2f (goods £%.2f + transport £%.2f)%s\nArrives in %d turn%s" % [
			total, goods, transport, suffix, max_turns, "" if max_turns == 1 else "s"]
	if _buy_cta != null:
		var n: int = tiles.size()
		var times := (" × %d tiles" % n) if n > 1 else ""
		var rec := " every turn" if recurring else ""
		_buy_cta.text = "Buy %d %s%s%s" % [qty, Catalog.get_display_name(good), times, rec]

func _on_buy_qty_changed(value: float) -> void:
	if _buy.is_empty():
		return
	_buy["qty"] = int(value)
	_update_buy_highlights()
	_update_buy_cost()

func _on_buy_recurring_toggled(_pressed: bool) -> void:
	_update_buy_cost()

func _on_buy_confirm() -> void:
	if _buy.is_empty():
		return
	var good := str(_buy.get("good", ""))
	var qty := int(_buy.get("qty", 0))
	var tiles: Array = _buy.get("tiles", [])
	if tiles.is_empty() or qty <= 0:
		return
	var recurring: bool = _buy_recurring != null and _buy_recurring.button_pressed
	var bought := 0
	for tid in tiles:
		if recurring:
			# A standing order executes (and is logged) every turn by production — don't
			# also fire a one-off buy now, or it double-buys and double-lists.
			MatchState.add_recurring_buy(str(tid), good, qty)
		else:
			var summary: Dictionary = MatchState.queue_buy(str(tid), good, qty)
			if not summary.is_empty():
				bought += int(summary.get("qty", 0))
	if recurring:
		MatchState.request_toast("Will buy %d %s every turn to %d tile%s" % [
			qty, Catalog.get_display_name(good), tiles.size(), "" if tiles.size() == 1 else "s"], "success")
	else:
		MatchState.request_toast("Buying %d %s to %d tile%s" % [
			bought, Catalog.get_display_name(good), tiles.size(), "" if tiles.size() == 1 else "s"], "success")
	_close_buy()

func _close_buy() -> void:
	_buy = {}
	terrain_layer.end_stockpile_destination_selection()
	var ov := _logistics_overlay()
	if ov != null and ov.has_method("clear_transfer"):
		ov.clear_transfer()
	if _buy_dialog != null:
		_buy_dialog.visible = false
	if _buy_legend_panel != null:
		_buy_legend_panel.visible = false
	if _buy_modal != null:
		_buy_modal.visible = false
	_exit_transfer_ui()

func _update_buy_modal() -> void:
	if _buy_modal == null:
		return
	_buy_modal.visible = not _buy.is_empty() and str(_buy.get("state", "")) != "ready"

func _process(_delta: float) -> void:
	# Live-update the buy step modal so it flips to the multi-tile hint while Shift is held.
	if _buy.is_empty() or _buy_modal == null or not _buy_modal.visible:
		return
	var want := "Select multiple tiles to multiply order" if Input.is_key_pressed(KEY_SHIFT) \
		else "Set quantity, then select a delivery tile  (hold Shift for multiple)"
	if _buy_modal_label.text != want:
		_buy_modal_label.text = want

func _update_buy_legend() -> void:
	if _buy_legend == null:
		return
	for c in _buy_legend.get_children():
		c.queue_free()
	_buy_legend.add_child(_legend_row(_TR_LIGHT_GREEN, "Consumes it (needs delivery)"))
	_buy_legend.add_child(_legend_row(_TR_DARK_GREEN, "Consumes & produces"))
	_buy_legend.add_child(_legend_row(_TR_YELLOW, "Selected delivery tile"))
	_buy_legend.add_child(_legend_row(_TR_RED, "No room for this quantity"))

func _build_buy_dialog() -> void:
	if _buy_dialog != null:
		return
	_buy_dialog = PanelContainer.new()
	_buy_dialog.theme = DS.theme
	_buy_dialog.anchor_left = 1.0
	_buy_dialog.anchor_right = 1.0
	_buy_dialog.offset_left = -340.0
	_buy_dialog.offset_right = -20.0
	_buy_dialog.offset_top = 80.0
	_buy_dialog.offset_bottom = 470.0
	_buy_dialog.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_buy_dialog.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	_buy_title = Label.new()
	_buy_title.add_theme_font_size_override("font_size", 18)
	vb.add_child(_buy_title)
	var src := Label.new()
	src.text = "From: World market (ships via nearest port)"
	src.add_theme_font_size_override("font_size", 12)
	src.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(src)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	var qlbl := Label.new()
	qlbl.text = "Quantity (scroll to change)"
	qlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(qlbl)
	_buy_qty = SpinBox.new()
	_buy_qty.min_value = 1
	_buy_qty.max_value = 99999
	_buy_qty.step = 1
	_buy_qty.value = 10
	_buy_qty.value_changed.connect(_on_buy_qty_changed)
	qrow.add_child(_buy_qty)
	vb.add_child(qrow)
	_buy_dest = Label.new()
	vb.add_child(_buy_dest)
	var buy_legend := _make_bottom_left_legend("BuyLegend", "Tile colours", 250.0, 144.0)
	_buy_legend_panel = buy_legend["panel"]
	_buy_legend = buy_legend["entries"]
	_buy_cost = Label.new()
	_buy_cost.add_theme_font_size_override("font_size", 13)
	_buy_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_buy_cost)
	_buy_recurring = UIHelpers.make_custom_checkbox()
	_buy_recurring.toggled.connect(_on_buy_recurring_toggled)
	vb.add_child(UIHelpers.make_setting_row("Make recurring every turn", _buy_recurring))
	_buy_cta = Button.new()
	_buy_cta.text = "Buy"
	_buy_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_cta.pressed.connect(_on_buy_confirm)
	vb.add_child(_buy_cta)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_buy)
	vb.add_child(cancel)
	_hud.add_child(_buy_dialog)
	# Bottom step modal.
	_buy_modal = PanelContainer.new()
	_buy_modal.theme = DS.theme
	_buy_modal.anchor_left = 0.5
	_buy_modal.anchor_right = 0.5
	_buy_modal.anchor_top = 1.0
	_buy_modal.anchor_bottom = 1.0
	_buy_modal.offset_left = -230.0
	_buy_modal.offset_right = 230.0
	_buy_modal.offset_top = -156.0
	_buy_modal.offset_bottom = -112.0
	_buy_modal.visible = false
	var mmargin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mmargin.add_theme_constant_override("margin_" + side, 10)
	_buy_modal.add_child(mmargin)
	_buy_modal_label = Label.new()
	_buy_modal_label.add_theme_font_size_override("font_size", 16)
	_buy_modal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mmargin.add_child(_buy_modal_label)
	_hud.add_child(_buy_modal)

func _on_buy_tile_pick_requested() -> void:
	_picking_buy_tile = true
	terrain_layer.begin_stockpile_destination_selection("")
	_enter_stockpile_ui_mode()

func _tile_data_by_id(tile_id: String) -> Dictionary:
	for coord in terrain_layer.tiles:
		var td: Dictionary = terrain_layer.tiles[coord]
		if str(td.get("id", "")) == tile_id:
			return td
	return {}

## The top bar's Transport module. Built on first use — nothing in a match needs the
## logistics panel to exist until the player opens it, and the load is already the
## thing this project spends the most care protecting.
func _on_transport_panel_requested() -> void:
	if _transport_panel == null or not is_instance_valid(_transport_panel):
		_transport_panel = load("res://scripts/transport_panel.gd").new()
		hud_content.add_child(_transport_panel)
	_transport_panel.open()

func _on_go_to_tile_stockpile(tile_id: String) -> void:
	var td := _tile_data_by_id(tile_id)
	if td.is_empty():
		return
	_last_selected_tile = td
	info_panel._active_tab = "stock"
	info_panel.show_tile(td)
	# show_tile resets to the Buildings tab, so ask for Stockpile again afterwards.
	info_panel._select_tab("stock")

## Deep-link target for notifications etc: centre the camera on the tile and
## open its panel. Emitted via MatchState.focus_tile_requested.
func _on_focus_tile_requested(tile_id: String) -> void:
	var td := _focus_camera_on_tile(tile_id)
	if td.is_empty():
		return
	_last_selected_tile = td
	info_panel.show_tile(td)

## UI-driven building selection (ledger row, empire view node, starvation
## notifications): pan to the tile and open BOTH the tile view panel and the
## building detail panel on top of it.
## From INSIDE the Empire view the map is hidden, so the pan and the tile panel
## would both happen invisibly behind the overlay — and the pan would leave the
## map somewhere else on Tab-out. There, ONLY the building detail panel opens,
## docked where the tile view panel normally sits (owner 2026-07-31).
func _on_focus_building_requested(instance_id: String) -> void:
	var building: Dictionary = MatchState.get_building(instance_id)
	if building.is_empty():
		return
	if empire_view != null and empire_view.visible:
		_open_building_detail(building, true)
		return
	var td := _focus_camera_on_tile(str(building.get("tile_id", "")))
	if not td.is_empty():
		_last_selected_tile = td
		info_panel.show_tile(td)
	_open_building_detail(building)

## Pan the camera to a tile over 0.3s (UI-driven selection only — clicking a
## tile directly on the map never pans); returns its tile_data ({} if unknown).
## Put the camera where the intro zoom would have LEFT it, before anything is painted.
##
## The map is painted at zoom_min otherwise, which frames the ENTIRE map — the most expensive
## thing this game ever draws, at ~24,450 draw calls against ~7,700 for the view the player
## actually plays at. The intro zoom then spends a second travelling from one to the other.
##
## NOTE the draw-call count is not what makes the reveal slow: cutting it 3x on its own moved
## the reveal frame by ~10%, because most of that frame was the forced repaint in
## reveal_for_play, not the geometry. With that repaint gone this is worth a further halving.
func _place_camera_at_play_zoom() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or not cam.has_method("_effective_zoom_min"):
		return
	var zmin: float = cam.call("_effective_zoom_min")
	var zmax: float = float(cam.get("zoom_max"))
	var z := lerpf(zmin, zmax, LoadingScreen.ZOOM_FRAC)
	cam.zoom = Vector2.ONE * z
	cam.set("_target_zoom", cam.zoom)
	if OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF camera placed at play zoom %.3f (was %.3f, max %.3f)" % [z, zmin, zmax])


func _focus_camera_on_tile(tile_id: String) -> Dictionary:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not terrain_layer.tiles.has(coord):
		return {}
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var cell := terrain_layer.map_coord_for_tile_coord(coord)
		var target: Vector2 = terrain_layer.to_global(terrain_layer.map_to_local(cell))
		if cam.has_method("pan_to_world"):
			# ui_focus_duration is the camera controller's own tunable (the tutorial raises
			# it); fall back if any other Camera2D is ever the active one.
			var dur = cam.get("ui_focus_duration")
			cam.pan_to_world(target, float(dur) if dur != null else 0.3)
		else:
			cam.position = target
	return terrain_layer.tiles[coord]

func _on_v2_pick_destination() -> void:
	# Enter map pick mode but keep the v2 panel visible; the result returns via
	# on_destination_picked() so the player can then confirm in the panel. Step 24
	# supplies its own precise white flash, so suppress the broad green category and
	# hover paint there while keeping the map click capture active.
	_v2_picking_dest = true
	var paint_overlay := not Tutorial.is_active_step("transport_redirect_pick")
	terrain_layer.begin_stockpile_destination_selection("", paint_overlay)

func _on_special_order_reroute_requested() -> void:
	_special_order_reroute_picking = true
	terrain_layer.begin_stockpile_destination_selection("")
	_enter_stockpile_ui_mode()
	MatchState.request_toast("Pick a destination tile for the remaining special-order shipments", "info")

func _on_stockpile_destination_selected(tile_data: Dictionary, ctrl: bool = false, shift: bool = false) -> void:
	if _v2_picking_dest:
		_v2_picking_dest = false
		terrain_layer.end_stockpile_destination_selection()
		info_panel.on_destination_picked(str(tile_data.get("id", "")))
		return
	if _special_order_reroute_picking:
		_special_order_reroute_picking = false
		terrain_layer.end_stockpile_destination_selection()
		_exit_stockpile_ui_mode()
		if _special_order_resolution_dialog != null:
			_special_order_resolution_dialog.call("reroute_current_to", str(tile_data.get("id", "")))
		return
	if not _buy.is_empty():
		_on_buy_tile_picked(tile_data)
		return
	if not _transfer.is_empty():
		_on_transfer_tile_picked(tile_data)
		return
	if _picking_buy_tile:
		_picking_buy_tile = false
		terrain_layer.end_stockpile_destination_selection()
		_exit_stockpile_ui_mode()
		MatchState.buy_tile_picked.emit(str(tile_data.get("id", "")))
		return
	if _pending_stockpile_selection.is_empty():
		return
	var instance_id: String = _pending_stockpile_selection.get("instance_id", "")
	var good_id: String = _pending_stockpile_selection.get("good_id", "")
	var tile_id: String = tile_data.get("id", "")
	var allow_split := bool(_pending_stockpile_selection.get("allow_split", false))
	if allow_split and shift:
		var count := MatchState.add_output_split_destination(instance_id, good_id, tile_id)
		if count >= 3:
			_pending_stockpile_selection.clear()
			_hide_stockpile_select_prompt()
			terrain_layer.end_stockpile_destination_selection()
			_exit_stockpile_ui_mode()
			_open_building_detail(MatchState.get_building(instance_id))
		else:
			MatchState.request_toast("%d destination%s selected — Shift-click another, or release Shift and click to finish" % [count, "" if count == 1 else "s"], "info")
		return
	if allow_split and MatchState.get_output_split_destinations(instance_id, good_id).size() >= 2:
		# A regular click after selecting two or three destinations is an explicit
		# "done" action; clicking a selected tile avoids accidentally changing it.
		_pending_stockpile_selection.clear()
		_hide_stockpile_select_prompt()
		_exit_stockpile_ui_mode()
		_open_building_detail(MatchState.get_building(instance_id))
		return
	if ctrl:
		# CTRL+click: don't route yet — highlight the pick green and open the
		# ship-quantity panel (consumers on that tile + amount box + Confirm).
		_open_ship_quantity_panel(_pending_stockpile_selection.duplicate(), tile_id)
		_pending_stockpile_selection.clear()
		_hide_stockpile_select_prompt()
		return
	MatchState.set_output_stockpile_destination(instance_id, tile_id, good_id)
	_pending_stockpile_selection.clear()
	_hide_stockpile_select_prompt()
	_exit_stockpile_ui_mode()

# ----- CTRL+click ship-quantity flow -----

var _ship_qty_panel: PanelContainer = null
var _ship_qty_selection: Dictionary = {}
var _ship_qty_tile := ""

func _open_ship_quantity_panel(selection: Dictionary, tile_id: String) -> void:
	_ship_qty_selection = selection
	_ship_qty_tile = tile_id
	terrain_layer.mark_selected_destination(tile_id)
	if _ship_qty_panel == null:
		_ship_qty_panel = load("res://scripts/ship_quantity_panel.gd").new()
		_ship_qty_panel.name = "ShipQuantityPanel"
		_hud.add_child(_ship_qty_panel)
		_ship_qty_panel.confirmed.connect(_on_ship_qty_confirmed)
		_ship_qty_panel.cancelled.connect(_on_ship_qty_cancelled)
	_ship_qty_panel.open(selection, tile_id)

func _on_ship_qty_confirmed(qty: int) -> void:
	var iid := str(_ship_qty_selection.get("instance_id", ""))
	var gid := str(_ship_qty_selection.get("good_id", ""))
	if iid != "" and gid != "" and _ship_qty_tile != "" and qty > 0:
		MatchState.set_output_stockpile_destination(iid, _ship_qty_tile, gid)
		MatchState.set_output_ship_quantity(iid, gid, qty)
		MatchState.request_toast("Sending %d %s to %s every turn" % [qty, Catalog.get_display_name(gid), Catalog.tile_label(_ship_qty_tile)], "success")
	_close_ship_quantity_flow()

func _on_ship_qty_cancelled() -> void:
	_close_ship_quantity_flow()

func _close_ship_quantity_flow() -> void:
	_ship_qty_selection = {}
	_ship_qty_tile = ""
	terrain_layer.clear_selected_destination()
	_exit_stockpile_ui_mode()

func _cancel_special_order_reroute_pick() -> void:
	if not _special_order_reroute_picking:
		return
	_special_order_reroute_picking = false
	terrain_layer.end_stockpile_destination_selection()
	_exit_stockpile_ui_mode()
	if _special_order_resolution_dialog != null:
		_special_order_resolution_dialog.call("cancel_reroute")

# ----- Stockpile selection UI mode -----

func _enter_stockpile_ui_mode() -> void:
	if _info_panel != null:
		_info_panel.hide()
	_hide_building_detail()
	if _hud.has_method("hide_bottom_menu"):
		_hud.hide_bottom_menu()
	if _dim_overlay != null:
		_dim_overlay.visible = true
	if _stockpile_legend != null:
		_stockpile_legend.visible = true

func _exit_stockpile_ui_mode() -> void:
	if _hud.has_method("show_bottom_menu"):
		_hud.show_bottom_menu()
	if _dim_overlay != null:
		_dim_overlay.visible = false
	if _stockpile_legend != null:
		_stockpile_legend.visible = false

# ----- Dim overlay -----

func _build_dim_overlay() -> void:
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "StockpileDimOverlay"
	_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.10)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.visible = false
	hud_content.add_child(_dim_overlay)
	# Move to index 0 so all existing panels render on top
	hud_content.move_child(_dim_overlay, 0)

# ----- Stockpile legend -----

func _build_stockpile_legend() -> void:
	_stockpile_legend = PanelContainer.new()
	_stockpile_legend.name = "StockpileLegend"
	_stockpile_legend.visible = false
	_stockpile_legend.custom_minimum_size = Vector2(210, 0)
	_pin_bottom_left_legend(_stockpile_legend, 210.0, 136.0)
	_stockpile_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.92)
	style.border_color = Color(0.995, 0.93, 0.76, 0.5)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_stockpile_legend.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stockpile_legend.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Tile colours"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.995, 0.93, 0.76, 0.7))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	vbox.add_child(_make_legend_row(Color(0.35, 1.0, 0.35, 1.0), "Consumes this good"))
	vbox.add_child(_make_legend_row(Color(0.1,  0.45, 0.1,  1.0), "Has buildings"))
	vbox.add_child(_make_legend_row(Color(0.3,  0.3,  0.3,  1.0), "Empty tile"))

	hud_content.add_child(_stockpile_legend)

func _make_legend_row(color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_style := StyleBoxFlat.new()
	sw_style.bg_color = color
	sw_style.corner_radius_top_left = 2
	sw_style.corner_radius_top_right = 2
	sw_style.corner_radius_bottom_left = 2
	sw_style.corner_radius_bottom_right = 2
	swatch.add_theme_stylebox_override("panel", sw_style)
	row.add_child(swatch)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row

func _on_end_turn_pressed() -> void:
	# Arm verbose-log capture on the first End Turn of turn 1 (current_turn only
	# increments once resolution runs, so it is still 1 here). arm() is idempotent.
	if TurnManager.current_turn == 1:
		SessionLog.arm()
	TurnManager.commit_turn()

func _on_encyclopedia_pressed() -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia"):
		search_overlay.open_encyclopedia()

func _on_encyclopedia_entry_requested(entry_id: String) -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia_entry"):
		search_overlay.open_encyclopedia_entry(entry_id)

func _on_goods_graph_requested() -> void:
	if goods_graph_view != null:
		goods_graph_view.toggle()

func _on_goods_graph_good_requested(good_id: String) -> void:
	if goods_graph_view != null:
		goods_graph_view.open_focused(good_id)


func _on_empire_view_requested() -> void:
	if empire_view != null:
		empire_view.toggle()

## Open the Research tree filtered to one tech. Goes through the bottom menu so the panel
## opens the same way a click on the Research button does — stack, rise tween and all.
func _on_research_search_requested(query: String) -> void:
	if _hud == null or not _hud.has_method("open_research_search"):
		return
	_hud.open_research_search(query)

func _on_encyclopedia_good_requested(good_id: String) -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia_good"):
		search_overlay.open_encyclopedia_good(good_id)

func _on_search_recipe_build_requested(building_id: String, recipe_id: String) -> void:
	BuildMode.enter_build_mode(building_id, recipe_id)

func _on_build_attempted(building_id: String, tile_id: String) -> void:
	print("[Build] attempt: building=%s tile=%s" % [building_id, tile_id])
	if _tutorial_blocks(tile_id):
		return
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		print("[Build] FAILED: tile_id %s did not resolve to a coord (id_to_coord returned -1,-1)" % tile_id)
		return

	var recipe_id: String = BuildMode.current_recipe_id
	if recipe_id == "":
		print("[Build] FAILED: no recipe selected (BuildMode.current_recipe_id is empty)")
		push_warning("Build attempted with no recipe selected")
		return
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		print("[Build] FAILED: unknown recipe %s (Catalog.get_recipe returned empty)" % recipe_id)
		push_warning("Build attempted with unknown recipe %s" % recipe_id)
		return
	if not terrain_layer.tiles.has(coord):
		print("[Build] WARNING: terrain_layer.tiles has no entry for coord %s (skipping requirement check)" % str(coord))
	else:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		# Terrain rule: only offshore wind / offshore oil on sea/deep_sea; everything else is
		# land-only (and those two cannot be placed on land).
		var tile_type := str(tile_data.get("type", ""))
		if not Catalog.is_building_allowed_on_tile_type(building_id, tile_type):
			var is_sea := tile_type == "sea" or tile_type == "deep_sea"
			MatchState.request_toast(
				"That can't be built at sea — only offshore wind and oil platforms can." if is_sea
				else "Offshore buildings can only be built on sea or deep-sea tiles.", "warning")
			return
		# Deposit recipes: block on a KNOWN-bad tile (toast), but let the player build
		# blind on an unsurveyed tile — the outcome is revealed when it finishes.
		var req_block := _recipe_requirement_block(tile_data, recipe, tile_id)
		if req_block == "deposit":
			MatchState.request_toast("Cannot build mine there, it does not have the right deposit.", "warning")
			return
		elif req_block == "other":
			print("[Build] FAILED: recipe requirements not met on %s" % tile_id)
			return

	# Look up cost
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = maxf(0.0, float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0)) - MatchState.construction_material_rebate(building_id))

	# Construction materials must be present on the tile. If any are missing, offer the
	# order-or-cancel dialog and stop here — no money deducted, no tile space reserved.
	var mat_check: Dictionary = Construction.check_tile(tile_id, building_id)
	if not bool(mat_check.get("satisfied", false)):
		print("[Build] materials missing on %s for %s: %s" % [tile_id, building_id, str(mat_check.get("missing", {}))])
		match MatchState.construct_material_source:
			"market":
				_on_construction_buy_requested(building_id, recipe_id, tile_id)
				return
			"same_tile":
				MatchState.request_toast("There are no tiles with the required construction materials. Deliver the materials manually to the tile to begin construction.", "error")
				return
			"any_tile":
				if not Construction.find_source_tile(tile_id, mat_check.get("missing", {})).is_empty():
					_on_construction_use_stockpile_requested(building_id, recipe_id, tile_id)
				else:
					MatchState.request_toast("There are no tiles with the required construction materials. Deliver the materials manually to the tile to begin construction.", "error")
				return
		_show_construction_missing_dialog(building_id, recipe_id, tile_id, mat_check.get("missing", {}))
		return

	# Check + deduct money
	if not MatchState.deduct_money(cost):
		print("[Build] FAILED: insufficient money. Need £%.2f, have £%.2f" % [cost, MatchState.money])
		MatchState.build_rejected_no_funds.emit("Not enough money — need £%.2f, you have £%.2f" % [cost, MatchState.money])
		return

	# Consume the construction materials and start the build (deferred behind a countdown).
	var instance_id := Construction.start_on_tile(building_id, recipe_id, tile_id, cost)

	var _building_name := _get_building_display_name(building_id)
	print("Built %s (instance %s, recipe %s) on %s — cost £%.2f" % [building_id, instance_id, recipe_id, tile_id, cost])

	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)
	Audio.building_placed()

## The credit facility offer, raised when a build is one turn out (Construction emits
## building_tab_opened). Declining closes the tab so costs hit cash as they always did.
func _show_building_credit_dialog(instance_id: String) -> void:
	if _credit_dialog == null:
		_credit_dialog = load("res://scripts/building_credit_dialog.gd").new()
		_credit_dialog.name = "BuildingCreditDialog"
		_hud.add_child(_credit_dialog)
		_credit_dialog.choice_made.connect(func(iid: String, mode: String) -> void:
			MatchState.set_building_tab_mode(iid, mode))
	# A standing answer skips the dialog entirely; "ask" is the only mode that interrupts.
	var preset := MatchState.construct_credit_default
	if preset != "ask":
		MatchState.set_building_tab_mode(instance_id, preset)
		return
	var building: Dictionary = MatchState.get_building(instance_id)
	var label := str(Catalog.get_building(str(building.get("building_id", ""))).get("display_name", "this building"))
	_credit_dialog.open(instance_id, label)


func _show_construction_missing_dialog(building_id: String, recipe_id: String, tile_id: String, missing: Dictionary) -> void:
	# Lazily build one reusable dialog on the HUD. Phase 1 only wires Cancel (close); the
	# Buy / Use-stockpile CTAs are disabled in the dialog and connected here for later phases.
	if _construction_dialog == null:
		_construction_dialog = load("res://scripts/construction_missing_dialog.gd").new()
		_construction_dialog.name = "ConstructionMissingDialog"   # tutorial spotlight target
		_hud.add_child(_construction_dialog)
		_construction_dialog.buy_requested.connect(_on_construction_buy_requested)
		_construction_dialog.use_stockpile_requested.connect(_on_construction_use_stockpile_requested)
		_construction_dialog.credit_requested.connect(_on_construction_credit_requested)
	_construction_dialog.open(building_id, recipe_id, tile_id, missing)

func _on_construction_buy_requested(building_id: String, recipe_id: String, tile_id: String) -> void:
	# Buy-from-market path: charge the build cost now, order the missing materials, reserve the
	# site as an awaiting_materials project. The material cost is charged inside queue_buy, so we
	# confirm the player can afford build + materials together before committing to either.
	var coord := terrain_layer.id_to_coord(tile_id)
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = maxf(0.0, float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0)) - MatchState.construction_material_rebate(building_id))
	var material_cost: float = Construction.estimate_market_cost(tile_id, building_id)
	if MatchState.money < cost + material_cost:
		MatchState.build_rejected_no_funds.emit(
			"Not enough money — build £%.0f + materials £%.0f, you have £%.0f" % [cost, material_cost, MatchState.money])
		return
	if not MatchState.deduct_money(cost):
		return
	var instance_id := Construction.start_awaiting_market(building_id, recipe_id, tile_id, cost)
	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)
	Audio.building_placed()

func _on_construction_credit_requested(building_id: String, recipe_id: String, tile_id: String) -> void:
	# Build-on-credit (Chief Investment): finance build cost + materials with a 10-turn,
	# 5% construction loan instead of paying cash. The loan disburses the full amount, we
	# pay the build cost now, and the awaiting-market order charges the materials as usual.
	if not MatchState.construction_credit_available():
		return
	var coord := terrain_layer.id_to_coord(tile_id)
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = maxf(0.0, float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0)) - MatchState.construction_material_rebate(building_id))
	var material_cost: float = Construction.estimate_market_cost(tile_id, building_id)
	if not LoanState.take_construction_loan(cost + material_cost):
		MatchState.build_rejected_no_funds.emit(
			"Construction loan of £%.0f exceeds your borrowing capacity" % (cost + material_cost))
		return
	if not MatchState.deduct_money(cost):
		return
	var instance_id := Construction.start_awaiting_market(building_id, recipe_id, tile_id, cost)
	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)
	Audio.building_placed()

func _on_construction_use_stockpile_requested(building_id: String, recipe_id: String, tile_id: String) -> void:
	# Source the missing materials from another tile's spare stock: charge the build cost +
	# transport, pull the shortfall into the build site, reserve it as an awaiting project.
	var coord := terrain_layer.id_to_coord(tile_id)
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = maxf(0.0, float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0)) - MatchState.construction_material_rebate(building_id))
	var missing: Dictionary = Construction.check_tile(tile_id, building_id).get("missing", {})
	var source: Dictionary = Construction.find_source_tile(tile_id, missing)
	if source.is_empty():
		MatchState.build_rejected_no_funds.emit("No tile has the spare materials to build this here")
		return
	var move_cost: float = float(MatchState.preview_move(str(source.get("tile_id", "")), tile_id, missing).get("cost", 0.0))
	if MatchState.money < cost + move_cost:
		MatchState.build_rejected_no_funds.emit(
			"Not enough money — build £%.0f + transport £%.0f, you have £%.0f" % [cost, move_cost, MatchState.money])
		return
	if not MatchState.deduct_money(cost):
		return
	var instance_id := Construction.start_awaiting_from_tile(building_id, recipe_id, tile_id, str(source.get("tile_id", "")), cost)
	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)
	Audio.building_placed()

func _on_construction_cancelled(instance_id: String, _tile_id: String) -> void:
	if building_visuals.has_method("remove_instance"):
		building_visuals.remove_instance(instance_id)
	if forest_visuals.has_method("remove_instance"):
		forest_visuals.remove_instance(instance_id)

func _get_building_display_name(building_id: String) -> String:
	return Catalog.get_building_display_name(building_id)

func _place_npc_ports(animate: bool = false) -> void:
	# Each port from ports.csv is a Port building (b_004) owned by an NPC. Placing it
	# as a real instance makes it render, appear in the tile chart, raise the tile's
	# storage capacity (+500), and become clickable.
	for port in Catalog.all_ports():
		var tile_id := str(port.get("tile_id", ""))
		if tile_id == "":
			continue
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var already := false
		for iid in MatchState.tile_buildings.get(tile_id, []):
			if str(MatchState.get_building(iid).get("building_id", "")) == "b_004":
				already = true
				break
		if already:
			continue
		var instance_id := MatchState.add_building("b_004", "", tile_id, "Three Diamonds Shipping Corporation")
		building_placed.emit(tile_id, "b_004", "", instance_id, coord)
		await _place_yield(animate)   # keeps the loading screen animating between slices

func _place_ruins(tile_id: String, animate: bool = false) -> void:
	# A pre-placed disused/ruins building (b_031), NPC-owned to start with.
	var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	for iid in MatchState.tile_buildings.get(tile_id, []):
		if str(MatchState.get_building(iid).get("building_id", "")) == "b_031":
			return
	var instance_id := MatchState.add_building("b_031", "", tile_id, "Abandoned Holdings")
	building_placed.emit(tile_id, "b_031", "", instance_id, coord)
	await _place_yield(animate)

func _on_hidden_buildings_enabled() -> void:
	# The two constructible prototypes reappear in the catalogue through MatchState's
	# unlock signal. Ruins are world scenery, so restore their authored placement too.
	if terrain_layer != null:
		_place_ruins("tile_23_16")

func _place_northern_old_growth_forests() -> void:
	for coord_key in terrain_layer.tiles:
		var coord: Vector2i = coord_key
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var row: int = coord.y + 1
		if row > NORTH_OLD_GROWTH_MAX_ROW:
			continue
		var tile_type: String = str(tile_data.get("type", "")).strip_edges().to_lower()
		if not OLD_GROWTH_TILE_TYPES.has(tile_type):
			continue
		var tile_id: String = str(tile_data.get("id", ""))
		if tile_id == "" or _tile_has_building(tile_id, OLD_GROWTH_FOREST_BUILDING_ID):
			continue
		# Deterministic instance id: the forest footprint disc is seeded from
		# (instance_id, tile_id), and the roads-v2 starting-network bake must
		# reproduce the exact discs a fresh match creates. One old-growth per
		# tile (guarded above), so the id cannot collide.
		var instance_id: String = MatchState.add_building(
			OLD_GROWTH_FOREST_BUILDING_ID,
			"",
			tile_id,
			OLD_GROWTH_FOREST_OWNER,
			"forest_%s_%s" % [OLD_GROWTH_FOREST_BUILDING_ID, tile_id],
			false
		)
		building_placed.emit(tile_id, OLD_GROWTH_FOREST_BUILDING_ID, "", instance_id, coord)

func _place_start_buildings(animate: bool = false) -> void:
	# The pre-existing NPC building pool (data/start_buildings.json): one themed
	# company per road region, real recipes, market phase tags for the later
	# purchase rotation. Deterministic instance ids — the roads-v2 bake seeds the
	# same list, so its forest footprint discs match a fresh match exactly.
	for entry in StartBuildings.entries():
		if not MatchState.is_building_available(str(entry.building)):
			continue
		var tile_id := str(entry.tile)
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var instance_id := str(entry.instance_id)
		if MatchState.buildings.has(instance_id):
			continue
		var t_add := Time.get_ticks_usec()
		MatchState.add_building(
			str(entry.building), str(entry.recipe), tile_id,
			str(entry.owner), instance_id, false)
		_place_add_us += Time.get_ticks_usec() - t_add
		var t_emit := Time.get_ticks_usec()
		building_placed.emit(tile_id, str(entry.building), str(entry.recipe), instance_id, coord)
		_place_emit_us += Time.get_ticks_usec() - t_emit
		await _place_yield(animate)   # ~30 ms placement slices keep the slideshow moving
## Emit a start snapshot's player-owned buildings only after RoadNetwork has
## bootstrapped. SaveLoad already imported their simulation data; this is solely
## the deferred visual pass that gives them the same road-aware layout as ports,
## ruins and the pre-placed NPC companies.
func _place_pending_start_buildings(animate: bool = false) -> void:
	for instance_id in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[instance_id]
		var building_id := str(inst.get("building_id", ""))
		if LoadPacing.legacy_load:
			# Cheat: reproduce the old procedure — the original skip re-emits every start
			# forest one per frame (the ~11 s tail), which is exactly what we want to record.
			if not MatchState.is_player_owned(inst) and building_visuals.has_placement(str(instance_id)):
				continue
		# Forests draw in ForestVisuals and never get a building_visuals footprint, so
		# has_placement() is false for them forever — without this check every start
		# forest (~145) was re-emitted here one-per-frame on every load (~11 s of the
		# loading screen) while also churning the forest draw cache. Roads/cables render
		# from network state, not placements, so re-emitting them does nothing either.
		elif building_visuals.FOREST_BUILDING_IDS.has(building_id):
			if forest_visuals.has_forest(str(instance_id)):
				continue
		elif building_visuals.NON_FOOTPRINT_IDS.has(building_id):
			continue
		# Player buildings always (re)lay out here. NPC buildings only if no earlier
		# pass drew them: ports/ruins/companies already have footprints, but a snapshot-
		# seeded NPC building (e.g. the tutorial's Vandel window factory) does not and
		# would otherwise never render.
		elif not MatchState.is_player_owned(inst) and building_visuals.has_placement(str(instance_id)):
			continue
		var tile_id := str(inst.get("tile_id", ""))
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if tile_id == "" or coord == Vector2i(-1, -1):
			continue
		building_placed.emit(tile_id, str(inst.get("building_id", "")),
			str(inst.get("recipe_id", "")), str(instance_id), coord)
		await _place_yield(animate)

## Post-build sanity: every sim building should have landed in a visual layer — a
## footprint in BuildingVisuals or (forests) a tracked disc set in ForestVisuals —
## and the baked road network should have bootstrapped into RoadNetwork. One cheap
## dictionary pass; it prints ONLY on failure (console output is expensive in
## Godot, so a clean load logs nothing).
func _audit_start_visuals() -> void:
	var no_footprint: Dictionary = {}   # building_id -> count without a drawn footprint
	var no_forest: Dictionary = {}      # forest building_id -> count missing from ForestVisuals
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		var bid := str(inst.get("building_id", ""))
		if building_visuals.FOREST_BUILDING_IDS.has(bid):
			if not forest_visuals.has_forest(str(iid)):
				no_forest[bid] = int(no_forest.get(bid, 0)) + 1
		elif building_visuals.NON_FOOTPRINT_IDS.has(bid):
			continue   # roads/cables render from network state, not placements
		elif not building_visuals.has_placement(str(iid)):
			no_footprint[bid] = int(no_footprint.get(bid, 0)) + 1
	if not no_footprint.is_empty():
		push_warning("Visual audit: %d building(s) have no drawn footprint (layout failed or tile too crowded), by id: %s"
			% [_audit_total(no_footprint), no_footprint])
	if not no_forest.is_empty():
		push_warning("Visual audit: %d forest(s) missing from ForestVisuals, by id: %s"
			% [_audit_total(no_forest), no_forest])
	var baked_edges: Variant = RoadsBaked.network_state().get("edges", [])
	if RoadNetwork.instance().edges.is_empty() and not baked_edges.is_empty():
		push_warning("Visual audit: RoadNetwork is empty but the baked start network has edges — bootstrap_from_bake failed?")

func _audit_total(counts: Dictionary) -> int:
	var n := 0
	for k in counts:
		n += int(counts[k])
	return n

func _tile_has_building(tile_id: String, building_id: String) -> bool:
	for iid in MatchState.tile_buildings.get(tile_id, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) == building_id:
			return true
	return false

# "" = buildable, "deposit" = known-missing deposit (toast + block),
# "other" = some other requirement (potential/produces) not met.
func _recipe_requirement_block(tile_data: Dictionary, recipe: Dictionary, tile_id: String) -> String:
	var status := MatchState.survey_status(tile_id, str(tile_data.get("type", "")))
	for req in recipe.get("requirements", []):
		var rtype := str(req.get("type", ""))
		if rtype == "deposit":
			var token := str(req.get("value", ""))
			# Unknown ground: allow a blind build (water is always visible, so it's
			# still checked normally).
			if token != "water" and status == "unsurveyed":
				continue
			if not _tile_meets_build_req(tile_data, req):
				return "deposit"
		else:
			if not _tile_meets_build_req(tile_data, req):
				return "other"
	return ""

func _recipe_nonwater_deposit_token(recipe: Dictionary) -> String:
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) == "deposit":
			var token := str(req.get("value", ""))
			if token != "" and token != "water":
				return token
	return ""

func _good_display_for_deposit(token: String) -> String:
	var internal := "pure_water" if token == "water" else token
	var good: Dictionary = Catalog.get_good_by_internal_name(internal)
	return str(good.get("display_name", token.capitalize()))

# When a blind (unsurveyed) deposit build finishes: reveal the deposit if it's
# there, otherwise warn the player it will not run. Partial/surveyed tiles are
# skipped (the player already knew the ground).
func _on_construction_completed_deposit_check(instance_id: String, tile_id: String) -> void:
	var building: Dictionary = MatchState.get_building(instance_id)
	if building.is_empty():
		return
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var token := _recipe_nonwater_deposit_token(recipe)
	if token == "":
		return
	var coord := terrain_layer.id_to_coord(tile_id)
	if not terrain_layer.tiles.has(coord):
		return
	var tile_data: Dictionary = terrain_layer.tiles[coord]
	if MatchState.survey_status(tile_id, str(tile_data.get("type", ""))) != "unsurveyed":
		return
	if _deposits_include(tile_data.get("deposits", []), token):
		MatchState.reveal_deposit(tile_id, token)
	else:
		_show_deposit_dialog(
			"No deposit found",
			"This tile has no deposit of %s so it will not run. Surveying could have warned us this was the case." % _good_display_for_deposit(token),
			[{"id": "demolish", "label": "Demolish"}])

func _on_deposit_exhausted(tile_id: String, token: String) -> void:
	if token == "water":
		return
	# Remember which building the exhausted deposit belongs to, so the dialog's
	# Demolish / Change Recipe buttons can act on it.
	_deposit_dialog_target = _building_with_deposit_token(tile_id, token)
	_show_deposit_dialog(
		"Deposit exhausted",
		"The %s deposit here has run out — this building can no longer produce." % _good_display_for_deposit(token),
		[{"id": "demolish", "label": "Demolish"}, {"id": "change", "label": "Change Recipe"}])

# The player building on `tile_id` whose recipe draws on the given deposit token.
func _building_with_deposit_token(tile_id: String, token: String) -> Dictionary:
	for iid in MatchState.tile_buildings.get(tile_id, []):
		var b: Dictionary = MatchState.get_building(str(iid))
		if b.is_empty() or not MatchState.is_player_owned(b):
			continue
		if _recipe_nonwater_deposit_token(Catalog.get_recipe(str(b.get("recipe_id", "")))) == token:
			return b
	return {}

func _show_deposit_dialog(title: String, body: String, buttons: Array) -> void:
	if _deposit_dialog == null:
		_deposit_dialog = load("res://scripts/deposit_dialog.gd").new()
		_hud.add_child(_deposit_dialog)
		_deposit_dialog.action_chosen.connect(_on_deposit_dialog_action)
	_deposit_dialog.open(title, body, buttons)

func _on_deposit_dialog_action(id: String) -> void:
	var building: Dictionary = _deposit_dialog_target
	_deposit_dialog_target = {}
	if building.is_empty():
		return
	match id:
		"demolish":
			# Route through the supply-chain review, same as the detail panel's Demolish.
			_open_supply_chain_review(str(building.get("instance_id", "")), "demolish")
		"change":
			# Open the building so the player can pick a new recipe.
			_open_building_detail(building)

# Mount the supply-chain review panel (feeders → target → dependents, per-building
# auto-fulfil/pause) for a sell or demolish. Same panel the building detail panel uses.
func _open_supply_chain_review(instance_id: String, action: String) -> void:
	if instance_id == "":
		return
	var layer := CanvasLayer.new()
	layer.layer = 130
	get_tree().root.add_child(layer)
	var panel: Control = load("res://scripts/supply_chain_panel.gd").new()
	layer.add_child(panel)
	panel.finished.connect(func(_confirmed: bool) -> void: layer.queue_free())
	panel.open(instance_id, action)

func _tile_meets_build_req(tile_data: Dictionary, req: Dictionary) -> bool:
	match req.get("type", ""):
		"deposit":
			var deposits: Array = tile_data.get("deposits", [])
			return _deposits_include(deposits, str(req.get("value", "")))
		"produces":
			return _tile_produces_good(tile_data, req.get("value", ""))
		"potential":
			var value: String = req.get("value", "")
			if value == "wind":
				return tile_data.get("wind_potential", 0) > 0
			if value == "solar":
				return tile_data.get("solar_potential", 0) > 0
			return false
	return false

func _deposits_include(deposits: Array, internal_name: String) -> bool:
	if internal_name == "":
		return false
	for deposit in deposits:
		if _deposit_base_name(str(deposit)) == internal_name:
			return true
	return false

func _deposit_base_name(deposit: String) -> String:
	var value := deposit.strip_edges()
	var quantity_marker := value.find("(")
	if quantity_marker > 0 and value.ends_with(")"):
		return value.substr(0, quantity_marker)
	return value

func _tile_produces_good(tile_data: Dictionary, internal_name: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return false
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	for inst_id in instance_ids:
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.get("output_name", "") == internal_name:
			return true
		for output in recipe.get("outputs", []):
			if output.get("internal_name", "") == internal_name:
				return true
	return false

func _on_infrastructure_attempted(infra_type: String, tile_id: String) -> void:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	if not terrain_layer.tiles.has(coord):
		return

	var tile: Dictionary = terrain_layer.tiles[coord]
	var infra: Array = tile.get("infrastructure_present", [])

	# Already present — silently bail (no charge, no error)
	if infra.has(infra_type):
		print("Tile %s already has %s" % [tile_id, infra_type])
		return

	# Lookup cost
	var building_data: Dictionary = Catalog.get_building_by_internal_name(infra_type)
	var infra_building_id: String = building_data.get("id", "")
	var cost: float = maxf(0.0, float(building_data.get("base_price", 0.0)) - MatchState.construction_material_rebate(infra_building_id))
	if infra_building_id != "":
		# Already being built here — silently bail rather than charging twice.
		for project in Construction.projects_on_tile(tile_id):
			if str(project.get("building_id", "")) == infra_building_id:
				print("Tile %s is already building %s" % [tile_id, infra_type])
				return
		var space_check := _space_check_for_build(tile_id, infra_building_id)
		if not bool(space_check.get("allowed", false)):
			# Say it ON THE TILE. This used to return silently, so the placement icon simply
			# appeared to do nothing and the corner toast went unread (owner 2026-08-23).
			_flash_build_refusal(coord, str(space_check.get("reason", "Cannot build here")))
			return
		# Infrastructure uses the same construction-material lifecycle as every
		# other building. Previously it skipped this check, then start_on_tile()
		# consumed whatever happened to be there and silently began the project.
		var mat_check: Dictionary = Construction.check_tile(tile_id, infra_building_id)
		if not bool(mat_check.get("satisfied", false)):
			match MatchState.construct_material_source:
				"market":
					_on_construction_buy_requested(infra_building_id, "", tile_id)
					return
				"same_tile":
					MatchState.request_toast("There are no tiles with the required construction materials. Deliver the materials manually to the tile to begin construction.", "error")
					return
				"any_tile":
					if not Construction.find_source_tile(tile_id, mat_check.get("missing", {})).is_empty():
						_on_construction_use_stockpile_requested(infra_building_id, "", tile_id)
					else:
						MatchState.request_toast("There are no tiles with the required construction materials. Deliver the materials manually to the tile to begin construction.", "error")
					return
			_show_construction_missing_dialog(infra_building_id, "", tile_id, mat_check.get("missing", {}))
			return
		var cost_multiplier := float(space_check.get("cost_multiplier", 1.0))
		cost *= cost_multiplier
		_try_build_infrastructure(tile_id, coord, infra_type, infra_building_id, cost)
		return

	_try_build_infrastructure(tile_id, coord, infra_type, infra_building_id, cost)

func _try_build_infrastructure(tile_id: String, coord: Vector2i, infra_type: String, infra_building_id: String, cost: float) -> void:
	# Check + deduct
	if not MatchState.deduct_money(cost):
		print("[Build] FAILED: insufficient money for %s. Need £%.2f, have £%.2f" % [infra_type, cost, MatchState.money])
		MatchState.build_rejected_no_funds.emit("Not enough money to build %s — need £%.2f, you have £%.2f" % [infra_type, cost, MatchState.money])
		_flash_build_refusal(coord, "Insufficient money — £%d needed" % int(ceil(cost)))
		return

	if infra_building_id == "":
		# No catalog building backs this type, so there is nothing to construct:
		# apply it instantly (none of the buildable types hit this path).
		_apply_built_infrastructure(coord, tile_id, infra_type)
		building_placed.emit(tile_id, "", "", "", coord)
		return

	# Infrastructure builds like buildings: a construction project counting down
	# build_duration turns (from the CSV) — the started/built toasts come from the
	# same Construction signals. The tile gains the infra only when the project
	# completes (_on_construction_completed_infra); until then the Infrastructure
	# mapmode shows it dashed/under-construction.
	var instance_id := Construction.start_on_tile(infra_building_id, "", tile_id, cost)
	print("Started building %s on %s — cost £%.2f" % [infra_type, tile_id, cost])
	building_placed.emit(tile_id, infra_building_id, "", instance_id, coord)

# A finished infrastructure build joins the tile's infrastructure_present and the
# router's live infra map (so roads/rails affect routing only once finished).
func _apply_built_infrastructure(coord: Vector2i, tile_id: String, infra_type: String) -> void:
	if not terrain_layer.tiles.has(coord):
		return
	var tile: Dictionary = terrain_layer.tiles[coord]
	var infra: Array = tile.get("infrastructure_present", [])
	if not infra.has(infra_type):
		infra.append(infra_type)
		tile["infrastructure_present"] = infra
		terrain_layer.tiles[coord] = tile
	Catalog.add_tile_infrastructure(tile_id, infra_type)
	tile_infrastructure_changed.emit(tile_id, infra_type)
	print("Built %s on %s" % [infra_type, tile_id])

## Tutorial-only, zero-cost infrastructure reveal. This is intentionally exposed at
## the world seam rather than mutating Catalog from the coach: it updates both the
## authoritative terrain tile and the router in exactly the same way as a completed
## construction project. Normal matches cannot call it successfully.
func tutorial_install_infrastructure(tile_ids: Array, infra_type: String) -> void:
	if not bool(MatchState.ruleset.get("tutorial_enabled", false)):
		return
	if not _is_tile_infra_type(infra_type):
		return
	for raw_tile_id in tile_ids:
		var tile_id := str(raw_tile_id)
		_apply_built_infrastructure(terrain_layer.id_to_coord(tile_id), tile_id, infra_type)
	# Baked road geometry already exists; changing only the tile clip flags leaves
	# its edge count unchanged, so force the static renderer to expose the route.
	var road_visuals := get_node_or_null("RoadNetworkVisuals")
	if road_visuals is CanvasItem:
		(road_visuals as CanvasItem).queue_redraw()

## Tutorial-only late reveal for the adjacent demonstration factory. Going through
## the normal MatchState + building_placed seams keeps simulation, tile indexes and
## map visuals in sync without making it a construction project the player must wait on.
func tutorial_spawn_building(building_id: String, recipe_id: String, tile_id: String) -> String:
	if not bool(MatchState.ruleset.get("tutorial_enabled", false)):
		return ""
	for iid in MatchState.tile_buildings.get(tile_id, []):
		var existing: Dictionary = MatchState.get_building(str(iid))
		if MatchState.is_player_owned(existing) \
				and str(existing.get("building_id", "")) == building_id \
				and str(existing.get("recipe_id", "")) == recipe_id:
			return str(iid)
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return ""
	var instance_id := MatchState.add_building(building_id, recipe_id, tile_id)
	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)
	return instance_id

func _on_construction_completed_infra(instance_id: String, tile_id: String) -> void:
	var building_id := str(MatchState.get_building(instance_id).get("building_id", ""))
	var internal_name := str(Catalog.get_building(building_id).get("internal_name", ""))
	if not _is_tile_infra_type(internal_name):
		return
	_apply_built_infrastructure(terrain_layer.id_to_coord(tile_id), tile_id, internal_name)

# The infra types that live on tiles (the canonical slot set). Port/airport are
# category "infrastructure" in the CSV but are ordinary buildings on the map.
func _is_tile_infra_type(internal_name: String) -> bool:
	if internal_name == "":
		return false
	for slot in InfraIcons.SLOTS:
		if str(slot.key) == internal_name:
			return true
	return false

## The infrastructure that runs over ground. Pipes and cables are deliberately absent —
## a pipeline or a cable may cross water, and only these two may not.
const OVERLAND_INFRA := {"roads": true, "rail": true}


func _space_check_for_build(tile_id: String, building_id: String) -> Dictionary:
	var building_data: Dictionary = Catalog.get_building(building_id)
	# Overland infrastructure cannot be laid on water, and saying so comes FIRST: a sea
	# tile also has no land to own, so the land gate below would otherwise answer "buy more
	# land here" for a road across open water — advice the player cannot act on and which
	# hides the real reason (owner 2026-08-25).
	var internal := str(building_data.get("internal_name", ""))
	if OVERLAND_INFRA.has(internal):
		var ttype := Catalog.tile_type(tile_id)
		if ttype == "sea" or ttype == "deep_sea":
			var sea_msg := "Cannot build that infrastructure on sea."
			print("[Build] FAILED: %s on %s tile %s" % [internal, ttype, tile_id])
			_show_tile_space_error(sea_msg)
			return {"allowed": false, "cost_multiplier": 1.0, "reason": sea_msg}
	var added_space := maxf(0.0, float(building_data.get("tile_size_used", 1.0)))
	var current_space := MatchState.get_tile_space_used(tile_id)
	var projected_space := current_space + added_space
	var tile_cap := MatchState.max_tile_land(tile_id)
	if projected_space > float(tile_cap):
		print("[Build] FAILED: tile %s is full (need %s, max %s)" % [tile_id, str(projected_space), str(tile_cap)])
		var full_msg := "There is no more room on that tile. Demolish buildings to make room."
		_show_tile_space_error(full_msg)
		return {"allowed": false, "cost_multiplier": 1.0, "reason": "No room on this tile"}
	# The owned-land gate only counts the player's estate — NPC buildings sit on
	# their own land and must not eat the land the player has bought.
	var projected_player := MatchState.get_tile_player_space_used(tile_id) + added_space
	var land_owned := MatchState.get_tile_land_owned(tile_id)
	# Auto-buy land (construct setting, or this one attempt's buy-land intent from the
	# V3 confirm — BuildMode.attempt_buy_land): cover ONLY the shortfall, rounded up to whole
	# patches, and only when there genuinely isn't room already — a tile that can already
	# take the building buys nothing. purchase_tile_land clamps to what's actually for sale
	# and can grant a clipped sliver, so the gate below is re-evaluated on the real result
	# rather than assumed to have succeeded.
	if projected_player > float(land_owned) \
			and (MatchState.construct_auto_buy_land or BuildMode.attempt_buy_land):
		var shortfall := projected_player - float(land_owned)
		var patches := int(ceil(shortfall / float(MatchState.LAND_PATCH_SIZE)))
		var before := land_owned
		if MatchState.purchase_tile_land(tile_id, patches):
			land_owned = MatchState.get_tile_land_owned(tile_id)
			MatchState.request_toast("Bought %d land on %s to fit this building." % [
				land_owned - before, Catalog.tile_label(tile_id)], "info")
		else:
			print("[Build] auto-buy land FAILED on %s (wanted %d patch(es))" % [tile_id, patches])
			_show_tile_space_error("Not enough money (or land for sale) to buy the land this building needs on %s" % Catalog.tile_label(tile_id))
			return {"allowed": false, "cost_multiplier": 1.0,
				"reason": "Insufficient money to buy the land"}
	if projected_player > float(land_owned):
		print("[Build] FAILED: insufficient land on tile %s (need %s, own %s)" % [tile_id, str(projected_player), str(land_owned)])
		_show_tile_space_error("You cannot build that. You do not own sufficient land on %s"
			% Catalog.tile_label(tile_id))
		return {"allowed": false, "cost_multiplier": 1.0, "reason": "Insufficient land — buy more here"}
	var cost_multiplier := 1.0
	if projected_space > DENSITY_SOFT_CAPACITY:
		cost_multiplier = 1.5
		_show_tile_space_caution("Local opposition to density on tile %s will increase material and money costs for new buildings by 50%%" % tile_id)
	return {"allowed": true, "cost_multiplier": cost_multiplier}

## Flash the refused tile red and print the reason under it, via the map overlay.
func _flash_build_refusal(coord: Vector2i, reason: String) -> void:
	if map_overlay != null and map_overlay.has_method("flash_build_refusal"):
		map_overlay.flash_build_refusal(coord, reason)

## Every space refusal comes through here — no room, no owned land, sea under a road.
##
## It goes to the bottom-CENTRE stack, not the bottom-left one the other toasts share. The
## left stack sits under the construct panel, and now that a refused build leaves that panel
## open (so the player can buy land or pick another tile without rebuilding their selection),
## a message posted there would be hidden behind the very panel that caused it. The centre
## stack clears the bottom menu by 40px.
func _show_tile_space_error(message: String) -> void:
	BuildMode.last_attempt_refused = true
	if _toast_layer != null and _toast_layer.has_method("show_blocked"):
		_toast_layer.call("show_blocked", message)
	elif _toast_layer != null and _toast_layer.has_method("show_error"):
		_toast_layer.call("show_error", message)
	else:
		push_warning(message)

func _show_tile_space_caution(message: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_caution"):
		_toast_layer.call("show_caution", message)
	else:
		push_warning(message)

# DEMO: hardcoded infrastructure levels (until levels become real gameplay) —
# a pipes chain stepping lvl 1 -> 2 and a rails chain stepping lvl 1 -> 3, so
# the Infrastructure mapmode's level line styles can be compared on the map.
const _DEMO_INFRA_LEVELS: Array = [
	{"tile": "tile_5_3", "infra": "pipes", "level": 1},
	{"tile": "tile_5_4", "infra": "pipes", "level": 1},
	{"tile": "tile_5_5", "infra": "pipes", "level": 2},
	{"tile": "tile_5_6", "infra": "pipes", "level": 2},
	{"tile": "tile_7_1", "infra": "rails", "level": 1},
	{"tile": "tile_7_2", "infra": "rails", "level": 1},
	{"tile": "tile_7_3", "infra": "rails", "level": 3},
	{"tile": "tile_7_4", "infra": "rails", "level": 3},
]

func _apply_demo_infra_levels() -> void:
	for entry in _DEMO_INFRA_LEVELS:
		var coord := terrain_layer.id_to_coord(str(entry.tile))
		if not terrain_layer.tiles.has(coord):
			continue
		var tile: Dictionary = terrain_layer.tiles[coord]
		var infra: Array = tile.get("infrastructure_present", [])
		if not infra.has(str(entry.infra)):
			infra.append(str(entry.infra))
			tile["infrastructure_present"] = infra
			Catalog.add_tile_infrastructure(str(entry.tile), str(entry.infra))
		var levels: Dictionary = tile.get("infrastructure_levels", {})
		levels[str(entry.infra)] = int(entry.level)
		tile["infrastructure_levels"] = levels
		terrain_layer.tiles[coord] = tile

func _infra_building_id_for(infra_type: String) -> String:
	# Maps infrastructure internal_name -> the building_id used for visual icons
	match infra_type:
		"cables": return "b_006"
		"roads": return "b_005"
		_: return ""

func _on_phase_started(phase: int) -> void:
	_update_phase_label(phase)
	print("Phase: ", TurnManager.get_phase_name(phase))

func _on_turn_advanced(new_turn: int) -> void:
	_update_turn_counter(new_turn)

func _on_resolution_started() -> void:
	end_turn_button.disabled = true

func _on_resolution_completed() -> void:
	end_turn_button.disabled = false

func _update_turn_counter(turn: int) -> void:
	turn_counter.text = "Turn %d / %d" % [turn, TurnManager.MAX_TURNS]

func _update_phase_label(phase: int) -> void:
	phase_label.text = "Phase: %s" % TurnManager.get_phase_name(phase)

func _build_stockpile_select_prompt() -> void:
	_stockpile_select_prompt = PanelContainer.new()
	_stockpile_select_prompt.name = "StockpileSelectPrompt"
	_stockpile_select_prompt.visible = false
	_stockpile_select_prompt.custom_minimum_size = Vector2(640, 30)
	_stockpile_select_prompt.anchor_left = 0.5
	_stockpile_select_prompt.anchor_right = 0.5
	_stockpile_select_prompt.anchor_top = 1.0
	_stockpile_select_prompt.anchor_bottom = 1.0
	_stockpile_select_prompt.offset_left = -320.0
	_stockpile_select_prompt.offset_right = 320.0
	_stockpile_select_prompt.offset_top = -158.0
	_stockpile_select_prompt.offset_bottom = -128.0
	_stockpile_select_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.94)
	style.border_color = DS.PALETTE.BORDER   # solid off-white outline
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_stockpile_select_prompt.add_theme_stylebox_override("panel", style)
	hud_content.add_child(_stockpile_select_prompt)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stockpile_select_prompt.add_child(label)

func _show_stockpile_select_prompt(_selection: Dictionary) -> void:
	if _stockpile_select_prompt == null:
		return
	var label := _stockpile_select_prompt.get_node_or_null("Label") as Label
	if label != null:
		label.text = "Click to choose a destination. CTRL + Click to send a specific quantity to 1 tile. SHIFT + Click to send to 2 or 3 tiles."
	_stockpile_select_prompt.visible = true

func _hide_stockpile_select_prompt() -> void:
	if _stockpile_select_prompt != null:
		_stockpile_select_prompt.visible = false

# Handled in _input (before GUI focus navigation) so Tab toggles the Empire view
# reliably even when a button/panel holds focus. Skipped while typing so Tab still
# works inside text fields (e.g. the search overlay).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_empire_view") and not _is_text_entry_focused():
		_on_empire_view_requested()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_goods_graph") and not _is_text_entry_focused():
		if goods_graph_view != null:
			goods_graph_view.toggle()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	if event.keycode == KEY_ESCAPE and search_overlay != null and search_overlay.visible:
		search_overlay.call("close_search")
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_X and _should_open_search(event):
		search_overlay.call("open_search")
		get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_ESCAPE:
			# Escape always cancels an active map interaction before it closes ordinary
			# panels or opens Pause. This is the unified map cancel path.
			if _cancel_map_interaction_or_mode():
				get_viewport().set_input_as_handled()
				return
			# A locked tutorial step still protects its spotlit panel once all map
			# interactions have been dismissed.
			if Tutorial.active and Tutorial.hard_gate:
				get_viewport().set_input_as_handled()
				return
			if not PanelStack.close_top():
				# Nothing left to close: Esc opens the in-game menu.
				PauseMenu.open(_hud)
			get_viewport().set_input_as_handled()


## Cancel the foremost map-level interaction. Each branch uses its established close
## routine so prompts, legends, dimmers and HUD state remain in sync.
func _cancel_map_interaction_or_mode() -> bool:
	if _special_order_reroute_picking:
		_cancel_special_order_reroute_pick()
		return true
	if _v2_picking_dest:
		_v2_picking_dest = false
		terrain_layer.end_stockpile_destination_selection()
		return true
	if not _buy.is_empty():
		_close_buy()
		return true
	if not _transfer.is_empty():
		_close_transfer()
		return true
	if _picking_buy_tile:
		_picking_buy_tile = false
		terrain_layer.end_stockpile_destination_selection()
		_exit_stockpile_ui_mode()
		return true
	if not _pending_stockpile_selection.is_empty():
		MatchState.cancel_output_stockpile_selection()
		return true
	if BuildMode.is_active:
		BuildMode.exit_build_mode()
		return true
	if MapMode.is_active():
		MapMode.clear_all()
		return true
	return false

func _should_open_search(event: InputEventKey) -> bool:
	if search_overlay == null or search_overlay.visible:
		return false
	if event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if _special_order_reroute_picking:
		return false
	if not _pending_stockpile_selection.is_empty():
		return false
	return not _is_text_entry_focused()

func _is_text_entry_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
