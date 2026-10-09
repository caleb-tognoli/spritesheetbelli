extends "res://tests/test_case.gd"
## One key's shape bent into the other's as rigidly as possible (ShapeBlend): outlines
## traced and matched, the shape bent part of the way

const SIZE := 40
const COLOR := Color("3b6fd1")


## A canvas [param SIZE] pixels square showing [param rects]
static func canvas(rects: Array[Rect2i]) -> PackedByteArray:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for rect in rects:
		img.fill_rect(rect, COLOR)
	return img.get_data()


## The middle of [param points]
static func middle_of(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / points.size()


func test_the_outline_goes_round_the_shape() -> void:
	var shape := ShapeBlend.shape_of(canvas([Rect2i(10, 10, 12, 8)]), SIZE, SIZE)
	var outline := ShapeBlend.outline_of(shape, SIZE, SIZE, 0)
	assert_true(outline.size() >= 24, "spaced along it")
	for point in outline:
		var inside := Rect2(9, 9, 14, 10).has_point(point)
		var deep := Rect2(11, 11, 10, 6).has_point(point)
		assert_true(inside and not deep, "on the outline: %s" % point)
	assert_true(absf(middle_of(outline).x - 16.0) <= 0.5, str(middle_of(outline).x))
	assert_true(absf(middle_of(outline).y - 14.0) <= 0.5, str(middle_of(outline).y))


func test_holes_are_filled_and_only_the_biggest_part_kept() -> void:
	var data := canvas([Rect2i(10, 10, 10, 10), Rect2i(30, 30, 2, 2)])
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	img.fill_rect(Rect2i(13, 13, 3, 3), Color(0, 0, 0, 0))
	var shape := ShapeBlend.shape_of(img.get_data(), SIZE, SIZE)
	assert_eq(shape[14 * SIZE + 14], 1, "the hole is filled")
	assert_eq(shape[30 * SIZE + 30], 0, "the small part isn't the shape")
	assert_eq(shape[10 * SIZE + 10], 1)


func test_the_same_shape_stays() -> void:
	var data := canvas([Rect2i(12, 8, 6, 24)])
	var blend := ShapeBlend.between(data, data, SIZE, SIZE, Vector2.ZERO, 24.0)
	var halfway := blend.at(0.5)
	for i in blend.rest.size():
		assert_true(halfway[i].distance_to(blend.rest[i]) < 0.6, "corner %d stays" % i)


func test_moving_moves_the_whole_shape() -> void:
	var a := canvas([Rect2i(8, 8, 6, 20)])
	var b := canvas([Rect2i(16, 10, 6, 20)])
	var blend := ShapeBlend.between(a, b, SIZE, SIZE, Vector2(8, 2), 22.0)
	var moved := middle_of(blend.at(0.5)) - middle_of(blend.rest)
	assert_true(absf(moved.x - 4.0) <= 0.5, str(moved.x))
	assert_true(absf(moved.y - 1.0) <= 0.5, str(moved.y))


func test_a_bar_bends_part_of_the_way() -> void:
	# Upright, then its top half bent over to the right
	var a := canvas([Rect2i(10, 6, 4, 28)])
	var b := canvas([Rect2i(10, 20, 4, 14), Rect2i(10, 20, 18, 4)])
	var blend := ShapeBlend.between(a, b, SIZE, SIZE, Vector2.ZERO, 28.0)
	# The corner at the bar's top end
	var top := 0
	for i in blend.rest.size():
		if blend.rest[i].y < blend.rest[top].y:
			top = i
	var halfway := blend.at(0.5)[top]
	var bent := blend.target[top]
	assert_true(bent.x > 22.0, "bent all the way: %s" % bent)
	assert_true(halfway.x > 14.0 and halfway.x < bent.x - 2.0, "partway across: %s" % halfway)
	assert_true(halfway.y > 8.0 and halfway.y < 22.0, "partway down: %s" % halfway)
	# Its foot stays
	var foot := 0
	for i in blend.rest.size():
		if blend.rest[i].y > blend.rest[foot].y:
			foot = i
	assert_true(blend.at(0.5)[foot].distance_to(blend.rest[foot]) < 1.5, "the foot stays")


func test_sources_cover_the_shape() -> void:
	var data := canvas([Rect2i(12, 8, 6, 24)])
	var blend := ShapeBlend.between(data, data, SIZE, SIZE, Vector2.ZERO, 24.0)
	var sources := blend.sources(0.0, false)
	for y in range(9, 31):
		for x in range(13, 17):
			var source := sources[y * SIZE + x]
			assert_true(source.distance_to(Vector2(x + 0.5, y + 0.5)) < 0.01, "shows itself")
	assert_true(sources[2 * SIZE + 2].x < 0.0, "nothing outside")
	var bigger := blend.sources(0.0, false, 2)
	assert_eq(bigger.size(), SIZE * SIZE * 4)
	assert_true(bigger[(20 * 2) * SIZE * 2 + 14 * 2].x >= 0.0)


func test_an_empty_key_has_no_blend() -> void:
	var data := canvas([Rect2i(12, 8, 6, 24)])
	assert_eq(ShapeBlend.between(data, canvas([]), SIZE, SIZE, Vector2.ZERO, 24.0), null)
