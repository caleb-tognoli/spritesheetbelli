class_name KeySide
extends RefCounted
## One key's side: its pieces and how they move to the other key, see [PieceMorph]

## Merging regions into pieces: two touching merge while one motion for both costs them
## less than this more, per pixel of the smaller, than each its own, beyond this share
## of what their own motions already miss (noise, for painted sprites)
const MERGE_COST := 0.02
const MERGE_NOISE := 0.5
## Pieces smaller than this share of the sprite merge unless their own motion is clearly
## better for them: by this much per pixel, and this many times
const SMALL_PIECE := 0.08
const CLEARLY_BY := 0.5
const CLEARLY_TIMES := 3.0
## Pieces smaller than this share of the sprite, or than [constant TINY_PIXELS], always
## merge: a few pixels flying off on their own spoil a frame more than they help it
const TINY_PIECE := 0.02
const TINY_PIXELS := 12
## Pieces fitting the other key worse than this (see [method RegionMotions.fit_of]), and
## not fitting it at least this much better than not moving, aren't there: they don't
## move on their own, see [method KeySide.merge]
const POOR_FIT := 0.4
const HOLDING := 0.8
## Pieces this big a share of the sprite, fitting the other key worse than this many pixels
## off would (see [method RegionMotions.pixel_off]), aren't there either
const BIG_PIECE := 0.3
const BIG_OFF := 2.0
## Pieces turning more apart than this (in radians) don't merge, see [method KeySide.merge]
const TURNS_APART := 0.25
## How readily a piece is the one the others are attached to: big, and turning little
const ROOT_TURN := 0.35
## Pieces turned less than this (in radians) by a frame aren't turned at all: they move by
## whole pixels, keeping their pixels as they are
const STILL_TURN := 0.06
## A piece is bent with the whole shape (see [ShapeBlend]) rather than moved rigidly, on
## its own, when bending costs it at most this share of what its motion does, and the
## bending covers at least this share of it
const BEND_SHARE := 1.0
const MESHED_SHARE := 0.5
## Seams up to this many pixels across (times how much bigger the key is drawn than
## worked out) between pieces moving on their own and those bending are filled
const SEAM := 2
## Pieces stretched at least this much are drawn with smooth outlines, see
## [method KeySide._smooth_covering]; [constant BENDING] stands for any piece bending
const MAGNIFIED := 1.25
## Touching pieces whose motions take their pixels within this many pixels (as worked out)
## of each other are one
const ALIKE_PIXELS := 0.75
const BENDING := -2
## Merges worked out on each thread at least, see [method merge]
const MERGINGS_LEAST := 4

## The key on its canvas
var data := PackedByteArray()
## Whether the keys are painted, with many colours: pieces turned are drawn blending
## the pixels they're turned between, rather than as pixel art, see [SmoothKey]
var painted := false
var pieces: KeyRegions
## How each piece moves to the other key, all the way, and how well it fits there (see
## [method RegionMotions.fit_of])
var motions: Array[Transform2D] = []
var fits := PackedFloat32Array()
## Whether most of the key wasn't found in the other key, as when a sprite changes into
## something else: frames then show the nearer key, see [method PieceMorph.frame]
var lost := false
## The pieces not found in the other key, see [method merge]
var unfound := PackedInt32Array()
## The piece each is attached to (-1 for none), and where
var parents := PackedInt32Array()
var joints := PackedVector2Array()
## The pieces, back to front
var order := PackedInt32Array()
## The key blown up for drawing pieces turned, see [method make_smooth]
var smooth: SmoothKey
## The whole shape bending, see [ShapeBlend], and whether this is key B
var blend: ShapeBlend
var is_b := false
## 1 for each piece drawn moving rigidly on its own, 0 for those bent with the whole
## shape, see [method choose_layers]
var layered := PackedByteArray()
## 1 for each pixel the bending covers
var meshed := PackedByteArray()
## How many times bigger than the bending the key is drawn
var scale := 1
## The smoothed outlines of pieces grown much, by piece, see [method _smooth_covering]:
## worked out as frames need them, which can be drawn on several threads at once
var _outlines := {}
var _outlines_lock := Mutex.new()
## The piece each pixel is drawn with: [member KeyRegions.labels] of [member pieces],
## with faint pixels too
var drawing := PackedInt32Array()


## Merges the regions of [param follower] into pieces, see [PieceMorph]
func merge(follower: RegionMotions, width: int) -> void:
	var region_motions := follower.chosen
	var regions := follower.regions
	var count := regions.count()
	var total := 0
	for r in count:
		total += regions.pixels[r].size()
	# Each piece: its regions' pixels, its motion and what that costs it
	var members: Array[PackedInt32Array] = []
	var piece_motions: Array[Transform2D] = []
	var costs := PackedFloat32Array()
	var alive := PackedByteArray()
	var touching: Array[Dictionary] = []
	for r in count:
		members.append(regions.pixels[r])
		piece_motions.append(follower.simplest(regions.pixels[r], region_motions[r]))
		costs.append(follower.cost(r, piece_motions[r]) * regions.pixels[r].size())
		alive.append(1)
		touching.append({})
	for key in regions.borders:
		touching[key.x][key.y] = true
		touching[key.y][key.x] = true
	var owner := PackedInt32Array(range(count))
	var cache := {}
	while true:
		# What merging each two touching pieces costs, for those not worked out yet: each
		# on its own, so they're shared out among threads
		var missing: Array[Vector2i] = []
		for p in count:
			if alive[p] == 0:
				continue
			for q: int in touching[p]:
				if q > p and alive[q] == 1 and not cache.has(Vector2i(p, q)):
					missing.append(Vector2i(p, q))
		var mergings := _mergings.bind(missing, follower, members, piece_motions, costs, total)
		var found := []
		for part: Array in Parallel.split(missing.size(), MERGINGS_LEAST, mergings):
			found.append_array(part)
		for k in missing.size():
			cache[missing[k]] = found[k]
		var best := Vector3(INF, -1, -1)
		for p in count:
			if alive[p] == 0:
				continue
			for q: int in touching[p]:
				if q <= p or alive[q] == 0:
					continue
				var key := Vector2i(p, q)
				var increase: float = cache[key][0]
				if increase < best.x:
					best = Vector3(increase, p, q)
		var alike := false
		if best.y < 0 or best.x > MERGE_COST:
			# Last, pieces moving alike, so what moves as one is drawn as one
			var pair := _moving_alike(alive, touching, piece_motions, members, follower)
			if pair.x < 0:
				break
			best = Vector3(0.0, pair.x, pair.y)
			alike = true
		var p := int(best.y)
		var q := int(best.z)
		var merged: Array = cache[Vector2i(mini(p, q), maxi(p, q))]
		if alike and members[q].size() > members[p].size():
			piece_motions[p] = piece_motions[q]
		members[p] = members[p] + members[q]
		if not alike:
			piece_motions[p] = follower.refined(members[p], merged[1])
		costs[p] = follower.cost_of(members[p], piece_motions[p]) * members[p].size()
		alive[q] = 0
		for k: int in touching[q]:
			if k != p:
				touching[p][k] = true
				touching[k].erase(q)
				touching[k][p] = true
		touching[p].erase(q)
		touching[p].erase(p)
		for r in count:
			if owner[r] == q:
				owner[r] = p
		for key: Vector2i in cache.keys():
			if key.x in [p, q] or key.y in [p, q]:
				cache.erase(key)
	# Number the pieces left
	var numbers := {}
	for r in count:
		if alive[r] == 1:
			numbers[r] = numbers.size()
			var motion := follower.simplest(members[r], piece_motions[r])
			var fit := follower.fit_of(members[r], motion)
			var off := fit / maxf(follower.pixel_off(members[r]), 0.05)
			var held := Transform2D(0.0, follower.shift.round())
			var big := members[r].size() >= BIG_PIECE * total
			if (
				(fit > POOR_FIT and fit > HOLDING * follower.fit_of(members[r], held))
				or (big and off > BIG_OFF)
			):
				# Not found in the other key: moving it there fits little better than not,
				# or for a big piece, like the body, much worse than a pixel off would.
				# Likely drawn anew, it travels with the whole sprite and gives way to the
				# other key's pixels halfway.
				motion = held
				unfound.append(numbers[r])
				if members[r].size() * 2 >= total:
					lost = true
			motions.append(motion)
			fits.append(off)
	var labels := regions.labels.duplicate()
	for p in labels.size():
		if labels[p] >= 0:
			labels[p] = numbers[owner[labels[p]]]
	pieces = KeyRegions.from_labels(data, width, labels)
	drawing = _with_faint(labels, width)


## Two touching pieces, alive in [param alive], whose motions take each of their pixels
## to within [constant ALIKE_PIXELS] of each other, as a [code]Vector2i[/code] (the
## smaller first); (-1, -1) for none
static func _moving_alike(
	alive: PackedByteArray,
	touching: Array[Dictionary],
	piece_motions: Array[Transform2D],
	members: Array[PackedInt32Array],
	follower: RegionMotions
) -> Vector2i:
	for p in alive.size():
		if alive[p] == 0:
			continue
		for q: int in touching[p]:
			if q <= p or alive[q] == 0:
				continue
			var apart := 0.0
			for pixels: PackedInt32Array in [members[p], members[q]]:
				for k in range(0, pixels.size(), maxi(1, pixels.size() / 64)):
					var point := follower.regions.point_of(pixels[k])
					apart = maxf(
						apart, (piece_motions[p] * point).distance_to(piece_motions[q] * point)
					)
			if apart < ALIKE_PIXELS:
				return Vector2i(p, q)
	return Vector2i(-1, -1)


## Blows the key up for drawing its pieces turned (see [SmoothKey]), once they're merged
## (see [method merge]): only needed for drawing the key as its pieces, not bent
func make_smooth() -> void:
	smooth = SmoothKey.of(data, pieces.width, drawing)


## [param labels] with the faint pixels (less than half shown, like a glow or soft edges),
## which no region has, given to the piece of the nearest pixel that has one, so they're
## drawn with it
func _with_faint(labels: PackedInt32Array, width: int) -> PackedInt32Array:
	var height := labels.size() / width
	# Worked out round the pixels shown only, which holds every pixel with a piece, so the
	# nearest are as on the whole canvas (see PixelCanvas.distances)
	var area := PixelCanvas.shown_rect(data, width, height, 0)
	var has := PackedByteArray()
	has.resize(area.size.x * area.size.y)
	var any_faint := false
	for y in range(area.position.y, area.end.y):
		var row := (y - area.position.y) * area.size.x - area.position.x
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if labels[p] >= 0:
				has[row + x] = 1
			elif data[p * 4 + 3] > 0:
				any_faint = true
	if not any_faint:
		return labels
	var nearest := _nearest_in(has, area, width, height)
	var result := labels.duplicate()
	for y in range(area.position.y, area.end.y):
		var row := (y - area.position.y) * area.size.x - area.position.x
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if labels[p] < 0 and data[p * 4 + 3] > 0 and nearest[row + x] >= 0:
				result[p] = labels[nearest[row + x]]
	return result


## For each pixel of [param area] of a canvas [param width] × [param height] pixels, by
## its place in the area, the canvas pixel nearest it that [param has] (by place in the
## area) marks, or -1: as on the whole canvas when the area holds every pixel marked
static func _nearest_in(
	has: PackedByteArray, area: Rect2i, width: int, height: int
) -> PackedInt32Array:
	var far := (width + height) * 4
	var nearest: PackedInt32Array = PixelCanvas.distances(has, area.size.x, area.size.y, 1, far)[1]
	for i in nearest.size():
		var n := nearest[i]
		if n >= 0:
			var x := n % area.size.x + area.position.x
			nearest[i] = (n / area.size.x + area.position.y) * width + x
	return nearest


## [method _merging] for the pairs of pieces [param pairs] [param start] to [param end]
## (past the last) say, each piece having [param members], [param piece_motions] and
## [param costs], of [param total] pixels in all
static func _mergings(
	start: int,
	end: int,
	pairs: Array[Vector2i],
	follower: RegionMotions,
	members: Array[PackedInt32Array],
	piece_motions: Array[Transform2D],
	costs: PackedFloat32Array,
	total: int
) -> Array:
	var found := []
	for k in range(start, end):
		var p := pairs[k].x
		var q := pairs[k].y
		found.append(
			_merging(
				follower,
				members[p],
				members[q],
				piece_motions[p],
				piece_motions[q],
				costs[p],
				costs[q],
				total
			)
		)
	return found


## What merging pieces of [param first] and [param second] pixels costs, see [PieceMorph]:
## [code][how much worse, the motion for both][/code]
static func _merging(
	follower: RegionMotions,
	first: PackedInt32Array,
	second: PackedInt32Array,
	first_motion: Transform2D,
	second_motion: Transform2D,
	first_cost: float,
	second_cost: float,
	total: int
) -> Array:
	var both := first + second
	var best_cost := INF
	var best_motion := first_motion
	for motion: Transform2D in [first_motion, second_motion]:
		var cost := follower.cost_of(both, motion) * both.size()
		if cost < best_cost:
			best_cost = cost
			best_motion = motion
	var small := mini(first.size(), second.size())
	if small < maxf(TINY_PIECE * total, TINY_PIXELS):
		return [-1.0, best_motion]
	if small < SMALL_PIECE * total:
		# A small piece is likely noise, unless its own motion is clearly better for it
		var smaller := first if first.size() <= second.size() else second
		var own := (first_cost if first.size() <= second.size() else second_cost) / small
		var other := follower.cost_of(smaller, best_motion)
		var clearly := other - own > CLEARLY_BY and other > CLEARLY_TIMES * own
		return [1.0 if clearly else -1.0, best_motion]
	# Pieces turning unlike each other stay apart, though a turn may fit one as well, like a
	# hand, square, swinging a sword: turned with the sword, it would spin
	var turns_apart := absf(
		wrapf(RegionMotions.turn_of(first_motion) - RegionMotions.turn_of(second_motion), -PI, PI)
	)
	if turns_apart > TURNS_APART:
		return [1.0, best_motion]
	var noise := (first_cost + second_cost) / both.size()
	return [(best_cost - first_cost - second_cost) / small - MERGE_NOISE * noise, best_motion]


## The side worked out on keys [param zoom] times smaller made for the key at its size,
## [param full_data], a canvas [param width] pixels wide: each pixel of it is of the
## piece of the smaller pixel it's in, or of the nearest piece for those out of any
func enlarge(full_data: PackedByteArray, width: int, zoom: int) -> void:
	var small_width := pieces.width
	var count := full_data.size() / 4
	var height := count / width
	var labels := PackedInt32Array()
	labels.resize(count)
	labels.fill(-1)
	# Only pixels shown have pieces: worked out round them
	var area := PixelCanvas.shown_rect(full_data, width, height, 0)
	var has := PackedByteArray()
	has.resize(area.size.x * area.size.y)
	var missing := false
	for y in range(area.position.y, area.end.y):
		var row := (y - area.position.y) * area.size.x - area.position.x
		var small_row := (y / zoom) * small_width
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if full_data[p * 4 + 3] == 0:
				continue
			var small := small_row + x / zoom
			labels[p] = drawing[small] if small < drawing.size() else -1
			if labels[p] >= 0:
				has[row + x] = 1
			else:
				missing = true
	if missing:
		var nearest := _nearest_in(has, area, width, height)
		for y in range(area.position.y, area.end.y):
			var row := (y - area.position.y) * area.size.x - area.position.x
			for x in range(area.position.x, area.end.x):
				var p := y * width + x
				if full_data[p * 4 + 3] > 0 and labels[p] < 0 and nearest[row + x] >= 0:
					labels[p] = labels[nearest[row + x]]
	for r in motions.size():
		var motion := motions[r]
		motions[r] = Transform2D(motion.x, motion.y, motion.origin * zoom)
		joints[r] *= zoom
	data = full_data
	pieces = KeyRegions.from_labels(full_data, width, labels, area)
	drawing = labels
	smooth = null
	scale = zoom
	if meshed.is_empty():
		meshed.resize(count)
	else:
		# Each pixel as the smaller pixel it's in, blown up natively
		var small_height := meshed.size() / small_width
		var image := Image.create_from_data(
			small_width, small_height, false, Image.FORMAT_L8, meshed
		)
		image.resize(small_width * zoom, small_height * zoom, Image.INTERPOLATE_NEAREST)
		meshed = image.get_region(Rect2i(0, 0, width, height)).get_data()


## Works out what pieces are attached to (see [member parents]) and the order they're
## drawn in, from where they land on [param other_data], the other key
func settle(other_data: PackedByteArray) -> void:
	var count := pieces.count()
	var sizes := PackedFloat32Array()
	var root := 0
	for r in count:
		sizes.append(pieces.pixels[r].size())
		var weight := sizes[r] * exp(-absf(RegionMotions.turn_of(motions[r])) / ROOT_TURN)
		var root_turn := absf(RegionMotions.turn_of(motions[root]))
		if weight > sizes[root] * exp(-root_turn / ROOT_TURN):
			root = r
	parents.resize(count)
	parents.fill(-1)
	joints.resize(count)
	# From the root out, each piece attached along the longest border
	var reached := {root: true}
	while true:
		var best := Vector3i(-1, -1, -1)
		for key in pieces.borders:
			var length := pieces.borders[key].size()
			for pair: Vector2i in [Vector2i(key.x, key.y), Vector2i(key.y, key.x)]:
				if reached.has(pair.x) and not reached.has(pair.y) and length > best.z:
					best = Vector3i(pair.x, pair.y, length)
		if best.x < 0:
			break
		reached[best.y] = true
		parents[best.y] = best.x
		var border := pieces.borders[Vector2i(mini(best.x, best.y), maxi(best.x, best.y))]
		var middle := Vector2.ZERO
		for point in border:
			middle += point
		joints[best.y] = middle / border.size()
	# Pieces not found in the other key go along with what they're attached to, like a
	# sword drawn anew in the hand
	for r in unfound:
		if parents[r] >= 0 and not unfound.has(parents[r]):
			motions[r] = motions[parents[r]]
	order = _depth_order(other_data)


## Which pieces move rigidly on their own (see [member layered]): those whose motion
## lands them on the other key about as well as [param shape] bending does, or better,
## like a sword swung or an arm over the body; the others bend with the whole shape,
## like cloth and legs. [param follower] has how the key's pixels match the other key's.
func choose_layers(shape: ShapeBlend, b_side: bool, follower: RegionMotions) -> void:
	blend = shape
	is_b = b_side
	var count := pieces.count()
	layered.resize(count)
	layered.fill(1)
	meshed.resize(drawing.size())
	if blend == null:
		return
	# Where each pixel lands on the other key, bent
	var landing := blend.sources(1.0 if is_b else 0.0, not is_b)
	for p in drawing.size():
		meshed[p] = 1 if landing[p].x >= 0.0 else 0
	for r in count:
		var pixels := pieces.pixels[r]
		if pixels.is_empty():
			continue
		var bent := 0.0
		var moved := 0.0
		var covered := 0
		for p in pixels:
			var point := pieces.point_of(p)
			moved += minf(
				follower.features.difference(p, follower.other, motions[r] * point),
				RegionMotions.CAP
			)
			if meshed[p] == 0:
				bent += RegionMotions.CAP
				continue
			covered += 1
			bent += minf(
				follower.features.difference(p, follower.other, landing[p]), RegionMotions.CAP
			)
		if covered >= pixels.size() * MESHED_SHARE and bent < moved * BEND_SHARE:
			layered[r] = 0


## Pieces back to front: where two land on the same pixel of the other key, the one
## more like it there is in front
func _depth_order(other_data: PackedByteArray) -> PackedInt32Array:
	var count := pieces.count()
	var width := pieces.width
	var height := pieces.height
	var best_err := PackedFloat32Array()
	best_err.resize(width * height)
	best_err.fill(INF)
	var best_piece := PackedInt32Array()
	best_piece.resize(width * height)
	best_piece.fill(-1)
	var landed := PackedInt32Array()
	landed.resize(width * height)
	var landings: Array[PackedInt32Array] = []
	for r in count:
		var spots := PackedInt32Array()
		for p in pieces.pixels[r]:
			var at := motions[r] * pieces.point_of(p)
			var x := floori(at.x)
			var y := floori(at.y)
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			var q := y * width + x
			var err := 0.0
			for c in 3:
				err += absf(data[p * 4 + c] - other_data[q * 4 + c]) / 255.0
			if other_data[q * 4 + 3] < 128:
				err += 3.0
			landed[q] += 1
			spots.append(q)
			if err < best_err[q]:
				best_err[q] = err
				best_piece[q] = r
		landings.append(spots)
	var scored: Array[Vector2] = []
	for r in count:
		var score := 0
		for q in landings[r]:
			if landed[q] > 1:
				score += 1 if best_piece[q] == r else -1
		scored.append(Vector2(score, r))
	scored.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	var result := PackedInt32Array()
	for entry in scored:
		result.append(int(entry.y))
	return result


## Each piece's motion [param t] of the way: turned about the joint it's attached by,
## so attached pieces stay attached
func motions_at(t: float) -> Array[Transform2D]:
	var count := pieces.count()
	var result: Array[Transform2D] = []
	result.resize(count)
	var done := PackedByteArray()
	done.resize(count)
	for _pass in count:
		var progressed := false
		for r in count:
			if done[r] == 1:
				continue
			var parent := parents[r]
			if parent >= 0 and done[parent] == 0:
				continue
			var motion := motions[r]
			if parent < 0:
				result[r] = RegionMotions.partway(motion, pieces.centers[r], t)
			else:
				var relative := motions[parent].affine_inverse() * motion
				result[r] = result[parent] * RegionMotions.partway(relative, joints[r], t)
			done[r] = 1
			progressed = true
		if not progressed:
			break
	return result


## The key's pieces [param t] of the way to the other key, on a canvas [param width]
## × [param height] pixels. Pieces bending with the whole shape are drawn through it (see
## [ShapeBlend]); the others move rigidly, in front of what's behind them: those that
## don't turn by whole pixels, keeping theirs as they are, turned ones smoothly, see
## [SmoothKey].
func drawn(t: float, width: int, height: int) -> PackedByteArray:
	var out := PixelCanvas.blank(width * height)
	var moved := motions_at(t)
	var labels := drawing
	# How far back each piece is, and of what's drawn on each pixel so far
	var depth := PackedInt32Array()
	depth.resize(pieces.count())
	for k in order.size():
		depth[order[k]] = k
	var drawn_depth := PackedInt32Array()
	drawn_depth.resize(width * height)
	drawn_depth.fill(-1)
	# Pixels the bending would show of pieces moving on their own, and from where
	var left_out := PackedInt32Array()
	if blend != null and layered.has(0):
		var grown := PackedFloat32Array()
		var bent := blend.sources(1.0 - t if is_b else t, is_b, scale, grown)
		var bent_width := blend.width * scale
		for y in height:
			for x in width:
				var source := bent[y * bent_width + x] if x < bent_width else Vector2(-1, -1)
				if source.x < 0.0:
					continue
				var sx := floori(source.x)
				var sy := floori(source.y)
				if sx < 0 or sy < 0 or sx >= width or sy >= height:
					continue
				var q := sy * width + sx
				if labels[q] >= 0 and layered[labels[q]] == 1:
					left_out.append_array([y * width + x, q])
					continue
				# What bends, its outline smooth where it's stretched
				if grown[y * bent_width + x] >= MAGNIFIED:
					q = _smooth_covering(source, BENDING, width, height)
				else:
					q = _covering(source, BENDING, width, height)
				if q < 0:
					continue
				var r := labels[q]
				var i := (y * width + x) * 4
				if painted:
					# Blended from the pixels round, so soft edges stay soft
					_blend(out, i, source, r, width, height)
					if out[i + 3] == 0:
						for c in 4:
							out[i + c] = data[q * 4 + c]
				else:
					for c in 4:
						out[i + c] = data[q * 4 + c]
				drawn_depth[y * width + x] = depth[r]
	for r in order:
		var motion := moved[r]
		# Pieces bending are drawn rigidly only where the bending doesn't reach
		var bending := layered.size() > r and layered[r] == 0
		var turned := (
			absf(RegionMotions.turn_of(motion)) >= STILL_TURN
			or RegionMotions.stretch_of(motion) >= STILL_TURN
		)
		# Stretched much, its outline is drawn smooth rather than its pixels' stairs grown
		var magnified := maxf(motion.x.length(), motion.y.length()) >= MAGNIFIED
		if not turned:
			# Its middle goes where the turn would take it, by whole pixels
			var middle := pieces.centers[r]
			motion = Transform2D(0.0, (motion * middle - middle).round())
		var back := motion.affine_inverse()
		# Where the piece lands, a pixel round
		var low := Vector2(INF, INF)
		var high := -low
		for p in pieces.pixels[r]:
			var at := motion * pieces.point_of(p)
			low = low.min(at)
			high = high.max(at)
		var x0 := maxi(floori(low.x) - 1, 0)
		var y0 := maxi(floori(low.y) - 1, 0)
		var x1 := mini(ceili(high.x) + 1, width)
		var y1 := mini(ceili(high.y) + 1, height)
		for y in range(y0, y1):
			for x in range(x0, x1):
				if drawn_depth[y * width + x] > depth[r]:
					continue
				var source := back * Vector2(x + 0.5, y + 0.5)
				var i := (y * width + x) * 4
				var sx := floori(source.x)
				var sy := floori(source.y)
				if sx < 0 or sy < 0 or sx >= width or sy >= height:
					continue
				var q := sy * width + sx
				if bending and meshed[q] == 1:
					continue
				if not turned:
					if labels[q] != r:
						continue
					for c in 4:
						out[i + c] = data[q * 4 + c]
					drawn_depth[y * width + x] = depth[r]
					continue
				if painted:
					_blend(out, i, source, r, width, height)
					if out[i + 3] > 0:
						drawn_depth[y * width + x] = depth[r]
					continue
				if magnified:
					var covering := _smooth_covering(source, r, width, height)
					if covering >= 0:
						for c in 4:
							out[i + c] = data[covering * 4 + c]
						drawn_depth[y * width + x] = depth[r]
					continue
				if smooth == null:
					# The nearest pixel of the piece
					if labels[q] == r:
						for c in 4:
							out[i + c] = data[q * 4 + c]
						drawn_depth[y * width + x] = depth[r]
					continue
				var code := smooth.code_at(source)
				if code == 0 or smooth.pieces[code] != r:
					continue
				var color := smooth.colors[code]
				out[i] = color >> 24 & 255
				out[i + 1] = color >> 16 & 255
				out[i + 2] = color >> 8 & 255
				out[i + 3] = color & 255
				drawn_depth[y * width + x] = depth[r]
	_close_seams(out, left_out, width, height)
	return out


## The pixel of the key point [param at] shows of piece [param r] (or of any piece
## bending, for [constant BENDING]), its outline taken smooth: where the piece's pixels
## round the point, weighted by how near, are at least half, the nearest of them; -1
## elsewhere. At pixels' middles it's the pixel itself, and stretched, the stairs of
## the piece's outline become straight or curved.
func _covering(at: Vector2, r: int, width: int, height: int) -> int:
	var x := at.x - 0.5
	var y := at.y - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var covered := 0.0
	var best := -1
	var best_weight := -1.0
	for k in 4:
		var qx := x0 + (k & 1)
		var qy := y0 + (k >> 1)
		if qx < 0 or qy < 0 or qx >= width or qy >= height:
			continue
		var q := qy * width + qx
		var label := drawing[q]
		if label < 0 or (label != r if r >= 0 else layered[label] == 1):
			continue
		var weight := (fx if k & 1 else 1.0 - fx) * (fy if k >> 1 else 1.0 - fy)
		covered += weight
		if weight > best_weight:
			best_weight = weight
			best = q
	return best if covered >= 0.5 else -1


## Like [method _covering], for pieces grown much: the outline is smoothed, so
## stretched its stairs become curves, see [SmoothOutline]. The pixel is the piece's
## nearest.
func _smooth_covering(at: Vector2, r: int, width: int, height: int) -> int:
	_outlines_lock.lock()
	if not _outlines.has(r):
		var mask := PackedByteArray()
		mask.resize(drawing.size())
		for p in drawing.size():
			mask[p] = 1 if _belongs(drawing[p], r) else 0
		_outlines[r] = SmoothOutline.of(mask, width, height, scale)
	var outline: SmoothOutline = _outlines[r]
	_outlines_lock.unlock()
	if not outline.covers(at):
		return -1
	var cx := floori(at.x)
	var cy := floori(at.y)
	var best := -1
	var best_apart := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px := cx + dx
			var py := cy + dy
			if px < 0 or py < 0 or px >= width or py >= height:
				continue
			var q := py * width + px
			if not _belongs(drawing[q], r):
				continue
			var apart := Vector2(px + 0.5, py + 0.5).distance_squared_to(at)
			if apart < best_apart:
				best_apart = apart
				best = q
	return best


## Whether a pixel of piece [param label] is of piece [param r], or bending for
## [constant BENDING]
func _belongs(label: int, r: int) -> bool:
	if label < 0:
		return false
	return label == r if r >= 0 else layered[label] == 0


## Fills the seams left between pieces moving on their own and those bending round
## them, where their motions differ a little: pixels in [param left_out] (pairs of a
## pixel of [param out] and the key's pixel the bending would show there) still empty
## and right by what's drawn take the key's pixel
func _close_seams(
	out: PackedByteArray, left_out: PackedInt32Array, width: int, height: int
) -> void:
	if left_out.is_empty():
		return
	var shown := PackedByteArray()
	shown.resize(width * height)
	for p in shown.size():
		shown[p] = 1 if out[p * 4 + 3] > 0 else 0
	var apart: PackedInt32Array = PixelCanvas.distances(shown, width, height, 1)[0]
	for k in range(0, left_out.size(), 2):
		var p := left_out[k]
		var q := left_out[k + 1]
		# In thirds of a pixel, see PixelCanvas.distances
		if shown[p] == 1 or apart[p] > SEAM * scale * 3:
			continue
		for c in 4:
			out[p * 4 + c] = data[q * 4 + c]


## Writes into [param out] at byte [param i] what piece [param r] shows at point
## [param at] of the key: its pixels round the point blended, weighted by how near
func _blend(out: PackedByteArray, i: int, at: Vector2, r: int, width: int, height: int) -> void:
	var x := at.x - 0.5
	var y := at.y - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var labels := drawing
	var sum := Vector4.ZERO
	var weight := 0.0
	for k in 4:
		var qx := x0 + (k & 1)
		var qy := y0 + (k >> 1)
		if qx < 0 or qy < 0 or qx >= width or qy >= height:
			continue
		var q := qy * width + qx
		if labels[q] != r:
			continue
		var near := (fx if k & 1 else 1.0 - fx) * (fy if k >> 1 else 1.0 - fy)
		var alpha := data[q * 4 + 3] / 255.0
		sum += Vector4(data[q * 4], data[q * 4 + 1], data[q * 4 + 2], 255.0) * alpha * near
		weight += near
	# Shown where the piece covers most of the point
	if weight < 0.5 or sum.w <= 0.0:
		return
	out[i] = roundi(sum.x / sum.w * 255.0)
	out[i + 1] = roundi(sum.y / sum.w * 255.0)
	out[i + 2] = roundi(sum.z / sum.w * 255.0)
	out[i + 3] = clampi(roundi(sum.w / weight), 0, 255)
