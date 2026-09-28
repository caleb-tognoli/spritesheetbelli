extends "res://tests/test_case.gd"


func test_even_grid() -> void:
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(16, 0, 16, 16), Color.RED)
	var result := Slicer.slice(img, Vector2i(2, 1))
	assert_eq(result.cell_size, Vector2i(16, 16))
	assert_eq(result.frames.keys(), [Vector2i(1, 0)], "transparent cell left out")
	assert_eq(result.unused, Vector2i.ZERO)


func test_offset_and_spacing() -> void:
	# 2 px border, 16 px cells, 4 px gaps
	var img := Image.create_empty(2 + 16 + 4 + 16, 2 + 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 16, 16), Color.RED)
	img.fill_rect(Rect2i(22, 2, 16, 16), Color.BLUE)
	var result := Slicer.slice(img, Vector2i(2, 1), Vector2i(2, 2), Vector2i(4, 0))
	assert_eq(result.cell_size, Vector2i(16, 16))
	assert_color(result.frames[Vector2i(0, 0)], Vector2i(0, 0), Color.RED)
	assert_color(result.frames[Vector2i(1, 0)], Vector2i(15, 15), Color.BLUE)


func test_uneven_size_reports_unused_pixels() -> void:
	var img := Image.create_empty(50, 33, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var result := Slicer.slice(img, Vector2i(3, 2))
	assert_eq(result.cell_size, Vector2i(16, 16))
	assert_eq(result.unused, Vector2i(2, 1))


## 24 px sprites with a 4 px border and 2 px gaps, and 2 px of spacing after the last
## column and row too, on a grey background: 134×56
func trailing_spacing_sheet() -> Image:
	var img := Image.create_empty(134, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color.GRAY)
	for row in 2:
		for column in 5:
			img.fill_rect(
				Rect2i(Vector2i(4, 4) + Vector2i(column, row) * 26, Vector2i(24, 24)), Color.RED
			)
	return img


func test_cell_size_from_grid() -> void:
	assert_eq(Slicer.get_cell_size(Vector2i(64, 32), Vector2i(4, 2)), Vector2i(16, 16))
	assert_eq(
		Slicer.get_cell_size(Vector2i(50, 33), Vector2i(3, 2)), Vector2i(16, 16), "rounded down"
	)
	# 2 + 16 + 4 + 16 = 38
	assert_eq(
		Slicer.get_cell_size(Vector2i(38, 18), Vector2i(2, 1), Vector2i(2, 2), Vector2i(4, 0)),
		Vector2i(16, 16)
	)
	assert_eq(Slicer.get_cell_size(Vector2i(8, 8), Vector2i(16, 1)), Vector2i(0, 8), "no room")


func test_grid_from_cell_size() -> void:
	assert_eq(Slicer.get_grid_size(Vector2i(64, 32), Vector2i(16, 16)), Vector2i(4, 2))
	assert_eq(
		Slicer.get_grid_size(Vector2i(50, 33), Vector2i(16, 16)), Vector2i(3, 2), "rounded down"
	)
	assert_eq(
		Slicer.get_grid_size(Vector2i(38, 18), Vector2i(16, 16), Vector2i(2, 2), Vector2i(4, 0)),
		Vector2i(2, 1)
	)
	assert_eq(Slicer.get_grid_size(Vector2i(8, 8), Vector2i(16, 16)), Vector2i.ONE, "at least one")


func test_grid_and_cell_size_are_as_big_as_fit() -> void:
	var size := Vector2i(134, 56)
	var offset := Vector2i(4, 4)
	var spacing := Vector2i(2, 2)
	for columns in range(1, 40):
		var grid := Vector2i(columns, 1 + columns % 5)
		var cell := Slicer.get_cell_size(size, grid, offset, spacing)
		var unused := Slicer.get_unused(size, grid, cell, offset, spacing)
		assert_true(unused.x < grid.x and unused.y < grid.y, "cells as big as fit %s" % grid)
	for width in range(1, 100):
		var cell := Vector2i(width, 1 + width % 40)
		var grid := Slicer.get_grid_size(size, cell, offset, spacing)
		var unused := Slicer.get_unused(size, grid, cell, offset, spacing)
		assert_true(
			unused.x < cell.x + spacing.x and unused.y < cell.y + spacing.y,
			"as many cells as fit %s" % cell
		)


func test_unused_pixels() -> void:
	assert_eq(Slicer.get_unused(Vector2i(64, 32), Vector2i(4, 2), Vector2i(16, 16)), Vector2i.ZERO)
	assert_eq(Slicer.get_unused(Vector2i(50, 33), Vector2i(3, 2), Vector2i(16, 16)), Vector2i(2, 1))
	assert_eq(
		Slicer.get_unused(
			Vector2i(134, 56), Vector2i(5, 2), Vector2i(24, 24), Vector2i(4, 4), Vector2i(2, 2)
		),
		Vector2i(2, 2),
		"spacing after the last cell"
	)


func test_trailing_spacing_is_left_over() -> void:
	var img := trailing_spacing_sheet()
	var offset := Vector2i(4, 4)
	var spacing := Vector2i(2, 2)
	var fitted := Slicer.fit(img.get_size(), Vector2i.ONE, Vector2i(24, 24), offset, spacing, true)
	assert_eq(fitted.grid, Vector2i(5, 2), "floor((134 - 4 + 2) / 26), floor((56 - 4 + 2) / 26)")
	assert_eq(fitted.cell_size, Vector2i(24, 24))
	assert_eq(fitted.unused, Vector2i(2, 2))
	var result := Slicer.slice(img, fitted.grid, offset, spacing, fitted.cell_size)
	assert_eq(result.frames.size(), 10)
	assert_eq(result.unused, Vector2i(2, 2))
	assert_eq(result.rects[Vector2i(4, 1)], Rect2i(108, 30, 24, 24))
	for coord: Vector2i in result.frames:
		var frame: Image = result.frames[coord]
		assert_eq(frame.get_size(), Vector2i(24, 24))
		assert_color(frame, Vector2i(23, 23), Color.RED, "no background in %s" % coord)


func test_fit_keeps_the_cell_size() -> void:
	var size := Vector2i(134, 56)
	var cell := Vector2i(24, 24)
	var fitted := Slicer.fit(size, Vector2i(9, 9), cell, Vector2i.ZERO, Vector2i.ZERO, true)
	assert_eq(fitted.grid, Vector2i(5, 2), "the grid follows")
	assert_eq(fitted.cell_size, cell)
	assert_eq(fitted.unused, Vector2i(14, 8))
	fitted = Slicer.fit(size, fitted.grid, cell, Vector2i(4, 4), Vector2i(2, 2), true)
	assert_eq(fitted.cell_size, cell, "kept when the offset and spacing change")
	assert_eq(fitted.grid, Vector2i(5, 2))
	fitted = Slicer.fit(size, fitted.grid, cell, Vector2i(4, 4), Vector2i(8, 8), true)
	assert_eq(fitted.cell_size, cell)
	assert_eq(fitted.grid, Vector2i(4, 1), "fewer cells fit")
	assert_eq(fitted.unused, Vector2i(10, 28))


func test_fit_keeps_the_grid() -> void:
	var size := Vector2i(134, 56)
	var grid := Vector2i(5, 2)
	var fitted := Slicer.fit(size, grid, Vector2i(24, 24), Vector2i.ZERO, Vector2i.ZERO, false)
	assert_eq(fitted.grid, grid)
	assert_eq(fitted.cell_size, Vector2i(26, 28), "the cell size follows")
	assert_eq(fitted.unused, Vector2i(4, 0))
	fitted = Slicer.fit(size, grid, fitted.cell_size, Vector2i(4, 4), Vector2i(2, 2), false)
	assert_eq(fitted.grid, grid, "kept when the offset and spacing change")
	assert_eq(fitted.cell_size, Vector2i(24, 25), "the trailing spacing can't be told apart")
	assert_eq(fitted.unused, Vector2i(2, 0))
	var img := trailing_spacing_sheet()
	fitted = Slicer.fit(size, grid, Vector2i.ONE, Vector2i(4, 4), Vector2i(2, 2), false, img)
	assert_eq(fitted.cell_size, Vector2i(24, 25), "grey is art without being told")
	fitted = Slicer.fit(
		size, grid, Vector2i.ONE, Vector2i(4, 4), Vector2i(2, 2), false, img, Color.GRAY
	)
	assert_eq(fitted.cell_size, Vector2i(24, 24), "but the image tells it apart")
	assert_eq(fitted.unused, Vector2i(2, 2))


## [param grid] sprites filling 24 px cells, with a 4 px border and 2 px gaps, and 2 px of
## spacing after the last column and row too, on [param background]: 134×56 for 5 × 2
func spacing_sheet(grid: Vector2i, background := Color.TRANSPARENT) -> Image:
	var size := Vector2i(4, 4) + grid * 26
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(background)
	for row in grid.y:
		for column in grid.x:
			img.fill_rect(
				Rect2i(Vector2i(4, 4) + Vector2i(column, row) * 26, Vector2i(24, 24)), Color.RED
			)
	return img


func test_spacing_after_the_last_cell_is_left_over_when_its_background() -> void:
	var offset := Vector2i(4, 4)
	var spacing := Vector2i(2, 2)
	var grid := Vector2i(5, 2)
	var img := spacing_sheet(grid)
	assert_eq(img.get_size(), Vector2i(134, 56))
	assert_eq(Slicer.get_cell_size(img.get_size(), grid, offset, spacing), Vector2i(24, 25))
	assert_eq(Slicer.get_cell_size_in(img, grid, offset, spacing), Vector2i(24, 24))
	var fitted := Slicer.fit(img.get_size(), grid, Vector2i.ONE, offset, spacing, false, img)
	assert_eq(fitted.grid, grid)
	assert_eq(fitted.cell_size, Vector2i(24, 24))
	assert_eq(fitted.unused, Vector2i(2, 2), "the spacing after the last cells")
	var result := Slicer.slice(img, grid, offset, spacing, fitted.cell_size)
	assert_eq(result.frames.size(), 10)
	for coord: Vector2i in result.frames:
		var frame: Image = result.frames[coord]
		assert_color(frame, Vector2i(23, 23), Color.RED, "no background in %s" % coord)

	img = spacing_sheet(Vector2i(2, 2))
	assert_eq(
		Slicer.get_cell_size(img.get_size(), Vector2i(2, 2), offset, spacing), Vector2i(25, 25)
	)
	assert_eq(
		Slicer.get_cell_size_in(img, Vector2i(2, 2), offset, spacing),
		Vector2i(24, 24),
		"across too"
	)


func test_spacing_of_the_background_colour_is_left_over() -> void:
	var offset := Vector2i(4, 4)
	var spacing := Vector2i(2, 2)
	var grid := Vector2i(5, 2)
	var img := spacing_sheet(grid, Color.MAGENTA)
	var fitted := Slicer.fit(
		img.get_size(), grid, Vector2i.ONE, offset, spacing, false, img, Color.MAGENTA
	)
	assert_eq(fitted.cell_size, Vector2i(24, 24))
	assert_eq(fitted.unused, Vector2i(2, 2))
	assert_eq(
		Slicer.get_cell_size_in(img, grid, offset, spacing),
		Vector2i(24, 25),
		"magenta is art without being told"
	)
	img.set_pixel(130, 55, Color(1, 0.05, 1))
	assert_eq(
		Slicer.get_cell_size_in(img, grid, offset, spacing, Color.MAGENTA),
		Vector2i(24, 24),
		"close to it"
	)


func test_spacing_with_sprite_pixels_is_divided() -> void:
	var offset := Vector2i(4, 4)
	var spacing := Vector2i(2, 2)
	var img := spacing_sheet(Vector2i(5, 2))
	img.set_pixel(60, 55, Color.RED)
	assert_eq(
		Slicer.get_cell_size_in(img, Vector2i(5, 2), offset, spacing),
		Vector2i(24, 25),
		"as without the image"
	)
	img = spacing_sheet(Vector2i(2, 2), Color.MAGENTA)
	img.set_pixel(55, 10, Color.RED)
	assert_eq(
		Slicer.get_cell_size_in(img, Vector2i(2, 2), offset, spacing, Color.MAGENTA),
		Vector2i(25, 24),
		"only across"
	)
	img = spacing_sheet(Vector2i(2, 2))
	assert_eq(
		Slicer.get_cell_size_in(img, Vector2i(2, 2), offset, Vector2i.ZERO),
		Vector2i(26, 26),
		"no spacing"
	)


func test_fit_keeps_cells_in_the_image() -> void:
	var size := Vector2i(40, 20)
	var fitted := Slicer.fit(
		size, Vector2i.ONE, Vector2i(100, 100), Vector2i(4, 2), Vector2i.ZERO, true
	)
	assert_eq(fitted.cell_size, Vector2i(36, 18), "at most what's left after the offset")
	assert_eq(fitted.grid, Vector2i.ONE)
	fitted = Slicer.fit(
		size, Vector2i(100, 100), Vector2i.ONE, Vector2i.ZERO, Vector2i(1, 1), false
	)
	assert_eq(fitted.grid, Vector2i(20, 10), "cells of at least a pixel")
	assert_eq(fitted.cell_size, Vector2i.ONE)
	fitted = Slicer.fit(
		Vector2i(4096, 8), Vector2i.ONE, Vector2i.ONE, Vector2i.ZERO, Vector2i.ZERO, true
	)
	assert_eq(fitted.grid, Vector2i(Slicer.MAX_GRID, 8), "at most as many as the fields take")
