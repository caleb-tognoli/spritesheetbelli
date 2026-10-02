class_name AnimationLabelLayout
extends RefCounted
## Where the names of animations go on the grid, see [AnimationLabels], worked out from
## their cells alone so it can be tested without drawing.
##
## Frames shown more than once count once, where they're first shown: a ping-pong written
## out as 0-5, 4-1 or a frame held with 3, 3 is still the row 0-5. The order they're
## shown in doesn't matter otherwise: 2, 4, 3 is the area 2-4. An animation gets a label
## when those cells are:
## [br]- every frame of one row and nothing else, named in the margin nearer its first
## frame; the same for a column, named above or below it. Empty cells don't count, so a
## row with frames missing is still whole;
## [br]- a rectangle of at least two rows and two columns, outlined;
## [br]- any connected area, where cells touch side to side or the end of a row leads on
## to the start of the next, such as part of a row, frames wrapping onto the next row or
## an L-shape, outlined.
## [br]Outlines take in the animation's empty cells too, and empty cells between two of
## its frames in a row or column, so a rectangle with a frame missing is still one.
## Other animations are scattered, and get none.

enum Shape {
	NONE,  ## Scattered: no label
	ROW,  ## A whole row, named in the margin where it starts
	COLUMN,  ## A whole column, named above or below it
	BLOCK,  ## A rectangle, outlined and named at its first frame
	AREA,  ## Any other area, outlined and named at its first frame
}
## The margin of the grid a row or column's label goes in
enum Side { NONE, LEFT, RIGHT, TOP, BOTTOM }


## The cells of [param cells] without repeats, in the order they're first shown
static func distinct_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {}
	var result: Array[Vector2i] = []
	for cell in cells:
		if not seen.has(cell):
			seen[cell] = true
			result.append(cell)
	return result


## What shape the animation of [param cells] makes in a grid of [param grid_size], where
## [param has_frame] tells which cells hold a frame (every one when it isn't given).
## Returns [code]{"shape": Shape, "cells": Array[Vector2i], "side": Side, "line": int}
## [/code]: the cells labelled without repeats (the frames of a row or column, every cell
## of an outline, empty gaps included), and for a row or a column the margin the label
## goes in and which row or column it is. A frame alone in its row is that whole row.
static func classify(
	cells: Array[Vector2i], grid_size: Vector2i, has_frame := Callable()
) -> Dictionary:
	if not has_frame.is_valid():
		has_frame = func(_cell: Vector2i) -> bool: return true
	var grid := Rect2i(Vector2i.ZERO, grid_size)
	# Empty cells off the grid are left out, rather than scattering the animation
	var kept := func(cell: Vector2i) -> bool: return grid.has_point(cell) or has_frame.call(cell)
	var distinct: Array[Vector2i] = []
	distinct.assign(distinct_cells(cells).filter(kept))
	var frames: Array[Vector2i] = []
	frames.assign(distinct.filter(has_frame))
	var result := {"shape": Shape.NONE, "cells": distinct, "side": Side.NONE, "line": -1}
	var inside := func(cell: Vector2i) -> bool: return grid.has_point(cell)
	if frames.is_empty() or not distinct.all(inside):
		return result
	var first: Vector2i = frames[0]
	var row := _frames_along(Vector2i(0, first.y), Vector2i.RIGHT, grid_size.x, has_frame)
	var column := _frames_along(Vector2i(first.x, 0), Vector2i.DOWN, grid_size.y, has_frame)
	if _is_whole(frames, row):
		result.shape = Shape.ROW
		result.cells = frames
		result.side = Side.LEFT if _starts_nearer_start(first, row) else Side.RIGHT
		result.line = first.y
	elif _is_whole(frames, column):
		result.shape = Shape.COLUMN
		result.cells = frames
		result.side = Side.TOP if _starts_nearer_start(first, column) else Side.BOTTOM
		result.line = first.x
	else:
		distinct.append_array(_empty_gaps(distinct, grid, has_frame))
		if _is_block(distinct):
			result.shape = Shape.BLOCK
		elif _is_area(distinct, grid_size):
			result.shape = Shape.AREA
	return result


## The empty cells between two of [param cells] in a row or a column, with nothing but
## empty cells between them
static func _empty_gaps(
	cells: Array[Vector2i], grid: Rect2i, has_frame: Callable
) -> Array[Vector2i]:
	var gaps: Array[Vector2i] = []
	var taken: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		taken[cell] = true
	for cell in cells:
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var between: Array[Vector2i] = []
			var next := cell + step
			while grid.has_point(next) and not taken.has(next) and not has_frame.call(next):
				between.append(next)
				next += step
			if taken.has(next):
				for gap in between:
					if not gap in gaps:
						gaps.append(gap)
	return gaps


## The cells holding a frame among the [param count] from [param start] on by [param step]
static func _frames_along(
	start: Vector2i, step: Vector2i, count: int, has_frame: Callable
) -> Array[Vector2i]:
	var frames: Array[Vector2i] = []
	for i in count:
		var cell := start + step * i
		if has_frame.call(cell):
			frames.append(cell)
	return frames


## Whether [param cells], all different, are all of [param line] and nothing else, in
## any order
static func _is_whole(cells: Array[Vector2i], line: Array[Vector2i]) -> bool:
	var in_line := func(cell: Vector2i) -> bool: return cell in line
	return cells.size() == line.size() and cells.all(in_line)


## Whether [param first] is in the first half of [param line], or its middle
static func _starts_nearer_start(first: Vector2i, line: Array[Vector2i]) -> bool:
	return line.find(first) * 2 <= line.size() - 1


## Whether [param cells], all different, fill a rectangle of at least two rows and two
## columns
static func _is_block(cells: Array[Vector2i]) -> bool:
	var bounds := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	var size := bounds.size
	return size.x >= 2 and size.y >= 2 and cells.size() == size.x * size.y


## Whether [param cells] are connected: each reached from the first through cells that
## touch side to side, or that follow on from the end of a row to the start of the next
static func _is_area(cells: Array[Vector2i], grid_size: Vector2i) -> bool:
	var left: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		left[cell] = true
	left.erase(cells[0])
	var reached: Array[Vector2i] = [cells[0]]
	while not reached.is_empty():
		var cell: Vector2i = reached.pop_back()
		var next: Array[Vector2i] = [
			cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN
		]
		if cell.x == grid_size.x - 1:
			next.append(Vector2i(0, cell.y + 1))
		if cell.x == 0:
			next.append(Vector2i(grid_size.x - 1, cell.y - 1))
		for neighbour in next:
			if left.erase(neighbour):
				reached.append(neighbour)
	return left.is_empty()


## How labels that overlap are told apart. [param labels] are results of [method classify]
## in the order of their animations. Labels overlap when their animations share cells, or
## when they go in the same margin of the same row or column. Returns for each label
## [code]{"stack": int, "stack_size": int, "inset": int}[/code]:
## [br]- its place among the labels in the same margin of its row or column, or among the
## outlines named at the same cell, first to last, and how many there are;
## [br]- for outlines, how many steps inside the cells it's drawn, so outlines around the
## same cells don't hide each other: each takes the first step no earlier outline around
## any of its cells takes.
static func arrange(labels: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cell_sets: Array[Dictionary] = []
	var slots := {}
	for i in labels.size():
		result.append({"stack": 0, "stack_size": 1, "inset": 0})
		var cells: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in labels[i].cells:
			cells[cell] = true
		cell_sets.append(cells)
		var slot := get_slot(labels[i])
		if not slots.has(slot):
			slots[slot] = []
		slots[slot].append(i)
	for slot: Vector3i in slots:
		var members: Array = slots[slot]
		for k in members.size():
			result[members[k]].stack = k
			result[members[k]].stack_size = members.size()
	for i in labels.size():
		if not is_outlined(labels[i]):
			continue
		var used: Array[int] = []
		for j in i:
			if is_outlined(labels[j]) and _shares_cells(cell_sets[i], cell_sets[j]):
				used.append(result[j].inset)
		var inset := 0
		while inset in used:
			inset += 1
		result[i].inset = inset
	return result


## Whether the label is an outline around the cells, rather than a name in a margin
static func is_outlined(label: Dictionary) -> bool:
	return label.shape in [Shape.BLOCK, Shape.AREA]


## Where the label's name goes: the margin and the row or column of a run, or the first
## cell of an outline. Labels in the same place are stacked.
static func get_slot(label: Dictionary) -> Vector3i:
	if is_outlined(label):
		var first: Vector2i = label.cells[0]
		return Vector3i(Side.NONE, first.x, first.y)
	return Vector3i(label.side, label.line, -1)


static func _shares_cells(a: Dictionary[Vector2i, bool], b: Dictionary[Vector2i, bool]) -> bool:
	var smaller := a if a.size() <= b.size() else b
	var larger := b if smaller == a else a
	for cell in smaller:
		if larger.has(cell):
			return true
	return false


## Moves text so none of it is drawn over other text. [param wanted] are where each text
## would go, most important first, and [param away] the way each may move to make room,
## e.g. further into its margin. Each is moved past what it overlaps, up to
## [param tries] times. Returns where each goes, or an empty rectangle for text that
## found no room and isn't drawn.
static func place(
	wanted: Array[Rect2], away: Array[Vector2], gap := 2.0, tries := 4
) -> Array[Rect2]:
	var placed: Array[Rect2] = []
	for i in wanted.size():
		var rect := wanted[i]
		var fits := false
		for attempt in tries + 1:
			var blocking: Variant = _overlapping(rect, placed, gap)
			if blocking == null:
				fits = true
				break
			rect = _moved_past(rect, blocking, away[i], gap)
		placed.append(rect if fits else Rect2())
	return placed


## The first of [param placed] that [param rect] overlaps, or null
static func _overlapping(rect: Rect2, placed: Array[Rect2], gap: float) -> Variant:
	for other in placed:
		if other.has_area() and rect.grow(gap / 2).intersects(other.grow(gap / 2)):
			return other
	return null


## [param rect] moved along [param direction] until it's [param gap] past [param other]
static func _moved_past(rect: Rect2, other: Rect2, direction: Vector2, gap: float) -> Rect2:
	var moved := rect
	if direction.x < 0:
		moved.position.x = other.position.x - gap - rect.size.x
	elif direction.x > 0:
		moved.position.x = other.end.x + gap
	elif direction.y < 0:
		moved.position.y = other.position.y - gap - rect.size.y
	else:
		moved.position.y = other.end.y + gap
	return moved
