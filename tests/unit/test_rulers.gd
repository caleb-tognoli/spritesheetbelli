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
	assert_false(rulers._has_point(Vector2(4, -10)), "not the toolbar above")
	assert_false(rulers._has_point(Vector2(-10, 4)), "nor what's on the left")


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


func test_a_typed_guide_is_shown_before_it_moves() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([-2]))
	rulers._edit(Vector2.AXIS_Y, -2, on_left(6))
	rulers._edit_spin.value = 9
	var shown := preview.guides.get_cell_guides(Global.spritesheet, Vector2.AXIS_Y)
	assert_eq(shown, PackedInt32Array([9]), "shown where typed")
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([-2]), "not moved yet")
	var line := rulers._edit_spin.get_line_edit()
	# As typing does
	line.text = "11"
	line.text_changed.emit(line.text)
	await get_tree().process_frame
	assert_eq(preview.guides.dragged_to.y, 11, "as it's typed")
	move_to(on_left(2))
	assert_eq(preview.guides.dragged_to.y, 11, "the mouse leaves it alone")
	rulers._edit_popup.hide()
	assert_false(preview.guides.is_dragging())
	assert_eq(guides(Vector2.AXIS_Y), PackedInt32Array([3]))
	assert_eq(Global.document.undo_redo.get_current_action_name(), "Move Horizontal Guide")


func test_a_cancelled_typed_guide_stays() -> void:
	Global.spritesheet.set_guides(Vector2.AXIS_X, PackedInt32Array([-4]))
	rulers._edit(Vector2.AXIS_X, -4, on_top(4))
	rulers._edit_spin.value = 10
	rulers._edit_cancelled = true
	rulers._edit_popup.hide()
	assert_false(preview.guides.is_dragging())
	assert_eq(guides(Vector2.AXIS_X), PackedInt32Array([-4]))


func test_the_guides_colour() -> void:
	Settings.set_value(&"guides_color", Color.RED)
	assert_eq(preview.guides.color, Color.RED)
	Actions.run(&"guides_color")
	assert_true(rulers._color_popup.visible)
	rulers._color_picker.color_changed.emit(Color.GREEN)
	assert_eq(Settings.get_value(&"guides_color"), Color.GREEN, "changed as it's picked")
	rulers._color_popup.hide()
	Settings.set_value(&"guides_color", Settings.DEFAULTS[&"guides_color"])


func test_the_rulers_button_opens_a_menu_and_shows_whether_they_are_on() -> void:
	var button: Button = main.preview_area._submenu_buttons[&"rulers_menu"]
	await get_tree().process_frame
	assert_true(button.button_pressed)
	Settings.set_value(&"show_rulers", false)
	await get_tree().process_frame
	assert_false(button.button_pressed)
	assert_eq(
		main.preview_area._menu_buttons[button],
		[&"toggle_rulers", &"clear_guides", &"", &"guides_color"]
	)


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


func key(keycode: Key, shift := false, alt := false, ctrl := false) -> bool:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.ctrl_pressed = ctrl
	return preview._handle_arrow_key(event)


func test_alt_arrow_keys_move_frames_onto_guides() -> void:
	var sheet := Global.spritesheet
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([10]))
	preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_false(key(KEY_DOWN, true, false, true), "Ctrl+Shift is left to shortcuts")
	assert_false(key(KEY_DOWN, true, true), "and Shift+Alt")
	assert_true(key(KEY_DOWN, false, true))
	# The 16 px frames' bottoms were 8 below the middle of the cells
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-8, -6))
	assert_eq(sheet.get_frame_origin(Vector2i(1, 0)), Vector2i(-8, -6))
	assert_false(sheet.has_frame_origin(Vector2i(2, 0)), "only the selected ones")
	# The cells now span -8..10: no guide above, so their top edge
	assert_true(key(KEY_UP, false, true))
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-8, -8))
	Settings.set_value(&"show_rulers", false)
	assert_true(key(KEY_DOWN, false, true))
	assert_eq(sheet.get_frame_origin(Vector2i(0, 0)), Vector2i(-8, -8), "not to hidden guides")
