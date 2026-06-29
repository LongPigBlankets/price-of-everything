extends Node2D

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var building_panel: PanelContainer = %BuildingDetailPanel
## The tabbed Tile View Panel, instantiated in code in _ready.
var info_panel: PanelContainer = null
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
@onready var river_layer: TileMapLayer = $RiverLayer
@onready var hud_content: Control = $UILayer/HUD/HUDContent
@onready var _hud: Control = $UILayer/HUD
@onready var _toast_layer: Control = $UILayer/HUD/ToastLayer
@onready var forest_visuals: Node2D = %ForestVisuals

# Empire view — full-screen node-graph alternative to the map (Tab to toggle).
# Created in code in _ready() and parented under HUDContent. See scripts/empire_view.gd.
# Typed via a preload const (not a class_name) to avoid global-class registration-order
# parse errors when this script is reloaded by the test harness.
const EmpireViewScript := preload("res://scripts/empire_view.gd")
var empire_view: EmpireViewScript

const DENSITY_SOFT_CAPACITY := 100.0
const InfraIcons := preload("res://scripts/infra_icons.gd")
const OLD_GROWTH_FOREST_BUILDING_ID := "b_016"
const OLD_GROWTH_FOREST_OWNER := "tile_data"
const NORTH_OLD_GROWTH_MAX_ROW := 6
const OLD_GROWTH_TILE_TYPES := ["rural", "hill"]

signal building_placed(tile_id: String, building_id: String, recipe_id: String, instance_id: String, coord: Vector2i)

var _survey_dialog: PanelContainer = null
var _unlock_dialog: PanelContainer = null
var _stockpile_select_prompt: PanelContainer = null
var _pending_stockpile_selection: Dictionary = {}
var _dim_overlay: ColorRect = null
var _stockpile_legend: PanelContainer = null
var _picking_buy_tile := false  # true while picking a Purchases-tab delivery tile
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
var _construction_dialog: PanelContainer = null
var _deposit_dialog: Control = null  # reused "no deposit" / "deposit exhausted" modal

## False until _ready has finished building the world. On a fresh start the heavy
## building-visual placement is spread across frames (so the loading screen can keep
## animating its slideshow), so "the scene exists" is NOT the same as "the world is
## ready" — the loading screen waits on this flag before offering "Begin".
var build_complete := false

# Prewarm: set true (before the node enters the tree) by MapPrewarm so _ready builds only the
# config-independent base — panels, terrain, first render to compile shaders / upload textures —
# then stops and emits base_ready. The reveal claims the warm instance and runs finish_build().
var prewarm_mode := false
signal base_ready


func _ready() -> void:
	await _build_base()
	if prewarm_mode:
		base_ready.emit()
		return   # finish_build() comes later, from the reveal, with the chosen start
	# A fresh new game with a loading screen up animates its build; tests / e2e / load-game
	# (no loading screen) build synchronously. The prewarm-reveal path calls finish_build()
	# itself with animate=true, having already run _build_base() ahead of time.
	await finish_build(_loading_screen_active())


# Build the config-INDEPENDENT visual scaffold: theme, signal wiring, the HUD panels, the
# terrain + visual layers. Runs no simulation and mutates no MatchState, so it can be built
# ahead of time (prewarmed) for ANY start; the per-start sim + buildings come in finish_build().
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
	MatchState.focus_tile_requested.connect(_on_focus_tile_requested)
	MatchState.focus_building_requested.connect(_on_focus_building_requested)

	TurnManager.phase_started.connect(_on_phase_started)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)
	MatchState.output_stockpile_selection_started.connect(_on_output_stockpile_selection_started)
	MatchState.output_stockpile_selection_cancelled.connect(_on_output_stockpile_selection_cancelled)

	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)
	_build_stockpile_select_prompt()
	_build_dim_overlay()
	_build_stockpile_legend()
	# Hand a frame to the loading screen here (right after the scene instantiated) so its
	# animation + the OS window stay live while the rest of the world builds. No-op without
	# a loading screen (tests / e2e / load-game run the build synchronously, as before).
	await _build_yield()

	# Infrastructure mapmode panel: shows/hides itself with the mapmode.
	hud_content.add_child(load("res://scripts/infrastructure_panel.gd").new())
	_apply_demo_infra_levels()

	# Empire view: full-screen node-graph alternative to the map (Tab to toggle).
	empire_view = EmpireViewScript.new()
	empire_view.name = "EmpireView"
	empire_view.visible = false
	hud_content.add_child(empire_view)

	# Wire visuals to react to building placements
	building_placed.connect(building_visuals.on_building_placed)
	building_placed.connect(forest_visuals.on_building_placed)
	# A cancelled construction site removes its hex icon (it was never a real building).
	Construction.construction_cancelled.connect(_on_construction_cancelled)
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

	# Capacity dialog: prompts the player when a tile first hits max storage.
	_hud.add_child(load("res://scripts/capacity_dialog.gd").new())

	# Overflow dialog: prompts when construction materials arrive at a full tile.
	var overflow_dialog: Node = load("res://scripts/overflow_dialog.gd").new()
	_hud.add_child(overflow_dialog)
	overflow_dialog.go_to_stockpile_requested.connect(_on_go_to_tile_stockpile)

	# Survey dialog: opened by clicking a tile in the Surveying mapmode.
	_survey_dialog = load("res://scripts/survey_dialog.gd").new()
	_hud.add_child(_survey_dialog)

	# "Unlocked …" popup, shown when a research unlock is earned by its condition.
	_unlock_dialog = load("res://scripts/unlock_dialog.gd").new()
	_hud.add_child(_unlock_dialog)
	MatchState.unlock_granted.connect(_on_unlock_granted)

	# The tabbed Tile View Panel; built in code, lives under HUDContent. Named
	# "TileInfoPanel" so building_detail_panel's panel-stacking lookups find it.
	info_panel = load("res://scripts/tile_info_panel_v2.gd").new()
	info_panel.name = "TileInfoPanel"
	hud_content.add_child(info_panel)
	info_panel.building_clicked.connect(_on_v2_building_clicked)
	info_panel.pick_destination_requested.connect(_on_v2_pick_destination)
	info_panel.survey_requested.connect(_on_survey_tile_clicked)

	# Debug cheat terminal (toggle with the ` key)
	add_child(load("res://scripts/debug_terminal.gd").new())

	# Floating £ that rises from a port whenever a market sale lands there
	var _sale_fx: CanvasLayer = load("res://scripts/sale_effects.gd").new()
	_sale_fx.terrain_layer = terrain_layer
	add_child(_sale_fx)

	# Collapsing-hex + rising-deposit-icon animation when a tile finishes surveying.
	var _survey_fx: Node2D = load("res://scripts/survey_effects.gd").new()
	_survey_fx.name = "SurveyEffects"
	_survey_fx.terrain_layer = terrain_layer
	add_child(_survey_fx)
	await _build_yield()


# Apply this start's (or a loaded save's) simulation and place its buildings on top of the
# base scaffold. Split out of _ready so a prewarmed base can be revealed instantly and then
# "finished" with the chosen start. `animate` spreads building placement one-per-frame.
func finish_build(animate: bool) -> void:
	# The port tiles start surveyed (the Surveying mapmode reveals them on turn 1).
	MatchState.seed_surveyed_ports()
	# Track depletable-deposit yields so mining can run them down over time.
	MatchState.seed_deposits(terrain_layer)
	# NOTE: the game-start BUILDINGS (NPC ports, the ruins, the start companies — and any future player
	# start buildings) are placed LATER, AFTER roads + enclosures exist, so they drop into the ready chunk
	# grid and fill the blocks. See the "roads → enclosures → buildings" sequence below.

	var pending_start := SaveLoad.pending_is_start()
	# A loaded save applies only now, once the terrain and default seeding exist;
	# it overwrites the fresh-match state above (docs/save_load_spec.md).
	var loaded_pending := SaveLoad.apply_pending()
	if loaded_pending:
		_rebuild_after_load()
	await _build_yield()
	# Forests are a TERRAIN feature (the land mask + block templates read them), so they come before roads
	# and enclosures. The buildings that used to follow here are deferred until after the blocks exist.
	if not loaded_pending or pending_start:
		_place_northern_old_growth_forests()

	# roads-v2: the predetermined river crossings must exist before any runtime
	# routing — the realizer whitelists river cells near these gates, so without
	# them a road can never cross a river (it was only ever built by the bake and
	# debug cheats, so river roads silently failed in normal play). Cheap (~123
	# river tiles), static for the match.
	if not RoadCrossings.is_built():
		RoadCrossings.build(terrain_layer)
	# A loaded save restores its as-built network + work orders
	# (SaveLoad.import_snapshot); anything else starts from the baked anchor
	# spine (spec 4.5b). bootstrap_from_bake no-ops when edges were imported.
	if not loaded_pending or pending_start:
		RoadNetwork.reset()
		RoadWorks.reset()
	RoadNetwork.bootstrap_from_bake()
	# Match-start ENCLOSURES on urban tiles (after the bake's roads exist, BEFORE any building): each urban
	# tile gets a city block + organic enclosure RING — the ring is the tile's visible road (no straight
	# centre-to-centre connector lines), and inland tiles like Arin dock now enclose. seed_urban_enclosures
	# lays a short INVISIBLE frontage anchor where there's no real road, then derives + draws the ring and
	# flags the tile "roads". Fresh start only; a loaded save carries the rings in its network snapshot.
	# When a loading screen is up, place the start buildings ONE PER FRAME so its
	# slideshow keeps animating through the ~7 s of per-building visual layout instead
	# of the whole window freezing. Without a loading screen (tests, e2e, load-game)
	# `animate` is false and placement runs synchronously, exactly as before.
	if not loaded_pending or pending_start:
		RoadWorks.seed_urban_enclosures(terrain_layer)
		await _build_yield()
		# BUILDINGS now — after roads + enclosures — so they drop into the ready chunk grid and FILL the
		# blocks they land in (NPC ports, the ruins, the start companies, + any future player start builds).
		await _place_npc_ports(animate)
		await _place_ruins("tile_23_16", animate)
		await _place_start_buildings(animate)
	RoadWorks.rebuild_occupancy()   # no-op until OCCUPANCY_ROADS_ENABLED

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

	build_complete = true   # the loading screen may now offer "Begin"
	print("WorldMap ready, signals connected")
	print("MatchState ready. Money: ", MatchState.money, ". Buildings: ", MatchState.buildings.size())


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
	if prewarm_mode or _loading_screen_active():
		await get_tree().process_frame

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

func _on_survey_tile_clicked(tile_data: Dictionary) -> void:
	# Clicking a tile in the Surveying mapmode opens its survey dialog. Fully
	# surveyed tiles (and ones already being surveyed) trigger no dialog.
	var tile_id := str(tile_data.get("id", ""))
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

func _on_unlock_granted(title: String, description: String, via_condition: bool) -> void:
	if via_condition:
		_unlock_dialog.show_unlock(title, description)

func _on_v2_building_clicked(building: Dictionary) -> void:
	# v2 is added to HUDContent after the building panel, so it would otherwise draw
	# on top. Raise the building panel FIRST (the re-sort re-asserts scene anchors),
	# then show/position it — otherwise the first click positions then the re-sort
	# undoes it, leaving an empty-looking panel until the next click.
	building_panel.move_to_front()
	building_panel.show_building(building)

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
	info_panel.hide()
	building_panel.hide()
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

func _on_go_to_tile_stockpile(tile_id: String) -> void:
	var td := _tile_data_by_id(tile_id)
	if td.is_empty():
		return
	_last_selected_tile = td
	info_panel._active_tab = "stock"
	info_panel.show_tile(td)

## Deep-link target for notifications etc: centre the camera on the tile and
## open its panel. Emitted via MatchState.focus_tile_requested.
func _on_focus_tile_requested(tile_id: String) -> void:
	var td := _focus_camera_on_tile(tile_id)
	if td.is_empty():
		return
	_last_selected_tile = td
	info_panel.show_tile(td)

## Deep-link target for a specific building (starvation notifications): centre on
## its tile and open the building detail panel rather than the tile panel.
func _on_focus_building_requested(instance_id: String) -> void:
	var building: Dictionary = MatchState.get_building(instance_id)
	if building.is_empty():
		return
	_focus_camera_on_tile(str(building.get("tile_id", "")))
	building_panel.move_to_front()
	building_panel.show_building(building)

## Centre the camera on a tile; returns its tile_data ({} if unknown).
func _focus_camera_on_tile(tile_id: String) -> Dictionary:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not terrain_layer.tiles.has(coord):
		return {}
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var cell := terrain_layer.map_coord_for_tile_coord(coord)
		cam.position = terrain_layer.to_global(terrain_layer.map_to_local(cell))
	return terrain_layer.tiles[coord]

func _on_v2_pick_destination() -> void:
	# Enter map pick mode but keep the v2 panel visible; the result returns via
	# on_destination_picked() so the player can then confirm in the panel.
	_v2_picking_dest = true
	terrain_layer.begin_stockpile_destination_selection("")

func _on_stockpile_destination_selected(tile_data: Dictionary) -> void:
	if _v2_picking_dest:
		_v2_picking_dest = false
		terrain_layer.end_stockpile_destination_selection()
		info_panel.on_destination_picked(str(tile_data.get("id", "")))
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
	MatchState.set_output_stockpile_destination(instance_id, tile_id, good_id)
	_pending_stockpile_selection.clear()
	_hide_stockpile_select_prompt()
	_exit_stockpile_ui_mode()

# ----- Stockpile selection UI mode -----

func _enter_stockpile_ui_mode() -> void:
	info_panel.hide()
	building_panel.hide()
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
	TurnManager.commit_turn()

func _on_encyclopedia_pressed() -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia"):
		search_overlay.open_encyclopedia()

func _on_encyclopedia_entry_requested(entry_id: String) -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia_entry"):
		search_overlay.open_encyclopedia_entry(entry_id)

func _on_search_recipe_build_requested(building_id: String, recipe_id: String) -> void:
	BuildMode.enter_build_mode(building_id, recipe_id)

func _on_build_attempted(building_id: String, tile_id: String) -> void:
	print("[Build] attempt: building=%s tile=%s" % [building_id, tile_id])
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
	var cost: float = float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0))

	# Construction materials must be present on the tile. If any are missing, offer the
	# order-or-cancel dialog and stop here — no money deducted, no tile space reserved.
	var mat_check: Dictionary = Construction.check_tile(tile_id, building_id)
	if not bool(mat_check.get("satisfied", false)):
		print("[Build] materials missing on %s for %s: %s" % [tile_id, building_id, str(mat_check.get("missing", {}))])
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

func _show_construction_missing_dialog(building_id: String, recipe_id: String, tile_id: String, missing: Dictionary) -> void:
	# Lazily build one reusable dialog on the HUD. Phase 1 only wires Cancel (close); the
	# Buy / Use-stockpile CTAs are disabled in the dialog and connected here for later phases.
	if _construction_dialog == null:
		_construction_dialog = load("res://scripts/construction_missing_dialog.gd").new()
		_hud.add_child(_construction_dialog)
		_construction_dialog.buy_requested.connect(_on_construction_buy_requested)
		_construction_dialog.use_stockpile_requested.connect(_on_construction_use_stockpile_requested)
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
	var cost: float = float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0))
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

func _on_construction_use_stockpile_requested(building_id: String, recipe_id: String, tile_id: String) -> void:
	# Source the missing materials from another tile's spare stock: charge the build cost +
	# transport, pull the shortfall into the build site, reserve it as an awaiting project.
	var coord := terrain_layer.id_to_coord(tile_id)
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0))
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
		if animate:
			await get_tree().process_frame   # let the loading screen animate between buildings

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
	if animate:
		await get_tree().process_frame

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
		var tile_id := str(entry.tile)
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var instance_id := str(entry.instance_id)
		if MatchState.buildings.has(instance_id):
			continue
		MatchState.add_building(
			str(entry.building), str(entry.recipe), tile_id,
			str(entry.owner), instance_id, false)
		building_placed.emit(tile_id, str(entry.building), str(entry.recipe), instance_id, coord)
		if animate:
			await get_tree().process_frame   # one building per frame keeps the slideshow moving

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
	_show_deposit_dialog(
		"Deposit exhausted",
		"The %s deposit here has run out — this building can no longer produce." % _good_display_for_deposit(token),
		[{"id": "demolish", "label": "Demolish"}, {"id": "change", "label": "Change Recipe"}])

func _show_deposit_dialog(title: String, body: String, buttons: Array) -> void:
	if _deposit_dialog == null:
		_deposit_dialog = load("res://scripts/deposit_dialog.gd").new()
		_hud.add_child(_deposit_dialog)
		_deposit_dialog.action_chosen.connect(_on_deposit_dialog_action)
	_deposit_dialog.open(title, body, buttons)

func _on_deposit_dialog_action(_id: String) -> void:
	pass  # Demolish / Change Recipe are no-ops for now; the dialog closes itself.

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
	var cost: float = float(building_data.get("base_price", 0.0))
	if infra_building_id != "":
		# Already being built here — silently bail rather than charging twice.
		for project in Construction.projects_on_tile(tile_id):
			if str(project.get("building_id", "")) == infra_building_id:
				print("Tile %s is already building %s" % [tile_id, infra_type])
				return
		var space_check := _space_check_for_build(tile_id, infra_building_id)
		if not bool(space_check.get("allowed", false)):
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
	print("Built %s on %s" % [infra_type, tile_id])

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

func _space_check_for_build(tile_id: String, building_id: String) -> Dictionary:
	var building_data: Dictionary = Catalog.get_building(building_id)
	var added_space := maxf(0.0, float(building_data.get("tile_size_used", 1.0)))
	var current_space := MatchState.get_tile_space_used(tile_id)
	var projected_space := current_space + added_space
	if projected_space > float(MatchState.MAX_TILE_LAND):
		print("[Build] FAILED: tile %s is full (need %s, max %s)" % [tile_id, str(projected_space), str(MatchState.MAX_TILE_LAND)])
		_show_tile_space_error("There is no more room on that tile. Demolish buildings to make room.")
		return {"allowed": false, "cost_multiplier": 1.0}
	var land_owned := MatchState.get_tile_land_owned(tile_id)
	if projected_space > float(land_owned):
		print("[Build] FAILED: insufficient land on tile %s (need %s, own %s)" % [tile_id, str(projected_space), str(land_owned)])
		_show_tile_space_error("You cannot build that. You do not own sufficient land on tile %s" % tile_id)
		return {"allowed": false, "cost_multiplier": 1.0}
	var cost_multiplier := 1.0
	if projected_space > DENSITY_SOFT_CAPACITY:
		cost_multiplier = 1.5
		_show_tile_space_caution("Local opposition to density on tile %s will increase material and money costs for new buildings by 50%%" % tile_id)
	return {"allowed": true, "cost_multiplier": cost_multiplier}

func _show_tile_space_error(message: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_error"):
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
	_stockpile_select_prompt.custom_minimum_size = Vector2(520, 30)
	_stockpile_select_prompt.anchor_left = 0.5
	_stockpile_select_prompt.anchor_right = 0.5
	_stockpile_select_prompt.anchor_top = 1.0
	_stockpile_select_prompt.anchor_bottom = 1.0
	_stockpile_select_prompt.offset_left = -260.0
	_stockpile_select_prompt.offset_right = 260.0
	_stockpile_select_prompt.offset_top = -158.0
	_stockpile_select_prompt.offset_bottom = -128.0
	_stockpile_select_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.94)
	style.border_color = Color(0.995, 0.93, 0.76, 0.6)
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

func _show_stockpile_select_prompt(selection: Dictionary) -> void:
	if _stockpile_select_prompt == null:
		return
	var label := _stockpile_select_prompt.get_node_or_null("Label") as Label
	if label != null:
		var good_id: String = selection.get("good_id", "")
		label.text = "Select tile to send %s to for stockpiling" % Catalog.get_display_name(good_id)
	_stockpile_select_prompt.visible = true

func _hide_stockpile_select_prompt() -> void:
	if _stockpile_select_prompt != null:
		_stockpile_select_prompt.visible = false

# Handled in _input (before GUI focus navigation) so Tab toggles the Empire view
# reliably even when a button/panel holds focus. Skipped while typing so Tab still
# works inside text fields (e.g. the search overlay).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_empire_view") and not _is_text_entry_focused():
		if empire_view != null:
			empire_view.toggle()
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
			if not _pending_stockpile_selection.is_empty():
				MatchState.cancel_output_stockpile_selection()
			elif not PanelStack.close_top():
				# Nothing left to close: Esc opens the in-game menu.
				PauseMenu.open(_hud)
			get_viewport().set_input_as_handled()

func _should_open_search(event: InputEventKey) -> bool:
	if search_overlay == null or search_overlay.visible:
		return false
	if event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if not _pending_stockpile_selection.is_empty():
		return false
	return not _is_text_entry_focused()

func _is_text_entry_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
