class_name PixelParts
extends RefCounted
## A canvas split into parts: runs of pixels of one colour touching, like a leg, an eye
## or a highlight, or of colours close to each other, like a smoothly shaded ball. See
## [PixelFlow] and [PartMorph].

## The pixels of each part, as canvas indices
var parts: Array[PackedInt32Array] = []
## The pixels around each part, not in it
var rings: Array[PackedInt32Array] = []
## The part each pixel is in, -1 for transparent ones
var part_of := PackedInt32Array()
## The colour of each part, see [method PixelCanvas.colors]: the average of its pixels'
var colors := PackedInt32Array()


## Splits the canvas whose pixels have [param pixel_colors] (see
## [method PixelCanvas.colors]), [param width] pixels wide, into parts, where pixels touch
## across [param sides]: the canvas index steps to their neighbours. Pixels touching join
## a part when their colour is no further from the colour the part started with than
## [param tolerance] (see [method distance]), 0 for the same colour only: not from their
## neighbour's, so a part doesn't creep across a gradient from one colour to a far one,
## like soft edges from a fill to its outline. The canvas needs a transparent border a
## pixel wide. With [param chain], pixels join when their colour is close to their
## neighbour's instead, so a part spreads along a gradient: for colours already reduced to
## a few (see [PixelPalette]), whose soft edges no longer bridge one colour to another.
static func find(
	pixel_colors: PackedInt32Array,
	width: int,
	sides: Array[int],
	tolerance := 0,
	chain := false,
) -> PixelParts:
	var found := PixelParts.new()
	found.part_of.resize(pixel_colors.size())
	found.part_of.fill(-1)
	for start in pixel_colors.size():
		if pixel_colors[start] == 0 or found.part_of[start] >= 0:
			continue
		var index := found.parts.size()
		var pixels := PackedInt32Array([start])
		found.part_of[start] = index
		var next := 0
		var color := pixel_colors[start]
		while next < pixels.size():
			var p := pixels[next]
			next += 1
			if chain:
				color = pixel_colors[p]
			for side in sides:
				var other := pixel_colors[p + side]
				if other == 0 or found.part_of[p + side] >= 0:
					continue
				if other == color or (tolerance > 0 and distance(color, other) <= tolerance):
					found.part_of[p + side] = index
					pixels.append(p + side)
		found.parts.append(pixels)
		found.colors.append(_average(pixel_colors, pixels))
	var straight: Array[int] = [-1, 1, -width, width]
	for index in found.parts.size():
		var ring := PackedInt32Array()
		var seen := {}
		for p in found.parts[index]:
			for side in straight:
				var q := p + side
				if found.part_of[q] != index and not seen.has(q):
					seen[q] = true
					ring.append(q)
		found.rings.append(ring)
	return found


## How far apart colours [param first] and [param second] are (see
## [method PixelCanvas.colors]): the sum of how far apart their red, green, blue and alpha
## are, 0 to 1020
static func distance(first: int, second: int) -> int:
	var apart := 0
	for shift in [24, 16, 8, 0]:
		apart += absi((first >> shift & 255) - (second >> shift & 255))
	return apart


## The average colour of [param pixels]
static func _average(pixel_colors: PackedInt32Array, pixels: PackedInt32Array) -> int:
	var first := pixel_colors[pixels[0]]
	var total := [0, 0, 0, 0]
	var same := true
	for p in pixels:
		var color := pixel_colors[p]
		same = same and color == first
		for c in 4:
			total[c] += color >> (24 - c * 8) & 255
	if same:
		return first
	var average := 0
	for c in 4:
		average = average << 8 | roundi(float(total[c]) / pixels.size())
	# Never 0, which is transparent
	return average if average != 0 else 1


## The canvas index steps to the 4 neighbours of a pixel, or the 8 with [param diagonal]
static func sides_of(width: int, diagonal := false) -> Array[int]:
	var sides: Array[int] = [-1, 1, -width, width]
	if diagonal:
		sides.append_array([-width - 1, -width + 1, width - 1, width + 1])
	return sides
