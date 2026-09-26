class_name Slicer
## Cuts a spritesheet image into frames.


## Splits [param img] into [param grid] cells after skipping [param offset] pixels at the
## top-left, with [param spacing] pixels between cells. Fully transparent cells are left out.
## Returns [code]{"cell_size": Vector2i, "frames": Dictionary[Vector2i, Image],
## "rects": Dictionary[Vector2i, Rect2i], "unused": Vector2i}[/code], where rects are where
## the frames are in the image and unused is the pixels left over on the right and bottom.
static func slice(
	img: Image, grid: Vector2i, offset := Vector2i.ZERO, spacing := Vector2i.ZERO
) -> Dictionary:
	grid = grid.max(Vector2i.ONE)
	offset = offset.clamp(Vector2i.ZERO, img.get_size())
	spacing = spacing.max(Vector2i.ZERO)
	var usable := img.get_size() - offset - spacing * (grid - Vector2i.ONE)
	var cell_size := (usable / grid).max(Vector2i.ZERO)
	var unused := (usable - cell_size * grid).max(Vector2i.ZERO)

	var frames: Dictionary[Vector2i, Image] = {}
	var rects: Dictionary[Vector2i, Rect2i] = {}
	if cell_size.x > 0 and cell_size.y > 0:
		for row in grid.y:
			for column in grid.x:
				var coord := Vector2i(column, row)
				var rect := Rect2i(offset + coord * (cell_size + spacing), cell_size)
				var frame := img.get_region(rect)
				if not frame.is_invisible():
					frames[coord] = frame
					rects[coord] = rect
	return {"cell_size": cell_size, "frames": frames, "rects": rects, "unused": unused}
