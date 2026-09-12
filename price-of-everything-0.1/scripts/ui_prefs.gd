extends Node
## UiPrefs: presentation-only switches — the panel/top-bar variant toggles the debug terminal
## flips (`swap` / `toggle`), the empire-view sprite and badge choices, the construct panel's
## cost display and expanded-recipe view, and the per-turn debug log flag. None of it is
## simulation state: nothing here changes an economic outcome, so it lives outside MatchState
## and is NOT written to saves (moved out on 2026-09-12; the two keys older saves may carry,
## construct_cost_display and construct_expanded_recipe_mode, are ignored on load).
##
## The two construct-panel display prefs still announce themselves through
## MatchState.construct_settings_changed, the signal the panels already listen to, and are
## reset to defaults with the match like before.


# The Building Detail v2 dev-toggle flipped; world_map re-renders the
# active detail panel. Session-only.
signal construct_panel_v2_changed(enabled: bool)
# The confirm-screen v3 dev-toggle flipped; the V2
# panel re-renders so the gated visuals apply immediately. Session-only.
signal construct_panel_v3_changed(enabled: bool)
# The top-bar icon redesign dev-toggle flipped; top_bar.gd
# re-renders the affected modules so the gated visuals apply immediately. Session-only.
signal topbar_v3_1_changed(enabled: bool)
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
# Debug-only: keeps the classic construct panel available
# for comparison. The redesigned construct panel is the normal default.
# Session-only; only changes the active match.
var use_construct_panel_v2: bool = true
# Debug-only: keeps the pre-redesign confirm screen
# available for comparison (designer spec "Confirm Construction Panel v2",
# tracked as v3 here) inside the V2 panel. The redesigned confirm screen is
# the normal default. Session-only, never persisted.
var use_construct_panel_v3: bool = true
# Debug-only: keeps the pre-redesign top bar (Goods Graph,
# Encyclopedia, Mission, Power, Victory, Rankings as text/vector-glyph faces)
# available for comparison inside the existing top_bar.gd — same "render branch
# behind a flag, not a second scene" shape as use_construct_panel_v3. The
# icon-faced redesign (baked standalone icons in assets/icons/ui_icons/standalone/)
# is the normal default. Session-only, never persisted.
var use_topbar_v3_1: bool = true
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

func set_use_construct_panel_v2(enabled: bool) -> bool:
	if enabled == use_construct_panel_v2:
		return use_construct_panel_v2
	use_construct_panel_v2 = enabled
	construct_panel_v2_changed.emit(use_construct_panel_v2)
	return use_construct_panel_v2

func toggle_use_construct_panel_v2() -> bool:
	return set_use_construct_panel_v2(not use_construct_panel_v2)

func set_use_construct_panel_v3(enabled: bool) -> bool:
	if enabled == use_construct_panel_v3:
		return use_construct_panel_v3
	use_construct_panel_v3 = enabled
	construct_panel_v3_changed.emit(use_construct_panel_v3)
	return use_construct_panel_v3

func toggle_use_construct_panel_v3() -> bool:
	return set_use_construct_panel_v3(not use_construct_panel_v3)

func set_use_topbar_v3_1(enabled: bool) -> bool:
	if enabled == use_topbar_v3_1:
		return use_topbar_v3_1
	use_topbar_v3_1 = enabled
	topbar_v3_1_changed.emit(use_topbar_v3_1)
	return use_topbar_v3_1

func toggle_use_topbar_v3_1() -> bool:
	return set_use_topbar_v3_1(not use_topbar_v3_1)

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
