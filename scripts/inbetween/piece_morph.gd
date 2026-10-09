class_name PieceMorph
extends RefCounted
## In-betweens made of pieces, see [InBetween]. Each key is cut into regions (see
## [KeyRegions]); each region is followed to the other key (see [RegionMotions]); regions
## that move alike, or have no clear motion of their own, merge into pieces, like an arm,
## a blade or a whole body. Frames show each key's pieces turned about their joints part of
## the way, drawn smoothly (see [SmoothKey]) in the order they overlap, and the two keys
## combined: a pixel is shown where the key nearer in time shows it, and takes its colour
## from that key first. Every pixel is taken from a key, so no new colours appear.

## Room around the keys on the canvases, as a share of their size
const MARGIN := 0.5
## Leftovers paired across the keys (see [method _pair_leftovers]) are at least this many
## pixels, or this share of the sprite, and alike in colour (red, green and blue summed,
## 0 to 3) by this much
const LEFTOVER_PIXELS := 6
const LEFTOVER_SHARE := 0.01
const LEFTOVER_COLOR := 0.3
## Rounds of making the two keys' motions agree, see [method RegionMotions.agree]
const AGREEING := 2
## See [member smallest_part]
const FLOATING_SHARE := 0.02
## Sprites bigger than this many pixels across are worked out smaller, about this size,
## and drawn at their own: finding pieces and how they move works best at sizes like
## pixel art's, and much faster
const ANALYSIS_SIZE := 160.0

## The canvases' place, the same for both keys
var rect := Rect2i()
## The outline round both keys, taken off before matching and drawn round each frame
var outline: PixelOutline
## Key A going to B, and B going back to A
var sides: Array[KeySide] = []
## How far the whole sprite moves from key A to key B
var shift := Vector2.ZERO
## How many times smaller the keys were worked out, see [constant ANALYSIS_SIZE]
var zoom := 1
## The whole shape bending from key A to key B, see [ShapeBlend]; null when it can't
var blend: ShapeBlend
## How often each 3 × 3 shape of what's shown happens in the keys, for smoothing jags out
## of frames (see [method PixelCleanup.smooth_jags]), and how opaque a pixel must be to
## count; empty for keys worked out smaller than drawn
var key_shapes := PackedInt32Array()
var jag_alpha := 1
## The keys' 5 × 5 shapes, see [method PixelCleanup.wide_shapes_of]
var key_wide_shapes := {}
## Parts left floating in frames smaller than this many pixels are taken out: smaller than
## any separate part the keys have, and than [constant FLOATING_SHARE] of the sprite
var smallest_part := 0


## Pieces of keys [param a] and [param b] (see [method InBetween.key_of]) and how they
## move, the whole sprite moving by [param whole_motion] (found when zero, see
## [method SpriteMotion.detect]). Slow: [param progress] tells how far it got, and stops it
## when cancelled, returning null.
static func find(
	a: Dictionary, b: Dictionary, whole_motion := Vector2i.ZERO, progress: WorkProgress = null
) -> PieceMorph:
	if progress == null:
		progress = WorkProgress.new()
	if whole_motion == Vector2i.ZERO:
		whole_motion = SpriteMotion.detect(a, b)
	var morph := PieceMorph.new()
	var a_img := PixelCanvas.rgba(a.image)
	var b_img := PixelCanvas.rgba(b.image)
	morph.outline = PixelOutline.detect(a_img, b_img)
	if morph.outline:
		a_img = morph.outline.strip(a_img)
		b_img = morph.outline.strip(b_img)
	var keys := Rect2i(a.origin, a_img.get_size()).merge(Rect2i(b.origin, b_img.get_size()))
	var margin := ceili(maxi(keys.size.x, keys.size.y) * MARGIN) + 2
	morph.rect = keys.grow(margin)
	var width := morph.rect.size.x
	var height := morph.rect.size.y
	var a_data := PixelCanvas.draw(a_img, a.origin, morph.rect)
	var b_data := PixelCanvas.draw(b_img, b.origin, morph.rect)
	var a_shown := PixelCanvas.shown_area(PixelCanvas.colors(a_data), width, height)
	var b_shown := PixelCanvas.shown_area(PixelCanvas.colors(b_data), width, height)
	var size := float(maxi(1, maxi(a_shown.merge(b_shown).size.x, a_shown.merge(b_shown).size.y)))
	morph.shift = Vector2(whole_motion)
	# Big sprites are worked out smaller, then drawn at their size
	var zoom := maxi(1, ceili(size / ANALYSIS_SIZE))
	morph.zoom = zoom
	var small_width := ceili(float(width) / zoom)
	var small_height := ceili(float(height) / zoom)
	var a_small := _shrunk(a_data, width, height, zoom)
	var b_small := _shrunk(b_data, width, height, zoom)
	var small_size := size / zoom
	var depth := clampf(roundf(small_size / 12.0), 2.0, 12.0)
	var a_features := KeyFeatures.of(a_small, small_width, small_height, depth)
	var b_features := KeyFeatures.of(b_small, small_width, small_height, depth)
	var split := KeyRegions.split_colors_of(a_small, b_small)
	var painted := (
		split[0] != PixelCanvas.colors(a_small)
		or split[1] != PixelCanvas.colors(b_small)
		or zoom > 1
	)
	var a_regions := KeyRegions.of(a_small, small_width, split[0])
	var b_regions := KeyRegions.of(b_small, small_width, split[1])
	progress.total += a_regions.count() + b_regions.count()
	var shift := morph.shift / zoom
	var forward := RegionMotions.find(
		a_regions, a_features, b_regions, b_features, shift, small_size, progress
	)
	if progress.cancelled:
		return null
	var backward := RegionMotions.find(
		b_regions, b_features, a_regions, a_features, -shift, small_size, progress
	)
	if progress.cancelled:
		return null
	for _pass in AGREEING:
		forward.agree(backward)
		backward.agree(forward)
	_pair_leftovers(forward, backward, a_small, b_small)
	morph.blend = ShapeBlend.between(a_small, b_small, small_width, small_height, shift, small_size)
	if zoom == 1:
		# Painted keys' soft edges are told by the pixels at least half opaque
		morph.jag_alpha = 128 if painted else 1
		morph.key_shapes = PixelCleanup.shapes_of(a_data, width, height, morph.jag_alpha)
		var b_shapes := PixelCleanup.shapes_of(b_data, width, height, morph.jag_alpha)
		morph.key_wide_shapes = PixelCleanup.wide_shapes_of(a_data, width, height, morph.jag_alpha)
		morph.key_wide_shapes.merge(
			PixelCleanup.wide_shapes_of(b_data, width, height, morph.jag_alpha)
		)
		var shown := 0
		for p in a_data.size() / 4:
			if a_data[p * 4 + 3] >= morph.jag_alpha:
				shown += 1
		morph.smallest_part = int(shown * FLOATING_SHARE)
		for data in [a_data, b_data]:
			var parts := PixelCleanup.parts_of(data, width, morph.jag_alpha)
			var biggest := 0
			for part in parts:
				biggest = maxi(biggest, part.size())
			for part in parts:
				if part.size() < biggest:
					morph.smallest_part = mini(morph.smallest_part, part.size())
		for k in b_shapes.size():
			morph.key_shapes[k] += b_shapes[k]
	for follower in [forward, backward]:
		var side := KeySide.new()
		side.painted = painted
		side.data = a_small if follower == forward else b_small
		side.merge(follower, small_width)
		side.settle(b_small if follower == forward else a_small)
		side.choose_layers(morph.blend, follower == backward, follower)
		morph.sides.append(side)
	if zoom > 1:
		morph.sides[0].enlarge(a_data, width, zoom)
		morph.sides[1].enlarge(b_data, width, zoom)
	return morph


## Parts of regions neither key's motions explain, like an arm of the body's colour, left
## over in both keys where it was and where it went: paired across the keys by colour and
## size, nearest first, and split off their regions with the motion pairing them, see
## [method RegionMotions.split_off]
static func _pair_leftovers(
	forward: RegionMotions,
	backward: RegionMotions,
	a_data: PackedByteArray,
	b_data: PackedByteArray
) -> void:
	var total := 0
	for pixels in forward.regions.pixels:
		total += pixels.size()
	var least := maxi(LEFTOVER_PIXELS, int(total * LEFTOVER_SHARE))
	var a_left := forward.leftovers(least)
	var b_left := backward.leftovers(least)
	var taken := {}
	for a_entry in a_left:
		var a_patch: PackedInt32Array = a_entry[0]
		var a_color := KeyRegions.mean_color(a_data, a_patch)
		var best := -1
		var best_score := INF
		for k in b_left.size():
			if taken.has(k):
				continue
			var b_patch: PackedInt32Array = b_left[k][0]
			var ratio := float(b_patch.size()) / a_patch.size()
			var apart := KeyRegions.mean_color(b_data, b_patch) - a_color
			var color := absf(apart.x) + absf(apart.y) + absf(apart.z)
			if ratio < 0.5 or ratio > 2.0 or color > LEFTOVER_COLOR:
				continue
			var score := color + absf(log(ratio))
			if score < best_score:
				best_score = score
				best = k
		if best < 0:
			continue
		var b_patch: PackedInt32Array = b_left[best][0]
		var motion := forward.pairing(a_patch, b_patch)
		if forward.split_off(a_entry, motion, a_data):
			taken[best] = true
			backward.split_off(b_left[best], motion.affine_inverse(), b_data)


## [param data], a canvas [param width] × [param height] pixels, [param zoom] times
## smaller: each pixel the average of the ones it stands for, weighed by how shown
static func _shrunk(data: PackedByteArray, width: int, height: int, zoom: int) -> PackedByteArray:
	if zoom == 1:
		return data
	var small_width := ceili(float(width) / zoom)
	var small_height := ceili(float(height) / zoom)
	var out := PixelCanvas.blank(small_width * small_height)
	for sy in small_height:
		for sx in small_width:
			var sum := Vector4.ZERO
			var count := 0
			for y in range(sy * zoom, mini((sy + 1) * zoom, height)):
				for x in range(sx * zoom, mini((sx + 1) * zoom, width)):
					var i := (y * width + x) * 4
					var alpha := data[i + 3]
					sum += Vector4(data[i] * alpha, data[i + 1] * alpha, data[i + 2] * alpha, alpha)
					count += 1
			if sum.w <= 0.0:
				continue
			var o := (sy * small_width + sx) * 4
			out[o] = roundi(sum.x / sum.w)
			out[o + 1] = roundi(sum.y / sum.w)
			out[o + 2] = roundi(sum.z / sum.w)
			out[o + 3] = roundi(sum.w / count)
	return out


## The frame [param t] of the way from key A to key B. Each key's pieces are drawn where
## they are by then; where the two drawings differ, the outline is morphed between theirs
## (by how far inside or outside each a pixel is, the key nearer in time counting more),
## and each pixel takes its colour from the nearer key's drawing, else the other's, else
## the nearest pixel the nearer one shows.
func frame(t: float) -> Dictionary:
	var width := rect.size.x
	var height := rect.size.y
	if sides[0].lost or sides[1].lost:
		# The keys don't match up: the nearer one, moved with the whole sprite
		var nearer := sides[0] if t <= 0.5 else sides[1]
		var moved := (shift * (t if t <= 0.5 else t - 1.0)).round()
		var held := PixelCanvas.blank(width * height)
		for y in height:
			for x in width:
				var from := Vector2i(Vector2(x, y) - moved)
				if from.x < 0 or from.y < 0 or from.x >= width or from.y >= height:
					continue
				var q := from.y * width + from.x
				for c in 4:
					held[(y * width + x) * 4 + c] = nearer.data[q * 4 + c]
		if outline:
			outline.draw_data(held, width, height)
		return PixelCanvas.cropped(held, rect)
	var from_a := sides[0].drawn(t, width, height)
	var from_b := sides[1].drawn(1.0 - t, width, height)
	var near_first := t <= 0.5
	var near := from_a if near_first else from_b
	var far := from_b if near_first else from_a
	var near_mask := _mask(near)
	var far_mask := _mask(far)
	var a_mask := near_mask if near_first else far_mask
	var b_mask := far_mask if near_first else near_mask
	var a_inside := PixelCanvas.distances(a_mask, width, height, 1)
	var b_inside := PixelCanvas.distances(b_mask, width, height, 1)
	var a_outside: PackedInt32Array = PixelCanvas.distances(a_mask, width, height, 0)[0]
	var b_outside: PackedInt32Array = PixelCanvas.distances(b_mask, width, height, 0)[0]
	var a_to_inside: PackedInt32Array = a_inside[0]
	var b_to_inside: PackedInt32Array = b_inside[0]
	var near_nearest: PackedInt32Array = (a_inside if near_first else b_inside)[1]
	var far_nearest: PackedInt32Array = (b_inside if near_first else a_inside)[1]
	var out := PixelCanvas.blank(width * height)
	for p in width * height:
		# How far inside (negative) or outside each drawing the pixel is
		var a_side: int = -a_outside[p] if a_mask[p] else a_to_inside[p]
		var b_side: int = -b_outside[p] if b_mask[p] else b_to_inside[p]
		var side := a_side * (1.0 - t) + b_side * t
		# What the nearer drawing shows stays, so thin parts that don't overlap aren't lost.
		# Sprites drawn bigger than worked out show only it: being a pixel apart there is
		# being a few apart drawn, and the other's pixels round the nearer's outline would
		# spoil it.
		if near_mask[p] == 0 and (side >= 0.0 or zoom > 1):
			# Its faint pixels too, like a glow
			if near[p * 4 + 3] > 0:
				for c in 4:
					out[p * 4 + c] = near[p * 4 + c]
			continue
		var from := near
		var source := p
		if near_mask[p] == 0:
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
	PixelCleanup.tidy_data(out, width, height)
	if not key_shapes.is_empty():
		PixelCleanup.clear_floating(out, width, smallest_part, jag_alpha)
		PixelCleanup.smooth_jags(out, width, height, key_shapes, jag_alpha, key_wide_shapes)
	if outline:
		outline.draw_data(out, width, height)
	return PixelCanvas.cropped(out, rect)


## 1 where [param data] is shown, at least half opaque
static func _mask(data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data.size() / 4)
	for p in result.size():
		result[p] = 1 if data[p * 4 + 3] >= 128 else 0
	return result
