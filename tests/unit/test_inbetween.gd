extends "res://tests/test_case.gd"


## A transparent image of [param size] with [param rects] filled in [param colors]
static func draw(size: Vector2i, rects: Array[Rect2i], colors: Array[Color]) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for i in rects.size():
		img.fill_rect(rects[i], colors[i])
	return img


static func key(img: Image, origin := Vector2i.ZERO) -> Dictionary:
	return {"image": img, "origin": origin}


## The colours of the pixels shown in [param img]
static func colors_in(img: Image) -> Dictionary:
	var colors := {}
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.a > 0:
				colors[color.to_html()] = true
	return colors


func test_motion_is_detected() -> void:
	# An L shape, so only one movement lines it up
	var rects: Array[Rect2i] = [Rect2i(2, 2, 2, 6), Rect2i(4, 6, 3, 2)]
	var colors: Array[Color] = [Color.RED, Color.YELLOW]
	var moved: Array[Rect2i] = [Rect2i(8, 4, 2, 6), Rect2i(10, 8, 3, 2)]
	var a := key(draw(Vector2i(16, 16), rects, colors), Vector2i(-8, -8))
	var b := key(draw(Vector2i(16, 16), moved, colors), Vector2i(-8, -8))
	assert_eq(SpriteMotion.detect(a, b), Vector2i(6, 2))
	assert_eq(SpriteMotion.detect(b, a), Vector2i(-6, -2))
	# The same sprite in a frame of another size, placed elsewhere
	var c := key(draw(Vector2i(20, 12), moved, colors), Vector2i(-3, -8))
	assert_eq(SpriteMotion.detect(a, c), Vector2i(11, 2))


func test_motion_detection_without_pixels() -> void:
	var a := key(Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	var b := key(make_image(Color.RED, Vector2i(4, 4)))
	assert_eq(SpriteMotion.detect(a, b), Vector2i.ZERO)


func test_a_movement_given_is_used_even_when_zero() -> void:
	var a := key(make_image(Color.RED, Vector2i(2, 2)))
	var b := key(make_image(Color.RED, Vector2i(2, 2)), Vector2i(8, 0))
	assert_eq(InBetween.prepare(a, b).shift, Vector2(8, 0), "found when not given")
	assert_eq(InBetween.prepare(a, b, Vector2i(3, 0)).shift, Vector2(3, 0))
	assert_eq(InBetween.prepare(a, b, Vector2i.ZERO).shift, Vector2.ZERO, "not moving at all")


func test_in_betweens_are_evenly_spaced() -> void:
	var a := key(make_image(Color.RED, Vector2i(2, 2)))
	var b := key(make_image(Color.RED, Vector2i(2, 2)), Vector2i(8, 0))
	var motion := SpriteMotion.detect(a, b)
	assert_eq(motion, Vector2i(8, 0))
	var frames := InBetween.generate(a, b, 3, motion)
	var origins := frames.map(func(frame: Dictionary) -> Vector2i: return frame.origin)
	assert_eq(origins, [Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)])


func test_names_and_pivots() -> void:
	var a_img := make_image(Color.RED, Vector2i(4, 4))
	a_img.resource_name = "walk_01.png"
	var a := key(a_img)
	a.pivot = Vector2(2, 4)
	var b := key(make_image(Color.RED, Vector2i(4, 4)), Vector2i(4, 0))
	var frames := InBetween.generate(a, b, 2, Vector2i(4, 0))
	assert_eq((frames[0].image as Image).resource_name, "walk_01_inbetween1")
	assert_eq((frames[1].image as Image).resource_name, "walk_01_inbetween2")
	# From (2, 4) to the middle of the second key, (6, 2), where they're placed
	assert_eq(frames[0].pivot, Vector2(2, 4).lerp(Vector2(6, 2), 1.0 / 3) - Vector2(1, 0))
	var unnamed := InBetween.generate(b, b, 1)
	assert_eq((unnamed[0].image as Image).resource_name, "inbetween1")
	assert_false(unnamed[0].has("pivot"), "only when a key has one")


func test_insert_between_both_ways() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var other := Vector2i(5, 5)
	var animation := SheetAnimation.create("walk", [a, b, other, b, a] as Array[Vector2i])
	animation.mode = SheetAnimation.Mode.ONCE
	animation.durations = [1.0, 2.0, 1.0, 1.0, 3.0] as Array[float]
	assert_eq(animation.count_between(a, b), 2)
	var new_cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	assert_eq(animation.insert_between(a, b, new_cells), 2)
	assert_eq(
		animation.cells,
		[a, Vector2i(0, 1), Vector2i(1, 1), b, other, b, Vector2i(1, 1), Vector2i(0, 1), a]
	)
	assert_eq(animation.durations, [1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 3.0])


func test_insert_between_around_a_loop() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var new_cell: Array[Vector2i] = [Vector2i(2, 0)]
	var loop := SheetAnimation.create("idle", [a, b] as Array[Vector2i])
	assert_eq(loop.count_between(a, b), 2, "and back from the last to the first")
	loop.insert_between(a, b, new_cell)
	assert_eq(loop.cells, [a, Vector2i(2, 0), b, Vector2i(2, 0)])
	var ping_pong := SheetAnimation.create("idle", [b, Vector2i(3, 3), a] as Array[Vector2i])
	ping_pong.mode = SheetAnimation.Mode.PING_PONG
	assert_eq(ping_pong.count_between(a, b), 0, "ping-pong turns back instead")
	assert_eq(ping_pong.insert_between(a, b, new_cell), 0)
	assert_eq(ping_pong.cells.size(), 3)
	assert_eq(loop.count_between(a, a), 0)


func test_add_after_the_first_key() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	sheet.add_animation(SheetAnimation.create("walk", cells))
	var back := SheetAnimation.create("back", [cells[1], cells[0]] as Array[Vector2i])
	back.mode = SheetAnimation.Mode.ONCE
	sheet.add_animation(back)
	var frames := InBetween.generate(
		InBetween.key_of(sheet, cells[0]), InBetween.key_of(sheet, cells[1]), 2
	)
	var coords := InBetween.add(
		sheet, cells[0], cells[1], frames, InBetween.Place.AFTER_FIRST, true
	)
	assert_eq(coords, [Vector2i(1, 0), Vector2i(2, 0)])
	# Like Insert Empty Cell, later frames move along in reading order, onto the next row
	assert_color(sheet.frames[Vector2i(0, 1)], Vector2i.ZERO, Color.GREEN, "moved along")
	assert_color(sheet.frames[Vector2i(1, 1)], Vector2i.ZERO, Color.BLUE)
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]
	)
	assert_eq(
		sheet.animations[1].cells, [Vector2i(0, 1), Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0)]
	)


func test_add_elsewhere_without_animations() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	sheet.add_animation(SheetAnimation.create("walk", cells))
	var frames := InBetween.generate(
		InBetween.key_of(sheet, cells[0]), InBetween.key_of(sheet, cells[1]), 1
	)
	var coords := InBetween.add(sheet, cells[0], cells[1], frames, InBetween.Place.NEW_ROW, false)
	assert_eq(coords, [Vector2i(0, 1)])
	assert_eq(sheet.animations[0].cells, cells, "left alone")
	coords = InBetween.add(sheet, cells[1], cells[0], frames, InBetween.Place.APPEND, true)
	assert_eq(coords, [Vector2i(1, 1)])
	assert_eq(sheet.animations[0].cells, [cells[0], Vector2i(1, 1), cells[1], Vector2i(1, 1)])


## The colour [param frame] (from InBetween.generate) shows where [param position] is placed
static func pixel_at(frame: Dictionary, position: Vector2i) -> Color:
	var img: Image = frame.image
	var local: Vector2i = position - frame.origin
	if not Rect2i(Vector2i.ZERO, img.get_size()).has_point(local):
		return Color(0, 0, 0, 0)
	return img.get_pixelv(local)


func test_spacing() -> void:
	assert_eq(InBetween.time_of(0, 1), 0.5)
	assert_eq(InBetween.time_of(1, 3), 0.5)
	assert_eq(InBetween.time_of(0, 1, InBetween.Spacing.EASE_IN), 0.25, "near the first key")
	assert_eq(InBetween.time_of(0, 1, InBetween.Spacing.EASE_OUT), 0.75, "near the second")
	assert_eq(InBetween.time_of(1, 3, InBetween.Spacing.EASE_IN_OUT), 0.5)
	assert_eq(InBetween.time_of(0, 3, InBetween.Spacing.EASE_IN_OUT), 0.125)
	assert_eq(InBetween.time_of(2, 3, InBetween.Spacing.EASE_IN_OUT), 0.875)
	var a := key(make_image(Color.RED, Vector2i(2, 2)))
	var b := key(make_image(Color.RED, Vector2i(2, 2)), Vector2i(16, 0))
	var frames := InBetween.generate(a, b, 1, Vector2i(16, 0), InBetween.Spacing.EASE_IN)
	assert_eq(frames[0].origin, Vector2i(4, 0), "a quarter of the way")


func test_insert_between_keeping_the_length() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var animation := SheetAnimation.create("walk", [a, b] as Array[Vector2i])
	animation.mode = SheetAnimation.Mode.ONCE
	animation.durations = [2.0, 1.0] as Array[float]
	animation.insert_between(a, b, [Vector2i(2, 0)] as Array[Vector2i], true)
	assert_eq(animation.durations, [1.0, 1.0, 1.0], "the first key's time, shared")
	var thirds := SheetAnimation.create("walk", [a, b] as Array[Vector2i])
	thirds.mode = SheetAnimation.Mode.ONCE
	thirds.insert_between(a, b, [Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i], true)
	assert_eq(thirds.durations, [0.34, 0.33, 0.33, 1.0], "adding up to what it was")
