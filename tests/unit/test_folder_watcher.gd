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


## The unlink button of [param row], a row of [member LinkedFolders.rows]
func unlink_button_of(row: Control) -> Button:
	return row.get_child(0).get_child(-1)


## The labels of [param row], a row of [member LinkedFolders.rows]: its name, and the folder
## it's in or that it's missing
func labels_of(row: Control) -> Array[Label]:
	var labels: Array[Label] = []
	labels.assign(row.get_child(0).get_child(0).get_children())
	return labels


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
	assert_true(main.linked_folders.visible, "listed")
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
	# Its row under Add Sprite(s) says so too, until reloading is on again
	var card: LinkedFolders = main.linked_folders
	var row: Control = card.rows.get_child(-1)
	assert_true(row.tooltip_text.ends_with("\nPaused: Reload changed files is off."))
	assert_true(card.paused_row.visible, "under the folders")
	card.turn_on_button.pressed.emit()
	assert_true(Settings.get_value(&"watch_sources"), "turned on")
	assert_false(card.paused_row.visible)
	row = card.rows.get_child(-1)
	assert_true(row.tooltip_text.ends_with("\nImages added to it are added here."))
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
	assert_true("Added 1 new sprite from linked." in Notify.get_toasts())

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
	assert_true("Remove 1 frame whose file was deleted?" in folders.dialog.dialog_text)
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
	var card: LinkedFolders = main.linked_folders
	assert_eq(card.rows.get_child_count(), 1, "listed")
	assert_true(card.visible)
	var unlink := unlink_button_of(card.rows.get_child(0))
	assert_eq(unlink.tooltip_text, "Unlink folder")
	unlink.pressed.emit()

	assert_true(Global.spritesheet.linked_folders.is_empty())
	assert_eq(Global.document.get_history()[-1], "Unlink folder")
	assert_false(card.visible, "not listed")
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
	main.linked_folders.refresh()
	assert_false(main.linked_folders.visible, "linked folders hidden")
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


func test_linked_folders_are_listed_under_add_sprites() -> void:
	write("a.png", Color.RED)
	await add_folder()
	var card: LinkedFolders = main.linked_folders
	assert_eq(card.get_index(), main.add_sprites_btn.get_parent().get_index() + 1)
	assert_eq(card.count_label.text, "1")
	var row: Control = card.rows.get_child(0)
	var labels := labels_of(row)
	assert_eq(labels[0].text, "linked")
	assert_true(
		labels[1].get_theme_font_size("font_size") < labels[0].get_theme_font_size("font_size"),
		"the path is smaller than the name"
	)
	assert_true(dir.get_base_dir().ends_with(labels[1].text.trim_prefix("…")), "where it is")
	assert_true(row.tooltip_text.begins_with(dir + "\n"))
	assert_false(card.paused_row.visible)
	card.open_menu(dir, Vector2.ZERO)
	var items: PackedStringArray = []
	for i in card.menu.item_count:
		items.append(card.menu.get_item_text(i))
	assert_eq(items, PackedStringArray(["Show in File Manager", "Copy Path", "", "Unlink Folder"]))
	card.menu.hide()


func test_a_missing_folder_can_be_located() -> void:
	var moved := temp_path("moved")
	var a := write("a.png", Color.RED)
	write("b.png", Color.BLUE)
	await add_folder()
	var sheet := Global.spritesheet
	var coord_a: Vector2i = FrameSource.get_linked(sheet, a)[0]
	DirAccess.remove_absolute(dir.path_join("b.png"))
	DirAccess.rename_absolute(dir, moved)
	# Saved there while it wasn't followed
	make_image(Color.GREEN, Vector2i(4, 4)).save_png(moved.path_join("c.png"))
	var card: LinkedFolders = main.linked_folders
	card.refresh()
	var row: Control = card.rows.get_child(0)
	assert_eq(labels_of(row)[1].text, "Not found")
	var locate_button: Button = row.get_child(0).get_child(1)
	assert_eq(locate_button.text, "Locate…")
	card.open_menu(dir, Vector2.ZERO)
	assert_ne(card.menu.get_item_index(LinkedFolders.MenuItem.LOCATE), -1, "in its menu too")
	assert_true(card.menu.is_item_disabled(card.menu.get_item_index(LinkedFolders.MenuItem.SHOW)))
	card.menu.hide()

	card.locate(dir)
	assert_eq(card.locate_dialog.current_dir, dir.get_base_dir(), "starts where it was")
	card.locate_dialog.hide()
	card.locate_dialog.dir_selected.emit(moved)
	assert_eq(sheet.linked_folders, PackedStringArray([moved]))
	assert_eq(Global.document.get_history()[-1], "Locate folder")
	assert_eq(sheet.frame_sources[coord_a].path, moved.path_join("a.png"), "its frames follow")
	assert_eq(sheet.frames.size(), 2, "nothing added yet")
	assert_eq(labels_of(card.rows.get_child(0))[0].text, "moved")
	look_twice()
	assert_eq(watcher.changed_paths, PackedStringArray(), "the moved files didn't change")
	assert_true(folders.has_changes(), "the image saved meanwhile is new")
	await folders.apply()
	assert_eq(sheet.frames.size(), 3, "and added")
	assert_false(folders.dialog.visible, "nothing was deleted")

	Global.document.undo()
	Global.document.undo()
	assert_eq(sheet.linked_folders, PackedStringArray([dir]), "undone")
	assert_eq(sheet.frame_sources[coord_a].path, a)
	for file in DirAccess.get_files_at(moved):
		DirAccess.remove_absolute(moved.path_join(file))
	DirAccess.remove_absolute(moved)


func test_locating_a_folder_linked_already_unlinks_it() -> void:
	var other := temp_path("other")
	DirAccess.make_dir_recursive_absolute(other)
	await add_folder()
	await main.files.add_sprites_from_folder(other)
	FolderWatcher.relocate(dir, other)
	assert_eq(Global.spritesheet.linked_folders, PackedStringArray([other]))
	assert_eq(Global.document.get_history()[-1], "Locate folder")
	DirAccess.remove_absolute(other)


func test_a_linked_folder_row_is_shaded_when_hovered() -> void:
	await add_folder()
	var row: Control = main.linked_folders.rows.get_child(0)
	var unlink := unlink_button_of(row)
	assert_eq(unlink.modulate.a, LinkedFolders.FAINT, "faint at first")
	row.mouse_entered.emit()
	assert_eq(unlink.modulate.a, 1.0)
	assert_true(row.has_theme_stylebox_override("panel"), "shaded")
	row.mouse_exited.emit()
	assert_eq(unlink.modulate.a, LinkedFolders.FAINT)
	assert_false(row.has_theme_stylebox_override("panel"))
	unlink.grab_focus()
	assert_eq(unlink.modulate.a, 1.0, "with focus too")
	unlink.release_focus()
