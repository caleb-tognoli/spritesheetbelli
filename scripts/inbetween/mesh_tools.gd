class_name MeshTools
extends RefCounted
## Helpers for [KeyMesh]: reading keys' pixels, and small containers


## The middles of the pixels of [param data] (a canvas [param canvas_width] wide) at least
## [param least_alpha] opaque
static func shown_points(
	data: PackedByteArray, canvas_width: int, least_alpha: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in data.size() / 4:
		if data[p * 4 + 3] >= least_alpha:
			points.append(Vector2(p % canvas_width + 0.5, p / canvas_width + 0.5))
	return points


## [param data]'s pixels premultiplied, 0 to 1, four numbers each
static func premultiplied(data: PackedByteArray) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(data.size())
	for p in data.size() / 4:
		var alpha := data[p * 4 + 3] / 255.0
		for c in 3:
			result[p * 4 + c] = data[p * 4 + c] / 255.0 * alpha
		result[p * 4 + 3] = alpha
	return result


## 1 for each pixel of [param colors] (premultiplied, a canvas [param width] ×
## [param height] pixels) shown, at least half opaque, on an edge: next to one not shown,
## or differing from a neighbour by more than [param least_step] (red, green, blue and
## alpha summed, 0 to 4)
static func edges(
	colors: PackedFloat32Array, width: int, height: int, least_step: float
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(width * height)
	for y in height:
		for x in width:
			var p := y * width + x
			if colors[p * 4 + 3] < 0.5:
				continue
			for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := PixelCanvas.index_at(x + side.x, y + side.y, width, height)
				if q < 0 or colors[q * 4 + 3] < 0.5:
					result[p] = 1
					break
				var step := 0.0
				for c in 4:
					step += absf(colors[q * 4 + c] - colors[p * 4 + c])
				if step > least_step:
					result[p] = 1
					break
	return result


## [param mask] closed: grown by a pixel to the sides, then shrunk back
static func closed(mask: PackedByteArray, mask_width: int, mask_height: int) -> PackedByteArray:
	var grown := mask.duplicate()
	for y in mask_height:
		for x in mask_width:
			var p := y * mask_width + x
			if mask[p] == 1:
				continue
			if (
				(x > 0 and mask[p - 1] == 1)
				or (x < mask_width - 1 and mask[p + 1] == 1)
				or (y > 0 and mask[p - mask_width] == 1)
				or (y < mask_height - 1 and mask[p + mask_width] == 1)
			):
				grown[p] = 1
	var result := grown.duplicate()
	for y in mask_height:
		for x in mask_width:
			var p := y * mask_width + x
			if grown[p] == 0:
				continue
			if (
				x == 0
				or x == mask_width - 1
				or y == 0
				or y == mask_height - 1
				or grown[p - 1] == 0
				or grown[p + 1] == 0
				or grown[p - mask_width] == 0
				or grown[p + mask_width] == 0
			):
				result[p] = 0
	for p in mask.size():
		if mask[p] == 1:
			result[p] = 1
	return result


## The pixel of [param full_data] (a canvas [param big_width] x [param big_height]) at
## [param at], or -1 where it's see-through
static func nearest_covering(
	at: Vector2, full_data: PackedByteArray, big_width: int, big_height: int
) -> int:
	var x := clampi(floori(at.x), 0, big_width - 1)
	var q := clampi(floori(at.y), 0, big_height - 1) * big_width + x
	return q if full_data[q * 4 + 3] > 0 else -1


## The pixel of [param full_data] (a canvas [param big_width] x [param big_height]) point
## [param at] shows with the outline smooth: where the pixels round it, weighted by how
## near, are at least half shown, the nearest of them shown; -1 elsewhere
static func smooth_covering(
	at: Vector2, full_data: PackedByteArray, big_width: int, big_height: int
) -> int:
	var x := at.x - 0.5
	var y := at.y - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var covered := 0.0
	var best := -1
	var best_weight := 0.0
	for dy in 2:
		for dx in 2:
			var q := PixelCanvas.index_at(x0 + dx, y0 + dy, big_width, big_height)
			if q < 0 or full_data[q * 4 + 3] == 0:
				continue
			var weight := (fx if dx == 1 else 1.0 - fx) * (fy if dy == 1 else 1.0 - fy)
			covered += weight
			if weight > best_weight or best < 0:
				best_weight = weight
				best = q
	return best if covered >= 0.5 else -1


## How much [param map] stretches things most, in any direction (its biggest singular
## value)
static func largest_stretch(map: Transform2D) -> float:
	var a := map.x.x
	var b := map.y.x
	var c := map.x.y
	var d := map.y.y
	var sum := a * a + b * b + c * c + d * d
	var det := a * d - b * c
	return sqrt(maxf((sum + sqrt(maxf(sum * sum - 4.0 * det * det, 0.0))) / 2.0, 0.0))


## The triangles of [param mesh] over the sprite drawn with their corners at
## [param positions] (on the canvas [param scale] times bigger), each pixel the nearest of
## [param full_data] where it rests; triangles flipped over by then left out. Triangles
## turned or grown much (see [constant KeyMesh.MAGNIFIED]) are drawn with their outline
## smooth (where the key's pixels round the point it rests at, weighted by how near, are
## at least half shown) rather than their pixels' stairs, and marked 1 in [param grown].
static func drawn_over(
	mesh: KeyMesh,
	positions: PackedVector2Array,
	full_data: PackedByteArray,
	scale: int,
	grown: PackedByteArray
) -> PackedByteArray:
	var big_width := mesh.width * scale
	var big_height := mesh.height * scale
	var out := PixelCanvas.blank(big_width * big_height)
	grown.resize(big_width * big_height)
	grown.fill(0)
	for k in range(0, mesh.triangles.size(), 3):
		if mesh.weights[k / 3] < 1.0:
			continue
		var c0 := positions[mesh.triangles[k]]
		var c1 := positions[mesh.triangles[k + 1]]
		var c2 := positions[mesh.triangles[k + 2]]
		var s0 := mesh.rest[mesh.triangles[k]] * scale
		var s1 := mesh.rest[mesh.triangles[k + 1]] * scale
		var s2 := mesh.rest[mesh.triangles[k + 2]] * scale
		var e1 := c1 - c0
		var e2 := c2 - c0
		var area := e1.cross(e2)
		if area <= 1e-6:
			continue
		var from := Transform2D(s1 - s0, s2 - s0, Vector2.ZERO)
		var magnified := false
		if absf(from.determinant()) > 1e-6:
			var growth := Transform2D(e1, e2, Vector2.ZERO) * from.affine_inverse()
			var turn := atan2(growth.x.y - growth.y.x, growth.x.x + growth.y.y)
			magnified = (
				largest_stretch(growth) >= KeyMesh.MAGNIFIED or absf(turn) >= KeyMesh.TURNED
			)
		var x0 := maxi(floori(minf(c0.x, minf(c1.x, c2.x))), 0)
		var y0 := maxi(floori(minf(c0.y, minf(c1.y, c2.y))), 0)
		var x1 := mini(ceili(maxf(c0.x, maxf(c1.x, c2.x))) + 1, big_width)
		var y1 := mini(ceili(maxf(c0.y, maxf(c1.y, c2.y))) + 1, big_height)
		for py in range(y0, y1):
			for px in range(x0, x1):
				var d := Vector2(px + 0.5, py + 0.5) - c0
				var u := d.cross(e2) / area
				var v := e1.cross(d) / area
				if u < -0.02 or v < -0.02 or u + v > 1.02:
					continue
				var source := s0 + (s1 - s0) * u + (s2 - s0) * v
				var q := (
					smooth_covering(source, full_data, big_width, big_height)
					if magnified
					else nearest_covering(source, full_data, big_width, big_height)
				)
				var p := py * big_width + px
				if magnified:
					grown[p] = 1
				if q < 0:
					continue
				for c in 4:
					out[p * 4 + c] = full_data[q * 4 + c]
	return out


## Both keys' pixels premultiplied, 0 to 1, four numbers each, and 1 for each pixel on
## an edge, see [method edges]
class Colors:
	var own := PackedFloat32Array()
	var other := PackedFloat32Array()
	var own_edges := PackedByteArray()
	var other_edges := PackedByteArray()


## Points of a key placed in its triangles: for each, the canvas pixel it's the middle
## of, the triangle it's in and how far along each corner
class Located:
	var points := PackedVector2Array()
	var pixels := PackedInt32Array()
	var triangles := PackedInt32Array()
	var weights := PackedVector3Array()

	## Where each point is once the corners are at [param positions], with
	## [param corners] (three per triangle)
	func at(positions: PackedVector2Array, corners: PackedInt32Array) -> PackedVector2Array:
		var result := PackedVector2Array()
		result.resize(points.size())
		for s in points.size():
			var k := triangles[s] * 3
			var w := weights[s]
			result[s] = (
				positions[corners[k]] * w.x
				+ positions[corners[k + 1]] * w.y
				+ positions[corners[k + 2]] * w.z
			)
		return result


## A heap of triangles to visit, the one with the biggest weight first: x weight, y the
## triangle, z the one it's reached from
class Heap:
	var _items: Array[Vector3] = []

	func is_empty() -> bool:
		return _items.is_empty()

	func push(weight: float, triangle: int, from: int) -> void:
		_items.append(Vector3(weight, triangle, from))
		var i := _items.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _items[parent].x >= _items[i].x:
				break
			var swap := _items[parent]
			_items[parent] = _items[i]
			_items[i] = swap
			i = parent

	func pop() -> Vector3:
		var top := _items[0]
		var last: Vector3 = _items.pop_back()
		if not _items.is_empty():
			_items[0] = last
			var i := 0
			var n := _items.size()
			while true:
				var left := i * 2 + 1
				var right := left + 1
				var biggest := i
				if left < n and _items[left].x > _items[biggest].x:
					biggest = left
				if right < n and _items[right].x > _items[biggest].x:
					biggest = right
				if biggest == i:
					break
				var swap := _items[biggest]
				_items[biggest] = _items[i]
				_items[i] = swap
				i = biggest
		return top


## Points kept in square cells, for asking whether any is near a spot
class Spots:
	var _cell := 1.0
	var _cells := {}
	var _count := 0

	func _init(cell: float) -> void:
		_cell = cell

	func count() -> int:
		return _count

	func add(point: Vector2) -> void:
		var key := Vector2i(floori(point.x / _cell), floori(point.y / _cell))
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(point)
		_count += 1

	## Whether any point is closer than [param reach] to [param at]
	func any_within(at: Vector2, reach: float) -> bool:
		var cells := ceili(reach / _cell)
		var home := Vector2i(floori(at.x / _cell), floori(at.y / _cell))
		for y in range(home.y - cells, home.y + cells + 1):
			for x in range(home.x - cells, home.x + cells + 1):
				for point: Vector2 in _cells.get(Vector2i(x, y), []):
					if point.distance_squared_to(at) < reach * reach:
						return true
		return false
