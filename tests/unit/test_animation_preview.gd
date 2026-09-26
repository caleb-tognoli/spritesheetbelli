extends "res://tests/test_case.gd"

var main: Control
var animation: AnimationPreview


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		imgs.append(make_image(color))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))
	animation = main.preview_area.animation_preview
	Actions.run(&"toggle_animation")


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


func test_toggle() -> void:
	assert_true(animation.visible)
	assert_true(Actions.is_checked(&"toggle_animation"))
	Actions.run(&"toggle_animation")
	assert_false(animation.visible)


## Plays one frame's worth of time
func advance() -> void:
	animation.player._process(1.0 / animation.player.fps + 0.0001)


func current() -> Vector2i:
	return animation.player.get_current_cell()


func test_loops_through_all_frames() -> void:
	var seen: Array[Vector2i] = [current()]
	for i in 3:
		advance()
		seen.append(current())
	assert_eq(
		seen, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i]
	)


func test_ping_pong() -> void:
	animation.player.mode = SheetAnimation.Mode.PING_PONG
	var seen: Array[int] = []
	for i in 5:
		advance()
		seen.append(current().x)
	assert_eq(seen, [1, 2, 1, 0, 1] as Array[int])


func test_once_stops_at_the_end() -> void:
	animation.player.mode = SheetAnimation.Mode.ONCE
	for i in 5:
		advance()
	assert_eq(current(), Vector2i(2, 0))
	assert_false(animation.player.playing)
	animation.player.play_button.pressed.emit()
	assert_eq(current(), Vector2i(0, 0), "playing again starts over")


func test_pause_and_back_to_start() -> void:
	advance()
	advance()
	animation.player.play_button.pressed.emit()
	assert_false(animation.player.playing, "paused")
	advance()
	assert_eq(current(), Vector2i(2, 0), "stays while paused")
	animation.player.play_button.pressed.emit()
	advance()
	assert_eq(current(), Vector2i(0, 0), "resumes where it was")
	advance()
	animation.player.start_button.pressed.emit()
	assert_eq(current(), Vector2i(0, 0))
	assert_true(animation.player.playing, "keeps playing from the start")


func test_previous_and_next_frame_stop_playing() -> void:
	animation.player.next_button.pressed.emit()
	assert_eq(current(), Vector2i(1, 0))
	assert_false(animation.player.playing)
	animation.player.previous_button.pressed.emit()
	animation.player.previous_button.pressed.emit()
	assert_eq(current(), Vector2i(2, 0), "wraps around")


func test_plays_only_selected_frames() -> void:
	assert_eq(animation.selector.get_item_text(0), "All frames", "nothing selected")
	assert_eq(animation.details_button.icon, main.ICONS[&"edit_animations"], "like the menu")
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(animation.selector.get_item_text(0), "Selected frames")
	advance()
	assert_eq(current(), Vector2i(2, 0))
	advance()
	assert_eq(current(), Vector2i(0, 0))


func test_plays_a_chosen_animation() -> void:
	var sheet := Global.spritesheet
	var walk := SheetAnimation.create(
		"walk", [Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i], 5
	)
	Global.document.perform("New animation", sheet.add_animation.bind(walk))
	assert_eq(animation.selector.item_count, 2, "selected frames and walk")
	animation.selector.select(1)
	animation.selector.item_selected.emit(1)
	assert_eq(animation.player.fps, 5.0)
	assert_eq(animation.player.get_cells(), walk.cells)


func test_animation_window() -> void:
	var window: AnimationWindow = main.animation_window
	main.preview.set_selected_coords([Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	window.open()
	assert_true(window.empty_hint.visible, "no animations yet")
	window.new_button.pressed.emit()
	var sheet := Global.spritesheet
	assert_eq(sheet.animations.size(), 1)
	assert_eq(sheet.animations[0].cells, [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(window.frames_edit.text, "1, 2")
	window.frames_edit.text = "2-0, 2"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i],
		"frames by number, in the typed order"
	)
	window.frames_edit.text = "1, oops"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_true("oops" in window.frames_info.text, "explains what it couldn't read")
	assert_eq(sheet.animations[0].cells.size(), 4, "unchanged")
	window.fps_spin.value = 20
	window.mode_option.select(window.mode_option.get_item_index(SheetAnimation.Mode.PING_PONG))
	window.mode_option.item_selected.emit(window.mode_option.selected)
	assert_eq(sheet.animations[0].fps, 20.0)
	assert_eq(sheet.animations[0].mode, SheetAnimation.Mode.PING_PONG)
	window.name_edit.text = "run"
	window.name_edit.text_submitted.emit("run")
	assert_eq(sheet.animations[0].name, "run")
	Global.document.undo()
	assert_eq(sheet.animations[0].name, "animation", "undoable")
	window.delete_button.pressed.emit()
	assert_true(sheet.animations.is_empty())
	window.hide()


func test_onion_skin_shows_the_previous_frame() -> void:
	var sheet := Spritesheet.new()
	for i in 3:
		sheet.add_frames([make_image(Color(i / 3.0, 0, 0))] as Array[Image])
	var player := FramePlayer.new()
	add_child(player)
	player.sheet = sheet
	player.set_cells(sheet.get_sorted_coords())
	assert_eq(player.get_previous_cell(), Vector2i(2, 0), "loops back to the last frame")
	player.mode = SheetAnimation.Mode.ONCE
	assert_eq(player.get_previous_cell(), Spritesheet.NO_CELL, "nothing before the start")
	player.step(1)
	assert_eq(player.get_previous_cell(), Vector2i(0, 0))

	Settings.set_value(&"onion_skin", true)
	assert_true(player.onion_button.button_pressed, "follows the setting")
	assert_true(player._onion.texture != null, "previous frame shown")
	player.onion_button.button_pressed = false
	assert_true(player._onion.texture == null, "hidden again")
	assert_false(Settings.get_value(&"onion_skin"), "remembered")
	player.queue_free()


func test_frames_are_shown_by_name_when_they_have_one() -> void:
	var sheet := Global.spritesheet
	sheet.rename_frame(Vector2i(1, 0), "idle")
	var window: AnimationWindow = main.animation_window
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	window.open()
	window.new_button.pressed.emit()
	assert_eq(window.frames_edit.text, "0, idle", "no toggle: names always")
	window.frames_edit.text = "idle, 2, 0"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i],
		"names and numbers both read"
	)
	assert_false("names_button" in window)
	window.hide()


func test_frames_editor() -> void:
	var sheet := Global.spritesheet
	var window: AnimationWindow = main.animation_window
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	window.open()
	window.new_button.pressed.emit()
	window.edit_frames_button.pressed.emit()
	var editor := window.frames_editor
	assert_true(editor.visible)
	assert_eq(editor.palette.get_child_count(), 3, "every sprite to pick from")
	assert_eq(editor.timeline.get_child_count(), 2, "the animation's frames")
	await get_tree().process_frame
	# A sprite dropped before the first frame, then the last frame moved to the front
	var first := editor.timeline.get_child(0) as Control
	editor._drop_at(Vector2(1, 1), {"cell": Vector2i(2, 0)}, first)
	assert_eq(editor.get_frames_text(), "2, 0, 1")
	editor.move_frame(2, 0)
	assert_eq(editor.get_frames_text(), "1, 2, 0")
	editor.set_duration(0, 2.0)
	editor.remove_frame(2)
	assert_eq(editor.get_frames_text(), "1*2, 2")
	editor.get_ok_button().pressed.emit()
	assert_eq(window.frames_edit.text, "1*2, 2", "written in the frames field")
	assert_eq(sheet.animations[0].cells, [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(sheet.animations[0].durations, [2.0, 1.0] as Array[float])
	Global.document.undo()
	assert_eq(sheet.animations[0].cells.size(), 2, "one undoable step")
	assert_eq(sheet.animations[0].cells[0], Vector2i(0, 0))
	window.hide()
