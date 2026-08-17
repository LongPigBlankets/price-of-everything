extends Node
## What ground does a gameplay building ACTUALLY cover, and what does its slot reserve?
##
## The slot boxes were squares sized to the class maximum. This measures the real thing:
## `InkBuildingGen.level_frame(art_key, 3)` is the sprite's own L3 frame, and the game scales
## it so its LONGER side hits the drawn target, then blocks `ART_BLOCK_MARGIN` around it —
## the same arithmetic `_crop_to_sprite` performs when it replaces a lot with the sprite's box.
##
##   <godot> --headless --path . res://tools/map_editor/slot_footprint_audit.tscn --quit-after 900

const AuthoredSlotSizes := preload("res://scripts/authored_slot_sizes.gd")
const AuthoredMapRef := preload("res://scripts/authored_map.gd")
const BuildingVisualsRef := preload("res://scenes/building_visuals.gd")
const InkBuildingGenRef := preload("res://scripts/ink_building_gen.gd")


static func _bigger_first(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector2 = a["blocked"]
	var pb: Vector2 = b["blocked"]
	return pa.x * pa.y > pb.x * pb.y


func _ready() -> void:
	await get_tree().process_frame
	var rows: Array = []
	var no_art: Array = []
	for row_value in AuthoredSlotSizes.table():
		var row: Dictionary = row_value
		var internal := str(row["internal"])
		var art_key := str(BuildingVisualsRef.INK_ART_KEY.get(internal, internal))
		var frame: Vector2 = InkBuildingGenRef.level_frame(art_key, 3)
		if frame.x <= 0.0 or frame.y <= 0.0:
			no_art.append(internal)
			continue
		var target := float(row["extent"])
		var scale := target / maxf(frame.x, frame.y)
		var drawn := Vector2(frame.x * scale, frame.y * scale)
		var blocked := drawn + Vector2.ONE * (BuildingVisualsRef.ART_BLOCK_MARGIN * 2.0)
		rows.append({"internal": internal, "class": str(row["class"]), "target": target,
			"drawn": drawn, "blocked": blocked})

	print("[FOOT] %d building(s) measured, %d with no ink art (%s)"
		% [rows.size(), no_art.size(), ", ".join(no_art)])
	print("[FOOT] margin=%.1f per side, so blocked = drawn + %.1f on each axis"
		% [BuildingVisualsRef.ART_BLOCK_MARGIN, BuildingVisualsRef.ART_BLOCK_MARGIN * 2.0])
	print("")
	for slot_class in ["small", "medium"]:
		var reserved: Vector2 = BuildingVisualsRef.AUTHORED_SLOT_BOXES.get(slot_class, Vector2.ZERO)
		var need := Vector2.ZERO
		var widest := ""
		var tallest := ""
		var count := 0
		var covered := 0.0
		for row_value in rows:
			var row: Dictionary = row_value
			if str(row["class"]) != slot_class:
				continue
			count += 1
			var blocked: Vector2 = row["blocked"]
			covered += blocked.x * blocked.y
			if blocked.x > need.x:
				need.x = blocked.x
				widest = str(row["internal"])
			if blocked.y > need.y:
				need.y = blocked.y
				tallest = str(row["internal"])
		if count == 0:
			continue
		var reserved_area := reserved.x * reserved.y
		print("[FOOT] %s — %d building(s)" % [slot_class.to_upper(), count])
		print("[FOOT]   reserved now : %.0f x %.0f  (%.0f u2)" % [reserved.x, reserved.y, reserved_area])
		print("[FOOT]   actually need: %.1f x %.1f  (widest %s, tallest %s)"
			% [need.x, need.y, widest, tallest])
		print("[FOOT]   -> %.0f%% of the reserved ground is never covered by the biggest member"
			% (100.0 * (1.0 - (need.x * need.y) / reserved_area)))
		print("[FOOT]   -> the AVERAGE member covers %.0f%% of it"
			% (100.0 * (covered / float(count)) / reserved_area))
		# The five biggest and five smallest, so the spread inside the class is visible.
		var members: Array = []
		for row_value in rows:
			if str((row_value as Dictionary)["class"]) == slot_class:
				members.append(row_value)
		members.sort_custom(_bigger_first)
		for i in mini(4, members.size()):
			var m: Dictionary = members[i]
			print("[FOOT]      largest  %-24s %.1f x %.1f" % [m["internal"],
				(m["blocked"] as Vector2).x, (m["blocked"] as Vector2).y])
		for i in range(maxi(0, members.size() - 4), members.size()):
			var m: Dictionary = members[i]
			print("[FOOT]      smallest %-24s %.1f x %.1f" % [m["internal"],
				(m["blocked"] as Vector2).x, (m["blocked"] as Vector2).y])
		print("")

	# What the slot actually does to the art. The authored path makes a rect of
	# (slot - CHUNK_GAP), then `_crop_to_sprite` shrinks the sprite to fit inside it. A slot
	# too small for its class's biggest member does not fail — it silently draws that member
	# smaller, which is the kind of defect nobody reports because it still looks fine.
	print("[FOOT] SHRINK — art scaled down to fit its slot (1.00 = drawn at full size)")
	var shrunk := 0
	for row_value in rows:
		var row: Dictionary = row_value
		var reserved: Vector2 = BuildingVisualsRef.AUTHORED_SLOT_BOXES.get(
			str(row["class"]), Vector2.ZERO)
		if reserved == Vector2.ZERO:
			continue
		var half := (reserved.x - BuildingVisualsRef.CHUNK_GAP) * 0.5
		var blocked: Vector2 = row["blocked"]
		var fit := minf(1.0, minf(half / (blocked.x * 0.5), half / (blocked.y * 0.5)))
		if fit < 0.999:
			shrunk += 1
			print("[FOOT]   %-24s %-7s %.1f x %.1f in a %.0f box -> x%.2f"
				% [row["internal"], row["class"], blocked.x, blocked.y, reserved.x, fit])
	print("[FOOT] %d of %d measured buildings are drawn smaller than intended" % [shrunk, rows.size()])
	print("")

	# The class a building ASKS for when it claims a slot is computed in building_visuals as
	# `slot_class_for(_art_size_for(size_units, ""))` — with an EMPTY art key, so the
	# per-recipe ART_SIZE_OVERRIDE never applies. The size table applies it. Where the two
	# disagree, a building claims a slot smaller than the one its art actually needs.
	print("[FOOT] CLASS MISMATCH — what a building claims vs what its art needs")
	var mismatched := 0
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var internal := str(building.get("internal_name", ""))
		if internal == "":
			continue
		var needs := AuthoredSlotSizes.class_for_building(str(building.get("id", "")))
		var units := int(building.get("tile_size_used", 1))
		# Mirrors the claim site in `_claim_slot`, ART KEY INCLUDED. It used to pass an empty
		# key, which is the defect this section was written to find.
		var art_key := str(BuildingVisualsRef.INK_ART_KEY.get(internal, ""))
		var extent: float = float(BuildingVisualsRef.ART_SIZE_OVERRIDE[art_key]) \
			if BuildingVisualsRef.ART_SIZE_OVERRIDE.has(art_key) \
			else lerpf(BuildingVisualsRef.ART_DRAWN_MIN, BuildingVisualsRef.ART_DRAWN_MAX,
				clampf((float(units) - 1.0) / 29.0, 0.0, 1.0))
		var claims: String = AuthoredMapRef.slot_class_for(extent, false)
		if needs != claims:
			mismatched += 1
			print("[FOOT]   %-24s claims '%s', art needs '%s'" % [internal, claims, needs])
	print("[FOOT] %d building(s) would claim the wrong slot class" % mismatched)
	get_tree().quit(0)
