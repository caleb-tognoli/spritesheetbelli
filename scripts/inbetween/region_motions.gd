class_name RegionMotions
extends RefCounted
## How each region of one key moved to the other, see [PieceMorph]: a turn and a move
## ([Transform2D]) for each. Candidate motions come from searching the other key for where
## each region lands best at every turn, and from pairing regions with the other key's of
## the same colour; then all regions pick theirs together (min-sum belief propagation over
## the regions touching), each scored by how well it lands on the other key, while
## neighbours are kept touching: they may slide along each other or turn about a joint, but
## not come apart.

## What one pixel landing on another unlike it costs at most
const CAP := 1.2
## What each pixel of movement, beyond the whole sprite's, costs a region's motion, per
## pixel: of motions that fit alike, like a square turned half round and not turned, the
## one moving its pixels least
const MOVE_COST := 0.005
## What growing or shrinking costs a region's motion, per pixel, for each time e (2.7)
## times bigger or smaller it gets
const AREA_COST := 0.2
## Stretches tried when pairing regions are at most this many times, either way
const MOST_STRETCH := 2.0
## What each pixel a region's pixels end up from where they started, going to the other
## key and back, costs its motion, per pixel, up to [constant ROUND_TRIP_CAP] pixels; see
## [method agree]
const ROUND_TRIP_COST := 0.05
const ROUND_TRIP_CAP := 10.0
## Leftovers, see [method leftovers]: how badly a pixel must land to be one, how much
## their region may stretch, how much better a leftover's own motion must fit (its cost at
## most this share of what its region's costs it), and how much better a pixel round it
## must land its way to join it
const MISFIT := 0.6
const LEFTOVER_STRETCH := 0.1
const SPLIT_GAIN := 0.5
const GROW_MARGIN := 0.1
## How unlike itself a region may be turned to count as looking the same, see
## [method simplest]
const SYMMETRIC := 0.08
## Pixels compared at most when scoring a region's motion: bigger regions are sampled
const SAMPLES := 256
## Turns tried when searching, evenly round
const TURNS := 24
## Places tried for each turn: the most voted for, see [method _search]
const VOTED := 12
## Places kept for each turn, at least this far apart, and kept in all for a region
const KEPT_PER_TURN := 2
const APART := 3.0
const KEPT := 6
## Points of a region whose colour is looked for in the other key to vote for places
const ANCHORS := 6
## How close (red, green and blue summed, 0 to 3) a pixel's colour must be to an anchor's
const ANCHOR_COLOR := 0.2
## Pixels of the other key voted from at most for each anchor
const VOTERS := 600
## What each pixel farther than the whole sprite's movement costs a place, per pixel
const DISTANCE_COST := 0.002
## Regions are paired with the other key's of a colour this close (red, green and blue
## summed, 0 to 3), of a size this many times theirs at most, the nearest few
const PAIR_COLOR := 0.35
const PAIR_SIZE := 2.5
const PAIRS := 6
## A region and the one paired with it, both this many times longer than wide, may have
## turned by how much their directions differ
const LONG := 1.6

## Each region's motion, once found
var chosen: Array[Transform2D] = []
var regions: KeyRegions
var features: KeyFeatures
var other: KeyFeatures
## Where the whole sprite moved, and how big it is
var shift := Vector2.ZERO
var side := 1.0


## How each of [param from_regions] (with [param from_features]) moved to the key with
## [param to_regions] and [param to_features], the whole sprite moving by [param whole]
## and being [param size] pixels across: see [member chosen]. Null when [param progress]
## is cancelled.
static func find(
	from_regions: KeyRegions,
	from_features: KeyFeatures,
	to_regions: KeyRegions,
	to_features: KeyFeatures,
	whole: Vector2,
	size: float,
	progress: WorkProgress
) -> RegionMotions:
	var motions := RegionMotions.new()
	motions.regions = from_regions
	motions.features = from_features
	motions.other = to_features
	motions.shift = whole
	motions.side = size
	var candidates: Array[Transform2D] = [Transform2D(0.0, whole)]
	var voters := motions._voters()
	# Each region is searched for on its own, so they're shared out among threads
	var searches := motions._searches.bind(voters, progress)
	var biggest := RegionChoice.biggest_first(from_regions)
	for part: Array[Transform2D] in RegionChoice.shared(biggest, searches):
		candidates.append_array(part)
	if progress.cancelled:
		return null
	candidates.append_array(motions._pairings(to_regions))
	motions.chosen = RegionChoice.choose(motions, candidates)
	return motions


## Makes the motions agree with [param back], the other key's coming back: a region's
## motion should land it on pixels whose own motion brings them back where it started.
## Of two arms alike, the one that went up lands on the arm raised in the other key, which
## comes back down to it, while landing on the other arm would come back to that one. Each
## region keeps its motion or takes the reverse of one of the other key's that lands on it,
## whichever fits best, counting how far its pixels end up from where they started.
func agree(back: RegionMotions) -> void:
	# The other key's regions landing on each of these, in order
	var landing: Array[PackedInt32Array] = []
	for r in regions.count():
		landing.append(PackedInt32Array())
	for s in back.regions.count():
		var hit := {}
		for k in range(0, back.regions.pixels[s].size(), 4):
			var at := back.chosen[s] * back.regions.point_of(back.regions.pixels[s][k])
			var x := floori(at.x)
			var y := floori(at.y)
			if x >= 0 and y >= 0 and x < regions.width and y < regions.height:
				var r := regions.labels[y * regions.width + x]
				if r >= 0 and not hit.has(r):
					hit[r] = true
					landing[r].append(s)
	# Each region on its own, so they're shared out among threads
	var agreeing := _agreeing.bind(back, landing)
	var agreed: Array[Transform2D] = []
	for part: Array[Transform2D] in Parallel.split(regions.count(), 1, agreeing):
		agreed.append_array(part)
	for r in agreed.size():
		chosen[r] = agreed[r]


## [method agree]'s motions for regions [param start] to [param end] (past the last), given
## the other key's regions [param landing] on each
func _agreeing(
	start: int, end: int, back: RegionMotions, landing: Array[PackedInt32Array]
) -> Array[Transform2D]:
	var found: Array[Transform2D] = []
	for r in range(start, end):
		var candidates: Array[Transform2D] = [chosen[r]]
		for s in landing[r]:
			candidates.append(back.chosen[s].affine_inverse())
		var best := chosen[r]
		var best_score := INF
		for motion in candidates:
			var score := cost(r, motion) + ROUND_TRIP_COST * round_trip(r, motion, back)
			if score < best_score:
				best_score = score
				best = motion
		found.append(best)
	return found


## Parts of regions that land badly with their region's motion, in patches of at least
## [param least] pixels, like an arm of the body's colour that moved on its own: for each,
## its pixels and the region it's of, [code][pixels, region][/code]. Regions squashing or
## stretching have none: their ends land off because they bend.
func leftovers(least: int) -> Array[Array]:
	var found: Array[Array] = []
	var sides := PixelParts.sides_of(regions.width)
	for r in regions.count():
		var pixels := regions.pixels[r]
		var motion := chosen[r]
		if pixels.size() < least * 2 or stretch_of(motion) > LEFTOVER_STRETCH:
			continue
		var misfit := {}
		for p in pixels:
			if features.difference(p, other, motion * regions.point_of(p)) > MISFIT:
				misfit[p] = true
		var seen := {}
		for start: int in misfit:
			if seen.has(start):
				continue
			var patch := PackedInt32Array([start])
			seen[start] = true
			var next := 0
			while next < patch.size():
				var p := patch[next]
				next += 1
				for offset in sides:
					var q: int = p + offset
					if misfit.has(q) and not seen.has(q):
						seen[q] = true
						patch.append(q)
			if patch.size() >= least and patch.size() * 2 < pixels.size():
				found.append([patch, r])
	return found


## Splits [param leftover] (see [method leftovers]) off its region as a region of its own
## moving by [param motion], with the region's pixels round it that land better that way;
## returns the new regions' labels, or empty when it doesn't fit much better that way
func split_off(leftover: Array, motion: Transform2D, data: PackedByteArray) -> bool:
	var patch: PackedInt32Array = leftover[0]
	var r: int = leftover[1]
	if cost_of(patch, motion) > SPLIT_GAIN * cost_of(patch, chosen[r]):
		return false
	var labels := regions.labels.duplicate()
	var next := regions.count()
	var grown := {}
	var queue: Array[int] = []
	for p in patch:
		grown[p] = true
		queue.append(p)
	var sides := PixelParts.sides_of(regions.width)
	while not queue.is_empty():
		var p: int = queue.pop_back()
		for offset in sides:
			var q: int = p + offset
			if grown.has(q) or labels[q] != r:
				continue
			var point := regions.point_of(q)
			var own := features.difference(q, other, motion * point)
			if own < features.difference(q, other, chosen[r] * point) - GROW_MARGIN:
				grown[q] = true
				queue.append(q)
	if grown.size() * 2 > regions.pixels[r].size():
		return false
	for p: int in grown:
		labels[p] = next
	regions = KeyRegions.from_labels(data, regions.width, labels)
	chosen.append(motion)
	return true


## The motion taking pixels [param from] of this key to [param to] of the other's (both
## patches, see [method leftovers]): middle to middle, turned as their directions differ
## (either way round), the better fitting, nudged to fit best
func pairing(from: PackedInt32Array, to: PackedInt32Array) -> Transform2D:
	var a := _shape_of(from, regions.width)
	var b := _shape_of(to, other.width)
	var best := Transform2D()
	var best_cost := INF
	for flip: float in [0.0, PI]:
		var motion := about(a[0], b[1] - a[1] + flip, b[0] - a[0])
		var motion_cost := cost_of(from, motion)
		if motion_cost < best_cost:
			best_cost = motion_cost
			best = motion
	return refined(from, best, 2)


## The middle and direction (the angle of the longest axis) of [param pixels] of a canvas
## [param width] pixels wide
static func _shape_of(pixels: PackedInt32Array, width: int) -> Array:
	var middle := Vector2.ZERO
	for p in pixels:
		middle += Vector2(p % width + 0.5, p / width + 0.5)
	middle /= maxi(pixels.size(), 1)
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for p in pixels:
		var d := Vector2(p % width + 0.5, p / width + 0.5) - middle
		xx += d.x * d.x
		xy += d.x * d.y
		yy += d.y * d.y
	return [middle, 0.5 * atan2(2.0 * xy, xx - yy)]


## How far, on average, region [param r]'s pixels end up from where they started, going to
## the other key with [param motion] and back with [param back]'s motions
func round_trip(r: int, motion: Transform2D, back: RegionMotions) -> float:
	var pixels := regions.pixels[r]
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var total := 0.0
	var counted := 0
	for k in range(0, pixels.size(), stride):
		var at := regions.point_of(pixels[k])
		var landed := motion * at
		var x := floori(landed.x)
		var y := floori(landed.y)
		var away := ROUND_TRIP_CAP
		if x >= 0 and y >= 0 and x < back.regions.width and y < back.regions.height:
			var s := back.regions.labels[y * back.regions.width + x]
			if s >= 0:
				away = minf((back.chosen[s] * landed).distance_to(at), ROUND_TRIP_CAP)
		total += away
		counted += 1
	return total / maxi(counted, 1)


## A motion turning by [param angle] about [param center], then moving by [param move]
static func about(center: Vector2, angle: float, move: Vector2) -> Transform2D:
	var motion := Transform2D(angle, Vector2.ZERO)
	motion.origin = center + move - motion.basis_xform(center)
	return motion


## How far [param motion] turns, in radians, setting aside how it stretches: the turn of
## the nearest motion that only turns
static func turn_of(motion: Transform2D) -> float:
	return atan2(motion.x.y - motion.y.x, motion.x.x + motion.y.y)


## [param motion] [param t] of the way: turned that much of its turn and stretched that
## much of its stretch, with [param pivot] moved that much of the way along its path
static func partway(motion: Transform2D, pivot: Vector2, t: float) -> Transform2D:
	var turn := turn_of(motion)
	var undo := Transform2D(-turn, Vector2.ZERO)
	# What's left once the turn is undone: the stretch
	var stretch := undo * Transform2D(motion.x, motion.y, Vector2.ZERO)
	var partial := Transform2D(
		Vector2(1, 0).lerp(stretch.x, t), Vector2(0, 1).lerp(stretch.y, t), Vector2.ZERO
	)
	var result := Transform2D(turn * t, Vector2.ZERO) * partial
	result.origin = pivot + (motion * pivot - pivot) * t - result.basis_xform(pivot)
	return result


## How much [param motion] stretches or squashes: 0 for none
static func stretch_of(motion: Transform2D) -> float:
	var undo := Transform2D(-turn_of(motion), Vector2.ZERO)
	var stretch := undo * Transform2D(motion.x, motion.y, Vector2.ZERO)
	return absf(stretch.x.x - 1.0) + absf(stretch.y.y - 1.0) + absf(stretch.x.y) + absf(stretch.y.x)


## How badly region [param r] lands on the other key with [param motion]: the average over
## its pixels (sampled) of how different the pixel it lands on is
func cost(r: int, motion: Transform2D) -> float:
	return cost_of(regions.pixels[r], motion)


## [method cost] for any [param pixels] of the key
func cost_of(pixels: PackedInt32Array, motion: Transform2D) -> float:
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var total := features.landing_sum(pixels, stride, motion, other, CAP, MOVE_COST, shift)
	var counted := (pixels.size() + stride - 1) / stride
	# Growing or shrinking costs: a region shrunk small lands well anywhere
	var area := absf(motion.determinant())
	return total / maxi(counted, 1) + AREA_COST * absf(log(maxf(area, 1e-3)))


## [method cost_of] when it's at most [param limit]; otherwise any number over
## [param limit] (worked out only as far as needed to tell), which the cost is at least
func cost_below(pixels: PackedInt32Array, motion: Transform2D, limit: float) -> float:
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var counted := (pixels.size() + stride - 1) / stride
	var area := absf(motion.determinant())
	var area_cost := AREA_COST * absf(log(maxf(area, 1e-3)))
	var bound := (limit - area_cost) * maxi(counted, 1)
	var total := features.landing_sum_below(
		pixels, stride, motion, other, CAP, MOVE_COST, shift, bound
	)
	var value := total / maxi(counted, 1) + area_cost
	# Given up early, though rounding left it within the limit: worked out whole
	if total > bound and value <= limit:
		return cost_of(pixels, motion)
	return value


## How badly [param pixels] land on the other key with [param motion], as
## [method cost_of] but counting only how they fit, not how far they move
func fit_of(pixels: PackedInt32Array, motion: Transform2D) -> float:
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var total := features.landing_sum(pixels, stride, motion, other, CAP)
	return total / maxi((pixels.size() + stride - 1) / stride, 1)


## How badly [param pixels] fit their own key moved a pixel across and down: how much a
## pixel off costs them, so thin lines cost more than broad shapes
func pixel_off(pixels: PackedInt32Array) -> float:
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var total := 0.0
	var counted := 0
	for k in range(0, pixels.size(), stride):
		var p := pixels[k]
		var at := regions.point_of(p)
		total += minf(features.difference(p, features, at + Vector2.RIGHT), CAP)
		total += minf(features.difference(p, features, at + Vector2.DOWN), CAP)
		counted += 2
	return total / maxi(counted, 1)


## [param motion] nudged, a pixel or a few degrees at a time and then finer, while
## [param pixels] land better with it, for up to [param rounds] rounds
func refined(pixels: PackedInt32Array, motion: Transform2D, rounds := 1) -> Transform2D:
	var best := cost_of(pixels, motion)
	var step := 1.0
	var turn := 0.08
	var center := Vector2.ZERO
	for p in pixels:
		center += regions.point_of(p)
	center /= maxi(pixels.size(), 1)
	for _step in rounds * 4:
		var improved := false
		var tries: Array[Transform2D] = []
		for move: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			tries.append(Transform2D(motion.x, motion.y, motion.origin + move * step))
		for direction: float in [1.0, -1.0]:
			var turned := about(center, direction * turn, Vector2.ZERO)
			tries.append(motion * turned)
			# Stretched a little along either axis, about the middle
			for axis in 2:
				var scale := Vector2.ONE
				scale[axis] = 1.0 + direction * turn
				var stretched := Transform2D(0.0, scale, 0.0, Vector2.ZERO)
				stretched.origin = center - stretched.basis_xform(center)
				tries.append(motion * stretched)
		for candidate in tries:
			# Only worked out whole when it might be better
			var score := cost_below(pixels, candidate, best)
			if score < best:
				best = score
				motion = candidate
				improved = true
		if not improved:
			step /= 2.0
			turn /= 2.0
			if step < 0.25:
				break
	return motion


## [param motion] for [param pixels], or the same motion less a turn the pixels look the
## same after, about their middle (a quarter or half turn for a square, any for a disc),
## whichever turns least: the frames between look alike at the ends, but the one turning
## less doesn't spin
func simplest(pixels: PackedInt32Array, motion: Transform2D) -> Transform2D:
	var center := Vector2.ZERO
	for p in pixels:
		center += regions.point_of(p)
	center /= maxi(pixels.size(), 1)
	var best := motion
	for quarter: int in [1, 2, 3]:
		var turn := quarter * PI / 2.0
		var turned := about(center, turn, Vector2.ZERO)
		if _self_cost(pixels, turned) > SYMMETRIC:
			continue
		var candidate := motion * turned.affine_inverse()
		if absf(turn_of(candidate)) < absf(turn_of(best)) - 0.01:
			best = candidate
	return best


## How unlike themselves [param pixels] are moved by [param motion], on their own key
func _self_cost(pixels: PackedInt32Array, motion: Transform2D) -> float:
	var stride := maxi(1, ceili(float(pixels.size()) / SAMPLES))
	var total := features.landing_sum(pixels, stride, motion, features, CAP)
	return total / maxi((pixels.size() + stride - 1) / stride, 1)


## The other key's shown pixels, by colour: for each, its middle and colour
func _voters() -> Array:
	var points := PackedVector2Array()
	var colours := PackedVector3Array()
	var values := other.values
	for p in other.width * other.height:
		var i := p * KeyFeatures.COUNT
		if values[i + 3] >= 0.5 * KeyFeatures.SHOWN_WEIGHT:
			points.append(other_point(p))
			var alpha := values[i + 3] / KeyFeatures.SHOWN_WEIGHT
			colours.append(Vector3(values[i], values[i + 1], values[i + 2]) / alpha)
	return [points, colours]


## [method _search] for regions [param start] to [param end] (past the last), one after the
## other, counting each done in [param progress] and stopping when it's cancelled
func _searches(start: int, end: int, voters: Array, progress: WorkProgress) -> Array[Transform2D]:
	var found: Array[Transform2D] = []
	for r in range(start, end):
		if progress.cancelled:
			break
		progress.advance()
		found.append_array(_search(r, voters))
	return found


## Where region [param r] lands best on the other key, at each turn: places are voted for
## by pixels of the other key of the colour of a few points of the region, as where the
## region would be if that point landed there; the most voted are scored (see
## [method cost]) and the best kept
func _search(r: int, voters: Array) -> Array[Transform2D]:
	return _search_pixels(regions.pixels[r], voters)


## [method _search] for any [param pixels] of the key. Places that can't be among the best
## kept are given up on as soon as that's clear, unless [param pruned] is false.
func _search_pixels(pixels: PackedInt32Array, voters: Array, pruned := true) -> Array[Transform2D]:
	if NativeKernels.kernels:
		return NativeKernels.search_pixels(self, pixels, voters)
	var center := Vector2.ZERO
	for p in pixels:
		center += regions.point_of(p)
	center /= maxi(pixels.size(), 1)
	var places_of: PackedVector2Array = voters[0]
	var colours: PackedVector3Array = voters[1]
	# Anchors spread through the region, and the other key's pixels of their colours
	var anchors := PackedVector2Array()
	var anchor_voters: Array[PackedVector2Array] = []
	var step := maxi(1, pixels.size() / ANCHORS)
	for k in range(0, pixels.size(), step):
		var p := pixels[k]
		var colour := _colour_at(p)
		var near := PackedVector2Array()
		for v in places_of.size():
			var apart := colours[v] - colour
			if absf(apart.x) + absf(apart.y) + absf(apart.z) <= ANCHOR_COLOR:
				near.append(places_of[v])
		if near.size() > VOTERS:
			var thinned := PackedVector2Array()
			var every := float(near.size()) / VOTERS
			for n in VOTERS:
				thinned.append(near[int(n * every)])
			near = thinned
		anchors.append(regions.point_of(p) - center)
		anchor_voters.append(near)
		if anchors.size() >= ANCHORS:
			break
	var expected := center + shift
	var reach := side * 0.75 + 4.0
	# Votes counted on a grid round where the region is expected, which places within
	# reach always fall on, and the places (their cells) in the order first voted for
	var grid_left := floori(expected.x - reach) - 2
	var grid_top := floori(expected.y - reach) - 2
	var grid_width := ceili(2.0 * reach) + 5
	var votes := PackedInt32Array()
	votes.resize(grid_width * (ceili(2.0 * reach) + 5))
	var found: Array[Array] = []
	var places := PackedInt32Array()
	var by_votes := PackedVector3Array()
	# Every score worked out whole, and whether any place was given up on
	var scores := PackedFloat64Array()
	var gave_up := false
	for turn in TURNS:
		var angle := TAU * turn / TURNS
		places.clear()
		for k in anchors.size():
			var offset := anchors[k].rotated(angle)
			for spot in anchor_voters[k]:
				var at := spot - offset
				if at.distance_to(expected) > reach:
					continue
				var cell := (roundi(at.y) - grid_top) * grid_width + roundi(at.x) - grid_left
				if votes[cell] == 0:
					places.append(cell)
				votes[cell] += 1
		# The places, most voted first, sorted natively much faster than with sort_custom:
		# a vector's x is the votes, and as y is NaN, places with as many votes compare as
		# neither first, as when comparing votes alone, so ties come out in the same order
		by_votes.resize(places.size())
		for n in places.size():
			var cell := places[n]
			by_votes[n] = Vector3(-votes[cell], NAN, cell)
			votes[cell] = 0
		by_votes.sort()
		var scored: Array[Array] = []
		# Once enough are kept, a place scoring worse than the best few kept so far can't be
		# among them: it's given up on as soon as that's clear
		var worst := _nth_score(found, KEPT) if pruned else INF
		for n in mini(by_votes.size(), VOTED):
			var cell := int(by_votes[n].z)
			var place := Vector2i(cell % grid_width + grid_left, cell / grid_width + grid_top)
			var motion := about(center, angle, Vector2(place) - center)
			var distance_cost := DISTANCE_COST * Vector2(place).distance_to(expected)
			var limit := worst - distance_cost
			var place_cost := cost_below(pixels, motion, limit)
			var score: float = place_cost + distance_cost
			if score > worst:
				gave_up = true
				continue
			if place_cost > limit:
				score = cost_of(pixels, motion) + distance_cost
			scored.append([score, motion, Vector2(place)])
			scores.append(score)
		scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var kept: Array[Vector2] = []
		for entry in scored:
			var place: Vector2 = entry[2]
			var close := false
			for other_place in kept:
				if absf(place.x - other_place.x) + absf(place.y - other_place.y) < APART:
					close = true
			if close:
				continue
			kept.append(place)
			found.append(entry)
			if kept.size() >= KEPT_PER_TURN:
				break
	found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	# Places given up on scored worse than the best kept, which come out as when every
	# place is scored, unless some of them score alike: their order could differ then
	if gave_up and _tied(scores, found[KEPT - 1][0]):
		return _search_pixels(pixels, voters, false)
	var best: Array[Transform2D] = []
	for entry: Array in found.slice(0, KEPT):
		best.append(entry[1])
	return best


## The [param n]th lowest score of [param entries] (each starting with its score), or INF
## when there are fewer
static func _nth_score(entries: Array[Array], n: int) -> float:
	if entries.size() < n:
		return INF
	var scores := PackedFloat64Array()
	for entry in entries:
		scores.append(entry[0])
	scores.sort()
	return scores[n - 1]


## Whether two of [param scores] at most [param most] are the same
static func _tied(scores: PackedFloat64Array, most: float) -> bool:
	var low := PackedFloat64Array()
	for score in scores:
		if score <= most:
			low.append(score)
	low.sort()
	for k in range(1, low.size()):
		if low[k] == low[k - 1]:
			return true
	return false


## The middle of the other key's canvas pixel [param q]
func other_point(q: int) -> Vector2:
	return Vector2(q % other.width + 0.5, q / other.width + 0.5)


## The colour of the key's pixel [param p], not faded
func _colour_at(p: int) -> Vector3:
	var i := p * KeyFeatures.COUNT
	var alpha := maxf(features.values[i + 3] / KeyFeatures.SHOWN_WEIGHT, 1e-3)
	return Vector3(features.values[i], features.values[i + 1], features.values[i + 2]) / alpha


## Motions pairing each region with regions of the other key ([param to_regions]) of
## about its colour and size, the nearest few: moved middle to middle, and turned as their
## directions differ when both are long
func _pairings(to_regions: KeyRegions) -> Array[Transform2D]:
	var found: Array[Transform2D] = []
	for r in regions.count():
		var size := regions.pixels[r].size()
		var paired: Array[Array] = []
		for s in to_regions.count():
			var apart := to_regions.colors[s] - regions.colors[r]
			var color := absf(apart.x) + absf(apart.y) + absf(apart.z)
			var other_size := to_regions.pixels[s].size()
			if (
				color >= PAIR_COLOR
				or other_size <= size / PAIR_SIZE
				or other_size >= size * PAIR_SIZE
			):
				continue
			var moved := to_regions.centers[s] - regions.centers[r]
			paired.append([color + 0.01 * moved.distance_to(shift), s])
		paired.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for entry: Array in paired.slice(0, PAIRS):
			var s: int = entry[1]
			var move := to_regions.centers[s] - regions.centers[r]
			var turns: Array[float] = [0.0]
			if regions.elongations[r] > LONG and to_regions.elongations[s] > LONG:
				var turned := to_regions.axes[s] - regions.axes[r]
				turns = [turned, turned + PI]
			for turn in turns:
				found.append(about(regions.centers[r], turn, move))
			# Squashed or stretched to the other's spread, along its own axes
			var stretch := _stretch_between(r, to_regions, s)
			if stretch != Vector2.ONE:
				var center := regions.centers[r]
				var axis := Transform2D(regions.axes[r], Vector2.ZERO)
				var scaled := (
					axis * Transform2D(0.0, stretch, 0.0, Vector2.ZERO) * axis.affine_inverse()
				)
				scaled.origin = center + move - scaled.basis_xform(center)
				found.append(scaled)
	return found


## How region [param r] would stretch along its own axes to spread as region [param s] of
## [param to_regions] does along them, within [constant MOST_STRETCH]
func _stretch_between(r: int, to_regions: KeyRegions, s: int) -> Vector2:
	var axis := Vector2.from_angle(regions.axes[r])
	var across := axis.orthogonal()
	var spread_r := _spread_along(regions, r, axis, across)
	var spread_s := _spread_along(to_regions, s, axis, across)
	var stretch := Vector2.ONE
	for k in 2:
		if spread_r[k] > 0.25 and spread_s[k] > 0.25:
			stretch[k] = clampf(sqrt(spread_s[k] / spread_r[k]), 1.0 / MOST_STRETCH, MOST_STRETCH)
	if absf(stretch.x - 1.0) < 0.1 and absf(stretch.y - 1.0) < 0.1:
		return Vector2.ONE
	return stretch


## How spread out region [param r] of [param of_regions] is along [param axis] and
## [param across] it: the variances
static func _spread_along(
	of_regions: KeyRegions, r: int, axis: Vector2, across: Vector2
) -> Vector2:
	var center := of_regions.centers[r]
	var spread := Vector2.ZERO
	for p in of_regions.pixels[r]:
		var d := of_regions.point_of(p) - center
		spread += Vector2(d.dot(axis) ** 2, d.dot(across) ** 2)
	return spread / maxi(of_regions.pixels[r].size(), 1)
