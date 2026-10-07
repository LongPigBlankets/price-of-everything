extends Node
## UiPrefs: presentation-only switches — the DS2 looks still under review (map legends, updates dock, research),
## which the debug terminal flips (`toggle`), the empire-view sprite and badge choices, the construct
## panel's cost display and expanded-recipe view, and the per-turn debug log flag. None of it is
## simulation state: nothing here changes an economic outcome, so it lives outside MatchState
## and is NOT written to saves (moved out on 2026-09-12; the two keys older saves may carry,
## construct_cost_display and construct_expanded_recipe_mode, are ignored on load).
##
## The two construct-panel display prefs still announce themselves through
## MatchState.construct_settings_changed, the signal the panels already listen to, and are
## reset to defaults with the match like before.


## The map legends' DS2 pad switched on or off.
signal legend_ds2_changed(enabled: bool)
## The updates dock's DS2 look switched on or off.
signal dock_ds2_changed(enabled: bool)
## The Research panel's DS2 look switched on or off.
signal research_ds2_changed(enabled: bool)
signal empire_button_icon_changed(use_badge: bool)

# Debug-only: verbose per-turn production / CostSolver logs. Off by default because
# large empires can produce hundreds of console lines per turn in editor builds.
# Toggled at runtime via the `logs` debug-terminal cheat. Session-only.
var debug_turn_logs_enabled: bool = false
# The empire view's DEFAULT look: no background pattern, a large 2.5D building sprite above
# each node with its metal plate attached below. Buildings without a sprite keep the classic
# full-card layout, so partial sprite coverage degrades gracefully.
# The dev toggle switches BACK to the classic card style. Session-only; never persisted.
var use_empire_sprite_view: bool = true
## Empire view: mark buildings that ship to market with a gold port hex on the sprite instead
## of drawing a line to the port row; the dev toggle switches back to lines.
## Session-only; never persisted.
var show_port_badge: bool = true
## Debug-only: alternates the bottom-menu Empire View icon
## between the badge-centre default and the skyline alternative. Session-only.
var use_empire_button_badge: bool = true
# The bottom-left map legends on the DS2 pad (scripts/ds2/legend_pad.gd): dark plastic with cut corners. Off until
# the owner has reviewed it; the debug cheat `toggle legend ds2` switches it on. Session-only.
var use_legend_ds2: bool = false
# The updates dock in DS2 (scripts/toast_manager.gd): navy steel, the pen and bells raised, a row a module with a
# lamp. Off until the owner has reviewed it; the debug cheat `toggle dock ds2` switches it on. Session-only.
var use_dock_ds2: bool = false
# The Research panel in DS2 (scripts/research_ds2/): the patent office's board of blueprints and the drawing office's
# plan chest of drawers. Off until the owner has reviewed it; the debug cheat `toggle research ds2` switches it on.
# Session-only.
var use_research_ds2: bool = false
# Building Detail v3's diagnostics: the Visual view (true) or the Text rows. The player's choice on the
# panel's switch, kept while the game runs (closing the panel or starting a match keeps it).
var bdp_diag_visual: bool = false
# Construct V2 defaults. They are match settings rather than panel-local state so
# a construction captures the current choices when it begins, including after a
# save/load. The legacy cost-display field remains load-compatible but is no
# longer exposed in the V2 settings UI.
var construct_cost_display: String = "grid"
## Off = the browse list's recipe cards show the compact mini diagram (icons + "+" +
## an arrow, no quantities); on = the full Building-Details-style diagram with qty
## pills. Display-only — never read by BuildForecast/Production.
var construct_expanded_recipe_mode: bool = false


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:
	construct_cost_display = "grid"
	construct_expanded_recipe_mode = false


## Debug cheat: toggle verbose production / CostSolver console logs.
## Returns the new state. Session-only, never persisted.
func toggle_debug_turn_logs() -> bool:
	debug_turn_logs_enabled = not debug_turn_logs_enabled
	return debug_turn_logs_enabled

## Debug cheat: switch the empire view between port badges and port lines.
## Returns the new state. Session-only, never persisted.
func toggle_show_port_badge() -> bool:
	show_port_badge = not show_port_badge
	return show_port_badge

func toggle_use_empire_sprite_view() -> bool:
	use_empire_sprite_view = not use_empire_sprite_view
	return use_empire_sprite_view

## Debug cheat: switch the bottom-menu Empire View icon to/from its badge-centre
## alternative. Session-only, so it is safe for in-match visual comparison.
func toggle_use_empire_button_badge() -> bool:
	use_empire_button_badge = not use_empire_button_badge
	empire_button_icon_changed.emit(use_empire_button_badge)
	return use_empire_button_badge

func set_use_legend_ds2(enabled: bool) -> bool:
	if enabled == use_legend_ds2:
		return use_legend_ds2
	use_legend_ds2 = enabled
	legend_ds2_changed.emit(use_legend_ds2)
	return use_legend_ds2

func toggle_use_legend_ds2() -> bool:
	return set_use_legend_ds2(not use_legend_ds2)

func set_use_dock_ds2(enabled: bool) -> bool:
	if enabled == use_dock_ds2:
		return use_dock_ds2
	use_dock_ds2 = enabled
	dock_ds2_changed.emit(use_dock_ds2)
	return use_dock_ds2

func toggle_use_dock_ds2() -> bool:
	return set_use_dock_ds2(not use_dock_ds2)

func set_use_research_ds2(enabled: bool) -> bool:
	if enabled == use_research_ds2:
		return use_research_ds2
	use_research_ds2 = enabled
	research_ds2_changed.emit(use_research_ds2)
	return use_research_ds2

func toggle_use_research_ds2() -> bool:
	return set_use_research_ds2(not use_research_ds2)

func set_bdp_diag_visual(visual: bool) -> void:
	bdp_diag_visual = visual

func set_construct_cost_display(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower()
	if resolved not in ["grid", "compact", "list"]:
		resolved = "grid"
	if construct_cost_display == resolved:
		return
	construct_cost_display = resolved
	if emit_change:
		MatchState.construct_settings_changed.emit()

func set_construct_expanded_recipe_mode(enabled: bool, emit_change: bool = true) -> void:
	if construct_expanded_recipe_mode == enabled:
		return
	construct_expanded_recipe_mode = enabled
	if emit_change:
		MatchState.construct_settings_changed.emit()
