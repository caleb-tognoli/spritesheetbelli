class_name SmoothKey
extends RefCounted
## A key blown up [constant ZOOM] times by Scale2x, as RotSprite does before turning pixel
## art: the corners of stair steps are filled in, so lines turned come out straight rather
## than jagged. Pieces of the key are drawn turned by reading it, see [PieceMorph].

const ZOOM := 8

var width := 0
var height := 0
## For each pixel of the blown up key, which of [member colors] it has
var codes := PackedInt32Array()
## The colours (see [method PixelCanvas.colors]) and the pieces they're of, by code; code 0
## is transparent, of no piece
var colors := PackedInt32Array()
var pieces := PackedInt32Array()


## [param data], a canvas [param canvas_width] pixels wide, whose pixels are of the pieces
## [param labels] says, blown up
static func of(data: PackedByteArray, canvas_width: int, labels: PackedInt32Array) -> SmoothKey:
	var smooth := SmoothKey.new()
	var canvas_height := labels.size() / canvas_width
	var key_colors := PixelCanvas.colors(data)
	var code_of := {Vector2i(0, -1): 0}
	smooth.colors.append(0)
	smooth.pieces.append(-1)
	var grid := PackedInt32Array()
	grid.resize(labels.size())
	for p in labels.size():
		if labels[p] < 0:
			continue
		var key := Vector2i(key_colors[p], labels[p])
		if not code_of.has(key):
			code_of[key] = smooth.colors.size()
			smooth.colors.append(key_colors[p])
			smooth.pieces.append(labels[p])
		grid[p] = code_of[key]
	var w := canvas_width
	var h := canvas_height
	var zoom := 1
	while zoom < ZOOM:
		grid = _scale2x(grid, w, h)
		w *= 2
		h *= 2
		zoom *= 2
	smooth.width = w
	smooth.height = h
	smooth.codes = grid
	return smooth


## The code of the blown up pixel at point [param at] of the key (in the key's pixels)
func code_at(at: Vector2) -> int:
	var x := floori(at.x * ZOOM)
	var y := floori(at.y * ZOOM)
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return codes[y * width + x]


static func _scale2x(grid: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(w * h * 4)
	var w2 := w * 2
	for y in h:
		for x in w:
			var e := grid[y * w + x]
			var up := grid[maxi(y - 1, 0) * w + x]
			var down := grid[mini(y + 1, h - 1) * w + x]
			var left := grid[y * w + maxi(x - 1, 0)]
			var right := grid[y * w + mini(x + 1, w - 1)]
			var top := y * 2 * w2 + x * 2
			out[top] = up if left == up and left != down and up != right else e
			out[top + 1] = right if up == right and up != left and right != down else e
			out[top + w2] = left if down == left and down != right and left != up else e
			out[top + w2 + 1] = down if right == down and right != up and down != left else e
	return out
