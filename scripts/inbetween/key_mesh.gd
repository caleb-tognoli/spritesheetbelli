class_name KeyMesh
extends RefCounted
## One key cut into triangles and laid onto the other key, for in-betweens that bend the
## drawing part of the way there: as-rigid-as-possible shape interpolation (Alexa,
## Cohen-Or and Levin, 2000; Baxter, Barla and Anjyo, 2008), with the triangles laid onto
## the other key by matching the key's pixels to the other key's.
##
## The key's shape is cut into triangles: corners along its outline and on a grid inside,
## with thin triangles bridging the gaps between its parts so they hang together loosely,
## and cut apart where its pieces (see [KeySide]) meet, so each can move on its own. The
## pieces first carry the triangles where they move; then, round after round, each pixel
## looks around where it landed for the pixel of the other key most like it and the
## pixels round it (turned as its triangle is), each edge of the other key pulls the
## nearest pixel most like it, and the triangles are laid where those pulls want them, as
## rigidly as the round allows, less rigidly each round. This follows what bends, like
## cloth, as well as what moves rigidly, like a blade.
##
## Frames turn and stretch each triangle part of the way and put them back together as
## well as they fit, the pieces staying attached as they were (see [method at]). The
## key's pixels are moved by whole pixels, the same for neighbours moving alike, so drawn
## shapes stay crisp; what turns or grows much is drawn through the triangles with its
## outline smooth (see [method drawn]).

## Points inside the shape this many pixels apart, and along its outline, for sprites up
## to [constant SIZE_UNIT] pixels across; bigger ones space them more
const GRID := 1.5
const SIZE_UNIT := 40.0
## How much a triangle bridging a gap between parts counts against one over the sprite,
## and at most how long its sides are, in grid spacings
const GLUE := 0.05
const GLUE_REACH := 6.0
## How much copies of a corner where pieces meet are tied together in frames, against a
## triangle: as far apart as part of the way they get, so pieces stay attached as they
## were
const TIE := 0.1
## Laying the triangles where the pieces move: how much a piece not found in the other
## key pulls, how rigid the triangles are against the pulls, and how many rounds
const UNFOUND := 0.05
const PIECE_STIFFNESS := 0.3
const PIECE_ROUNDS := 10
## Matching rounds: how far each pixel looks (for sprites up to [constant SIZE_UNIT]
## across), and how rigid the triangles are, both less each round
const REACHES := [8.0, 6.0, 4.0, 3.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0]
const STIFFNESS := [8.0, 4.0, 2.0, 1.0, 0.5, 0.3, 0.2, 0.1, 0.1, 0.1]
## Rounds of turning the triangles and laying them again, per matching round
const INNER_ROUNDS := 3
## How much being far from where a pixel landed counts against a match, at the edge of
## where it looks, as a share of [constant LIKENESS]
const NEARNESS := 0.5
## How unlike two pixels (red, green, blue and alpha summed, premultiplied, 0 to 4) must be
## for their pull to fade to a third
const LIKENESS := 0.25
## How much the pixels on the other key's edges pull, against the key's own pixels
const EDGE_PULL := 1.0
## How much pixels inside the key's flat colours pull, against those on its edges
const FLAT_PULL := 0.3
## Pixels differing from a neighbour by this much (red, green, blue and alpha summed,
## premultiplied, 0 to 4) are on an edge
const EDGE_STEP := 0.15
## Triangles squashed flat, flipped or stretched this many times more one way than the
## other count this much less when frames are put together
const WARPED_RATIO := 4.0
const WARPED_SMALLEST := 0.2
const WARPED_WEIGHT := 0.002
## Pixels moved by whole pixels take the move most of those up to this many pixels
## round have, of the moves within a pixel of theirs, theirs counting this much more
const ALIKE_REACH := 2
const OWN_MOVE := 0.3
## Triangles grown this much or more by a frame, or turned this much (in radians), are
## drawn through the triangles with their outline smooth, see [method MeshTools.drawn_over]
const MAGNIFIED := 1.25
const TURNED := 0.2
## Solving for the corners: at most this many steps, until this close
const SOLVER_STEPS := 50
const SOLVER_CLOSE := 1e-4
## Pins (see [method pinned]) pull this many times harder than the triangles hold together,
## for so many rounds of turning the triangles and laying them again
const PIN_PULL := 20.0
const PIN_ROUNDS := 6

## The canvas the key is on, as worked out
var width := 0
var height := 0
## The triangles' corners, where they are in the key and on the other key
var rest := PackedVector2Array()
var target := PackedVector2Array()
## Three corners each, and how much each counts: 1 over the sprite, [constant GLUE]
## bridging gaps
var triangles := PackedInt32Array()
var weights := PackedFloat32Array()
## Each pixel's depth, the rank of its piece back to front, for pixels landing on the same
## spot
var depth := PackedInt32Array()

## 1 for corners of pieces attached to none (see [member KeySide.parents]), which keep
## to their way in frames, 0 for the others; all 1 when none is
var _anchors := PackedFloat32Array()
## Copies of a corner where pieces meet, in pairs, tied together; and where they start
## among the joined pairs
var _ties := PackedInt32Array()
var _first_tie := 0
## Corners joined by triangle sides, each pair once, and each triangle's three sides
## among them
var _side_from := PackedInt32Array()
var _side_to := PackedInt32Array()
var _triangle_sides := PackedInt32Array()
## Each triangle's turn from the key to the other, its stretch (2 × 2, by rows), and how
## much it counts when frames are put together
var _turns := PackedFloat32Array()
var _stretches := PackedFloat32Array()
var _frame_weights := PackedFloat32Array()
var _frame_matrix: MeshMatrix
## The key drawn in frames, [member _drawn_scale] times bigger than worked out, see
## [method draw_from]; its pixels placed in the triangles
var _drawn_data := PackedByteArray()
var _drawn_scale := 1
var _drawn_points: MeshTools.Located
## Pixels of the key shown off the triangles and the nearest pixel on them, in pairs
var _strays := PackedInt32Array()


## The mesh of [param data] laid onto [param other] (keys on canvases [param canvas_width]
## × [param canvas_height] pixels), its pieces moving as [param side] says; null when the
## key shows nothing. [param progress] tells how far it got, and stops it when cancelled.
static func lay(
	data: PackedByteArray,
	other: PackedByteArray,
	canvas_width: int,
	canvas_height: int,
	side: KeySide,
	progress: WorkProgress = null
) -> KeyMesh:
	var mesh := KeyMesh.new()
	mesh.width = canvas_width
	mesh.height = canvas_height
	# How big the sprite is: the side of a square as big as the bigger key
	var shown := Vector2i.ZERO
	for p in data.size() / 4:
		shown += Vector2i(1 if data[p * 4 + 3] >= 128 else 0, 1 if other[p * 4 + 3] >= 128 else 0)
	var size := maxf(sqrt(maxi(shown.x, shown.y)), 4.0)
	var unit := maxf(1.0, size / SIZE_UNIT)
	if not mesh._cut(data, GRID * unit):
		return null
	var located := mesh._locate(MeshTools.shown_points(data, canvas_width, 128), 1)
	if located.pixels.is_empty():
		return null
	mesh._depths(side)
	var corner_pieces := mesh._split(side)
	mesh._anchor(side, corner_pieces)
	mesh._follow_pieces(located, side, corner_pieces)
	var colors := MeshTools.Colors.new()
	colors.own = MeshTools.premultiplied(data)
	colors.other = MeshTools.premultiplied(other)
	colors.own_edges = MeshTools.edges(colors.own, canvas_width, canvas_height, EDGE_STEP)
	colors.other_edges = MeshTools.edges(colors.other, canvas_width, canvas_height, EDGE_STEP)
	for r in REACHES.size():
		if progress and progress.cancelled:
			return null
		mesh._match_round(colors, located, REACHES[r] * unit, STIFFNESS[r])
		if progress:
			progress.done += 1
	mesh._find_turns()
	return mesh


## How many steps [method lay] reports to its progress
static func steps() -> int:
	return REACHES.size()


# --- Cutting into triangles


## Cuts the key's shape into triangles, corners [param spacing] pixels apart; false when
## it can't
func _cut(data: PackedByteArray, spacing: float) -> bool:
	var size := width * height
	var shown := PackedByteArray()
	shown.resize(size)
	for p in size:
		shown[p] = 1 if data[p * 4 + 3] >= 128 else 0
	if not shown.has(1):
		return false
	var whole := ShapeBlend.shape_of(data, width, height)
	var points := ShapeBlend.outline_of(whole, width, height, 0, spacing)
	var near := MeshTools.Spots.new(maxf(spacing, 1.0))
	for point in points:
		near.add(point)
	# A grid inside, clear of the outline
	var y := spacing / 2.0
	while y < height:
		var x := spacing / 2.0
		while x < width:
			var place := Vector2(x, y)
			if shown[int(y) * width + int(x)] == 1 and not near.any_within(place, spacing * 0.6):
				points.append(place)
			x += spacing
		y += spacing
	for k in range(near.count(), points.size()):
		near.add(points[k])
	# Thin parts the grid missed
	var extra := MeshTools.Spots.new(maxf(spacing, 1.0))
	for p in size:
		if shown[p] == 0:
			continue
		var place := Vector2(p % width + 0.5, p / width + 0.5)
		if near.any_within(place, spacing * 0.9) or extra.any_within(place, spacing * 0.7):
			continue
		extra.add(place)
		points.append(place)
	if points.size() < 3:
		return false
	var found := Geometry2D.triangulate_delaunay(points)
	# Over the sprite (a pixel round it counting), or bridging a gap
	var grown := shown.duplicate()
	for p in size:
		if shown[p] == 0:
			continue
		for side in PixelParts.sides_of(width):
			var q: int = p + side
			if q >= 0 and q < size and absi(q % width - p % width) <= 1:
				grown[q] = 1
	for k in range(0, found.size(), 3):
		var i0 := found[k]
		var i1 := found[k + 1]
		var i2 := found[k + 2]
		var c0 := points[i0]
		var c1 := points[i1]
		var c2 := points[i2]
		var area := (c1 - c0).cross(c2 - c0)
		if absf(area) < 1e-3:
			continue
		if area < 0.0:
			var swap := i1
			i1 = i2
			i2 = swap
			var corner := c1
			c1 = c2
			c2 = corner
		var inside := true
		for probe: Vector2 in [
			(c0 + c1 + c2) / 3.0, (c0 + c1) / 2.0, (c1 + c2) / 2.0, (c2 + c0) / 2.0
		]:
			var px := clampi(floori(probe.x), 0, width - 1)
			var py := clampi(floori(probe.y), 0, height - 1)
			if grown[py * width + px] == 0:
				inside = false
				break
		var longest := maxf(c0.distance_to(c1), maxf(c1.distance_to(c2), c2.distance_to(c0)))
		if not inside and longest >= spacing * GLUE_REACH:
			continue
		triangles.append_array([i0, i1, i2])
		weights.append(1.0 if inside else GLUE)
	if triangles.is_empty():
		return false
	rest = points
	target = points.duplicate()
	return true


## Cuts the triangles apart where [param side]'s pieces meet, so each piece can move on
## its own: each triangle goes with the piece at its middle (or the nearest), corners of
## triangles of several pieces are copied for each, and the copies tied together. Returns
## each corner's piece.
func _split(side: KeySide) -> PackedInt32Array:
	var labelled := PackedByteArray()
	labelled.resize(width * height)
	for p in mini(labelled.size(), side.drawing.size()):
		labelled[p] = 1 if side.drawing[p] >= 0 else 0
	var nearest: PackedInt32Array = PixelCanvas.distances(labelled, width, height, 1)[1]
	var copies := {}
	var first := {}
	var corners := PackedVector2Array()
	var pieces := PackedInt32Array()
	for k in range(0, triangles.size(), 3):
		var middle := (rest[triangles[k]] + rest[triangles[k + 1]] + rest[triangles[k + 2]]) / 3.0
		var x := clampi(floori(middle.x), 0, width - 1)
		var y := clampi(floori(middle.y), 0, height - 1)
		var q := nearest[y * width + x]
		var piece := side.drawing[q] if q >= 0 else -1
		for e in 3:
			var corner := triangles[k + e]
			var key := Vector2i(corner, piece)
			if not copies.has(key):
				copies[key] = corners.size()
				if first.has(corner):
					_ties.append_array([first[corner], corners.size()])
				else:
					first[corner] = corners.size()
				corners.append(rest[corner])
				pieces.append(piece)
			triangles[k + e] = copies[key]
	rest = corners
	target = corners.duplicate()
	# Each pair of corners joined once, then the ties
	var index := {}
	for k in range(0, triangles.size(), 3):
		for e in 3:
			var a := triangles[k + e]
			var b := triangles[k + (e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not index.has(key):
				index[key] = _side_from.size()
				_side_from.append(key.x)
				_side_to.append(key.y)
			_triangle_sides.append(index[key])
	_first_tie = _side_from.size()
	for k in range(0, _ties.size(), 2):
		_side_from.append(_ties[k])
		_side_to.append(_ties[k + 1])
	return pieces


## Where each of [param points] (on the canvas [param scale] times bigger) is in the
## triangles where they rest: the triangle it's in, or the nearest, and how far along
## each of its corners
func _locate(points: PackedVector2Array, scale: int) -> MeshTools.Located:
	var big_width := width * scale
	var big_height := height * scale
	var best := PackedFloat32Array()
	best.resize(big_width * big_height)
	best.fill(-INF)
	var owner := PackedInt32Array()
	owner.resize(big_width * big_height)
	owner.fill(-1)
	var weights_at := PackedVector3Array()
	weights_at.resize(big_width * big_height)
	for k in range(0, triangles.size(), 3):
		var c0 := rest[triangles[k]] * scale
		var c1 := rest[triangles[k + 1]] * scale
		var c2 := rest[triangles[k + 2]] * scale
		var e1 := c1 - c0
		var e2 := c2 - c0
		var area := e1.cross(e2)
		var bridging := -0.5 if weights[k / 3] < 1.0 else 0.0
		var x0 := maxi(floori(minf(c0.x, minf(c1.x, c2.x))) - 1, 0)
		var y0 := maxi(floori(minf(c0.y, minf(c1.y, c2.y))) - 1, 0)
		var x1 := mini(ceili(maxf(c0.x, maxf(c1.x, c2.x))) + 1, big_width)
		var y1 := mini(ceili(maxf(c0.y, maxf(c1.y, c2.y))) + 1, big_height)
		for py in range(y0, y1):
			for px in range(x0, x1):
				var d := Vector2(px + 0.5, py + 0.5) - c0
				var u := d.cross(e2) / area
				var v := e1.cross(d) / area
				var score := minf(minf(u, v), 1.0 - u - v) + bridging
				var p := py * big_width + px
				if score > best[p]:
					best[p] = score
					owner[p] = k / 3
					weights_at[p] = Vector3(1.0 - u - v, u, v)
	var located := MeshTools.Located.new()
	for point in points:
		var p := floori(point.y) * big_width + floori(point.x)
		if owner[p] < 0 or best[p] <= -0.3:
			continue
		located.points.append(point)
		located.pixels.append(p)
		located.triangles.append(owner[p])
		located.weights.append(weights_at[p])
	return located


## Each pixel's depth from [param side]'s pieces, back to front
func _depths(side: KeySide) -> void:
	var rank := PackedInt32Array()
	rank.resize(side.pieces.count())
	for k in side.order.size():
		rank[side.order[k]] = k + 1
	depth.resize(width * height)
	for p in mini(depth.size(), side.drawing.size()):
		var r := side.drawing[p]
		depth[p] = rank[r] if r >= 0 and r < rank.size() else 0


# --- Laying onto the other key


## Marks the corners of pieces attached to none, see [member _anchors]
func _anchor(side: KeySide, corner_pieces: PackedInt32Array) -> void:
	_anchors.resize(rest.size())
	var any := false
	for i in rest.size():
		var r := corner_pieces[i]
		if r >= 0 and r < side.parents.size() and side.parents[r] < 0:
			_anchors[i] = 1.0
			any = true
	if not any:
		_anchors.fill(1.0)


## Lays the triangles where [param side]'s pieces move the key's pixels ([param located])
func _follow_pieces(
	located: MeshTools.Located, side: KeySide, corner_pieces: PackedInt32Array
) -> void:
	var count := located.pixels.size()
	var goals := PackedVector2Array()
	goals.resize(count)
	var pulls := PackedFloat32Array()
	pulls.resize(count)
	var unfound := {}
	for r in side.unfound:
		unfound[r] = true
	for s in count:
		var r := side.drawing[located.pixels[s]] if located.pixels[s] < side.drawing.size() else -1
		if r < 0 or r >= side.motions.size():
			goals[s] = located.points[s]
			continue
		goals[s] = side.motions[r] * located.points[s]
		pulls[s] = UNFOUND if unfound.has(r) else 1.0
	# Each corner moves with its piece
	for i in rest.size():
		var r := corner_pieces[i]
		target[i] = side.motions[r] * rest[i] if r >= 0 and r < side.motions.size() else rest[i]
	_lay(located, goals, pulls, PackedInt32Array(), PackedVector2Array(), PackedFloat32Array(),
		weights, PIECE_STIFFNESS, PIECE_ROUNDS)


## A round of matching the key's pixels ([param located]) to the other key's (both in
## [param colors]), each looking up to [param reach] pixels round where it landed, then
## laying the triangles where the matches pull, as rigidly as [param stiffness] says
func _match_round(
	colors: MeshTools.Colors, located: MeshTools.Located, reach: float, stiffness: float
) -> void:
	var count := located.pixels.size()
	var turns := _triangle_turns(target)
	var landed := located.at(target, triangles)
	var own := colors.own
	var others := colors.other
	var own_edges := colors.own_edges
	var goals := PackedVector2Array()
	goals.resize(count)
	var pulls := PackedFloat32Array()
	pulls.resize(count)
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
	var near_cost := NEARNESS * LIKENESS / maxf(reach * reach, 1.0)
	var patch := PackedFloat32Array()
	patch.resize(36)
	for s in count:
		var p := located.pixels[s]
		var px := p % width
		var py := p / width
		# The pixel and those round it, as they are in the key
		var k := 0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var q := PixelCanvas.index_at(px + ox, py + oy, width, height)
				for c in 4:
					patch[k * 4 + c] = own[q * 4 + c] if q >= 0 else 0.0
				k += 1
		# Turned as its triangle is, a whole pixel each
		var turn := turns[located.triangles[s]]
		var ways := PackedInt32Array()
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var turned := Vector2(ox, oy).rotated(turn)
				ways.append(floori(turned.x + 0.5))
				ways.append(floori(turned.y + 0.5))
		var place := landed[s]
		var base := Vector2i(floori(place.x), floori(place.y))
		var best := INF
		var best_cost := 0.0
		var best_spot := base
		for spot in spots:
			var cx := base.x + spot.x
			var cy := base.y + spot.y
			# Spots are nearest first, give or take where in its pixel it landed
			var least := maxf(Vector2(spot).length() - 0.71, 0.0)
			if near_cost * least * least >= best:
				break
			var apart := Vector2(cx + 0.5, cy + 0.5) - place
			var prior := near_cost * apart.length_squared()
			if prior >= best:
				continue
			var cost := 0.0
			var limit := (best - prior) * 9.0
			for j in 9:
				var qx := cx + ways[j * 2]
				var qy := cy + ways[j * 2 + 1]
				var q := qy * width + qx
				if qx < 0 or qy < 0 or qx >= width or qy >= height:
					for c in 4:
						cost += absf(patch[j * 4 + c])
				else:
					for c in 4:
						cost += absf(others[q * 4 + c] - patch[j * 4 + c])
				if cost >= limit:
					break
			if cost >= limit:
				continue
			cost /= 9.0
			if cost + prior < best:
				best = cost + prior
				best_cost = cost
				best_spot = Vector2i(cx, cy)
		goals[s] = Vector2(best_spot) + Vector2(0.5, 0.5)
		pulls[s] = (1.0 if own_edges[p] == 1 else FLAT_PULL) * exp(-best_cost / LIKENESS)
	# The other key's edges each pull the landed pixel nearest and most like it
	var other_edges := colors.other_edges
	var cell := maxf(reach + 1.0, 1.0)
	var buckets := {}
	for s in count:
		var key := Vector2i(floori(landed[s].x / cell), floori(landed[s].y / cell))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(s)
	var edge_samples := PackedInt32Array()
	var edge_goals := PackedVector2Array()
	var edge_pulls := PackedFloat32Array()
	for q in other_edges.size():
		if other_edges[q] == 0:
			continue
		var spot := Vector2(q % width + 0.5, q / width + 0.5)
		var home := Vector2i(floori(spot.x / cell), floori(spot.y / cell))
		var best := INF
		var best_cost := 0.0
		var best_sample := -1
		for by in range(home.y - 1, home.y + 2):
			for bx in range(home.x - 1, home.x + 2):
				for s: int in buckets.get(Vector2i(bx, by), []):
					var apart := landed[s].distance_squared_to(spot)
					if apart > cell * cell:
						continue
					var o := located.pixels[s] * 4
					var cost := 0.0
					for c in 4:
						cost += absf(own[o + c] - others[q * 4 + c])
					var total := cost + near_cost * apart
					if total < best:
						best = total
						best_cost = cost
						best_sample = s
		if best_sample >= 0:
			edge_samples.append(best_sample)
			edge_goals.append(spot)
			edge_pulls.append(EDGE_PULL * exp(-best_cost / LIKENESS))
	_lay(located, goals, pulls, edge_samples, edge_goals, edge_pulls, weights, stiffness,
		INNER_ROUNDS)


## Lays the triangles as rigidly as [param stiffness] says ([param stiff], how much each
## triangle counts), the pixels of [param located] pulled to [param goals] by
## [param pulls], and the ones [param extra] says to [param extra_goals] by
## [param extra_pulls], [param rounds] times turning the triangles and laying them again
func _lay(
	located: MeshTools.Located,
	goals: PackedVector2Array,
	pulls: PackedFloat32Array,
	extra: PackedInt32Array,
	extra_goals: PackedVector2Array,
	extra_pulls: PackedFloat32Array,
	stiff: PackedFloat32Array,
	stiffness: float,
	rounds: int
) -> void:
	var n := rest.size()
	var matrix := MeshMatrix.new(n, _side_from, _side_to)
	var data_side := PackedVector2Array()
	data_side.resize(n)
	var pulled := 0.0
	for s in located.pixels.size():
		pulled += pulls[s]
		_add_pull(matrix, data_side, located, s, goals[s], pulls[s])
	for e in extra.size():
		pulled += extra_pulls[e]
		_add_pull(matrix, data_side, located, extra[e], extra_goals[e], extra_pulls[e])
	var stiff_total := 0.0
	for k in stiff.size():
		stiff_total += stiff[k] * 3.0
	var scale := stiffness * pulled / maxf(stiff_total, 1e-9) * 3.0
	var laplacian := MeshMatrix.new(n, _side_from, _side_to)
	_add_laplacian(laplacian, stiff, 0.0)
	matrix.add_scaled(laplacian, scale)
	matrix.add_diagonal(1e-6)
	for _round in rounds:
		var turns := _triangle_turns(target)
		var wanted := _pulls(turns, PackedFloat32Array(), stiff, 1.0)
		var right := PackedVector2Array()
		right.resize(n)
		for i in n:
			right[i] = wanted[i] * scale + data_side[i] + target[i] * 1e-6
		matrix.solve(target, right, SOLVER_STEPS, SOLVER_CLOSE)


## Adds to [param matrix] and [param right] pixel [param s] of [param located] pulled to
## [param goal] by [param pull]
func _add_pull(
	matrix: MeshMatrix,
	right: PackedVector2Array,
	located: MeshTools.Located,
	s: int,
	goal: Vector2,
	pull: float
) -> void:
	if pull <= 0.0:
		return
	var k := located.triangles[s]
	var w := located.weights[s]
	var amounts := [w.x, w.y, w.z]
	for e in 3:
		var i := triangles[k * 3 + e]
		var a: float = amounts[e]
		matrix.diagonal[i] += pull * a * a
		right[i] += goal * (pull * a)
		var b: float = amounts[(e + 1) % 3]
		matrix.sides[_triangle_sides[k * 3 + e]] += pull * a * b


## Adds the triangles' sides to [param matrix], each triangle counting [param stiff], and
## the ties between copies of corners, each counting [param tie]
func _add_laplacian(matrix: MeshMatrix, stiff: PackedFloat32Array, tie: float) -> void:
	for k in range(0, triangles.size(), 3):
		var w := stiff[k / 3]
		for e in 3:
			matrix.diagonal[triangles[k + e]] += w
			matrix.diagonal[triangles[k + (e + 1) % 3]] += w
			matrix.sides[_triangle_sides[k + e]] -= w
	if tie <= 0.0:
		return
	for e in range(_first_tie, _side_from.size()):
		matrix.diagonal[_side_from[e]] += tie
		matrix.diagonal[_side_to[e]] += tie
		matrix.sides[e] -= tie


## What each corner is pulled by when each triangle side wants to be as it rests turned by
## its triangle's turn in [param turns], stretched by [param stretches] (4 per triangle,
## by rows; none when empty) and scaled by [param amount], each triangle counting
## [param stiff]; or as it is in [param shape] instead, when given
func _pulls(
	turns: PackedFloat32Array,
	stretches: PackedFloat32Array,
	stiff: PackedFloat32Array,
	amount: float,
	shape := PackedVector2Array()
) -> PackedVector2Array:
	var resting := rest if shape.is_empty() else shape
	var result := PackedVector2Array()
	result.resize(rest.size())
	for k in range(0, triangles.size(), 3):
		var t := k / 3
		var w := stiff[t]
		if w <= 0.0:
			continue
		var turn := turns[t]
		for e in 3:
			var from := triangles[k + e]
			var to := triangles[k + (e + 1) % 3]
			var side := resting[to] - resting[from]
			if not stretches.is_empty():
				var s := t * 4
				side = Vector2(
					stretches[s] * side.x + stretches[s + 1] * side.y,
					stretches[s + 2] * side.x + stretches[s + 3] * side.y
				)
			side = side.rotated(turn) * (w * amount)
			result[to] += side
			result[from] -= side
	return result


## The turn best taking each triangle from where it rests (or is in [param shape], when
## given) to [param positions]
func _triangle_turns(
	positions: PackedVector2Array, shape := PackedVector2Array()
) -> PackedFloat32Array:
	var resting := rest if shape.is_empty() else shape
	var result := PackedFloat32Array()
	result.resize(triangles.size() / 3)
	for k in range(0, triangles.size(), 3):
		var r0 := resting[triangles[k]]
		var r1 := resting[triangles[k + 1]]
		var r2 := resting[triangles[k + 2]]
		var q0 := positions[triangles[k]]
		var q1 := positions[triangles[k + 1]]
		var q2 := positions[triangles[k + 2]]
		var rm := (r0 + r1 + r2) / 3.0
		var qm := (q0 + q1 + q2) / 3.0
		var dot := (r0 - rm).dot(q0 - qm) + (r1 - rm).dot(q1 - qm) + (r2 - rm).dot(q2 - qm)
		var cross := (
			(r0 - rm).cross(q0 - qm) + (r1 - rm).cross(q1 - qm) + (r2 - rm).cross(q2 - qm)
		)
		result[k / 3] = atan2(cross, dot)
	return result


# --- Frames


## Each triangle's turn and stretch from the key to the other, and how much it counts in
## frames: less for those flipped or squashed flat. Turns of neighbours are kept within
## half a turn of each other, from the best triangles out, so the whole shape turns one
## way.
func _find_turns() -> void:
	var count := triangles.size() / 3
	var raw := PackedFloat32Array()
	raw.resize(count)
	_stretches.resize(count * 4)
	_frame_weights.resize(count)
	for t in count:
		var k := t * 3
		var r0 := rest[triangles[k]]
		var q0 := target[triangles[k]]
		var from := Transform2D(rest[triangles[k + 1]] - r0, rest[triangles[k + 2]] - r0, Vector2.ZERO)
		var to := Transform2D(target[triangles[k + 1]] - q0, target[triangles[k + 2]] - q0, Vector2.ZERO)
		var whole := to * from.affine_inverse()
		var turn := atan2(whole.x.y - whole.y.x, whole.x.x + whole.y.y)
		var stretch := Transform2D(-turn, Vector2.ZERO) * whole
		var across := (stretch.y.x + stretch.x.y) / 2.0
		_stretches[t * 4] = stretch.x.x
		_stretches[t * 4 + 1] = across
		_stretches[t * 4 + 2] = across
		_stretches[t * 4 + 3] = stretch.y.y
		raw[t] = turn
		# Flipped, squashed flat or stretched one way much more than the other
		var a := whole.x.x
		var b := whole.y.x
		var c := whole.x.y
		var d := whole.y.y
		var sum := a * a + b * b + c * c + d * d
		var det := a * d - b * c
		var root := sqrt(maxf(sum * sum - 4.0 * det * det, 0.0))
		var largest := sqrt(maxf((sum + root) / 2.0, 0.0))
		var smallest := sqrt(maxf((sum - root) / 2.0, 0.0))
		var warped := (
			det <= 0.0
			or smallest <= WARPED_SMALLEST
			or largest >= smallest * WARPED_RATIO
		)
		_frame_weights[t] = weights[t] * (WARPED_WEIGHT if warped else 1.0)
	_turns = _unwrapped(raw)
	var n := rest.size()
	_frame_matrix = MeshMatrix.new(n, _side_from, _side_to)
	_add_laplacian(_frame_matrix, _frame_weights, TIE)
	var mean := 0.0
	for i in n:
		mean += _frame_matrix.diagonal[i]
	_frame_matrix.add_diagonal(1e-4 * maxf(mean / n, 1e-9))


## How far the key turns as a whole on its way to the other, in radians: its triangles'
## turns averaged by how much they count in frames
func whole_turn() -> float:
	var total := 0.0
	var count := 0.0
	for t in _turns.size():
		total += _turns[t] * _frame_weights[t]
		count += _frame_weights[t]
	return total / count if count > 0.0 else 0.0


## [param raw] turns kept within half a turn of their neighbours', spreading from the
## triangles counting most, then the whole made to average within half a turn of none
func _unwrapped(raw: PackedFloat32Array) -> PackedFloat32Array:
	var count := raw.size()
	var neighbours: Array[Array] = []
	for t in count:
		neighbours.append([])
	var by_side := {}
	for k in triangles.size():
		var side := _triangle_sides[k]
		if by_side.has(side):
			var other: int = by_side[side]
			neighbours[k / 3].append(other)
			neighbours[other].append(k / 3)
		else:
			by_side[side] = k / 3
	var result := raw.duplicate()
	var seen := PackedByteArray()
	seen.resize(count)
	var roots := range(count)
	roots.sort_custom(func(x: int, y: int) -> bool: return _frame_weights[x] > _frame_weights[y])
	var heap := MeshTools.Heap.new()
	for root: int in roots:
		if seen[root] == 1:
			continue
		seen[root] = 1
		for j: int in neighbours[root]:
			heap.push(_frame_weights[j], j, root)
		while not heap.is_empty():
			var top := heap.pop()
			var j := int(top.y)
			var from := int(top.z)
			if seen[j] == 1:
				continue
			result[j] = result[from] + wrapf(raw[j] - result[from], -PI, PI)
			seen[j] = 1
			for l: int in neighbours[j]:
				if seen[l] == 0:
					heap.push(minf(_frame_weights[j], _frame_weights[l]), l, j)
	var mean := 0.0
	var total := 0.0
	for t in count:
		mean += result[t] * _frame_weights[t]
		total += _frame_weights[t]
	if total > 0.0:
		var whole_turns := roundf(mean / total / TAU) * TAU
		for t in count:
			result[t] -= whole_turns
	return result


## The triangles' corners [param t] of the way from the key to the other
func at(t: float) -> PackedVector2Array:
	var n := rest.size()
	var wanted := PackedVector2Array()
	wanted.resize(n)
	for i in n:
		wanted[i] = rest[i].lerp(target[i], t)
	if t <= 0.0:
		return rest.duplicate()
	if t >= 1.0:
		return target.duplicate()
	var count := triangles.size() / 3
	var turns := PackedFloat32Array()
	turns.resize(count)
	var stretches := PackedFloat32Array()
	stretches.resize(count * 4)
	for k in count:
		turns[k] = _turns[k] * t
		var s := k * 4
		stretches[s] = 1.0 - t + t * _stretches[s]
		stretches[s + 1] = t * _stretches[s + 1]
		stretches[s + 2] = t * _stretches[s + 2]
		stretches[s + 3] = 1.0 - t + t * _stretches[s + 3]
	var right := _pulls(turns, stretches, _frame_weights, 1.0)
	# Copies of a corner as far apart as part of the way they get
	for e in range(_first_tie, _side_from.size()):
		var a := _side_from[e]
		var b := _side_to[e]
		var apart := (target[a] - target[b]) * (t * TIE)
		right[a] += apart
		right[b] -= apart
	var close := _frame_matrix.diagonal_extra
	for i in n:
		right[i] += wanted[i] * close
	var positions := wanted.duplicate()
	_frame_matrix.solve(positions, right, SOLVER_STEPS, SOLVER_CLOSE)
	# The middle of the pieces the others hang from moves evenly
	var corner_weights := PackedFloat32Array()
	corner_weights.resize(n)
	for k in range(0, triangles.size(), 3):
		if weights[k / 3] < 1.0:
			continue
		for e in 3:
			var corner := triangles[k + e]
			corner_weights[corner] += _frame_weights[k / 3] * _anchors[corner]
	var offset := Vector2.ZERO
	var total := 0.0
	for i in n:
		offset += (wanted[i] - positions[i]) * corner_weights[i]
		total += corner_weights[i]
	if total > 0.0:
		offset /= total
	for i in n:
		positions[i] += offset
	return positions


## The corners [param positions], where [method at] puts them [param t] of the way, bent
## by pins: the points at [param pin_from] in the frame halfway go to [param pin_to] there,
## and [method PinWarp.weight] of the way at [param t], each followed from halfway in the
## triangle it's in (or the nearest). The triangles bend round the pins as rigidly as they
## can, each pulled towards how it is in [param positions] turned its own way, the pins
## pulling much harder, and every corner held weakly where it is, so a pin moves the part
## round it (about [constant PinWarp.REACH] of the sprite across) and what's far stays. The
## same [param positions] without pins, or at the keys.
func pinned(
	positions: PackedVector2Array,
	t: float,
	pin_from: PackedVector2Array,
	pin_to: PackedVector2Array
) -> PackedVector2Array:
	var amount := PinWarp.weight(t)
	if pin_from.is_empty() or amount <= 0.0:
		return positions
	var n := rest.size()
	var half := at(0.5)
	var located := MeshTools.Located.new()
	for point in pin_from:
		var place := _nearest_place(half, point)
		located.points.append(point)
		located.pixels.append(0)
		located.triangles.append(int(place.x))
		located.weights.append(Vector3(place.y, place.z, 1.0 - place.y - place.z))
	var froms := located.at(positions, triangles)
	var tos := PackedVector2Array()
	for k in froms.size():
		tos.append(froms[k] + (pin_to[k] - pin_from[k]) * amount)
	var matrix := MeshMatrix.new(n, _side_from, _side_to)
	matrix.add_scaled(_frame_matrix, 1.0)
	var mean := 0.0
	for i in n:
		mean += _frame_matrix.diagonal[i]
	var pull := PIN_PULL * mean / maxf(n, 1)
	var pins_side := PackedVector2Array()
	pins_side.resize(n)
	for s in froms.size():
		_add_pull(matrix, pins_side, located, s, tos[s], pull)
	# Each corner held where it is, weakly enough that the bend reaches about as far as
	# a pin's pull: a triangle side's stiffness, over how many sides that is
	var low := Vector2(INF, INF)
	var high := -low
	for point in positions:
		low = low.min(point)
		high = high.max(point)
	var reach := maxf(maxf(high.x - low.x, high.y - low.y), 1.0) * PinWarp.REACH
	var sides := 0.0
	for e in _first_tie:
		sides += positions[_side_from[e]].distance_to(positions[_side_to[e]])
	var side := sides / maxf(_first_tie, 1)
	var hold := mean / maxf(n, 1) / 6.0 * pow(side / reach, 2.0)
	matrix.add_diagonal(hold)
	# Started bent smoothly round the pins, then made as rigid as it can
	var bend := PinWarp.Bend.new(froms, tos, positions)
	var result := PackedVector2Array()
	result.resize(n)
	for i in n:
		result[i] = bend.moved(positions[i])
	var close := _frame_matrix.diagonal_extra + hold
	for _round in PIN_ROUNDS:
		var turns := _triangle_turns(result, positions)
		var right := _pulls(turns, PackedFloat32Array(), _frame_weights, 1.0, positions)
		# Copies of a corner kept as far apart as they were
		for e in range(_first_tie, _side_from.size()):
			var a := _side_from[e]
			var b := _side_to[e]
			var apart := (positions[a] - positions[b]) * TIE
			right[a] += apart
			right[b] -= apart
		for i in n:
			right[i] += pins_side[i] + positions[i] * close
		matrix.solve(result, right, SOLVER_STEPS, SOLVER_CLOSE)
	return result


## The triangle [param point] is in when the corners are at [param positions], or the
## nearest, avoiding those bridging gaps: x the triangle, y and z how far along its first
## two corners the point is, kept inside it
func _nearest_place(positions: PackedVector2Array, point: Vector2) -> Vector3:
	var best := Vector3(0, 1.0 / 3.0, 1.0 / 3.0)
	var best_score := -INF
	for k in range(0, triangles.size(), 3):
		var c0 := positions[triangles[k]]
		var e1 := positions[triangles[k + 1]] - c0
		var e2 := positions[triangles[k + 2]] - c0
		var area := e1.cross(e2)
		if absf(area) < 1e-9:
			continue
		var d := point - c0
		var u := d.cross(e2) / area
		var v := e1.cross(d) / area
		var score := minf(minf(u, v), 1.0 - u - v) - (0.5 if weights[k / 3] < 1.0 else 0.0)
		if score > best_score:
			best_score = score
			# Kept inside the triangle
			u = maxf(u, 0.0)
			v = maxf(v, 0.0)
			var w := maxf(1.0 - u - v, 0.0)
			var sum := u + v + w
			best = Vector3(k / 3, w / sum, u / sum)
	return best


## Frames are drawn from [param full_data], the key drawn [param scale] times bigger than
## worked out, on a canvas that much bigger. Call before [method drawn], once.
func draw_from(full_data: PackedByteArray, scale: int) -> void:
	_drawn_data = full_data
	_drawn_scale = scale
	_drawn_points = _locate(MeshTools.shown_points(full_data, width * scale, 1), scale)
	_find_strays(full_data, width * scale, height * scale)


## The key [param t] of the way to the other key, drawn as [method draw_from] says: each
## pixel moved by whole pixels to where the triangles take it, those moving alike
## together, the one in front kept where two land on one spot, and gaps between them
## filled from the triangles drawn over (see [method MeshTools.drawn_over]). Triangles
## turned or grown much are drawn over entirely, so their outline stays smooth. Pins
## moving points at [param pin_from] (as worked out, halfway) to [param pin_to] bend the
## triangles further, see [method pinned]. Frames can be drawn on several threads at once.
func drawn(
	t: float, pin_from := PackedVector2Array(), pin_to := PackedVector2Array()
) -> PackedByteArray:
	var full_data := _drawn_data
	var scale := _drawn_scale
	var big_width := width * scale
	var big_height := height * scale
	var positions := pinned(at(t), t, pin_from, pin_to)
	for i in positions.size():
		positions[i] *= scale
	var located := _drawn_points
	var count := located.pixels.size()
	var landed := located.at(positions, triangles)
	# Whole-pixel moves, then each the move most of its neighbours moving alike have
	var moves := PackedVector2Array()
	moves.resize(count)
	var move_at := {}
	for s in count:
		var move := (landed[s] - located.points[s]).round()
		moves[s] = move
		move_at[located.pixels[s]] = s
	var chosen := PackedVector2Array()
	chosen.resize(count)
	for s in count:
		var p := located.pixels[s]
		var px := p % big_width
		var py := p / big_width
		var own := moves[s]
		var tally := {}
		for dy in range(-ALIKE_REACH, ALIKE_REACH + 1):
			for dx in range(-ALIKE_REACH, ALIKE_REACH + 1):
				var qx := px + dx
				var qy := py + dy
				if qx < 0 or qy < 0 or qx >= big_width or qy >= big_height:
					continue
				var other: int = move_at.get(qy * big_width + qx, -1)
				if other < 0:
					continue
				var move := moves[other]
				if absf(move.x - own.x) > 1.0 or absf(move.y - own.y) > 1.0:
					continue
				tally[move] = tally.get(move, 0.0) + 1.0
		tally[own] = tally.get(own, 0.0) + OWN_MOVE
		var best := own
		var most := -1.0
		for move: Vector2 in tally:
			if tally[move] > most:
				most = tally[move]
				best = move
		chosen[s] = best
	# Pixels off the triangles, like a faint glow, move with the nearest pixel on them
	var pixels := located.pixels.duplicate()
	for k in range(0, _strays.size(), 2):
		var s: int = move_at[_strays[k + 1]]
		pixels.append(_strays[k])
		chosen.append(chosen[s])
		var apart := Vector2(
			_strays[k] % big_width - _strays[k + 1] % big_width,
			_strays[k] / big_width - _strays[k + 1] / big_width
		)
		landed.append(landed[s] + apart)
	var out := PixelCanvas.blank(big_width * big_height)
	var front := PackedFloat32Array()
	front.resize(big_width * big_height)
	front.fill(-INF)
	for s in pixels.size():
		var p := pixels[s]
		var dest := Vector2i(p % big_width, p / big_width) + Vector2i(chosen[s])
		if dest.x < 0 or dest.y < 0 or dest.x >= big_width or dest.y >= big_height:
			continue
		var small := (p / big_width / scale) * width + (p % big_width) / scale
		var rank := depth[small] if small < depth.size() else 0
		var key := rank * 100.0 - landed[s].distance_to(Vector2(dest) + Vector2(0.5, 0.5))
		var q := dest.y * big_width + dest.x
		if key < front[q]:
			continue
		front[q] = key
		for c in 4:
			out[q * 4 + c] = full_data[p * 4 + c]
	# Gaps a pixel across filled from the triangles drawn over
	var covered := PackedByteArray()
	covered.resize(big_width * big_height)
	for p in covered.size():
		covered[p] = 1 if out[p * 4 + 3] > 0 else 0
	var closed := MeshTools.closed(covered, big_width, big_height)
	var grown := PackedByteArray()
	var over := MeshTools.drawn_over(self, positions, full_data, scale, grown)
	var over_shown := PackedByteArray()
	over_shown.resize(covered.size())
	for p in covered.size():
		over_shown[p] = 1 if over[p * 4 + 3] > 0 else 0
	var over_closed := MeshTools.closed(over_shown, big_width, big_height)
	for p in covered.size():
		# Grown much, smooth from the triangles drawn over, but for pinholes in them
		var smooth := grown[p] == 1 and (over_shown[p] == 1 or over_closed[p] == 0)
		if smooth or (covered[p] == 0 and closed[p] == 1 and over_shown[p] == 1):
			for c in 4:
				out[p * 4 + c] = over[p * 4 + c]
	return out


## The pixels of [param full_data] (a canvas [param big_width] × [param big_height]) shown
## but off the triangles, each with the nearest pixel on them, see [member _strays]
func _find_strays(full_data: PackedByteArray, big_width: int, big_height: int) -> void:
	_strays = PackedInt32Array()
	var on := PackedByteArray()
	on.resize(big_width * big_height)
	for p in _drawn_points.pixels:
		on[p] = 1
	var nearest: PackedInt32Array = PixelCanvas.distances(on, big_width, big_height, 1)[1]
	for p in on.size():
		if on[p] == 0 and full_data[p * 4 + 3] > 0 and nearest[p] >= 0:
			_strays.append_array([p, nearest[p]])


