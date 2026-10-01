class_name PivotHandles
extends RefCounted
## The pivots of a [SpritesheetPreview]'s frames, while [member shown]: the selected
## frames, and the frame under the mouse, show their pivot as a cross to drag. Dragging a
## selected frame's pivot moves the pivots of every selected frame. Dragged pivots stay on
## whole pixels inside their frames, edges included, see [method FrameEdits.pivot_inside].

## On-screen size of pivot marks
const SIZE := 7.0
## How near a pivot on screen pressing grabs it
const REACH := 8.0

## Whether pivots are shown, see the use_pivots setting. Never where frames can't move.
var shown := false
## The frame whose pivot is under the mouse, see [method hover], or
## [constant SpritesheetPreview.NO_CELL]
var hovered := SpritesheetPreview.NO_CELL
## The frame whose pivot is dragged, or [constant SpritesheetPreview.NO_CELL]
var dragged := SpritesheetPreview.NO_CELL
## The frames that get the dragged pivot, and where it goes, in unscaled pixels of the
## dragged frame
var targets: Array[Vector2i] = []
var pivot := Vector2.ZERO

## Where the pivot is from the mouse, so it doesn't jump when grabbed
var _grab := Vector2.ZERO


## Whether pivots show in [param canvas]
func is_shown(canvas: SpritesheetPreview) -> bool:
	return shown and canvas.able_to_move_frames


## Whether the mouse is on a pivot, to drag it
func is_hovered(canvas: SpritesheetPreview) -> bool:
	return is_shown(canvas) and hovered != SpritesheetPreview.NO_CELL


## Finds the frame whose pivot is at [param screen_position] in [param canvas]: the frame
## there, or else one next to it, since pivots are often on an edge, like the bottom.
## Whether it's another than before.
func hover(canvas: SpritesheetPreview, screen_position: Vector2) -> bool:
	var found := SpritesheetPreview.NO_CELL
	var under := canvas.get_cell_at_screen_position(screen_position)
	if _reaches(canvas, under, screen_position):
		found = under
	elif is_shown(canvas):
		var reach := Vector2.ONE * REACH / canvas.camera.zoom.x
		var world := canvas.screen_to_world(screen_position)
		for coord in canvas.get_frames_in(Rect2(world - reach, reach * 2)):
			if _reaches(canvas, coord, screen_position):
				found = coord
				break
	if found == hovered:
		return false
	hovered = found
	return true


## Whether [param screen_position] is on the pivot of the frame at [param cell]
func _reaches(canvas: SpritesheetPreview, cell: Vector2i, screen_position: Vector2) -> bool:
	if not is_shown(canvas) or not canvas.spritesheet.has_frame(cell):
		return false
	var at := canvas.pivot_to_world(cell, canvas.spritesheet.get_pivot(cell))
	var on_screen := (at - canvas.screen_to_world(screen_position)) * canvas.camera.zoom
	return on_screen.length() <= REACH


## The frames whose pivot dragging [param cell]'s moves: the selection when it's in it,
## else only it
static func targets_of(canvas: SpritesheetPreview, cell: Vector2i) -> Array[Vector2i]:
	if canvas.is_selected(cell):
		return canvas.get_selected_coords()
	return [cell] as Array[Vector2i]


## Starts dragging the pivot of the frame at [param cell], grabbed at [param world]
func grab(canvas: SpritesheetPreview, cell: Vector2i, world: Vector2) -> void:
	dragged = cell
	targets = targets_of(canvas, cell)
	pivot = canvas.spritesheet.get_pivot(cell)
	_grab = canvas.pivot_to_world(cell, pivot) - world


## Moves the dragged pivot after the mouse at [param world]
func drag_to(canvas: SpritesheetPreview, world: Vector2) -> void:
	var to := canvas.world_to_pivot(dragged, world + _grab).round()
	pivot = FrameEdits.pivot_inside(canvas.spritesheet, dragged, to)


func release() -> void:
	dragged = SpritesheetPreview.NO_CELL


func is_dragging() -> bool:
	return dragged != SpritesheetPreview.NO_CELL


## The frames whose pivots show: the selected ones, the one whose pivot is under the
## mouse or else the one under it, and those whose pivot is dragged
func get_shown_coords(canvas: SpritesheetPreview) -> Array[Vector2i]:
	if not is_shown(canvas):
		return []
	var coords := canvas.get_selected_coords()
	var under := hovered if hovered != SpritesheetPreview.NO_CELL else canvas.hovered_cell
	var extra: Array[Vector2i] = [under]
	if is_dragging():
		extra = targets
	for coord in extra:
		if canvas.spritesheet.has_frame(coord) and coord not in coords:
			coords.append(coord)
	return coords


## Draws the pivots of [method get_shown_coords], the dragged ones where they go, with
## [param pixel] a pixel on screen. None while [param moving] frames.
func draw(canvas: SpritesheetPreview, pixel: float, moving: bool) -> void:
	if moving:
		return
	for coord in get_shown_coords(canvas):
		var at := canvas.spritesheet.get_pivot(coord)
		if is_dragging() and coord in targets:
			at = FrameEdits.pivot_inside(canvas.spritesheet, coord, pivot)
		_draw_cross(canvas, canvas.pivot_to_world(coord, at), pixel)


static func _draw_cross(canvas: SpritesheetPreview, at: Vector2, pixel: float) -> void:
	var arm := SIZE * pixel
	var accent := canvas.selection_color
	# An outline, then the accent over it
	for line: Array in [[Color.BLACK, 4], [accent, 2]]:
		var width: float = pixel * line[1]
		canvas.draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), line[0], width)
		canvas.draw_line(at - Vector2(0, arm), at + Vector2(0, arm), line[0], width)
	canvas.draw_circle(at, arm * 0.35, accent)
