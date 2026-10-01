extends "res://tests/test_case.gd"

const Detector := preload("res://tests/unit/test_sprite_detector.gd")
const IMAGE := Rect2i(0, 0, 64, 48)
## The boxes found in [method Detector.packed_sheet], in reading order
const FOUND: Array[Rect2i] = [
	Rect2i(2, 4, 10, 10),
	Rect2i(30, 2, 8, 12),
	Rect2i(50, 3, 6, 9),
	Rect2i(4, 26, 12, 16),
	Rect2i(24, 30, 6, 12),
]

var window: AddSpritesheetWindow
var view: SpriteBoxView


func before_each() -> void:
	Global.document.reset()
	window = load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	add_child(window)
	view = window.box_editor.view


func after_each() -> void:
	window.queue_free()
	Global.document.reset()


## The window showing the boxes found in [method Detector.packed_sheet], at 4×, the image's
## top-left corner 10 px from the view's
func open(path := "packed.png") -> void:
	window.setup(Detector.packed_sheet(), path)
	window.set_cut(AddSpritesheetWindow.Cut.DETECT)
	# Headless windows have no size, so the view is given one
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(600, 400)
	view.set_zoom(4)
	view.pan = Vector2(10, 10)


## The frames [member window] would add, by the rectangle they're cut from
func get_cut_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for coord in window.spritesheet.get_sorted_coords():
		var rect: Array = window.spritesheet.frame_sources[coord].rect
		rects.append(Rect2i(rect[0], rect[1], rect[2], rect[3]))
	return rects


#region Box operations


func test_merging_makes_one_box_around_them() -> void:
	var merged := SpriteBoxes.merge(FOUND, [0, 3] as Array[int])
	assert_eq(merged.size(), 4)
	assert_eq(merged[-1], Rect2i(2, 4, 14, 38), "around both, at the end")
	assert_eq(merged.slice(0, 3), [FOUND[1], FOUND[2], FOUND[4]])
	assert_eq(SpriteBoxes.merge(FOUND, [1] as Array[int]), FOUND, "one box doesn't merge")
	assert_eq(FOUND[0], Rect2i(2, 4, 10, 10), "the boxes given are left alone")


func test_removing() -> void:
	var left := SpriteBoxes.remove(FOUND, [4, 0] as Array[int])
	assert_eq(left, [FOUND[1], FOUND[2], FOUND[3]])


func test_moving_stays_in_the_image() -> void:
	var both := [0, 1] as Array[int]
	var moved := SpriteBoxes.move(FOUND, both, Vector2i(3, 5), IMAGE)
	assert_eq(moved[0], Rect2i(5, 9, 10, 10))
	assert_eq(moved[1], Rect2i(33, 7, 8, 12))
	assert_eq(moved[2], FOUND[2], "others stay")
	# Together, as far as the first reaches the left edge and the second the top
	moved = SpriteBoxes.move(FOUND, both, Vector2i(-20, -20), IMAGE)
	assert_eq(moved[0].position, Vector2i(0, 2))
	assert_eq(moved[1].position, Vector2i(28, 0))
	moved = SpriteBoxes.move(FOUND, [2] as Array[int], Vector2i(100, 100), IMAGE)
	assert_eq(moved[2], Rect2i(58, 39, 6, 9), "in the bottom-right corner")


func test_resizing_stays_in_the_image() -> void:
	var box := FOUND[0]  # 2, 4, 10×10
	assert_eq(
		SpriteBoxes.resize(box, SpriteBoxes.RIGHT, Vector2i(20, 0), IMAGE), Rect2i(2, 4, 18, 10)
	)
	assert_eq(
		SpriteBoxes.resize(box, SpriteBoxes.LEFT, Vector2i(-5, 0), IMAGE), Rect2i(0, 4, 12, 10)
	)
	var corner := SpriteBoxes.TOP | SpriteBoxes.LEFT
	assert_eq(SpriteBoxes.resize(box, corner, Vector2i(5, 6), IMAGE), Rect2i(5, 6, 7, 8))
	assert_eq(
		SpriteBoxes.resize(box, SpriteBoxes.BOTTOM, Vector2i(0, 99), IMAGE),
		Rect2i(2, 4, 10, 44),
		"to the bottom of the image"
	)
	assert_eq(
		SpriteBoxes.resize(box, SpriteBoxes.RIGHT, Vector2i(-10, 0), IMAGE),
		Rect2i(2, 4, 1, 10),
		"a pixel wide at least"
	)
	assert_eq(
		SpriteBoxes.resize(box, SpriteBoxes.TOP, Vector2i(0, 30), IMAGE),
		Rect2i(2, 13, 10, 1),
		"a pixel high at least"
	)


func test_new_boxes_take_both_corners() -> void:
	assert_eq(SpriteBoxes.from_corners(Vector2i(3, 4), Vector2i(5, 9), IMAGE), Rect2i(3, 4, 3, 6))
	assert_eq(SpriteBoxes.from_corners(Vector2i(5, 9), Vector2i(3, 4), IMAGE), Rect2i(3, 4, 3, 6))
	assert_eq(SpriteBoxes.from_corners(Vector2i(7, 7), Vector2i(7, 7), IMAGE), Rect2i(7, 7, 1, 1))
	assert_eq(
		SpriteBoxes.from_corners(Vector2i(60, -3), Vector2i(90, 2), IMAGE),
		Rect2i(60, 0, 4, 3),
		"cut to the image"
	)


func test_boxes_are_numbered_in_reading_order() -> void:
	# In another order, and a box drawn by hand at the end, in the first row
	var boxes: Array[Rect2i] = [
		FOUND[3], FOUND[1], FOUND[4], FOUND[0], FOUND[2], Rect2i(20, 5, 4, 4)
	]
	assert_eq(SpriteBoxes.get_numbers(boxes), PackedInt32Array([4, 2, 5, 0, 3, 1]))
	assert_eq(SpriteBoxes.get_numbers(boxes, 1)[3], 1, "from the first number")
	var coords := SpriteBoxes.get_coords(boxes)
	assert_eq(coords[3], Vector2i(0, 0))
	assert_eq(coords[5], Vector2i(1, 0))
	assert_eq(coords[4], Vector2i(3, 0))
	assert_eq(coords[2], Vector2i(1, 1))
	assert_eq(SpriteBoxes.to_rows(boxes)[0][1], Rect2i(20, 5, 4, 4))
	var same: Array[Rect2i] = [FOUND[0], FOUND[0]]
	assert_eq(SpriteBoxes.get_numbers(same), PackedInt32Array([0, 1]), "boxes in one place too")


func test_finding_boxes_and_edges() -> void:
	var boxes: Array[Rect2i] = [Rect2i(0, 0, 20, 20), Rect2i(5, 5, 4, 4)]
	assert_eq(SpriteBoxes.find_at(boxes, Vector2(6, 6)), 1, "the smaller one inside")
	assert_eq(SpriteBoxes.find_at(boxes, Vector2(15, 15)), 0)
	assert_eq(SpriteBoxes.find_at(boxes, Vector2(25, 5)), -1)
	var box := Rect2i(10, 10, 20, 20)
	assert_eq(SpriteBoxes.edges_at(box, Vector2(20, 20), 1), 0, "the middle")
	assert_eq(SpriteBoxes.edges_at(box, Vector2(9.5, 20), 1), SpriteBoxes.LEFT, "just outside")
	assert_eq(SpriteBoxes.edges_at(box, Vector2(30, 30), 1), SpriteBoxes.RIGHT | SpriteBoxes.BOTTOM)
	assert_eq(SpriteBoxes.edges_at(box, Vector2(40, 20), 1), 0, "too far")
	assert_eq(SpriteBoxes.touching(boxes, Rect2(8, 0, 1, 1)), [0] as Array[int])
	assert_eq(SpriteBoxes.touching(boxes, Rect2(8, 8, 4, 4)), [0, 1] as Array[int])


#endregion

#region Editing


func click(at: Vector2, pressed: bool, ctrl := false, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	view._gui_input(event)


## Drags from pixel [param from] to pixel [param to] of the image, at [method open]'s zoom
func drag(from: Vector2, to: Vector2, ctrl := false) -> void:
	click(view.world_to_screen(from), true, ctrl)
	for step in 3:
		var motion := InputEventMouseMotion.new()
		motion.position = view.world_to_screen(from.lerp(to, (step + 1) / 3.0))
		motion.ctrl_pressed = ctrl
		view._gui_input(motion)
	click(view.world_to_screen(to), false, ctrl)


func press_key(keycode: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	view._gui_input(event)


func test_found_sprites_are_shown_as_boxes() -> void:
	open()
	assert_true(window.box_editor.visible)
	assert_eq(window.box_editor.get_boxes(), FOUND)
	assert_eq(view.image.get_size(), Vector2i(64, 48), "over the image")
	assert_eq(get_cut_rects(), FOUND)
	assert_false(window.box_editor.is_edited())


func test_clicking_selects() -> void:
	open()
	var inside := func(index: int) -> Vector2:
		return view.world_to_screen(Rect2(FOUND[index]).get_center())
	click(inside.call(1), true)
	click(inside.call(1), false)
	assert_eq(view.selected, [1] as Array[int])
	click(inside.call(3), true, false, true)
	click(inside.call(3), false, false, true)
	click(inside.call(4), true, true)
	click(inside.call(4), false, true)
	assert_eq(view.selected, [1, 3, 4] as Array[int], "Shift and Ctrl add")
	assert_eq(window.add_selected_frames_btn.text, "Add selected frames (3)")
	click(inside.call(3), true, true)
	click(inside.call(3), false, true)
	assert_eq(view.selected, [1, 4] as Array[int], "and take out")
	click(view.world_to_screen(Vector2(40, 40)), true)
	click(view.world_to_screen(Vector2(40, 40)), false)
	assert_true(view.selected.is_empty(), "empty space selects nothing")
	assert_eq(window.box_editor.get_boxes(), FOUND, "clicks don't edit")


func test_dragging_moves_and_resizes_whole_pixels() -> void:
	open()
	# From inside the first box, 3.4 px right and 2.6 px down
	drag(Vector2(6, 8), Vector2(9.4, 10.6))
	assert_eq(window.box_editor.get_boxes()[0], Rect2i(5, 7, 10, 10), "moved")
	# The sprite is at 2, 4, 10×10: what's drawn of it inside the box
	assert_eq(get_cut_rects()[0], Rect2i(5, 7, 7, 7), "cut there, without transparent borders")
	# Its right edge, to the line nearest the mouse
	drag(Vector2(15, 12), Vector2(20.3, 12))
	assert_eq(window.box_editor.get_boxes()[0], Rect2i(5, 7, 15, 10), "wider")
	# Its bottom-left corner, past the image
	drag(Vector2(5, 17), Vector2(-10, 30))
	assert_eq(window.box_editor.get_boxes()[0], Rect2i(0, 7, 20, 23), "to the image's edge")
	assert_eq(view.selected, [0] as Array[int])


func test_drawing_a_new_box() -> void:
	open()
	assert_eq(window.box_editor.info_label.text, "", "no hint while nothing is selected")
	drag(Vector2(40.5, 20.5), Vector2(44.5, 23.5))
	var boxes := window.box_editor.get_boxes()
	assert_eq(boxes.size(), 6)
	assert_eq(boxes[-1], Rect2i(40, 20, 5, 4), "from pixel to pixel")
	assert_eq(view.selected, [5] as Array[int], "selected")
	assert_eq(window.spritesheet.frames.size(), 6, "added as a frame")
	assert_true(window.box_editor.is_edited())
	assert_eq(window.box_editor.info_label.text, "Frame 3 · 40, 20 · 5×4 px", "a row of its own")

	# Where it is shows while drawing
	click(view.world_to_screen(Vector2(40.5, 30.5)), true)
	var motion := InputEventMouseMotion.new()
	motion.position = view.world_to_screen(Vector2(50.5, 35.5))
	view._gui_input(motion)
	assert_eq(window.box_editor.info_label.text, "40, 30 · 11×6 px")
	assert_eq(window.box_editor.get_boxes().size(), 6, "not added yet")
	click(motion.position, false)
	assert_eq(window.box_editor.get_boxes().size(), 7)


func test_ctrl_dragging_merges() -> void:
	open()
	# Across the first two boxes of the first row
	drag(Vector2(10, 10), Vector2(32, 10), true)
	var boxes := window.box_editor.get_boxes()
	assert_eq(boxes.size(), 4)
	assert_eq(boxes[-1], Rect2i(2, 2, 36, 12))
	assert_eq(view.selected, [3] as Array[int], "the merged box is selected")
	assert_eq(view.get_number(3), 0, "and numbered first")
	assert_eq(window.spritesheet.frames.size(), 4)
	# Over one box, nothing to merge
	drag(Vector2(52, 5), Vector2(53, 6), true)
	assert_eq(window.box_editor.get_boxes().size(), 4)


func test_merge_delete_and_undo() -> void:
	open()
	view.select([0, 2] as Array[int])
	window.box_editor.merge_btn.pressed.emit()
	assert_eq(window.box_editor.get_boxes()[-1], Rect2i(2, 3, 54, 11))
	assert_eq(window.spritesheet.frames.size(), 4)
	press_key(KEY_DELETE)
	assert_eq(window.box_editor.get_boxes(), [FOUND[1], FOUND[3], FOUND[4]], "deleted")
	assert_eq(window.spritesheet.frames.size(), 3)
	press_key(KEY_Z, true)
	assert_eq(window.box_editor.get_boxes().size(), 4, "undone")
	assert_eq(view.selected, [3] as Array[int], "with its selection")
	window.box_editor.undo()
	assert_eq(window.box_editor.get_boxes(), FOUND)
	assert_eq(window.spritesheet.frames.size(), 5, "cut again")
	press_key(KEY_Y, true)
	assert_eq(window.box_editor.get_boxes().size(), 4, "redone")
	assert_true(window.box_editor.can_redo())


func test_finding_again_replaces_edits_until_undone() -> void:
	open()
	view.select([0] as Array[int])
	view.remove_selected()
	assert_true(window.box_editor.find_btn.visible and not window.box_editor.find_btn.disabled)
	var edited := window.box_editor.get_boxes()
	var joined := SpriteBoxes.from_rows(SpriteDetector.detect(Detector.packed_sheet(), 12))
	assert_true(joined.size() < FOUND.size(), "some sprites joined")
	window.merge_distance.value = 12
	assert_eq(window.box_editor.get_boxes(), joined, "found again with the new setting")
	assert_true(window.box_editor.notice.visible, "saying so")
	assert_eq(window.spritesheet.frames.size(), joined.size())
	# Not edited since, so the step is replaced
	window.merge_distance.value = 13
	window.box_editor.undo()
	assert_eq(window.box_editor.get_boxes(), edited, "the edits are back")
	assert_false(window.box_editor.notice.visible)
	assert_eq(window.spritesheet.frames.size(), 4)

	# Reset goes back to the boxes the settings find
	assert_eq(window.box_editor.find_btn.text, "Reset")
	window.box_editor.find_btn.pressed.emit()
	var rows := SpriteDetector.detect(Detector.packed_sheet(), 13)
	assert_eq(window.box_editor.get_boxes(), SpriteBoxes.from_rows(rows))
	assert_false(window.box_editor.is_edited())
	assert_true(window.box_editor.find_btn.disabled, "nothing to reset")


func test_the_key_colour_finds_the_sprites_again() -> void:
	open()
	view.select([0] as Array[int])
	view.remove_selected()
	# Green away: the green sprite goes too, once confirmed
	window.background.open()
	window.background.pick(Color.GREEN)
	for i in 5:
		await get_tree().process_frame
	assert_eq(view.image.get_pixelv(FOUND[1].position).a, 0.0, "shown without it")
	var kept := SpriteBoxes.remove(FOUND, [0] as Array[int])
	assert_eq(window.box_editor.get_boxes(), kept, "the boxes stay until confirmed")
	window.background.confirm()
	assert_eq(window.box_editor.get_boxes(), [FOUND[0], FOUND[2], FOUND[3], FOUND[4]])
	window.box_editor.undo()
	assert_eq(window.box_editor.get_boxes(), SpriteBoxes.remove(FOUND, [0] as Array[int]))


func test_the_eyedropper_picks_from_the_image() -> void:
	open()
	window.background.set_picking(true)
	assert_true(view.picking)
	click(view.world_to_screen(Vector2(52.5, 5.5)), true)
	click(view.world_to_screen(Vector2(52.5, 5.5)), false)
	assert_eq(window.background.get_color(), Color.BLUE)
	assert_false(view.picking, "put away")
	assert_true(view.selected.is_empty(), "picking doesn't select")


func test_align_and_the_packed_layout_follow_the_boxes() -> void:
	open()
	drag(Vector2(40.5, 20.5), Vector2(44.5, 23.5))
	window.align_option.select(1)
	window.align_option.item_selected.emit(1)
	assert_eq(window.box_editor.get_boxes().size(), 6, "the edits stay")
	# The new box is a row of its own, between the others
	var sheet := window.spritesheet
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 1)).end.y, sheet.sprite_size.y, "aligned")
	window.keep_layout.button_pressed = true
	assert_eq(window.spritesheet.layout, Spritesheet.Layout.PACKED)
	var place: Dictionary = window.spritesheet.placements[Vector2i(0, 1)]
	assert_eq(place.position, Vector2i(40, 20), "where the box is")
	assert_eq(window.box_editor.get_boxes().size(), 6)


func test_edited_boxes_are_added_and_reloaded() -> void:
	var dir := temp_path("boxes")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("packed.png")
	Detector.packed_sheet().save_png(path)
	open(path)
	# The red and green sprites as one, the yellow one gone, a box on empty space
	view.select([0, 1] as Array[int])
	view.merge_selected()
	view.select([2] as Array[int])
	view.remove_selected()
	drag(Vector2(40.5, 20.5), Vector2(44.5, 23.5))
	var expected: Array[Rect2i] = [
		Rect2i(2, 2, 36, 12), Rect2i(50, 3, 6, 9), Rect2i(40, 20, 5, 4), Rect2i(4, 26, 12, 16)
	]
	assert_eq(get_cut_rects(), expected)

	window.add_spritesheet_to_global()
	var sheet := Global.spritesheet
	assert_eq(sheet.frames.size(), 4)
	var first := sheet.get_sorted_coords()[0]
	assert_eq(sheet.frames[first].get_size(), Vector2i(36, 12), "merged")
	var source: Dictionary = sheet.frame_sources[first]
	assert_eq(source.rect, [2, 2, 36, 12])
	var saved := FrameSource.from_json(FrameSource.to_json(source, dir), dir)
	assert_eq(saved, source, "kept in projects")

	# The file changes: the merged box is cut again, not found again
	var changed := Detector.packed_sheet()
	changed.fill_rect(Rect2i(14, 6, 10, 4), Color.CYAN)
	changed.save_png(path)
	var key := FrameSource.get_load_key(source)
	var pixels := FrameSource.cut(source, {key: FrameSource.load_key(key)})
	assert_eq(pixels.get_size(), Vector2i(36, 12))
	assert_color(pixels, Vector2i(12, 4), Color.CYAN, "the new pixels, in the same box")
	assert_color(pixels, Vector2i(0, 2), Color.RED)


func test_adding_the_selected_boxes() -> void:
	open()
	view.select([4, 0] as Array[int])
	window.add_selected_frames_btn.pressed.emit()
	var sheet := Global.spritesheet
	assert_eq(sheet.frames.size(), 2)
	var sizes: Array[Vector2i] = []
	for coord in sheet.get_sorted_coords():
		sizes.append(sheet.frames[coord].get_size())
	assert_eq(sizes, [Vector2i(10, 10), Vector2i(6, 12)] as Array[Vector2i], "in reading order")

#endregion
