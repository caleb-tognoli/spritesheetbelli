class_name KeyFeatures
extends RefCounted
## What's compared when matching a key's pixels with the other key's, see [RegionMotions]:
## each pixel's colour (faded by how see-through it is), how much it's shown, and how deep
## inside the sprite it is, so even plain areas tell where in the shape they are.

## Features per pixel
const COUNT := 5
## How much each kind of feature counts: colour, being shown, depth inside
const SHOWN_WEIGHT := 1.5
const DEPTH_WEIGHT := 0.3
## Depth is counted up to this many times [member scale] in or out of the sprite
const DEPTH_REACH := 1.5

var width := 0
var height := 0
## [constant COUNT] numbers for each pixel of the canvas, one after another
var values := PackedFloat32Array()
## The size of things in the sprite: depth is measured in it
var scale := 2.0


## The features of [param data], a canvas [param canvas_width] × [param canvas_height]
## pixels, with depth measured in [param depth_scale] pixels
static func of(
	data: PackedByteArray, canvas_width: int, canvas_height: int, depth_scale: float
) -> KeyFeatures:
	if NativeKernels.kernels:
		return NativeKernels.features_of(data, canvas_width, canvas_height, depth_scale)
	var features := KeyFeatures.new()
	features.width = canvas_width
	features.height = canvas_height
	features.scale = depth_scale
	var count := canvas_width * canvas_height
	# Worked out round the pixels shown, with room for their depth to reach out: farther
	# out, nothing is shown and the depth is as far out as it's counted
	var reach := ceili(DEPTH_REACH * depth_scale) + 1
	var area := PixelCanvas.shown_rect(data, canvas_width, canvas_height, reach)
	var none := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, -DEPTH_REACH * DEPTH_WEIGHT])
	var found := none
	while found.size() < count * COUNT:
		found.append_array(found.duplicate())
	found.resize(count * COUNT)
	features.values = found
	var w := area.size.x
	var h := area.size.y
	var shown := PackedByteArray()
	shown.resize(w * h)
	for y in h:
		var row := (y + area.position.y) * canvas_width + area.position.x
		for x in w:
			shown[y * w + x] = 1 if data[(row + x) * 4 + 3] >= 128 else 0
	# Distances in thirds of a pixel, to the nearest pixel not shown, and to the nearest
	# shown: as on the whole canvas, as the area holds every pixel shown and, but at the
	# canvas's edge, pixels not shown all round (see PixelCanvas.distances)
	var far := (canvas_width + canvas_height) * 4
	var inside: PackedInt32Array = PixelCanvas.distances(shown, w, h, 0, far)[0]
	var outside: PackedInt32Array = PixelCanvas.distances(shown, w, h, 1, far)[0]
	for y in h:
		var row := (y + area.position.y) * canvas_width + area.position.x
		for x in w:
			var p := row + x
			var alpha := data[p * 4 + 3] / 255.0
			var i := p * COUNT
			found[i] = data[p * 4] / 255.0 * alpha
			found[i + 1] = data[p * 4 + 1] / 255.0 * alpha
			found[i + 2] = data[p * 4 + 2] / 255.0 * alpha
			found[i + 3] = alpha * SHOWN_WEIGHT
			var depth := (inside[y * w + x] - outside[y * w + x]) / 3.0 / depth_scale
			found[i + 4] = clampf(depth, -DEPTH_REACH, DEPTH_REACH) * DEPTH_WEIGHT
	return features


## How different pixel [param p] of these features is from [param other]'s at point
## [param at] (pixel centres are at half pixels), read between pixels; outside the canvas
## nothing is shown
func difference(p: int, other: KeyFeatures, at: Vector2) -> float:
	var x := at.x - 0.5
	var y := at.y - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var w := other.width
	var o := other.values
	# The four pixels around the point, weighted by how near; none outside the canvas
	var w00 := (1.0 - fx) * (1.0 - fy)
	var w10 := fx * (1.0 - fy)
	var w01 := (1.0 - fx) * fy
	var w11 := fx * fy
	if x0 < 0 or y0 < 0:
		w00 = 0.0
	if x0 + 1 >= w or y0 < 0:
		w10 = 0.0
	if x0 < 0 or y0 + 1 >= other.height:
		w01 = 0.0
	if x0 + 1 >= w or y0 + 1 >= other.height:
		w11 = 0.0
	if x0 + 1 < 0 or y0 + 1 < 0 or x0 >= w or y0 >= other.height:
		# Wholly outside: nothing shown there
		var none := 0.0
		for c in COUNT:
			none += absf(values[p * COUNT + c])
		return none
	var q00 := (clampi(y0, 0, other.height - 1) * w + clampi(x0, 0, w - 1)) * COUNT
	var q10 := (clampi(y0, 0, other.height - 1) * w + clampi(x0 + 1, 0, w - 1)) * COUNT
	var q01 := (clampi(y0 + 1, 0, other.height - 1) * w + clampi(x0, 0, w - 1)) * COUNT
	var q11 := (clampi(y0 + 1, 0, other.height - 1) * w + clampi(x0 + 1, 0, w - 1)) * COUNT
	var i := p * COUNT
	var total := 0.0
	for c in COUNT:
		var sampled := o[q00 + c] * w00 + o[q10 + c] * w10 + o[q01 + c] * w01 + o[q11 + c] * w11
		total += absf(values[i + c] - sampled)
	return total


## [method difference] summed over every [param stride]th of [param pixels] (canvas
## indices), each pixel's middle taken where [param motion] takes it and each difference
## capped at [param cap]; with [param move_cost], each pixel also costs that much for each
## pixel it lands from where [param shift] alone would take it. The same as calling
## [method difference] for each, much faster.
func landing_sum(
	pixels: PackedInt32Array,
	stride: int,
	motion: Transform2D,
	other: KeyFeatures,
	cap: float,
	move_cost := 0.0,
	shift := Vector2.ZERO
) -> float:
	if NativeKernels.kernels:
		return NativeKernels.landing_sum(self, pixels, stride, motion, other, cap, move_cost, shift)
	var own := values
	var o := other.values
	var w := other.width
	var h := other.height
	var row := w * COUNT
	var total := 0.0
	for k in range(0, pixels.size(), stride):
		var p := pixels[k]
		var at := Vector2(p % width + 0.5, p / width + 0.5)
		var landed := motion * at
		var x := landed.x - 0.5
		var y := landed.y - 0.5
		var x0 := floori(x)
		var y0 := floori(y)
		var i := p * COUNT
		var d := 0.0
		if x0 >= 0 and y0 >= 0 and x0 + 1 < w and y0 + 1 < h:
			# Wholly inside, the usual case: as in difference, without its checks
			var fx := x - x0
			var fy := y - y0
			var w00 := (1.0 - fx) * (1.0 - fy)
			var w10 := fx * (1.0 - fy)
			var w01 := (1.0 - fx) * fy
			var w11 := fx * fy
			var q00 := (y0 * w + x0) * COUNT
			var q10 := q00 + COUNT
			var q01 := q00 + row
			var q11 := q01 + COUNT
			var sampled := o[q00] * w00 + o[q10] * w10 + o[q01] * w01 + o[q11] * w11
			d += absf(own[i] - sampled)
			sampled = o[q00 + 1] * w00 + o[q10 + 1] * w10 + o[q01 + 1] * w01 + o[q11 + 1] * w11
			d += absf(own[i + 1] - sampled)
			sampled = o[q00 + 2] * w00 + o[q10 + 2] * w10 + o[q01 + 2] * w01 + o[q11 + 2] * w11
			d += absf(own[i + 2] - sampled)
			sampled = o[q00 + 3] * w00 + o[q10 + 3] * w10 + o[q01 + 3] * w01 + o[q11 + 3] * w11
			d += absf(own[i + 3] - sampled)
			sampled = o[q00 + 4] * w00 + o[q10 + 4] * w10 + o[q01 + 4] * w01 + o[q11 + 4] * w11
			d += absf(own[i + 4] - sampled)
		else:
			d = difference(p, other, landed)
		total += minf(d, cap)
		if move_cost != 0.0:
			total += move_cost * landed.distance_to(at + shift)
	return total


## [method landing_sum], given up as soon as the sum so far is over [param bound]: then
## what it is so far, over [param bound] and no more than the whole sum
func landing_sum_below(
	pixels: PackedInt32Array,
	stride: int,
	motion: Transform2D,
	other: KeyFeatures,
	cap: float,
	move_cost: float,
	shift: Vector2,
	bound: float
) -> float:
	if NativeKernels.kernels:
		return NativeKernels.landing_sum(
			self, pixels, stride, motion, other, cap, move_cost, shift, bound
		)
	var own := values
	var o := other.values
	var w := other.width
	var h := other.height
	var row := w * COUNT
	var total := 0.0
	for k in range(0, pixels.size(), stride):
		var p := pixels[k]
		var at := Vector2(p % width + 0.5, p / width + 0.5)
		var landed := motion * at
		var x := landed.x - 0.5
		var y := landed.y - 0.5
		var x0 := floori(x)
		var y0 := floori(y)
		var i := p * COUNT
		var d := 0.0
		if x0 >= 0 and y0 >= 0 and x0 + 1 < w and y0 + 1 < h:
			var fx := x - x0
			var fy := y - y0
			var w00 := (1.0 - fx) * (1.0 - fy)
			var w10 := fx * (1.0 - fy)
			var w01 := (1.0 - fx) * fy
			var w11 := fx * fy
			var q00 := (y0 * w + x0) * COUNT
			var q10 := q00 + COUNT
			var q01 := q00 + row
			var q11 := q01 + COUNT
			var sampled := o[q00] * w00 + o[q10] * w10 + o[q01] * w01 + o[q11] * w11
			d += absf(own[i] - sampled)
			sampled = o[q00 + 1] * w00 + o[q10 + 1] * w10 + o[q01 + 1] * w01 + o[q11 + 1] * w11
			d += absf(own[i + 1] - sampled)
			sampled = o[q00 + 2] * w00 + o[q10 + 2] * w10 + o[q01 + 2] * w01 + o[q11 + 2] * w11
			d += absf(own[i + 2] - sampled)
			sampled = o[q00 + 3] * w00 + o[q10 + 3] * w10 + o[q01 + 3] * w01 + o[q11 + 3] * w11
			d += absf(own[i + 3] - sampled)
			sampled = o[q00 + 4] * w00 + o[q10 + 4] * w10 + o[q01 + 4] * w01 + o[q11 + 4] * w11
			d += absf(own[i + 4] - sampled)
		else:
			d = difference(p, other, landed)
		total += minf(d, cap)
		if move_cost != 0.0:
			total += move_cost * landed.distance_to(at + shift)
		if total > bound:
			return total
	return total
