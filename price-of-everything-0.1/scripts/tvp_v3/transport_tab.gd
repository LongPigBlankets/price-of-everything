extends RefCounted
## Tile view v3: the Transport tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.


static func build(panel: Control, pane: VBoxContainer) -> void:
	panel.call("_build_transport_pane", pane)
