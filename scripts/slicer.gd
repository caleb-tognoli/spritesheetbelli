class_name Slicer
## Cuts a spritesheet image into frames.


## Splits [param img] into [param grid] cells after skipping [param offset] pixels at the
## top-left, with [param spacing] pixels between cells. Fully transparent cells are left out.
## Returns [code]{"cell_size": Vector2i, "frames": Dictionary[Vector2i, Image],
## "unused": Vector2i}[/code], where unused is the pixels left over on the right and bottom.
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
	if cell_size.x > 0 and cell_size.y > 0:
		for row in grid.y:
			for column in grid.x:
				var coord := Vector2i(column, row)
				var position := offset + coord * (cell_size + spacing)
				var frame := img.get_region(Rect2i(position, cell_size))
				if not frame.is_invisible():
					frames[coord] = frame
	return {"cell_size": cell_size, "frames": frames, "unused": unused}
