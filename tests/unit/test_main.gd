extends "res://tests/test_case.gd"

var main: Control
var dir := temp_path()


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


func save_images(colors: Dictionary) -> void:
	for file_name: String in colors:
		make_image(colors[file_name]).save_png(dir.path_join(file_name))


func test_added_sprites_are_sorted_and_deduplicated() -> void:
	save_images({"f1.png": Color.RED, "f2.png": Color.GREEN, "f10.png": Color.BLUE})
	await main.files.add_sprites_from_paths(
		PackedStringArray(
			[
				dir.path_join("f10.png"),
				dir.path_join("f2.png"),
				dir.path_join("f1.png"),
				dir.path_join("f1.png")
			]
		)
	)
	var frames: Dictionary = Global.spritesheet.frames
	assert_eq(frames.size(), 3)
	assert_color(frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(frames[Vector2i(1, 0)], Vector2i.ZERO, Color.GREEN)
	assert_color(frames[Vector2i(2, 0)], Vector2i.ZERO, Color.BLUE)


func test_file_dialog_opens_once() -> void:
	main.files.popup_file_dialog(main.files.open_sprites_dialog)
	main.files.popup_file_dialog(main.files.open_sprites_dialog)
	assert_eq(main.files.open_file_dialogs.size(), 1)
	main.files.open_sprites_dialog.canceled.emit()
	assert_true(main.files.open_file_dialogs.is_empty(), "canceled releases the dialog")
	main.files.open_sprites_dialog.hide()


func test_zoom_keeps_point_under_cursor() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	var preview: SpritesheetPreview = main.preview_area.spritesheet_preview
	var anchor := Vector2(100, 80)
	var before := preview.screen_to_world(anchor)
	preview.set_zoom(4, anchor)
	assert_eq(preview.screen_to_world(anchor), before)
	assert_true(preview.is_index_visible(), "index visible when a cell is 64px on screen")
	preview.set_zoom(1)
	assert_false(preview.is_index_visible(), "index hidden when a cell is 16px on screen")


func test_add_spritesheet_keeps_empty_rows() -> void:
	var img := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)
	img.fill_rect(Rect2i(32, 32, 16, 16), Color.BLUE)
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.setup(img)
	window.update_grid_size(3, 3)
	window.add_spritesheet_to_global()
	var frames: Dictionary = Global.spritesheet.frames
	assert_color(frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(frames[Vector2i(2, 2)], Vector2i.ZERO, Color.BLUE)
	assert_eq(Global.spritesheet.grid_size, Vector2i(3, 3))


func test_export_appends_png_extension() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	var path := dir.path_join("sheet_no_ext")
	await main.files.exports.export_to(path)
	assert_true(FileAccess.file_exists(path + ".png"))
	assert_eq(Global.document.export_path, path + ".png", "Ctrl+E exports here next time")
	Notify.message_dialog.hide()


func test_the_export_format_adds_its_extension() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	var options := ExportOptions.from_sheet(Global.spritesheet)
	options.image_format = "jpg"
	Global.spritesheet.set_export_settings(options.to_dictionary())
	var typed := dir.path_join("format.png")
	var written := typed + ".jpg"
	DirAccess.remove_absolute(typed)
	DirAccess.remove_absolute(written)
	assert_true(await main.files.exports.export_to(typed))
	assert_true(FileAccess.file_exists(written), "a JPG, the PNG's extension part of its name")
	assert_false(FileAccess.file_exists(typed))
	assert_eq(Global.document.export_path, written)
	assert_eq(ExportController.suggested_path(options), written)

	# A target of another format since: the same name, format.png
	var target := ExportTarget.create(Global.spritesheet, options.to_dictionary())
	target.path = written
	target.options.image_format = "webp"
	options.image_format = "webp"
	assert_eq(ExportController.suggested_path(options), typed + ".webp")
	assert_eq(ExportController.get_output_path(target), typed + ".webp")
	DirAccess.remove_absolute(typed + ".webp")
	var targets: Array[ExportTarget] = [target]
	assert_true(await main.files.exports.export_targets(targets))
	assert_true(FileAccess.file_exists(typed + ".webp"), "again, as WebP")

	# Typed with the format's extension, in any case or spelling: written as typed
	options.image_format = "jpg"
	Global.spritesheet.set_export_settings(options.to_dictionary())
	var jpeg := dir.path_join("FORMAT.JPEG")
	DirAccess.remove_absolute(jpeg)
	assert_true(await main.files.exports.export_to(jpeg))
	assert_true(FileAccess.file_exists(jpeg))
	assert_eq(ExportController.suggested_path(options), jpeg)
	target.path = jpeg
	target.options.image_format = "jpg"
	assert_eq(ExportController.get_output_path(target), jpeg, "the same file again")
	for path: String in [written, typed + ".webp", jpeg]:
		DirAccess.remove_absolute(path)


func test_save_and_open_project() -> void:
	Global.document.perform(
		"Add",
		func() -> void:
			Global.spritesheet.add_frames(
				[make_image(Color.RED), make_image(Color.BLUE, Vector2i(8, 16))] as Array[Image]
			)
			Global.spritesheet.set_grid_size(Vector2i(3, 2))
			Global.spritesheet.set_locked(Vector2i(2, 1), true)
			Global.spritesheet.resize_sprites(Vector2i(32, 32))
			var saved := SheetAnimation.create("jump", [Vector2i(1, 0)] as Array[Vector2i], 7.5)
			saved.mode = SheetAnimation.Mode.PING_PONG
			Global.spritesheet.add_animation(saved)
	)
	var path := dir.path_join("project")
	assert_true(await main.files.save_project(path))
	assert_eq(Global.document.path, path + ".sbelli")
	assert_false(Global.document.is_dirty)
	Notify.message_dialog.hide()

	Global.document.reset()
	assert_true(await main.files.open_project(path + ".sbelli"))
	var sheet := Global.spritesheet
	assert_eq(sheet.grid_size, Vector2i(3, 2))
	assert_eq(sheet.frames[Vector2i(1, 0)].get_size(), Vector2i(8, 16), "original size kept")
	assert_eq(sheet.sprite_size, Vector2i(32, 32), "scale kept")
	assert_true(sheet.is_locked(Vector2i(2, 1)))
	var jump := sheet.animations[0]
	assert_eq([jump.name, jump.cells, jump.fps], ["jump", [Vector2i(1, 0)], 7.5], "animations kept")
	assert_eq(jump.mode, SheetAnimation.Mode.PING_PONG)
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_false(Global.document.can_undo())


func test_opening_a_document_clears_the_selection() -> void:
	var preview: SpritesheetPreview = main.preview
	var images: Array[Image] = []
	for i in 6:
		images.append(make_image(Color.from_hsv(i / 6.0, 1, 1)))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(images))
	var first := dir.path_join("first.sbelli")
	assert_true(await main.files.save_project(first))
	Notify.message_dialog.hide()
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(images.slice(0, 1)))
	var second := dir.path_join("second.sbelli")
	assert_true(await main.files.save_project(second))
	Notify.message_dialog.hide()
	var image := dir.path_join("opened.png")
	make_image(Color.RED, Vector2i(64, 16)).save_png(image)

	var select_five := func() -> void:
		var five := Global.spritesheet.get_sorted_coords().slice(0, 5)
		preview.set_selected_coords(five)
		preview._anchor = five[-1]
		assert_eq(preview.get_selected_coords().size(), 5)
		assert_true(main.sheet_info.text.contains("5 selected"))
	var check := func(what: String) -> void:
		assert_true(preview.get_selected_coords().is_empty(), what)
		assert_eq(preview._anchor, SpritesheetPreview.NO_CELL, what + ": no range start")
		assert_false(main.sheet_info.text.contains("selected"), what + ": status bar")

	select_five.call()
	assert_true(await main.files.open_project(first))
	check.call("the same project")
	select_five.call()
	assert_true(await main.files.open_project(second))
	check.call("another project")
	select_five.call()
	main.files.set_filepath_when_opening_spritesheet = true
	await main.files.show_add_spritesheet_window(image)
	main.files.add_spritesheet_window.add_spritesheet_to_global()
	check.call("an image")
	assert_true(await main.files.open_project(second))
	select_five.call()
	main.files.new_spritesheet()
	check.call("New")

	# Undo and redo keep the selection
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(images))
	var moved := Global.spritesheet.get_sorted_coords().slice(0, 2)
	preview.set_selected_coords(moved)
	preview.move_requested.emit(moved, Vector2i(0, 5), false)
	moved = preview.get_selected_coords()
	assert_eq(moved[0].y, 5, "moved, and the selection with them")
	Actions.run(&"flip_h")
	Global.document.undo()
	assert_eq(preview.get_selected_coords(), moved, "kept by undo")
	Global.document.redo()
	assert_eq(preview.get_selected_coords(), moved, "and redo")


func test_opening_invalid_project_shows_error() -> void:
	var path := dir.path_join("broken.sbelli")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a zip")
	f.close()
	assert_false(await main.files.open_project(path))
	assert_true(Notify.message_dialog.visible)
	Notify.message_dialog.hide()


func test_confirmation_runs_latest_action_once() -> void:
	var calls := [0]
	Notify.confirm("t", "t", func() -> void: calls[0] += 1)
	Notify.confirm_dialog.canceled.emit()
	Notify.confirm("t", "t", func() -> void: calls[0] += 10)
	Notify.confirm_dialog.confirmed.emit()
	Notify.confirm_dialog.confirmed.emit()
	assert_eq(calls[0], 10)
	Notify.confirm_dialog.hide()


func test_canceling_open_keeps_spritesheet() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	Global.document.mark_saved()
	main.files.open_spritesheet()
	assert_true(main.files.open_dialog in main.files.open_file_dialogs, "open dialog shown")
	main.files.open_dialog.canceled.emit()
	assert_eq(Global.spritesheet.frames.size(), 1)
	main.files.open_dialog.hide()


func test_new_clears_everything() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	Global.document.path = "x.png"
	Global.document.mark_saved()
	main.files.new_spritesheet()
	assert_true(Global.spritesheet.is_empty())
	assert_eq(Global.document.path, "")


func test_clearing_grid_field_keeps_previous_value() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	await get_tree().process_frame
	var field: SpinBox = main.grid_columns
	var line_edit := field.get_line_edit()
	line_edit.text = ""
	line_edit.text_submitted.emit("")
	field.apply()
	assert_eq(Global.spritesheet.frames.size(), 2, "no sprites deleted")
	assert_eq(int(field.value), 2)


func test_grid_spinbox_arrows_add_columns() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	main.grid_columns.value += 1
	assert_eq(Global.spritesheet.grid_size, Vector2i(2, 1))


func test_add_spritesheet_only_locks_its_own_cells() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED), make_image(Color.GREEN)] as Array[Image])
	Global.spritesheet.remove_frames([Vector2i(0, 0)] as Array[Vector2i])
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.BLUE)
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.setup(img)
	window.update_grid_size(2, 1)
	window.add_spritesheet_to_global()
	assert_false(Global.spritesheet.is_locked(Vector2i(0, 0)), "old gap stays free")
	assert_true(Global.spritesheet.is_locked(Vector2i(1, 1)), "new sheet's empty cell locked")


func test_add_spritesheet_can_leave_empty_cells_free() -> void:
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.BLUE)
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.setup(img)
	window.update_grid_size(2, 1)
	assert_true(window.lock_empty_cells.button_pressed, "on by default")
	assert_true(window.lock_empty_cells.visible, "the sheet has an empty cell")
	window.lock_empty_cells.button_pressed = false
	assert_false(Settings.get_value(&"lock_empty_cells"), "remembered")
	window.add_spritesheet_to_global()
	assert_false(Global.spritesheet.is_locked(Vector2i(1, 0)), "empty cell stays free")

	window.setup(make_image(Color.RED, Vector2i(32, 16)))
	window.update_grid_size(2, 1)
	assert_false(window.lock_empty_cells.button_pressed, "unchecked the next time")
	assert_false(window.lock_empty_cells.visible, "no empty cells to lock")
	Settings.set_value(&"lock_empty_cells", true)


func test_add_sheet_locks_empty_cells_when_asked() -> void:
	var sheet := Spritesheet.new()
	sheet.set_grid_size(Vector2i(2, 2))
	sheet.set_frame(Vector2i(0, 0), make_image(Color.RED))
	for lock_empty: bool in [true, false]:
		var target := Spritesheet.new()
		target.add_frames([make_image(Color.GREEN)] as Array[Image])
		AddSpritesheetWindow.add_sheet(target, sheet, lock_empty)
		assert_eq(target.frames.size(), 2, "added below the frames")
		var locked: Array[Vector2i] = []
		if lock_empty:
			locked = [Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)]
		assert_eq(target.locked_coordinates, locked, "lock empty: %s" % lock_empty)


func test_opening_a_file_is_not_an_unsaved_change() -> void:
	var path := dir.path_join("open_me.png")
	make_image(Color.RED, Vector2i(32, 16)).save_png(path)
	main.files.set_filepath_when_opening_spritesheet = true
	await main.files.show_add_spritesheet_window(path)
	main.files.add_spritesheet_window.add_spritesheet_to_global()
	assert_false(Global.spritesheet.is_empty())
	assert_false(Global.document.is_dirty)
	assert_eq(Global.document.export_path, path, "exports back to the opened image")
	assert_eq(Global.document.path, "", "not saved as a project yet")
	assert_false(Global.document.can_undo(), "opening can't be undone")
	await get_tree().process_frame
	Actions.run(&"select_all")
	Actions.run(&"flip_h")
	assert_true(Global.document.is_dirty, "later edits are changes")


func test_keep_ratio_resize_rounds() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED, Vector2i(32, 24))] as Array[Image])
	main.sprite_width.value = 33
	assert_eq(Global.spritesheet.sprite_size, Vector2i(33, 25))
	main.keep_ratio_btn.button_pressed = false
	main.sprite_height.value = 10
	assert_eq(Global.spritesheet.sprite_size, Vector2i(33, 10))


func test_linked_size_keeps_a_stretch() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED, Vector2i(32, 24))] as Array[Image])
	main.keep_ratio_btn.button_pressed = false
	main.sprite_height.value = 48
	main.keep_ratio_btn.button_pressed = true
	main.sprite_width.value = 64
	assert_eq(Global.spritesheet.sprite_size, Vector2i(64, 96), "the stretch is kept")
	main.sprite_height.value = 48
	assert_eq(Global.spritesheet.sprite_size, Vector2i(32, 48))


func test_selecting_is_in_the_menu_not_the_toolbar() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	await get_tree().process_frame
	assert_false("select_all_btn" in main.preview_area)
	assert_false(main.preview_area._action_buttons.has(&"select_all"))
	Actions.run(&"select_all")
	assert_eq(main.preview.get_selected_coords().size(), 1)
	Actions.run(&"select_none")
	assert_true(main.preview.get_selected_coords().is_empty())


func test_closing_with_unsaved_changes_asks_first() -> void:
	var quits := [0]
	main.files.confirm_unsaved_changes("closing", func() -> void: quits[0] += 1)
	assert_eq(quits[0], 1, "nothing to save: closes right away")

	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	main.files.confirm_unsaved_changes("closing", func() -> void: quits[0] += 1)
	assert_true(main.files.unsaved_changes_dialog.visible, "asks")
	assert_eq(quits[0], 1)
	main.files.unsaved_changes_dialog.custom_action.emit(&"discard")
	assert_eq(quits[0], 2, "Don't Save closes")

	Global.document.path = dir.path_join("close_save.sbelli")
	main.files.confirm_unsaved_changes("closing", func() -> void: quits[0] += 1)
	main.files.unsaved_changes_dialog.confirmed.emit()
	assert_eq(quits[0], 3, "Save saves, then closes")
	assert_false(Global.document.is_dirty)
	assert_true(FileAccess.file_exists(dir.path_join("close_save.sbelli")))


func test_dropping_files() -> void:
	var folder := dir.path_join("drop_folder")
	DirAccess.make_dir_recursive_absolute(folder)
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	make_image(Color.RED).save_png(folder.path_join("a2.png"))
	make_image(Color.BLUE).save_png(folder.path_join("a10.png"))
	var note := FileAccess.open(folder.path_join("notes.txt"), FileAccess.WRITE)
	note.close()

	await main.files.open_dropped_files(PackedStringArray([folder]))
	assert_eq(Global.spritesheet.frames.size(), 2, "folder: images only")
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "a2 first")

	await main.files.open_dropped_files(PackedStringArray([folder.path_join("a2.png")]))
	assert_true(main.files.add_spritesheet_window.visible, "one image opens Add Spritesheet")
	main.files.add_spritesheet_window.hide()


func test_quick_scale_buttons_and_filter() -> void:
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	main.double_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.sprite_size, Vector2i(32, 32))
	main.half_size_btn.pressed.emit()
	main.half_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.sprite_size, Vector2i(8, 8))
	main.resize_filter.item_selected.emit(Image.INTERPOLATE_CUBIC)
	assert_eq(Global.spritesheet.scale_filter, Image.INTERPOLATE_CUBIC)
	main.double_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.scale_filter, Image.INTERPOLATE_CUBIC, "keeps the sheet's filter")
	main.original_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.sprite_size, Vector2i(16, 16))


func test_add_spritesheet_offset_spacing_and_warning() -> void:
	var img := Image.create_empty(2 + 16 + 4 + 16 + 1, 18, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 16, 16), Color.RED)
	img.fill_rect(Rect2i(22, 2, 16, 16), Color.BLUE)
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.setup(img)
	window.update_grid_size(2, 1)
	window.offset_x.value = 2
	window.offset_y.value = 2
	window.spacing_x.value = 4
	assert_eq(window.spritesheet.sprite_size, Vector2i(16, 16))
	assert_color(window.spritesheet.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.BLUE)
	var notice := window.preview_area.notice_label.text
	assert_true(window.preview_area.notice.visible, "over the preview")
	assert_eq(window.preview_area.notice.anchor_bottom, 1.0, "at the bottom right")
	assert_eq(window.preview_area.notice.anchor_right, 1.0)
	assert_true(notice.contains("1 px on the right"), notice)
	assert_false(window.slice_info.text.contains("not used"), "not in the bar")
	window.spacing_x.value = 3
	assert_false(window.preview_area.notice.visible, "the grid fits now")


func test_empty_hint_and_toasts() -> void:
	assert_true(main.preview_area.empty_hint.visible, "hint while empty")
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	await get_tree().process_frame
	assert_false(main.preview_area.empty_hint.visible)
	await main.files.exports.export_to(dir.path_join("toast.png"))
	assert_true(Notify.get_toasts()[-1].begins_with("Exported toast.png"))


func test_zoom_buttons() -> void:
	var area: PreviewArea = main.preview_area
	Settings.set_value(&"pixel_perfect_zoom", "off")
	main.preview.set_zoom(1)
	area.zoom_in_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "125%")
	area.zoom_out_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "100%")
	Settings.set_value(&"pixel_perfect_zoom", "auto")
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	area.center_view_btn.pressed.emit()
	assert_true(main.preview.camera.zoom.x > 4.0, "fits the view")
	area.zoom_label_btn.pressed.emit()
	assert_eq(main.preview.camera.zoom.x, 1.0, "the percentage is 100%")
	assert_false(area.zoom_in_btn.get_parent() is HFlowContainer, "not in the toolbar")
	var corner := area.zoom_in_btn.get_global_rect().end.x
	assert_true(corner > area.stage.get_global_rect().end.x - 20, "top right of the preview")


func test_pixel_perfect_zoom() -> void:
	var area: PreviewArea = main.preview_area
	var preview: SpritesheetPreview = main.preview
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	assert_eq(Global.spritesheet.scale_filter, Image.INTERPOLATE_NEAREST)
	preview.set_zoom(1)
	area.zoom_in_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "200%", "Auto with Nearest steps by whole zooms")
	area.zoom_out_btn.pressed.emit()
	area.zoom_out_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "50%")
	area.center_view_btn.pressed.emit()
	var zoom := preview.camera.zoom.x
	assert_eq(zoom, roundf(zoom), "fits at a whole zoom")

	preview.set_zoom(3)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.5
	preview._unhandled_input(wheel)
	assert_eq(preview.camera.zoom.x, 3.0, "half a notch doesn't zoom yet")
	preview._unhandled_input(wheel)
	assert_eq(preview.camera.zoom.x, 4.0, "a whole notch goes a whole zoom")

	Global.spritesheet.set_frame_scale(Vector2.ONE, Image.INTERPOLATE_BILINEAR)
	preview.set_zoom(1)
	area.zoom_in_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "125%", "Auto is off when the filter smooths")
	Settings.set_value(&"pixel_perfect_zoom", "on")
	area.zoom_in_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "200%")
	Settings.set_value(&"pixel_perfect_zoom", "auto")


func test_pixel_perfect_zoom_with_the_interface_scaled() -> void:
	var area: PreviewArea = main.preview_area
	var preview: SpritesheetPreview = main.preview
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	Settings.set_value(&"pixel_perfect_zoom", "on")
	Settings.set_value(&"ui_scale", 1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(absf(PixelZoom.screen_scale(preview) - 1.5) < 0.0001)
	var viewport := preview.get_viewport() as SubViewport
	assert_eq(
		Vector2(viewport.size),
		Vector2(viewport.size_2d_override) * 1.5,
		"stretched by exactly the interface's scale"
	)
	preview.set_zoom(1)
	var labels: Array[String] = []
	for i in 3:
		area.zoom_in_btn.pressed.emit()
		labels.append(area.zoom_label_btn.text)
	assert_eq(labels, ["133%", "200%", "267%"] as Array[String], "2, 3, 4 screen pixels")
	labels.clear()
	for i in 3:
		area.zoom_out_btn.pressed.emit()
		labels.append(area.zoom_label_btn.text)
	assert_eq(labels, ["200%", "133%", "67%"] as Array[String], "and back")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1
	preview._unhandled_input(wheel)
	assert_eq(area.zoom_label_btn.text, "133%", "the wheel too")

	preview.set_zoom(3)
	area.zoom_label_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "133%", "100% is the nearest, 2 screen pixels")
	preview.set_zoom(3)
	Actions.run(&"zoom_reset")
	assert_eq(area.zoom_label_btn.text, "133%")

	area.center_view_btn.pressed.emit()
	var zoom := preview.camera.zoom.x
	assert_true(absf(zoom * 1.5 - roundf(zoom * 1.5)) < 0.0001, "fits at whole screen pixels")
	var shown := Vector2(Global.spritesheet.sprite_size) * zoom
	var view := preview.get_viewport_rect().size
	assert_true(shown.x <= view.x and shown.y <= view.y, "fits")
	area.zoom_in_btn.pressed.emit()
	shown = Vector2(Global.spritesheet.sprite_size) * preview.camera.zoom.x
	assert_true(shown.x > view.x - 80 or shown.y > view.y - 80, "the biggest that fits")

	Settings.set_value(&"ui_scale", 2.0)
	await get_tree().process_frame
	preview.set_zoom(1)
	area.zoom_in_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "200%", "at 200%, as at 100%")
	area.zoom_label_btn.pressed.emit()
	assert_eq(area.zoom_label_btn.text, "100%")
	Settings.set_value(&"ui_scale", Settings.DEFAULTS[&"ui_scale"])
	Settings.set_value(&"pixel_perfect_zoom", "auto")


func test_formatted_text_is_translatable() -> void:
	var german := Translation.new()
	german.locale = "de"
	german.add_message("%d frames · %d×%d grid · %d×%d px", "%d Frames · %d×%d Raster · %d×%d px")
	TranslationServer.add_translation(german)
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	main.update_sheet_info()
	var text: String = main.sheet_info.text
	TranslationServer.set_locale(previous)
	TranslationServer.remove_translation(german)
	assert_eq(text, "1 Frames · 1×1 Raster · 16×16 px")


func test_view_fits_when_first_frames_appear() -> void:
	main.preview.set_zoom(1)
	var imgs: Array[Image] = []
	for i in 3:
		imgs.append(make_image(Color.RED))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	await get_tree().process_frame
	assert_true(main.preview.camera.zoom.x > 2.0, "zoomed to fit 48×16 px")
	main.preview.set_zoom(1)
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.BLUE)] as Array[Image])
	)
	await get_tree().process_frame
	assert_eq(main.preview.camera.zoom.x, 1.0, "later additions keep the view")


func test_opened_sheet_shows_whole_and_new_one_100_percent() -> void:
	var imgs: Array[Image] = []
	for i in 3:
		imgs.append(make_image(Color.RED))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	await get_tree().process_frame
	main.preview.set_zoom(7.32)
	Global.document.load_state(Global.spritesheet.get_state(), dir.path_join("other.sbelli"))
	await get_tree().process_frame
	var opened: Dictionary = main.preview.get_view()
	main.preview.fit_to_view()
	assert_eq(opened, main.preview.get_view(), "a sheet without a saved view is fitted")
	assert_ne(opened.zoom, 7.32)
	Global.document.reset()
	await get_tree().process_frame
	assert_eq(main.preview.camera.zoom.x, 1.0, "a new sheet is shown at 100%")


func test_view_is_saved_with_the_project() -> void:
	var imgs: Array[Image] = []
	for i in 3:
		imgs.append(make_image(Color.RED))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	await get_tree().process_frame
	main.preview.set_zoom(5)
	main.preview.camera.position = Vector2(3, 7)
	var saved: Dictionary = main.preview.get_view()
	var path := dir.path_join("view.sbelli")
	assert_true(await main.files.save_project(path))
	Notify.message_dialog.hide()
	main.preview.set_zoom(2)
	assert_false(Global.document.is_dirty, "the view isn't an unsaved change")

	Global.document.reset()
	await get_tree().process_frame
	assert_true(await main.files.open_project(path))
	await get_tree().process_frame
	var view: Dictionary = main.preview.get_view()
	assert_eq(view.zoom, 5.0)
	assert_true(view.centre.is_equal_approx(saved.centre), "centred where it was saved")


func test_view_json() -> void:
	var view := {"centre": Vector2(12.5, -3), "zoom": 2.0}
	var json: Variant = JSON.parse_string(JSON.stringify(FileController.view_to_json(view)))
	assert_eq(FileController.view_from_json(json), view)
	assert_eq(FileController.view_from_json(null), {})
	assert_eq(FileController.view_from_json({"centre": [1, 2], "zoom": 0}), {}, "no zoom")
	assert_eq(FileController.view_from_json({"centre": "1, 2", "zoom": 2}), {})
	assert_eq(FileController.view_to_json({}), {})


func test_ctrl_scroll_steps_fields_and_triple_size() -> void:
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	main.grid_columns.gui_input.emit(wheel)
	assert_eq(Global.spritesheet.grid_size.x, 2, "Ctrl+wheel adds a column")
	main.triple_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.sprite_size, Vector2i(48, 48))


func test_too_big_sprites_show_an_error() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED, Vector2i(6000, 10))] as Array[Image])
	main.triple_size_btn.pressed.emit()
	assert_eq(Global.spritesheet.sprite_size, Vector2i(6000, 10), "not resized")
	assert_true(Notify.message_dialog.visible, "explains why")
	Notify.message_dialog.hide()


func test_export_dialog() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	await get_tree().process_frame
	Actions.run(&"export")
	var dialog: ExportDialog = main.export_dialog
	assert_true(dialog.visible)
	assert_true(dialog.image_format.visible, "image settings for an image")
	assert_false(dialog.pattern.visible)
	dialog.select_type(ExportOptions.Target.SPRITES)
	assert_false(dialog.image_format.visible)
	assert_true(dialog.pattern.visible, "file names for sprites")
	assert_false("padding" in dialog, "spacing is in the sidebar")
	assert_false("background_check" in dialog, "just a colour")
	assert_eq(dialog.background_picker.color.a, 0.0, "transparent by default")
	dialog.background_picker.color = Color.RED
	dialog.background_picker.color_changed.emit(Color.RED)
	dialog.select_type(ExportOptions.Target.DATA)
	assert_true(dialog.animation_fps.visible)
	var formats := dialog.grid_data
	var godot := range(formats.item_count).find_custom(
		func(i: int) -> bool: return formats.get_item_metadata(i) == "godot"
	)
	formats.select(godot)
	formats.item_selected.emit(godot)
	dialog.get_ok_button().pressed.emit()
	var file_dialog := dialog.output.file_dialog
	assert_true(file_dialog.visible, "asks where")
	assert_eq(file_dialog.current_file, "spritesheet.png")
	assert_true(dialog.visible, "until it's picked")

	var path := dir.path_join("dialog_export.png")
	file_dialog.file_selected.emit(path)
	await get_tree().process_frame
	assert_false(dialog.visible)
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(dir.path_join("dialog_export.tres")), "SpriteFrames too")
	var targets := ExportTarget.list(Global.spritesheet)
	assert_eq(targets.size(), 1, "kept in the project")
	assert_eq(targets[0].options.target, ExportOptions.Target.DATA)
	assert_eq(targets[0].options.background, Color.RED)
	assert_eq(targets[0].path, path)
	Notify.message_dialog.hide()


func test_export_dialog_for_a_packed_sheet() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	Global.spritesheet.set_layout(Spritesheet.Layout.PACKED)
	await get_tree().process_frame
	Actions.run(&"export")
	var dialog: ExportDialog = main.export_dialog
	var atlas := (
		ExportDialog
		. TYPES
		. map(func(t: Dictionary) -> int: return t.target)
		. find(ExportOptions.Target.ATLAS)
	)
	assert_eq(dialog.type.selected, atlas, "atlas first")
	assert_false(dialog.type.is_item_disabled(0), "pages as images")
	assert_true(dialog.type.is_item_disabled(2), "no data file of a grid")
	assert_true(dialog.atlas_data.visible)
	assert_true("Atlas size" in dialog.output_info.text, dialog.output_info.text)
	dialog.select_type(ExportOptions.Target.IMAGE)
	assert_true("Image size" in dialog.output_info.text, dialog.output_info.text)
	dialog.hide()
	Actions.run(&"export")
	assert_eq(dialog.type.selected, 0, "remembered")
	dialog.hide()


func test_packed_pages_export_as_images() -> void:
	var sheet := Global.spritesheet
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.BLUE, Color.GREEN]:
		images.append(make_image(color, Vector2i(40, 40)))
	sheet.add_frames(images)
	var settings := sheet.atlas_settings
	settings.max_size = 64
	sheet.set_atlas_settings(settings)
	sheet.set_layout(Spritesheet.Layout.PACKED)
	var pages := PackedLayout.get_page_sizes(sheet)
	assert_eq(pages.size(), 3, "a page each")
	var options := ExportOptions.from_sheet(sheet)
	options.target = ExportOptions.Target.IMAGE
	sheet.set_export_settings(options.to_dictionary())
	var path := dir.path_join("pages.png")
	assert_true(await main.files.exports.export_to(path))
	for i in 3:
		var page := Image.load_from_file(dir.path_join("pages_%d.png" % i))
		assert_eq(page.get_size(), pages[i])
	assert_false(FileAccess.file_exists(dir.path_join("pages.json")), "no data file")


func test_output_is_at_the_top_of_the_sidebar() -> void:
	var sections: Node = main.sheet_size.get_parent()
	assert_eq(main.export_btn.get_index(), 0, "the export button first")
	assert_eq(main.sheet_size.get_index(), 1, "its description under it")
	for child in sections.get_children():
		assert_false(child is Label and child.text == "Output", "no heading")


func test_history_panel() -> void:
	assert_true(main.preview_area._action_buttons.has(&"toggle_history"), "in the toolbar")
	var buttons: Dictionary = main.preview_area._action_buttons
	assert_eq(buttons[&"toggle_history"].get_index(), buttons[&"toggle_sprites"].get_index() + 1)
	assert_ne(Actions.get_action(&"toggle_history").icon, null)
	Actions.run(&"toggle_history")
	var panel: HistoryPanel = main.history_panel
	assert_true(panel.visible)
	for color: Color in [Color.RED, Color.GREEN]:
		Global.document.perform(
			"Add sprites", Global.spritesheet.add_frames.bind([make_image(color)] as Array[Image])
		)
	assert_eq(panel.list.item_count, 3, "the start and two steps")
	assert_eq(panel.list.get_item_text(2), "Add sprites")
	assert_true(panel.list.is_selected(2), "the current step")
	panel.list.item_clicked.emit(0, Vector2.ZERO, MOUSE_BUTTON_WHEEL_DOWN)
	assert_false(Global.spritesheet.is_empty(), "scrolling doesn't go back")
	panel.list.item_clicked.emit(0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	assert_true(Global.spritesheet.is_empty(), "clicking the start undoes everything")
	assert_true(panel.list.is_selected(0))
	Actions.run(&"toggle_history")
	assert_false(panel.visible)


func test_opening_an_image_uses_its_data_file() -> void:
	var path := dir.path_join("packed_hero.png")
	var img := Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 10, 16), Color.RED)
	img.fill_rect(Rect2i(10, 0, 22, 16), Color.BLUE)
	img.save_png(path)
	var data := {
		"frames":
		{
			"a": {"frame": {"x": 0, "y": 0, "w": 10, "h": 16}},
			"b": {"frame": {"x": 10, "y": 0, "w": 22, "h": 16}},
		},
		"meta": {"image": "packed_hero.png", "frameTags": [{"name": "walk", "from": 0, "to": 1}]},
	}
	var file := FileAccess.open(dir.path_join("packed_hero.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	Global.spritesheet.add_frames([make_image(Color.GREEN)] as Array[Image])
	await main.files.show_add_spritesheet_window(dir.path_join("packed_hero.json"))
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	assert_eq(window.get_cut(), AddSpritesheetWindow.Cut.DATA)
	assert_eq(window.spritesheet.frames.size(), 2)
	window.set_cut(AddSpritesheetWindow.Cut.GRID)
	assert_eq(window.spritesheet.animations.size(), 0, "back to cutting a grid")
	window.set_cut(AddSpritesheetWindow.Cut.DATA)
	window.add_spritesheet_to_global()
	var sheet := Global.spritesheet
	assert_eq(sheet.frames[Vector2i(1, 1)].get_size(), Vector2i(22, 16))
	assert_eq(sheet.animations[0].cells, [Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i])


func test_resize_filter_sticks_at_the_original_size() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	main.resize_filter.select(Image.INTERPOLATE_BILINEAR)
	main.resize_filter.item_selected.emit(Image.INTERPOLATE_BILINEAR)
	await get_tree().process_frame
	assert_eq(main.resize_filter.selected, Image.INTERPOLATE_BILINEAR)
	assert_eq(Global.spritesheet.scale_filter, Image.INTERPOLATE_BILINEAR)
	Settings.set_value(&"resize_filter", Image.INTERPOLATE_CUBIC)
	Global.document.reset()
	await get_tree().process_frame
	assert_eq(main.resize_filter.selected, Image.INTERPOLATE_CUBIC, "new sheets use the setting")
	Settings.set_value(&"resize_filter", Image.INTERPOLATE_NEAREST)


func test_context_menu_submenus() -> void:
	var menu: ActionPopupMenu = main.preview_area.options_menu
	var labels: Array[String] = []
	for i in menu.item_count:
		labels.append(menu.get_item_text(i))
	for label: String in ["Transform", "Align in Cell", "Rows"]:
		assert_true(label in labels, label)
		var index := labels.find(label)
		assert_ne(menu.get_item_submenu_node(index), null, label + " opens a submenu")
		assert_ne(menu.get_item_icon(index), null, label + " has an icon")
	assert_false("Flip Horizontally" in labels, "flipping is in Transform")
	var rows := menu.get_item_submenu_node(labels.find("Rows")) as ActionPopupMenu
	assert_eq(rows.get_item_text(0), "Insert Row")
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	main.preview.select_all()
	await get_tree().process_frame
	rows.index_pressed.emit(0)
	assert_eq(Global.spritesheet.grid_size.y, 2, "runs the action")


func test_outline_keeps_frames_in_place() -> void:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 4, 4), Color.RED)
	Global.spritesheet.add_frames([img, make_image(Color.BLUE, Vector2i(8, 8))] as Array[Image])
	main.preview.set_selected_coords([Vector2i(0, 0)] as Array[Vector2i])
	Global.document.perform(
		"Nudge",
		Global.spritesheet.nudge_frames.bind([Vector2i(0, 0)] as Array[Vector2i], Vector2i(1, 0))
	)
	var before := Global.spritesheet.get_frame_origin(Vector2i(0, 0))
	await main.add_outline(Color.BLACK, 2, true)
	var after := Global.spritesheet.get_frame_origin(Vector2i(0, 0))
	assert_eq(Global.spritesheet.frames[Vector2i(0, 0)].get_size(), Vector2i(12, 12))
	assert_eq(after, before - Vector2i(2, 2), "the pixels stay in place")
	await main.color_key.remove(Color.BLACK, 0.05)
	assert_true(Global.spritesheet.has_frame_origin(Vector2i(0, 0)), "keeps its place")
	assert_eq(Global.document.get_history()[-1], "Remove background")
