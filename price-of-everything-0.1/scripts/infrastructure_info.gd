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
		"roads": return "Enables faster movement of solid goods like sand, coal and computers."
		"rail": return "Enables faster and cheaper movement of solid goods than roads."
		"pipes": return "Enables transport of safe liquids — water, crude oil, processed oil and waste water."
		"reinf_pipes": return "Enables transport of hazardous liquids and gases, such as nitrogen, hydrogen and chlorine."
		"cables": return "Enables power transmission from electricity producers and to consumers. Required to power buildings."
		"hvdc": return "Nothing yet."
		_: return "Infrastructure improves how this region moves goods and power."

static func has_level_stats(key: String) -> bool:
	return key != "hvdc"

static func level_stats(key: String, level: int) -> Dictionary:
	if key == "cables":
		return {
			"capacity_label": "Power cap",
			"capacity": "%s power / tile / turn" % _number(float(EconomyConfig.CABLE_POWER_CAP.get(level, 0))),
			"tiles": "Connected cable network",
			"cost": "No per-unit transmission charge",
		}
	var mode := key
	var range := 0
	match key:
		"roads": range = 2
		"rail": range = 4
		"pipes", "reinf_pipes": range = 2
	var capacity: float = TransportService.link_capacity(mode, level)
	var cost := "£0.02–£0.06 / unit / turn"
	if key == "rail":
		cost = "£0.01–£0.03 / unit / turn"
	elif key == "pipes" or key == "reinf_pipes":
		cost = "£0.03 / unit / tile"
	return {
		"capacity_label": "Transport soft cap",
		"capacity": "%s units / tile / turn" % _number(capacity),
		"tiles": "%d tile%s / turn" % [range, "" if range == 1 else "s"],
		"cost": cost,
	}

static func _number(value: float) -> String:
	return str(int(round(value)))
