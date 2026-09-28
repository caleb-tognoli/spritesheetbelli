class_name Slicer
## Cuts a spritesheet image into frames.

## The most cells on either axis, as many as the grid fields take
const MAX_GRID := 1024


## Splits [param img] into [param grid] cells after skipping [param offset] pixels at the
## top-left, with [param spacing] pixels between cells. Fully transparent cells are left out.
## The cells are [param cell_size] when it's given, or else as big as fits (see
## [method get_cell_size]).
## Returns [code]{"cell_size": Vector2i, "frames": Dictionary[Vector2i, Image],
## "rects": Dictionary[Vector2i, Rect2i], "unused": Vector2i}[/code], where rects are where
## the frames are in the image and unused is the pixels left over on the right and bottom.
static func slice(
	img: Image,
	grid: Vector2i,
	offset := Vector2i.ZERO,
	spacing := Vector2i.ZERO,
	cell_size := Vector2i.ZERO,
) -> Dictionary:
	var size := img.get_size()
	grid = grid.max(Vector2i.ONE)
	offset = offset.clamp(Vector2i.ZERO, size)
	spacing = spacing.max(Vector2i.ZERO)
	if cell_size == Vector2i.ZERO:
		cell_size = get_cell_size(size, grid, offset, spacing)
	var unused := get_unused(size, grid, cell_size, offset, spacing)

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


## The size of the biggest cells that fit [param grid] times in [param image_size] after
## [param offset], with [param spacing] between them. Pixels that don't divide evenly are
## left over on the right and bottom.
static func get_cell_size(
	image_size: Vector2i, grid: Vector2i, offset := Vector2i.ZERO, spacing := Vector2i.ZERO
) -> Vector2i:
	var room := image_size - offset + spacing
	return (room / grid.max(Vector2i.ONE) - spacing).max(Vector2i.ZERO)


## The size of [param grid] cells in [param img], like [method get_cell_size], except that a
## strip as wide as [param spacing] after the last cell, with only background in it, is left
## over instead of making the cells bigger: many sheets have spacing after every cell, the
## last one too. Background is transparency, or [param background] when it's a colour,
## within [param tolerance], for a sheet drawn on one.
static func get_cell_size_in(
	img: Image,
	grid: Vector2i,
	offset := Vector2i.ZERO,
	spacing := Vector2i.ZERO,
	background: Variant = null,
	tolerance := SheetBackground.DEFAULT_TOLERANCE,
) -> Vector2i:
	var size := img.get_size()
	grid = grid.max(Vector2i.ONE)
	var cell_size := get_cell_size(size, grid, offset, spacing)
	for axis in 2:
		# The cells fit with the spacing after the last one when the room divides evenly
		var room := size[axis] - offset[axis]
		var cell := room / grid[axis] - spacing[axis]
		if spacing[axis] <= 0 or room % grid[axis] != 0 or cell <= 0 or cell >= cell_size[axis]:
			continue
		var strip := Rect2i(offset, size - offset)
		strip.position[axis] = size[axis] - spacing[axis]
		strip.size[axis] = spacing[axis]
		if _is_background(img, strip, background, tolerance):
			cell_size[axis] = cell
	return cell_size


## How many cells of [param cell_size] fit in [param image_size] after [param offset], with
## [param spacing] between them, at least one. Spacing after the last cell is left over, not
## part of a cell.
static func get_grid_size(
	image_size: Vector2i, cell_size: Vector2i, offset := Vector2i.ZERO, spacing := Vector2i.ZERO
) -> Vector2i:
	var room := image_size - offset + spacing
	return (room / (cell_size.max(Vector2i.ONE) + spacing)).max(Vector2i.ONE)


## The pixels on the right and bottom of [param image_size] outside [param grid] cells of
## [param cell_size]
static func get_unused(
	image_size: Vector2i,
	grid: Vector2i,
	cell_size: Vector2i,
	offset := Vector2i.ZERO,
	spacing := Vector2i.ZERO,
) -> Vector2i:
	var used := offset + grid * cell_size + (grid - Vector2i.ONE) * spacing
	return (image_size - used).max(Vector2i.ZERO)


## Fits a grid in [param image_size] from either its number of cells, [param grid], or their
## size, [param cell_size]: the other follows from the image size, [param offset] and
## [param spacing]. [param by_cell_size] keeps the cell size, or else the grid. Both are
## clamped so every cell is in the image and at least 1 px. Given the image, [param img], a
## grid leaves the spacing after the last cell over when it's background, transparency or
## [param background], see [method get_cell_size_in].
## Returns [code]{"grid": Vector2i, "cell_size": Vector2i, "unused": Vector2i}[/code].
static func fit(
	image_size: Vector2i,
	grid: Vector2i,
	cell_size: Vector2i,
	offset: Vector2i,
	spacing: Vector2i,
	by_cell_size: bool,
	img: Image = null,
	background: Variant = null,
) -> Dictionary:
	image_size = image_size.max(Vector2i.ONE)
	offset = offset.clamp(Vector2i.ZERO, image_size - Vector2i.ONE)
	spacing = spacing.max(Vector2i.ZERO)
	var most := get_grid_size(image_size, Vector2i.ONE, offset, spacing).mini(MAX_GRID)
	if by_cell_size:
		cell_size = cell_size.clamp(Vector2i.ONE, image_size - offset)
		grid = get_grid_size(image_size, cell_size, offset, spacing).min(most)
	else:
		grid = grid.clamp(Vector2i.ONE, most)
		if img:
			cell_size = get_cell_size_in(img, grid, offset, spacing, background)
		else:
			cell_size = get_cell_size(image_size, grid, offset, spacing)
	return {
		"grid": grid,
		"cell_size": cell_size,
		"unused": get_unused(image_size, grid, cell_size, offset, spacing),
	}


## Whether every pixel of [param img] in [param rect] is transparent, or close to
## [param background] when it's a colour
static func _is_background(img: Image, rect: Rect2i, background: Variant, tolerance: float) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := img.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			if background == null or not SheetBackground.is_close(color, background, tolerance):
				return false
	return true
