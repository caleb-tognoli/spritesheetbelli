extends "res://tests/test_case.gd"

var sheet: Spritesheet


func before_each() -> void:
	sheet = Spritesheet.new()


func test_first_frame_goes_to_origin() -> void:
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	assert_eq(sheet.grid_size, Vector2i(1, 1))
	assert_eq(sheet.sprite_size, Vector2i(16, 16))
	assert_true(sheet.frames.has(Vector2i.ZERO))


func test_single_row_fills_gaps_then_grows() -> void:
	sheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	sheet.frames.erase(Vector2i(1, 0))
	sheet.add_frames([make_image(Color.WHITE)] as Array[Image])
	assert_true(sheet.frames.has(Vector2i(1, 0)), "gap filled")
	sheet.add_frames([make_image(Color.WHITE)] as Array[Image])
	assert_eq(sheet.grid_size, Vector2i(4, 1), "grows horizontally")


func test_frames_are_padded_to_sprite_size() -> void:
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(8, 8)), make_image(Color.BLUE, Vector2i(16, 12))]
			as Array[Image]
		)
	)
	assert_eq(sheet.sprite_size, Vector2i(16, 12))
	for img: Image in sheet.frames.values():
		assert_eq(img.get_size(), Vector2i(16, 12))


func test_locked_spaces_are_skipped() -> void:
	sheet.grid_size = Vector2i(3, 2)
	sheet.locked_coordinates.append(Vector2i(0, 0))
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	assert_true(sheet.frames.has(Vector2i(1, 0)))


func test_shrinking_grid_removes_outside_frames() -> void:
	sheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	sheet.grid_size = Vector2i(2, 1)
	assert_eq(sheet.frames.size(), 2)


func test_get_image_places_frames() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	var img := sheet.get_image()
	assert_eq(img.get_size(), Vector2i(32, 16))
	assert_color(img, Vector2i(20, 5), Color.BLUE)


func test_guess_grid_size() -> void:
	assert_eq(AddSpritesheetWindow.guess_grid_size(Vector2i(96, 64)), Vector2i(3, 2))
