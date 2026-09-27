extends "res://tests/test_case.gd"

var main: Control
var sheet: Spritesheet
var panel: SpritesPanel


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	panel = main.layout_controller.sprites_panel
	var images: Array[Image] = []
	for entry: Array in [["star", Color.YELLOW], ["bean", Color.TAN], ["", Color.RED]]:
		var img := make_image(entry[1], Vector2i(12, 8))
		img.resource_name = entry[0]
		images.append(img)
	Global.document.perform("Add", sheet.add_frames.bind(images))
	Settings.set_value(&"show_sprites", true)
	await get_tree().process_frame


func after_each() -> void:
	Settings.set_value(&"show_sprites", false)
	main.queue_free()
	Global.document.reset()


## The frames listed, as their labels
func labels() -> Array[String]:
	var result: Array[String] = []
	var item := panel.tree.get_root().get_next_in_tree()
	while item:
		if item.get_metadata(0) is Vector2i:
			result.append(item.get_text(0))
		item = item.get_next_in_tree()
	return result


func item_of(coord: Vector2i) -> TreeItem:
	var item := panel.tree.get_root().get_next_in_tree()
	while item:
		if item.get_metadata(0) == coord:
			return item
		item = item.get_next_in_tree()
	return null


func test_frames_are_listed() -> void:
	assert_true(panel.is_visible_in_tree())
	assert_eq(labels(), ["star", "bean", "Frame 2"] as Array[String])
	assert_eq(item_of(Vector2i(0, 0)).get_text(1), "12×8")
	assert_false(item_of(Vector2i(0, 0)).is_selectable(1), "sizes can't be clicked")
	Actions.run(&"toggle_sprites")
	assert_false(panel.visible, "hidden")
	assert_false(main.layout_controller.side_split.visible, "with the history hidden too")


func test_selection_goes_both_ways() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(panel.get_selected_coords(), [Vector2i(1, 0)] as Array[Vector2i])
	item_of(Vector2i(2, 0)).select(0)
	panel.tree.multi_selected.emit(item_of(Vector2i(2, 0)), 0, true)
	assert_eq(
		main.preview.get_selected_coords(),
		[Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i],
		"the preview follows"
	)


func test_the_cursor_follows_the_preview() -> void:
	main.preview.set_selected_coords([Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(panel.tree.get_selected(), item_of(Vector2i(1, 0)), "on the first selected")
	main.preview.set_selected_coords([] as Array[Vector2i])
	assert_true(panel.tree.get_selected() == null, "on none")
	assert_true(
		panel.tree.get_theme_stylebox("cursor_unfocused") is StyleBoxEmpty, "only drawn with focus"
	)


func test_the_whole_row_is_highlighted() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	var item := item_of(Vector2i(1, 0))
	assert_true(item.get_custom_stylebox(0) is StyleBoxFlat, "the name")
	assert_true(item.get_custom_stylebox(1) is StyleBoxFlat, "the size")
	assert_true(item_of(Vector2i(0, 0)).get_custom_stylebox(0) == null)
	assert_true(
		panel.tree.get_theme_stylebox("selected") is StyleBoxEmpty, "not cell by cell as well"
	)
	# Picked in the list
	panel.tree.set_selected(item_of(Vector2i(0, 0)), 0)
	assert_true(item_of(Vector2i(0, 0)).get_custom_stylebox(1) is StyleBoxFlat)
	assert_true(item.get_custom_stylebox(1) == null, "no longer selected")
	Actions.run(&"layout_packed")
	var box: StyleBoxFlat = item_of(Vector2i(0, 0)).get_custom_stylebox(1)
	assert_true(box.expand_margin_right > 0, "over the pin too")


func test_the_row_is_highlighted_in_the_selection_colours() -> void:
	main.preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	var item := item_of(Vector2i(1, 0))
	var name_box := item.get_custom_stylebox(0) as StyleBoxFlat
	var selected := panel.get_theme_stylebox("selected", &"Tree") as StyleBoxFlat
	assert_eq(name_box.bg_color, selected.bg_color, "the theme's selection")
	var text := panel.get_theme_color("font_selected_color", &"Tree")
	assert_eq(item.get_custom_color(1), text, "the size in the selection's text colour")
	assert_ne(item_of(Vector2i(0, 0)).get_custom_color(1), text, "only when selected")
	panel.tree.grab_focus()
	var focused := panel.get_theme_stylebox("selected_focus", &"Tree") as StyleBoxFlat
	name_box = item.get_custom_stylebox(0) as StyleBoxFlat
	assert_eq(name_box.bg_color, focused.bg_color, "stronger while the list has focus")
	panel.tree.release_focus()
	name_box = item.get_custom_stylebox(0) as StyleBoxFlat
	assert_eq(name_box.bg_color, selected.bg_color, "back without focus")
	# A new accent colours the selection too
	var accent: Color = Settings.get_value(&"accent_color")
	Settings.set_value(&"accent_color", Color.ORANGE)
	selected = panel.get_theme_stylebox("selected", &"Tree") as StyleBoxFlat
	name_box = item_of(Vector2i(1, 0)).get_custom_stylebox(0) as StyleBoxFlat
	assert_eq(name_box.bg_color, selected.bg_color, "follows the accent")
	assert_true(selected.bg_color.r > selected.bg_color.b, "orange")
	Settings.set_value(&"accent_color", accent)


func test_search() -> void:
	panel.search.text = "EA"
	panel.search.text_changed.emit("EA")
	assert_eq(labels(), ["bean"] as Array[String])


func test_renaming() -> void:
	var item := item_of(Vector2i(0, 0))
	# As if the name was typed in the list
	item.set_text(0, " big star ")
	panel._rename(item)
	assert_eq(sheet.frames[Vector2i(0, 0)].resource_name, "big star")
	assert_true("big star" in labels(), "listed with the new name")
	Global.document.undo()
	assert_eq(sheet.frames[Vector2i(0, 0)].resource_name, "star")


func test_pins_in_the_packed_layout() -> void:
	assert_eq(item_of(Vector2i(0, 0)).get_button_count(1), 0, "no pins in the grid")
	Actions.run(&"layout_packed")
	var item := item_of(Vector2i(0, 0))
	assert_eq(item.get_button_count(1), 1)
	panel.tree.button_clicked.emit(item, 1, SpritesPanel.PIN_BUTTON, MOUSE_BUTTON_LEFT)
	assert_true(sheet.placements[Vector2i(0, 0)].pinned)
	Global.document.undo()
	assert_false(sheet.placements[Vector2i(0, 0)].pinned)


func test_double_clicking_a_size_does_nothing() -> void:
	await get_tree().process_frame
	panel.tree.set_selected(item_of(Vector2i(2, 0)), 0)
	var item := item_of(Vector2i(0, 0))
	var at := panel.tree.get_item_area_rect(item, 1).get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = at
	var activated := [false]
	panel.tree.item_activated.connect(func() -> void: activated[0] = true)
	panel.tree.gui_input.emit(click)
	assert_true(panel.tree.get_viewport().is_input_handled(), "swallowed")
	assert_false(activated[0])
	assert_false(item_of(Vector2i(2, 0)).is_editable(0), "no other frame is renamed")


func test_only_names_are_edited() -> void:
	var item := item_of(Vector2i(0, 0))
	panel.tree.set_selected(item, 0)
	# The cursor moved onto the size with the keyboard
	panel.tree.grab_focus()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	panel.tree.get_viewport().push_input(right)
	assert_eq(panel.tree.get_selected_column(), 1)
	panel._edit_selected()
	assert_eq(panel.tree.get_selected_column(), 0, "the name, not the size")
	assert_false(item.is_editable(1))
