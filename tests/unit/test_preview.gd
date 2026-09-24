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


func drag(from: Vector2, to: Vector2, alt := false) -> void:
	mouse(MOUSE_BUTTON_LEFT, true, from)
	move_to(from.lerp(to, 0.5))
	move_to(to)
	mouse(MOUSE_BUTTON_LEFT, false, to, false, false, alt)


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


func test_box_selection() -> void:
	drag(at(Vector2i(1, 1)), at(Vector2i(2, 0)))
	assert_eq(selected(), [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])


func test_dragging_frames_moves_them() -> void:
	click(Vector2i(0, 0))
	drag(at(Vector2i(0, 0)), at(Vector2i(1, 1)))
	var sheet := Global.spritesheet
	assert_false(sheet.has_frame(Vector2i(0, 0)))
	assert_color(sheet.frames[Vector2i(1, 1)], Vector2i.ZERO, Color.RED)
	assert_eq(selected(), [Vector2i(1, 1)] as Array[Vector2i], "selection follows")
	Global.document.undo()
	assert_color(sheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "undoable")


func test_dragging_selects_when_moving_is_off() -> void:
	preview.able_to_move_frames = false
	drag(at(Vector2i(0, 0)), at(Vector2i(1, 0)))
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED, "not moved")
	assert_eq(selected(), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "box selection")


func test_alt_drag_copies() -> void:
	drag(at(Vector2i(0, 0)), at(Vector2i(0, 1)), true)
	assert_color(Global.spritesheet.frames[Vector2i(0, 0)], Vector2i.ZERO, Color.RED)
	assert_color(Global.spritesheet.frames[Vector2i(0, 1)], Vector2i.ZERO, Color.RED)


func test_click_empty_cell_locks_it() -> void:
	click(Vector2i(3, 1))
	assert_true(Global.spritesheet.is_locked(Vector2i(3, 1)))
	click(Vector2i(3, 1))
	assert_false(Global.spritesheet.is_locked(Vector2i(3, 1)))


func test_click_empty_cell_first_clears_selection() -> void:
	click(Vector2i(0, 0))
	click(Vector2i(3, 1))
	assert_true(selected().is_empty())
	assert_false(Global.spritesheet.is_locked(Vector2i(3, 1)))


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


func key(keycode: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	preview._unhandled_input(event)


func test_arrow_keys_move_selection() -> void:
	key(KEY_RIGHT)
	assert_eq(selected(), [Vector2i(0, 0)] as Array[Vector2i], "first press selects a frame")
	key(KEY_RIGHT)
	assert_eq(selected(), [Vector2i(1, 0)] as Array[Vector2i])
	key(KEY_RIGHT, true)
	assert_eq(selected(), [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i], "shift extends")
	key(KEY_DOWN)
	assert_eq(selected(), [Vector2i(2, 0)] as Array[Vector2i], "no frame below: stays")
