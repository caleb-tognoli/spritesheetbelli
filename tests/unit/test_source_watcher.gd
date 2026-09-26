extends "res://tests/test_case.gd"

const FIRST := Vector2i(0, 0)

var main: Control
var watcher: SourceWatcher
var dir := OS.get_user_data_dir().path_join("tests/watched")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	watcher = main.source_watcher
	# Looks are made by the tests, one at a time
	watcher.timer.stop()
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


## A 6x4 image, [param color] on the left half
func write(file_name: String, color: Color) -> String:
	var img := Image.create_empty(6, 4, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 3, 4), color)
	var path := dir.path_join(file_name)
	img.save_png(path)
	return path


## Adds images as sprites and takes a first look at their files
func add_sprites(paths: Array[String]) -> void:
	await main.files.add_sprites_from_paths(PackedStringArray(paths))
	watcher.check()


## Two looks: a changed file counts once it's done being written
func look_twice() -> void:
	watcher.check()
	watcher.check()


func test_added_sprites_are_linked() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	assert_eq(Global.spritesheet.frame_sources[FIRST], FrameSource.for_file(path))
	assert_true(Global.document.source_hashes.has(path), "first look remembers the file")
	assert_true(
		"Linked to %s" % path in PreviewArea.describe_cell(Global.spritesheet, FIRST), "tooltip"
	)


func test_a_change_is_noticed_once_written() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	watcher.check()
	assert_true(watcher.changed_paths.is_empty(), "unchanged")
	write("walk.png", Color.BLUE)
	watcher.check()
	assert_true(watcher.changed_paths.is_empty(), "may still be being written")
	watcher.check()
	assert_eq(watcher.changed_paths, PackedStringArray([path]))
	watcher.check()
	assert_eq(watcher.changed_paths.size(), 1, "asked about once")


func test_missing_files_are_skipped() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	DirAccess.remove_absolute(path)
	look_twice()
	assert_true(watcher.changed_paths.is_empty())
	write("walk.png", Color.RED)
	look_twice()
	assert_true(watcher.changed_paths.is_empty(), "saved back the same")


func test_reload_keeping_or_dropping_edits() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	var sheet := Global.spritesheet
	Global.document.perform("Flip", FrameEdits.flip.bind(sheet, [FIRST] as Array[Vector2i], true))
	write("walk.png", Color.BLUE)

	await watcher.reload(PackedStringArray([path]), true)
	assert_color(sheet.frames[FIRST], Vector2i(5, 0), Color.BLUE, "new pixels, still flipped")
	assert_true(FrameSource.has_edits(sheet.frame_sources[FIRST]), "edits kept")
	assert_eq(sheet.frames[FIRST].resource_name, "walk.png")
	assert_eq(Global.document.get_history()[-1], "Reload walk.png")
	look_twice()
	assert_true(watcher.changed_paths.is_empty(), "the reloaded file is the known one")

	Global.document.undo()
	assert_color(sheet.frames[FIRST], Vector2i(5, 0), Color.RED, "undone")
	await watcher.reload(PackedStringArray([path]), false)
	assert_color(sheet.frames[FIRST], Vector2i(0, 0), Color.BLUE, "not flipped")
	assert_false(FrameSource.has_edits(sheet.frame_sources[FIRST]), "edits dropped")


func test_answering_for_every_changed_file() -> void:
	var paths: Array[String] = [write("a.png", Color.RED), write("b.png", Color.RED)]
	await add_sprites(paths)
	FrameEdits.flip(Global.spritesheet, [Vector2i(1, 0)] as Array[Vector2i], true)
	write("a.png", Color.BLUE)
	write("b.png", Color.BLUE)
	look_twice()
	assert_eq(watcher.changed_paths.size(), 2)

	watcher.ask_next()
	var dialog := watcher.dialog
	assert_true(dialog.visible)
	assert_true("a.png" in dialog.message.text)
	assert_true(dialog.for_all_check.visible)
	assert_false(dialog.reset_button.visible, "a.png's frame wasn't edited")
	dialog.for_all_check.button_pressed = true
	assert_true(dialog.reset_button.visible, "b.png's frame was")
	dialog.get_ok_button().pressed.emit()
	for i in 60:
		if watcher.changed_paths.is_empty() and not dialog.visible and not watcher._reloading:
			break
		await get_tree().process_frame
	await get_tree().process_frame

	assert_false(dialog.visible, "nothing left to ask")
	assert_eq(Global.document.get_history()[-1], "Reload 2 files", "one undoable step")
	assert_color(Global.spritesheet.frames[FIRST], Vector2i.ZERO, Color.BLUE)
	assert_color(Global.spritesheet.frames[Vector2i(1, 0)], Vector2i(5, 0), Color.BLUE)


func test_ignoring_a_change() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	write("walk.png", Color.BLUE)
	look_twice()
	watcher.ask_next()
	watcher.dialog.ignore_button.pressed.emit()
	await get_tree().process_frame
	assert_color(Global.spritesheet.frames[FIRST], Vector2i.ZERO, Color.RED, "left alone")
	look_twice()
	assert_true(watcher.changed_paths.is_empty(), "not asked again")
	assert_false(watcher.dialog.visible)


func test_changed_files_whose_frames_are_gone_are_not_asked_about() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	write("walk.png", Color.BLUE)
	look_twice()
	Global.document.perform(
		"Delete", Global.spritesheet.remove_frames.bind([FIRST] as Array[Vector2i])
	)
	watcher.ask_next()
	assert_false(watcher.dialog.visible)


func test_reload_from_file_action() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	var preview: SpritesheetPreview = main.preview_area.spritesheet_preview
	preview.set_selected_coords([FIRST] as Array[Vector2i])
	assert_true(Actions.is_enabled(&"reload_source"))
	write("walk.png", Color.BLUE)
	await watcher.reload_frames(main.get_selected_linked_coords(), true, "Reload from file")
	assert_color(Global.spritesheet.frames[FIRST], Vector2i.ZERO, Color.BLUE)


func test_exporting_over_a_linked_file_unlinks_it() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	assert_true(await main.files.export_image_to(path))
	assert_true(Global.spritesheet.frame_sources.is_empty())
	assert_true(path in Global.document.unwatched_paths)
	var toasts := " ".join(Notify.get_toasts())
	assert_true("Frames from walk.png are no longer linked" in toasts)
	# Redoing the step that linked it doesn't make it reload what was exported
	Global.document.undo()
	Global.document.redo()
	assert_false(Global.spritesheet.frame_sources.is_empty())
	write("walk.png", Color.BLUE)
	look_twice()
	assert_true(watcher.changed_paths.is_empty())
	# Adding the file again links it again
	await add_sprites([path])
	assert_false(path in Global.document.unwatched_paths)


func test_spritesheets_are_linked_by_region() -> void:
	var path := write("sheet.png", Color.RED)
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.setup(Image.load_from_file(path), path)
	window.update_grid_size(2, 1)
	window.add_spritesheet_to_global()
	var source: Dictionary = Global.spritesheet.frame_sources[FIRST]
	assert_eq(source, FrameSource.for_region(path, Rect2i(0, 0, 3, 4)))
	# The right half is transparent, so it isn't a frame
	assert_eq(Global.spritesheet.frame_sources.size(), 1)


func test_projects_notice_changes_made_while_closed() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	var project := dir.path_join("walk.sbelli")
	assert_true(await main.files.save_project(project))
	Global.document.reset()
	write("walk.png", Color.BLUE)
	assert_true(await main.files.open_project(project))
	assert_true(Global.document.source_hashes.has(path))
	look_twice()
	assert_eq(watcher.changed_paths, PackedStringArray([path]))


func test_turning_it_off() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	Settings.set_value(&"watch_sources", false)
	assert_false(watcher.is_enabled())
	Settings.set_value(&"watch_sources", true)


func test_waits_for_open_dialogs_to_close() -> void:
	var path := write("walk.png", Color.RED)
	await add_sprites([path])
	write("walk.png", Color.BLUE)
	look_twice()
	main.settings_window.popup_centered()
	watcher.ask_next()
	assert_false(watcher.dialog.visible, "not over Settings")
	main.settings_window.hide()
	watcher.ask_next()
	assert_true(watcher.dialog.visible)
	watcher.dialog.hide()
