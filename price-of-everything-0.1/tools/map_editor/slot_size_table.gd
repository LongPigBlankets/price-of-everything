extends Node
## Prints the slot size-class table for review — the P3 item the owner rules on.
##
##   <godot> --headless --path . res://tools/map_editor/slot_size_table.tscn --quit-after 400
##
## Derived from the catalog and the art's own size constants, so it cannot drift from what is
## actually drawn. Anything wrong here is fixed by an override in AuthoredSlotSizes.OVERRIDES,
## not by editing the numbers.

const AuthoredSlotSizes := preload("res://scripts/authored_slot_sizes.gd")
const AuthoredMap := preload("res://scripts/authored_map.gd")

func _ready() -> void:
	var rows := AuthoredSlotSizes.table()
	var counts: Dictionary = {}
	for slot_class in AuthoredMap.SLOT_CLASSES:
		counts[slot_class] = 0
	var ceilings := PackedStringArray()
	for slot_class in AuthoredMap.SLOT_BOX_CLASSES:
		ceilings.append("%s < %.0f" % [slot_class, float(AuthoredMap.SLOT_CLASS_CEILINGS[slot_class])])
	print("[SLOTS] ceilings, in world units of drawn art: %s" % ", ".join(ceilings))
	print("[SLOTS] %-26s %6s %8s  %s" % ["building", "size", "extent", "class"])
	for row in rows:
		counts[str(row["class"])] = int(counts.get(str(row["class"]), 0)) + 1
		print("[SLOTS] %-26s %6.0f %8.1f  %s"
			% [row["internal"], row["size_units"], row["extent"], row["class"]])
	var tally := PackedStringArray()
	for slot_class in AuthoredMap.SLOT_CLASSES:
		tally.append("%d %s" % [int(counts[slot_class]), slot_class])
	print("[SLOTS] %d buildings — %s" % [rows.size(), ", ".join(tally)])
	get_tree().quit(0)
