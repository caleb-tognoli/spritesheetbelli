class_name PieceMorph
extends RefCounted
## In-betweens made of pieces, see [InBetween]. Each key is cut into regions (see
## [KeyRegions]); each region is followed to the other key (see [RegionMotions]); regions
## that move alike, or have no clear motion of their own, merge into pieces, like an arm,
## a blade or a whole body. Each key, cut into triangles, is then laid onto the other,
## its pieces carrying it there first and its pixels matched to the other key's after
## (see [KeyMesh]). Frames show each key bent part of the way, its pixels moved by whole
## pixels, and the two keys combined: a pixel is shown where the key nearer in time shows
## it, and takes its colour from that key first. Every pixel is taken from a key, so no
## new colours appear. Keys whose pieces alone land well, or that can't be cut into
## triangles, are drawn as pieces turned about their joints (see [SmoothKey]).
##
## Painted keys with soft edges are followed pixel by pixel instead, see [FlowMorph]: they
## bend more like cloth than turn like pieces, and their soft edges would make poor pieces.

## Room around the keys on the canvases, as a share of their size, and for keys followed
## pixel by pixel (see [FlowMorph])
const MARGIN := 0.5
const FLOW_MARGIN := 0.1
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
## Keys whose pieces land on the other key this well both ways (see [method _fit_of]: a
## share of how a pixel off would land) are drawn as their pieces, turned about their
## joints, rather than bent (see [KeyMesh]): they move rigidly, and bending only blurs them
const PIECES_FIT := 0.45
## Keys that don't match up (see [member KeySide.lost]) are bent only when key A bent onto
## B and B bent onto A agree on how the sprite turns as a whole, their turns undoing each
## other within this many radians; otherwise the bend is a guess that can lay one pose
## sideways onto the other, and frames hold the nearer key instead
const LOST_TURNS_APART := 2.0
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
## The keys followed pixel by pixel, for painted keys with soft edges (see [FlowMorph]);
## null when they're cut into pieces
var flow: FlowMorph
## Key A's triangles laid onto key B and B's onto A, see [KeyMesh]; empty when they
## can't be made
var meshes: Array[KeyMesh] = []


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
	if FlowMorph.soft(a_img, b_img):
		var flowing := _flowing(a, b, a_img, b_img, whole_motion, progress)
		if flowing != null or progress.cancelled:
			return flowing
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
	progress.total += a_regions.count() + b_regions.count() + 2 * KeyMesh.steps()
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
	# Bent unless the pieces alone land well, laid with the pieces as worked out, before
	# they're made the keys' size
	if _fit_of(morph.sides[0]) > PIECES_FIT or _fit_of(morph.sides[1]) > PIECES_FIT:
		var a_mesh := KeyMesh.lay(
			a_small, b_small, small_width, small_height, morph.sides[0], progress
		)
		var b_mesh := KeyMesh.lay(
			b_small, a_small, small_width, small_height, morph.sides[1], progress
		)
		if progress.cancelled:
			return null
		var lost := morph.sides[0].lost or morph.sides[1].lost
		if (
			a_mesh
			and b_mesh
			and not (
				lost
				and absf(angle_difference(-a_mesh.whole_turn(), b_mesh.whole_turn()))
				> LOST_TURNS_APART
			)
		):
			a_mesh.draw_from(a_data, zoom)
			b_mesh.draw_from(b_data, zoom)
			morph.meshes = [a_mesh, b_mesh]
	else:
		progress.done += 2 * KeyMesh.steps()
	if zoom > 1:
		morph.sides[0].enlarge(a_data, width, zoom)
		morph.sides[1].enlarge(b_data, width, zoom)
	return morph


## Keys [param a] and [param b], their images [param a_img] and [param b_img], followed
## pixel by pixel (see [FlowMorph]), the whole sprite moving by [param whole_motion]; null
## when they can't be or [param progress] is cancelled
static func _flowing(
	a: Dictionary,
	b: Dictionary,
	a_img: Image,
	b_img: Image,
	whole_motion: Vector2i,
	progress: WorkProgress
) -> PieceMorph:
	var morph := PieceMorph.new()
	var keys := Rect2i(a.origin, a_img.get_size()).merge(Rect2i(b.origin, b_img.get_size()))
	# Pixels only move between where they are in the keys: a little room is enough
	var margin := ceili(maxi(keys.size.x, keys.size.y) * FLOW_MARGIN) + 2
	morph.rect = keys.grow(margin)
	morph.shift = Vector2(whole_motion)
	var a_data := PixelCanvas.draw(a_img, a.origin, morph.rect)
	var b_data := PixelCanvas.draw(b_img, b.origin, morph.rect)
	morph.flow = FlowMorph.between(
		a_data, b_data, morph.rect.size.x, morph.rect.size.y, morph.shift, progress
	)
	return morph if morph.flow != null else null


## How well [param side]'s pieces land on the other key: their fits (see
## [member KeySide.fits]) averaged, weighted by their pixels
static func _fit_of(side: KeySide) -> float:
	var total := 0.0
	var count := 0
	for r in side.fits.size():
		var pixels := side.pieces.pixels[r].size()
		total += side.fits[r] * pixels
		count += pixels
	return total / count if count > 0 else 0.0


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


## The frame [param t] of the way from key A to key B. Each key is drawn bent part of the
## way (see [KeyMesh]); where the two drawings differ, the outline is morphed between
## theirs (by how far inside or outside each a pixel is, the key nearer in time counting
## more), and each pixel takes its colour from the nearer key's drawing, else the other's,
## else the nearest pixel the nearer one shows. Keys that don't match up take every colour
## from the nearer one.
##
## [param pins] steer the frames like a puppet's (see [PinWarp]): each a Dictionary with
## "at", a point of the sprite as the frame halfway shows it, and "to", where it goes
## there, both placed as frames are (Vector2). A pin left where it was holds its spot; a
## dragged one pulls the part round it, and what's far from every pin stays. Bent keys and
## keys followed pixel by pixel bend round the pins as they move; keys drawn as pieces are
## bent round them afterwards, each pin moving along with the whole sprite.
## Frames can be drawn on several threads at once.
func frame(t: float, pins: Array[Dictionary] = []) -> Dictionary:
	# The pins on the canvas
	var pin_from := PackedVector2Array()
	var pin_to := PackedVector2Array()
	if PinWarp.weight(t) > 0.0:
		for pin in pins:
			pin_from.append(Vector2(pin.at) - Vector2(rect.position))
			pin_to.append(Vector2(pin.to) - Vector2(rect.position))
	if flow:
		return PixelCanvas.cropped(flow.frame(t, pin_from, pin_to), rect)
	var width := rect.size.x
	var height := rect.size.y
	var bent := not meshes.is_empty()
	# Keys that don't match up show only the nearer one's colours
	var lost := sides[0].lost or sides[1].lost
	if lost and not bent:
		# Nor bend: the nearer one, moved with the whole sprite
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
		held = _pinned(held, t, pin_from, pin_to)
		if outline:
			outline.draw_data(held, width, height)
		return PixelCanvas.cropped(held, rect)
	var from_a: PackedByteArray
	var from_b: PackedByteArray
	if bent:
		# Pins where the triangles are, as worked out
		var mesh_from := pin_from.duplicate()
		var mesh_to := pin_to.duplicate()
		for k in mesh_from.size():
			mesh_from[k] /= zoom
			mesh_to[k] /= zoom
		from_a = meshes[0].drawn(t, mesh_from, mesh_to)
		from_b = meshes[1].drawn(1.0 - t, mesh_from, mesh_to)
	else:
		from_a = sides[0].drawn(t, width, height)
		from_b = sides[1].drawn(1.0 - t, width, height)
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
			if far_mask[p] == 1 and not lost:
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
	if not bent:
		out = _pinned(out, t, pin_from, pin_to)
	return _finished(out)


## [param data], the frame [param t] of the way on the canvas, bent round the pins
## [param pin_from] going to [param pin_to] (see [method frame]): each pin moved along with
## the whole sprite from halfway, and [method PinWarp.weight] of its way, see
## [method PinWarp.warped]
func _pinned(
	data: PackedByteArray, t: float, pin_from: PackedVector2Array, pin_to: PackedVector2Array
) -> PackedByteArray:
	var amount := PinWarp.weight(t)
	if pin_from.is_empty() or amount <= 0.0:
		return data
	var froms := PackedVector2Array()
	var tos := PackedVector2Array()
	for k in pin_from.size():
		var now := pin_from[k] + shift * (t - 0.5)
		froms.append(now)
		tos.append(now + (pin_to[k] - pin_from[k]) * amount)
	return PinWarp.warped(data, rect.size.x, rect.size.y, froms, tos)


## [param out], a frame on the canvas, tidied up, outlined and cut to what it shows
func _finished(out: PackedByteArray) -> Dictionary:
	var width := rect.size.x
	var height := rect.size.y
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
