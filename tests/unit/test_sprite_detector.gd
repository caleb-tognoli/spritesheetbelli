extends "res://tests/test_case.gd"


## Two rows of blocks of different sizes, not in a grid
static func packed_sheet() -> Image:
	var img := Image.create_empty(64, 48, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(30, 2, 8, 12), Color.GREEN)
	img.fill_rect(Rect2i(2, 4, 10, 10), Color.RED)
	img.fill_rect(Rect2i(50, 3, 6, 9), Color.BLUE)
	img.fill_rect(Rect2i(4, 26, 12, 16), Color.WHITE)
	img.fill_rect(Rect2i(24, 30, 6, 12), Color.YELLOW)
	return img


func test_finds_sprites_in_rows() -> void:
	var rows := SpriteDetector.detect(packed_sheet())
	assert_eq(rows.size(), 2)
	assert_eq(rows[0], [Rect2i(2, 4, 10, 10), Rect2i(30, 2, 8, 12), Rect2i(50, 3, 6, 9)])
	assert_eq(rows[1], [Rect2i(4, 26, 12, 16), Rect2i(24, 30, 6, 12)])


func test_joins_close_parts_and_ignores_dust() -> void:
	var img := Image.create_empty(48, 24, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 8, 16), Color.RED)
	img.fill_rect(Rect2i(13, 4, 3, 3), Color.RED)  # A spark 3 pixels away
	img.fill_rect(Rect2i(30, 2, 8, 16), Color.RED)
	img.set_pixel(45, 20, Color.RED)  # Dust
	assert_eq(SpriteDetector.detect(img).size(), 1)
	assert_eq(SpriteDetector.detect(img)[0].size(), 3, "spark on its own")
	var joined := SpriteDetector.detect(img, 4)
	assert_eq(joined[0], [Rect2i(2, 2, 14, 16), Rect2i(30, 2, 8, 16)])


func test_parts_inside_a_sprite_belong_to_it() -> void:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 20, 20), Color.RED)
	img.fill_rect(Rect2i(6, 6, 12, 12), Color.TRANSPARENT)
	img.fill_rect(Rect2i(10, 10, 3, 3), Color.BLUE)
	var rows := SpriteDetector.detect(img)
	assert_eq(rows, [[Rect2i(2, 2, 20, 20)]])


func test_opaque_background_is_removed() -> void:
	var img := packed_sheet()
	var keyed := Image.create_empty(64, 48, false, Image.FORMAT_RGBA8)
	keyed.fill(Color.MAGENTA)
	keyed.blend_rect(img, Rect2i(0, 0, 64, 48), Vector2i.ZERO)
	var rows := SpriteDetector.detect(keyed)
	assert_eq(rows.size(), 2)
	var sheet := SpriteDetector.to_spritesheet(keyed, rows)
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_eq(sheet.get_cell_image(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0, "background gone")


func test_spritesheet_keeps_rows_and_aligns() -> void:
	var img := packed_sheet()
	var sheet := SpriteDetector.to_spritesheet(
		img, SpriteDetector.detect(img), Spritesheet.Alignment.BOTTOM
	)
	assert_eq(sheet.grid_size, Vector2i(3, 2))
	assert_eq(sheet.frames[Vector2i(1, 0)].get_size(), Vector2i(8, 12))
	assert_eq(sheet.sprite_size, Vector2i(12, 16))
	# Bottoms on one line
	for coord in sheet.frames:
		assert_eq(sheet.get_frame_rect_in_cell(coord).end.y, 16, str(coord))


func test_add_spritesheet_window_finds_sprites() -> void:
	var window: AddSpritesheetWindow = (
		load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	)
	add_child(window)
	window.setup(packed_sheet())
	window.align_option.select(1)
	window.set_cut(AddSpritesheetWindow.Cut.DETECT)
	assert_eq(window.spritesheet.frames.size(), 5)
	assert_true(window.spritesheet.has_frame_origin(Vector2i(0, 0)), "aligned to the bottom")
	window.queue_free()
