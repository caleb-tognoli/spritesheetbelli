extends "res://tests/test_case.gd"
## Making in-betweens in the background (InBetweenMaker): the movement found first, then
## the pieces, then the frame halfway and the others; only the newest ask worked on, a few
## pieces of work at a time; frames made kept for asking again

const Pins := preload("res://tests/unit/test_inbetween_pins.gd")

var maker: InBetweenMaker
var found: Array[Vector2i] = []
var middles: Array[Dictionary] = []
var a := Pins.key(Pins.figure(0))
var b := Pins.key(Pins.figure(8), Vector2i(5, 0))


func before_each() -> void:
	maker = InBetweenMaker.new()
	add_child(maker)
	maker.motion_found.connect(func(motion: Vector2i) -> void: found.append(motion))
	maker.middle_made.connect(func(frame: Dictionary) -> void: middles.append(frame))


func after_each() -> void:
	# Waits for the work still running
	maker.free()


## Waits until the maker is at [param stage], or a while
func until(stage: InBetweenMaker.Stage) -> void:
	var waiting := Time.get_ticks_msec()
	while maker.get_stage() != stage and Time.get_ticks_msec() - waiting < 20000:
		await get_tree().process_frame


## Starts on the keys and waits for the movement
func started() -> Vector2i:
	maker.start(a, b)
	var waiting := Time.get_ticks_msec()
	while found.is_empty() and Time.get_ticks_msec() - waiting < 20000:
		await get_tree().process_frame
	return found[0] if found else Vector2i.ZERO


static func times(count: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i in count:
		result.append(InBetween.time_of(i, count))
	return result


func test_finds_the_movement_then_makes_the_frames() -> void:
	maker.start(a, b)
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.MOTION)
	var motion: Vector2i = await started()
	assert_eq(motion, SpriteMotion.detect(a, b))
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.IDLE, "nothing asked yet")
	maker.ask(motion, times(3))
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.PIECES)
	await until(InBetweenMaker.Stage.DONE)
	assert_eq(middles.size(), 1, "the middle frame, made once though it's asked for twice")
	assert_true(is_same(middles[0], maker.get_frame(InBetweenMaker.MIDDLE)))
	var frames := maker.get_frames()
	var expected := InBetween.generate(a, b, 3, motion)
	assert_eq(frames.size(), 3)
	for i in 3:
		assert_eq(frames[i].origin, expected[i].origin)
		assert_eq(frames[i].image.get_data(), expected[i].image.get_data(), "as made at once")
		assert_eq(frames[i].image.resource_name, expected[i].image.resource_name, "named alike")
	var middle: Image = maker.get_frame(InBetweenMaker.MIDDLE).image
	assert_false(is_same(frames[1].image, middle), "a copy, apart from what's kept")


func test_frames_made_are_had_again_at_once() -> void:
	var motion: Vector2i = await started()
	maker.ask(motion, times(3))
	await until(InBetweenMaker.Stage.DONE)
	maker.ask(motion, times(1))
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.DONE, "the frame halfway is made")
	maker.ask(motion, times(3))
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.DONE, "back to the frames made")
	assert_eq(maker.count_running(), 0, "nothing made again")
	maker.ask(motion, times(3), [{"at": Vector2(16, 14), "to": Vector2(18, 14)}])
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.FRAMES, "pins make other frames")
	await until(InBetweenMaker.Stage.DONE)


func test_only_the_newest_ask_is_worked_on() -> void:
	maker.slots = 2
	var motion: Vector2i = await started()
	maker.ask(motion, times(1))
	await until(InBetweenMaker.Stage.DONE)
	var many := times(16)
	maker.ask(motion, many)
	assert_eq(maker.count_running(), 2, "a few at a time")
	maker.ask(motion, times(1))
	var most := 0
	while maker.count_running() > 0:
		most = maxi(most, maker.count_running())
		await get_tree().process_frame
	assert_true(most <= 2, "never more")
	var made := 0
	for time in many:
		if not maker.get_frame(time).is_empty():
			made += 1
	assert_true(made <= 2, "the frames of the first ask that were being made, not the rest")
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.DONE)


func test_pieces_for_another_movement_stop() -> void:
	var motion: Vector2i = await started()
	maker.ask(motion, times(1))
	var first: WorkProgress
	for task in maker._running:
		if task.kind == &"pieces":
			first = task.progress
	assert_ne(first, null, "working out the pieces")
	maker.ask(motion + Vector2i(1, 0), times(1))
	assert_true(first.cancelled, "not needed any more")
	await until(InBetweenMaker.Stage.DONE)
	assert_eq(maker.get_pins(), [] as Array[Dictionary])


func test_a_movement_of_zero_is_used() -> void:
	var motion: Vector2i = await started()
	assert_ne(motion, Vector2i.ZERO, "the keys move")
	maker.ask(Vector2i.ZERO, times(1))
	await until(InBetweenMaker.Stage.DONE)
	assert_eq(maker._prepared[Vector2i.ZERO].shift, Vector2.ZERO, "not found again")


func test_stopping_lets_everything_go() -> void:
	var motion: Vector2i = await started()
	maker.ask(motion, times(3))
	maker.stop()
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.IDLE)
	while maker.count_running() > 0:
		await get_tree().process_frame
	assert_eq(maker.get_stage(), InBetweenMaker.Stage.IDLE, "what ended after isn't kept")
	assert_true(middles.is_empty(), "nor shown")
	assert_true(maker.get_frames().is_empty())
