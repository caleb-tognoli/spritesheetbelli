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


func test_previous_and_next_frame_stop_playing() -> void:
	animation.player.next_button.pressed.emit()
	assert_eq(current(), Vector2i(1, 0))
	assert_false(animation.player.playing)
	animation.player.previous_button.pressed.emit()
	animation.player.previous_button.pressed.emit()
	assert_eq(current(), Vector2i(2, 0), "wraps around")


func test_plays_only_selected_frames() -> void:
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
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
	window.from_spin.value = 0
	assert_eq(sheet.animations[0].cells.size(), 3, "from 0 to 2")
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
