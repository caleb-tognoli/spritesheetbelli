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
