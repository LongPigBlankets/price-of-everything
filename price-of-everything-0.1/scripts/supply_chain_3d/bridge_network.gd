extends RefCounted
## Authored bridge strokes often end at a shared point in the river. Complete
## those spans across connected strokes; never make a half deck to that point.
static func complete(segments: Array, ground: Callable) -> Dictionary:
	var nodes := {}
	for i in segments.size():
		var rec: Dictionary = segments[i]
		for end in ["a", "b"]:
			var key := Vector2i(((rec[end] as Vector2) * 100.0).round())
			var node: Dictionary = nodes.get_or_add(key, {"p": rec[end], "wet": false, "edges": [], "height": -INF})
			node.wet = node.wet or rec.get("wet_" + end, false)
			node.height = maxf(node.height, float(rec["h" + end]))
			node.edges.append(i)
			rec["node_" + end] = key
	var seen := {}
	var crossings: Array = []
	var unresolved: Array = []
	for key in nodes:
		if seen.has(key) or not nodes[key].wet: continue
		var pending: Array = [key]
		var cursor := 0
		var component: Array = []
		var anchors := {}
		var edges := {}
		var incomplete := false
		while cursor < pending.size():
			var current: Vector2i = pending[cursor]; cursor += 1
			if seen.has(current): continue
			seen[current] = true; component.append(current)
			for i in nodes[current].edges:
				var rec: Dictionary = segments[i]
				edges[i] = true
				incomplete = incomplete or not bool(rec.bridge)
				var other: Vector2i = rec.node_b if rec.node_a == current else rec.node_a
				if nodes[other].wet: pending.append(other)
				else: anchors[other] = true
		if not incomplete: continue
		var middle := Vector2.ZERO
		for node in component: middle += nodes[node].p
		middle /= component.size()
		var banks := anchors.keys()
		var opposing := false
		var widest := 0.0
		var pair: Array = []
		for i in banks.size():
			for j in range(i + 1, banks.size()):
				var a: Vector2 = nodes[banks[i]].p
				var b: Vector2 = nodes[banks[j]].p
				if (a - middle).normalized().dot((b - middle).normalized()) >= -0.25: continue
				var distance := a.distance_to(b)
				if distance > widest: widest = distance; pair = [a, b]
				opposing = true
		if not opposing or widest > 400.0:
			unresolved.append({"point": middle, "banks": banks.size(), "samples": component.size()})
			continue
		var deck := -INF
		for i in edges:
			var rec: Dictionary = segments[i]
			var normal: Vector2 = (rec.b - rec.a).normalized().orthogonal() * (float(rec.half) + 9.0)
			for p in [rec.a, rec.b]:
				for off in [Vector2.ZERO, normal, -normal]: deck = maxf(deck, float(ground.call(p + off)) + 5.0)
		for node in component: nodes[node].height = maxf(nodes[node].height, deck)
		for i in edges:
			var rec: Dictionary = segments[i]
			rec.bridge = true
			rec.start = not nodes[rec.node_a].wet
			rec.end = not nodes[rec.node_b].wet
		# Blend dry approaches along the same graph, including branches. Do not
		# smooth across an unconnected road which happens to lie nearby.
		var distances := {}
		pending = []
		for bank in banks: distances[bank] = 0.0; pending.append(bank)
		cursor = 0
		while cursor < pending.size():
			var current: Vector2i = pending[cursor]; cursor += 1
			var node: Dictionary = nodes[current]
			var distance: float = distances[current]
			node.height = maxf(node.height, lerpf(deck, float(ground.call(node.p)), smoothstep(0.0, 42.0, distance)))
			for i in node.edges:
				var rec: Dictionary = segments[i]
				var other: Vector2i = rec.node_b if rec.node_a == current else rec.node_a
				if nodes[other].wet: continue
				var next: float = distance + (nodes[other].p as Vector2).distance_to(node.p)
				if next >= 42.0 or next >= float(distances.get(other, INF)): continue
				distances[other] = next; pending.append(other)
		crossings.append({"source": "joined-strokes", "a": pair[0], "b": pair[1], "height_a": deck, "height_b": deck})
	for rec in segments:
		rec.ha = nodes[rec.node_a].height
		rec.hb = nodes[rec.node_b].height
		rec.erase("node_a"); rec.erase("node_b")
		rec.erase("wet_a"); rec.erase("wet_b")
	return {"crossings": crossings, "unresolved": unresolved}
