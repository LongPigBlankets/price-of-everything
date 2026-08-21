## Shared helpers for the Infrastructure mapmode UI. SLOTS is the canonical
## six-type set (same slots as the tile panel's infrastructure grid), and
## normalise() collapses the assorted spellings found in map data and runtime
## builds ("railways", "pipework", …) back to those slot keys. Note this is the
## building namespace ("rails"), not Catalog's routing namespace ("rail").
## Like good_icons.gd, callers pass Catalog-derived data in; this file only
## resolves icon files.

const SLOTS: Array = [
	{"key": "cables", "label": "Cables"},
	{"key": "roads", "label": "Roads"},
	{"key": "pipes", "label": "Pipework"},
	{"key": "hvdc", "label": "HVDC"},
	{"key": "rails", "label": "Rail"},
	{"key": "reinf_pipes", "label": "Reinforced pipework"},
]

## Mapmode colour per infrastructure type — the stockpile bar-chart palette
## (stockpile_view.gd COLOR_PALETTE) assigned in the agreed order:
## cables, roads, rails, pipes, hvdc, reinf_pipes.
const COLORS := {
	"cables": Color(0.13, 0.55, 0.13, 0.92),       # green
	"roads": Color(0.95, 0.83, 0.18, 0.92),        # yellow
	"rails": Color(0.47, 0.78, 1.0, 0.92),         # light blue
	"pipes": Color(0.55, 0.35, 0.88, 0.92),        # purple
	"hvdc": Color(0.22, 0.22, 0.22, 0.92),         # near-black
	"reinf_pipes": Color(0.95, 0.48, 0.14, 0.92),  # orange
}

const _EXTS := [".png", ".PNG"]

static func color_for(infra_key: String) -> Color:
	return COLORS.get(infra_key, Color.WHITE)

## Icon for an infrastructure type via its building (whose internal_name is the
## slot key). Returns null when the building or its art doesn't exist (HVDC).
static func texture_for(building_id: String, infra_key: String) -> Texture2D:
	var path := source_path_for(building_id, infra_key)
	return load(path) as Texture2D if path != "" else null


## The file texture_for would load, or "". Split out so a caller can hash the exact source it
## is about to clean (see building_icon.gd) rather than guessing at the extension.
static func source_path_for(building_id: String, infra_key: String) -> String:
	if building_id == "" or infra_key == "":
		return ""
	for ext in _EXTS:
		var path := "res://assets/icons/buildings/%s_%s%s" % [building_id, infra_key, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

static func normalise(infra_name: String) -> String:
	match infra_name.strip_edges().to_lower():
		"rail", "rails", "railway", "railways":
			return "rails"
		"pipes", "pipework", "pipeworks":
			return "pipes"
		"reinf_pipes", "reinforced_pipes", "reinforced_pipework", "reinforced_pipeworks":
			return "reinf_pipes"
		_:
			return infra_name.strip_edges().to_lower()
