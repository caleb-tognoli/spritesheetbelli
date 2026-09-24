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
	var checks := window.find_children("*", "CheckBox", true, false)
	assert_true(checks.size() >= 4)
	var show_grid: CheckBox = checks[0]
	assert_true(show_grid.button_pressed)
	show_grid.button_pressed = false
	assert_false(Settings.get_value(&"show_grid"))
	Settings.reset_to_defaults()
	assert_true(show_grid.button_pressed, "controls follow the settings")
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
