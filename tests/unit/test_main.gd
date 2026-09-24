extends "res://tests/test_case.gd"

var main: Control
var dir := OS.get_user_data_dir().path_join("tests")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Global.reset_spritesheet()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	Global.reset_spritesheet()


func save_images(colors: Dictionary) -> void:
	for file_name: String in colors:
		make_image(colors[file_name]).save_png(dir.path_join(file_name))


func test_added_sprites_are_sorted_and_deduplicated() -> void:
	save_images({"f1.png": Color.RED, "f2.png": Color.GREEN, "f10.png": Color.BLUE})
	main.add_sprites_from_paths(PackedStringArray([
		dir.path_join("f10.png"), dir.path_join("f2.png"), dir.path_join("f1.png"), dir.path_join("f1.png")
	]))
	var frames: Dictionary = Global.spritesheet.frames
	assert_eq(frames.size(), 3)
	assert_color(frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(frames[Vector2i(1, 0)], Vector2i.ZERO, Color.GREEN)
	assert_color(frames[Vector2i(2, 0)], Vector2i.ZERO, Color.BLUE)


func test_file_dialog_opens_once() -> void:
	main.popup_file_dialog(main.open_sprites_dialog)
	main.popup_file_dialog(main.open_sprites_dialog)
	assert_eq(main.open_file_dialogs.size(), 1)
	main.open_sprites_dialog.canceled.emit()
	assert_true(main.open_file_dialogs.is_empty(), "canceled releases the dialog")
	main.open_sprites_dialog.hide()


func test_zoom_keeps_point_under_cursor() -> void:
	main.add_sprites_from_paths(PackedStringArray())
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	var preview: SpritesheetPreview = main.preview_area.spritesheet_preview
	var anchor := Vector2(100, 80)
	var before := preview.camera.position + anchor / preview.camera.zoom
	preview.set_zoom(4, anchor)
	assert_eq(preview.camera.position + anchor / preview.camera.zoom, before)
	var frame: SpritesheetPreviewFrame = preview.frames.get_child(0)
	assert_eq(frame.index_container.scale, Vector2.ONE * 0.25)
	assert_true(frame.index_container.visible, "index visible when frame is 64px on screen")
	preview.set_zoom(1)
	assert_false(frame.index_container.visible, "index hidden when frame is 16px on screen")


func test_add_spritesheet_keeps_empty_rows() -> void:
	var img := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)
	img.fill_rect(Rect2i(32, 32, 16, 16), Color.BLUE)
	var window: AddSpritesheetWindow = main.add_spritesheet_window
	window.setup(img)
	window.update_grid_size(3, 3)
	window.add_spritesheet_to_global()
	var frames: Dictionary = Global.spritesheet.frames
	assert_color(frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(frames[Vector2i(2, 2)], Vector2i.ZERO, Color.BLUE)
	assert_eq(Global.spritesheet.grid_size, Vector2i(3, 3))


func test_save_appends_png_extension() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	var path := dir.path_join("sheet_no_ext")
	main.save_spritesheet(path)
	assert_true(FileAccess.file_exists(path + ".png"))
	assert_eq(Global.filepath, path + ".png")
	assert_false(Global.has_unsaved_changes)
	main.notification_dialog.hide()


func test_confirmation_runs_latest_action_once() -> void:
	var calls := [0]
	main.show_confirmation_dialog("t", "t", func(): calls[0] += 1)
	main.confirmation_dialog.canceled.emit()
	main.show_confirmation_dialog("t", "t", func(): calls[0] += 10)
	main.confirmation_dialog.confirmed.emit()
	main.confirmation_dialog.confirmed.emit()
	assert_eq(calls[0], 10)
	main.confirmation_dialog.hide()


func test_canceling_open_keeps_spritesheet() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	Global.has_unsaved_changes = false
	main.open_spritesheet()
	main.open_spritesheet_dialog.canceled.emit()
	assert_eq(Global.spritesheet.frames.size(), 1)
	assert_false(main.set_filepath_when_opening_spritesheet)
	main.open_spritesheet_dialog.hide()


func test_new_clears_everything() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	Global.filepath = "x.png"
	Global.has_unsaved_changes = false
	main.new_spritesheet()
	assert_true(Global.spritesheet.is_empty())
	assert_eq(Global.filepath, "")
