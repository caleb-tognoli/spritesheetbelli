class_name MeshMatching
extends RefCounted
## A round of matching a [KeyMesh]'s key to the other key, see [method KeyMesh._match_round]:
## where each of the key's pixels is pulled, and which of its pixels each of the other
## key's edges pulls. Shared by the threads it's worked out on, which only read it.

## How much nearer than worked out a pixel can be, for rounding, see [method edge_pulls]
const CLOSE_ENOUGH := 1.0 - 1e-6
## Pixels matched at once, see [method all_pixel_matches]
const RUN := 64

## The canvas the keys are on, as worked out
var width := 0
var height := 0
var colors: MeshTools.Colors
var located: MeshTools.Located
## Each triangle's turn, and where each pixel landed
var turns := PackedFloat32Array()
var landed := PackedVector2Array()
## The steps to the spots each pixel looks at, nearest first, and the least each can cost
## for being away, give or take where in its pixel a pixel landed
var spot_x := PackedInt32Array()
var spot_y := PackedInt32Array()
var spot_least := PackedFloat64Array()
## How far the spots reach at most, across or down; and for each, its middle from the
## pixel a pixel landed in, and how far on its colours are (four numbers a pixel) on the
## canvas
var spot_reach := 0
var spot_middle := PackedVector2Array()
var spot_step := PackedInt32Array()
## What being a pixel away costs, squared
var near_cost := 0.0
## The landed pixels in square cells this big, which each is in, across and down
var cell := 1.0
var cell_x := PackedInt32Array()
var cell_y := PackedInt32Array()
## The landed pixels by the pixel they landed in, on the canvas grown by
## [member grid_margin] all round, [member grid_width] pixels wide: the last to land in
## each pixel (-1 for none), and for each landed pixel, the one before it in its pixel
var grid_margin := 0
var grid_width := 0
var grid_last := PackedInt32Array()
var grid_before := PackedInt32Array()
## The steps on that grid to the pixels an edge pixel looks in, those that can hold the
## nearest first, and the least a pixel in each can be away, squared
var near_steps := PackedInt32Array()
var near_least := PackedFloat64Array()
## The other key's edge pixels
var edges := PackedInt32Array()


## A round matching [param key_located], [param key_colors] landed at [param key_landed]
## (with its triangles turned by [param key_turns]), each pixel looking up to [param reach]
## pixels round where it landed; [param mesh] is the key's
func _init(
	key_colors: MeshTools.Colors,
	key_located: MeshTools.Located,
	key_turns: PackedFloat32Array,
	key_landed: PackedVector2Array,
	reach: float,
	mesh: KeyMesh
) -> void:
	width = mesh.width
	height = mesh.height
	colors = key_colors
	located = key_located
	turns = key_turns
	landed = key_landed
	# Candidate spots round where a pixel landed, nearest first
	var r := ceili(reach)
	var spots: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= reach * reach + 0.5:
				spots.append(Vector2i(dx, dy))
	spots.sort_custom(
		func(m: Vector2i, n: Vector2i) -> bool: return m.length_squared() < n.length_squared()
	)
	near_cost = KeyMesh.NEARNESS * KeyMesh.LIKENESS / maxf(reach * reach, 1.0)
	spot_reach = r
	for spot in spots:
		spot_x.append(spot.x)
		spot_y.append(spot.y)
		var least := maxf(Vector2(spot).length() - 0.71, 0.0)
		spot_least.append(near_cost * least * least)
		spot_middle.append(Vector2(spot.x + 0.5, spot.y + 0.5))
		spot_step.append((spot.y * width + spot.x) * 4)
	cell = maxf(reach + 1.0, 1.0)
	_place_landed()
	var other_edges := colors.other_edges
	var q := other_edges.find(1)
	while q >= 0:
		edges.append(q)
		q = other_edges.find(1, q + 1)


## Puts the landed pixels in their cells and pixels, see [member cell_x] and
## [member grid_last], and works out [member near_steps]
func _place_landed() -> void:
	var count := landed.size()
	cell_x.resize(count)
	cell_y.resize(count)
	grid_before.resize(count)
	# Room round the canvas for every pixel landing near enough to an edge pixel on it
	grid_margin = ceili(cell) + 2
	grid_width = width + grid_margin * 2
	var grid_height := height + grid_margin * 2
	grid_last.resize(grid_width * grid_height)
	grid_last.fill(-1)
	for s in count:
		var place := landed[s]
		cell_x[s] = floori(place.x / cell)
		cell_y[s] = floori(place.y / cell)
		var x := floori(place.x) + grid_margin
		var y := floori(place.y) + grid_margin
		grid_before[s] = -1
		if x < 0 or y < 0 or x >= grid_width or y >= grid_height:
			continue
		var g := y * grid_width + x
		grid_before[s] = grid_last[g]
		grid_last[g] = s
	# Pixels round an edge pixel's that can hold one near enough (a little more, for
	# rounding), by the least they can be away: from its middle to their nearest side
	var r := ceili(cell) + 1
	var steps: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var least_x := maxf(absi(dx) - 0.5, 0.0)
			var least_y := maxf(absi(dy) - 0.5, 0.0)
			var least := least_x * least_x + least_y * least_y
			if least <= cell * cell + 1.0:
				# In quarters, a whole number
				steps.append(Vector2i(roundi(least * 4.0), dy * grid_width + dx))
	steps.sort_custom(func(m: Vector2i, n: Vector2i) -> bool: return m.x < n.x)
	for step in steps:
		near_least.append(step.x / 4.0)
		near_steps.append(step.y)


## For the key's pixels [param start] to [param end] (past the last), where each is pulled
## and how hard: the spot round where it landed whose pixels, turned as its triangle is,
## are most like its own and those round it, being far counting against it.
## [code][goals, pulls][/code]
func pixel_matches(start: int, end: int) -> Array:
	if NativeKernels.kernels:
		return NativeKernels.pixel_matches(self, start, end)
	var own := colors.own
	var own_edges := colors.own_edges
	var goals := PackedVector2Array()
	goals.resize(end - start)
	var pulls := PackedFloat32Array()
	pulls.resize(end - start)
	var patch := PackedFloat32Array()
	patch.resize(36)
	var ways := PackedInt32Array()
	ways.resize(18)
	var best_found := PackedFloat64Array()
	best_found.resize(2)
	for s in range(start, end):
		var p := located.pixels[s]
		var px := p % width
		var py := p / width
		# The pixel and those round it, as they are in the key
		var k := 0
		for oy in range(-1, 2):
			var qy := py + oy
			for ox in range(-1, 2):
				var qx := px + ox
				if qx < 0 or qy < 0 or qx >= width or qy >= height:
					patch[k] = 0.0
					patch[k + 1] = 0.0
					patch[k + 2] = 0.0
					patch[k + 3] = 0.0
				else:
					var q := (qy * width + qx) * 4
					patch[k] = own[q]
					patch[k + 1] = own[q + 1]
					patch[k + 2] = own[q + 2]
					patch[k + 3] = own[q + 3]
				k += 4
		# Turned as its triangle is, a whole pixel each
		var turn := turns[located.triangles[s]]
		k = 0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var turned := Vector2(ox, oy).rotated(turn)
				ways[k] = floori(turned.x + 0.5)
				ways[k + 1] = floori(turned.y + 0.5)
				k += 2
		var place := landed[s]
		var base_x := floori(place.x)
		var base_y := floori(place.y)
		var reach := spot_reach + 1
		if (
			base_x >= reach
			and base_y >= reach
			and base_x + reach < width
			and base_y + reach < height
		):
			_inside_match(patch, ways, place, best_found)
		else:
			_any_match(patch, ways, place, best_found)
		var best_x := base_x + spot_x[int(best_found[0])]
		var best_y := base_y + spot_y[int(best_found[0])]
		var best_cost := best_found[1]
		goals[s - start] = Vector2(best_x, best_y) + Vector2(0.5, 0.5)
		var pull := 1.0 if own_edges[p] == 1 else KeyMesh.FLAT_PULL
		pulls[s - start] = pull * exp(-best_cost / KeyMesh.LIKENESS)
	return [goals, pulls]


## [method pixel_matches] for all the key's pixels, written into [param goals] and
## [param pulls] (sized to fit): shared out among threads (at least [param least] pixels
## each), each taking runs of [constant RUN] pixels spread through them all, so each gets
## as much of the hard parts
func all_pixel_matches(goals: PackedVector2Array, pulls: PackedFloat32Array, least: int) -> void:
	if NativeKernels.kernels:
		NativeKernels.all_pixel_matches(self, goals, pulls, least)
		return
	var count := goals.size()
	var most := ceili(float(count) / maxi(least, 1))
	var threads := clampi(mini(OS.get_processor_count() / 2, most), 1, 16)
	Parallel.split(threads, 1, _pixel_matches_spread.bind(threads, goals, pulls))


## [method all_pixel_matches] for threads [param start] to [param end] (past the last) of
## [param threads]
func _pixel_matches_spread(
	start: int, end: int, threads: int, goals: PackedVector2Array, pulls: PackedFloat32Array
) -> void:
	var count := goals.size()
	for thread in range(start, end):
		var from := thread * RUN
		while from < count:
			var to := mini(from + RUN, count)
			var part := pixel_matches(from, to)
			var part_goals: PackedVector2Array = part[0]
			var part_pulls: PackedFloat32Array = part[1]
			for k in to - from:
				goals[from + k] = part_goals[k]
				pulls[from + k] = part_pulls[k]
			from += threads * RUN


## For a pixel that landed at [param place], its colours and those round it
## [param patch] (see [method pixel_matches]) looked for turned by whole pixels
## [param ways]: writes into [param found] the spot that matches best and how unlike it is
func _any_match(
	patch: PackedFloat32Array, ways: PackedInt32Array, place: Vector2, found: PackedFloat64Array
) -> void:
	var others := colors.other
	var base_x := floori(place.x)
	var base_y := floori(place.y)
	var best := INF
	var best_cost := 0.0
	var best_n := 0
	for n in spot_least.size():
		if spot_least[n] >= best:
			break
		var cx := base_x + spot_x[n]
		var cy := base_y + spot_y[n]
		var apart := Vector2(cx + 0.5, cy + 0.5) - place
		var prior := near_cost * apart.length_squared()
		if prior >= best:
			continue
		var cost := 0.0
		var limit := (best - prior) * 9.0
		for j in 9:
			var qx := cx + ways[j * 2]
			var qy := cy + ways[j * 2 + 1]
			var i := j * 4
			if qx < 0 or qy < 0 or qx >= width or qy >= height:
				cost += absf(patch[i])
				cost += absf(patch[i + 1])
				cost += absf(patch[i + 2])
				cost += absf(patch[i + 3])
			else:
				var q := (qy * width + qx) * 4
				cost += absf(others[q] - patch[i])
				cost += absf(others[q + 1] - patch[i + 1])
				cost += absf(others[q + 2] - patch[i + 2])
				cost += absf(others[q + 3] - patch[i + 3])
			if cost >= limit:
				break
		if cost >= limit:
			continue
		cost /= 9.0
		if cost + prior < best:
			best = cost + prior
			best_cost = cost
			best_n = n
	found[0] = best_n
	found[1] = best_cost


## [method _any_match] for a pixel looking only at spots whose pixels and those round them
## are all on the canvas, the same but quicker
func _inside_match(
	patch: PackedFloat32Array, ways: PackedInt32Array, place: Vector2, found: PackedFloat64Array
) -> void:
	var others := colors.other
	var base_x := floori(place.x)
	var base_y := floori(place.y)
	# Exact, as the spots are well inside the canvas, so moving it by a spot gives what
	# the spot less where the pixel landed would
	var off := Vector2(base_x, base_y) - place
	var center := (base_y * width + base_x) * 4
	var o0 := (ways[1] * width + ways[0]) * 4
	var o1 := (ways[3] * width + ways[2]) * 4
	var o2 := (ways[5] * width + ways[4]) * 4
	var o3 := (ways[7] * width + ways[6]) * 4
	var o4 := (ways[9] * width + ways[8]) * 4
	var o5 := (ways[11] * width + ways[10]) * 4
	var o6 := (ways[13] * width + ways[12]) * 4
	var o7 := (ways[15] * width + ways[14]) * 4
	var o8 := (ways[17] * width + ways[16]) * 4
	var a0 := patch[0]
	var a1 := patch[1]
	var a2 := patch[2]
	var a3 := patch[3]
	var a4 := patch[4]
	var a5 := patch[5]
	var a6 := patch[6]
	var a7 := patch[7]
	var a8 := patch[8]
	var a9 := patch[9]
	var a10 := patch[10]
	var a11 := patch[11]
	var a12 := patch[12]
	var a13 := patch[13]
	var a14 := patch[14]
	var a15 := patch[15]
	var a16 := patch[16]
	var a17 := patch[17]
	var a18 := patch[18]
	var a19 := patch[19]
	var a20 := patch[20]
	var a21 := patch[21]
	var a22 := patch[22]
	var a23 := patch[23]
	var a24 := patch[24]
	var a25 := patch[25]
	var a26 := patch[26]
	var a27 := patch[27]
	var a28 := patch[28]
	var a29 := patch[29]
	var a30 := patch[30]
	var a31 := patch[31]
	var a32 := patch[32]
	var a33 := patch[33]
	var a34 := patch[34]
	var a35 := patch[35]
	var best := INF
	var best_cost := 0.0
	var best_n := 0
	for n in spot_least.size():
		if spot_least[n] >= best:
			break
		var prior := near_cost * (off + spot_middle[n]).length_squared()
		if prior >= best:
			continue
		var limit := (best - prior) * 9.0
		var c := center + spot_step[n]
		var q := c + o0
		var cost := (
			absf(others[q] - a0)
			+ absf(others[q + 1] - a1)
			+ absf(others[q + 2] - a2)
			+ absf(others[q + 3] - a3)
		)
		if cost >= limit:
			continue
		q = c + o1
		cost = (
			cost
			+ absf(others[q] - a4)
			+ absf(others[q + 1] - a5)
			+ absf(others[q + 2] - a6)
			+ absf(others[q + 3] - a7)
		)
		if cost >= limit:
			continue
		q = c + o2
		cost = (
			cost
			+ absf(others[q] - a8)
			+ absf(others[q + 1] - a9)
			+ absf(others[q + 2] - a10)
			+ absf(others[q + 3] - a11)
		)
		if cost >= limit:
			continue
		q = c + o3
		cost = (
			cost
			+ absf(others[q] - a12)
			+ absf(others[q + 1] - a13)
			+ absf(others[q + 2] - a14)
			+ absf(others[q + 3] - a15)
		)
		if cost >= limit:
			continue
		q = c + o4
		cost = (
			cost
			+ absf(others[q] - a16)
			+ absf(others[q + 1] - a17)
			+ absf(others[q + 2] - a18)
			+ absf(others[q + 3] - a19)
		)
		if cost >= limit:
			continue
		q = c + o5
		cost = (
			cost
			+ absf(others[q] - a20)
			+ absf(others[q + 1] - a21)
			+ absf(others[q + 2] - a22)
			+ absf(others[q + 3] - a23)
		)
		if cost >= limit:
			continue
		q = c + o6
		cost = (
			cost
			+ absf(others[q] - a24)
			+ absf(others[q + 1] - a25)
			+ absf(others[q + 2] - a26)
			+ absf(others[q + 3] - a27)
		)
		if cost >= limit:
			continue
		q = c + o7
		cost = (
			cost
			+ absf(others[q] - a28)
			+ absf(others[q + 1] - a29)
			+ absf(others[q + 2] - a30)
			+ absf(others[q + 3] - a31)
		)
		if cost >= limit:
			continue
		q = c + o8
		cost = (
			cost
			+ absf(others[q] - a32)
			+ absf(others[q + 1] - a33)
			+ absf(others[q + 2] - a34)
			+ absf(others[q + 3] - a35)
		)
		if cost >= limit:
			continue
		cost /= 9.0
		if cost + prior < best:
			best = cost + prior
			best_cost = cost
			best_n = n
	found[0] = best_n
	found[1] = best_cost


## For the other key's edge pixels [param start] to [param end] (past the last), the landed
## pixel each pulls, nearest and most like it, where to and how hard, for those with one:
## [code][samples, goals, pulls][/code]
func edge_pulls(start: int, end: int) -> Array:
	if NativeKernels.kernels:
		return NativeKernels.edge_pulls(self, start, end)
	var pixels := located.pixels
	var own := colors.own
	var others := colors.other
	var samples := PackedInt32Array()
	var goals := PackedVector2Array()
	var pulls := PackedFloat32Array()
	var before := grid_before
	var last := grid_last
	var near := cell * cell
	var count := landed.size()
	for e in range(start, end):
		var q := edges[e]
		var qx := q % width
		var qy := q / width
		var spot := Vector2(qx + 0.5, qy + 0.5)
		var home_x := floori(spot.x / cell)
		var home_y := floori(spot.y / cell)
		var middle := (qy + grid_margin) * grid_width + qx + grid_margin
		var best := INF
		var best_cost := 0.0
		var best_sample := -1
		var best_order := 0
		var i := q * 4
		# Nearest first, until none left can be the best however alike; of those as good,
		# the first in the cells round its cell, row by row, then by pixel
		for n in near_steps.size():
			if near_cost * near_least[n] * CLOSE_ENOUGH > best:
				break
			var s := last[middle + near_steps[n]]
			while s >= 0:
				var sample := s
				s = before[s]
				var apart := landed[sample].distance_squared_to(spot)
				if apart > near:
					continue
				var off_x := cell_x[sample] - home_x
				var off_y := cell_y[sample] - home_y
				if off_x < -1 or off_x > 1 or off_y < -1 or off_y > 1:
					continue
				var prior := near_cost * apart
				if prior > best:
					continue
				var o := pixels[sample] * 4
				var cost := 0.0
				cost += absf(own[o] - others[i])
				cost += absf(own[o + 1] - others[i + 1])
				cost += absf(own[o + 2] - others[i + 2])
				cost += absf(own[o + 3] - others[i + 3])
				var total := cost + prior
				var order := ((off_y + 1) * 3 + off_x + 1) * count + sample
				if total < best or (total == best and order < best_order):
					best = total
					best_cost = cost
					best_sample = sample
					best_order = order
		if best_sample >= 0:
			samples.append(best_sample)
			goals.append(spot)
			pulls.append(KeyMesh.EDGE_PULL * exp(-best_cost / KeyMesh.LIKENESS))
	return [samples, goals, pulls]
