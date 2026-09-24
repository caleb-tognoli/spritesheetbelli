extends "res://tests/test_case.gd"

var main: Control
var dir := OS.get_user_data_dir().path_join("tests")


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
	main.files.export_image_to(path)
	assert_true(FileAccess.file_exists(path + ".png"))
	assert_eq(Global.document.export_path, path + ".png", "Ctrl+E exports here next time")
	Notify.message_dialog.hide()


func test_save_and_open_project() -> void:
	Global.document.perform(
		"Add",
		func() -> void:
			Global.spritesheet.add_frames(
				[make_image(Color.RED), make_image(Color.BLUE, Vector2i(8, 16))] as Array[Image]
			)
			Global.spritesheet.set_grid_size(Vector2i(3, 2))
			Global.spritesheet.set_locked(Vector2i(2, 1), true)
			Global.spritesheet.set_row_name(0, "idle")
			Global.spritesheet.resize_sprites(Vector2i(32, 32))
	)
	var path := dir.path_join("project")
	assert_true(main.files.save_project(path))
	assert_eq(Global.document.path, path + ".sbelli")
	assert_false(Global.document.is_dirty)
	Notify.message_dialog.hide()

	Global.document.reset()
	assert_true(main.files.open_project(path + ".sbelli"))
	var sheet := Global.spritesheet
	assert_eq(sheet.grid_size, Vector2i(3, 2))
	assert_eq(sheet.frames[Vector2i(1, 0)].get_size(), Vector2i(8, 16), "original size kept")
	assert_eq(sheet.sprite_size, Vector2i(32, 32), "scale kept")
	assert_true(sheet.is_locked(Vector2i(2, 1)))
	assert_eq(sheet.row_names.get(0), "idle")
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_false(Global.document.can_undo())


func test_opening_invalid_project_shows_error() -> void:
	var path := dir.path_join("broken.sbelli")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a zip")
	f.close()
	assert_false(main.files.open_project(path))
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


func test_opening_a_file_is_not_an_unsaved_change() -> void:
	var path := dir.path_join("open_me.png")
	make_image(Color.RED, Vector2i(32, 16)).save_png(path)
	main.files.set_filepath_when_opening_spritesheet = true
	main.files.show_add_spritesheet_window(path)
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


func test_select_none_shows_with_a_selection() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	await get_tree().process_frame
	var button: Button = main.preview_area.select_none_btn
	assert_false(button.visible, "nothing selected")
	Actions.run(&"select_all")
	assert_true(button.visible)
	Actions.run(&"select_none")
	assert_false(button.visible)


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

	main.files.open_dropped_files(PackedStringArray([folder.path_join("a2.png")]))
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
	assert_true(window.slice_info.text.contains("1 px on the right"), window.slice_info.text)


func test_empty_hint_and_toasts() -> void:
	assert_true(main.preview_area.empty_hint.visible, "hint while empty")
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	await get_tree().process_frame
	assert_false(main.preview_area.empty_hint.visible)
	main.files.export_image_to(dir.path_join("toast.png"))
	assert_true(Notify.get_toasts()[-1].begins_with("Exported toast.png"))


func test_zoom_presets() -> void:
	var menu: PopupMenu = main.preview_area.zoom.get_popup()
	menu.id_pressed.emit(PreviewArea.ZOOM_PRESETS.find(4.0))
	assert_eq(main.preview.camera.zoom.x, 4.0)
	assert_eq(main.preview_area.zoom.text, "400%")


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
