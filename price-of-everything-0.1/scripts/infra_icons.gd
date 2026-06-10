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

const _EXTS := [".png", ".PNG"]

## Icon for an infrastructure type via its building (whose internal_name is the
## slot key). Returns null when the building or its art doesn't exist (HVDC).
static func texture_for(building_id: String, infra_key: String) -> Texture2D:
	if building_id == "" or infra_key == "":
		return null
	for ext in _EXTS:
		var path := "res://assets/icons/buildings/%s_%s%s" % [building_id, infra_key, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

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
