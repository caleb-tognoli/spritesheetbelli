extends "res://tests/test_case.gd"

var main: Control
var preview: SpritesheetPreview


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE]:
		imgs.append(make_image(color))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	Global.document.perform("Grid", Global.spritesheet.set_grid_size.bind(Vector2i(4, 2)))
	preview.camera.position = Vector2.ZERO
	preview.set_zoom(4)


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


## Screen position of the centre of a cell (16 px cells at 4x zoom)
func at(cell: Vector2i) -> Vector2:
	return (Vector2(cell) * 16 + Vector2(8, 8)) * 4


func mouse(
	button: MouseButton, pressed: bool, pos: Vector2, ctrl := false, shift := false, alt := false
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = pos
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	preview._unhandled_input(event)


func move_to(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	preview._unhandled_input(event)


func click(cell: Vector2i, ctrl := false, shift := false) -> void:
	mouse(MOUSE_BUTTON_LEFT, true, at(cell), ctrl, shift)
	mouse(MOUSE_BUTTON_LEFT, false, at(cell), ctrl, shift)


func drag(from: Vector2, to: Vector2, ctrl := false, shift := false, alt := false) -> void:
	mouse(MOUSE_BUTTON_LEFT, true, from, ctrl, shift, alt)
	move_to(from.lerp(to, 0.5))
	move_to(to)
	mouse(MOUSE_BUTTON_LEFT, false, to, ctrl, shift, alt)


func selected() -> Array[Vector2i]:
	return preview.get_selected_coords()


func test_click_selects_one() -> void:
	click(Vector2i(1, 0))
	assert_eq(selected(), [Vector2i(1, 0)] as Array[Vector2i])
	click(Vector2i(2, 0))
	assert_eq(selected(), [Vector2i(2, 0)] as Array[Vector2i])


func test_ctrl_click_toggles() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(2, 0), true)
	assert_eq(selected().size(), 2)
	click(Vector2i(0, 0), true)
	assert_eq(selected(), [Vector2i(2, 0)] as Array[Vector2i])


func test_shift_click_selects_range() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(2, 0), false, true)
	assert_eq(selected().size(), 3)


func test_box_from_an_empty_cell() -> void:
	click(Vector2i(3, 0))
	drag(at(Vector2i(1, 1)), at(Vector2i(2, 0)))
	assert_eq(selected(), [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i], "replaces")
	assert_false(Global.spritesheet.is_locked(Vector2i(1, 1)), "a drag locks nothing")


func test_dragging_a_frame_moves_it() -> void:
	drag(at(Vector2i(0, 0)), at(Vector2i(1, 1)))
	var sheet := Global.spritesheet
	assert_false(sheet.has_frame(Vector2i(0, 0)))
	assert_color(sheet.frames[Vector2i(1, 1)], Vector2i.ZERO, Color.RED)
	assert_eq(selected(), [Vector2i(1, 1)] as Array[Vector2i], "selection follows")
	assert_eq(Global.document.get_history()[-1], "Move frames")
	Global.document.undo()
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "undoable")


func test_dragging_a_selected_frame_moves_the_selection() -> void:
	preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	drag(at(Vector2i(1, 0)), at(Vector2i(1, 1)))
	var sheet := Global.spritesheet
	assert_color(sheet.frames[Vector2i(0, 1)], Vector2i.ZERO, Color.RED)
	assert_color(sheet.frames[Vector2i(1, 1)], Vector2i.ZERO, Color.GREEN)
	assert_eq(selected(), [Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i])


func test_dragging_an_unselected_frame_moves_only_it() -> void:
	preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	drag(at(Vector2i(2, 0)), at(Vector2i(2, 1)))
	var sheet := Global.spritesheet
	assert_color(sheet.frames[Vector2i(2, 1)], Vector2i.ZERO, Color.BLUE)
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "the selection stays")
	assert_eq(selected(), [Vector2i(2, 1)] as Array[Vector2i], "the dragged frame is picked")


func test_alt_drag_moves_too() -> void:
	drag(at(Vector2i(0, 0)), at(Vector2i(0, 1)), false, false, true)
	var sheet := Global.spritesheet
	assert_false(sheet.has_frame(Vector2i(0, 0)), "no copy left behind")
	assert_color(sheet.frames[Vector2i(0, 1)], Vector2i.ZERO, Color.RED)


func test_shift_drag_from_a_frame_adds_a_box() -> void:
	click(Vector2i(3, 0))
	drag(at(Vector2i(0, 0)), at(Vector2i(1, 0)), false, true)
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "not moved")
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0)] as Array[Vector2i])


func test_ctrl_drag_from_a_frame_toggles_a_box() -> void:
	preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	drag(at(Vector2i(1, 0)), at(Vector2i(2, 0)), true)
	assert_color(Global.spritesheet.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.GREEN, "not moved")
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])


func test_dragging_selects_when_moving_is_off() -> void:
	preview.able_to_move_frames = false
	drag(at(Vector2i(0, 0)), at(Vector2i(1, 0)))
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "not moved")
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "box selection")
	move_to(at(Vector2i(2, 0)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.NONE, "nothing to grab")


func test_pressing_a_frame_moves_nothing_until_dragged() -> void:
	var some: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	preview.set_selected_coords(some)
	var steps := Global.document.get_history().size()
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(1, 0)))
	assert_true(preview._get_lifted_coords().is_empty(), "nothing lifted yet")
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.MOVE, "but a drag would move")
	move_to(at(Vector2i(1, 0)) + Vector2(2, 0))
	assert_true(preview._get_lifted_coords().is_empty(), "not past the threshold")
	mouse(MOUSE_BUTTON_LEFT, false, at(Vector2i(1, 0)))
	assert_eq(selected(), [Vector2i(1, 0)] as Array[Vector2i], "a click picks it alone")
	assert_eq(Global.document.get_history().size(), steps, "no step")


func test_cursor_follows_what_dragging_does() -> void:
	move_to(at(Vector2i(0, 0)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.GRAB, "over a frame")
	assert_eq(preview.surface.mouse_default_cursor_shape, Control.CURSOR_MOVE, "shown")
	move_to(at(Vector2i(3, 1)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.NONE, "over an empty cell")
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(3, 1)))
	move_to(at(Vector2i(2, 1)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.BOX, "drawing a box")
	mouse(MOUSE_BUTTON_LEFT, false, at(Vector2i(2, 1)))
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(0, 0)))
	move_to(at(Vector2i(1, 1)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.MOVE, "moving")
	mouse(MOUSE_BUTTON_LEFT, false, at(Vector2i(1, 1)))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	preview._unhandled_input(space)
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.PAN, "Space pans")
	space.pressed = false
	preview._unhandled_input(space)
	assert_eq(Input.get_current_cursor_shape(), Input.CURSOR_ARROW, "the app's own is left be")


func test_escape_puts_back_what_is_dragged() -> void:
	var steps := Global.document.get_history().size()
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(0, 0)))
	move_to(at(Vector2i(1, 1)))
	assert_false(preview._get_lifted_coords().is_empty())
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	preview._input(escape)
	assert_true(preview._get_lifted_coords().is_empty(), "put down")
	mouse(MOUSE_BUTTON_LEFT, false, at(Vector2i(1, 1)))
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "not moved")
	assert_eq(Global.document.get_history().size(), steps, "no step")


func test_selection_tint_setting() -> void:
	assert_eq(preview.selection_tint, 0.25, "25% by default, as before the setting")
	var import_preview: SpritesheetPreview = (
		main.files.add_spritesheet_window.preview_area.spritesheet_preview
	)
	Settings.set_value(&"selection_tint", 60)
	assert_eq(preview.selection_tint, 0.6)
	assert_eq(import_preview.selection_tint, 0.6, "Add Spritesheet too")
	Settings.set_value(&"selection_tint", Settings.DEFAULTS[&"selection_tint"])
	var window := SettingsWindow.new()
	add_child(window)
	assert_eq((window.get_control(&"selection_tint") as SpinBox).suffix, "%")
	window.queue_free()


func test_there_are_no_tools() -> void:
	for id: StringName in [&"tool_select", &"tool_move", &"tool_pivot"]:
		assert_false(Actions.has(id), id)
		assert_false(InputMap.has_action(id), "no shortcut: %s" % id)


func test_click_empty_cell_locks_it() -> void:
	click(Vector2i(3, 1))
	assert_true(Global.spritesheet.is_locked(Vector2i(3, 1)))
	click(Vector2i(3, 1))
	assert_false(Global.spritesheet.is_locked(Vector2i(3, 1)))


func test_click_empty_cell_keeps_the_selection() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(3, 1))
	assert_true(Global.spritesheet.is_locked(Vector2i(3, 1)), "locked")
	assert_eq(selected(), [Vector2i(0, 0)] as Array[Vector2i], "still selected")


func test_click_outside_the_grid_selects_nothing() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(6, 0))
	assert_true(selected().is_empty())
	assert_true(Global.spritesheet.locked_coordinates.is_empty(), "nothing locked")


func test_right_click_selects_frame_under_mouse() -> void:
	click(Vector2i(0, 0))
	mouse(MOUSE_BUTTON_RIGHT, true, at(Vector2i(2, 0)))
	assert_eq(selected(), [Vector2i(2, 0)] as Array[Vector2i])


func test_selection_dropped_when_frames_deleted() -> void:
	preview.select_all()
	Actions.run(&"delete_frames")
	assert_true(selected().is_empty())


func test_tooltip_describes_cells() -> void:
	var sheet := Global.spritesheet
	assert_true(PreviewArea.describe_cell(sheet, Vector2i(0, 0)).contains("16×16"))
	assert_true(PreviewArea.describe_cell(sheet, Vector2i(3, 1)).contains("lock"))
	assert_eq(PreviewArea.describe_cell(sheet, Vector2i(9, 9)), "")


func key(keycode: Key, shift := false, ctrl := false, alt := false) -> bool:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	return preview._handle_arrow_key(event)


func test_arrow_keys_move_frames() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(1, 0), true)
	key(KEY_RIGHT)
	var sheet := Global.spritesheet
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "selection kept")
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-7, -8), "a pixel right")
	assert_eq(sheet.get_frame_origin(Vector2i(1, 0)), Vector2i(-7, -8), "every selected frame")
	assert_false(sheet.has_frame_origin(Vector2i(2, 0)))
	key(KEY_UP, true)
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-7, -16), "8 pixels with Shift")


func test_ctrl_arrow_keys_add_to_the_selection() -> void:
	assert_true(key(KEY_RIGHT, false, true))
	assert_eq(selected(), [Vector2i(0, 0)] as Array[Vector2i], "first press selects a frame")
	key(KEY_RIGHT, false, true)
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "adds the next")
	key(KEY_DOWN, false, true)
	assert_eq(selected().size(), 2, "no frame below: stays")
	assert_false(sheet_moved(), "nothing nudged")


func sheet_moved() -> bool:
	for coord in Global.spritesheet.frames:
		if Global.spritesheet.has_frame_origin(coord):
			return true
	return false


func test_arrow_keys_leave_shortcuts_be() -> void:
	click(Vector2i(0, 0))
	assert_false(key(KEY_DOWN, true, true), "Ctrl+Shift moves rows")
	assert_false(key(KEY_LEFT, false, true, true), "Ctrl+Alt is for shortcuts")
	assert_true(key(KEY_LEFT, false, false, true), "Alt snaps to guides, here none")
	assert_false(key(KEY_LEFT, true, false, true), "Shift+Alt is for shortcuts")
	assert_false(sheet_moved())
	preview.able_to_move_frames = false
	assert_false(key(KEY_RIGHT), "nothing to nudge where frames can't move")


func test_cells_show_the_spacing_of_the_export() -> void:
	var sheet := Global.spritesheet
	var options := ExportOptions.from_sheet(sheet)
	options.padding = 4
	options.spacing = 2
	options.extrude = 1
	Global.document.perform("Spacing", sheet.set_export_settings.bind(options.to_dictionary()))
	for coord: Vector2i in [Vector2i(0, 0), Vector2i(3, 1)]:
		var exported := SpritesheetExporter.get_cell_rect(sheet, coord, options)
		assert_eq(preview.cell_rect(coord), Rect2(exported), "where the export puts it")
	# 16 px cells, 4 px step between them, 5 px before the first
	var second := preview.cell_rect(Vector2i(1, 0))
	assert_eq(second.position, Vector2(5 + 20, 5))
	assert_eq(preview.world_to_cell(second.get_center()), Vector2i(1, 0))
	assert_eq(preview.world_to_cell(second.position - Vector2(1, -1)), Vector2i(1, 0), "gap")
	assert_eq(preview.world_to_cell(second.position - Vector2(3, -1)), Vector2i(0, 0))
	Global.document.undo()
	assert_eq(preview.cell_rect(Vector2i(1, 0)).position, Vector2(16, 0), "follows undo")


func test_frames_dragged_out_and_back_move_in_the_sheet() -> void:
	assert_true(preview.drag_frames_out, "to drop them on a timeline")
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(0, 0)))
	move_to(at(Vector2i(1, 1)))
	move_to(Vector2(at(Vector2i(0, 0)).x, preview.get_viewport_rect().size.y + 20))
	assert_true(preview.mover.carried, "carried out")
	assert_true(get_viewport().gui_is_dragging(), "as dragged data")
	assert_true(preview._get_lifted_coords().is_empty(), "not shown in the sheet")
	var data: Variant = get_viewport().gui_get_drag_data()
	assert_true(preview._can_drop_back(at(Vector2i(2, 1)), data), "back over the sheet")
	assert_eq(preview._get_lifted_coords(), [Vector2i(0, 0)] as Array[Vector2i], "moving again")
	assert_false(preview.mover.card.visible, "only drawn where it'd land")
	preview.carry_away()
	assert_true(preview._get_lifted_coords().is_empty(), "off it again")
	assert_true(preview.mover.card.visible)
	assert_false(preview._can_drop_back(at(Vector2i(2, 1)), {"type": "other"}))
	preview._drop_back(at(Vector2i(2, 1)), data)
	get_viewport().gui_cancel_drag()
	var sheet := Global.spritesheet
	assert_false(sheet.has_frame(Vector2i(0, 0)))
	assert_color(sheet.frames[Vector2i(2, 1)], Vector2i.ZERO, Color.RED, "moved where dropped")
	assert_false(preview.mover.carried, "put down")
