extends "res://tests/test_case.gd"

var main: Control
var preview: SpritesheetPreview
var rulers: Rulers


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	rulers = main.preview_area.rulers
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE]:
		imgs.append(make_image(color))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	Global.document.perform("Grid", Global.spritesheet.set_grid_size.bind(Vector2i(4, 2)))
	Settings.set_value(&"show_rulers", true)
	# 16 px cells at 4x zoom, the sheet's corner 40 px from the view's, past the rulers
	preview.set_zoom(4)
	preview.camera.position = Vector2(-10, -10)


func after_each() -> void:
	Settings.set_value(&"show_rulers", false)
	main.queue_free()
	Global.document.reset()


## Where [param world] is in the view, the same in the rulers
func screen(world: Vector2) -> Vector2:
	return (world + Vector2(10, 10)) * 4


## The middle of the left ruler at [param y] pixels of the sheet, or of the top one at x
func on_left(y: float) -> Vector2:
	return Vector2(Rulers.WIDTH / 2, screen(Vector2(0, y)).y)


func on_top(x: float) -> Vector2:
	return Vector2(screen(Vector2(x, 0)).x, Rulers.WIDTH / 2)


func mouse(button: MouseButton, pressed: bool, pos: Vector2, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = pos
	event.double_click = double
	rulers._gui_input(event)


func move_to(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	rulers._gui_input(event)


func drag(from: Vector2, to: Vector2) -> void:
	move_to(from)
	mouse(MOUSE_BUTTON_LEFT, true, from)
	move_to(from.lerp(to, 0.5))
	move_to(to)
	mouse(MOUSE_BUTTON_LEFT, false, to)


func guides(axis: int) -> PackedInt32Array:
	return Global.spritesheet.get_guides(axis)


func test_rulers_are_turned_on() -> void:
	assert_true(rulers.visible)
	assert_true(preview.guides.shown)
	Settings.set_value(&"show_rulers", false)
	assert_false(rulers.visible, "off by default")
	assert_false(preview.guides.shown)
	assert_false(Actions.is_checked(&"toggle_rulers"))
	Actions.run(&"toggle_rulers")
	assert_true(rulers.visible)


func test_only_the_rulers_take_the_mouse() -> void:
	assert_true(rulers._has_point(Vector2(4, 200)))
	assert_true(rulers._has_point(Vector2(200, 4)))
	assert_false(rulers._has_point(Vector2(200, 200)), "the preview gets the rest")


func test_clicking_the_left_ruler_adds_a_horizontal_guide() -> void:
	drag(on_left(6), on_left(6))
	# Pixels from the cells' corner, guides from their middle
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([-2]))
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array())
	assert_eq(Global.document.undo_redo.get_current_action_name(), "Create Horizontal Guide")
	Global.document.undo()
	assert_false(Global.spritesheet.has_guides)


func test_clicking_the_top_ruler_adds_a_vertical_guide() -> void:
	# In the second column, 4 pixels in
	drag(on_top(20), on_top(20))
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array([-4]))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array())


func test_dragging_a_guide_moves_it() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([-2]))
	drag(on_left(6), on_left(9))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([1]))
	# Out into the preview, it follows the mouse in the cell under it
	drag(on_left(9), screen(Vector2(30, 16 + 12)))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([4]))


func test_dropping_a_guide_on_the_other_ruler_removes_it() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([-2, 5]))
	drag(on_left(6), on_top(20))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([5]))
	assert_eq(Global.document.undo_redo.get_current_action_name(), "Remove Horizontal Guide")
	drag(on_top(20), on_left(20))
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array(), "a new one dropped there isn't added")


func test_right_click_removes_a_guide() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_X, PackedInt32Array([-4]))
	move_to(on_top(4))
	mouse(MOUSE_BUTTON_RIGHT, true, on_top(4))
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array())


func test_the_corner_adds_both_guides() -> void:
	drag(Vector2.ONE * Rulers.WIDTH / 2, screen(Vector2(20, 6)))
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array([-4]))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([-2]))


func test_escape_leaves_guides_as_they_were() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([-2]))
	move_to(on_left(6))
	mouse(MOUSE_BUTTON_LEFT, true, on_left(6))
	move_to(on_left(10))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	rulers._input(escape)
	assert_false(preview.guides.is_dragging())
	mouse(MOUSE_BUTTON_LEFT, false, on_left(10))
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([-2]))


func test_hidden_in_the_packed_layout() -> void:
	Global.document.perform("Packed", Global.spritesheet.set_layout.bind(Spritesheet.Layout.PACKED))
	assert_false(rulers.visible)
	assert_false(preview.guides.shown)
	assert_false(Actions.is_available(&"toggle_rulers"))


func test_numbers_are_at_least_60_pixels_apart() -> void:
	assert_eq(Rulers.label_step(1), 100)
	assert_eq(Rulers.label_step(8), 10)
	assert_eq(Rulers.label_step(11), 10, "not 25, so 24 px cells have more than a 0")
	assert_eq(Rulers.label_step(20), 5)
	assert_eq(Rulers.label_step(0.25), 500)


func key(keycode: Key, shift := false, alt := false) -> bool:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	event.alt_pressed = alt
	return preview._handle_arrow_key(event)


func test_shift_alt_arrow_keys_move_frames_onto_guides() -> void:
	var sheet := Global.spritesheet
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([10]))
	preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_false(key(KEY_DOWN, false, true), "Alt alone is left to shortcuts")
	assert_true(key(KEY_DOWN, true, true))
	# The 16 px frames' bottoms were 8 below the middle of the cells
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-8, -6))
	assert_eq(sheet.get_frame_origin(Vector2i(1, 0)), Vector2i(-8, -6))
	assert_false(sheet.has_frame_origin(Vector2i(2, 0)), "only the selected ones")
	Settings.set_value(&"show_rulers", false)
	assert_true(key(KEY_UP, true, true))
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-8, -6), "not to hidden guides")
