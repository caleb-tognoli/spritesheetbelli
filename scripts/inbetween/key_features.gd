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
	var features := KeyFeatures.new()
	features.width = canvas_width
	features.height = canvas_height
	features.scale = depth_scale
	var count := canvas_width * canvas_height
	var shown := PackedByteArray()
	shown.resize(count)
	for p in count:
		shown[p] = 1 if data[p * 4 + 3] >= 128 else 0
	# Distances in thirds of a pixel, to the nearest pixel not shown, and to the nearest shown
	var inside: PackedInt32Array = PixelCanvas.distances(shown, canvas_width, canvas_height, 0)[0]
	var outside: PackedInt32Array = PixelCanvas.distances(shown, canvas_width, canvas_height, 1)[0]
	features.values.resize(count * COUNT)
	for p in count:
		var alpha := data[p * 4 + 3] / 255.0
		var i := p * COUNT
		features.values[i] = data[p * 4] / 255.0 * alpha
		features.values[i + 1] = data[p * 4 + 1] / 255.0 * alpha
		features.values[i + 2] = data[p * 4 + 2] / 255.0 * alpha
		features.values[i + 3] = alpha * SHOWN_WEIGHT
		var depth := (inside[p] - outside[p]) / 3.0 / depth_scale
		features.values[i + 4] = clampf(depth, -DEPTH_REACH, DEPTH_REACH) * DEPTH_WEIGHT
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
