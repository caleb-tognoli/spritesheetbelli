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


func key(keycode: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
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
	preview.tool = SpritesheetPreview.Tool.MOVE
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
	preview.tool = SpritesheetPreview.Tool.MOVE
	var before := sheet.placements.duplicate()
	drag(at(Vector2i(1, 0)), at(Vector2i(0, 0)))
	assert_eq(sheet.placements, before, "nothing moved")


func test_frames_can_go_on_a_new_page() -> void:
	preview.tool = SpritesheetPreview.Tool.MOVE
	var coord := Vector2i(0, 0)
	mouse(MOUSE_BUTTON_LEFT, true, at(coord))
	move_to(at(coord) + Vector2(10, 0))
	assert_true(preview.is_dragging_frames())
	var new_page := preview.packed_view.get_new_page_rect()
	var target := to_screen(new_page.position + Vector2(20, 20))
	move_to(target)
	mouse(MOUSE_BUTTON_LEFT, false, target)
	assert_eq(sheet.placements[coord].page, 1)
	assert_eq(PackedLayout.get_page_count(sheet), 2)


func test_arrow_keys_move_frames_in_the_move_mode() -> void:
	preview.tool = SpritesheetPreview.Tool.MOVE
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


func test_arrow_keys_pick_the_next_frame() -> void:
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
		key(keys[direction])
		assert_eq(preview.get_selected_coords(), [expected] as Array[Vector2i])
		if expected != Vector2i(0, 0):
			var delta := preview.get_frame_world_rect(expected).get_center() - start
			assert_true(delta.dot(Vector2(direction)) > 0, "that way")


func test_dragging_a_pivot() -> void:
	preview.tool = SpritesheetPreview.Tool.PIVOT
	var coord := Vector2i(2, 0)
	var rect := preview.get_frame_world_rect(coord)
	drag(at(coord), to_screen(rect.position + Vector2(3, rect.size.y)))
	assert_eq(sheet.get_pivot(coord), Vector2(3, 12), "bottom, three pixels in")
	# The same in the grid
	sheet.set_layout(Spritesheet.Layout.GRID)
	var cell := preview.cell_rect(coord)
	var in_cell := sheet.get_frame_rect_in_cell(coord)
	var frame_start := cell.position + Vector2(in_cell.position)
	drag(to_screen(frame_start + Vector2(5, 5)), to_screen(frame_start + Vector2(1, 2)))
	assert_eq(sheet.get_pivot(coord), Vector2(1, 2))


func test_turned_frames_are_drawn_turned() -> void:
	var settings := sheet.atlas_settings
	settings.allow_rotation = true
	settings.max_size = 32
	sheet.set_atlas_settings(settings)
	var turned := sheet.placements.keys().filter(
		func(coord: Vector2i) -> bool: return sheet.placements[coord].rotated
	)
	if turned.is_empty():
		return
	var coord: Vector2i = turned[0]
	var rect := preview.get_frame_world_rect(coord)
	assert_eq(rect.size, Vector2(12, sheet.frames[coord].get_width()), "tall on the page")
	var pivot := Vector2(0, 0)
	assert_eq(preview.pivot_to_world(coord, pivot), rect.position + Vector2(rect.size.x, 0))
	assert_eq(preview.world_to_pivot(coord, rect.position + Vector2(rect.size.x, 0)), pivot)
