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
## Pixels and edges matched on each thread at least, see [method _match_round]
const PARALLEL_LEAST := 256
## How many frames' corners [method at] keeps
const AT_KEPT := 64

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
## How the triangles hold together while they're laid, each counting its weight, and the
## weights summed, three times each, see [method _lay]
var _laplacian: MeshMatrix
var _stiff_total := 0.0
## The key drawn in frames, see [method draw_from]
var _drawing: MeshDrawing
## The corners [method at] worked out, by how far along, kept for frames drawn again (at
## most [constant AT_KEPT]); frames drawn at once share them
var _at_known := {}
var _at_lock := Mutex.new()


## The mesh of [param data] laid onto [param other] (keys on canvases [param canvas_width]
## × [param canvas_height] pixels), its pieces moving as [param side] says; null when the
## key shows nothing. [param progress] tells how far it got, and stops it when cancelled.
## [param colors] are the keys' colours (see [method key_colors]), worked out when not
## given.
static func lay(
	data: PackedByteArray,
	other: PackedByteArray,
	canvas_width: int,
	canvas_height: int,
	side: KeySide,
	progress: WorkProgress = null,
	colors: MeshTools.Colors = null
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
	var located := mesh.locate(MeshTools.shown_points(data, canvas_width, 128), 1)
	if located.pixels.is_empty():
		return null
	mesh._depths(side)
	var corner_pieces := mesh._split(side)
	mesh._anchor(side, corner_pieces)
	# How the triangles hold together, the same for every round of laying them
	mesh._laplacian = MeshMatrix.new(mesh.rest.size(), mesh._side_from, mesh._side_to)
	mesh._add_laplacian(mesh._laplacian, mesh.weights, 0.0)
	for k in mesh.weights.size():
		mesh._stiff_total += mesh.weights[k] * 3.0
	mesh._follow_pieces(located, side, corner_pieces)
	if colors == null:
		var both := key_colors(data, other, canvas_width, canvas_height)
		colors = MeshTools.Colors.new()
		colors.own = both[0]
		colors.other = both[1]
		colors.own_edges = both[2]
		colors.other_edges = both[3]
	for r in REACHES.size():
		if progress and progress.cancelled:
			return null
		mesh._match_round(colors, located, REACHES[r] * unit, STIFFNESS[r])
		if progress:
			progress.advance()
	mesh._find_turns()
	return mesh


## Keys [param first] and [param second] (on canvases [param canvas_width] ×
## [param canvas_height] pixels) premultiplied, and their edges, see [MeshTools.Colors]:
## [code][first's colours, second's, first's edges, second's][/code]
static func key_colors(
	first: PackedByteArray, second: PackedByteArray, canvas_width: int, canvas_height: int
) -> Array:
	var first_colors := MeshTools.premultiplied(first)
	var second_colors := MeshTools.premultiplied(second)
	return [
		first_colors,
		second_colors,
		MeshTools.edges(first_colors, canvas_width, canvas_height, EDGE_STEP),
		MeshTools.edges(second_colors, canvas_width, canvas_height, EDGE_STEP),
	]


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
	# Only where the key shows anything, as it's nothing elsewhere
	var used := MeshTools.used_rect(data, width)
	for row in range(used.position.y, used.end.y):
		for p in range(row * width + used.position.x, row * width + used.end.x):
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
	for row in range(used.position.y, used.end.y):
		for p in range(row * width + used.position.x, row * width + used.end.x):
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
	var sides := PixelParts.sides_of(width)
	for row in range(used.position.y, used.end.y):
		for p in range(row * width + used.position.x, row * width + used.end.x):
			if shown[p] == 0:
				continue
			for side in sides:
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
	# The pixel at each triangle's middle, and the nearest pixel of a piece to it, worked out
	# round the pieces' pixels and those middles only, which gives what the whole canvas
	# would there (see PixelCanvas.distances)
	var middles := PackedInt32Array()
	var low := Vector2i(width, height)
	var high := Vector2i(-1, -1)
	for k in range(0, triangles.size(), 3):
		var middle := (rest[triangles[k]] + rest[triangles[k + 1]] + rest[triangles[k + 2]]) / 3.0
		var spot := Vector2i(
			clampi(floori(middle.x), 0, width - 1), clampi(floori(middle.y), 0, height - 1)
		)
		middles.append(spot.y * width + spot.x)
		low = low.min(spot)
		high = high.max(spot)
	var drawing := side.drawing
	for p in mini(width * height, drawing.size()):
		if drawing[p] >= 0:
			var spot := Vector2i(p % width, p / width)
			low = low.min(spot)
			high = high.max(spot)
	var area := Rect2i(low, high - low + Vector2i.ONE)
	var labelled := PackedByteArray()
	labelled.resize(area.get_area())
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if p < drawing.size() and drawing[p] >= 0:
				labelled[(y - low.y) * area.size.x + x - low.x] = 1
	var nearest: PackedInt32Array = (
		PixelCanvas.distances(labelled, area.size.x, area.size.y, 1, (width + height) * 4)[1]
	)
	var copies := {}
	var first := {}
	var corners := PackedVector2Array()
	var pieces := PackedInt32Array()
	for k in range(0, triangles.size(), 3):
		var middle := middles[k / 3]
		var q := nearest[(middle / width - low.y) * area.size.x + middle % width - low.x]
		if q >= 0:
			q = (q / area.size.x + low.y) * width + q % area.size.x + low.x
		var piece := drawing[q] if q >= 0 else -1
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


## Where each of [param points] (on a canvas [param canvas] pixels, [param scale] times
## as big as the one worked out, give or take a few pixels; just that much bigger when
## not given) is in the triangles where they rest: the triangle it's in, or the nearest,
## and how far along each of its corners
func locate(
	points: PackedVector2Array, scale: int, canvas := Vector2i.ZERO
) -> MeshTools.Located:
	if canvas == Vector2i.ZERO:
		canvas = Vector2i(width, height) * scale
	var big_width := canvas.x
	var big_height := canvas.y
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
	var drawing := side.drawing
	for p in mini(depth.size(), drawing.size()):
		var r := drawing[p]
		if r >= 0 and r < rank.size():
			depth[p] = rank[r]


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
		PIECE_STIFFNESS, PIECE_ROUNDS)


## A round of matching the key's pixels ([param located]) to the other key's (both in
## [param colors]), each looking up to [param reach] pixels round where it landed, then
## laying the triangles where the matches pull, as rigidly as [param stiffness] says
func _match_round(
	colors: MeshTools.Colors, located: MeshTools.Located, reach: float, stiffness: float
) -> void:
	var matching := MeshMatching.new(
		colors, located, _triangle_turns(target), located.at(target, triangles), reach, self
	)
	# Each pixel looks for its match on its own, and each edge for its pixel, so they're
	# shared out among threads
	var goals := PackedVector2Array()
	var pulls := PackedFloat32Array()
	var count := located.pixels.size()
	goals.resize(count)
	pulls.resize(count)
	matching.all_pixel_matches(goals, pulls, PARALLEL_LEAST)
	var edge_samples := PackedInt32Array()
	var edge_goals := PackedVector2Array()
	var edge_pulls := PackedFloat32Array()
	var edges := matching.edges.size()
	for part: Array in Parallel.split(edges, PARALLEL_LEAST, matching.edge_pulls):
		edge_samples.append_array(part[0])
		edge_goals.append_array(part[1])
		edge_pulls.append_array(part[2])
	_lay(located, goals, pulls, edge_samples, edge_goals, edge_pulls, stiffness, INNER_ROUNDS)


## Lays the triangles as rigidly as [param stiffness] says (each counting its weight), the
## pixels of [param located] pulled to [param goals] by [param pulls], and the ones
## [param extra] says to [param extra_goals] by [param extra_pulls], [param rounds] times
## turning the triangles and laying them again
func _lay(
	located: MeshTools.Located,
	goals: PackedVector2Array,
	pulls: PackedFloat32Array,
	extra: PackedInt32Array,
	extra_goals: PackedVector2Array,
	extra_pulls: PackedFloat32Array,
	stiffness: float,
	rounds: int
) -> void:
	if NativeKernels.kernels:
		NativeKernels.lay(
			self, located, goals, pulls, extra, extra_goals, extra_pulls, stiffness, rounds
		)
		return
	var n := rest.size()
	var matrix := MeshMatrix.new(n, _side_from, _side_to)
	var data_side := PackedVector2Array()
	data_side.resize(n)
	var pulled := 0.0
	for s in located.pixels.size():
		pulled += pulls[s]
	matrix.add_pulls(
		triangles, _triangle_sides, located, PackedInt32Array(), goals, pulls, data_side
	)
	for e in extra.size():
		pulled += extra_pulls[e]
	matrix.add_pulls(
		triangles, _triangle_sides, located, extra, extra_goals, extra_pulls, data_side
	)
	var scale := stiffness * pulled / maxf(_stiff_total, 1e-9) * 3.0
	matrix.add_scaled(_laplacian, scale)
	matrix.add_diagonal(1e-6)
	for _round in rounds:
		var turns := _triangle_turns(target)
		var wanted := _pulls(turns, PackedFloat32Array(), weights, 1.0)
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
	var k := located.triangles[s] * 3
	var w := located.weights[s]
	var diagonal := matrix.diagonal
	var sides := matrix.sides
	# Each corner, and the side from it to the next round
	var i := triangles[k]
	diagonal[i] += pull * w.x * w.x
	right[i] += goal * (pull * w.x)
	sides[_triangle_sides[k]] += pull * w.x * w.y
	i = triangles[k + 1]
	diagonal[i] += pull * w.y * w.y
	right[i] += goal * (pull * w.y)
	sides[_triangle_sides[k + 1]] += pull * w.y * w.z
	i = triangles[k + 2]
	diagonal[i] += pull * w.z * w.z
	right[i] += goal * (pull * w.z)
	sides[_triangle_sides[k + 2]] += pull * w.z * w.x


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
	_at_lock.lock()
	var known: Variant = _at_known.get(t)
	_at_lock.unlock()
	if known != null:
		return (known as PackedVector2Array).duplicate()
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
	_at_lock.lock()
	if _at_known.size() >= AT_KEPT:
		_at_known.clear()
	_at_known[t] = positions.duplicate()
	_at_lock.unlock()
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
## worked out, on a canvas [param full_width] pixels wide: the one worked out that much
## bigger, give or take a few pixels (see [MeshDrawing]). Call before [method drawn], once.
func draw_from(full_data: PackedByteArray, scale: int, full_width: int) -> void:
	_drawing = MeshDrawing.new(self, full_data, scale, full_width)


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
	return _drawing.drawn(self, t, pin_from, pin_to)
