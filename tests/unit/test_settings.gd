extends "res://tests/test_case.gd"


func after_each() -> void:
	Settings.reset_to_defaults()


func test_values_persist_to_file() -> void:
	Settings.set_value(&"checker_size", 16)
	Settings.load_settings(Settings.path)
	assert_eq(Settings.get_value(&"checker_size"), 16)


func test_values_keep_their_type() -> void:
	Settings.set_value(&"checker_size", 12.0)
	assert_eq(typeof(Settings.get_value(&"checker_size")), TYPE_INT)


func test_changed_signal() -> void:
	var keys: Array[StringName] = []
	var on_changed := func(key: StringName) -> void: keys.append(key)
	Settings.changed.connect(on_changed)
	Settings.set_value(&"show_grid", false)
	Settings.set_value(&"show_grid", false)
	Settings.changed.disconnect(on_changed)
	assert_eq(keys, [&"show_grid"] as Array[StringName], "only real changes")


func test_window_edits_settings() -> void:
	var window := SettingsWindow.new()
	add_child(window)
	window.popup_centered()
	window.show_category("Preview")
	var show_grid := window.get_control(&"show_grid") as CheckBox
	assert_true(show_grid.is_visible_in_tree(), "the category's settings are shown")
	assert_false(window.get_control(&"theme").is_visible_in_tree(), "others are not")
	assert_true(show_grid.button_pressed)
	assert_false(window.get_revert_button(&"show_grid").visible, "at its default")
	show_grid.button_pressed = false
	assert_false(Settings.get_value(&"show_grid"))
	assert_true(window.get_revert_button(&"show_grid").visible, "can be reverted")
	window.get_revert_button(&"show_grid").pressed.emit()
	assert_true(Settings.get_value(&"show_grid"))

	show_grid.button_pressed = false
	window.custom_action.emit(&"reset")
	assert_true(Notify.confirm_dialog.visible, "asks before resetting everything")
	assert_false(Settings.get_value(&"show_grid"))
	Notify.confirm_dialog.confirmed.emit()
	Notify.confirm_dialog.hide()
	assert_true(show_grid.button_pressed, "controls follow the settings")

	window.search.text = "colour"
	window.search.text_changed.emit("colour")
	assert_true(window.get_control(&"grid_color").is_visible_in_tree())
	assert_true(window.get_control(&"accent_color").is_visible_in_tree(), "from all categories")
	assert_false(show_grid.is_visible_in_tree())
	window.queue_free()


func test_index_start_used_in_export() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	var dir := OS.get_user_data_dir().path_join("tests/index_start")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	SpritesheetExporter.export_sprites(sheet, dir, [], 1)
	assert_true(FileAccess.file_exists(dir.path_join("1.png")))


func test_add_mode_new_row() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	sheet.add_frames(
		[make_image(Color.BLUE), make_image(Color.BLUE)] as Array[Image],
		Spritesheet.AddMode.NEW_ROW
	)
	assert_true(sheet.has_frame(Vector2i(0, 1)))
	assert_true(sheet.has_frame(Vector2i(1, 1)))


func test_recent_files() -> void:
	Settings.clear_recent_files()
	for i in 12:
		Settings.add_recent_file("file%d.sbelli" % i)
	Settings.add_recent_file("file5.sbelli")
	var recent := Settings.get_recent_files()
	assert_eq(recent.size(), Settings.MAX_RECENT_FILES)
	assert_eq(recent[0], "file5.sbelli", "most recent first, no duplicates")
	assert_eq(recent.count("file5.sbelli"), 1)
	Settings.clear_recent_files()


func test_recent_files_menu() -> void:
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var path := OS.get_user_data_dir().path_join("tests/recent.sbelli")
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	ProjectFile.save(sheet, path)
	Settings.clear_recent_files()
	Settings.add_recent_file(path)
	var menu: RecentFilesMenu = main.get_node("%MenuBar").recent_files
	menu.refresh()
	assert_eq(menu.get_item_text(0), "recent.sbelli  (%s)" % path.get_base_dir())
	menu.id_pressed.emit(0)
	assert_eq(Global.document.path, path, "opened")
	assert_eq(Global.spritesheet.frames.size(), 1)
	menu.id_pressed.emit(RecentFilesMenu.CLEAR_ID)
	assert_true(Settings.get_recent_files().is_empty())
	main.queue_free()
	Global.document.reset()


func test_messages_open_over_modal_windows() -> void:
	var window := SettingsWindow.new()
	add_child(window)
	window.popup_centered()
	window.custom_action.emit(&"reset")
	assert_true(Notify.confirm_dialog.visible)
	assert_eq(Notify.confirm_dialog.get_parent(), window, "shown over the settings")
	Notify.confirm_dialog.hide()
	await get_tree().process_frame
	assert_eq(Notify.confirm_dialog.get_parent(), Notify, "back once closed")
	window.queue_free()
	await get_tree().process_frame
	assert_true(is_instance_valid(Notify.confirm_dialog))
