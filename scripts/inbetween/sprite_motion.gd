class_name SpriteMotion
extends RefCounted
## How far a whole sprite moves from one key to the other, see [method detect]: what
## [PieceMorph] looks for the parts' movements on top of.

## Pixels compared at most for each movement tried: bigger frames are sampled
const SAMPLE_PIXELS := 4096
## Movements tried at most, one pixel at a time
const MAX_STEPS := 256


## How far the sprite moves from key [param a] to key [param b], in whole pixels: the
## movement that lines their pixels up best. It starts from how far their middles and
## their weight moved and looks around them a pixel at a time.
static func detect(a: Dictionary, b: Dictionary) -> Vector2i:
	var a_used := (a.image as Image).get_used_rect()
	var b_used := (b.image as Image).get_used_rect()
	if not a_used.has_area() or not b_used.has_area():
		return Vector2i.ZERO
	var a_placed := Placed.new(a.image, a.origin)
	var b_placed := Placed.new(b.image, b.origin)
	a_used.position += a_placed.rect.position
	b_used.position += b_placed.rect.position
	var biggest := maxi(a_used.get_area(), b_used.get_area())
	var stride := maxi(1, ceili(sqrt(float(biggest) / SAMPLE_PIXELS)))
	var scores := {}
	var score := func(motion: Vector2i) -> float:
		if not scores.has(motion):
			var area := a_used.merge(Rect2i(b_used.position - motion, b_used.size))
			scores[motion] = _mismatch(a_placed, b_placed, area, motion, stride)
		return scores[motion]
	var guesses: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i((b_placed.centroid(b_used, stride) - a_placed.centroid(a_used, stride)).round()),
		b_used.get_center() - a_used.get_center(),
		b_used.end - a_used.end,
		b_used.position - a_used.position,
	]
	var best := guesses[0]
	for guess in guesses:
		if score.call(guess) < score.call(best):
			best = guess
	for _step in MAX_STEPS:
		var moved := best
		for y in range(-1, 2):
			for x in range(-1, 2):
				var next := best + Vector2i(x, y)
				if score.call(next) < score.call(moved):
					moved = next
		if moved == best:
			break
		best = moved
	return best


## How different [param a] is from [param b] moved back by [param motion], over the pixels
## of [param area] either shows: 0 when the same, 1 when nothing lines up. One pixel in
## [param stride] each way is compared.
static func _mismatch(a: Placed, b: Placed, area: Rect2i, motion: Vector2i, stride: int) -> float:
	var differ := 0.0
	var shown := 0
	# The same pixels are sampled whatever the motion
	var start := area.position
	start -= Vector2i(posmod(start.x, stride), posmod(start.y, stride))
	for y in range(start.y, area.end.y, stride):
		for x in range(start.x, area.end.x, stride):
			var i := a.index(x, y)
			var j := b.index(x + motion.x, y + motion.y)
			var a_alpha: int = a.data[i + 3] if i >= 0 else 0
			var b_alpha: int = b.data[j + 3] if j >= 0 else 0
			if a_alpha == 0 and b_alpha == 0:
				continue
			shown += 1
			if a_alpha == 0 or b_alpha == 0:
				differ += 1.0
				continue
			var apart := absi(a_alpha - b_alpha)
			for c in 3:
				apart += absi(a.data[i + c] - b.data[j + c])
			differ += apart / 1020.0
	return differ / shown if shown else 1.0


## An image's pixels placed somewhere, read by where they're placed
class Placed:
	var data: PackedByteArray
	## Where the whole image is placed
	var rect: Rect2i

	func _init(img: Image, position: Vector2i) -> void:
		var source := PixelCanvas.rgba(img)
		data = source.get_data()
		rect = Rect2i(position, source.get_size())

	## Where the pixel placed at ([param x], [param y]) starts in [member data], or -1
	## when the image doesn't cover it
	func index(x: int, y: int) -> int:
		var local_x := x - rect.position.x
		var local_y := y - rect.position.y
		if local_x < 0 or local_y < 0 or local_x >= rect.size.x or local_y >= rect.size.y:
			return -1
		return (local_y * rect.size.x + local_x) * 4

	## Where the pixels of [param area] weigh the same on each side, weighed by alpha,
	## sampling one pixel in [param stride] each way
	func centroid(area: Rect2i, stride: int) -> Vector2:
		var total := Vector2.ZERO
		var weight := 0.0
		for y in range(area.position.y, area.end.y, stride):
			for x in range(area.position.x, area.end.x, stride):
				var i := index(x, y)
				if i >= 0 and data[i + 3] > 0:
					total += Vector2(x + 0.5, y + 0.5) * data[i + 3]
					weight += data[i + 3]
		return total / weight if weight > 0 else Vector2(area.get_center())
