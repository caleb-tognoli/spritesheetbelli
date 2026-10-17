class_name PixelCleanup
extends RefCounted
## Tidies up frames made pixel by pixel, see [InBetween]: stray pixels standing alone in
## the open are taken out and pinholes are filled, so in-betweens look drawn rather than
## scattered. Lone pixels inside the sprite, like eyes, stay.

## Neighbours (of 8) that must be transparent for a pixel with none of its colour around
## to be a stray one: nearly all, so details of the keys, like a lone pixel on an edge,
## stay
const STRAY_OPEN := 7
## Rounds of smoothing jags, see [method smooth_jags], and the bit for a pixel itself in
## the shapes round it
const JAG_ROUNDS := 2
const CENTER := 1 << 4
const WIDE_CENTER := 1 << 12


## [param frame] ([code]{"image", "origin"}[/code]) tidied up, see [PixelCleanup]
static func tidy(frame: Dictionary) -> Dictionary:
	var img: Image = frame.image
	var rect := Rect2i(frame.origin - Vector2i.ONE, img.get_size() + Vector2i(2, 2))
	var data := PixelCanvas.draw(img, frame.origin, rect)
	tidy_data(data, rect.size.x, rect.size.y)
	return PixelCanvas.cropped(data, rect)


## Tidies up [param data], a canvas [param width] × [param height] pixels with a
## transparent border, in place
static func tidy_data(data: PackedByteArray, width: int, height: int) -> void:
	var colors := PixelCanvas.colors(data)
	var sides := PixelParts.sides_of(width, true)
	var area := PixelCanvas.shown_area(colors, width, height)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			var color := colors[p]
			var clear := 0
			var same := 0
			for side in sides:
				var other := colors[p + side]
				if other == 0:
					clear += 1
				elif other == color:
					same += 1
			if color != 0 and same == 0 and clear >= STRAY_OPEN:
				for c in 4:
					data[p * 4 + c] = 0
			elif color == 0 and _enclosed(colors, p, width):
				# Filled with the colour most of its neighbours have
				var best := _most_common(colors, p, sides)
				data[p * 4] = best >> 24 & 255
				data[p * 4 + 1] = best >> 16 & 255
				data[p * 4 + 2] = best >> 8 & 255
				data[p * 4 + 3] = best & 255


## Whether the pixels above, below and to either side of pixel [param p] are all shown
static func _enclosed(colors: PackedInt32Array, p: int, width: int) -> bool:
	return (
		colors[p - 1] != 0
		and colors[p + 1] != 0
		and colors[p - width] != 0
		and colors[p + width] != 0
	)


## The colour most of the neighbours of pixel [param p] have, across [param sides]
static func _most_common(colors: PackedInt32Array, p: int, sides: Array[int]) -> int:
	var counts := {}
	var best := 0
	for side in sides:
		var other := colors[p + side]
		if other != 0:
			counts[other] = counts.get(other, 0) + 1
			if best == 0 or counts[other] > counts[best]:
				best = other
	return best


## How often each 3 × 3 shape of what's shown (at least [param least_alpha] opaque) happens
## in [param data] (a canvas [param width] × [param height] pixels): 512 counts, by
## [method _shape_at]
static func shapes_of(
	data: PackedByteArray, width: int, height: int, least_alpha := 1
) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(512)
	var mask := _shown(data, least_alpha)
	var area := PixelCanvas.shown_area(PixelCanvas.colors(data), width, height)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			counts[_shape_at(mask, y * width + x, width)] += 1
	return counts


## Smooths the outline of [param data] (a canvas [param width] × [param height] pixels with
## a transparent border) as the keys draw theirs: pixels sticking out on their own and
## notches a pixel wide whose 3 × 3 shape never happens in the keys ([param shapes], see
## [method shapes_of]) are taken out or filled when the other way it does, so jags the keys
## don't have go. Filled ones take the colour most of their neighbours have.
static func smooth_jags(
	data: PackedByteArray,
	width: int,
	height: int,
	shapes: PackedInt32Array,
	least_alpha := 1,
	wide_shapes := {}
) -> void:
	var sides := PixelParts.sides_of(width, true)
	for _round in JAG_ROUNDS:
		var mask := _shown(data, least_alpha)
		var colors := PixelCanvas.colors(data)
		var area := PixelCanvas.shown_area(colors, width, height)
		var changed := false
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var p := y * width + x
				var shape := _shape_at(mask, p, width)
				var flipped := shape ^ CENTER
				# Only a pixel sticking out on its own, or a notch a pixel wide
				var shown_sides := mask[p - 1] + mask[p + 1] + mask[p - width] + mask[p + width]
				var jag := (shown_sides <= 1) if mask[p] == 1 else (shown_sides >= 3)
				var smoothed := jag and shapes[shape] == 0 and shapes[flipped] > 0
				# Or wider: the 5 × 5 round it the keys never have, but would flipped
				if not smoothed and not wide_shapes.is_empty() and _wide_fits(p, width, height):
					var wide := _wide_at(mask, p, width)
					smoothed = (not wide_shapes.has(wide) and wide_shapes.has(wide ^ WIDE_CENTER))
				if not smoothed:
					continue
				if mask[p] == 1:
					for c in 4:
						data[p * 4 + c] = 0
				else:
					var best := _most_common(colors, p, sides)
					data[p * 4] = best >> 24 & 255
					data[p * 4 + 1] = best >> 16 & 255
					data[p * 4 + 2] = best >> 8 & 255
					data[p * 4 + 3] = best & 255
				mask[p] = 1 - mask[p]
				changed = true
		if not changed:
			return


## The 5 × 5 shapes of what [param data] (a canvas [param width] × [param height] pixels)
## shows at least [param least_alpha] opaque, as keys of a dictionary, by [method _wide_at]
static func wide_shapes_of(
	data: PackedByteArray, width: int, height: int, least_alpha := 1
) -> Dictionary:
	var found := {}
	var mask := _shown(data, least_alpha)
	var area := PixelCanvas.shown_area(PixelCanvas.colors(data), width, height)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if _wide_fits(p, width, height):
				found[_wide_at(mask, p, width)] = true
	return found


## Whether the 5 × 5 round pixel [param p] is on the canvas
static func _wide_fits(p: int, width: int, height: int) -> bool:
	var x := p % width
	var y := p / width
	return x >= 2 and y >= 2 and x < width - 2 and y < height - 2


## The 5 × 5 shape of [param mask] round pixel [param p] as 25 bits, the pixel itself
## [constant WIDE_CENTER]
static func _wide_at(mask: PackedByteArray, p: int, width: int) -> int:
	var bits := 0
	var bit := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if mask[p + dy * width + dx] == 1:
				bits |= 1 << bit
			bit += 1
	return bits


## 1 for each pixel of [param data] at least [param least_alpha] opaque
static func _shown(data: PackedByteArray, least_alpha: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data.size() / 4)
	for p in result.size():
		result[p] = 1 if data[p * 4 + 3] >= least_alpha else 0
	return result


## The 3 × 3 shape of [param mask] round pixel [param p] as 9 bits, the pixel itself
## [constant CENTER]
static func _shape_at(mask: PackedByteArray, p: int, width: int) -> int:
	var bits := 0
	var bit := 0
	for dy: int in [-width, 0, width]:
		for dx: int in [-1, 0, 1]:
			if mask[p + dy + dx] == 1:
				bits |= 1 << bit
			bit += 1
	return bits


## The separate parts of what [param data] (a canvas [param width] pixels wide) shows at
## least [param least_alpha] opaque, touching across corners too: each part's pixels
static func parts_of(
	data: PackedByteArray, width: int, least_alpha := 1
) -> Array[PackedInt32Array]:
	var mask := _shown(data, least_alpha)
	var seen := PackedByteArray()
	seen.resize(mask.size())
	var sides := PixelParts.sides_of(width, true)
	var parts: Array[PackedInt32Array] = []
	for start in mask.size():
		if mask[start] == 0 or seen[start] == 1:
			continue
		var part := PackedInt32Array([start])
		seen[start] = 1
		var next := 0
		while next < part.size():
			var p := part[next]
			next += 1
			var x := p % width
			for side in sides:
				var q: int = p + side
				if q < 0 or q >= mask.size() or absi(q % width - x) > 1:
					continue
				if mask[q] == 1 and seen[q] == 0:
					seen[q] = 1
					part.append(q)
		parts.append(part)
	return parts


## Takes out the parts of [param data], a canvas [param width] pixels wide (see
## [method parts_of]), smaller than
## [param smaller_than] pixels, other than the biggest, and the see-through pixels right
## round them: bits left floating, like a line that came off what it was drawn round
static func clear_floating(
	data: PackedByteArray, width: int, smaller_than: int, least_alpha := 1
) -> void:
	var parts := parts_of(data, width, least_alpha)
	if parts.size() < 2:
		return
	var biggest := 0
	for k in parts.size():
		if parts[k].size() > parts[biggest].size():
			biggest = k
	var sides := PixelParts.sides_of(width, true)
	for k in parts.size():
		if k == biggest or parts[k].size() >= smaller_than:
			continue
		for p in parts[k]:
			for c in 4:
				data[p * 4 + c] = 0
		for p in parts[k]:
			for side in sides:
				var q: int = p + side
				if q < 0 or q * 4 >= data.size() or data[q * 4 + 3] >= least_alpha:
					continue
				for c in 4:
					data[q * 4 + c] = 0
