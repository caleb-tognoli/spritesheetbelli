extends "res://tests/test_case.gd"
## Animation from Row, Column and Selection, and the Animation menu

var main: Control
var sheet: Spritesheet
var commands: AnimationCommands
var dialog: AnimationNameDialog


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	commands = main.animation_commands
	dialog = commands.dialog
	# A 3×2 grid: slime_walk_00 to 02 in the first row, jump_0, an empty cell and an
	# unnamed frame in the second
	Global.document.perform(
		"Add",
		func() -> void:
			sheet.set_grid_size(Vector2i(3, 2))
			for entry: Array in [
				[Vector2i(0, 0), "slime_walk_00.png"],
				[Vector2i(1, 0), "slime_walk_01.png"],
				[Vector2i(2, 0), "slime_walk_02.png"],
				[Vector2i(0, 1), "jump_0.png"],
				[Vector2i(2, 1), ""],
			]:
				var img := make_image(Color.RED)
				img.resource_name = entry[1]
				sheet.set_frame(entry[0], img)
	)
	await get_tree().process_frame


func after_each() -> void:
	dialog.hide()
	main.queue_free()
	Global.document.reset()


func select(coords: Array[Vector2i]) -> void:
	main.preview.set_selected_coords(coords)


## Types [param text] in the open dialog and presses its OK button
func confirm(text := "") -> void:
	assert_true(dialog.visible, "the dialog asks for a name")
	if text:
		dialog.line_edit.text = text
	dialog.confirmed.emit()
	dialog.hide()


func press(keycode: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.command_or_control_autoremap = ctrl
	event.shift_pressed = shift
	get_viewport().push_input(event)
	await get_tree().process_frame


func test_default_names() -> void:
	var name_of := func(names: Array, taken: Array = []) -> String:
		return SheetAnimation.default_name(PackedStringArray(names), PackedStringArray(taken))
	assert_eq(name_of.call(["slime_walk_00", "slime_walk_05"]), "slime_walk", "prefix trimmed")
	assert_eq(name_of.call(["walk_10.png", "walk_11.png"]), "walk", "without the extension")
	assert_eq(name_of.call(["idle"]), "idle", "one frame")
	assert_eq(name_of.call(["hero-run.3", "hero-run.4"]), "hero-run", "dots and dashes")
	assert_eq(name_of.call(["walk 1", "walk 2"]), "walk", "spaces")
	assert_eq(name_of.call(["walk_0", "walk_1"], ["walk"]), "walk_2", "made unique")
	assert_eq(name_of.call(["walk_0"], ["walk", "walk_2"]), "walk_3")
	assert_eq(name_of.call(["walk", "jump"]), "animation", "nothing in common")
	assert_eq(name_of.call(["01", "02"]), "animation", "only numbers")
	assert_eq(name_of.call(["", ""]), "animation", "frames without names")
	assert_eq(name_of.call([]), "animation")
	assert_eq(name_of.call(["", "walk_0", "", "walk_1"]), "walk", "unnamed frames left out")
	assert_eq(name_of.call([""], ["animation"]), "animation_2")


func test_animation_from_row() -> void:
	select([Vector2i(1, 0)] as Array[Vector2i])
	assert_true(Actions.run(&"animation_from_row"))
	assert_eq(dialog.line_edit.text, "slime_walk", "named after the frames")
	assert_eq(dialog.line_edit.get_selected_text(), "slime_walk", "picked, so typing replaces it")
	confirm()
	assert_eq(sheet.animations.size(), 1)
	var animation := sheet.animations[0]
	assert_eq(animation.name, "slime_walk")
	assert_eq(animation.cells, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(main.animation_panel.get_selected(), 0, "chosen in the animation panel")
	assert_eq(main.animation_panel.detail.get_animation_index(), 0, "to edit")
	Global.document.undo()
	assert_true(sheet.animations.is_empty(), "one undo step")


func test_empty_cells_are_skipped() -> void:
	select([Vector2i(0, 1)] as Array[Vector2i])
	Actions.run(&"animation_from_row")
	confirm("hop")
	assert_eq(sheet.animations[0].cells, [Vector2i(0, 1), Vector2i(2, 1)] as Array[Vector2i])
	assert_eq(sheet.animations[0].name, "hop", "the name typed")


func test_animation_from_column() -> void:
	select([Vector2i(0, 1)] as Array[Vector2i])
	Actions.run(&"animation_from_column")
	assert_eq(dialog.line_edit.text, "animation", "the names have nothing in common")
	confirm()
	assert_eq(sheet.animations[0].cells, [Vector2i(0, 0), Vector2i(0, 1)] as Array[Vector2i])


func test_animation_from_selection() -> void:
	select([Vector2i(2, 1), Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	Actions.run(&"animation_from_selection")
	assert_eq(dialog.line_edit.text, "slime_walk", "the unnamed frame is left out")
	confirm()
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 1)] as Array[Vector2i],
		"in reading order"
	)


func test_the_same_frames_again_rename() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"animation_from_row")
	confirm()
	Actions.run(&"animation_from_row")
	assert_eq(dialog.title, "Rename Animation")
	assert_eq(dialog.line_edit.text, "slime_walk", "its name to change")
	confirm("walk_right")
	assert_eq(sheet.animations.size(), 1, "not made twice")
	assert_eq(sheet.animations[0].name, "walk_right")
	Global.document.undo()
	assert_eq(sheet.animations[0].name, "slime_walk", "one undo step")
	# Other frames make another animation, with a name of its own
	select([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"animation_from_selection")
	assert_eq(dialog.title, "New Animation")
	assert_eq(dialog.line_edit.text, "slime_walk_2")
	confirm()
	assert_eq(sheet.animations.size(), 2)


func test_empty_names_are_not_taken() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"animation_from_row")
	dialog.line_edit.text = "  "
	dialog.line_edit.text_changed.emit("  ")
	assert_true(dialog.get_ok_button().disabled)
	confirm()
	assert_true(sheet.animations.is_empty())


func test_rows_and_columns_need_a_frame() -> void:
	assert_false(Actions.is_enabled(&"animation_from_row"), "nothing selected")
	assert_false(Actions.is_enabled(&"animation_from_selection"))
	select([Vector2i(0, 0)] as Array[Vector2i])
	assert_true(Actions.is_enabled(&"animation_from_row"))
	assert_true(Actions.is_enabled(&"animation_from_column"))


func test_right_clicked_cell() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	main.preview.hovered_cell = Vector2i(1, 1)
	var menu: PopupMenu = main.preview_area.options_menu
	menu.about_to_popup.emit()
	Actions.run(&"animation_from_column")
	menu.popup_hide.emit()
	confirm()
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(1, 0)] as Array[Vector2i],
		"the column of the right-clicked cell, not of the selection"
	)
	await get_tree().process_frame
	assert_eq(commands.menu_cell, SpritesheetPreview.NO_CELL, "forgotten once the menu is closed")
	Actions.run(&"animation_from_column")
	confirm()
	assert_eq(sheet.animations[1].cells, [Vector2i(0, 0), Vector2i(0, 1)] as Array[Vector2i])


func test_packed_layout_has_no_rows() -> void:
	Actions.run(&"layout_packed")
	select([Vector2i(0, 0)] as Array[Vector2i])
	assert_false(Actions.is_available(&"animation_from_row"))
	assert_false(Actions.is_available(&"animation_from_column"))
	assert_true(Actions.is_enabled(&"animation_from_selection"))


func test_shortcuts() -> void:
	assert_eq(Actions.get_shortcut_text(&"animation_from_row"), "F2")
	assert_eq(Actions.get_shortcut_text(&"animation_from_column"), "Shift+F2")
	assert_eq(Actions.get_shortcut_text(&"animation_from_selection"), "Ctrl+F2")
	select([Vector2i(1, 0)] as Array[Vector2i])
	await get_tree().process_frame
	for entry: Array in [
		[false, true, [Vector2i(1, 0)]],
		[true, false, [Vector2i(1, 0)]],
		[false, false, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]],
	]:
		await press(KEY_F2, entry[0], entry[1])
		confirm()
		var cells: Array[Vector2i] = []
		cells.assign(entry[2])
		assert_eq(sheet.animations[-1].cells, cells)
		await get_tree().process_frame
	assert_eq(sheet.animations.size(), 2, "the column of one frame is the selection, renamed")


func test_menus() -> void:
	await get_tree().process_frame
	var ids := []
	var menu: PopupMenu = main.get_node("%MenuBar").get_node("Animation")
	for i in menu.item_count:
		ids.append(menu.get_item_metadata(i))
	for id: StringName in [
		&"animation_from_row",
		&"animation_from_selection",
		&"edit_animations",
		&"duplicate_animation",
		&"mirror_animation",
		&"toggle_animation",
		&"toggle_onion_skin",
	]:
		assert_true(id in ids, "%s in the Animation menu" % id)
	# Each action is in one menu, so F1 lists it once
	var seen := {}
	for title: String in MainMenuBar.MENUS:
		for id: StringName in MainMenuBar.MENUS[title]:
			var inside: Array = (
				MainMenuBar.SUBMENUS[id][1] if MainMenuBar.SUBMENUS.has(id) else [id]
			)
			for each: StringName in inside:
				if not each.is_empty():
					assert_false(seen.has(each), "%s is listed once" % each)
					seen[each] = true
	var sprites: SpritesPanel = main.layout_controller.sprites_panel
	assert_eq(sprites.context_menu.get_item_metadata(0), &"animation_from_selection")
	assert_true(&"animation_menu" in main.CONTEXT_ACTIONS)


func test_mirror_and_delete_the_chosen_animation() -> void:
	assert_false(Actions.is_enabled(&"mirror_animation"), "no animation")
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"animation_from_row")
	confirm("walk_right")
	assert_true(Actions.run(&"mirror_animation"))
	assert_eq(sheet.animations.size(), 2)
	assert_eq(sheet.animations[1].name, "walk_left")
	assert_eq(main.animation_panel.get_selected(), 1, "the copy is chosen")
	assert_true(Actions.run(&"delete_animation"))
	assert_eq(sheet.animations.size(), 1)
	assert_eq(sheet.animations[0].name, "walk_right", "the copy deleted")
	assert_eq(main.animation_panel.get_selected(), 0, "then the one before it, as in the panel")
	Global.document.undo()
	assert_eq(sheet.animations.size(), 2, "one undo step")
	main.animation_panel.select_animation(-1)
	assert_false(Actions.is_enabled(&"mirror_animation"), "the selected frames are chosen")
	assert_false(Actions.is_enabled(&"delete_animation"))


func test_onion_skin() -> void:
	var before: bool = Settings.get_value(&"onion_skin")
	Actions.run(&"toggle_onion_skin")
	assert_eq(Settings.get_value(&"onion_skin"), not before)
	assert_eq(Actions.is_checked(&"toggle_onion_skin"), not before)
	Settings.set_value(&"onion_skin", before)


func test_sprites_panel_menu() -> void:
	Settings.set_value(&"show_sprites", true)
	await get_tree().process_frame
	var panel: SpritesPanel = main.layout_controller.sprites_panel
	var tree := panel.tree
	select([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	await get_tree().process_frame
	var right_click := func(coord: Vector2i) -> void:
		# Frames are listed under their group's name
		var item := tree.get_root().get_next_in_tree()
		while not (item.get_metadata(0) is Vector2i and item.get_metadata(0) == coord):
			item = item.get_next_in_tree()
		var pos := tree.get_global_transform() * tree.get_item_area_rect(item).get_center()
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_RIGHT
			event.pressed = pressed
			event.position = pos
			event.global_position = pos
			get_viewport().push_input(event)
	right_click.call(Vector2i(1, 0))
	await get_tree().process_frame
	assert_eq(
		main.preview.get_selected_coords(),
		[Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i],
		"a selected frame keeps the selection"
	)
	assert_true(panel.context_menu.visible, "the menu opens")
	panel.context_menu.hide()
	right_click.call(Vector2i(2, 0))
	await get_tree().process_frame
	assert_eq(main.preview.get_selected_coords(), [Vector2i(2, 0)] as Array[Vector2i])
	panel.context_menu.hide()
	# F2 renames the frame there, and Ctrl+F2 still makes an animation
	tree.grab_focus()
	await press(KEY_F2, true)
	confirm()
	assert_eq(sheet.animations[0].cells, [Vector2i(2, 0)] as Array[Vector2i])
	assert_false(tree.get_selected().is_editable(0), "not renamed")
	Settings.set_value(&"show_sprites", false)


func test_right_clicking_the_preview() -> void:
	var preview: SpritesheetPreview = main.preview
	var container: Control = main.preview_area.container
	select([Vector2i(0, 0)] as Array[Vector2i])
	await get_tree().process_frame
	var world := preview.cell_rect(Vector2i(1, 1)).get_center()
	var pos := (
		container.get_global_transform() * ((world - preview.camera.position) * preview.camera.zoom)
	)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = pos
		event.global_position = pos
		get_viewport().push_input(event)
	await get_tree().process_frame
	assert_true(main.preview_area.options_menu.visible, "the menu opens")
	assert_eq(commands.menu_cell, Vector2i(1, 1), "on the empty cell right-clicked")
	# Picking from its Animation submenu hides the menus, then runs the action
	for submenu: ActionPopupMenu in main.preview_area.options_menu._action_submenus:
		for i in submenu.item_count:
			if submenu.get_item_metadata(i) == &"animation_from_column":
				main.preview_area.options_menu.hide()
				submenu.index_pressed.emit(i)
	await get_tree().process_frame
	assert_false(main.preview_area.options_menu.visible)
	assert_eq(commands.menu_cell, SpritesheetPreview.NO_CELL, "forgotten")
	confirm()
	assert_eq(sheet.animations[0].cells, [Vector2i(1, 0)] as Array[Vector2i], "its column")
