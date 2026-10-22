class_name FlowLevel
extends RefCounted
## A key worked out [member zoom] times smaller, what [FlowMorph] matches: for each pixel
## its colour, how opaque it is and how far inside the outline it is

## Numbers for the pixels past the canvas: nothing shown, outside the outline
const EMPTY: Array[float] = [0.0, 0.0, 0.0, 0.0, FlowMorph.DEPTH_WEIGHT]

var zoom := 1
## The key's own width
var full_width := 0
var width := 0
var height := 0
## [constant FlowMorph.FEATURES] numbers a pixel: red, green and blue times opacity (0 to
## 1), opacity, and depth (see [constant FlowMorph.DEPTH_REACH])
var features := PackedFloat32Array()
## 1 for the pixels matched, see [constant FlowMorph.MATCHED_ALPHA]
var matched := PackedByteArray()


## [param data], RGBA bytes [param data_width] × [param data_height] pixels, [param times]
## times smaller: each pixel the average of the ones it stands for, weighed by how shown
func _init(data: PackedByteArray, data_width: int, data_height: int, times: int) -> void:
	zoom = times
	full_width = data_width
	width = ceili(float(data_width) / times)
	height = ceili(float(data_height) / times)
	var count := width * height
	var features_each := FlowMorph.FEATURES
	features.resize(count * features_each)
	matched.resize(count)
	var shown := PackedByteArray()
	shown.resize(count)
	var area := float(times * times)
	for sy in height:
		for sx in width:
			var sum := Vector4.ZERO
			for y in range(sy * times, mini((sy + 1) * times, data_height)):
				for x in range(sx * times, mini((sx + 1) * times, data_width)):
					var i := (y * data_width + x) * 4
					var alpha := data[i + 3] / 255.0
					sum += Vector4(data[i] * alpha, data[i + 1] * alpha, data[i + 2] * alpha, alpha)
			var p := sy * width + sx
			var opacity := sum.w / area
			var f := p * features_each
			features[f] = sum.x / 255.0 / area
			features[f + 1] = sum.y / 255.0 / area
			features[f + 2] = sum.z / 255.0 / area
			features[f + 3] = opacity
			shown[p] = 1 if opacity > 0.5 else 0
			matched[p] = 1 if opacity > FlowMorph.MATCHED_ALPHA else 0
	var sides := sides_of(shown, width, height)
	var reach := FlowMorph.DEPTH_REACH
	for p in count:
		features[p * features_each + 4] = (
			clampf(sides[p], -reach, reach) / reach * FlowMorph.DEPTH_WEIGHT
		)


## How far outside (positive) or inside (negative) [param mask] each pixel of a canvas
## [param w] × [param h] pixels is, in pixels, the edge half a pixel either side; see
## [method PixelCanvas.distances] for [param far]
static func sides_of(mask: PackedByteArray, w: int, h: int, far := 0) -> PackedFloat32Array:
	var outside: PackedInt32Array = PixelCanvas.distances(mask, w, h, 1, far)[0]
	var inside: PackedInt32Array = PixelCanvas.distances(mask, w, h, 0, far)[0]
	return sides_from(mask, outside, inside)


## [method sides_of] from how far each pixel is from [param mask]'s pixels,
## [param outside], and from the others, [param inside] (see [method PixelCanvas.distances])
static func sides_from(
	mask: PackedByteArray, outside: PackedInt32Array, inside: PackedInt32Array
) -> PackedFloat32Array:
	var sides := PackedFloat32Array()
	sides.resize(mask.size())
	for p in mask.size():
		if mask[p] == 1:
			sides[p] = 0.5 - inside[p] / 3.0
		else:
			sides[p] = outside[p] / 3.0 - 0.5
	return sides
