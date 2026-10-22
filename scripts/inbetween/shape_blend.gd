class_name ShapeBlend
extends RefCounted
## One key's shape bent into the other's, as rigidly as possible, for in-betweens where
## things bend rather than turn, like cloth and legs: as-rigid-as-possible shape
## interpolation (Alexa, Cohen-Or and Levin, 2000).
##
## Each key's outline (its biggest part, holes filled) is traced, smoothed and spaced
## evenly; the two are matched point to point (dynamic time warping round the outline,
## points alike in where they are once the whole sprite's move is taken off, in the colour
## just inside, and in direction); key A's shape is cut into triangles (its outline points
## and a grid inside); the triangles are laid onto key B as rigidly as possible with the
## outline on the points it matched (Sorkine and Alexa, 2007). In-betweens turn and stretch
## each triangle part of the way and put them back together as well as they fit.

## How far apart outline points are, in pixels, and at most how many there are
const SPACING := 1.5
const MOST_POINTS := 220
## How much outlines are smoothed (in outline points) before they're spaced
const SMOOTHING := 1.0
## Matching outline points: how much being apart (a share of the sprite's size), colour
## (red, green and blue summed, 0 to 3) and direction (0 to 1) count, what skipping a
## point costs, and how many starting pairs are tried
const POSITION_WEIGHT := 1.0
const COLOR_WEIGHT := 0.6
const DIRECTION_WEIGHT := 0.25
const STEP_COST := 0.02
const STARTS := 32
## Matched points are smoothed over this many on each side
const MATCH_SMOOTHING := 2
## How far inside the outline its colour is taken
const INSIDE := 1.5
## Points inside the shape, this many outline spacings apart
const GRID := 1.6
## Gaps in the triangles up to this many pixels across are filled, see [method sources]
const GAP := 2
## Rounds of laying the triangles onto key B
const FITTING := 30
## Solving for the triangles' corners: at most this many steps, until this close
const SOLVER_STEPS := 300
const SOLVER_CLOSE := 1e-4

## The canvas both keys are on
var width := 0
var height := 0
## The triangles' corners, where they are in key A and in key B
var rest := PackedVector2Array()
var target := PackedVector2Array()
## Three corners each
var triangles := PackedInt32Array()
## Each triangle's turn from A to B, and its stretch (the 2 × 2 matrix, by rows)
var _turns := PackedFloat32Array()
var _stretches := PackedFloat32Array()
## Corners joined by triangle sides, each side once per triangle
var _edges := PackedInt32Array()


## The blend of [param a_data] into [param b_data], keys on a canvas [param canvas_width]
## × [param canvas_height] pixels, the whole sprite moving by [param shift], about
## [param size] pixels big; null when either key shows nothing
static func between(
	a_data: PackedByteArray,
	b_data: PackedByteArray,
	canvas_width: int,
	canvas_height: int,
	shift: Vector2,
	size: float
) -> ShapeBlend:
	# Both shapes at once
	var datas: Array[PackedByteArray] = [a_data, b_data]
	var shaped := func(k: int) -> PackedByteArray:
		return shape_of(datas[k], canvas_width, canvas_height)
	var masks := Parallel.each(2, shaped)
	var a_mask: PackedByteArray = masks[0]
	var b_mask: PackedByteArray = masks[1]
	if not a_mask.has(1) or not b_mask.has(1):
		return null
	var blend := ShapeBlend.new()
	blend.width = canvas_width
	blend.height = canvas_height
	var a_points := outline_of(a_mask, canvas_width, canvas_height, 0)
	var b_points := outline_of(b_mask, canvas_width, canvas_height, a_points.size())
	if a_points.size() < 8 or b_points.size() < 8:
		return null
	var matched := _matched(
		a_points,
		b_points,
		_inside_colors(a_data, a_points, canvas_width, canvas_height),
		_inside_colors(b_data, b_points, canvas_width, canvas_height),
		shift,
		maxf(size, 1.0)
	)
	blend._mesh(a_mask, a_points)
	if blend.triangles.is_empty():
		return null
	blend._fit(a_points.size(), matched, shift)
	blend._find_turns()
	return blend


## 1 for the pixels of [param data]'s biggest part (pixels at least half opaque, touching
## side by side), holes filled; 0 for the others
static func shape_of(
	data: PackedByteArray, canvas_width: int, canvas_height: int
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(canvas_width * canvas_height)
	# Worked out round the pixels shown and a pixel more: all past them is outside the shape
	var area := PixelCanvas.shown_rect(data, canvas_width, canvas_height, 1)
	if not area.has_area():
		return result
	var w := area.size.x
	var shape := _shape_in(PixelCanvas.region(data, canvas_width, area), w, area.size.y)
	for y in area.size.y:
		var row := (y + area.position.y) * canvas_width + area.position.x
		for x in w:
			result[row + x] = shape[y * w + x]
	return result


## [method shape_of] worked out on the whole of a canvas [param canvas_width] ×
## [param canvas_height] pixels
static func _shape_in(
	data: PackedByteArray, canvas_width: int, canvas_height: int
) -> PackedByteArray:
	var size := canvas_width * canvas_height
	var labels := PackedInt32Array()
	labels.resize(size)
	labels.fill(-1)
	var sides := PixelParts.sides_of(canvas_width)
	var biggest := -1
	var biggest_size := 0
	var count := 0
	for start in size:
		if labels[start] >= 0 or data[start * 4 + 3] < 128:
			continue
		var part := PackedInt32Array([start])
		labels[start] = count
		var next := 0
		while next < part.size():
			var p := part[next]
			next += 1
			for side in sides:
				var q: int = p + side
				if q < 0 or q >= size or labels[q] >= 0 or data[q * 4 + 3] < 128:
					continue
				if absi(q % canvas_width - p % canvas_width) > 1:
					continue
				labels[q] = count
				part.append(q)
		if part.size() > biggest_size:
			biggest_size = part.size()
			biggest = count
		count += 1
	# Holes: what the outside can't reach
	var outside := PackedByteArray()
	outside.resize(size)
	var queue := PackedInt32Array()
	for x in canvas_width:
		for y: int in [0, canvas_height - 1]:
			queue.append(y * canvas_width + x)
	for y in canvas_height:
		for x: int in [0, canvas_width - 1]:
			queue.append(y * canvas_width + x)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if outside[p] == 1 or labels[p] == biggest:
			continue
		outside[p] = 1
		var x := p % canvas_width
		if x > 0:
			queue.append(p - 1)
		if x < canvas_width - 1:
			queue.append(p + 1)
		if p >= canvas_width:
			queue.append(p - canvas_width)
		if p + canvas_width < size:
			queue.append(p + canvas_width)
	var result := PackedByteArray()
	result.resize(size)
	if biggest < 0:
		return result
	for p in size:
		result[p] = 1 - outside[p]
	return result


## The outline of [param shape] (see [method shape_of]), clockwise on screen, smoothed and
## spaced evenly: [param count] points, or as many as its length needs when 0, about
## [param spacing] pixels apart
static func outline_of(
	shape: PackedByteArray,
	canvas_width: int,
	canvas_height: int,
	count: int,
	spacing := SPACING
) -> PackedVector2Array:
	var corners := _traced(shape, canvas_width, canvas_height)
	var n := corners.size()
	if n < 4:
		return PackedVector2Array()
	# Smoothed, the stairs of pixel corners rounded off
	var reach := ceili(SMOOTHING * 3.0)
	var weights := PackedFloat32Array()
	var total := 0.0
	for k in range(-reach, reach + 1):
		var weight := exp(-0.5 * k * k / (SMOOTHING * SMOOTHING))
		weights.append(weight)
		total += weight
	var smooth := PackedVector2Array()
	smooth.resize(n)
	for i in n:
		var sum := Vector2.ZERO
		for k in range(-reach, reach + 1):
			sum += Vector2(corners[posmod(i + k, n)]) * weights[k + reach]
		smooth[i] = sum / total
	# Spaced evenly along it
	var lengths := PackedFloat32Array([0.0])
	for i in n:
		lengths.append(lengths[i] + smooth[i].distance_to(smooth[(i + 1) % n]))
	var length := lengths[n]
	if count <= 0:
		count = clampi(int(length / spacing), 24, MOST_POINTS)
	var result := PackedVector2Array()
	var k := 0
	for i in count:
		var along := length * i / count
		while k < n - 1 and lengths[k + 1] <= along:
			k += 1
		var part := lengths[k + 1] - lengths[k]
		var f := (along - lengths[k]) / part if part > 0.0 else 0.0
		result.append(smooth[k].lerp(smooth[(k + 1) % n], f))
	return result


## The corners round [param shape]'s outside, in order, clockwise on screen: the longest
## loop of the sides between its pixels and others
static func _traced(
	shape: PackedByteArray, canvas_width: int, canvas_height: int
) -> Array[Vector2i]:
	var ways := {}
	for y in canvas_height:
		for x in canvas_width:
			if shape[y * canvas_width + x] == 0:
				continue
			if y == 0 or shape[(y - 1) * canvas_width + x] == 0:
				_add_way(ways, Vector2i(x, y), Vector2i(x + 1, y))
			if x == canvas_width - 1 or shape[y * canvas_width + x + 1] == 0:
				_add_way(ways, Vector2i(x + 1, y), Vector2i(x + 1, y + 1))
			if y == canvas_height - 1 or shape[(y + 1) * canvas_width + x] == 0:
				_add_way(ways, Vector2i(x + 1, y + 1), Vector2i(x, y + 1))
			if x == 0 or shape[y * canvas_width + x - 1] == 0:
				_add_way(ways, Vector2i(x, y + 1), Vector2i(x, y))
	var longest: Array[Vector2i] = []
	while not ways.is_empty():
		var start: Vector2i = ways.keys()[0]
		var loop: Array[Vector2i] = [start]
		var place := start
		var heading := Vector2i.ZERO
		while true:
			var outs: Array = ways.get(place, [])
			if outs.is_empty():
				break
			var pick := 0
			if outs.size() > 1 and heading != Vector2i.ZERO:
				# Turning right first, so pixels touching only by corners stay apart
				var best := INF
				for k in outs.size():
					var way: Vector2i = outs[k] - place
					var turn := float(heading.y * way.x - heading.x * way.y)
					if turn < best:
						best = turn
						pick = k
			var next: Vector2i = outs[pick]
			outs.remove_at(pick)
			if outs.is_empty():
				ways.erase(place)
			heading = next - place
			place = next
			if place == start:
				break
			loop.append(place)
		if loop.size() > longest.size():
			longest = loop
	return longest


static func _add_way(ways: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if not ways.has(from):
		ways[from] = []
	(ways[from] as Array).append(to)


## The colour (premultiplied, 0 to 1) just inside the outline at each of [param points]
static func _inside_colors(
	data: PackedByteArray, points: PackedVector2Array, canvas_width: int, canvas_height: int
) -> PackedVector3Array:
	var n := points.size()
	var result := PackedVector3Array()
	for i in n:
		var along := points[(i + 1) % n] - points[posmod(i - 1, n)]
		var inward := Vector2(-along.y, along.x).normalized()
		var place := points[i] + inward * INSIDE
		var x := clampi(floori(place.x), 0, canvas_width - 1)
		var y := clampi(floori(place.y), 0, canvas_height - 1)
		var q := (y * canvas_width + x) * 4
		var alpha := data[q + 3] / 255.0
		result.append(Vector3(data[q], data[q + 1], data[q + 2]) / 255.0 * alpha)
	return result


## The direction of the outline at each of [param points]
static func _directions(points: PackedVector2Array) -> PackedFloat32Array:
	var n := points.size()
	var result := PackedFloat32Array()
	for i in n:
		result.append((points[(i + 2) % n] - points[posmod(i - 2, n)]).angle())
	return result


## Where on outline [param b] each point of outline [param a] goes: dynamic time warping
## round the outlines, from the best of a few starting pairs
static func _matched(
	a: PackedVector2Array,
	b: PackedVector2Array,
	a_colors: PackedVector3Array,
	b_colors: PackedVector3Array,
	shift: Vector2,
	size: float
) -> PackedVector2Array:
	var n := a.size()
	var m := b.size()
	var a_ways := _directions(a)
	var b_ways := _directions(b)
	var costs := PackedFloat32Array()
	costs.resize(n * m)
	for i in n:
		for j in m:
			var apart := a_colors[i] - b_colors[j]
			costs[i * m + j] = (
				POSITION_WEIGHT * (a[i] + shift).distance_to(b[j]) / size
				+ COLOR_WEIGHT * (absf(apart.x) + absf(apart.y) + absf(apart.z))
				+ DIRECTION_WEIGHT * (1.0 - cos(a_ways[i] - b_ways[j])) / 2.0
			)
	# Starting pairs: the points of B the first of A is most like, and some spread round
	var order := range(m)
	order.sort_custom(func(x: int, y: int) -> bool: return costs[x] < costs[y])
	var starts := {}
	for k in mini(STARTS / 2, m):
		starts[order[k]] = true
	for k in STARTS / 2:
		starts[k * m / (STARTS / 2)] = true
	var best_start := 0
	var best_cost := INF
	# Each start tried on its own, so they're shared out among threads
	var tried := PackedInt32Array(starts.keys())
	var warps := []
	var warping := _warps.bind(tried, costs, n, m)
	for part: PackedFloat64Array in Parallel.split(tried.size(), 1, warping):
		warps.append_array(part)
	for k in tried.size():
		var cost: float = warps[k]
		if cost < best_cost:
			best_cost = cost
			best_start = tried[k]
	var moves := PackedByteArray()
	moves.resize(n * m)
	_warp(costs, n, m, best_start, moves)
	# Back along the best path: each point of A, the middle of what it was paired with
	var sums := PackedFloat32Array()
	sums.resize(n)
	var counts := PackedInt32Array()
	counts.resize(n)
	var i := n - 1
	var j := m - 1
	while true:
		sums[i] += j
		counts[i] += 1
		if i == 0 and j == 0:
			break
		match moves[i * m + j]:
			0:
				i -= 1
				j -= 1
			1:
				i -= 1
			_:
				j -= 1
	# Smoothed along the outline, as pairing point by point jitters
	var alongs := PackedFloat32Array()
	for k in n:
		alongs.append(sums[k] / counts[k])
	for k in range(1, n):
		alongs[k] = maxf(alongs[k], alongs[k - 1])
	var smoothed := PackedFloat32Array()
	for k in n:
		var sum := 0.0
		var weight := 0.0
		for d in range(-MATCH_SMOOTHING, MATCH_SMOOTHING + 1):
			var place := k + d
			# Past the ends, round the outline
			var value := 0.0
			if place < 0:
				value = alongs[place + n] - m
			elif place >= n:
				value = alongs[place - n] + m
			else:
				value = alongs[place]
			sum += value
			weight += 1.0
		smoothed.append(sum / weight)
	var result := PackedVector2Array()
	for k in n:
		var along := smoothed[k] + best_start
		var low := floori(along)
		result.append(b[posmod(low, m)].lerp(b[posmod(low + 1, m)], along - low))
	return result


## [method _warp] from each of the starts [param tried] [param first] to [param end] (past
## the last)
static func _warps(
	first: int, end: int, tried: PackedInt32Array, costs: PackedFloat32Array, n: int, m: int
) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	for k in range(first, end):
		found.append(_warp(costs, n, m, tried[k], PackedByteArray()))
	return found


## The cost of warping outline A onto outline B starting at B's point [param start] (see
## [method _matched]), writing each step's move into [param moves] unless it's empty: 0
## both on, 1 A on, 2 B on
static func _warp(
	costs: PackedFloat32Array, n: int, m: int, start: int, moves: PackedByteArray
) -> float:
	if NativeKernels.kernels:
		return NativeKernels.warp(costs, n, m, start, moves)
	var writing := not moves.is_empty()
	var above := PackedFloat32Array()
	above.resize(m)
	var row := PackedFloat32Array()
	row.resize(m)
	for i in n:
		for j in m:
			var here := costs[i * m + (j + start) % m]
			if i == 0 and j == 0:
				row[0] = here
				continue
			var best := INF
			var move := 0
			if i > 0 and j > 0:
				best = above[j - 1]
			if i > 0 and above[j] + STEP_COST < best:
				best = above[j] + STEP_COST
				move = 1
			if j > 0 and row[j - 1] + STEP_COST < best:
				best = row[j - 1] + STEP_COST
				move = 2
			row[j] = best + here
			if writing:
				moves[i * m + j] = move
		var swap := above
		above = row
		row = swap
	return above[m - 1]


## Cuts [param shape] into triangles: corners on [param outline] and on a grid inside
func _mesh(shape: PackedByteArray, outline: PackedVector2Array) -> void:
	var spacing := GRID * SPACING
	var points := outline.duplicate()
	var y := spacing / 2.0
	while y < height:
		var x := spacing / 2.0
		while x < width:
			var place := Vector2(x, y)
			if shape[int(y) * width + int(x)] == 1:
				var clear := true
				for o in outline:
					if o.distance_squared_to(place) < spacing * spacing * 0.36:
						clear = false
						break
				if clear:
					points.append(place)
			x += spacing
		y += spacing
	var found := Geometry2D.triangulate_delaunay(points)
	# Only triangles over the shape (a pixel round it counting)
	var grown := shape.duplicate()
	var sides := PixelParts.sides_of(width)
	for p in shape.size():
		if shape[p] == 0:
			continue
		for side in sides:
			var q: int = p + side
			if q >= 0 and q < grown.size():
				grown[q] = 1
	for k in range(0, found.size(), 3):
		var c0 := points[found[k]]
		var c1 := points[found[k + 1]]
		var c2 := points[found[k + 2]]
		var area := (c1 - c0).cross(c2 - c0)
		if absf(area) < 1e-4:
			continue
		var inside := true
		for probe: Vector2 in [
			(c0 + c1 + c2) / 3.0, (c0 + c1) / 2.0, (c1 + c2) / 2.0, (c2 + c0) / 2.0
		]:
			var px := clampi(floori(probe.x), 0, width - 1)
			var py := clampi(floori(probe.y), 0, height - 1)
			if grown[py * width + px] == 0:
				inside = false
				break
		if inside:
			triangles.append_array([found[k], found[k + 1], found[k + 2]])
	rest = points
	for k in range(0, triangles.size(), 3):
		for e in 3:
			_edges.append_array([triangles[k + e], triangles[k + (e + 1) % 3]])


## Lays the triangles onto key B: the first [param pinned] corners (the outline) on
## [param matched], the others as rigidly as possible
func _fit(pinned: int, matched: PackedVector2Array, shift: Vector2) -> void:
	var n := rest.size()
	var fixed := PackedByteArray()
	fixed.resize(n)
	target.resize(n)
	for i in pinned:
		fixed[i] = 1
		target[i] = matched[i]
	# Corners in no triangle stay with the whole sprite
	var used := PackedByteArray()
	used.resize(n)
	for corner in triangles:
		used[corner] = 1
	for i in range(pinned, n):
		target[i] = rest[i] + shift
		if used[i] == 0:
			fixed[i] = 1
	# Smoothly in between first, then as rigidly as possible
	var zeros := PackedVector2Array()
	zeros.resize(n)
	_solve(target, zeros, fixed)
	_relax(fixed)


## Rounds of laying the triangles as rigidly as possible, the [param fixed] corners held
func _relax(fixed: PackedByteArray) -> void:
	for _round in FITTING:
		var turns := PackedFloat32Array()
		for k in range(0, triangles.size(), 3):
			turns.append(_best_turn(k, target))
		_solve(target, _pulls(turns, PackedFloat32Array()), fixed)


## The turn best taking triangle [param k] (its first corner's index in [member triangles])
## from where it rests to [param positions]
func _best_turn(k: int, positions: PackedVector2Array) -> float:
	var r0 := rest[triangles[k]]
	var r1 := rest[triangles[k + 1]]
	var r2 := rest[triangles[k + 2]]
	var q0 := positions[triangles[k]]
	var q1 := positions[triangles[k + 1]]
	var q2 := positions[triangles[k + 2]]
	var rm := (r0 + r1 + r2) / 3.0
	var qm := (q0 + q1 + q2) / 3.0
	var dot := (r0 - rm).dot(q0 - qm) + (r1 - rm).dot(q1 - qm) + (r2 - rm).dot(q2 - qm)
	var cross := (r0 - rm).cross(q0 - qm) + (r1 - rm).cross(q1 - qm) + (r2 - rm).cross(q2 - qm)
	return atan2(cross, dot)


## What each corner is pulled by when each triangle side wants to be its rest turned by
## its triangle's turn in [param turns], and stretched by [param stretches] (4 per
## triangle, by rows; none when empty)
func _pulls(turns: PackedFloat32Array, stretches: PackedFloat32Array) -> PackedVector2Array:
	var pulls := PackedVector2Array()
	pulls.resize(rest.size())
	for e in range(0, _edges.size(), 2):
		var from := _edges[e]
		var to := _edges[e + 1]
		var k := e / 6
		var side := rest[to] - rest[from]
		if not stretches.is_empty():
			var s := k * 4
			side = Vector2(
				stretches[s] * side.x + stretches[s + 1] * side.y,
				stretches[s + 2] * side.x + stretches[s + 3] * side.y
			)
		side = side.rotated(turns[k])
		pulls[to] += side
		pulls[from] -= side
	return pulls


## Solves for [param positions] (where [param fixed] is 0, starting from what's there):
## each corner the average of its neighbours plus its [param pulls], by conjugate
## gradients
func _solve(
	positions: PackedVector2Array, pulls: PackedVector2Array, fixed: PackedByteArray
) -> void:
	var n := positions.size()
	var residual := pulls.duplicate()
	var applied := _laplacian(positions)
	for i in n:
		residual[i] = Vector2.ZERO if fixed[i] else residual[i] - applied[i]
	var direction := residual.duplicate()
	var before := _dot(residual, residual)
	var scale := _dot(pulls, pulls) + 1.0
	for _step in SOLVER_STEPS:
		if before <= SOLVER_CLOSE * SOLVER_CLOSE * scale:
			break
		var pushed := _laplacian(direction)
		for i in n:
			if fixed[i]:
				pushed[i] = Vector2.ZERO
		var along := _dot(direction, pushed)
		if along <= 0.0:
			break
		var step := before / along
		for i in n:
			positions[i] += direction[i] * step
			residual[i] -= pushed[i] * step
		var after := _dot(residual, residual)
		for i in n:
			direction[i] = residual[i] + direction[i] * (after / before)
		before = after


## The graph Laplacian of the triangle sides applied to [param values]
func _laplacian(values: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(values.size())
	for e in range(0, _edges.size(), 2):
		var from := _edges[e]
		var to := _edges[e + 1]
		var apart := values[to] - values[from]
		result[to] += apart
		result[from] -= apart
	return result


## The x and y parts of [param a] and [param b] multiplied and summed
static func _dot(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var sum := 0.0
	for i in a.size():
		sum += a[i].dot(b[i])
	return sum


## Each triangle's turn and stretch from key A to key B, turns kept round the middle one so
## the whole shape turns one way
func _find_turns() -> void:
	for k in range(0, triangles.size(), 3):
		var r0 := rest[triangles[k]]
		var q0 := target[triangles[k]]
		var from := Transform2D(
			rest[triangles[k + 1]] - r0, rest[triangles[k + 2]] - r0, Vector2.ZERO
		)
		var to := Transform2D(
			target[triangles[k + 1]] - q0, target[triangles[k + 2]] - q0, Vector2.ZERO
		)
		var whole := to * from.affine_inverse()
		# The nearest turn, then what's left is the stretch
		var turn := atan2(whole.x.y - whole.y.x, whole.x.x + whole.y.y)
		var stretch := Transform2D(-turn, Vector2.ZERO) * whole
		_turns.append(turn)
		_stretches.append_array([stretch.x.x, stretch.y.x, stretch.x.y, stretch.y.y])
	var sorted := _turns.duplicate()
	sorted.sort()
	var middle := sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	for k in _turns.size():
		_turns[k] = middle + wrapf(_turns[k] - middle, -PI, PI)


## The triangles' corners [param t] of the way from key A to key B
func at(t: float) -> PackedVector2Array:
	if t <= 0.0:
		return rest.duplicate()
	if t >= 1.0:
		return target.duplicate()
	var turns := PackedFloat32Array()
	var stretches := PackedFloat32Array()
	for k in _turns.size():
		turns.append(_turns[k] * t)
		var s := k * 4
		(
			stretches
			. append_array(
				[
					1.0 - t + t * _stretches[s],
					t * _stretches[s + 1],
					t * _stretches[s + 2],
					1.0 - t + t * _stretches[s + 3],
				]
			)
		)
	var positions := PackedVector2Array()
	positions.resize(rest.size())
	for i in rest.size():
		positions[i] = rest[i].lerp(target[i], t)
	# One corner held, as the rest only fixes how corners lie to each other
	var fixed := PackedByteArray()
	fixed.resize(rest.size())
	fixed[triangles[0]] = 1
	_solve(positions, _pulls(turns, stretches), fixed)
	# Placed so its middle moves evenly
	var middle := Vector2.ZERO
	var wanted := Vector2.ZERO
	for i in rest.size():
		middle += positions[i]
		wanted += rest[i].lerp(target[i], t)
	var offset := (wanted - middle) / rest.size()
	for i in rest.size():
		positions[i] += offset
	return positions


## For each pixel of a canvas [param scale] times as big, the point of a key it shows at
## [param t] (key A's when [param from_b] is false, else B's), on that bigger canvas;
## [code]Vector2(-1, -1)[/code] where the triangles don't cover it. Triangles flipped over
## by then are left out, as they'd fold over others; gaps a few pixels across, theirs or
## between triangles, take the points round them, carried on. Writes into
## [param magnified] how much the key is grown at each pixel. Can be called on several
## threads at once.
func sources(
	t: float, from_b: bool, scale := 1, magnified := PackedFloat32Array()
) -> PackedVector2Array:
	var big_width := width * scale
	var big_height := height * scale
	var result := PackedVector2Array()
	result.resize(big_width * big_height)
	result.fill(Vector2(-1, -1))
	magnified.resize(result.size())
	magnified.fill(1.0)
	var positions := at(t)
	var from := target if from_b else rest
	# Where the pixels covered are
	var low := Vector2i(big_width, big_height)
	var high := Vector2i(-1, -1)
	for k in range(0, triangles.size(), 3):
		var c0 := positions[triangles[k]] * scale
		var c1 := positions[triangles[k + 1]] * scale
		var c2 := positions[triangles[k + 2]] * scale
		var s0 := from[triangles[k]] * scale
		var s1 := from[triangles[k + 1]] * scale
		var s2 := from[triangles[k + 2]] * scale
		var e1 := c1 - c0
		var e2 := c2 - c0
		var area := e1.cross(e2)
		var rested := (rest[triangles[k + 1]] - rest[triangles[k]]).cross(
			rest[triangles[k + 2]] - rest[triangles[k]]
		)
		if absf(area) < 1e-6 or (area > 0.0) != (rested > 0.0):
			continue
		# How much the triangle is grown from the key: its map's biggest stretch
		var from_sides := Transform2D(s1 - s0, s2 - s0, Vector2.ZERO)
		var grown := 1.0
		if absf(from_sides.determinant()) > 1e-6:
			grown = _largest_stretch(
				Transform2D(e1, e2, Vector2.ZERO) * from_sides.affine_inverse()
			)
		var x0 := maxi(floori(minf(c0.x, minf(c1.x, c2.x))), 0)
		var y0 := maxi(floori(minf(c0.y, minf(c1.y, c2.y))), 0)
		var x1 := mini(ceili(maxf(c0.x, maxf(c1.x, c2.x))) + 1, big_width)
		var y1 := mini(ceili(maxf(c0.y, maxf(c1.y, c2.y))) + 1, big_height)
		for py in range(y0, y1):
			for px in range(x0, x1):
				var d := Vector2(px + 0.5, py + 0.5) - c0
				var u := d.cross(e2) / area
				var v := e1.cross(d) / area
				if u < -0.02 or v < -0.02 or u + v > 1.02:
					continue
				result[py * big_width + px] = s0 + (s1 - s0) * u + (s2 - s0) * v
				magnified[py * big_width + px] = grown
				low = low.min(Vector2i(px, py))
				high = high.max(Vector2i(px, py))
	if high.x < 0:
		return result
	# Gaps are filled round the pixels covered only: the area round holds every one, so
	# the nearest are as on the whole canvas (see PixelCanvas.distances), and those farther
	# out than a gap stay uncovered
	var around := Rect2i(low, high - low + Vector2i.ONE).grow(GAP * scale + 1)
	around = around.intersection(Rect2i(0, 0, big_width, big_height))
	var w := around.size.x
	var covered := PackedByteArray()
	covered.resize(w * around.size.y)
	for y in range(around.position.y, around.end.y):
		var row := (y - around.position.y) * w - around.position.x
		for x in range(around.position.x, around.end.x):
			covered[row + x] = 1 if result[y * big_width + x].x >= 0.0 else 0
	var far := (big_width + big_height) * 4
	var nearest: Array = PixelCanvas.distances(covered, w, around.size.y, 1, far)
	var apart: PackedInt32Array = nearest[0]
	var from_pixel: PackedInt32Array = nearest[1]
	for i in covered.size():
		if covered[i] == 1 or from_pixel[i] < 0 or apart[i] > GAP * scale * 3:
			continue
		var p := (i / w + around.position.y) * big_width + i % w + around.position.x
		var n := from_pixel[i]
		var q := (n / w + around.position.y) * big_width + n % w + around.position.x
		var step := Vector2(p % big_width - q % big_width, p / big_width - q / big_width)
		result[p] = result[q] + step
		magnified[p] = magnified[q]
	return result


## How much [param map] stretches things most, in any direction (its biggest singular
## value)
static func _largest_stretch(map: Transform2D) -> float:
	var a := map.x.x
	var b := map.y.x
	var c := map.x.y
	var d := map.y.y
	var sum := a * a + b * b + c * c + d * d
	var det := a * d - b * c
	return sqrt(maxf((sum + sqrt(maxf(sum * sum - 4.0 * det * det, 0.0))) / 2.0, 0.0))
