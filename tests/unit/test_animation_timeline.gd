extends "res://tests/test_case.gd"
## The timeline of frames in the animation panel's details: adding, taking out, moving
## and timing frames, each one step to undo, picking them, and their labels

const PANEL_SETTINGS: Array[StringName] = [
	&"animation_panel",
	&"bottom_dock_height",
	&"animation_frames_text",
	&"show_sprites",
	&"index_start",
]

var main: Control
var panel: AnimationPanel
var detail: AnimationDetail
var timeline: AnimationTimeline


func before_each() -> void:
	Settings.set_value(&"animation_panel", "open")
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	panel = main.animation_panel
	detail = panel.detail
	timeline = detail.timeline
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE]:
		imgs.append(make_image(color))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	# An animation of the first three frames
	main.preview.set_selected_coords(cells([0, 1, 2]))
	panel.new_button.pressed.emit()
	main.preview.set_selected_coords([] as Array[Vector2i])


func after_each() -> void:
	var viewport := get_viewport()
	if viewport.gui_is_dragging():
		viewport.gui_cancel_drag()
	main.queue_free()
	Global.document.reset()
	for key in PANEL_SETTINGS:
		Settings.set_value(key, Settings.DEFAULTS[key])


## The cells of the frames numbered [param numbers] in the 4×1 sheet
static func cells(numbers: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for number: int in numbers:
		result.append(Vector2i(number, 0))
	return result


func animation() -> SheetAnimation:
	return Global.spritesheet.animations[0]


## How many steps there are to undo
func steps() -> int:
	return Global.document.undo_redo.get_history_count()


func test_shows_the_frames() -> void:
	await get_tree().process_frame
	assert_eq(timeline.row.get_child_count(), 3, "a tile for each frame")
	var tile := timeline.get_tile(1)
	assert_eq(tile.duration_spin.value, 1.0)
	assert_eq(tile.duration_spin.prefix, "×")
	assert_ne(tile.picture.texture, null, "its picture")
	assert_eq(tile.get_label_text(), "1", "its number without a name")
	assert_true("16×16" in tile.tooltip_text, tile.tooltip_text)
	assert_false(timeline.empty_hint.visible)
	for button: Button in [panel.mirror_button, panel.delete_button]:
		assert_true(button.is_visible_in_tree(), "mirror and delete stay")
	assert_false("frames_editor" in detail, "no Edit Animation window")


func test_adding_frames_is_one_step() -> void:
	var before := steps()
	timeline.insert_cells(cells([3, 3]), 1)
	assert_eq(animation().cells, cells([0, 3, 3, 1, 2]), "where they're put, in order")
	assert_eq(steps(), before + 1, "one step")
	assert_eq(timeline.get_selected(), [1, 2] as Array[int], "the new frames are picked")
	assert_eq(timeline.row.get_child_count(), 5)
	timeline.insert_cells(cells([0]))
	assert_eq(animation().cells, cells([0, 3, 3, 1, 2, 0]), "after the last")
	Global.document.undo()
	Global.document.undo()
	assert_eq(animation().cells, cells([0, 1, 2]), "undone")
	assert_eq(timeline.row.get_child_count(), 3, "the timeline follows")


func test_moving_frames() -> void:
	Global.document.perform(
		"Timed",
		func() -> void:
			var timed := animation()
			timed.durations = [1.0, 2.0, 3.0] as Array[float]
			Global.spritesheet.set_animation(0, timed)
	)
	var before := steps()
	timeline.move_frames([0] as Array[int], 3)
	assert_eq(animation().cells, cells([1, 2, 0]), "the first to the end")
	assert_eq(animation().durations, [2.0, 3.0, 1.0] as Array[float], "with its duration")
	assert_eq(steps(), before + 1, "one step")
	assert_eq(timeline.get_selected(), [2] as Array[int], "still picked")
	timeline.move_frames([1, 2] as Array[int], 0)
	assert_eq(animation().cells, cells([2, 0, 1]), "several, keeping their order")
	timeline.move_frames([0] as Array[int], 1)
	assert_eq(steps(), before + 2, "not moved: no step")
	Global.document.undo()
	assert_eq(animation().cells, cells([1, 2, 0]))


func test_removing_frames() -> void:
	var before := steps()
	timeline.remove_frames([0, 2] as Array[int])
	assert_eq(animation().cells, cells([1]))
	assert_eq(steps(), before + 1, "one step")
	Global.document.undo()
	assert_eq(animation().cells, cells([0, 1, 2]))

	# The × on a tile
	await get_tree().process_frame
	var tile := timeline.get_tile(1)
	assert_true(tile.remove_button.is_visible_in_tree(), "always shown")
	await hover(tile.picture.get_global_rect().get_center())
	assert_eq(tile.theme_type_variation, &"TimelineFrameHover", "lit when hovered")
	await hover(tile.remove_button.get_global_rect().get_center())
	assert_eq(tile.theme_type_variation, &"TimelineFrameHover", "and over the ×")
	await hover(tile.duration_spin.get_global_rect().get_center())
	assert_eq(tile.theme_type_variation, &"TimelineFrameHover", "or the duration")
	await hover(Vector2(-10, -10))
	assert_eq(tile.theme_type_variation, &"TimelineFrame", "not once the mouse leaves")
	tile.remove_button.pressed.emit()
	assert_eq(animation().cells, cells([0, 2]))

	# Delete takes the picked frames out
	timeline.select([0, 1] as Array[int])
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	timeline._gui_input(key)
	assert_true(animation().cells.is_empty())
	assert_true(timeline.empty_hint.visible, "says what to do")


func test_durations() -> void:
	var before := steps()
	timeline.get_tile(0).duration_spin.value = 2.5
	assert_eq(animation().durations, [2.5, 1.0, 1.0] as Array[float])
	assert_eq(steps(), before + 1, "one step")
	assert_eq(detail.frames_edit.text, "0*2.5, 1, 2", "in the frames as text too")
	timeline.set_duration(0, 2.5)
	assert_eq(steps(), before + 1, "unchanged: no step")
	Global.document.undo()
	assert_eq(timeline.get_tile(0).duration_spin.value, 1.0, "undone")


func test_dropping_frames() -> void:
	await get_tree().process_frame
	var first := timeline.get_tile(0)
	var data := AnimationTimeline.frames_drag_data(cells([3, 2]))
	assert_true(timeline._can_drop(Vector2(1, 1), data, first), "frames of the sheet")
	assert_eq(timeline._drop_index, 0, "before the first")
	assert_false(timeline._can_drop(Vector2(1, 1), {"type": "other"}, first))
	assert_false(timeline._can_drop(Vector2(1, 1), "text", first))
	timeline._drop(Vector2(1, 1), data, first)
	assert_eq(animation().cells, cells([3, 2, 0, 1, 2]), "several at once, in order")
	# After the last, dropped on the empty space
	timeline._drop(Vector2(timeline.row.size.x - 1, 1), data, timeline.row)
	assert_eq(animation().cells, cells([3, 2, 0, 1, 2, 3, 2]))

	# Tiles are dragged within the timeline
	Global.document.undo()
	Global.document.undo()
	await get_tree().process_frame
	# Asked for while dragging, which is when a picture can follow the mouse
	timeline.force_drag(true, null)
	var moved: Variant = timeline._get_tile_drag(Vector2.ZERO, timeline.get_tile(0))
	get_viewport().gui_cancel_drag()
	assert_eq(timeline.get_selected(), [0] as Array[int], "the dragged tile is picked")
	var last := timeline.get_tile(2)
	assert_true(timeline._can_drop(Vector2(last.size.x - 1, 1), moved, last))
	timeline._drop(Vector2(last.size.x - 1, 1), moved, last)
	assert_eq(animation().cells, cells([1, 2, 0]), "moved after the last")


func test_picking() -> void:
	await get_tree().process_frame
	click(0)
	assert_eq(timeline.get_selected(), [0] as Array[int])
	click(2, KEY_MASK_SHIFT)
	assert_eq(timeline.get_selected(), [0, 1, 2] as Array[int], "Shift picks a range")
	click(1, KEY_MASK_CTRL)
	assert_eq(timeline.get_selected(), [0, 2] as Array[int], "Ctrl takes one out")
	assert_true(timeline.get_tile(2).selected)
	assert_eq(timeline.get_tile(2).theme_type_variation, &"TimelineFrameSelected")
	assert_eq(timeline.get_tile(2).label.theme_type_variation, &"TimelineLabelSelected")
	assert_eq(timeline.get_tile(1).label.theme_type_variation, &"StatusLabel")
	# Pressing a picked frame keeps the others for dragging, until released
	click(0, 0, true)
	assert_eq(timeline.get_selected(), [0, 2] as Array[int])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	timeline._on_tile_input(release, timeline.get_tile(0))
	assert_eq(timeline.get_selected(), [0] as Array[int])

	# A box across the second and third frames
	var start := timeline.get_tile(1).get_rect().get_center()
	var end := timeline.get_tile(2).get_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	timeline._on_row_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	timeline._on_row_input(motion)
	var let_go := press.duplicate() as InputEventMouseButton
	let_go.pressed = false
	timeline._on_row_input(let_go)
	assert_eq(timeline.get_selected(), [1, 2] as Array[int], "picked by the box")


## Moves the mouse to [param at] in the window
func hover(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	await get_tree().process_frame


## Clicks the tile at [param index] with [param modifiers], or only presses it with
## [param press_only]
func click(index: int, modifiers := 0, press_only := false) -> void:
	var tile := timeline.get_tile(index)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.shift_pressed = modifiers & KEY_MASK_SHIFT != 0
	event.ctrl_pressed = modifiers & KEY_MASK_CTRL != 0
	event.pressed = true
	timeline._on_tile_input(event, tile)
	if not press_only:
		var release := event.duplicate() as InputEventMouseButton
		release.pressed = false
		timeline._on_tile_input(release, tile)


func test_labels_leave_out_what_names_share() -> void:
	var short := AnimationTimeline.short_labels
	assert_eq(
		short.call(PackedStringArray(["walk_01", "walk_02", "walk_10"])),
		PackedStringArray(["01", "02", "10"]),
		"not in the middle of a number"
	)
	assert_eq(
		short.call(PackedStringArray(["idle1", "idle2"])),
		PackedStringArray(["1", "2"]),
		"where letters and digits meet"
	)
	assert_eq(
		short.call(PackedStringArray(["slime_walk", "slime_wave"])),
		PackedStringArray(["walk", "wave"]),
		"not in the middle of a word"
	)
	assert_eq(
		short.call(PackedStringArray(["walk", "walk_2"])),
		PackedStringArray(["walk", "walk_2"]),
		"nothing left of one: whole names"
	)
	assert_eq(
		short.call(PackedStringArray(["hero_run_0", "", "hero_run_0", "hero_run_1"])),
		PackedStringArray(["0", "", "0", "1"]),
		"repeats and frames without names"
	)
	assert_eq(
		short.call(PackedStringArray(["jump", "jump"])),
		PackedStringArray(["jump", "jump"]),
		"one name: whole"
	)


func test_long_labels_are_cut_at_the_end() -> void:
	var font := ThemeDB.fallback_font
	var fit := AnimationTimeline.fit_text
	assert_eq(fit.call("run", font, 12, 200.0), "run", "fits")
	var cut: String = fit.call("attack_upward_swing", font, 12, 40.0)
	assert_true(cut.ends_with("…"), cut)
	assert_true("attack_upward_swing".begins_with(cut.trim_suffix("…")), "the start stays")
	assert_true(font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 40, cut)

	# In a tile, the part that differs, shortened to fit
	var sheet := Global.spritesheet
	var long_name := "overhead_slash_with_a_very_long_follow_through"
	for i in 3:
		sheet.rename_frame(Vector2i(i, 0), "knight_attack_%s" % ["a", "b", long_name][i])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(timeline.get_tile(0).get_label_text(), "a")
	var long := timeline.get_tile(2).get_label_text()
	assert_true(long.begins_with("over") and long.ends_with("…"), long)
	assert_true(("knight_attack_" + long_name) in timeline.get_tile(2).tooltip_text)


func test_tiles_fit_the_panel_height() -> void:
	for height: int in [BottomDock.MIN_HEIGHT, 320]:
		Settings.set_value(&"bottom_dock_height", height)
		panel.dock.apply_height()
		await get_tree().process_frame
		await get_tree().process_frame
		var picture := timeline.get_picture_size()
		assert_true(picture >= AnimationTimeline.MIN_PICTURE, "never smaller")
		if picture > AnimationTimeline.MIN_PICTURE:
			var bottom := timeline.get_global_rect().end.y
			assert_true(bottom <= detail.get_global_rect().end.y + 0.5, "fits: %d" % height)
	var tall := timeline.get_picture_size()
	Settings.set_value(&"bottom_dock_height", BottomDock.MIN_HEIGHT)
	panel.dock.apply_height()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(timeline.get_picture_size() < tall, "smaller in a short panel")


func test_frames_as_text_stays_under_its_button() -> void:
	assert_false(detail.frames_edit.is_visible_in_tree(), "hidden at first")
	detail.frames_text_button.toggled.emit(true)
	assert_true(detail.frames_edit.is_visible_in_tree())
	assert_true(Settings.get_value(&"animation_frames_text"), "remembered")
	detail.frames_edit.text = "2, 0"
	detail.frames_edit.text_submitted.emit(detail.frames_edit.text)
	assert_eq(timeline.get_cells(), cells([2, 0]), "the timeline follows")
	detail.frames_edit.text = "oops"
	detail.frames_edit.text_submitted.emit(detail.frames_edit.text)
	assert_eq(detail.frames_info.theme_type_variation, &"ErrorLabel", "says what's wrong")


func test_frames_are_dragged_from_the_sprites_panel() -> void:
	Settings.set_value(&"show_sprites", true)
	await get_tree().process_frame
	var sprites: SpritesPanel = main.layout_controller.sprites_panel
	main.preview.set_selected_coords(cells([3, 1]))
	# Asked for while dragging, which is when a picture can follow the mouse
	sprites.force_drag(true, null)
	var data: Variant = sprites._get_drag_data_of_tree(Vector2.ZERO)
	get_viewport().gui_cancel_drag()
	assert_eq(data, AnimationTimeline.frames_drag_data(cells([1, 3])), "in the listed order")
	main.preview.set_selected_coords([] as Array[Vector2i])
	assert_eq(sprites._get_drag_data_of_tree(Vector2.ZERO), null, "nothing to drag")

	# A frame that isn't selected is dragged alone
	main.preview.set_selected_coords(cells([0]))
	await get_tree().process_frame
	# Group names have their key as metadata, frames their cell
	var item := sprites.tree.get_root().get_next_in_tree()
	while item and var_to_str(item.get_metadata(0)) != var_to_str(Vector2i(2, 0)):
		item = item.get_next_in_tree()
	var on_it := sprites.tree.get_item_area_rect(item).get_center()
	sprites.force_drag(true, null)
	data = sprites._get_drag_data_of_tree(on_it)
	get_viewport().gui_cancel_drag()
	assert_eq(data, AnimationTimeline.frames_drag_data(cells([2])), "only the one pressed")
	assert_eq(main.preview.get_selected_coords(), cells([2]), "and it's selected")


func test_frames_are_dragged_out_of_the_sheet() -> void:
	var preview: SpritesheetPreview = main.preview
	assert_true(preview.drag_frames_out, "to drop them on a timeline")
	var dragged: Array = []
	preview.frames_dragged_out.connect(
		func(coords: Array[Vector2i]) -> void: dragged.append(coords)
	)
	preview.set_selected_coords(cells([2, 3]))
	var inside := preview.cell_rect(Vector2i(2, 0)).get_center()
	var screen := (inside - preview.camera.position) * preview.camera.zoom
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	preview._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = screen + Vector2(10, 0)
	preview._unhandled_input(motion)
	assert_true(dragged.is_empty(), "still moving inside the preview")
	motion = motion.duplicate() as InputEventMouseMotion
	motion.position = Vector2(screen.x, preview.get_viewport_rect().size.y + 20)
	preview._unhandled_input(motion)
	assert_eq(dragged, [cells([2, 3])], "the selection, once out")
	assert_eq(preview.get_selected_coords(), cells([2, 3]), "still selected")
	assert_true(preview.mover.carried, "carried")
	get_viewport().gui_cancel_drag()
	preview.notification(Control.NOTIFICATION_DRAG_END)
	assert_false(preview.mover.carried, "put down when the drag ends")

	panel.set_expanded(false)
	panel.select_animation(-1)
	assert_true(preview.drag_frames_out, "always: the panel opens when they're held over it")


func test_numbers_follow_the_first_frame_number() -> void:
	await get_tree().process_frame
	assert_eq(timeline.get_tile(1).get_label_text(), "1")
	assert_eq(detail.frames_edit.text, "0-2")
	Settings.set_value(&"index_start", 1)
	await get_tree().process_frame
	assert_eq(timeline.get_tile(1).get_label_text(), "2", "numbered from 1")
	assert_true(timeline.get_tile(1).tooltip_text.begins_with("Frame 2"), "its tooltip too")
	assert_eq(detail.frames_edit.text, "1-3", "and as text")


func test_alt_drag_copies_tiles() -> void:
	var before := steps()
	timeline.copy_frames([0, 1] as Array[int], 3)
	assert_eq(animation().cells, cells([0, 1, 2, 0, 1]), "copied after the last")
	assert_eq(timeline.get_selected(), [3, 4] as Array[int], "the copies are picked")
	assert_eq(steps(), before + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Duplicate frames")


func test_frames_dropped_off_the_animations_make_one() -> void:
	await get_tree().process_frame
	var data := AnimationTimeline.frames_drag_data(cells([3, 1]))
	var below := panel.list.get_item_rect(panel.list.item_count - 1).end + Vector2(0, 4)
	assert_true(panel._can_drop_on_list(below, data), "under the animations")
	var on_animation := panel.list.get_item_rect(1).get_center()
	assert_false(panel._can_drop_on_list(on_animation, data), "not on one")
	assert_false(panel._can_drop_on_list(below, {"type": "other"}))
	panel._drop_on_list(below, data)
	var animations := Global.spritesheet.animations
	assert_eq(animations.size(), 2)
	assert_eq(animations[1].cells, cells([3, 1]), "in the order dragged")
	assert_eq(panel.get_selected(), 1, "chosen to edit")
	panel.select_animation(-1)
	assert_true(detail._can_drop_frames(Vector2.ZERO, data), "on the details while none is")
	detail._drop_frames(Vector2.ZERO, data)
	assert_eq(Global.spritesheet.animations.size(), 3)
	assert_false(detail._can_drop_frames(Vector2.ZERO, data), "then the timeline takes them")


func test_holding_frames_over_the_dock_button_opens_the_panel() -> void:
	panel.set_expanded(false)
	await get_tree().process_frame
	var middle := panel.dock_button.get_global_rect().get_center()
	panel.dock.hold_over(middle, 0.3)
	panel.dock.hold_over(middle, 0.3)
	assert_false(panel.is_expanded(), "not right away")
	panel.dock.hold_over(middle + Vector2(0, -500), 0.3)
	panel.dock.hold_over(middle, 0.4)
	panel.dock.hold_over(middle, 0.4)
	assert_false(panel.is_expanded(), "leaving the button starts again")
	panel.dock.hold_over(middle, 0.4)
	assert_true(panel.is_expanded(), "held long enough")
