class_name InfrastructureInfo
extends RefCounted
## Small, UI-agnostic reference for infrastructure descriptions and its player-facing
## level stats. Capacities deliberately come from EconomyConfig, the same source the
## simulation uses, so the panels cannot drift away from actual transport behaviour.

static func key_for(building_data: Dictionary) -> String:
	match str(building_data.get("internal_name", "")).strip_edges().to_lower():
		"rails", "rail", "railway", "railways": return "rail"
		"pipes", "pipework", "pipeworks": return "pipes"
		"reinf_pipes", "reinforced_pipes", "reinforced pipework": return "reinf_pipes"
		"high voltage cables", "high_voltage_cables": return "hvdc"
		_: return str(building_data.get("internal_name", "")).strip_edges().to_lower()

static func purpose(key: String) -> String:
	match key:
		"roads": return "Moves solid goods like sand, coal and computers for a quarter of the cost over bare ground. Upgrades make it faster."
		"rail": return "Enables faster and cheaper movement of solid goods than roads."
		"rail_hub": return "Doubles rail throughput within 3 tiles while owned and powered. Overlapping hubs do not stack. Occupies 30 land, costs £10 maintenance and £6 base labour per turn, and consumes 80 power. No levels."
		"pipes": return "Enables transport of safe liquids: water, crude oil, processed oil and waste water."
		"reinf_pipes": return "Enables transport of hazardous liquids and gases, such as nitrogen, hydrogen and chlorine."
		"cables": return "Enables power transmission from electricity producers and to consumers. Required to power buildings."
		"hvdc": return "Nothing yet."
		_: return "Infrastructure improves how this region moves goods and power."

static func has_level_stats(key: String) -> bool:
	return key not in ["hvdc", "rail_hub"]

static func level_stats(key: String, level: int) -> Dictionary:
	if key == "cables":
		return {
			"capacity_label": "Power cap",
			"capacity": "%s power / tile / turn" % _number(float(EconomyConfig.CABLE_POWER_CAP.get(level, 0))),
			"tiles": "Connected cable network",
			"cost": "No per-unit transmission charge",
		}
	var mode := key
	# Keep the building details and construction panels on the router's speed table, level by level.
	var range := EconomyConfig.infra_speed_for_level(mode, level)
	if range <= 0:
		# Preserve the CSV fallback for a future levelled mode that has not yet been added
		# to EconomyConfig.INFRA_SPEED_BY_LEVEL.
		range = Catalog.infra_range(mode)
	var capacity: float = TransportService.link_capacity(mode, level)
	return {
		"capacity_label": "Transport soft cap",
		"capacity": "%s units / tile / turn" % _number(capacity),
		"tiles": "%d tile%s / turn" % [range, "" if range == 1 else "s"],
		"cost": _tile_cost_text(mode, level),
	}

## The weight charge a unit pays a tile on `mode` at `level`, lightest class to heaviest, before the share that rides
## on the good's value: what EconomyConfig.freight_tile_mult charges. Pipes carry fluids at one rate.
static func _tile_cost_text(mode: String, level: int) -> String:
	var rates: Array = []
	for cls: String in (["safe_liquid"] if EconomyConfig.PIPE_MODES.has(mode) else ["solid_light", "solid_heavy", "ultra_heavy"]):
		rates.append(TransportService.tile_weight_rate(cls, mode, level))
	if is_equal_approx(float(rates.min()), float(rates.max())):
		return "£%.3f / unit / tile" % float(rates[0])
	return "£%.3f to £%.3f / unit / tile" % [float(rates.min()), float(rates.max())]


static func _number(value: float) -> String:
	return str(int(round(value)))
