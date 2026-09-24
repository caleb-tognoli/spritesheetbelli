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
	assert_eq(menu_bar.get_menu_count(), 4)
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
