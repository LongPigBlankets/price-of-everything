extends "res://tools/supply_chain_3d/capture.gd"
## Every bridge in the company view: authored road bridges over rivers, roads over rail, and rail
## truss spans. Each is shot close from two sides, and every road or rail that crosses a deck's
## plan without belonging to it is listed with the height gap between them.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/bridge_audit.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir>
var output := ""
var report := {"sites": []}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
		if arg == "--no-clearance": preload("res://scripts/supply_chain_3d/building_clearance.gd").enabled = false
	DirAccess.make_dir_recursive_absolute(output)
	await super._ready()

func _settle(board: Control, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until or bool(board.get("_building")) or not bool(board.call("detail_ready")):
		RenderingServer.force_draw(false); await get_tree().process_frame
		if Time.get_ticks_msec() > until + 90000: break

## Decks: every raised span, as segments with their top height at each end.
func _decks(builder: RefCounted) -> Array:
	var decks: Array = []
	for rec in builder.authored_profile.segments:
		if rec.get("bridge", false): decks.append({"kind": "road over river", "a": rec.a, "b": rec.b, "ha": float(rec.ha), "hb": float(rec.hb), "half": float(rec.half)})
	var grade: RefCounted = builder.road_grade
	for rec in grade.segments:
		if grade.nodes[rec.ka].core or grade.nodes[rec.kb].core:
			decks.append({"kind": "road over rail", "a": rec.a, "b": rec.b, "ha": float(rec.ha), "hb": float(rec.hb), "half": float(rec.half)})
	for samples in _rail_runs(builder):
		for i in range(1, samples.size()):
			if samples[i - 1].get("bridge", false) and samples[i].get("bridge", false):
				decks.append({"kind": "rail bridge", "a": samples[i - 1].p, "b": samples[i].p, "ha": float(samples[i - 1].h), "hb": float(samples[i].h), "half": 6.0})
	return decks

func _rail_runs(builder: RefCounted) -> Array:
	builder._prepare_rail_art()
	var runs: Array = []
	var profiles: Variant = builder._prepared_rail_art.get("profiles", [])
	for profile in (profiles.values() if profiles is Dictionary else profiles):
		if profile is Dictionary and profile.has("samples"): runs.append(profile.samples)
	return runs

## Sites: decks of one kind within 80 units of each other.
func _sites(decks: Array) -> Array:
	var sites: Array = []
	for deck in decks:
		var mid: Vector2 = (deck.a + deck.b) * 0.5
		var found := false
		for site in sites:
			if site.kind == deck.kind and (site.points as Array).any(func(q: Vector2) -> bool: return q.distance_to(mid) < 80.0):
				site.points.append(mid); site.decks.append(deck); found = true; break
		if not found: sites.append({"kind": deck.kind, "points": [mid], "decks": [deck]})
	return sites

static func _at(a: Vector2, b: Vector2, p: Vector2) -> float:
	return clampf(Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(a) / maxf(0.01, a.distance_to(b)), 0.0, 1.0)

## What crosses a site's decks in plan without belonging to them, and passes through or too
## close under the deck (a road needs 4.5 of headroom under 1.0 of deck).
func _crossings(builder: RefCounted, site: Dictionary) -> Array:
	var found: Array = []
	var others: Array = []
	for rec in builder.road_grade.segments: others.append({"what": "road L%d" % int(rec.get("level", 1)), "a": rec.a, "b": rec.b, "ha": float(rec.ha), "hb": float(rec.hb)})
	if site.kind != "rail bridge":
		for samples in _rail_runs(builder):
			for i in range(1, samples.size()): others.append({"what": "rail", "a": samples[i - 1].p, "b": samples[i].p, "ha": float(samples[i - 1].h), "hb": float(samples[i].h)})
	var seen := {}
	for e in others:
		for deck in site.decks:
			var hit: Variant = Geometry2D.segment_intersects_segment(e.a, e.b, deck.a, deck.b)
			if hit == null: continue
			var deck_h := lerpf(deck.ha, deck.hb, _at(deck.a, deck.b, hit))
			var h := lerpf(e.ha, e.hb, _at(e.a, e.b, hit))
			if absf(h - deck_h) < 0.8: continue
			if h > deck_h - 1.0 - 4.5 and h < deck_h + 0.5:
				var key := str(e.what) + str((hit as Vector2).snapped(Vector2(8, 8)))
				if seen.has(key): continue
				seen[key] = true
				found.append({"with": e.what, "at": [snappedf(hit.x, 0.1), snappedf(hit.y, 0.1)], "deck_h": snappedf(deck_h, 0.1), "its_h": snappedf(h, 0.1), "headroom": snappedf(deck_h - 1.0 - h, 0.1)})
	return found

## Every place a road crosses a rail or another road in plan at a height that is neither level
## (within 0.8) nor separated (5.5: 1.0 of deck and 4.5 of headroom): one runs into the other.
func _bad_crossings(builder: RefCounted) -> Array:
	var lines: Array = []
	for rec in builder.road_grade.segments:
		lines.append({"what": "road L%d" % int(rec.get("level", 1)), "a": rec.a, "b": rec.b, "ha": float(rec.ha), "hb": float(rec.hb), "ka": rec.ka, "kb": rec.kb})
	for samples in _rail_runs(builder):
		for i in range(1, samples.size()):
			if samples[i - 1].get("hidden", false) and samples[i].get("hidden", false): continue
			var truss: bool = samples[i - 1].get("river", false) or samples[i].get("river", false)
			lines.append({"what": "rail truss" if truss else "rail", "a": samples[i - 1].p, "b": samples[i].p, "ha": float(samples[i - 1].h), "hb": float(samples[i].h)})
	var grid := {}
	for i in lines.size():
		var box := Rect2(lines[i].a, Vector2.ZERO).expand(lines[i].b)
		for x in range(floori(box.position.x / 32.0), floori(box.end.x / 32.0) + 1):
			for y in range(floori(box.position.y / 32.0), floori(box.end.y / 32.0) + 1):
				(grid.get_or_add(Vector2i(x, y), []) as Array).append(i)
	var found: Array = []
	var seen := {}
	for cell in grid:
		var ids: Array = grid[cell]
		for m in ids.size():
			for n in range(m + 1, ids.size()):
				var e: Dictionary = lines[ids[m]]
				var f: Dictionary = lines[ids[n]]
				if str(e.what).begins_with("rail") and str(f.what).begins_with("rail"): continue
				if e.has("ka") and f.has("ka") and (e.ka in [f.ka, f.kb] or e.kb in [f.ka, f.kb]): continue
				var hit: Variant = Geometry2D.segment_intersects_segment(e.a, e.b, f.a, f.b)
				if hit == null: continue
				var he := lerpf(e.ha, e.hb, _at(e.a, e.b, hit))
				var hf := lerpf(f.ha, f.hb, _at(f.a, f.b, hit))
				var gap := absf(he - hf)
				# A truss's girders stand over its track: nothing crosses it at track level either.
				var truss: bool = e.what == "rail truss" or f.what == "rail truss"
				if (gap < 0.8 and not truss) or gap >= 5.5: continue
				var key := str((hit as Vector2).snapped(Vector2(16, 16)))
				if seen.has(key): continue
				seen[key] = true
				var upper: Dictionary = e if he > hf else f
				var lower: Dictionary = f if he > hf else e
				found.append({"over": upper.what, "under": lower.what, "at": [snappedf(hit.x, 0.1), snappedf(hit.y, 0.1)], "gap": snappedf(gap, 0.1),
					"tile": str(builder.ground.tile_at(hit)) if builder.ground.has_method("tile_at") else ""})
	return found

## Cliffs: where a visible rail or a road jumps 2 or more between neighbouring samples (a bridge
## end with no approach, a deck dropped onto a bank, a stepped street). The biggest per 24 units.
func _steps(builder: RefCounted) -> Array:
	var best := {}
	for samples in _rail_runs(builder):
		for i in range(1, samples.size()):
			var a: Dictionary = samples[i - 1]
			var b: Dictionary = samples[i]
			if a.get("hidden", false) or b.get("hidden", false): continue
			_keep(best, "rail", a.p, float(b.h) - float(a.h), (a.p as Vector2).distance_to(b.p),
				a.get("river", false) != b.get("river", false) or a.get("bridge", false) != b.get("bridge", false), builder)
	for rec in builder.road_grade.segments:
		var engineering := "serpentine" if rec.get("serpentine", false) else "eased" if rec.has("road_ha") else "terrain"
		_keep(best, "road L%d %s" % [int(rec.get("level", 1)), engineering], rec.a, float(rec.hb) - float(rec.ha), (rec.a as Vector2).distance_to(rec.b), bool(rec.bridge), builder)
	return best.values()

func _keep(best: Dictionary, what: String, at: Vector2, rise: float, run: float, bridge_end: bool, builder: RefCounted) -> void:
	if absf(rise) < 2.0 or run < 0.1 or absf(rise) / run < 0.35: return
	var key := what.get_slice(" ", 0) + str(at.snapped(Vector2(24, 24)))
	if best.has(key) and absf(float(best[key].rise)) >= absf(rise): return
	best[key] = {"what": what, "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "rise": snappedf(rise, 0.1), "run": snappedf(run, 0.1),
		"bridge_end": bridge_end, "tile": str(builder.ground.tile_at(at)) if builder.ground.has_method("tile_at") else ""}

## Everything standing on a road's carriageway (its own driveway aside): homes, depots, works.
func _on_roads(builder: RefCounted) -> Array:
	var Clearance := preload("res://scripts/supply_chain_3d/building_clearance.gd")
	var roads: Array = []
	for rec in builder.road_grade.segments: roads.append({"a": rec.a, "b": rec.b, "half": float(rec.get("widths", [rec.half])[-1]) if rec.has("widths") else float(rec.half)})
	var index := Clearance.Index.segments(roads, 12.0)
	var found: Array = []
	for pair in builder.sprite_pairs:
		if not pair.get("standing") is Dictionary or pair.standing.has("harbour"): continue
		var st: Dictionary = pair.standing
		if str(st.kind) not in ["house", "warehouse", "suppliers", "building", "site"]: continue
		if Clearance._on_road(st, Clearance.base(st, str(builder.standing_key(st)), float(st.side)), roads, index):
			found.append({"what": str(st.kind), "name": str(st.get("decor_asset", st.get("internal_name", ""))), "npc": bool(st.get("npc", false)), "at": [snappedf(st.pos.x, 0.1), snappedf(st.pos.y, 0.1)],
				"tile": str(st.get("tile", ""))})
	return found

func _continent_review(board: Control, _home: Dictionary) -> void:
	await _settle(board, 3.0)
	if "--all-tiles" in OS.get_cmdline_user_args():
		var started := Time.get_ticks_msec()
		await board.set_all_tiles(true, false)
		# The continent may still be building when the call returns: wait for its builder.
		while not (board._builder != null and bool(board._builder.streamed) and not bool(board.get("_building"))):
			RenderingServer.force_draw(false); await get_tree().process_frame
			if Time.get_ticks_msec() - started > 5400000: break
		await _settle(board, 5.0)
		print("[BRIDGE] all tiles shown after ", Time.get_ticks_msec() - started, " ms")
	var shots := "--no-shots" not in OS.get_cmdline_user_args()
	for probe in OS.get_environment("AUDIT_PROBE").split(";", false):
		var at := Vector2(float(probe.get_slice(",", 0)), float(probe.get_slice(",", 1)))
		print("[PROBE] ==== ", at)
		for rec in board._builder.road_grade.segments:
			if Geometry2D.get_closest_point_to_segment(at, rec.a, rec.b).distance_to(at) < 60.0:
				print("[PROBE] road L", rec.get("level", 1), " ", rec.a, "->", rec.b, " h ", snappedf(rec.ha, 0.1), "/", snappedf(rec.hb, 0.1), " bridge ", rec.bridge, " over_rail ", rec.over_rail, " eased ", board._builder.road_grade.nodes[rec.ka].get("eased", false), " core ", board._builder.road_grade.nodes[rec.ka].core, " base ", snappedf(board._builder.road_grade.nodes[rec.ka].base, 0.1), " mode ", rec.get("rail_crossing_mode", ""))
		var Clearance := preload("res://scripts/supply_chain_3d/building_clearance.gd")
		for pair in board._builder.sprite_pairs:
			if not pair.get("standing") is Dictionary: continue
			var st: Dictionary = pair.standing
			if (st.pos as Vector2).distance_to(at) > 50.0: continue
			var shapes := Clearance.base(st, str(board._builder.standing_key(st)), float(st.side))
			var best := INF
			for rec in board._builder.road_grade.segments:
				for poly in shapes:
					if poly.size() >= 3: best = minf(best, Clearance.RoadPlacement.distance_to_polygon(rec.a, rec.b, poly) - float(rec.half))
			print("[PROBE] standing ", st.kind, " ", st.get("decor_asset", st.get("internal_name", "")), " pos ", st.pos, " side ", snappedf(st.side, 0.1), " shapes ", shapes.size(), " pts ", (shapes[0] as PackedVector2Array).size() if not shapes.is_empty() else 0, " road_gap(half) ", snappedf(best, 0.1))
		for rec in board._builder.authored_profile.segments:
			if Geometry2D.get_closest_point_to_segment(at, rec.a, rec.b).distance_to(at) < 60.0:
				print("[PROBE] authored ", rec.a, "->", rec.b, " h ", snappedf(rec.ha, 0.1), "/", snappedf(rec.hb, 0.1), " bridge ", rec.bridge, " elevated ", rec.get("elevated", false), " ground ", snappedf(board._builder.natural_height(rec.a), 0.1), "/", snappedf(board._builder.natural_height(rec.b), 0.1))
		for samples in _rail_runs(board._builder):
			for smp in samples:
				if (smp.p as Vector2).distance_to(at) < 60.0:
					print("[PROBE] rail ", smp.p, " h ", snappedf(smp.h, 0.1), " bridge ", smp.get("bridge", false), " river ", smp.get("river", false), " hidden ", smp.get("hidden", false), " cut ", smp.get("cut", false), " ground ", snappedf(board._builder.natural_height(smp.p), 0.1))
	report.bad_crossings = _bad_crossings(board._builder)
	print("[BRIDGE] bad crossings ", report.bad_crossings.size())
	for c in report.bad_crossings: print("[CROSSING] ", JSON.stringify(c))
	report.on_roads = _on_roads(board._builder)
	print("[BRIDGE] on roads ", report.on_roads.size())
	for c in report.on_roads: print("[ONROAD] ", JSON.stringify(c))
	report.steps = _steps(board._builder)
	print("[BRIDGE] steps ", report.steps.size())
	for c in report.steps: print("[STEP] ", JSON.stringify(c))
	var builder: RefCounted = board._builder
	if shots and "--shoot-faults" in OS.get_cmdline_user_args():
		var faults: Array = []
		for c in report.bad_crossings: faults.append({"label": "crossing_%s_over_%s" % [str(c.over).replace(" ", ""), str(c.under).replace(" ", "")], "at": c.at, "tile": c.tile})
		for c in report.on_roads: faults.append({"label": "onroad_%s" % str(c.what), "at": c.at, "tile": c.tile})
		for c in report.steps: faults.append({"label": "step_%s_%s" % [str(c.what).replace(" ", ""), "bridge" if c.bridge_end else "line"], "at": c.at, "tile": c.tile})
		var shot_points: Array = []
		var k := 0
		for fault in faults:
			var p := Vector2(fault.at[0], fault.at[1])
			if shot_points.any(func(q: Vector2) -> bool: return q.distance_to(p) < 60.0): continue
			shot_points.append(p)
			var camera: Dictionary = board.capture_camera()
			camera.target = builder.point(p)
			camera.yaw = board.Rig.HOME_YAW
			camera.pitch = board.Rig.HOME_PITCH
			camera.span = 200.0
			board.restore_camera(camera)
			await _settle(board, 1.2)
			board.restore_camera(camera)
			await _settle(board, 0.6)
			board._viewport.get_texture().get_image().save_png(output.path_join("fault_%02d_%s_%s.png" % [k, fault.tile, fault.label]))
			k += 1
	var sites := _sites(_decks(builder))
	var index := 0
	for site in sites:
		var centre := Vector2.ZERO
		for p in site.points: centre += p
		centre /= site.points.size()
		var entry := {"n": index, "kind": site.kind, "centre": [snappedf(centre.x, 0.1), snappedf(centre.y, 0.1)], "decks": site.decks.size(),
			"tile": str(builder.ground.tile_at(centre)) if builder.ground.has_method("tile_at") else "", "crossings": _crossings(builder, site)}
		for side in (2 if shots and not entry.crossings.is_empty() or shots and "--every-site" in OS.get_cmdline_user_args() else 0):
			var camera: Dictionary = board.capture_camera()
			camera.target = builder.point(centre)
			camera.yaw = board.Rig.HOME_YAW + PI * side
			camera.pitch = float(OS.get_environment("AUDIT_PITCH")) if OS.get_environment("AUDIT_PITCH") != "" else board.Rig.HOME_PITCH
			camera.span = float(OS.get_environment("AUDIT_SPAN")) if OS.get_environment("AUDIT_SPAN") != "" else 260.0
			board.restore_camera(camera)
			await _settle(board, 1.2)
			board.restore_camera(camera)
			await _settle(board, 0.6)
			board._viewport.get_texture().get_image().save_png(output.path_join("bridge_%02d_%s.png" % [index, "front" if side == 0 else "back"]))
		report.sites.append(entry)
		print("[BRIDGE] ", JSON.stringify(entry))
		index += 1
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
