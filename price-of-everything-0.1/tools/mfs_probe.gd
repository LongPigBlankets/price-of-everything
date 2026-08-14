extends SceneTree
## Scratch probe for scripts/mass_form_shapes.gd. Not part of the suite.

const MFS := preload("res://scripts/mass_form_shapes.gd")

func _initialize() -> void:
	var boxes := [
		Vector2(120.0, 55.0), Vector2(60.0, 60.0), Vector2(45.0, 90.0),
		Vector2(200.0, 40.0), Vector2(30.0, 30.0), Vector2(18.0, 14.0),
		Vector2(300.0, 300.0), Vector2(80.0, 26.0), Vector2(26.0, 80.0),
	]
	for form_value in MFS.ALL_FORMS:
		var form := str(form_value)
		var line := "%-16s " % form
		for box_value in boxes:
			var box: Vector2 = box_value
			var res := MFS.construct(form, box.x, box.y, MFS.params_mid(form))
			var polys: Array = res.get("polys", [])
			line += ("." if polys.is_empty() else str(polys.size()))
		print(line)
	# Congruence probe: two keys, same form, same box.
	for form_value in MFS.ALL_FORMS:
		var form := str(form_value)
		var a := MFS.construct(form, 140.0, 70.0, MFS.params(form, "blockA|7"))
		var b := MFS.construct(form, 140.0, 70.0, MFS.params(form, "blockQ|31"))
		var pa: Array = a.get("polys", [])
		var pb: Array = b.get("polys", [])
		if pa.is_empty() or pb.is_empty():
			print("congruence %-16s SKIP" % form)
			continue
		var same := true
		for i in mini(pa.size(), pb.size()):
			if MFS.area(pa[i]) != MFS.area(pb[i]):
				same = false
		print("congruence %-16s identical=%s  areaA=%.1f areaB=%.1f verts=%d" % [
			form, str(same), MFS.area(pa[0]), MFS.area(pb[0]), (pa[0] as PackedVector2Array).size()])
	quit()
