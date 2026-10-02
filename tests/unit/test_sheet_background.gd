extends "res://tests/test_case.gd"

const MAGENTA := Color("#ff00ff")

var window: AddSpritesheetWindow


func before_each() -> void:
	Global.document.reset()
	# Remembered between runs, so each test starts from the default
	Settings.set_value(&"background_tolerance", SheetBackground.DEFAULT_TOLERANCE)
	window = load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	add_child(window)


func after_each() -> void:
	window.queue_free()
	Global.document.reset()


## 4 × 2 sprites of 12 px on magenta, 1 px apart and 1 px from the edges: 53×27
static func magenta_sheet() -> Image:
	var img := Image.create_empty(53, 27, false, Image.FORMAT_RGBA8)
	img.fill(MAGENTA)
	for row in 2:
		for column in 4:
			var sprite := Rect2i(Vector2i(1, 1) + Vector2i(column, row) * 13, Vector2i(12, 12))
			img.fill_rect(sprite, Color.RED)
			img.fill_rect(Rect2i(sprite.position + Vector2i(2, 2), Vector2i(2, 2)), Color.BLUE)
	return img


#region Detecting


func test_an_opaque_sheet_with_a_uniform_border_has_a_background() -> void:
	assert_eq(SheetBackground.detect(magenta_sheet()), MAGENTA)
	var rgb := magenta_sheet()
	rgb.convert(Image.FORMAT_RGB8)
	assert_eq(SheetBackground.detect(rgb), MAGENTA, "no alpha at all")


func test_a_transparent_sheet_has_none() -> void:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(4, 4, 8, 8), Color.RED)
	assert_eq(SheetBackground.detect(img), null)
	# Mostly transparent, even with an opaque frame around it
	img.fill_rect(Rect2i(0, 0, 32, 1), MAGENTA)
	img.fill_rect(Rect2i(0, 31, 32, 1), MAGENTA)
	img.fill_rect(Rect2i(0, 0, 1, 32), MAGENTA)
	img.fill_rect(Rect2i(31, 0, 1, 32), MAGENTA)
	assert_eq(SheetBackground.detect(img), null, "an opaque border")


func test_an_image_of_one_colour_has_none() -> void:
	assert_eq(SheetBackground.detect(make_image(Color.RED, Vector2i(32, 16))), null)


func test_a_few_transparent_pixels_are_fine() -> void:
	var img := magenta_sheet()
	# 5 of 1431 pixels see-through, like a soft shadow
	for x in 5:
		img.set_pixel(2 + x, 10, Color(0, 0, 0, 0.5))
	assert_eq(SheetBackground.detect(img), MAGENTA)
	img.fill_rect(Rect2i(1, 1, 12, 12), Color.TRANSPARENT)
	assert_eq(SheetBackground.detect(img), null, "a whole transparent sprite is too many")


func test_a_noisy_border_has_none() -> void:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, Color8((x * 37 + y * 91) % 256, (x * 11) % 256, (y * 53) % 256))
	assert_eq(SheetBackground.detect(img), null)


func test_slight_noise_on_the_border_is_still_one_colour() -> void:
	var img := magenta_sheet()
	# Like after JPEG compression
	for x in range(0, 53, 3):
		img.set_pixel(x, 0, Color8(253, 1, 254))
	assert_eq(SheetBackground.detect(img), MAGENTA, "the most common colour")


## Corners with the same colour but other colours along the edges are art that fills the
## image, like a tileset or a scene with a sky, which keying would cut holes in: the whole
## border decides, not the corners
func test_agreeing_corners_alone_are_not_a_background() -> void:
	var img := make_image(Color.SKY_BLUE, Vector2i(40, 40))
	var stripes: Array[Color] = [Color.DARK_GREEN, Color.SADDLE_BROWN, Color.GOLD, Color.GRAY]
	for i in stripes.size():
		img.fill_rect(Rect2i(i * 10, 0, 10, 40), stripes[i])
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(38, 0), Vector2i(0, 38), Vector2i(38, 38)]:
		img.fill_rect(Rect2i(corner, Vector2i(2, 2)), Color.SKY_BLUE)
	assert_eq(SheetBackground.detect(img), null)


func test_a_sprite_over_a_corner_leaves_the_background() -> void:
	var img := magenta_sheet()
	img.fill_rect(Rect2i(0, 0, 6, 6), Color.RED)
	assert_eq(SheetBackground.detect(img), MAGENTA)


#endregion

#region Removing


func test_removing_keeps_other_colours() -> void:
	var img := magenta_sheet()
	img.set_pixel(0, 0, Color8(250, 10, 245))
	var keyed := SheetBackground.remove(img, MAGENTA)
	assert_eq(keyed.get_pixel(0, 0).a, 0.0, "close enough")
	assert_eq(keyed.get_pixel(1, 1), Color.RED)
	assert_eq(img.get_pixel(0, 0).a, 1.0, "the original is left alone")
	assert_eq(SheetBackground.remove(img, MAGENTA, 0.0).get_pixel(0, 0).a, 1.0, "exactly")


func test_big_images_are_keyed_the_same_on_threads() -> void:
	var img := Image.create_empty(640, 480, false, Image.FORMAT_RGBA8)
	for y in 480:
		img.fill_rect(Rect2i(0, y, 640, 1), Color8(y % 256, 0, 255 - y % 256))
	assert_true(img.get_width() * img.get_height() >= ImageUtils.THREADED_PIXELS)
	var keyed := SheetBackground.remove(img, Color8(100, 0, 155), 0.05)
	var max_distance := (0.05 * 255.0) ** 2 * 3.0
	for y in 480:
		var shade := y % 256
		var distance := (shade - 100) ** 2 + (255 - shade - 155) ** 2
		var alpha := 0.0 if distance <= max_distance else 1.0
		for x: int in [0, 321, 639]:
			assert_eq(keyed.get_pixel(x, y).a, alpha, "%d, %d" % [x, y])
	# In bands of rows, while the main thread goes on
	var in_bands := await SheetBackground.remove_async(img, Color8(100, 0, 155), 0.05)
	assert_eq(in_bands.get_size(), img.get_size())
	assert_eq(in_bands.get_data(), keyed.get_data(), "the same pixels")
	var small := magenta_sheet()
	var small_keyed := await SheetBackground.remove_async(small, MAGENTA)
	assert_eq(small_keyed.get_data(), SheetBackground.remove(small, MAGENTA).get_data())
	assert_eq(small.get_pixel(0, 0), MAGENTA, "the image is left alone")


func test_the_grid_is_guessed_from_the_gaps_of_the_background() -> void:
	var img := magenta_sheet()
	assert_eq(GridGuesser.guess(img), Vector2i.ONE, "no transparent gaps")
	assert_eq(GridGuesser.guess(SheetBackground.remove(img, MAGENTA)), Vector2i(4, 2))


func test_sprites_are_found_once_the_background_is_removed() -> void:
	var img := magenta_sheet()
	assert_eq(SpriteDetector.detect(img), [[Rect2i(0, 0, 53, 27)]], "one big sprite")
	var rows := SpriteDetector.detect(SheetBackground.remove(img, MAGENTA))
	assert_eq(rows.size(), 2)
	assert_eq(rows[1].size(), 4)
	assert_eq(rows[1][0], Rect2i(1, 14, 12, 12))


#endregion

#region Import


func assert_clean(sheet: Spritesheet, message: String) -> void:
	for coord in sheet.frames:
		var img: Image = sheet.frames[coord]
		for y in img.get_height():
			for x in img.get_width():
				var color := img.get_pixel(x, y)
				if color.a > 0 and color.is_equal_approx(MAGENTA):
					fail("%s: magenta at %d, %d of %s" % [message, x, y, coord])
					return


func test_the_import_makes_the_background_transparent() -> void:
	window.setup(magenta_sheet())
	assert_true(window.background.is_on(), "on when found")
	assert_eq(window.background.get_color(), MAGENTA)
	assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.GRID)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2), "guessed from the gaps")
	assert_eq(window.spritesheet.frames.size(), 8)
	assert_clean(window.spritesheet, "grid")
	assert_color(window.spritesheet.frames[Vector2i(1, 1)], Vector2i(1, 1), Color.RED)
	assert_eq(window.source_image.get_pixel(0, 0), MAGENTA, "the opened image is kept")

	window.set_cut(AddSpritesheetWindow.Cut.DETECT)
	assert_eq(window.spritesheet.frames.size(), 8)
	assert_eq(window.spritesheet.frames[Vector2i(0, 0)].get_size(), Vector2i(12, 12))
	assert_clean(window.spritesheet, "found sprites")

	window.set_cut(AddSpritesheetWindow.Cut.GRID)
	window.add_spritesheet_to_global()
	assert_eq(Global.spritesheet.frames.size(), 8)
	assert_clean(Global.spritesheet, "added")


func test_the_import_can_be_prepared_on_worker_threads() -> void:
	var img := magenta_sheet()
	var tolerance: float = Settings.get_value(&"background_tolerance")
	var prepared := await AddSpritesheetWindow.prepare(img, "", null, "", tolerance)
	window.setup(img, "", null, "", prepared)
	assert_true(window.spritesheet_image == prepared.keyed[0], "the keyed image is taken")
	assert_true(window.background.is_on())
	assert_eq(window.background.get_color(), MAGENTA)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2))
	assert_clean(window.spritesheet, "grid")

	# Keyed differently than prepared, like with another tolerance: keyed again
	Settings.set_value(&"background_tolerance", 0.5)
	window.setup(img, "", null, "", prepared)
	assert_false(window.spritesheet_image == prepared.keyed[0], "keyed again")
	assert_eq(window.background.get_tolerance(), 0.5)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2))
	assert_clean(window.spritesheet, "keyed again")


## Waits for the background to be previewed, keyed on worker threads
func settle() -> void:
	for i in 5:
		await get_tree().process_frame


func test_turning_it_off_keeps_the_background() -> void:
	window.setup(magenta_sheet())
	window.background.open()
	window.background.enabled_check.button_pressed = false
	assert_clean(window.spritesheet, "previewed at the frame's end")
	await settle()
	assert_eq(window.spritesheet.frames[Vector2i.ZERO].get_pixel(0, 0), MAGENTA, "previewed")
	assert_false(window.background.tolerance_field.editable)
	window.background.confirm()
	assert_eq(window.spritesheet.frames[Vector2i.ZERO].get_pixel(0, 0), MAGENTA)
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2), "no gaps to guess from, so kept")

	# A grid set by hand stays
	window.update_grid_size(2, 1)
	window.background.open()
	window.background.enabled_check.button_pressed = true
	window.background.confirm()
	assert_eq(window.spritesheet.grid_size, Vector2i(2, 1), "set by hand")
	assert_clean(window.spritesheet, "on again")


func test_the_tolerance_takes_more_colours() -> void:
	var img := magenta_sheet()
	# A gap a little off the background colour, which hides the gap from the grid guess
	img.fill_rect(Rect2i(13, 1, 1, 12), Color8(220, 35, 220))
	window.setup(img)
	window.update_grid_size(4, 2)
	var second := window.spritesheet.frames[Vector2i(1, 0)] as Image
	assert_eq(second.get_pixel(0, 1).a, 1.0, "not within 10%")
	window.background.open()
	window.background.tolerance_field.value = 20
	window.background.tolerance_field.value = 15
	await settle()
	second = window.spritesheet.frames[Vector2i(1, 0)]
	assert_eq(second.get_pixel(0, 1).a, 0.0, "previewed within 15%")
	window.background.confirm()
	second = window.spritesheet.frames[Vector2i(1, 0)]
	assert_eq(second.get_pixel(0, 1).a, 0.0, "within 15%")


func test_transparent_sheets_can_have_a_colour_removed_by_hand() -> void:
	var img := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	for column in 4:
		img.fill_rect(Rect2i(column * 16 + 2, 2, 12, 12), Color.RED)
		img.fill_rect(Rect2i(column * 16 + 2, 18, 12, 12), Color.GREEN)
	window.setup(img)
	assert_false(window.background.is_on(), "nothing to remove")
	assert_true(window.background.visible, "but still there")
	assert_eq(window.spritesheet.frames.size(), 8)

	var preview := window.preview_area.spritesheet_preview
	window.background.open()
	window.background.set_picking(true)
	assert_true(preview.picking)
	preview.color_picked.emit(Color.TRANSPARENT)
	assert_true(window.background.is_picking(), "nothing to pick on a transparent pixel")
	preview.color_picked.emit(Color.GREEN)
	assert_false(preview.picking, "picked")
	assert_true(window.background.is_open(), "still open")
	assert_true(window.background.is_on())
	assert_eq(window.background.get_color(), Color.GREEN)
	await settle()
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 2), "the grid is guessed on Confirm")
	window.background.confirm()
	assert_eq(window.spritesheet.frames.size(), 4, "the green sprites are gone")
	assert_eq(window.spritesheet.grid_size, Vector2i(4, 1), "guessed again")


func test_the_eyedropper_picks_from_the_preview() -> void:
	window.setup(magenta_sheet())
	var preview := window.preview_area.spritesheet_preview
	# Headless windows have no size, so the preview is given one
	window.preview_area.container.stretch = false
	(preview.get_viewport() as SubViewport).size = Vector2i(600, 400)
	preview.fit_to_view()
	window.background.open()
	window.background.set_picking(true)
	# The blue eye of the second sprite
	var target := preview.get_frame_world_rect(Vector2i(1, 0)).position + Vector2(3.5, 3.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (target - preview.camera.position) * preview.camera.zoom
	preview._unhandled_input(click)
	assert_eq(window.background.get_color(), Color.BLUE)
	assert_false(window.background.is_picking())
	assert_true(window.background.is_open(), "stays open")
	assert_true(preview.get_selected_coords().is_empty(), "picking doesn't select")
	window.background.cancel()


func test_cancel_puts_the_background_back() -> void:
	window.setup(magenta_sheet())
	window.update_grid_size(2, 2)
	var frames := window.spritesheet.frames.duplicate()
	var cut_image := window.spritesheet_image
	for close: Callable in [
		func() -> void: window.background.cancel_button.pressed.emit(),
		func() -> void:
			var escape := InputEventAction.new()
			escape.action = &"ui_cancel"
			escape.pressed = true
			window.background._input(escape),
		func() -> void:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = window.preview_area.container.get_global_rect().get_center()
			window.background._input(click),
	]:
		window.background.open()
		window.background.swatch.color = Color.RED
		window.background.enabled_check.button_pressed = false
		window.background.tolerance_field.value = 40
		await settle()
		assert_eq(window.spritesheet_image, window.source_image, "previewed without it")
		close.call()
		assert_false(window.background.is_open())
		assert_true(window.background.is_on(), "on again")
		assert_eq(window.background.get_color(), MAGENTA)
		assert_eq(window.background.get_tolerance(), SheetBackground.DEFAULT_TOLERANCE)
		assert_eq(window.spritesheet_image, cut_image, "the image as it was")
		assert_eq(window.spritesheet.grid_size, Vector2i(2, 2))
		assert_eq(window.spritesheet.frames.size(), frames.size())
		assert_clean(window.spritesheet, "cut as it was")
		await settle()
		assert_eq(window.spritesheet_image, cut_image, "nothing keyed late")
	assert_eq(Settings.get_value(&"background_tolerance"), 0.1, "not remembered")


func test_changes_are_previewed_once_a_frame_and_cut_on_confirm() -> void:
	window.setup(magenta_sheet())
	window.set_cut(AddSpritesheetWindow.Cut.DETECT)
	var boxes := window.box_editor.get_boxes()
	window.background.open()
	var passes := window.background_passes
	# Like dragging in the colour picker
	for i in 20:
		window.background.set_key(true, Color(1, 0, 1 - i * 0.002), 0.1)
		window.background.changed.emit()
	await settle()
	assert_eq(window.background_passes, passes + 1, "one keying pass")
	assert_eq(window.spritesheet_image.get_pixel(0, 0).a, 0.0, "previewed")
	assert_eq(window.box_editor.view.image, window.spritesheet_image, "shown under the boxes")
	assert_eq(window.box_editor.get_boxes(), boxes, "not found again while it changes")
	window.background.set_key(false, MAGENTA, 0.1)
	window.background.changed.emit()
	await settle()
	assert_eq(window.box_editor.view.image, window.source_image)
	window.background.confirm()
	assert_eq(window.box_editor.get_boxes().size(), 1, "found again: one big sprite")


func test_reloading_removes_the_background_again() -> void:
	var dir := temp_path("background")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("magenta.png")
	magenta_sheet().save_png(path)
	window.setup(magenta_sheet(), path)
	window.background.open()
	window.background.tolerance_field.value = 5
	window.background.confirm()
	var source: Dictionary = window.spritesheet.frame_sources[Vector2i(1, 0)]
	assert_eq(source.key, {"color": "ff00ff", "tolerance": 0.05})
	assert_eq(Settings.get_value(&"background_tolerance"), 0.05, "remembered")
	window.setup(magenta_sheet(), path)
	assert_eq(window.background.get_tolerance(), 0.05, "starts with the last tolerance")
	var saved := FrameSource.from_json(FrameSource.to_json(source, dir), dir)
	assert_eq(saved, source, "kept in projects")

	# The sheet changes on disk: the magenta around the sprite is still removed
	var changed := magenta_sheet()
	changed.fill_rect(Rect2i(14, 1, 12, 12), Color.YELLOW)
	changed.save_png(path)
	var key := FrameSource.get_load_key(source)
	var pixels := FrameSource.cut(source, {key: FrameSource.load_key(key)})
	assert_eq(pixels.get_pixel(0, 0).a, 0.0, "the gap is transparent")
	assert_color(pixels, Vector2i(1, 1), Color.YELLOW)

	# Without the background removed, sources don't say so
	window.background.open()
	window.background.enabled_check.button_pressed = false
	window.background.confirm()
	assert_false(window.spritesheet.frame_sources[Vector2i.ZERO].has("key"))


func test_the_background_button_is_in_every_cut() -> void:
	var frame := {"frame": {"x": 1, "y": 1, "w": 12, "h": 12}}
	var data := SheetData.parse_json(JSON.stringify({"frames": {"0": frame}}))
	window.setup(magenta_sheet(), "", data, "sheet.json")
	for cut: AddSpritesheetWindow.Cut in [
		AddSpritesheetWindow.Cut.GRID,
		AddSpritesheetWindow.Cut.DETECT,
		AddSpritesheetWindow.Cut.DATA
	]:
		window.set_cut(cut)
		# The window itself isn't shown in tests
		var shown := true
		for node: Node in [window.background, window.background.get_parent()]:
			shown = shown and (node as Control).visible
		assert_true(shown, "in cut %d" % cut)
	assert_true(window.background.shows_color, "shows the colour while on")
	assert_true(window.background.enabled_check.visible, "can be turned off")
	# Escape in the window closes the panel, not the window
	window.background.open()
	var closed := [false]
	window.canceled.connect(func() -> void: closed[0] = true)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	window.window_input.emit(escape)
	assert_false(closed[0], "the window stays")
	window.background.cancel()

#endregion
