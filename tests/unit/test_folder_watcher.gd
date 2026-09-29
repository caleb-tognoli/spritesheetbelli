extends "res://tests/test_case.gd"

var main: Control
var watcher: SourceWatcher
var folders: FolderWatcher
var dir := temp_path("linked")
var _add_mode: Variant


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	_add_mode = Settings.get_value(&"add_mode")
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	watcher = main.source_watcher
	folders = watcher.folders
	# Looks are made by the tests, one at a time
	watcher.timer.stop()
	await get_tree().process_frame


func after_each() -> void:
	folders.dialog.hide()
	main.queue_free()
	Settings.set_value(&"add_mode", _add_mode)
	FolderWatcher.in_browser = WebFiles.is_web()
	Global.document.reset()


## A 4x4 image of [param color]
func write(file_name: String, color: Color) -> String:
	var path := dir.path_join(file_name)
	make_image(color, Vector2i(4, 4)).save_png(path)
	return path


## Adds the folder like Add Folder, and takes a first look at its files
func add_folder() -> void:
	await main.files.add_sprites_from_folder(dir)
	watcher.check()
	folders.check()


## Two looks: a new file counts once it's done being written, a deleted one once it
## stays gone
func look_twice() -> void:
	for i in 2:
		watcher.check()
		folders.check()


func test_add_folder_links_it() -> void:
	write("a.png", Color.RED)
	write("b.png", Color.BLUE)
	await add_folder()
	var sheet := Global.spritesheet
	assert_eq(sheet.frames.size(), 2)
	assert_eq(sheet.linked_folders, PackedStringArray([dir]))
	look_twice()
	assert_false(folders.has_changes(), "the files added aren't new")
	# Linking is part of adding
	Global.document.undo()
	assert_true(sheet.linked_folders.is_empty(), "undone")
	Global.document.redo()
	assert_eq(sheet.linked_folders, PackedStringArray([dir]), "redone")


func test_dropping_a_folder_links_it() -> void:
	write("a.png", Color.RED)
	await main.files.open_dropped_files(PackedStringArray([dir]))
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([dir]))


func test_a_folder_without_images_is_linked() -> void:
	var sheet := Global.spritesheet
	await add_folder()
	assert_eq(sheet.linked_folders, PackedStringArray([dir]))
	assert_true(sheet.frames.is_empty())
	assert_false(Notify.message_dialog.visible, "no error")
	assert_eq(Notify.get_toasts()[-1], "Watching linked for new images.")
	assert_eq(Global.document.get_history()[-1], "Link folder")
	var panel: SpritesPanel = main.layout_controller.sprites_panel
	panel.visible = true
	panel.refresh()
	assert_true(panel.folders_box.get_parent().visible, "listed")
	# Images saved there later are added
	write("a.png", Color.RED)
	look_twice()
	assert_true(folders.has_changes())
	await folders.apply()
	assert_eq(sheet.frames.size(), 1)
	Global.document.undo()
	Global.document.undo()
	assert_true(sheet.linked_folders.is_empty(), "undone like Add Folder")


func test_dropping_a_folder_without_images_links_it() -> void:
	await main.files.open_dropped_files(PackedStringArray([dir]))
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([dir]))
	assert_false(Notify.message_dialog.visible, "no error")
	assert_eq(Notify.get_toasts()[-1], "Watching linked for new images.")


func test_a_folder_without_images_is_linked_paused_when_reloading_is_off() -> void:
	Settings.set_value(&"watch_sources", false)
	await add_folder()
	# Its tooltip in the Sprites panel says so too, until reloading is on again
	var panel: SpritesPanel = main.layout_controller.sprites_panel
	panel.visible = true
	panel.refresh()
	var label: Label = panel.folders_box.get_children()[-1].get_child(1)
	assert_true(label.tooltip_text.ends_with("\nPaused: Reload changed files is off."))
	Settings.set_value(&"watch_sources", true)
	label = panel.folders_box.get_children()[-1].get_child(1)
	assert_true(label.tooltip_text.ends_with("\nImages added to it are added here."))
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([dir]), "still linked")
	assert_false(Notify.message_dialog.visible, "no error")
	assert_eq(Notify.get_toasts()[-1], "Linked linked, paused: Reload changed files is off.")


func test_adding_images_does_not_link() -> void:
	var path := write("a.png", Color.RED)
	await main.files.add_sprites_from_paths(PackedStringArray([path]))
	assert_true(Global.spritesheet.linked_folders.is_empty())


func test_new_files_are_added() -> void:
	write("a.png", Color.RED)
	await add_folder()
	Settings.set_value(&"add_mode", Spritesheet.AddMode.NEW_ROW)
	var history := Global.document.get_history().size()
	Global.document.mark_saved()
	var path := write("b.png", Color.BLUE)
	folders.check()
	assert_false(folders.has_changes(), "may still be being written")
	write("b.png", Color.GREEN)
	folders.check()
	assert_false(folders.has_changes(), "still being written")
	folders.check()
	assert_true(folders.has_changes(), "done")
	await folders.apply()

	var sheet := Global.spritesheet
	var added := Vector2i(0, 1)
	assert_eq(sheet.frames.size(), 2)
	assert_color(sheet.frames[added], Vector2i.ZERO, Color.GREEN, "in a new row")
	assert_eq(sheet.frame_sources[added], FrameSource.for_file(path), "linked")
	assert_eq(Global.document.get_history().size(), history + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Add new sprites")
	assert_true(Global.document.is_dirty, "unsaved")
	assert_true("Added 1 new sprites from linked." in Notify.get_toasts())

	Global.document.undo()
	assert_false(sheet.frames.has(added), "undone")
	look_twice()
	assert_false(folders.has_changes(), "not added again")


func test_only_images_right_in_the_folder_count() -> void:
	write("a.png", Color.RED)
	await add_folder()
	DirAccess.make_dir_absolute(dir.path_join("sub"))
	make_image(Color.BLUE).save_png(dir.path_join("sub/b.png"))
	FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE).store_string("hi")
	look_twice()
	assert_false(folders.has_changes())
	remove_dir(dir.path_join("sub"))


func test_deleted_files_are_asked_about() -> void:
	write("a.png", Color.RED)
	var path := write("b.png", Color.BLUE)
	await add_folder()
	DirAccess.remove_absolute(path)
	folders.check()
	assert_false(folders.has_changes(), "may be being saved by deleting and renaming")
	folders.check()
	assert_true(folders.has_changes())
	await folders.apply()
	assert_true(folders.dialog.visible)
	assert_true("Remove 1 frames whose files were deleted?" in folders.dialog.dialog_text)
	assert_true("b.png" in folders.dialog.dialog_text)

	folders.dialog.get_ok_button().pressed.emit()
	var sheet := Global.spritesheet
	assert_eq(sheet.frames.size(), 1, "removed")
	assert_true(sheet.frames.has(Vector2i.ZERO), "a.png's frame is left")
	assert_eq(Global.document.get_history()[-1], "Remove frames of deleted files")
	look_twice()
	assert_false(folders.has_changes())


func test_keeping_the_frames_of_deleted_files() -> void:
	var path := write("a.png", Color.RED)
	await add_folder()
	DirAccess.remove_absolute(path)
	look_twice()
	await folders.apply()
	folders.dialog.get_cancel_button().pressed.emit()
	assert_eq(Global.spritesheet.frames.size(), 1, "kept")
	look_twice()
	assert_false(folders.has_changes(), "not asked again")
	# Back again, it's the file the frame is linked to, not a new one
	write("a.png", Color.RED)
	look_twice()
	assert_false(folders.has_changes())


func test_a_file_deleted_with_its_frames_is_not_asked_about() -> void:
	var path := write("a.png", Color.RED)
	await add_folder()
	Global.document.perform(
		"Delete", Global.spritesheet.remove_frames.bind([Vector2i.ZERO] as Array[Vector2i])
	)
	DirAccess.remove_absolute(path)
	look_twice()
	await folders.apply()
	assert_false(folders.dialog.visible)


func test_renamed_files_are_followed() -> void:
	write("a.png", Color.RED)
	write("b.png", Color.BLUE)
	await add_folder()
	var history := Global.document.get_history().size()
	var new_path := dir.path_join("c.png")
	DirAccess.rename_absolute(dir.path_join("b.png"), new_path)
	look_twice()
	await folders.apply()
	var sheet := Global.spritesheet
	assert_false(folders.dialog.visible, "not asked")
	assert_eq(sheet.frames.size(), 2, "not added again")
	assert_eq(sheet.frame_sources[Vector2i(1, 0)], FrameSource.for_file(new_path))
	assert_eq(Global.document.get_history().size(), history + 1)
	assert_eq(Global.document.get_history()[-1], "Follow renamed files")
	look_twice()
	assert_false(folders.has_changes())
	# Changes to the renamed file are noticed
	write("c.png", Color.GREEN)
	look_twice()
	assert_eq(watcher.changed_paths, PackedStringArray([new_path]))


func test_unlinking() -> void:
	write("a.png", Color.RED)
	await add_folder()
	var panel: SpritesPanel = main.layout_controller.sprites_panel
	panel.visible = true
	panel.refresh()
	var rows := panel.folders_box.get_children().filter(
		func(row: Node) -> bool: return not row.is_queued_for_deletion()
	)
	assert_eq(rows.size(), 1, "listed")
	assert_true(panel.folders_box.get_parent().visible)
	var label: Label = rows[0].get_child(1)
	assert_eq(label.text, "linked")
	var unlink: Button = rows[0].get_child(2)
	assert_eq(unlink.tooltip_text, "Unlink folder")
	unlink.pressed.emit()

	assert_true(Global.spritesheet.linked_folders.is_empty())
	assert_eq(Global.document.get_history()[-1], "Unlink folder")
	assert_false(panel.folders_box.get_parent().visible, "not listed")
	assert_eq(Global.spritesheet.frame_sources.size(), 1, "the frames stay linked to their files")
	write("b.png", Color.BLUE)
	look_twice()
	assert_false(folders.has_changes(), "not followed")


func test_saved_with_the_project() -> void:
	write("a.png", Color.RED)
	await add_folder()
	var project := temp_path("folder.sbelli")
	assert_true(await main.files.save_project(project))
	Global.document.reset()
	# Added while the project was closed
	write("b.png", Color.BLUE)
	assert_true(await main.files.open_project(project))
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([dir]))
	assert_eq(Global.document.folder_files[dir], PackedStringArray(["a.png"]))
	look_twice()
	await folders.apply()
	assert_eq(Global.spritesheet.frames.size(), 2, "added on opening")
	DirAccess.remove_absolute(project)


func test_moved_with_the_project() -> void:
	write("a.png", Color.RED)
	await add_folder()
	var project := dir.path_join("folder.sbelli")
	assert_true(await main.files.save_project(project))
	var moved := temp_path("moved")
	DirAccess.rename_absolute(dir, moved)
	var result := ProjectFile.load(moved.path_join("folder.sbelli"))
	DirAccess.rename_absolute(moved, dir)
	DirAccess.remove_absolute(project)
	assert_eq(result.state.folders, PackedStringArray([moved]))


func test_a_missing_folder_is_left_alone() -> void:
	write("a.png", Color.RED)
	await add_folder()
	var moved := temp_path("moved")
	DirAccess.rename_absolute(dir, moved)
	look_twice()
	DirAccess.rename_absolute(moved, dir)
	assert_false(folders.has_changes(), "its files aren't deleted")
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([dir]), "still linked")


func test_turned_off_with_reloading() -> void:
	write("a.png", Color.RED)
	await add_folder()
	Settings.set_value(&"watch_sources", false)
	write("b.png", Color.BLUE)
	for i in 2:
		watcher.timer.timeout.emit()
	Settings.set_value(&"watch_sources", true)
	assert_false(folders.has_changes(), "not looked at")
	assert_eq(Global.spritesheet.frames.size(), 1)


func test_web_build_does_not_link() -> void:
	write("a.png", Color.RED)
	await add_folder()
	FolderWatcher.in_browser = true
	var panel: SpritesPanel = main.layout_controller.sprites_panel
	panel.visible = true
	panel.refresh()
	assert_false(panel.folders_box.get_parent().visible, "linked folders hidden")
	Global.document.reset()
	await main.files.add_sprites_from_folder(dir)
	assert_eq(Global.spritesheet.frames.size(), 1, "still added")
	assert_true(Global.spritesheet.linked_folders.is_empty(), "not linked")
	# Nor without images
	Global.document.reset()
	DirAccess.remove_absolute(dir.path_join("a.png"))
	await main.files.add_sprites_from_folder(dir)
	assert_true(Global.spritesheet.linked_folders.is_empty())
	assert_true(Notify.message_dialog.visible, "there are no images")
	Notify.message_dialog.hide()
