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
	sheet.remove_frames([Vector2i(1, 0)] as Array[Vector2i])
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
	for coord in sheet.frames:
		assert_eq(sheet.get_cell_image(coord).get_size(), Vector2i(16, 12))
	assert_eq(sheet.frames[Vector2i(0, 0)].get_size(), Vector2i(8, 8), "stored unpadded")


func test_locked_spaces_are_skipped() -> void:
	sheet.set_grid_size(Vector2i(3, 2))
	sheet.set_locked(Vector2i(0, 0), true)
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	assert_true(sheet.frames.has(Vector2i(1, 0)))


func test_shrinking_grid_removes_outside_frames() -> void:
	sheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	sheet.set_grid_size(Vector2i(2, 1))
	assert_eq(sheet.frames.size(), 2)


func test_get_image_places_frames() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	var img := sheet.get_image()
	assert_eq(img.get_size(), Vector2i(32, 16))
	assert_color(img, Vector2i(20, 5), Color.BLUE)


func test_rotating_back_restores_sprite_size() -> void:
	sheet.add_frames(
		[make_image(Color.RED, Vector2i(16, 32)), make_image(Color.BLUE)] as Array[Image]
	)
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	sheet.rotate_frames(coords, true)
	assert_eq(sheet.sprite_size, Vector2i(32, 16))
	sheet.rotate_frames(coords, false)
	assert_eq(sheet.sprite_size, Vector2i(16, 32))


func test_one_update_per_operation() -> void:
	var count := [0]
	sheet.updated.connect(func() -> void: count[0] += 1)
	var imgs: Array[Image] = []
	for i in 20:
		imgs.append(make_image(Color.RED))
	sheet.add_frames(imgs)
	assert_eq(count[0], 1)


func test_edits_never_modify_images_in_place() -> void:
	var img := make_image(Color.RED)
	img.set_pixel(0, 0, Color.BLUE)
	sheet.add_frames([img] as Array[Image])
	var state := sheet.get_state()
	sheet.flip_frames([Vector2i.ZERO] as Array[Vector2i], true)
	assert_color(img, Vector2i.ZERO, Color.BLUE, "original untouched")
	sheet.set_state(state)
	assert_color(sheet.frames[Vector2i.ZERO], Vector2i.ZERO, Color.BLUE, "state restored")


func test_resize_is_lossless() -> void:
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	sheet.resize_sprites(Vector2i(4, 4))
	assert_eq(sheet.sprite_size, Vector2i(4, 4))
	sheet.resize_sprites(Vector2i(64, 64))
	assert_eq(sheet.sprite_size, Vector2i(64, 64))
	assert_eq(sheet.frames[Vector2i.ZERO].get_size(), Vector2i(16, 16), "source kept")


func test_move_frames_swaps() -> void:
	sheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	sheet.move_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(2, 0))
	assert_color(sheet.frames[Vector2i(2, 0)], Vector2i.ZERO, Color.RED)
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.BLUE)


func test_insert_and_remove_cell() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.GREEN)] as Array[Image])
	sheet.set_grid_size(Vector2i(2, 1))
	sheet.insert_empty_cell(Vector2i(0, 0))
	assert_false(sheet.has_frame(Vector2i(0, 0)))
	assert_color(sheet.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.RED)
	assert_color(sheet.frames[Vector2i(0, 1)], Vector2i.ZERO, Color.GREEN, "wraps to next row")
	sheet.remove_cell(Vector2i(0, 0))
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(sheet.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.GREEN)


func test_trim_and_color_key() -> void:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(4, 4, 4, 6), Color.RED)
	sheet.add_frames([img, make_image(Color.MAGENTA)] as Array[Image])
	sheet.trim_frames([Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(sheet.frames[Vector2i(0, 0)].get_size(), Vector2i(4, 6))
	sheet.color_key_frames([Vector2i(1, 0)] as Array[Vector2i], Color.MAGENTA)
	assert_true(sheet.frames[Vector2i(1, 0)].is_invisible())


func test_exported_sprites_are_named_by_grid_index() -> void:
	var dir := OS.get_user_data_dir().path_join("tests/export_order")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	sheet.set_grid_size(Vector2i(3, 1))
	sheet.set_frame(Vector2i(2, 0), make_image(Color.BLUE))
	sheet.set_frame(Vector2i(0, 0), make_image(Color.RED))
	var written := SpritesheetExporter.export_sprites(sheet, dir)
	assert_eq(written.size(), 2)
	assert_color(Image.load_from_file(dir.path_join("0.png")), Vector2i.ZERO, Color.RED)
	assert_color(Image.load_from_file(dir.path_join("2.png")), Vector2i.ZERO, Color.BLUE)


func test_jpg_export_fills_transparency() -> void:
	var path := OS.get_user_data_dir().path_join("tests/transparent.jpg")
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 8, 16), Color.BLUE)
	assert_eq(SpritesheetExporter.save_image(img, path), OK)
	var saved := Image.load_from_file(path)
	assert_true(saved.get_pixel(12, 8).r > 0.9, "transparent half is white, not black")
	assert_eq(SpritesheetExporter.with_image_extension("a/b"), "a/b.png")
	assert_eq(SpritesheetExporter.with_image_extension("a/b.JPEG"), "a/b.JPEG")


func test_frame_names_survive_edits_and_projects() -> void:
	var img := make_image(Color.RED)
	img.resource_name = "walk_01.png"
	sheet.add_frames([img] as Array[Image])
	var coords: Array[Vector2i] = [Vector2i.ZERO]
	sheet.flip_frames(coords, true)
	sheet.trim_frames(coords)
	assert_eq(sheet.frames[Vector2i.ZERO].resource_name, "walk_01.png")
	var path := OS.get_user_data_dir().path_join("tests/names.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	var loaded: Dictionary = ProjectFile.load(path)
	assert_eq(loaded.state.frames[Vector2i.ZERO].resource_name, "walk_01.png")


func test_undoing_a_resize_reuses_scaled_images() -> void:
	sheet.add_frames([make_image(Color.RED, Vector2i(8, 8))] as Array[Image])
	sheet.set_frame_scale(Vector2(2, 2))
	var scaled := sheet.get_frame_image(Vector2i.ZERO)
	var state := sheet.get_state()
	sheet.set_frame_scale(Vector2.ONE)
	sheet.set_state(state)
	assert_true(sheet.get_frame_image(Vector2i.ZERO) == scaled)
	sheet.flip_frames([Vector2i.ZERO] as Array[Vector2i], true)
	assert_false(sheet.is_frame_scaled(Vector2i.ZERO), "an edited frame is scaled again")


func test_prepare_scaled_images() -> void:
	var imgs: Array[Image] = []
	for i in 4:
		imgs.append(make_image(Color.RED, Vector2i(10, 6)))
	sheet.add_frames(imgs)
	sheet.set_frame_scale(Vector2(3, 3), Image.INTERPOLATE_BILINEAR)
	assert_false(sheet.is_frame_scaled(Vector2i.ZERO))
	assert_true(sheet.get_pending_scale_work() > 0)
	assert_eq(
		sheet.get_frame_rect_in_cell(Vector2i(1, 0)).size, Vector2i(30, 18), "no scaling needed"
	)
	assert_false(sheet.is_frame_scaled(Vector2i(1, 0)))
	await sheet.prepare_scaled_images()
	assert_true(sheet.is_frame_scaled(Vector2i(3, 0)))
	assert_eq(sheet.get_pending_scale_work(), 0)
	assert_eq(sheet.get_frame_image(Vector2i(2, 0)).get_size(), Vector2i(30, 18))


func test_animations_follow_their_frames() -> void:
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		imgs.append(make_image(color))
	sheet.add_frames(imgs)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var index := sheet.add_animation(SheetAnimation.create("walk", cells, 8))
	assert_eq(sheet.animations[index].name, "walk")
	sheet.move_frames([Vector2i(1, 0)] as Array[Vector2i], Vector2i(0, 1))
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 0)] as Array[Vector2i],
		"a moved frame keeps its place in the animation"
	)
	sheet.remove_cell(Vector2i(0, 0))
	assert_eq(sheet.animations[0].cells.size(), 2, "a removed cell leaves the animation")
	var state := sheet.get_state()
	sheet.remove_animation(0)
	assert_true(sheet.animations.is_empty())
	sheet.set_state(state)
	assert_eq(sheet.animations.size(), 1, "undoable")
	assert_eq(sheet.get_unique_animation_name("walk"), "walk2")


func test_ping_pong_playback() -> void:
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		imgs.append(make_image(color))
	sheet.add_frames(imgs)
	var animation := SheetAnimation.create("a", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	animation.mode = SheetAnimation.Mode.PING_PONG
	assert_eq(
		animation.get_playback_cells(sheet),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i]
	)


func test_frame_numbers() -> void:
	assert_eq(SheetAnimation.parse_numbers("0-3, 5 9-7").numbers, [0, 1, 2, 3, 5, 9, 8, 7])
	assert_eq(SheetAnimation.parse_numbers("2,x").error, "x")
	assert_eq(SheetAnimation.parse_numbers("1-2-3").error, "1-2-3")
	assert_eq(SheetAnimation.format_numbers([0, 1, 2, 3, 5, 9, 8, 7] as Array[int]), "0-3, 5, 9-7")
	assert_eq(
		SheetAnimation.format_numbers([4, 5, 7] as Array[int]), "4, 5, 7", "two in a row stay apart"
	)


func test_insert_remove_and_move_rows() -> void:
	sheet.set_grid_size(Vector2i(2, 3))
	for y in 3:
		sheet.set_frame(Vector2i(0, y), make_image(Color(y / 3.0, 0, 0)))
		sheet.set_row_name(y, "row%d" % y)
	var bottom := sheet.frames[Vector2i(0, 2)]
	sheet.set_locked(Vector2i(1, 2), true)
	sheet.nudge_frames([Vector2i(0, 2)] as Array[Vector2i], Vector2i(1, 0))
	sheet.add_animation(SheetAnimation.create("a", [Vector2i(0, 1), Vector2i(0, 2)]))

	sheet.insert_row(1)
	assert_eq(sheet.grid_size, Vector2i(2, 4))
	assert_eq(sheet.frames[Vector2i(0, 3)], bottom)
	assert_true(sheet.has_frame_origin(Vector2i(0, 3)), "origin moved along")
	assert_true(sheet.is_locked(Vector2i(1, 3)), "lock moved along")
	assert_eq(sheet.row_names, {0: "row0", 2: "row1", 3: "row2"} as Dictionary[int, String])
	assert_eq(sheet.animations[0].cells, [Vector2i(0, 2), Vector2i(0, 3)] as Array[Vector2i])

	sheet.move_row(3, -3)
	assert_eq(sheet.frames[Vector2i(0, 0)], bottom)
	assert_eq(sheet.row_names.get(0), "row2")
	assert_eq(sheet.row_names.get(3), "row0")
	sheet.move_row(0, -1)
	assert_eq(sheet.frames[Vector2i(0, 0)], bottom, "can't move out of the grid")

	sheet.remove_row(2)
	assert_eq(sheet.grid_size, Vector2i(2, 3))
	assert_eq(
		sheet.animations[0].cells, [Vector2i(0, 0)] as Array[Vector2i], "removed cell dropped"
	)
	assert_eq(sheet.row_names, {0: "row2", 2: "row0"} as Dictionary[int, String])
