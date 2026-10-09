extends "res://tests/test_case.gd"
## Tidying frames made pixel by pixel (PixelCleanup): jags the keys don't have smoothed
## away, those they do kept

const SIZE := 16
const FILL := Color("3b6fd1")


## A canvas [param SIZE] pixels square showing [param rects] and [param pixels]
static func canvas(rects: Array[Rect2i], pixels: Array[Vector2i] = []) -> PackedByteArray:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for rect in rects:
		img.fill_rect(rect, FILL)
	for at in pixels:
		img.set_pixelv(at, FILL)
	return img.get_data()


static func shown(data: PackedByteArray, at: Vector2i) -> bool:
	return data[(at.y * SIZE + at.x) * 4 + 3] > 0


func test_a_jag_the_keys_dont_have_goes() -> void:
	var keys := PixelCleanup.shapes_of(canvas([Rect2i(4, 4, 8, 8)]), SIZE, SIZE)
	# A pixel sticking out of the block's side, and a notch in its top
	var frame := canvas([Rect2i(4, 4, 8, 8)], [Vector2i(12, 7)])
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, frame)
	img.set_pixel(7, 4, Color(0, 0, 0, 0))
	frame = img.get_data()
	PixelCleanup.smooth_jags(frame, SIZE, SIZE, keys)
	assert_false(shown(frame, Vector2i(12, 7)), "the pixel sticking out goes")
	assert_true(shown(frame, Vector2i(7, 4)), "the notch is filled")
	assert_eq(frame[(4 * SIZE + 7) * 4], FILL.r8, "with the block's colour")


func test_a_jag_the_keys_have_stays() -> void:
	# The keys have a pixel sticking out of the block's side, like a nose
	var keys := PixelCleanup.shapes_of(canvas([Rect2i(4, 4, 8, 8)], [Vector2i(12, 7)]), SIZE, SIZE)
	var frame := canvas([Rect2i(3, 5, 8, 8)], [Vector2i(11, 8)])
	PixelCleanup.smooth_jags(frame, SIZE, SIZE, keys)
	assert_true(shown(frame, Vector2i(11, 8)), "the nose stays")


func test_corners_of_a_turned_shape_stay() -> void:
	# Keys of an upright block only; a frame with a stair-stepped edge keeps its steps
	var keys := PixelCleanup.shapes_of(canvas([Rect2i(4, 4, 8, 8)]), SIZE, SIZE)
	var frame := canvas([Rect2i(4, 6, 8, 6), Rect2i(4, 4, 4, 2)])
	var before := frame.duplicate()
	PixelCleanup.smooth_jags(frame, SIZE, SIZE, keys)
	assert_eq(frame, before, "steps two pixels wide aren't jags")


func test_bits_left_floating_go() -> void:
	# A block and, apart from it, a short line that came off it
	var frame := canvas([Rect2i(2, 2, 8, 8)], [Vector2i(12, 3), Vector2i(13, 4)])
	PixelCleanup.clear_floating(frame, SIZE, 6)
	assert_false(shown(frame, Vector2i(12, 3)), "the line goes")
	assert_true(shown(frame, Vector2i(5, 5)), "the block stays")


func test_parts_as_big_as_the_keys_have_stay() -> void:
	var frame := canvas([Rect2i(2, 2, 8, 8), Rect2i(12, 12, 3, 3)])
	PixelCleanup.clear_floating(frame, SIZE, 6)
	assert_true(shown(frame, Vector2i(13, 13)), "a part of 9 pixels isn't floating")


func test_a_step_filled_on_a_slope_goes() -> void:
	# Keys of a diamond, its sides even stairs; a frame with one step filled in
	var diamond: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if absi(x - 8) + absi(y - 8) <= 5:
				diamond.append(Vector2i(x, y))
	var keys := PixelCleanup.shapes_of(canvas([], diamond), SIZE, SIZE)
	var wide := PixelCleanup.wide_shapes_of(canvas([], diamond), SIZE, SIZE)
	var stepped: Array[Vector2i] = diamond.duplicate()
	stepped.append(Vector2i(11, 11))
	var frame := canvas([], stepped)
	PixelCleanup.smooth_jags(frame, SIZE, SIZE, keys, 1, wide)
	assert_false(shown(frame, Vector2i(11, 11)), "the step is cut back")
	assert_true(shown(frame, Vector2i(10, 11)), "the diamond stays")
