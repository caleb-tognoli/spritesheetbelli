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


func test_loops_through_all_frames() -> void:
	var seen: Array[Vector2i] = [animation.get_current_coord()]
	for i in 3:
		animation.step()
		seen.append(animation.get_current_coord())
	assert_eq(
		seen, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i]
	)


func test_ping_pong() -> void:
	animation.mode = AnimationPreview.Mode.PING_PONG
	var seen: Array[int] = []
	for i in 5:
		animation.step()
		seen.append(animation.get_current_coord().x)
	assert_eq(seen, [1, 2, 1, 0, 1] as Array[int])


func test_once_stops_at_the_end() -> void:
	animation.mode = AnimationPreview.Mode.ONCE
	for i in 5:
		animation.step()
	assert_eq(animation.get_current_coord(), Vector2i(2, 0))
	assert_false(animation.playing)


func test_plays_only_selected_frames() -> void:
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	animation.step()
	assert_eq(animation.get_current_coord(), Vector2i(2, 0))
	animation.step()
	assert_eq(animation.get_current_coord(), Vector2i(0, 0))


func test_advances_with_time() -> void:
	animation.fps = 60
	var start := animation.get_current_coord()
	animation._process(1.0 / 60 + 0.001)
	assert_ne(animation.get_current_coord(), start)
