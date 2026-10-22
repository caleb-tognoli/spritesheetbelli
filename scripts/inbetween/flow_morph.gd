class_name FlowMorph
extends RefCounted
## In-betweens of painted keys with soft edges, see [PieceMorph]: every pixel of each key
## is followed to where it went in the other key, neighbouring pixels moving alike (see
## [method between]). Frames show each key's pixels moved part of the way, as little
## squares stretched between their neighbours so nothing tears, and the two keys combined:
## the outline is morphed between theirs and each pixel takes its colour from the key
## nearer in time first. Every pixel is taken from a key, so no new colours appear.
##
## Pixels are matched by their colour, how opaque they are and how far inside the outline
## they are, over a small patch round them, so flat areas of one colour still line up.
## The movements are found on a small copy of the keys first, looking far, then made
## finer a size at a time, looking near what was found; each time neighbours tell each
## other where they'd go until they agree (loopy belief propagation, Felzenszwalb and
## Huttenlocher, 2006).

## Keys are matched at most about this many pixels across, then the movements are spread
## smoothly over their pixels
const ANALYSIS_SIZE := 60.0
## The smallest copy of the keys, where the search starts, is about this many pixels across
const COARSEST_SIZE := 16.0
## On the smallest copy each pixel looks this share of the sprite's size away, each way
const SEARCH_SHARE := 0.4
## On each bigger copy, each pixel looks this many pixels round what the smaller one found
const REFINE_REACH := 2
## Pixels are compared over a square patch this many pixels round them
const PATCH := 3
## What moving one pixel differently from a neighbour costs, against a patch's average
## difference (0 to 5, see [constant FEATURE_CUT]); differences past [constant SMOOTH_CUT]
## pixels cost no more, so parts can move apart
const SMOOTHNESS := 0.5
const SMOOTH_CUT := 20.0
## Rounds of neighbours telling each other where they'd go
const ROUNDS := 8
## Movements or pixels worked out on each thread at least, see [method _match]
const PARALLEL_LEAST := 16
## Keys and frames at least this many pixels are worked on by several threads at once, see
## [method frame]
const PARALLEL_PIXELS := 20000
## How much a pixel's colour (red, green and blue times opacity), opacity and depth can each
## differ at most (0 to 1)
const FEATURE_CUT := 1.0
## How far inside or outside the outline counts for depth, in pixels, and how much it counts
const DEPTH_REACH := 5.0
const DEPTH_WEIGHT := 0.4
## Pixels this opaque at least (0 to 1) are matched
const MATCHED_ALPHA := 0.1
## Keys count as soft-edged when this share of the pixels round their outline are partly
## see-through: nearly all of them in painted keys, none in pixel art
const SOFT_SHARE := 0.5
## Faint pixels of the nearer key just outside the morphed outline, up to this many pixels
## out, stay, so soft edges stay soft
const FAINT_REACH := 1.5
## A stretched pixel is drawn this many pixels across at most
const MOST_STRETCH := 8
## Pixels this opaque at least (0 to 255) count as shown when frames are tidied up, see
## [PixelCleanup]
const TIDY_ALPHA := 128
## Numbers worked out for each pixel matched: colour (3), opacity and depth
const FEATURES := 5
## How far outside a pixel's square (in pixels times its sides) a point still counts as in
## it, see [method _moved]
const CLOSE := 1e-4

## The canvas both keys are on
var width := 0
var height := 0
## The keys' RGBA bytes
var a_data := PackedByteArray()
var b_data := PackedByteArray()
## How far each pixel of key A goes to key B, and of B to A
var a_flow := PackedVector2Array()
var b_flow := PackedVector2Array()
## How far each key's pixels are from coming back where they were by the other key's
## movements: where pixels overlap as they move, the surest are drawn on top
var a_doubt := PackedFloat32Array()
var b_doubt := PackedFloat32Array()
## How often each 3 × 3 and 5 × 5 shape of what's shown happens in the keys, for smoothing
## jags out of frames, see [method PixelCleanup.smooth_jags]
var key_shapes := PackedInt32Array()
var key_wide_shapes := {}
## Where either key shows any pixel
var _keys_area := Rect2i()


## Whether keys [param a] and [param b] (RGBA8 images) are painted with soft edges: most
## of the pixels round their outline partly see-through, see [constant SOFT_SHARE]
static func soft(a: Image, b: Image) -> bool:
	var edge := 0
	var partly := 0
	for img: Image in [a, b]:
		var data: PackedByteArray = img.get_data()
		var w: int = img.get_width()
		var h: int = img.get_height()
		for y in h:
			for x in w:
				var p := y * w + x
				var alpha := data[p * 4 + 3]
				if alpha == 0:
					continue
				# On the outline: next to a clear pixel or the image's edge
				if (
					x == 0
					or y == 0
					or x == w - 1
					or y == h - 1
					or data[(p - 1) * 4 + 3] == 0
					or data[(p + 1) * 4 + 3] == 0
					or data[(p - w) * 4 + 3] == 0
					or data[(p + w) * 4 + 3] == 0
				):
					edge += 1
					if alpha < 255:
						partly += 1
	return edge > 0 and partly >= edge * SOFT_SHARE


## Keys [param a_bytes] and [param b_bytes], RGBA bytes on a canvas [param canvas_width] ×
## [param canvas_height] pixels, matched pixel by pixel, the whole sprite moving by
## [param shift] from A to B (see [method SpriteMotion.detect]). Null when either key
## shows nothing or [param progress] is cancelled.
static func between(
	a_bytes: PackedByteArray,
	b_bytes: PackedByteArray,
	canvas_width: int,
	canvas_height: int,
	shift: Vector2,
	progress: WorkProgress = null
) -> FlowMorph:
	if progress == null:
		progress = WorkProgress.new()
	var low := Vector2i(canvas_width, canvas_height)
	var high := Vector2i(-1, -1)
	for data: PackedByteArray in [a_bytes, b_bytes]:
		for p in canvas_width * canvas_height:
			if data[p * 4 + 3] > 0:
				var at := Vector2i(p % canvas_width, p / canvas_width)
				low = low.min(at)
				high = high.max(at)
	if high.x < 0:
		return null
	var size := float(maxi(high.x - low.x, high.y - low.y) + 1)
	var morph := FlowMorph.new()
	morph._keys_area = Rect2i(low, high - low + Vector2i.ONE)
	morph.width = canvas_width
	morph.height = canvas_height
	morph.a_data = a_bytes
	morph.b_data = b_bytes
	var zoom := maxi(1, ceili(size / ANALYSIS_SIZE))
	var zooms: Array[int] = [zoom]
	while size / zooms[-1] > COARSEST_SIZE * 1.5:
		zooms.append(zooms[-1] * 2)
	progress.total += zooms.size() * 2
	var a_level: FlowLevel
	var b_level: FlowLevel
	var a_moves := PackedVector2Array()
	var b_moves := PackedVector2Array()
	for k in range(zooms.size() - 1, -1, -1):
		var z := zooms[k]
		a_level = FlowLevel.new(a_bytes, canvas_width, canvas_height, z)
		b_level = FlowLevel.new(b_bytes, canvas_width, canvas_height, z)
		if a_moves.is_empty():
			var start := (shift / z).round()
			var reach := ceili(SEARCH_SHARE * size / z)
			a_moves = _match(a_level, b_level, _filled(start, a_level), reach, false)
			b_moves = _match(b_level, a_level, _filled(-start, b_level), reach, false)
		else:
			var a_start := _doubled(a_moves, a_level)
			var b_start := _doubled(b_moves, b_level)
			a_moves = _match(a_level, b_level, a_start, REFINE_REACH, true)
			b_moves = _match(b_level, a_level, b_start, REFINE_REACH, true)
		if a_moves.is_empty() or b_moves.is_empty():
			return null
		progress.done += 2
		if progress.cancelled:
			return null
	morph.a_flow = _enlarged(a_moves, a_level, canvas_width, canvas_height)
	morph.b_flow = _enlarged(b_moves, b_level, canvas_width, canvas_height)
	morph.a_doubt = morph._doubts(morph.a_flow, morph.b_flow)
	morph.b_doubt = morph._doubts(morph.b_flow, morph.a_flow)
	morph.key_shapes = PixelCleanup.shapes_of(a_bytes, canvas_width, canvas_height, TIDY_ALPHA)
	var b_shapes := PixelCleanup.shapes_of(b_bytes, canvas_width, canvas_height, TIDY_ALPHA)
	for k in b_shapes.size():
		morph.key_shapes[k] += b_shapes[k]
	for data: PackedByteArray in [a_bytes, b_bytes]:
		morph.key_wide_shapes.merge(
			PixelCleanup.wide_shapes_of(data, canvas_width, canvas_height, TIDY_ALPHA)
		)
	return morph


## The frame [param t] of the way from key A to key B, RGBA bytes on the canvas. Each key's
## pixels are moved that far along; where the two differ, the outline is morphed between
## theirs (by how far inside or outside each a pixel is, the key nearer in time counting
## more), what the nearer key shows stays, and each pixel takes its colour from the nearer
## key, else the other, else the nearest pixel the nearer one shows. Stray pixels, pinholes
## and jags the keys don't have are tidied away, see [PixelCleanup]. Pins moving points at
## [param pin_from] (on the canvas, halfway) to [param pin_to] bend both keys' movements,
## see [method _pinned].
func frame(
	t: float, pin_from := PackedVector2Array(), pin_to := PackedVector2Array()
) -> PackedByteArray:
	# Both keys moved at once, on threads of their own for big keys
	var big := _keys_area.get_area() >= PARALLEL_PIXELS
	var move := func(k: int) -> PackedByteArray:
		var data := a_data if k == 0 else b_data
		var flow := a_flow if k == 0 else b_flow
		var along := t if k == 0 else 1.0 - t
		var doubt := a_doubt if k == 0 else b_doubt
		return _moved(data, _pinned(data, flow, along, pin_from, pin_to), doubt, along)
	var moved := Parallel.each(2, move, big)
	var from_a: PackedByteArray = moved[0]
	var from_b: PackedByteArray = moved[1]
	# Put together round what the moved keys show only, which gives what the whole canvas
	# would (see PixelCanvas.distances), with room for tidying up to grow it
	var far_away := (width + height) * 4
	var area := PixelCanvas.shown_rect_of(from_a, from_b, width, height, PieceMorph.AREA_MARGIN)
	from_a = PixelCanvas.region(from_a, width, area)
	from_b = PixelCanvas.region(from_b, width, area)
	var w := area.size.x
	var h := area.size.y
	var count := w * h
	var near_first := t <= 0.5
	var near := from_a if near_first else from_b
	var far := from_b if near_first else from_a
	var a_mask := _mask(from_a)
	var b_mask := _mask(from_b)
	# How far from each moved key's pixels and from the rest each pixel is, all at once on
	# threads of their own for big frames
	var masks: Array[PackedByteArray] = [a_mask, a_mask, b_mask, b_mask]
	var measure := func(k: int) -> Array[PackedInt32Array]:
		return PixelCanvas.distances(masks[k], w, h, 1 - k % 2, far_away)
	var measured := Parallel.each(4, measure, count >= PARALLEL_PIXELS)
	var a_to: Array[PackedInt32Array] = measured[0]
	var b_to: Array[PackedInt32Array] = measured[2]
	var a_sides := FlowLevel.sides_from(a_mask, a_to[0], measured[1][0])
	var b_sides := FlowLevel.sides_from(b_mask, b_to[0], measured[3][0])
	var near_mask := a_mask if near_first else b_mask
	var far_mask := b_mask if near_first else a_mask
	var near_nearest: PackedInt32Array = (a_to if near_first else b_to)[1]
	var far_nearest: PackedInt32Array = (b_to if near_first else a_to)[1]
	var out := PixelCanvas.blank(count)
	for p in count:
		var from := near
		var source := p
		if near_mask[p] == 0:
			var side := a_sides[p] * (1.0 - t) + b_sides[p] * t
			if side >= 0.0:
				# Outside the morphed outline: only the nearer key's faint pixels close by
				if near[p * 4 + 3] > 0 and side < FAINT_REACH:
					for c in 4:
						out[p * 4 + c] = near[p * 4 + c]
				continue
			if far_mask[p] == 1:
				from = far
			elif near_nearest[p] >= 0:
				source = near_nearest[p]
			else:
				from = far
				source = far_nearest[p]
		if source < 0:
			continue
		for c in 4:
			out[p * 4 + c] = from[source * 4 + c]
	PixelCleanup.tidy_data(out, w, h)
	PixelCleanup.smooth_jags(out, w, h, key_shapes, TIDY_ALPHA, key_wide_shapes)
	return PixelCanvas.placed(out, area, width, height)


## [param flow], the movements of [param data]'s pixels, bent so that at [param t] of the
## way the points under the pins [param pin_from] (on the canvas, halfway between the keys)
## go towards [param pin_to] by [method PinWarp.weight] of the way: each pin follows the
## pixel showing its point halfway, and the pixels round the pins move with them as
## rigidly as they can, the rest staying, see [PinWarp.Bend]. The same [param flow] without
## pins, or at the keys.
func _pinned(
	data: PackedByteArray,
	flow: PackedVector2Array,
	t: float,
	pin_from: PackedVector2Array,
	pin_to: PackedVector2Array
) -> PackedVector2Array:
	var amount := PinWarp.weight(t)
	if pin_from.is_empty() or amount <= 0.0:
		return flow
	var froms := PackedVector2Array()
	var tos := PackedVector2Array()
	# Only where the keys show anything
	var area := _keys_area
	for k in pin_from.size():
		# Pixels' middles are at whole numbers here
		var at := pin_from[k] - Vector2(0.5, 0.5)
		var best := -1
		var nearest := INF
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var p := y * width + x
				if data[p * 4 + 3] == 0:
					continue
				var apart := (Vector2(x, y) + flow[p] * 0.5).distance_squared_to(at)
				if apart < nearest:
					nearest = apart
					best = p
		var now := at + (flow[best] * (t - 0.5) if best >= 0 else Vector2.ZERO)
		froms.append(now)
		tos.append(now + (pin_to[k] - pin_from[k]) * amount)
	# Where the pixels are at t, holding themselves still away from the pins
	var shape := PackedVector2Array()
	var shown := PackedInt32Array()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if data[p * 4 + 3] > 0:
				shape.append(Vector2(x, y) + flow[p] * t)
				shown.append(p)
	var bend := PinWarp.Bend.new(froms, tos, shape)
	# Sampled only where the pixels are
	bend.lay(width, height, shape)
	var result := flow.duplicate()
	for s in shown.size():
		result[shown[s]] += (bend.sampled(shape[s]) - shape[s]) / t
	return result


## [param data] with its pixels moved [param t] of their [param flow], each a little square
## whose corners move with the pixels sharing them, so they stretch rather than tear.
## Where squares overlap, the pixel with the least [param doubt] is on top.
func _moved(
	data: PackedByteArray, flow: PackedVector2Array, doubt: PackedFloat32Array, t: float
) -> PackedByteArray:
	if NativeKernels.kernels:
		return NativeKernels.flow_moved(self, data, flow, doubt, t)
	var out := PixelCanvas.blank(width * height)
	var best := PackedFloat32Array()
	best.resize(width * height)
	best.fill(INF)
	var last_x := width - 1
	var last_y := height - 1
	# Only where the keys show anything
	var area := _keys_area
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if data[p * 4 + 3] == 0:
				continue
			# Each corner moves as the pixels sharing it, shown, on average: the pixel itself,
			# the one beside it, the one above or below it, then the one across the corner
			var own := flow[p]
			var up := p - width
			var down := p + width
			var has_left := x > 0 and data[(p - 1) * 4 + 3] > 0
			var has_right := x < last_x and data[(p + 1) * 4 + 3] > 0
			var has_up := y > 0 and data[up * 4 + 3] > 0
			var has_down := y < last_y and data[down * 4 + 3] > 0
			var sum := own
			var n := 1
			if has_left:
				sum += flow[p - 1]
				n += 1
			if has_up:
				sum += flow[up]
				n += 1
			if x > 0 and y > 0 and data[(up - 1) * 4 + 3] > 0:
				sum += flow[up - 1]
				n += 1
			var c0 := Vector2(x - 0.5, y - 0.5) + sum * (t / n)
			sum = own
			n = 1
			if has_right:
				sum += flow[p + 1]
				n += 1
			if has_up:
				sum += flow[up]
				n += 1
			if x < last_x and y > 0 and data[(up + 1) * 4 + 3] > 0:
				sum += flow[up + 1]
				n += 1
			var c1 := Vector2(x + 0.5, y - 0.5) + sum * (t / n)
			sum = own
			n = 1
			if has_right:
				sum += flow[p + 1]
				n += 1
			if has_down:
				sum += flow[down]
				n += 1
			if x < last_x and y < last_y and data[(down + 1) * 4 + 3] > 0:
				sum += flow[down + 1]
				n += 1
			var c2 := Vector2(x + 0.5, y + 0.5) + sum * (t / n)
			sum = own
			n = 1
			if has_left:
				sum += flow[p - 1]
				n += 1
			if has_down:
				sum += flow[down]
				n += 1
			if x > 0 and y < last_y and data[(down - 1) * 4 + 3] > 0:
				sum += flow[down - 1]
				n += 1
			var c3 := Vector2(x - 0.5, y + 0.5) + sum * (t / n)
			var lowest := c0.min(c1).min(c2.min(c3))
			var highest := c0.max(c1).max(c2.max(c3))
			var x0 := maxi(0, floori(lowest.x))
			var y0 := maxi(0, floori(lowest.y))
			var x1 := mini(mini(last_x, ceili(highest.x)), x0 + MOST_STRETCH)
			var y1 := mini(mini(last_y, ceili(highest.y)), y0 + MOST_STRETCH)
			var own_doubt := doubt[p]
			# The square as two triangles, c0 c1 c2 and c0 c2 c3: a point is in one when it's
			# on the same side of its three sides, either way round, or on them
			var side_01 := c1 - c0
			var side_12 := c2 - c1
			var side_20 := c0 - c2
			var side_02 := c2 - c0
			var side_23 := c3 - c2
			var side_30 := c0 - c3
			var i := p * 4
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					var q := py * width + px
					if own_doubt > best[q]:
						continue
					var at := Vector2(px, py)
					var d1 := side_01.cross(at - c0)
					var d2 := side_12.cross(at - c1)
					var d3 := side_20.cross(at - c2)
					if not (
						(d1 >= -CLOSE and d2 >= -CLOSE and d3 >= -CLOSE)
						or (d1 <= CLOSE and d2 <= CLOSE and d3 <= CLOSE)
					):
						d1 = side_02.cross(at - c0)
						d2 = side_23.cross(at - c2)
						d3 = side_30.cross(at - c3)
						if not (
							(d1 >= -CLOSE and d2 >= -CLOSE and d3 >= -CLOSE)
							or (d1 <= CLOSE and d2 <= CLOSE and d3 <= CLOSE)
						):
							continue
					best[q] = own_doubt
					out[q * 4] = data[i]
					out[q * 4 + 1] = data[i + 1]
					out[q * 4 + 2] = data[i + 2]
					out[q * 4 + 3] = data[i + 3]
	return out


## 1 where [param data] is shown, at least half opaque
static func _mask(data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data.size() / 4)
	for p in result.size():
		result[p] = 1 if data[p * 4 + 3] >= 128 else 0
	return result


## How far each pixel's [param flow] is from coming back by the other key's [param back]
func _doubts(flow: PackedVector2Array, back: PackedVector2Array) -> PackedFloat32Array:
	var doubts := PackedFloat32Array()
	doubts.resize(flow.size())
	for y in height:
		for x in width:
			var p := y * width + x
			var to := (Vector2(x, y) + flow[p]).round()
			var q := clampi(int(to.y), 0, height - 1) * width + clampi(int(to.x), 0, width - 1)
			var off := flow[p] + back[q]
			doubts[p] = absf(off.x) + absf(off.y)
	return doubts


## Every pixel of [param level] moving by [param move]
static func _filled(move: Vector2, level: FlowLevel) -> PackedVector2Array:
	var moves := PackedVector2Array()
	moves.resize(level.width * level.height)
	moves.fill(move)
	return moves


## [param moves] of the level half the size of [param level], for its pixels
static func _doubled(moves: PackedVector2Array, level: FlowLevel) -> PackedVector2Array:
	var small_width := ceili(level.full_width / (level.zoom * 2.0))
	var small_height := moves.size() / small_width
	var result := PackedVector2Array()
	result.resize(level.width * level.height)
	for y in level.height:
		for x in level.width:
			var from := mini(y / 2, small_height - 1) * small_width + mini(x / 2, small_width - 1)
			result[y * level.width + x] = moves[from] * 2.0
	return result


## [param moves] of [param level], spread smoothly over the pixels of the whole canvas
static func _enlarged(
	moves: PackedVector2Array, level: FlowLevel, full_width: int, full_height: int
) -> PackedVector2Array:
	var z := level.zoom
	if z == 1:
		return moves
	moves = _spread(moves, level)
	var w := level.width
	var result := PackedVector2Array()
	result.resize(full_width * full_height)
	for y in full_height:
		var sy := clampf((y + 0.5) / z - 0.5, 0.0, level.height - 1.0)
		var y0 := floori(sy)
		var y1 := mini(y0 + 1, level.height - 1)
		var fy := sy - y0
		for x in full_width:
			var sx := clampf((x + 0.5) / z - 0.5, 0.0, w - 1.0)
			var x0 := floori(sx)
			var x1 := mini(x0 + 1, w - 1)
			var fx := sx - x0
			var top := moves[y0 * w + x0].lerp(moves[y0 * w + x1], fx)
			var bottom := moves[y1 * w + x0].lerp(moves[y1 * w + x1], fx)
			result[y * full_width + x] = top.lerp(bottom, fy) * z
	return result


## [param moves] with each pixel [param level] doesn't match taking the nearest matched
## one's
static func _spread(moves: PackedVector2Array, level: FlowLevel) -> PackedVector2Array:
	var nearest: PackedInt32Array = (
		PixelCanvas.distances(level.matched, level.width, level.height, 1)[1]
	)
	var result := moves.duplicate()
	for p in moves.size():
		if level.matched[p] == 0 and nearest[p] >= 0:
			result[p] = moves[nearest[p]]
	return result


## Where each pixel of [param from] goes in [param to] (levels the same size): each looks
## [param reach] pixels round where [param start] says (first spread to the pixels not
## matched and smoothed when [param refining]), neighbours agreeing as they can. Empty
## when [param from] matches no pixel.
static func _match(
	from: FlowLevel, to: FlowLevel, start: PackedVector2Array, reach: int, refining: bool
) -> PackedVector2Array:
	var w := from.width
	var h := from.height
	if refining:
		start = _median(_spread(start, from), w, h)
	var guess := PackedInt32Array()
	guess.resize(w * h * 2)
	for p in w * h:
		guess[p * 2] = roundi(start[p].x)
		guess[p * 2 + 1] = roundi(start[p].y)
	# The pixels matched, and the area their patches cover
	var nodes := PackedInt32Array()
	var node_of := PackedInt32Array()
	node_of.resize(w * h)
	node_of.fill(-1)
	var low := Vector2i(w, h)
	var high := Vector2i(-1, -1)
	for p in w * h:
		if from.matched[p] == 1:
			node_of[p] = nodes.size()
			nodes.append(p)
			low = low.min(Vector2i(p % w, p / w))
			high = high.max(Vector2i(p % w, p / w))
	if nodes.is_empty():
		return PackedVector2Array()
	var x0 := maxi(0, low.x - PATCH)
	var y0 := maxi(0, low.y - PATCH)
	var area := Rect2i(
		x0, y0, mini(w - 1, high.x + PATCH) - x0 + 1, mini(h - 1, high.y + PATCH) - y0 + 1
	)
	var side := 2 * reach + 1
	var labels := side * side
	var costs := PackedFloat32Array()
	costs.resize(nodes.size() * labels)
	# Each movement's costs on their own, so they're shared out among threads, each writing
	# only its own
	var label_costs := _label_costs.bind(from, to, guess, nodes, area, reach, costs)
	Parallel.split(labels, PARALLEL_LEAST, label_costs)
	var chosen := _agree(costs, nodes, node_of, w, h, side)
	var moves := PackedVector2Array()
	moves.resize(w * h)
	for p in w * h:
		moves[p] = Vector2(guess[p * 2], guess[p * 2 + 1])
	for n in nodes.size():
		moves[nodes[n]] += Vector2(chosen[n] % side - reach, chosen[n] / side - reach)
	return moves


## Writes into [param costs] (see [method _match]) what moving each of [param nodes] of
## [param from] by labels [param start] to [param end] (past the last) round its
## [param guess], up to [param reach] each way, costs: how unlike [param to] its patch is
## there, over [param area], the part of [param from] the patches cover
static func _label_costs(
	start: int,
	end: int,
	from: FlowLevel,
	to: FlowLevel,
	guess: PackedInt32Array,
	nodes: PackedInt32Array,
	area: Rect2i,
	reach: int,
	costs: PackedFloat32Array
) -> void:
	var w := from.width
	var h := from.height
	var x0 := area.position.x
	var y0 := area.position.y
	var area_width := area.size.x
	var area_height := area.size.y
	var stride := area_width + 1
	var side := 2 * reach + 1
	var labels := side * side
	# Differences summed over the area from its top left, for patch sums
	var summed := PackedFloat32Array()
	summed.resize(stride * (area_height + 1))
	var window := float((2 * PATCH + 1) * (2 * PATCH + 1))
	var f_from := from.features
	var f_to := to.features
	var empty_0: float = FlowLevel.EMPTY[0]
	var empty_1: float = FlowLevel.EMPTY[1]
	var empty_2: float = FlowLevel.EMPTY[2]
	var empty_3: float = FlowLevel.EMPTY[3]
	var empty_4: float = FlowLevel.EMPTY[4]
	for label in range(start, end):
		var lx := label % side - reach
		var ly := label / side - reach
		for ay in area_height:
			var row := 0.0
			var y := y0 + ay
			for ax in area_width:
				var x := x0 + ax
				var p := y * w + x
				var tx := x + guess[p * 2] + lx
				var ty := y + guess[p * 2 + 1] + ly
				var i := p * FEATURES
				var d := 0.0
				if tx < 0 or ty < 0 or tx >= w or ty >= h:
					d += minf(absf(f_from[i] - empty_0), FEATURE_CUT)
					d += minf(absf(f_from[i + 1] - empty_1), FEATURE_CUT)
					d += minf(absf(f_from[i + 2] - empty_2), FEATURE_CUT)
					d += minf(absf(f_from[i + 3] - empty_3), FEATURE_CUT)
					d += minf(absf(f_from[i + 4] - empty_4), FEATURE_CUT)
				else:
					var j := (ty * w + tx) * FEATURES
					d += minf(absf(f_from[i] - f_to[j]), FEATURE_CUT)
					d += minf(absf(f_from[i + 1] - f_to[j + 1]), FEATURE_CUT)
					d += minf(absf(f_from[i + 2] - f_to[j + 2]), FEATURE_CUT)
					d += minf(absf(f_from[i + 3] - f_to[j + 3]), FEATURE_CUT)
					d += minf(absf(f_from[i + 4] - f_to[j + 4]), FEATURE_CUT)
				row += d
				var s := (ay + 1) * stride + ax + 1
				summed[s] = summed[s - stride] + row
		for n in nodes.size():
			var px := nodes[n] % w - x0
			var py := nodes[n] / w - y0
			var left := maxi(0, px - PATCH)
			var top := maxi(0, py - PATCH)
			var right := mini(area_width, px + PATCH + 1)
			var bottom := mini(area_height, py + PATCH + 1)
			var sum := (
				summed[bottom * stride + right]
				- summed[top * stride + right]
				- summed[bottom * stride + left]
				+ summed[top * stride + left]
			)
			costs[n * labels + label] = sum / window


## The label each node settles on, of [param side] × [param side] (movements round its
## guess) with [param costs] for each: loopy min-sum belief propagation between the 4
## neighbours, moving differently from a neighbour costing [constant SMOOTHNESS] a pixel,
## up to [constant SMOOTH_CUT] pixels
static func _agree(
	costs: PackedFloat32Array,
	nodes: PackedInt32Array,
	node_of: PackedInt32Array,
	w: int,
	h: int,
	side: int
) -> PackedInt32Array:
	var count := nodes.size()
	var labels := side * side
	# Neighbours left, right, up and down
	var neighbours := PackedInt32Array()
	neighbours.resize(count * 4)
	for n in count:
		var p := nodes[n]
		neighbours[n * 4] = node_of[p - 1] if p % w > 0 else -1
		neighbours[n * 4 + 1] = node_of[p + 1] if p % w < w - 1 else -1
		neighbours[n * 4 + 2] = node_of[p - w] if p / w > 0 else -1
		neighbours[n * 4 + 3] = node_of[p + w] if p / w < h - 1 else -1
	# What each node heard from each side
	var heard := PackedFloat32Array()
	heard.resize(count * 4 * labels)
	for _round in ROUNDS:
		# Each node tells its neighbours on its own, so they're shared out among threads,
		# each writing only what its nodes tell
		var next := PackedFloat32Array()
		next.resize(count * 4 * labels)
		Parallel.split(count, PARALLEL_LEAST, _tell.bind(costs, heard, next, neighbours, side))
		heard = next
	var chosen := PackedInt32Array()
	chosen.resize(count)
	for n in count:
		var at := n * 4 * labels
		var best := INF
		for k in labels:
			var belief := (
				costs[n * labels + k]
				+ heard[at + k]
				+ heard[at + labels + k]
				+ heard[at + 2 * labels + k]
				+ heard[at + 3 * labels + k]
			)
			if belief < best:
				best = belief
				chosen[n] = k
	return chosen


## Writes into [param next] what nodes [param start] to [param end] (past the last) tell
## their [param neighbours] in a round of [method _agree], from their [param costs] and what
## they [param heard], of [param side] × [param side] labels
static func _tell(
	start: int,
	end: int,
	costs: PackedFloat32Array,
	heard: PackedFloat32Array,
	next: PackedFloat32Array,
	neighbours: PackedInt32Array,
	side: int
) -> void:
	var labels := side * side
	var total := PackedFloat32Array()
	total.resize(labels)
	var message := PackedFloat32Array()
	message.resize(labels)
	var cut := SMOOTHNESS * SMOOTH_CUT
	for n in range(start, end):
		var base := n * labels
		var at := n * 4 * labels
		for k in labels:
			total[k] = (
				costs[base + k]
				+ heard[at + k]
				+ heard[at + labels + k]
				+ heard[at + 2 * labels + k]
				+ heard[at + 3 * labels + k]
			)
		for to_side in 4:
			var other := neighbours[n * 4 + to_side]
			if other < 0:
				continue
			# Leaving out what that neighbour said
			var own := at + to_side * labels
			for k in labels:
				message[k] = total[k] - heard[own + k]
			var top := _spread_costs(message, side) + cut
			var settled := INF
			for k in labels:
				message[k] = minf(message[k], top)
				settled = minf(settled, message[k])
			# The neighbour hears it from the opposite side
			var into := (other * 4 + (to_side ^ 1)) * labels
			for k in labels:
				next[into + k] = message[k] - settled


## Lowers each of [param costs], [param side] × [param side] labels, to the cheapest other
## label plus [constant SMOOTHNESS] for each step away; returns the lowest cost
static func _spread_costs(costs: PackedFloat32Array, side: int) -> float:
	var lowest := INF
	for k in costs.size():
		lowest = minf(lowest, costs[k])
	for row in side:
		var r := row * side
		for i in range(1, side):
			costs[r + i] = minf(costs[r + i], costs[r + i - 1] + SMOOTHNESS)
		for i in range(side - 2, -1, -1):
			costs[r + i] = minf(costs[r + i], costs[r + i + 1] + SMOOTHNESS)
	for k in range(side, costs.size()):
		costs[k] = minf(costs[k], costs[k - side] + SMOOTHNESS)
	for k in range(costs.size() - side - 1, -1, -1):
		costs[k] = minf(costs[k], costs[k + side] + SMOOTHNESS)
	return lowest


## [param moves] each the median of the 3 × 3 round it, across and down apart
static func _median(moves: PackedVector2Array, w: int, h: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(moves.size())
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(9)
	ys.resize(9)
	for y in h:
		for x in w:
			var k := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					# Past the edge counts as the edge
					var q := clampi(y + dy, 0, h - 1) * w + clampi(x + dx, 0, w - 1)
					xs[k] = moves[q].x
					ys[k] = moves[q].y
					k += 1
			xs.sort()
			ys.sort()
			result[y * w + x] = Vector2(xs[4], ys[4])
	return result
