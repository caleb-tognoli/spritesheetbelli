extends "res://tests/test_case.gd"


## A transparent sheet with a small opaque square in the middle of every cell
func make_sheet(grid: Vector2i, cell: Vector2i, margin := 2) -> Image:
	var img := Image.create_empty(grid.x * cell.x, grid.y * cell.y, false, Image.FORMAT_RGBA8)
	for y in grid.y:
		for x in grid.x:
			var rect := Rect2i(
				Vector2i(x, y) * cell + Vector2i.ONE * margin, cell - Vector2i.ONE * margin * 2
			)
			img.fill_rect(rect, Color.RED)
	return img


func test_file_name_sprite_size() -> void:
	assert_eq(GridGuesser.guess_from_file_name("hero_32x32.png", Vector2i(256, 64)), Vector2i(8, 2))


func test_file_name_grid_counts() -> void:
	assert_eq(GridGuesser.guess_from_file_name("walk_8x2.png", Vector2i(128, 32)), Vector2i(8, 2))


func test_file_name_strip() -> void:
	assert_eq(GridGuesser.guess_from_file_name("run_strip6.png", Vector2i(96, 16)), Vector2i(6, 1))


func test_file_name_that_does_not_fit_is_ignored() -> void:
	assert_eq(GridGuesser.guess_from_file_name("hero_30x30.png", Vector2i(64, 64)), Vector2i.ZERO)
	assert_eq(GridGuesser.guess_from_file_name("hero.png", Vector2i(64, 64)), Vector2i.ZERO)


func test_gaps_between_sprites() -> void:
	# 8×2 of 16 px: the old GCD guess said 4×1
	assert_eq(GridGuesser.guess(make_sheet(Vector2i(8, 2), Vector2i(16, 16))), Vector2i(8, 2))
	assert_eq(GridGuesser.guess(make_sheet(Vector2i(5, 3), Vector2i(24, 40))), Vector2i(5, 3))


func test_uneven_gaps_fall_back_to_common_sizes() -> void:
	var img := Image.create_empty(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	assert_eq(GridGuesser.guess(img), Vector2i(2, 1), "largest common size (64)")


func test_single_image_is_one_cell() -> void:
	var img := Image.create_empty(37, 23, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	assert_eq(GridGuesser.guess(img), Vector2i.ONE)
