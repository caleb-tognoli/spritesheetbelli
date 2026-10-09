class_name KeyRegions
extends RefCounted
## A key cut into regions, see [PieceMorph]: runs of pixels of one colour, with runs too
## small to matter merged into the neighbour of nearest colour, and line work (thin lines
## darker than what they're drawn round) split among the regions it touches. Also used for
## the pieces regions are merged into.

## Regions smaller than this share of the sprite, or than [constant MIN_PIXELS], are merged
## into a neighbour
const MIN_SHARE := 0.004
const MIN_PIXELS := 3
## Share of a region's pixels that may lie in 2 × 2 squares of it for it to be a line one
## pixel wide
const LINE_SQUARES := 0.2
## How much darker than its neighbours (red, green and blue summed, 0 to 3) a line must be
## to be line work
const LINE_DARKER := 0.25
## Fewer colours than this and the keys are pixel art, split by their colours; more, and
## they're painted, split by [constant PALETTE] colours standing for theirs
const MANY_COLORS := 48
const PALETTE := 16
## Regions this many times longer than wide have a direction, see [member axes]
const LONG := 1.6

var width := 0
var height := 0
## The region of each canvas pixel, -1 for transparent ones
var labels := PackedInt32Array()
## Each region's pixels, as canvas indices
var pixels: Array[PackedInt32Array] = []
## Each region's middle
var centers := PackedVector2Array()
## Each region's average colour, red, green and blue from 0 to 1
var colors := PackedVector3Array()
## Each region's direction, the angle of its longest axis, and how many times longer than
## wide it is
var axes := PackedFloat32Array()
var elongations := PackedFloat32Array()
## The points along the border of each two regions touching, midway between their pixels:
## keyed by [code]Vector2i(first, second)[/code], the first the lower
var borders: Dictionary[Vector2i, PackedVector2Array] = {}


## The regions of [param data], a canvas [param canvas_width] pixels wide with a transparent
## border, split by [param split_colors] (see [method PixelCanvas.colors]), which may be
## fewer colours than the canvas has, see [method split_colors_of]
static func of(
	data: PackedByteArray, canvas_width: int, split_colors: PackedInt32Array
) -> KeyRegions:
	var found := PixelParts.find(split_colors, canvas_width, PixelParts.sides_of(canvas_width))
	var labels := found.part_of
	var count := found.parts.size()
	var colors := _average_colors(data, labels, count)
	var sizes := PackedInt32Array()
	sizes.resize(count)
	for p in labels.size():
		if labels[p] >= 0:
			sizes[labels[p]] += 1
	var shown := 0
	for size in sizes:
		shown += size
	_merge_small(labels, canvas_width, sizes, colors, maxi(MIN_PIXELS, int(shown * MIN_SHARE)))
	_dissolve_lines(labels, canvas_width, data.size() / 4 / canvas_width, colors)
	return from_labels(data, canvas_width, _renumbered(labels))


## [param a_data] and [param b_data]'s colours (see [method PixelCanvas.colors]) to split
## them into regions by: their own for pixel art, a few colours standing for theirs, the
## same in both, for painted sprites with many: [code][a, b][/code]
static func split_colors_of(
	a_data: PackedByteArray, b_data: PackedByteArray
) -> Array[PackedInt32Array]:
	var a_colors := PixelCanvas.colors(a_data)
	var b_colors := PixelCanvas.colors(b_data)
	# Only fully shown pixels count as the sprite's
	for colors in [a_colors, b_colors]:
		for p in colors.size():
			if colors[p] != 0 and (colors[p] & 255) < 128:
				colors[p] = 0
	if PixelPalette.count(a_colors + b_colors, MANY_COLORS) <= MANY_COLORS:
		return [a_colors, b_colors]
	return PixelPalette.reduce(a_colors, b_colors, PALETTE)


## Regions of [param data] as [param region_labels] says (see [member labels]): numbered
## from 0 with none missing
static func from_labels(
	data: PackedByteArray, canvas_width: int, region_labels: PackedInt32Array
) -> KeyRegions:
	var regions := KeyRegions.new()
	regions.width = canvas_width
	regions.height = region_labels.size() / canvas_width
	regions.labels = region_labels
	var count := 0
	for label in region_labels:
		count = maxi(count, label + 1)
	for r in count:
		regions.pixels.append(PackedInt32Array())
	for p in region_labels.size():
		if region_labels[p] >= 0:
			regions.pixels[region_labels[p]].append(p)
	regions.centers.resize(count)
	regions.colors = _average_colors(data, region_labels, count)
	regions.axes.resize(count)
	regions.elongations.resize(count)
	for r in count:
		regions._shape(r)
	# Borders: midway between pixels of two regions side by side
	for p in region_labels.size():
		var label := region_labels[p]
		if label < 0:
			continue
		for side in [1, canvas_width]:
			var q: int = p + side
			if q >= region_labels.size():
				continue
			var other := region_labels[q]
			if other < 0 or other == label:
				continue
			var key := Vector2i(mini(label, other), maxi(label, other))
			if not regions.borders.has(key):
				regions.borders[key] = PackedVector2Array()
			regions.borders[key].append((regions.point_of(p) + regions.point_of(q)) / 2.0)
	return regions


## The average colour, red, green and blue from 0 to 1, of [param pixels] of [param data]
static func mean_color(data: PackedByteArray, pixels: PackedInt32Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in pixels:
		sum += Vector3(data[p * 4], data[p * 4 + 1], data[p * 4 + 2]) / 255.0
	return sum / maxi(pixels.size(), 1)


## The middle of canvas pixel [param p]
func point_of(p: int) -> Vector2:
	return Vector2(p % width + 0.5, p / width + 0.5)


## How many regions there are
func count() -> int:
	return pixels.size()


## The regions touching region [param r]
func neighbours_of(r: int) -> Array[int]:
	var found: Array[int] = []
	for key in borders:
		if key.x == r:
			found.append(key.y)
		elif key.y == r:
			found.append(key.x)
	return found


func _shape(r: int) -> void:
	var points := pixels[r]
	var middle := Vector2.ZERO
	for p in points:
		middle += point_of(p)
	middle /= maxi(points.size(), 1)
	centers[r] = middle
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for p in points:
		var d := point_of(p) - middle
		xx += d.x * d.x
		xy += d.x * d.y
		yy += d.y * d.y
	# The covariance's eigenvalues and the direction of the larger
	var trace := xx + yy
	var gap := sqrt(maxf((xx - yy) * (xx - yy) + 4.0 * xy * xy, 0.0))
	var big := (trace + gap) / 2.0
	var small := maxf((trace - gap) / 2.0, 1e-3 * points.size())
	axes[r] = 0.5 * atan2(2.0 * xy, xx - yy)
	elongations[r] = sqrt(maxf(big, 1e-6) / small)


static func _average_colors(
	data: PackedByteArray, region_labels: PackedInt32Array, count: int
) -> PackedVector3Array:
	var sums := PackedVector3Array()
	sums.resize(count)
	var sizes := PackedInt32Array()
	sizes.resize(count)
	for p in region_labels.size():
		var r := region_labels[p]
		if r >= 0:
			sums[r] += Vector3(data[p * 4], data[p * 4 + 1], data[p * 4 + 2]) / 255.0
			sizes[r] += 1
	for r in count:
		if sizes[r] > 0:
			sums[r] /= sizes[r]
	return sums


## Merges regions smaller than [param least] pixels, smallest first, each into the
## neighbour of nearest colour (a longer shared border counting a little)
static func _merge_small(
	region_labels: PackedInt32Array,
	canvas_width: int,
	sizes: PackedInt32Array,
	colors: PackedVector3Array,
	least: int
) -> void:
	var members: Array[PackedInt32Array] = []
	for r in sizes.size():
		members.append(PackedInt32Array())
	for p in region_labels.size():
		if region_labels[p] >= 0:
			members[region_labels[p]].append(p)
	var sides := PixelParts.sides_of(canvas_width)
	var corners: Array[int] = [
		-canvas_width - 1, -canvas_width + 1, canvas_width - 1, canvas_width + 1
	]
	var changed := true
	while changed:
		changed = false
		var order: Array[int] = []
		for r in sizes.size():
			if sizes[r] > 0 and sizes[r] < least:
				order.append(r)
		order.sort_custom(func(x: int, y: int) -> bool: return sizes[x] < sizes[y])
		for r in order:
			if sizes[r] == 0 or sizes[r] >= least:
				continue
			var touching := {}
			for p in members[r]:
				for side in sides:
					var other := region_labels[p + side]
					if other >= 0 and other != r:
						touching[other] = touching.get(other, 0) + 1
			# Touching only across a corner, it joins what it touches there
			if touching.is_empty():
				for p in members[r]:
					for side in corners:
						var other := region_labels[p + side]
						if other >= 0 and other != r:
							touching[other] = touching.get(other, 0) + 1
			if touching.is_empty():
				continue
			var best := -1
			var best_score := INF
			for other: int in touching:
				var apart := colors[other] - colors[r]
				var score: float = (
					absf(apart.x) + absf(apart.y) + absf(apart.z) - 0.02 * touching[other]
				)
				if score < best_score:
					best_score = score
					best = other
			for p in members[r]:
				region_labels[p] = best
			members[best].append_array(members[r])
			members[r] = PackedInt32Array()
			colors[best] = (
				(colors[best] * sizes[best] + colors[r] * sizes[r]) / (sizes[best] + sizes[r])
			)
			sizes[best] += sizes[r]
			sizes[r] = 0
			changed = true


## Line work, regions a pixel wide darker than what they touch, split among the regions
## round it: each of its pixels joins the nearest other region
static func _dissolve_lines(
	region_labels: PackedInt32Array,
	canvas_width: int,
	canvas_height: int,
	colors: PackedVector3Array
) -> void:
	var count := colors.size()
	var sizes := PackedInt32Array()
	sizes.resize(count)
	var in_squares := PackedInt32Array()
	in_squares.resize(count)
	var touching_light := PackedFloat32Array()
	touching_light.resize(count)
	var touching := PackedInt32Array()
	touching.resize(count)
	var size := region_labels.size()
	var square := PackedByteArray()
	square.resize(size)
	# Pixels in a 2 × 2 square all of their region
	for p in size:
		var r := region_labels[p]
		if r < 0 or p % canvas_width == canvas_width - 1 or p + canvas_width + 1 >= size:
			continue
		if (
			region_labels[p + 1] == r
			and region_labels[p + canvas_width] == r
			and region_labels[p + canvas_width + 1] == r
		):
			for q in [p, p + 1, p + canvas_width, p + canvas_width + 1]:
				square[q] = 1
	var sides := PixelParts.sides_of(canvas_width)
	for p in size:
		var r := region_labels[p]
		if r < 0:
			continue
		sizes[r] += 1
		in_squares[r] += square[p]
		for side in sides:
			var q: int = p + side
			if q < 0 or q >= size:
				continue
			var other := region_labels[q]
			if other >= 0 and other != r:
				var c := colors[other]
				touching_light[r] += c.x + c.y + c.z
				touching[r] += 1
	var lines := PackedByteArray()
	lines.resize(count)
	var any := false
	for r in count:
		if sizes[r] == 0 or touching[r] == 0 or in_squares[r] > sizes[r] * LINE_SQUARES:
			continue
		var light := colors[r].x + colors[r].y + colors[r].z
		if light <= touching_light[r] / touching[r] - LINE_DARKER:
			lines[r] = 1
			any = true
	if not any:
		return
	# Each line pixel takes the region of the nearest pixel of another region
	var others := PackedByteArray()
	others.resize(size)
	for p in size:
		others[p] = 1 if region_labels[p] >= 0 and lines[region_labels[p]] == 0 else 0
	var nearest: PackedInt32Array = PixelCanvas.distances(others, canvas_width, canvas_height, 1)[1]
	var before := region_labels.duplicate()
	for p in size:
		var r := before[p]
		if r >= 0 and lines[r] == 1 and nearest[p] >= 0:
			region_labels[p] = before[nearest[p]]


## [param region_labels] numbered from 0 with none missing
static func _renumbered(region_labels: PackedInt32Array) -> PackedInt32Array:
	var numbers := {}
	var result := region_labels.duplicate()
	for p in result.size():
		var r := result[p]
		if r < 0:
			continue
		if not numbers.has(r):
			numbers[r] = numbers.size()
		result[p] = numbers[r]
	return result
