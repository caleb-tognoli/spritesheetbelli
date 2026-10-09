class_name PixelOutline
extends RefCounted
## The outline drawn around a sprite, one colour a pixel thick, as pixel art often has.
## The outline bends with every part that moves, so it can't be moved like a part: it's
## taken off the keys before they're matched (see [method strip]) and drawn again around
## each frame made (see [method draw_around]). See [PartMorph].

## Share of the pixels along a sprite's edge that must be of one colour for it to be an
## outline
const EDGE_SHARE := 0.6
## Fewest edge pixels a sprite needs to tell an outline
const MIN_EDGE := 8
## Share of an outline's pixels that may come out otherwise when it's drawn again round the
## sprite without it, see [method draw_data]
const REDRAWN_MISS := 0.25

## The outline's colour, see [method PixelCanvas.colors]
var color := 0
## The colour's RGBA bytes
var bytes := PackedByteArray()
## Whether it's drawn across corners too, round pixels touching the sprite only
## diagonally, where [member drawn] doesn't say
var diagonal := false
## How the keys draw it: for each way the 8 pixels round a pixel outside the sprite can be
## shown (a bit each, see [method _around]), how often the keys put the outline there and
## how often they don't, so corners come out as the artist draws them
var drawn := PackedInt32Array()
var not_drawn := PackedInt32Array()
## The same for the 24 pixels two round, told apart first: how often the outline is there
## less how often it isn't
var drawn_wide := {}


## The outline both [param a] and [param b] have, or null when they don't share one
static func detect(a: Image, b: Image) -> PixelOutline:
	var a_outline := _detect_one(PixelCanvas.rgba(a))
	var b_outline := _detect_one(PixelCanvas.rgba(b))
	if a_outline == null or b_outline == null or a_outline.color != b_outline.color:
		return null
	for k in 256:
		a_outline.drawn[k] += b_outline.drawn[k]
		a_outline.not_drawn[k] += b_outline.not_drawn[k]
	for around: int in b_outline.drawn_wide:
		a_outline.drawn_wide[around] = (
			a_outline.drawn_wide.get(around, 0) + b_outline.drawn_wide[around]
		)
	return a_outline


static func _detect_one(img: Image) -> PixelOutline:
	var width := img.get_width() + 2
	var height := img.get_height() + 2
	var data := PixelCanvas.draw(img, Vector2i.ONE, Rect2i(0, 0, width, height))
	var colors := PixelCanvas.colors(data)
	var counts := {}
	var edge := 0
	for p in colors.size():
		if colors[p] != 0 and _touches_clear(colors, p, width):
			edge += 1
			counts[colors[p]] = counts.get(colors[p], 0) + 1
	if edge < MIN_EDGE:
		return null
	var best := 0
	for color: int in counts:
		if best == 0 or counts[color] > counts[best]:
			best = color
	if counts[best] < edge * EDGE_SHARE:
		return null
	var outline := PixelOutline.new()
	outline.color = best
	outline.bytes = PackedByteArray(
		[best >> 24 & 255, best >> 16 & 255, best >> 8 & 255, best & 255]
	)
	var stripped := outline.strip_data(data, width)
	# Something of other colours is inside it: a sprite of one colour isn't outlined
	var inner := PixelCanvas.colors(stripped)
	var inner_edge := 0
	var inner_outline := 0
	for p in inner.size():
		if inner[p] != 0 and _touches_clear(inner, p, width):
			inner_edge += 1
			if inner[p] == best:
				inner_outline += 1
	if inner_edge == 0 or inner_outline * 2 > inner_edge:
		return null
	# Drawn across corners when doing so gives back the outline the key has
	var missed := [0, 0]
	for corners in 2:
		var drawn := stripped.duplicate()
		outline.diagonal = corners == 1
		outline.draw_data(drawn, width, height)
		var drawn_colors := PixelCanvas.colors(drawn)
		for p in colors.size():
			if (colors[p] == best) != (drawn_colors[p] == best):
				missed[corners] += 1
	outline.diagonal = missed[1] < missed[0]
	# An outline is drawn back where it was: lines of its colour that aren't round
	# anything, like a blade, aren't one
	if mini(missed[0], missed[1]) > counts[best] * REDRAWN_MISS:
		return null
	# How the key draws it round each shape of corner
	var shown := PixelCanvas.mask(stripped)
	outline.drawn.resize(256)
	outline.not_drawn.resize(256)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var p := y * width + x
			if shown[p] == 1:
				continue
			var around := _around(shown, p, width)
			if around == 0:
				continue
			var wide := _around(shown, p, width, 2)
			var vote := 1 if colors[p] == best else -1
			outline.drawn_wide[wide] = outline.drawn_wide.get(wide, 0) + vote
			if colors[p] == best:
				outline.drawn[around] += 1
			else:
				outline.not_drawn[around] += 1
	return outline


## The pixels up to [param reach] round pixel [param p] of [param shown] (1 for shown), a
## bit each, from the top left across and down; those off it count as not shown
static func _around(shown: PackedByteArray, p: int, width: int, reach := 1) -> int:
	var bits := 0
	var bit := 0
	var x := p % width
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx == 0 and dy == 0:
				continue
			var q := p + dy * width + dx
			if x + dx >= 0 and x + dx < width and q >= 0 and q < shown.size() and shown[q] == 1:
				bits |= 1 << bit
			bit += 1
	return bits


static func _touches_clear(colors: PackedInt32Array, p: int, width: int) -> bool:
	return (
		colors[p - 1] == 0 or colors[p + 1] == 0 or colors[p - width] == 0 or colors[p + width] == 0
	)


## [param img] without its outline: the outline's pixels along the sprite's edge made
## transparent, while ones inside, like eyes or lines between parts, stay
func strip(img: Image) -> Image:
	var source := PixelCanvas.rgba(img)
	var width := source.get_width() + 2
	var height := source.get_height() + 2
	var data := PixelCanvas.draw(source, Vector2i.ONE, Rect2i(0, 0, width, height))
	var stripped := strip_data(data, width)
	var padded := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, stripped)
	return padded.get_region(Rect2i(Vector2i.ONE, source.get_size()))


## [param data], a canvas [param width] pixels wide with a transparent border, without the
## outline along its edge
func strip_data(data: PackedByteArray, width: int) -> PackedByteArray:
	var colors := PixelCanvas.colors(data)
	var stripped := data.duplicate()
	for p in colors.size():
		if colors[p] == color and _touches_clear(colors, p, width):
			for c in 4:
				stripped[p * 4 + c] = 0
	return stripped


## Draws the outline around what [param data] shows, a canvas [param width] ×
## [param height] pixels with a transparent border
func draw_data(data: PackedByteArray, width: int, height: int) -> void:
	var shown := PixelCanvas.mask(data)
	var sides := PixelParts.sides_of(width, diagonal)
	var area := PixelCanvas.shown_area(PixelCanvas.colors(data), width, height)
	var learnt := not drawn.is_empty()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := y * width + x
			if shown[p] == 1:
				continue
			var around := _around(shown, p, width) if learnt else 0
			var wide := _around(shown, p, width, 2) if learnt and around != 0 else 0
			var outlined := false
			if learnt and drawn_wide.get(wide, 0) != 0:
				# As the keys draw it round the same shape, two pixels round
				outlined = drawn_wide[wide] > 0
			elif learnt and drawn[around] + not_drawn[around] > 0:
				# As the keys draw it round the same shape
				outlined = drawn[around] > not_drawn[around]
			else:
				for side in sides:
					if shown[p + side] == 1:
						outlined = true
						break
			if outlined:
				for c in 4:
					data[p * 4 + c] = bytes[c]
