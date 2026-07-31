extends RefCounted
## Crossing-minimal LANE ORDERING within a routing channel. Extracted from the goods graph
## (owner 2026-07-22b) so the empire view can use the same solver rather than a second,
## weaker one — both charts route orthogonal edges through vertical channels between columns,
## and the ordering problem in a channel is identical.
##
## A LEG is `[id, leg_index, ys, ye, dir]` and describes a Z: an entry stub at `ys` arriving
## from its source side (left when `dir == 1`, right when `dir == -1`), a vertical between
## `ys` and `ye` at the lane's x, and an exit run at `ye` leaving to its destination side.
## Both horizontals reach past every other lane in the channel, so two legs cross exactly when
## one leg's horizontal y falls strictly inside the other's vertical span on the side that
## horizontal actually covers.
##
## Because the cost of a pair depends ONLY on which of the two sits left, total cost is
## order-decomposable and subset DP gives the exact optimum. Past 12 legs (not seen in
## practice) it falls back to a deterministic pairwise-improvement pass to stay O(n^2).
##
## Consumers preload this as `const LaneOrder := preload("res://scripts/lane_order.gd")`.


## Crossings between two legs when `a` takes the lane LEFT of `b`.
static func leg_cross(a: Array, b: Array) -> int:
	var n := 0
	# b's horizontal on the LEFT side (entry when travelling right, exit when travelling
	# left) sweeps across a's vertical.
	if between(float(b[2]) if int(b[4]) == 1 else float(b[3]), a):
		n += 1
	# a's horizontal on the RIGHT side sweeps across b's vertical.
	if between(float(a[3]) if int(a[4]) == 1 else float(a[2]), b):
		n += 1
	return n


static func between(y: float, leg: Array) -> bool:
	var lo := minf(float(leg[2]), float(leg[3]))
	var hi := maxf(float(leg[2]), float(leg[3]))
	return y > lo + 0.5 and y < hi - 0.5


## Left-to-right lane order for one channel, minimising total pairwise crossings.
static func solve(reqs: Array) -> Array:
	var n := reqs.size()
	if n <= 1:
		return reqs.duplicate()
	var base := reqs.duplicate()
	base.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[3]) < float(b[3]) \
			or (float(a[3]) == float(b[3]) and int(a[0]) < int(b[0])))
	var w: Array = []   # w[i][j] = crossings if base[i] sits left of base[j]
	for i: int in range(n):
		var row := PackedInt32Array()
		row.resize(n)
		for j: int in range(n):
			if i != j:
				row[j] = leg_cross(base[i] as Array, base[j] as Array)
		w.append(row)
	var order: Array = []
	if n <= 12:
		var full := (1 << n) - 1
		var dp := PackedInt32Array()
		var par := PackedInt32Array()
		dp.resize(full + 1)
		par.resize(full + 1)
		for m: int in range(1, full + 1):
			dp[m] = 1 << 24
		for m: int in range(full):
			if int(dp[m]) >= (1 << 24):
				continue
			for k: int in range(n):
				if m & (1 << k):
					continue
				var cost := int(dp[m])
				for i: int in range(n):
					if m & (1 << i):
						cost += int((w[i] as PackedInt32Array)[k])
				var nm := m | (1 << k)
				if cost < int(dp[nm]):
					dp[nm] = cost
					par[nm] = k
		var m2 := full
		while m2 != 0:
			var k2 := int(par[m2])
			order.push_front(k2)
			m2 &= ~(1 << k2)
	else:
		for i: int in range(n):
			order.append(i)
		var improved := true
		var passes := 0
		while improved and passes < n:
			improved = false
			passes += 1
			for i: int in range(n - 1):
				var a := int(order[i])
				var b := int(order[i + 1])
				if int((w[b] as PackedInt32Array)[a]) < int((w[a] as PackedInt32Array)[b]):
					order[i] = b
					order[i + 1] = a
					improved = true
	var out: Array = []
	for idx in order:
		out.append(base[int(idx)])
	return out
