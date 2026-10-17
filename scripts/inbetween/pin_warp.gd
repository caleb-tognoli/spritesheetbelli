class_name PinWarp
extends RefCounted
## Pins steering in-betweens, like a puppet: a pin on the frame halfway between the keys
## takes the point under it somewhere else, pulling the part of the sprite round it along,
## turning and bending it as rigidly as it can; parts far from every pin stay where they'd
## be without pins. A pin left where it was holds its spot firmly. A pin's move counts fully
## halfway and fades to nothing at the keys (see [method weight]), so the motion passes
## through the pinned pose and still starts and ends on the keys. See
## [method PieceMorph.frame].
##
## Pins are worked into how each kind of in-between moves its pixels where they can be
## ([FlowMorph], [KeyMesh]); frames drawn as pieces are bent afterwards, see [method warped].
## Both bend through a [PinWarp.Bend].

## How far a pin's pull reaches, as a share of the sprite's size: this far from a pin it
## counts as much as the spots held round it, then fades fast
const REACH := 0.25
## The sprite holds itself still at spots this share of its size apart (at least
## [constant LEAST_SPACING] pixels), each holding weakly, so what's far from every pin stays
const HOLD_SPACING := 0.1
const LEAST_SPACING := 2.0
## How a bend is worked out: on points this share of the sprite's size apart (at most a
## pixel), smoothly in between
const STEP_SHARE := 0.02
## Nearer than this (squared) to a pin, a point goes with the pin alone
const ON_PIN := 1e-8


## How much a pin's move counts [param t] of the way from key A to key B: all of it
## halfway, none at the keys
static func weight(t: float) -> float:
	return clampf(4.0 * t * (1.0 - t), 0.0, 1.0)


## [param data], a canvas [param width] × [param height] pixels, bent so what's at
## [param froms] goes to [param tos] (see [PinWarp.Bend]), the sprite holding itself still
## where it shows: each pixel takes the one it came from, the nearest, so no new colours
## appear
static func warped(
	data: PackedByteArray,
	width: int,
	height: int,
	froms: PackedVector2Array,
	tos: PackedVector2Array
) -> PackedByteArray:
	var shown := PackedVector2Array()
	for p in width * height:
		if data[p * 4 + 3] > 0:
			shown.append(Vector2(p % width + 0.5, p / width + 0.5))
	# Bent the other way round, near enough to undo it
	var bend := Bend.new(tos, froms, shown)
	bend.lay(width, height)
	var out := PixelCanvas.blank(width * height)
	for y in height:
		for x in width:
			var source := bend.sampled(Vector2(x + 0.5, y + 0.5))
			var sx := floori(source.x)
			var sy := floori(source.y)
			if sx < 0 or sy < 0 or sx >= width or sy >= height:
				continue
			var p := (y * width + x) * 4
			var q := (sy * width + sx) * 4
			for c in 4:
				out[p + c] = data[q + c]
	return out


## A bend taking points at [code]froms[/code] to [code]tos[/code], the shape at
## [code]shape[/code] (its points as drawn) holding itself still: each point turns and
## moves as rigidly as it can with the pins and the held spots, nearer ones counting more
## (moving least squares, Schaefer, McPhail and Warren, 2006). Pins count much more than
## held spots near them and fade fast past [constant REACH], so a pin pulls the part round
## it and what's far stays. Made for one frame; can be used on several threads.
class Bend:
	## The pins, and how much each counts against the held spots
	var froms := PackedVector2Array()
	var tos := PackedVector2Array()
	var strengths := PackedFloat32Array()
	## Spots the shape holds still, and how softly (squared), so no spot holds alone
	var holds := PackedVector2Array()
	var soft := 1.0
	## Moves worked out on a grid, see [method lay]
	var _moves := PackedVector2Array()
	var _step := 1.0
	var _columns := 0
	var _rows := 0

	func _init(from: PackedVector2Array, to: PackedVector2Array, shape: PackedVector2Array) -> void:
		froms = from
		tos = to
		var low := Vector2(INF, INF)
		var high := -low
		for point in shape:
			low = low.min(point)
			high = high.max(point)
		for point in from:
			low = low.min(point)
			high = high.max(point)
		var size := maxf(maxf(high.x - low.x, high.y - low.y), 1.0)
		var spacing := maxf(size * HOLD_SPACING, LEAST_SPACING)
		soft = spacing * spacing
		_step = clampf(size * STEP_SHARE, 0.25, 1.0)
		# One held spot for each square of the shape: the middle of its points there
		var cells := {}
		for point in shape:
			var cell := Vector2i((point / spacing).floor())
			var sum: Vector3 = cells.get(cell, Vector3.ZERO)
			cells[cell] = sum + Vector3(point.x, point.y, 1.0)
		for sum: Vector3 in cells.values():
			holds.append(Vector2(sum.x, sum.y) / sum.z)
		# A pin counts as much as the held spots round it this far away
		var reach := size * REACH
		for point in from:
			var held := 0.0
			for spot in holds:
				held += 1.0 / (spot.distance_squared_to(point) + soft)
			strengths.append(pow(reach, 4.0) * maxf(held, 1e-12))

	## Where [param point] goes
	func moved(point: Vector2) -> Vector2:
		var count := froms.size()
		var weights := PackedFloat32Array()
		weights.resize(count + holds.size())
		var total := 0.0
		var from_middle := Vector2.ZERO
		var to_middle := Vector2.ZERO
		for i in count:
			var apart := froms[i].distance_squared_to(point)
			if apart < ON_PIN:
				return point + tos[i] - froms[i]
			weights[i] = strengths[i] / (apart * apart)
			total += weights[i]
			from_middle += froms[i] * weights[i]
			to_middle += tos[i] * weights[i]
		for j in holds.size():
			var w := 1.0 / (holds[j].distance_squared_to(point) + soft)
			weights[count + j] = w
			total += w
			from_middle += holds[j] * w
			to_middle += holds[j] * w
		if total <= 0.0:
			return point
		from_middle /= total
		to_middle /= total
		# The turn taking the points round their middle best where they go
		var along := 0.0
		var across := 0.0
		for i in count:
			var p := froms[i] - from_middle
			var q := tos[i] - to_middle
			along += weights[i] * p.dot(q)
			across += weights[i] * p.cross(q)
		for j in holds.size():
			var p := holds[j] - from_middle
			var q := holds[j] - to_middle
			along += weights[count + j] * p.dot(q)
			across += weights[count + j] * p.cross(q)
		var turn := atan2(across, along) if absf(along) + absf(across) > 1e-12 else 0.0
		return (point - from_middle).rotated(turn) + to_middle

	## Works the bend out over a canvas [param width] × [param height], for
	## [method sampled]
	func lay(width: int, height: int) -> void:
		_columns = ceili(width / _step) + 2
		_rows = ceili(height / _step) + 2
		_moves.resize(_columns * _rows)
		for row in _rows:
			for column in _columns:
				var at := Vector2(column, row) * _step
				_moves[row * _columns + column] = moved(at) - at

	## Where [param point] goes, smoothly between the points [method lay] worked out
	func sampled(point: Vector2) -> Vector2:
		var grid := point / _step
		var x := clampf(grid.x, 0.0, _columns - 1.001)
		var y := clampf(grid.y, 0.0, _rows - 1.001)
		var column := floori(x)
		var row := floori(y)
		var fx := x - column
		var fy := y - row
		var i := row * _columns + column
		var top := _moves[i].lerp(_moves[i + 1], fx)
		var bottom := _moves[i + _columns].lerp(_moves[i + _columns + 1], fx)
		return point + top.lerp(bottom, fy)
