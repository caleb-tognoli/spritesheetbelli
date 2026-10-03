class_name GuideLines
extends RefCounted
## The guides of a [SpritesheetPreview]'s sheet (see [method Spritesheet.get_guides]),
## drawn in every cell while [member shown], and the ones dragged from its [Rulers]:
## where they'd go, and whether they'd be removed.

## Godot's editors/2d/guides_color
const COLOR := Color(0.6, 0.0, 0.8)
const DRAGGED_COLOR := Color(0.75, 0.3, 1.0)
## No guide grabbed: the guides dragged are new ones
const NEW := -(1 << 30)

## Whether guides are shown, with the rulers, see the show_rulers setting
var shown := false
## The axes of the guides dragged: one, or both from the rulers' corner. Empty when
## nothing is dragged.
var dragged_axes: Array[int] = []
## The guide dragged, across the one axis of [member dragged_axes], or [constant NEW]
var grabbed := NEW
## Where the dragged guides would go, in pixels from the cells' top-left corner
var dragged_to := Vector2i.ZERO
## Whether letting go would remove the guide grabbed, or not add the new ones
var removing := false


func is_dragging() -> bool:
	return not dragged_axes.is_empty()


func start_drag(axes: Array[int], guide := NEW) -> void:
	dragged_axes = axes
	grabbed = guide
	removing = false


func stop_drag() -> void:
	dragged_axes = []
	grabbed = NEW
	removing = false


## The guides across [param axis] as they'd be after the drag, in pixels from the cells'
## top-left corner. [param with_dragged] leaves out the dragged one, to draw it apart.
func get_cell_guides(sheet: Spritesheet, axis: int, with_dragged := true) -> PackedInt32Array:
	var result := PackedInt32Array()
	var dragged := axis in dragged_axes
	for guide in sheet.get_guides(axis):
		if not (dragged and guide == grabbed):
			result.append(sheet.guide_to_cell(axis, guide))
	if dragged and with_dragged and not removing:
		result.append(dragged_to[axis])
	return result


## The guides of the sheet once the drag ends, for [method Spritesheet.set_guides]. Those
## not dragged keep their own values, which pixels of scaled cells may not tell apart.
func get_dropped_guides(sheet: Spritesheet) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for axis in 2:
		var values := sheet.get_guides(axis)
		if axis in dragged_axes:
			if grabbed != NEW:
				values.remove_at(values.find(grabbed))
			if not removing:
				values.append(sheet.cell_to_guide(axis, dragged_to[axis]))
		result.append(values)
	return result


## Draws the guides in the cells of [param visible_cells] of [param canvas], with
## [param pixel] a pixel on screen: each across the visible cells when there's no room
## between them, else in each cell
func draw(canvas: SpritesheetPreview, visible_cells: Rect2i, pixel: float) -> void:
	if not shown or visible_cells.size.x <= 0 or visible_cells.size.y <= 0:
		return
	var grid := canvas.grid_view
	var cell := Vector2(canvas.spritesheet.sprite_size)
	var first := grid.get_cell_rect(visible_cells.position)
	var last := grid.get_cell_rect(visible_cells.end - Vector2i.ONE)
	for axis in 2:
		var across := 1 - axis
		# Runs of cells the lines go through: all the visible ones at once, or one by one
		var runs: Array[Vector2] = []
		if grid.has_gaps():
			for i in range(visible_cells.position[across], visible_cells.end[across]):
				var start := grid.origin[across] + i * grid.step[across]
				runs.append(Vector2(start, start + cell[across]))
		else:
			runs.append(Vector2(first.position[across], last.end[across]))
		for in_cell in get_cell_guides(canvas.spritesheet, axis, false):
			_draw_lines(canvas, visible_cells, axis, in_cell, runs, COLOR, pixel)
		if axis in dragged_axes and not removing:
			_draw_lines(canvas, visible_cells, axis, dragged_to[axis], runs, DRAGGED_COLOR, pixel)


## Lines at [param in_cell] across [param axis] of every visible cell
static func _draw_lines(
	canvas: SpritesheetPreview,
	visible_cells: Rect2i,
	axis: int,
	in_cell: float,
	runs: Array[Vector2],
	color: Color,
	pixel: float
) -> void:
	var grid := canvas.grid_view
	if in_cell < 0 or in_cell > canvas.spritesheet.sprite_size[axis]:
		return
	for i in range(visible_cells.position[axis], visible_cells.end[axis]):
		var at := grid.origin[axis] + i * grid.step[axis] + in_cell
		for run in runs:
			var from := Vector2.ZERO
			var to := Vector2.ZERO
			from[axis] = at
			to[axis] = at
			from[1 - axis] = run.x
			to[1 - axis] = run.y
			canvas.draw_line(from, to, color, pixel)
