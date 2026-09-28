class_name SpriteBoxes
## Editing the boxes around the sprites of a sheet by hand, after [SpriteDetector] found
## them: merging, moving, resizing, drawing and removing boxes. Boxes are rectangles of
## whole pixels that stay inside the image. Every function returns new boxes and leaves
## the ones given alone.

## Edges of a box, to say which ones a drag moves; a corner is two of them
const LEFT := 1
const TOP := 2
const RIGHT := 4
const BOTTOM := 8


## The boxes in rows, the way their frames are laid out, see [method SpriteDetector.group_in_rows]
static func to_rows(boxes: Array[Rect2i]) -> Array[Array]:
	return SpriteDetector.group_in_rows(boxes)


## Where the frame of each of [param boxes] goes in the sheet cut with [method to_rows],
## by the box's index
static func get_coords(boxes: Array[Rect2i]) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	coords.resize(boxes.size())
	var rows := SpriteDetector.order_in_rows(boxes)
	for row in rows.size():
		for column: int in rows[row].size():
			coords[rows[row][column]] = Vector2i(column, row)
	return coords


## The number of each of [param boxes], by index: they're numbered in reading order, row
## by row, from [param first]
static func get_numbers(boxes: Array[Rect2i], first := 0) -> PackedInt32Array:
	var numbers := PackedInt32Array()
	numbers.resize(boxes.size())
	var number := first
	for row in SpriteDetector.order_in_rows(boxes):
		for index: int in row:
			numbers[index] = number
			number += 1
	return numbers


## The boxes found in [param rows] from [method SpriteDetector.detect], in reading order
static func from_rows(rows: Array[Array]) -> Array[Rect2i]:
	var boxes: Array[Rect2i] = []
	for row in rows:
		boxes.append_array(row)
	return boxes


## [param boxes] with the ones at [param indices] replaced by one box around them all, at
## the end. Fewer than two boxes don't merge.
static func merge(boxes: Array[Rect2i], indices: Array[int]) -> Array[Rect2i]:
	if indices.size() < 2:
		return boxes.duplicate()
	var merged := boxes[indices[0]]
	for index in indices:
		merged = merged.merge(boxes[index])
	var result := remove(boxes, indices)
	result.append(merged)
	return result


## [param boxes] without the ones at [param indices]
static func remove(boxes: Array[Rect2i], indices: Array[int]) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for index in boxes.size():
		if index not in indices:
			result.append(boxes[index])
	return result


## [param boxes] with the ones at [param indices] moved together by [param offset], as far
## as they go without leaving [param bounds]
static func move(
	boxes: Array[Rect2i], indices: Array[int], offset: Vector2i, bounds: Rect2i
) -> Array[Rect2i]:
	var result := boxes.duplicate()
	if indices.is_empty():
		return result
	var around := boxes[indices[0]]
	for index in indices:
		around = around.merge(boxes[index])
	# The most they can go each way
	offset = offset.clamp(bounds.position - around.position, bounds.end - around.end)
	for index in indices:
		result[index] = Rect2i(boxes[index].position + offset, boxes[index].size)
	return result


## [param rect] with its [param edges] (see [constant LEFT]…) moved to the lines between
## pixels at [param to]: x for the left and right edges, y for the top and bottom. Edges
## stay in [param bounds] and a pixel away from the opposite edge.
static func resize(rect: Rect2i, edges: int, to: Vector2i, bounds: Rect2i) -> Rect2i:
	var start := rect.position
	var end := rect.end
	if edges & LEFT:
		start.x = clampi(to.x, bounds.position.x, end.x - 1)
	if edges & RIGHT:
		end.x = clampi(to.x, start.x + 1, bounds.end.x)
	if edges & TOP:
		start.y = clampi(to.y, bounds.position.y, end.y - 1)
	if edges & BOTTOM:
		end.y = clampi(to.y, start.y + 1, bounds.end.y)
	return Rect2i(start, end - start)


## A new box from pixel [param from] to pixel [param to], both in it, cut to [param bounds]
static func from_corners(from: Vector2i, to: Vector2i, bounds: Rect2i) -> Rect2i:
	var start := from.min(to).clamp(bounds.position, bounds.end - Vector2i.ONE)
	var end := from.max(to).clamp(bounds.position, bounds.end - Vector2i.ONE) + Vector2i.ONE
	return Rect2i(start, end - start)


## The indices of the boxes [param rect] touches
static func touching(boxes: Array[Rect2i], rect: Rect2) -> Array[int]:
	var result: Array[int] = []
	for index in boxes.size():
		if Rect2(boxes[index]).intersects(rect, true):
			result.append(index)
	return result


## The index of the box at [param point], the smallest when boxes overlap so a box inside
## another can be picked, or -1
static func find_at(boxes: Array[Rect2i], point: Vector2) -> int:
	var found := -1
	for index in boxes.size():
		if Rect2(boxes[index]).has_point(point):
			if found < 0 or boxes[index].get_area() < boxes[found].get_area():
				found = index
	return found


## The edges of [param rect] (see [constant LEFT]…) within [param reach] of [param point],
## both in pixels of the image, or 0. Near a corner, both of its edges.
static func edges_at(rect: Rect2i, point: Vector2, reach: float) -> int:
	var area := Rect2(rect)
	if not area.grow(reach).has_point(point):
		return 0
	# A box smaller than the reach is still moved from its middle
	reach = minf(reach, minf(area.size.x, area.size.y) / 3.0)
	var edges := 0
	if absf(point.x - area.position.x) <= reach:
		edges |= LEFT
	elif absf(point.x - area.end.x) <= reach:
		edges |= RIGHT
	if absf(point.y - area.position.y) <= reach:
		edges |= TOP
	elif absf(point.y - area.end.y) <= reach:
		edges |= BOTTOM
	return edges
