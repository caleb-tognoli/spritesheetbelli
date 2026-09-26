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


func test_rows_with_names_are_headers() -> void:
	sheet.set_row_name(0, "items")
	var header := panel.tree.get_root().get_first_child()
	assert_eq(header.get_text(0), "items")
	assert_eq(header.get_child_count(), 3)


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


func test_only_names_are_edited() -> void:
	var item := item_of(Vector2i(0, 0))
	panel.tree.set_selected(item, 1)
	panel._edit_selected()
	assert_eq(panel.tree.get_selected_column(), 0, "the name, not the size")
	assert_false(item.is_editable(1))
