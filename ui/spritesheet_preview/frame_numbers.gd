class_name FrameNumbers
extends RefCounted
## The numbers of a [SpritesheetPreview]'s frames, counted from the index_start setting, in
## the top-left corner of their cells or of their places on packed pages. They keep the
## same size at any zoom, and only show where there's room for them.

## Minimum on-screen size of a cell for its number to be shown
const MIN_SIZE := Vector2(40, 30)
const FONT_SIZE := 14


## The numbers of the frames in [param visible_cells] of the grid, but those an
## animation's name is drawn over
static func draw_in_cells(canvas: SpritesheetPreview, visible_cells: Rect2i) -> void:
	for coord in canvas.spritesheet.frames:
		if visible_cells.has_point(coord) and not _is_under_label(canvas, coord):
			_draw_number(canvas, coord, canvas.cell_rect(coord))
	canvas.draw_set_transform(Vector2.ZERO)


## The numbers of the packed frames in [param visible_rect] that are big enough on screen
static func draw_in_pages(canvas: SpritesheetPreview, visible_rect: Rect2) -> void:
	for coord in canvas.packed_view.get_frames_in(visible_rect):
		var rect := canvas.packed_view.get_frame_rect(coord)
		if rect.size * canvas.camera.zoom >= MIN_SIZE:
			_draw_number(canvas, coord, rect)
	canvas.draw_set_transform(Vector2.ZERO)


## Whether an animation's name is drawn where the frame's number would be
static func _is_under_label(canvas: SpritesheetPreview, coord: Vector2i) -> bool:
	var camera := canvas.camera
	var corner := (canvas.cell_rect(coord).position - camera.position) * camera.zoom
	var number := Rect2(corner + Vector2(4, 2), Vector2(36, FONT_SIZE + 6))
	return canvas.animation_labels.covers(number)


## The frame's number in the top-left corner of [param rect]
static func _draw_number(canvas: SpritesheetPreview, coord: Vector2i, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	# Text is drawn unscaled so it keeps the same size at any zoom
	canvas.draw_set_transform(rect.position, 0, Vector2.ONE / canvas.camera.zoom)
	var text := str(canvas.spritesheet.index_of(coord) + canvas.index_start)
	var text_position := Vector2(6, 4 + FONT_SIZE)
	canvas.draw_string_outline(
		font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 6, Color.BLACK
	)
	canvas.draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
