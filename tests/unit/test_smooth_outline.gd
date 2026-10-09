extends "res://tests/test_case.gd"
## A shape's outline smoothed for drawing it grown (SmoothOutline): stairs become slopes,
## thin parts stay, and pixels' middles are as they are

const SIZE := 24


## A canvas [param SIZE] pixels square with [param pixels] shown
static func mask_of(pixels: Array[Vector2i]) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(SIZE * SIZE)
	for at in pixels:
		mask[at.y * SIZE + at.x] = 1
	return mask


## The pixels of a rectangle
static func rect_pixels(rect: Rect2i) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			pixels.append(Vector2i(x, y))
	return pixels


func test_a_block_is_itself_at_its_pixels_middles() -> void:
	var outline := SmoothOutline.of(mask_of(rect_pixels(Rect2i(6, 6, 10, 8))), SIZE, SIZE)
	for y in SIZE:
		for x in SIZE:
			var inside := Rect2i(6, 6, 10, 8).has_point(Vector2i(x, y))
			var deep := Rect2i(7, 7, 8, 6).has_point(Vector2i(x, y))
			var far := not Rect2i(5, 5, 12, 10).has_point(Vector2i(x, y))
			if deep:
				assert_true(outline.covers(Vector2(x + 0.5, y + 0.5)), "inside at %d, %d" % [x, y])
			if far:
				assert_false(
					outline.covers(Vector2(x + 0.5, y + 0.5)), "outside at %d, %d" % [x, y]
				)
			if not inside and not far:
				continue


func test_stairs_become_a_slope() -> void:
	# Stairs two pixels wide going down to the right, filled below
	var pixels: Array[Vector2i] = []
	for x in range(2, 22):
		for y in range(4 + x / 2, 22):
			pixels.append(Vector2i(x, y))
	var outline := SmoothOutline.of(mask_of(pixels), SIZE, SIZE)
	# Along the slope, the edge is about halfway between the stairs' corners
	for x in range(6, 18):
		var edge := 4.0 + x / 2.0
		var found := -1.0
		var y := 2.0
		while y < 20.0:
			if outline.covers(Vector2(x + 0.5, y)):
				found = y
				break
			y += 0.05
		assert_true(absf(found - (edge + 0.25)) < 0.6, "edge at %s near %s" % [found, edge + 0.25])


func test_thin_lines_stay() -> void:
	var line := rect_pixels(Rect2i(4, 10, 16, 1))
	var outline := SmoothOutline.of(mask_of(line), SIZE, SIZE)
	for x in range(4, 20):
		assert_true(outline.covers(Vector2(x + 0.5, 10.5)), "the line at %d" % x)
	assert_false(outline.covers(Vector2(10.5, 12.5)), "not round it")


func test_nothing_covers_nothing() -> void:
	var outline := SmoothOutline.of(mask_of([]), SIZE, SIZE)
	assert_false(outline.covers(Vector2(10, 10)))
