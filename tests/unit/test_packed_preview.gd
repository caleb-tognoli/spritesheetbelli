extends "res://tests/test_case.gd"
## The preview of a sheet in the packed layout

const ZOOM := 2.0

var main: Control
var preview: SpritesheetPreview
var sheet: Spritesheet


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	sheet = Global.spritesheet
	var images: Array[Image] = []
	for i in 4:
		images.append(make_image(Color.from_hsv(i / 5.0, 1, 1), Vector2i(10 + i * 6, 12)))
	var settings := AtlasSettings.new()
	settings.pack_mode = AtlasSettings.PackMode.KEEP
	settings.spacing = 2
	Global.document.perform(
		"Pack",
		func() -> void:
			sheet.add_frames(images)
			sheet.set_atlas_settings(settings)
			sheet.set_layout(Spritesheet.Layout.PACKED)
	)
	preview.camera.position = Vector2.ZERO
	preview.set_zoom(ZOOM)


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


## Screen position of the middle of a frame
func at(coord: Vector2i) -> Vector2:
	return to_screen(preview.get_frame_world_rect(coord).get_center())


func to_screen(world: Vector2) -> Vector2:
	return (world - preview.camera.position) * ZOOM


func mouse(button: MouseButton, pressed: bool, pos: Vector2, ctrl := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = pos
	event.ctrl_pressed = ctrl
	preview._unhandled_input(event)


func move_to(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	preview._unhandled_input(event)


func drag(from: Vector2, to: Vector2) -> void:
	mouse(MOUSE_BUTTON_LEFT, true, from)
	move_to(from.lerp(to, 0.5))
	move_to(to)
	mouse(MOUSE_BUTTON_LEFT, false, to)


func key(keycode: Key, shift := false, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	preview._unhandled_input(event)


func test_frames_are_where_they_are_packed() -> void:
	for coord in sheet.frames:
		var rect := preview.get_frame_world_rect(coord)
		assert_eq(Rect2i(rect), PackedLayout.get_rect(sheet, coord), "page 1 starts at 0")
		assert_eq(preview.get_cell_at_screen_position(at(coord)), coord)
	var outside := to_screen(preview.packed_view.get_content_rect().end + Vector2(5, 5))
	assert_eq(preview.get_cell_at_screen_position(outside), Spritesheet.NO_CELL)


func test_click_box_and_empty_space() -> void:
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(2, 0)))
	mouse(MOUSE_BUTTON_LEFT, false, at(Vector2i(2, 0)))
	assert_eq(preview.get_selected_coords(), [Vector2i(2, 0)] as Array[Vector2i])
	var content := preview.packed_view.get_content_rect()
	drag(to_screen(content.position - Vector2(4, 4)), to_screen(content.end + Vector2(4, 4)))
	assert_eq(preview.get_selected_coords().size(), 4, "the box takes every frame")
	var empty := to_screen(content.end + Vector2(10, 10))
	mouse(MOUSE_BUTTON_LEFT, true, empty)
	mouse(MOUSE_BUTTON_LEFT, false, empty)
	assert_true(preview.get_selected_coords().is_empty(), "clicking nothing clears")
	assert_true(sheet.locked_coordinates.is_empty(), "and locks nothing")


func test_dragging_moves_a_frame_and_pins_it() -> void:
	var coord := Vector2i(1, 0)
	var before := PackedLayout.get_rect(sheet, coord)
	var right := preview.packed_view.get_content_rect().end.x + 20
	var target := Vector2(right, 30)
	drag(at(coord), to_screen(target))
	var after := PackedLayout.get_rect(sheet, coord)
	var moved_by := Vector2i((target - preview.get_frame_world_rect(coord).get_center()).round())
	assert_ne(after, before, "moved")
	assert_true(moved_by.length() <= 1, "under the mouse")
	assert_true(sheet.placements[coord].pinned, "pinned")
	Global.document.undo()
	assert_eq(PackedLayout.get_rect(sheet, coord), before, "one undo step")


func test_frames_dont_land_on_others() -> void:
	var before := sheet.placements.duplicate()
	drag(at(Vector2i(1, 0)), at(Vector2i(0, 0)))
	assert_eq(sheet.placements, before, "nothing moved")


func test_frames_can_go_on_a_new_page() -> void:
	var coord := Vector2i(0, 0)
	mouse(MOUSE_BUTTON_LEFT, true, at(coord))
	move_to(at(coord) + Vector2(10, 0))
	assert_eq(preview._get_lifted_coords(), [coord] as Array[Vector2i])
	var new_page := preview.packed_view.get_new_page_rect()
	var target := to_screen(new_page.position + Vector2(20, 20))
	move_to(target)
	mouse(MOUSE_BUTTON_LEFT, false, target)
	assert_eq(sheet.placements[coord].page, 1)
	assert_eq(PackedLayout.get_page_count(sheet), 2)


func test_dragging_a_selected_frame_moves_the_selection() -> void:
	var some: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
	preview.set_selected_coords(some)
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(2, 0)))
	assert_true(preview._get_lifted_coords().is_empty(), "not lifted before the mouse moves")
	move_to(at(Vector2i(2, 0)) + Vector2(0, 30))
	assert_eq(preview._get_lifted_coords(), some, "the selection")
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.MOVE)


func test_where_frames_dont_fit_is_shown() -> void:
	mouse(MOUSE_BUTTON_LEFT, true, at(Vector2i(1, 0)))
	move_to(at(Vector2i(0, 0)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.FORBIDDEN, "on another frame")


func test_arrow_keys_move_frames() -> void:
	var coord := Vector2i(3, 0)
	preview.set_selected_coords([coord] as Array[Vector2i])
	var before := PackedLayout.get_rect(sheet, coord)
	# Somewhere with room around it first
	preview.placement_move_requested.emit([coord] as Array[Vector2i], 0, Vector2i(300, 300))
	key(KEY_RIGHT)
	key(KEY_DOWN, true)
	assert_eq(
		PackedLayout.get_rect(sheet, coord).position,
		before.position + Vector2i(300, 300) + Vector2i(1, 8)
	)


func test_ctrl_arrow_keys_add_the_next_frame() -> void:
	preview.set_selected_coords([Vector2i(0, 0)] as Array[Vector2i])
	var start := preview.get_frame_world_rect(Vector2i(0, 0)).get_center()
	var keys := {
		Vector2i.RIGHT: KEY_RIGHT,
		Vector2i.DOWN: KEY_DOWN,
		Vector2i.LEFT: KEY_LEFT,
		Vector2i.UP: KEY_UP
	}
	for direction: Vector2i in keys:
		var expected := preview.packed_view.get_neighbour(Vector2i(0, 0), direction)
		preview.set_selected_coords([Vector2i(0, 0)] as Array[Vector2i])
		preview._anchor = Vector2i(0, 0)
		key(keys[direction], false, true)
		assert_true(preview.is_selected(expected), "added")
		assert_true(preview.is_selected(Vector2i(0, 0)), "to the selection")
		if expected != Vector2i(0, 0):
			var delta := preview.get_frame_world_rect(expected).get_center() - start
			assert_true(delta.dot(Vector2(direction)) > 0, "that way")


## Screen position of the pivot of a frame
func pivot_at(coord: Vector2i) -> Vector2:
	return to_screen(preview.pivot_to_world(coord, sheet.get_pivot(coord)))


func test_dragging_a_pivot() -> void:
	Settings.set_value(&"use_pivots", true)
	var coord := Vector2i(2, 0)
	move_to(pivot_at(coord))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.POINT, "over the pivot")
	move_to(pivot_at(coord) + Vector2(12, 0))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.GRAB, "elsewhere on the frame")
	var rect := preview.get_frame_world_rect(coord)
	drag(pivot_at(coord), to_screen(rect.position + Vector2(3, rect.size.y)))
	assert_eq(sheet.get_pivot(coord), Vector2(3, 12), "bottom, three pixels in")
	assert_eq(PackedLayout.get_rect(sheet, coord), Rect2i(rect), "the frame stays")
	assert_true(preview.get_selected_coords().is_empty(), "nothing selected")
	# The same in the grid
	sheet.set_layout(Spritesheet.Layout.GRID)
	var cell := preview.cell_rect(coord)
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	var frame_start := cell.position + Vector2(in_cell.position)
	drag(pivot_at(coord), to_screen(frame_start + Vector2(1, 2)))
	assert_eq(sheet.get_pivot(coord), Vector2(1, 2))
	Settings.set_value(&"use_pivots", Settings.DEFAULTS[&"use_pivots"])


func test_pivots_stay_inside_their_frames() -> void:
	Settings.set_value(&"use_pivots", true)
	var coord := Vector2i(0, 0)
	var rect := preview.get_frame_world_rect(coord)
	drag(pivot_at(coord), to_screen(rect.end + Vector2(40, 40)))
	assert_eq(sheet.get_pivot(coord), Vector2(sheet.frames[coord].get_size()), "the corner")
	Settings.set_value(&"use_pivots", Settings.DEFAULTS[&"use_pivots"])


func test_a_selected_pivot_moves_the_selection_pivots() -> void:
	Settings.set_value(&"use_pivots", true)
	var some: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	preview.set_selected_coords(some)
	drag(pivot_at(Vector2i(1, 0)), pivot_at(Vector2i(1, 0)) + Vector2(-6, -6))
	assert_eq(sheet.get_pivot(Vector2i(1, 0)), Vector2(5, 3))
	assert_eq(sheet.get_pivot(Vector2i(0, 0)), Vector2(5, 3), "the other selected frame too")
	assert_eq(preview.get_selected_coords(), some, "still selected")
	assert_false(sheet.has_pivot(Vector2i(2, 0)), "not the others")
	drag(pivot_at(Vector2i(1, 0)), pivot_at(Vector2i(1, 0)) + Vector2(18, 0))
	assert_eq(sheet.get_pivot(Vector2i(1, 0)), Vector2(14, 3))
	assert_eq(sheet.get_pivot(Vector2i(0, 0)), Vector2(10, 3), "inside the narrower frame")
	Settings.set_value(&"use_pivots", false)
	move_to(pivot_at(Vector2i(2, 0)))
	assert_eq(preview.get_cursor_hint(), CanvasCursor.Hint.GRAB, "no pivots when they're off")
	Settings.set_value(&"use_pivots", Settings.DEFAULTS[&"use_pivots"])


func test_turned_frames_are_drawn_turned() -> void:
	var settings := sheet.atlas_settings
	settings.allow_rotation = true
	settings.max_size = 32
	sheet.set_atlas_settings(settings)
	var turned := sheet.placements.keys().filter(
		func(c: Vector2i) -> bool: return sheet.placements[c].rotated
	)
	if turned.is_empty():
		return
	var coord: Vector2i = turned[0]
	var rect := preview.get_frame_world_rect(coord)
	assert_eq(rect.size, Vector2(12, sheet.frames[coord].get_width()), "tall on the page")
	var pivot := Vector2(0, 0)
	assert_eq(preview.pivot_to_world(coord, pivot), rect.position + Vector2(rect.size.x, 0))
	assert_eq(preview.world_to_pivot(coord, rect.position + Vector2(rect.size.x, 0)), pivot)


func test_selected_frames_always_show_their_pivots() -> void:
	Settings.set_value(&"use_pivots", true)
	var some: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	preview.set_selected_coords(some)
	preview.clear_hover()
	assert_eq(preview.pivots.get_shown_coords(preview), some, "without the mouse over them")
	move_to(at(Vector2i(3, 0)))
	var with_hovered: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0)]
	assert_eq(preview.pivots.get_shown_coords(preview), with_hovered, "and the one under it")
	Settings.set_value(&"use_pivots", false)
	assert_true(preview.pivots.get_shown_coords(preview).is_empty(), "none while off")
	Settings.set_value(&"use_pivots", Settings.DEFAULTS[&"use_pivots"])
