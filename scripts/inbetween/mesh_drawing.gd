class_name MeshDrawing
extends RefCounted
## A [KeyMesh]'s key drawn in frames, see [method KeyMesh.draw_from] and
## [method KeyMesh.drawn]

## Pixels moved by whole pixels take the move most of those up to this many pixels
## round have, of the moves within a pixel of theirs, theirs counting this much more
const ALIKE_REACH := 2
const OWN_MOVE := 0.3
## The move across of a spot with no pixel, see [method _alike_moves]: none is within a
## pixel of it
const NONE := 1 << 30
## Pixels worked out on each thread at least, see [method _alike_moves]
const PARALLEL_LEAST := 4096

## The key, [member _scale] times bigger than worked out, on a canvas [member _width] ×
## [member _height] pixels; its pixels placed in the triangles
var _data := PackedByteArray()
var _scale := 1
var _width := 0
var _height := 0
var _points: MeshTools.Located
## Pixels of the key shown off the triangles and the nearest pixel on them, in pairs
var _strays := PackedInt32Array()
## For each of those, which of [member _points] the one on them is, and how far off it is
var _stray_of := PackedInt32Array()
var _stray_apart := PackedVector2Array()
## The pixels drawn, [member _points]'s then the strays': where each is, and its depth
## (see [member KeyMesh.depth]) times 100
var _all_pixels := PackedInt32Array()
var _xs := PackedInt32Array()
var _ys := PackedInt32Array()
var _rank_keys := PackedFloat64Array()
## [member _points] on a grid round them, [constant ALIKE_REACH] pixels wider each way so
## their neighbours are never off it: how big it is, and where each is on it
var _grid_width := 0
var _grid_height := 0
var _cells := PackedInt32Array()


## [param mesh]'s frames drawn from [param full_data], the key drawn [param scale] times
## bigger than worked out, on a canvas [param full_width] pixels wide: the one worked out
## that much bigger, give or take a few pixels, as it's worked out a whole number of times
## smaller
func _init(mesh: KeyMesh, full_data: PackedByteArray, scale: int, full_width: int) -> void:
	_data = full_data
	_scale = scale
	_width = full_width
	_height = full_data.size() / 4 / full_width
	var points := MeshTools.shown_points(full_data, _width, 1)
	_points = mesh.locate(points, scale, Vector2i(_width, _height))
	_find_strays()
	_find_places(mesh)


## The key [param t] of the way to the other key, see [method KeyMesh.drawn]; given
## [param mesh] (the one it was made for) rather than keeping it, which would keep both
func drawn(
	mesh: KeyMesh, t: float, pin_from: PackedVector2Array, pin_to: PackedVector2Array
) -> PackedByteArray:
	if NativeKernels.kernels:
		return NativeKernels.drawn(self, mesh, t, pin_from, pin_to)
	var full_data := _data
	var scale := _scale
	var big_width := _width
	var big_height := _height
	var positions := mesh.pinned(mesh.at(t), t, pin_from, pin_to)
	for i in positions.size():
		positions[i] *= scale
	var landed := _points.at(positions, mesh.triangles)
	# Whole-pixel moves, then each the move most of its neighbours moving alike have
	var chosen := _alike_moves(landed)
	# Pixels off the triangles, like a faint glow, move with the nearest pixel on them
	for k in _stray_of.size():
		var s := _stray_of[k]
		chosen.append(chosen[s])
		landed.append(landed[s] + _stray_apart[k])
	var out := PixelCanvas.blank(big_width * big_height)
	var front := PackedFloat32Array()
	front.resize(big_width * big_height)
	front.fill(-INF)
	# Where pixels land, and the triangles drawn over are, see below
	var pixels := _all_pixels
	var xs := _xs
	var ys := _ys
	var ranks := _rank_keys
	var low_x := big_width
	var low_y := big_height
	var high_x := -1
	var high_y := -1
	for s in pixels.size():
		var move := chosen[s]
		var dest_x := xs[s] + int(move.x)
		var dest_y := ys[s] + int(move.y)
		if dest_x < 0 or dest_y < 0 or dest_x >= big_width or dest_y >= big_height:
			continue
		var key := ranks[s] - landed[s].distance_to(Vector2(dest_x + 0.5, dest_y + 0.5))
		var q := dest_y * big_width + dest_x
		if key < front[q]:
			continue
		front[q] = key
		out.encode_u32(q * 4, full_data.decode_u32(pixels[s] * 4))
		low_x = mini(low_x, dest_x)
		low_y = mini(low_y, dest_y)
		high_x = maxi(high_x, dest_x)
		high_y = maxi(high_y, dest_y)
	var low := Vector2i(low_x, low_y)
	var high := Vector2i(high_x, high_y)
	var triangles := mesh.triangles
	for k in range(0, triangles.size(), 3):
		if mesh.weights[k / 3] < 1.0:
			continue
		for e in 3:
			var corner := positions[triangles[k + e]]
			low = low.min(Vector2i(floori(corner.x), floori(corner.y)))
			high = high.max(Vector2i(ceili(corner.x), ceili(corner.y)))
	if high.x < 0:
		return out
	# Everything below is nothing outside that, so it's only worked out there, with room
	# for closing gaps
	var area := Rect2i(low, high - low + Vector2i.ONE).grow(2).intersection(
		Rect2i(0, 0, big_width, big_height)
	)
	# Gaps a pixel across filled from the triangles drawn over
	var covered := PackedByteArray()
	covered.resize(big_width * big_height)
	for y in range(area.position.y, area.end.y):
		for p in range(y * big_width + area.position.x, y * big_width + area.end.x):
			covered[p] = 1 if out[p * 4 + 3] > 0 else 0
	var grown := PackedByteArray()
	var canvas := Vector2i(big_width, big_height)
	var over := MeshTools.drawn_over(mesh, positions, full_data, scale, canvas, grown)
	var over_shown := PackedByteArray()
	over_shown.resize(covered.size())
	for y in range(area.position.y, area.end.y):
		for p in range(y * big_width + area.position.x, y * big_width + area.end.x):
			over_shown[p] = 1 if over[p * 4 + 3] > 0 else 0
	# Both closed (see MeshTools.closed) worked out only where it matters
	for y in range(area.position.y, area.end.y):
		for p in range(y * big_width + area.position.x, y * big_width + area.end.x):
			# Grown much, smooth from the triangles drawn over, but for pinholes in them
			var smooth := (
				grown[p] == 1
				and (
					over_shown[p] == 1
					or MeshTools.closed_at(over_shown, big_width, big_height, area, p) == 0
				)
			)
			if (
				smooth
				or (
					covered[p] == 0
					and over_shown[p] == 1
					and MeshTools.closed_at(covered, big_width, big_height, area, p) == 1
				)
			):
				out.encode_u32(p * 4, over.decode_u32(p * 4))
	return out


## Works out what frames need of where the pixels are, the same for each, see
## [member _all_pixels] and [member _cells]
func _find_places(mesh: KeyMesh) -> void:
	var pixels := _points.pixels
	var big_width := _width
	var index := {}
	for s in pixels.size():
		index[pixels[s]] = s
	for k in range(0, _strays.size(), 2):
		_stray_of.append(index[_strays[k + 1]])
		_stray_apart.append(
			Vector2(
				_strays[k] % big_width - _strays[k + 1] % big_width,
				_strays[k] / big_width - _strays[k + 1] / big_width
			)
		)
	_all_pixels = pixels.duplicate()
	for k in range(0, _strays.size(), 2):
		_all_pixels.append(_strays[k])
	var depth := mesh.depth
	var width := mesh.width
	for p in _all_pixels:
		var x := p % big_width
		var y := p / big_width
		_xs.append(x)
		_ys.append(y)
		var small := (y / _scale) * width + x / _scale
		_rank_keys.append((depth[small] if small < depth.size() else 0) * 100.0)
	# The grid, round the pixels on the triangles
	var low := Vector2i(big_width, _height)
	var high := Vector2i(-1, -1)
	for s in pixels.size():
		low = low.min(Vector2i(_xs[s], _ys[s]))
		high = high.max(Vector2i(_xs[s], _ys[s]))
	_grid_width = maxi(high.x - low.x + 1, 0) + ALIKE_REACH * 2
	_grid_height = maxi(high.y - low.y + 1, 0) + ALIKE_REACH * 2
	var corner := low - Vector2i.ONE * ALIKE_REACH
	_cells.resize(pixels.size())
	for s in pixels.size():
		_cells[s] = (_ys[s] - corner.y) * _grid_width + _xs[s] - corner.x


## Each of [member _points]'s whole-pixel move to where it [param landed], as the move most
## of those up to [constant ALIKE_REACH] pixels round have, of the moves within a pixel of
## its own, its own counting [constant OWN_MOVE] more, ties going to the first found
func _alike_moves(landed: PackedVector2Array) -> PackedVector2Array:
	var points := _points.points
	var count := points.size()
	var cells := _cells
	var gw := _grid_width
	var size := gw * _grid_height
	var moves := PackedVector2Array()
	moves.resize(count)
	var move_x := PackedInt32Array()
	move_x.resize(size)
	move_x.fill(NONE)
	var move_y := PackedInt32Array()
	move_y.resize(size)
	for s in count:
		var move := (landed[s] - points[s]).round()
		moves[s] = move
		var c := cells[s]
		move_x[c] = int(move.x)
		move_y[c] = int(move.y)
	var chosen := PackedVector2Array()
	var work := _alike_run.bind(moves, move_x, move_y)
	for part: PackedVector2Array in Parallel.split(count, PARALLEL_LEAST, work):
		chosen.append_array(part)
	return chosen


## [method _alike_moves] for [member _points] [param start] to [param end] (past the
## last), their whole-pixel moves [param moves], and those on the grid [param move_x] and
## [param move_y]
func _alike_run(
	start: int,
	end: int,
	moves: PackedVector2Array,
	move_x: PackedInt32Array,
	move_y: PackedInt32Array
) -> PackedVector2Array:
	var cells := _cells
	var gw := _grid_width
	var chosen := PackedVector2Array()
	chosen.resize(end - start)
	# Moves within a pixel of a pixel's own, 5 × 5 round it: how many neighbours have each,
	# kept from the pixel to the left when it moves the same, a column out and one in
	var counts := PackedInt32Array()
	counts.resize(9)
	var last := -2
	var last_x := 0
	var last_y := 0
	# For the order moves are first found in, which settles ties
	var tally := PackedFloat64Array()
	tally.resize(9)
	var found := PackedInt32Array()
	found.resize(9)
	for s in range(start, end):
		var c := cells[s]
		var own_x := move_x[c]
		var own_y := move_y[c]
		if c == last + 1 and own_x == last_x and own_y == last_y:
			for dy in range(-ALIKE_REACH, ALIKE_REACH + 1):
				var q := c + dy * gw - ALIKE_REACH - 1
				var off_x := move_x[q] - own_x
				var off_y := move_y[q] - own_y
				if off_x >= -1 and off_x <= 1 and off_y >= -1 and off_y <= 1:
					counts[(off_y + 1) * 3 + off_x + 1] -= 1
				q += ALIKE_REACH * 2 + 1
				off_x = move_x[q] - own_x
				off_y = move_y[q] - own_y
				if off_x >= -1 and off_x <= 1 and off_y >= -1 and off_y <= 1:
					counts[(off_y + 1) * 3 + off_x + 1] += 1
		else:
			counts.fill(0)
			for dy in range(-ALIKE_REACH, ALIKE_REACH + 1):
				var row := c + dy * gw
				for q in range(row - ALIKE_REACH, row + ALIKE_REACH + 1):
					var off_x := move_x[q] - own_x
					var off_y := move_y[q] - own_y
					if off_x >= -1 and off_x <= 1 and off_y >= -1 and off_y <= 1:
						counts[(off_y + 1) * 3 + off_x + 1] += 1
		last = c
		last_x = own_x
		last_y = own_y
		# The most, its own counting more; when others tie for it, the first found
		var best := 4
		var top := counts[4] + OWN_MOVE
		var tied := false
		for kind in 9:
			if kind == 4 or counts[kind] < top:
				continue
			if counts[kind] > top:
				top = counts[kind]
				best = kind
				tied = false
			else:
				tied = true
		if tied:
			best = _first_most(c, own_x, own_y, move_x, move_y, tally, found)
		chosen[s - start] = moves[s] + Vector2(best % 3 - 1, best / 3 - 1)
	return chosen


## The move most of those round grid cell [param c] have, see [method _alike_moves], as a
## kind (0 to 8, 3 × 3 round its own move, [param own_x] and [param own_y]): of those as
## many, the first found going row by row. [param tally] and [param found] are room to work
## in, 9 long, [param tally] all 0 and left so.
func _first_most(
	c: int,
	own_x: int,
	own_y: int,
	move_x: PackedInt32Array,
	move_y: PackedInt32Array,
	tally: PackedFloat64Array,
	found: PackedInt32Array
) -> int:
	var kinds := 0
	for dy in range(-ALIKE_REACH, ALIKE_REACH + 1):
		var row := c + dy * _grid_width
		for q in range(row - ALIKE_REACH, row + ALIKE_REACH + 1):
			var off_x := move_x[q] - own_x
			var off_y := move_y[q] - own_y
			if off_x < -1 or off_x > 1 or off_y < -1 or off_y > 1:
				continue
			var kind := (off_y + 1) * 3 + off_x + 1
			if tally[kind] == 0.0:
				found[kinds] = kind
				kinds += 1
			tally[kind] += 1.0
	if tally[4] == 0.0:
		found[kinds] = 4
		kinds += 1
	tally[4] += OWN_MOVE
	var best := 4
	var top := -1.0
	for k in kinds:
		var kind := found[k]
		if tally[kind] > top:
			top = tally[kind]
			best = kind
		tally[kind] = 0.0
	return best


## The pixels of the key shown but off the triangles, each with the nearest pixel on
## them, see [member _strays]
func _find_strays() -> void:
	_strays = PackedInt32Array()
	var big_width := _width
	# Worked out round the pixels shown only, which holds every pixel on the triangles, so
	# the nearest are as on the whole canvas (see PixelCanvas.distances)
	var used := MeshTools.used_rect(_data, big_width)
	if not used.has_area():
		return
	var w := used.size.x
	var on := PackedByteArray()
	on.resize(w * used.size.y)
	for p in _points.pixels:
		on[(p / big_width - used.position.y) * w + p % big_width - used.position.x] = 1
	var nearest: PackedInt32Array = PixelCanvas.distances(on, w, used.size.y, 1)[1]
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var p := y * big_width + x
			var i := (y - used.position.y) * w + x - used.position.x
			if on[i] == 0 and _data[p * 4 + 3] > 0 and nearest[i] >= 0:
				var n := nearest[i]
				_strays.append_array(
					[p, (n / w + used.position.y) * big_width + n % w + used.position.x]
				)
