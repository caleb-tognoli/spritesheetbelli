class_name SmoothOutline
extends RefCounted
## A shape's outline smoothed, for drawing it grown: from how far inside or outside the
## shape each pixel round it is, blurred, so that stretched, the stairs of its pixels
## become straight lines and curves rather than bigger stairs. Where the shape is a pixel
## or two thin, which blurring would lose, the outline is kept as it is. See
## [PieceMorph].

## How far round the shape it's worked out, and how much it's blurred, in pixels (times
## how much bigger the shape is drawn than it was worked out)
const REACH := 4
const BLUR := 1.0
## Pixels with none round them deeper inside than this are in a thin part
const THIN := 1.0

## Where the grid starts on the canvas, and how big it is
var left := 0
var top := 0
var width := 0
var height := 0
## How far inside (positive) or outside each pixel's middle is, in pixels: blurred, and
## as it is
var smoothed := PackedFloat32Array()
var raw := PackedFloat32Array()
## 1 for the pixels in a thin part
var thin := PackedByteArray()


## The outline of [param mask] (1 for the shape's pixels), a canvas [param canvas_width] ×
## [param canvas_height] pixels, drawn [param scale] times bigger than worked out
static func of(
	mask: PackedByteArray, canvas_width: int, canvas_height: int, scale := 1
) -> SmoothOutline:
	var outline := SmoothOutline.new()
	var low := Vector2i(canvas_width, canvas_height)
	var high := Vector2i(-1, -1)
	for p in mask.size():
		if mask[p] == 1:
			low = low.min(Vector2i(p % canvas_width, p / canvas_width))
			high = high.max(Vector2i(p % canvas_width, p / canvas_width))
	if high.x < 0:
		return outline
	var reach := REACH * scale
	outline.left = maxi(low.x - reach, 0)
	outline.top = maxi(low.y - reach, 0)
	outline.width = mini(high.x + reach + 1, canvas_width) - outline.left
	outline.height = mini(high.y + reach + 1, canvas_height) - outline.top
	var size := outline.width * outline.height
	var local := PackedByteArray()
	local.resize(size)
	for y in outline.height:
		for x in outline.width:
			var p := (outline.top + y) * canvas_width + outline.left + x
			local[y * outline.width + x] = mask[p]
	var to_inside: PackedInt32Array = (
		PixelCanvas.distances(local, outline.width, outline.height, 1)[0]
	)
	var to_outside: PackedInt32Array = (
		PixelCanvas.distances(local, outline.width, outline.height, 0)[0]
	)
	# In pixels, from thirds (see PixelCanvas.distances), the edge half a pixel from the
	# middles of the pixels either side
	outline.raw.resize(size)
	for i in size:
		if local[i] == 1:
			outline.raw[i] = to_outside[i] / 3.0 - 0.5
		else:
			outline.raw[i] = 0.5 - to_inside[i] / 3.0
	outline.thin.resize(size)
	for y in outline.height:
		for x in outline.width:
			var i := y * outline.width + x
			if local[i] == 0:
				continue
			var deepest := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < outline.width and ny < outline.height:
						deepest = maxf(deepest, outline.raw[ny * outline.width + nx])
			outline.thin[i] = 1 if deepest <= THIN * scale else 0
	outline.smoothed = _blurred(outline.raw, outline.width, outline.height, BLUR * scale)
	return outline


## Whether point [param at] of the canvas is inside the smoothed outline, or inside a thin
## part as it is
func covers(at: Vector2) -> bool:
	var x := at.x - 0.5 - left
	var y := at.y - 0.5 - top
	var x0 := floori(x)
	var y0 := floori(y)
	if x0 < 0 or y0 < 0 or x0 >= width - 1 or y0 >= height - 1:
		return false
	var fx := x - x0
	var fy := y - y0
	var i := y0 * width + x0
	var corners := PackedInt32Array([i, i + 1, i + width, i + width + 1])
	var weights := PackedFloat32Array(
		[(1.0 - fx) * (1.0 - fy), fx * (1.0 - fy), (1.0 - fx) * fy, fx * fy]
	)
	var inside := 0.0
	var inside_raw := 0.0
	var any_thin := false
	for c in 4:
		inside += smoothed[corners[c]] * weights[c]
		inside_raw += raw[corners[c]] * weights[c]
		any_thin = any_thin or thin[corners[c]] == 1
	return inside >= 0.0 or (any_thin and inside_raw >= 0.0)


## [param values], a grid [param grid_width] × [param grid_height], blurred by
## [param blur] pixels
static func _blurred(
	values: PackedFloat32Array, grid_width: int, grid_height: int, blur: float
) -> PackedFloat32Array:
	var reach := ceili(blur * 2.5)
	var kernel := PackedFloat32Array()
	var total := 0.0
	for k in range(-reach, reach + 1):
		kernel.append(exp(-0.5 * k * k / (blur * blur)))
		total += kernel[k + reach]
	for k in kernel.size():
		kernel[k] /= total
	var across := PackedFloat32Array()
	across.resize(values.size())
	for y in grid_height:
		for x in grid_width:
			var sum := 0.0
			for k in range(-reach, reach + 1):
				var nx := clampi(x + k, 0, grid_width - 1)
				sum += values[y * grid_width + nx] * kernel[k + reach]
			across[y * grid_width + x] = sum
	var result := PackedFloat32Array()
	result.resize(values.size())
	for y in grid_height:
		for x in grid_width:
			var sum := 0.0
			for k in range(-reach, reach + 1):
				var ny := clampi(y + k, 0, grid_height - 1)
				sum += across[ny * grid_width + x] * kernel[k + reach]
			result[y * grid_width + x] = sum
	return result
