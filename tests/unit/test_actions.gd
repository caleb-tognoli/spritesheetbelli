extends "res://tests/test_case.gd"

var main: Control


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Global.spritesheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


func press(keycode: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.command_or_control_autoremap = ctrl
	event.shift_pressed = shift
	get_viewport().push_input(event)
	await get_tree().process_frame


func test_menus_are_built_from_actions() -> void:
	await get_tree().process_frame
	var menu_bar: MenuBar = main.get_node("%MenuBar")
	assert_eq(menu_bar.get_menu_count(), MainMenuBar.MENUS.size())
	var file: PopupMenu = menu_bar.get_child(0)
	assert_eq(file.get_item_text(0), "New")
	assert_ne(file.get_item_shortcut(0), null, "shortcut shown in menu")


func test_select_all_and_flip_keep_selection() -> void:
	Actions.run(&"select_all")
	assert_eq(main.preview.get_selected_coords().size(), 3)
	var before: Image = Global.spritesheet.frames[Vector2i.ZERO]
	Actions.run(&"flip_h")
	assert_ne(Global.spritesheet.frames[Vector2i.ZERO], before, "frame replaced")
	await get_tree().process_frame
	assert_eq(main.preview.get_selected_coords().size(), 3, "selection kept after rebuild")


func test_actions_need_a_selection() -> void:
	assert_false(Actions.is_enabled(&"delete_frames"))
	assert_false(Actions.run(&"delete_frames"))
	Actions.run(&"select_all")
	assert_true(Actions.is_enabled(&"delete_frames"))


func test_delete_shortcut() -> void:
	Actions.run(&"select_all")
	await get_tree().process_frame
	await press(KEY_DELETE)
	assert_true(Global.spritesheet.is_empty())


func test_ctrl_a_selects_all() -> void:
	await press(KEY_A, true)
	assert_eq(main.preview.get_selected_coords().size(), 3)


func test_shortcut_text() -> void:
	assert_eq(Actions.get_shortcut_text(&"save_as"), "Ctrl+Shift+S")


func test_shortcuts_dialog_lists_actions() -> void:
	main.shortcuts_dialog.popup_centered()
	var labels: Array[String] = []
	for child: Label in main.shortcuts_dialog.find_children("*", "Label", true, false):
		labels.append(child.text)
	assert_true("Ctrl+Shift+S" in labels)
	main.shortcuts_dialog.hide()


func test_undo_redo_shortcuts() -> void:
	Actions.run(&"select_all")
	Actions.run(&"delete_frames")
	assert_true(Global.spritesheet.is_empty())
	await get_tree().process_frame
	await press(KEY_Z, true)
	assert_eq(Global.spritesheet.frames.size(), 3, "Ctrl+Z")
	await get_tree().process_frame
	await press(KEY_Z, true, true)
	assert_true(Global.spritesheet.is_empty(), "Ctrl+Shift+Z")


func test_copy_paste() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"copy")
	assert_true(Actions.run(&"paste"))
	assert_eq(Global.spritesheet.frames.size(), 4)
	assert_color(Global.spritesheet.frames[Vector2i(3, 0)], Vector2i.ZERO, Color.GREEN)
	assert_eq(
		main.preview.get_selected_coords(),
		[Vector2i(3, 0)] as Array[Vector2i],
		"pasted frames selected"
	)


func test_cut() -> void:
	main.preview.set_selected_coords([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"cut")
	assert_false(Global.spritesheet.has_frame(Vector2i(0, 0)))
	Actions.run(&"paste")
	assert_color(
		Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "fills the gap"
	)


func test_duplicate() -> void:
	Actions.run(&"select_all")
	Actions.run(&"duplicate")
	assert_eq(Global.spritesheet.frames.size(), 6)
	Global.document.undo()
	assert_eq(Global.spritesheet.frames.size(), 3, "one undo step")


func test_insert_and_remove_cell() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"insert_cell")
	assert_false(Global.spritesheet.has_frame(Vector2i(1, 0)))
	assert_color(Global.spritesheet.frames[Vector2i(2, 0)], Vector2i.ZERO, Color.GREEN)
	main.preview.set_selected_coords([Vector2i(2, 0)] as Array[Vector2i])
	Actions.run(&"remove_cell")
	assert_color(Global.spritesheet.frames[Vector2i(2, 0)], Vector2i.ZERO, Color.BLUE)


func test_trim_and_color_key_actions() -> void:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.fill_rect(Rect2i(4, 4, 8, 8), Color.RED)
	Global.document.perform("Add", Global.spritesheet.add_frames.bind([img] as Array[Image]))
	main.preview.set_selected_coords([Vector2i(3, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	assert_eq(main.color_key_dialog.picker.color, Color.MAGENTA, "suggests the corner colour")
	main.color_key_dialog.confirmed.emit()
	main.color_key_dialog.hide()
	Actions.run(&"trim")
	assert_eq(Global.spritesheet.frames[Vector2i(3, 0)].get_size(), Vector2i(8, 8))


func test_name_row() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"name_row")
	assert_true(main.row_name_dialog.visible)
	main.row_name_dialog.line_edit.text = "walk"
	main.row_name_dialog.confirmed.emit()
	main.row_name_dialog.hide()
	assert_eq(Global.spritesheet.row_names.get(0), "walk")
	Global.document.undo()
	assert_false(Global.spritesheet.row_names.has(0))
