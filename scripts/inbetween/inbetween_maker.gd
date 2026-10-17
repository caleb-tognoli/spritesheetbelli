class_name InBetweenMaker
extends Node
## Makes in-betweens in the background for Generate In-Betweens (see [InBetweenDialog]), on
## worker threads, so the window stays responsive. Started with two keys (see
## [method start]), it finds how the whole sprite moves; asked for frames (see
## [method ask]), it works out the keys' pieces for the movement asked (see
## [method InBetween.prepare]), then makes the frame halfway between the keys, then the
## others in order.
##
## Only what was asked last is worked on. Working out pieces for another movement stops;
## frames being made for an older ask can't be stopped, but only a few pieces of work run
## at once (see [member slots]), so the newest ask never waits behind a pile of old ones.
## Frames made for the movement and pins asked are kept, so asking for them again, with
## another count or spacing, has them at once.

## Emitted with how the whole sprite moves from the first key to the second, once found
signal motion_found(motion: Vector2i)
## Emitted with the frame halfway between the keys for the movement asked, the newest
## made: while pins are dragged, ones made for where they were show on the way
signal middle_made(frame: Dictionary)
## Emitted when anything was made or got further, see [method get_stage]
signal updated

## What's being worked on, see [method get_stage]
enum Stage {
	IDLE,  ## Nothing: nothing was started or asked for
	MOTION,  ## Finding how the whole sprite moves
	PIECES,  ## Working out the keys' pieces, see [method InBetween.prepare]
	FRAMES,  ## Making the frames asked for
	DONE,  ## Every frame asked for is made
	FAILED,  ## Something went wrong making them
}

## How far between the keys the frame halfway is
const MIDDLE := 0.5

## Pieces of work run at most at once: on half the threads at most, leaving the rest to
## the window, and fewer than every frame, so the first ones show sooner
var slots := clampi(OS.get_processor_count() / 2, 1, 8) if OS.has_feature("threads") else 1
## The keys, see [method InBetween.key_of]
var a := {}
var b := {}

## Work started and not ended yet, also work for what isn't asked any more
var _running: Array[Task] = []
## Counts the times work was started or stopped, so what ends from before is let go
var _starts := 0
## Whether the movement of the whole sprite is being found
var _finding := false
var _failed := false
## What was asked last, see [method ask]
var _asked := false
var _motion := Vector2i.ZERO
var _times := PackedFloat64Array()
var _pins: Array[Dictionary] = []
## The movement and pins asked, as text, to tell frames made for them
var _version := ""
## Counts the asks, so a middle frame is never shown after a newer one
var _asks := 0
var _middle_ask := -1
## The keys' pieces worked out, by the movement
var _prepared: Dictionary[Vector2i, PieceMorph] = {}
## Frames made for the movement and pins asked, by how far between the keys they are
var _made: Dictionary[float, Dictionary] = {}


func _init() -> void:
	set_process(false)


func _notification(what: int) -> void:
	# Work on worker threads must be waited for, to let its resources go
	if what == NOTIFICATION_PREDELETE:
		stop()
		for task in _running:
			if task.id >= 0:
				WorkerThreadPool.wait_for_task_completion(task.id)


## Starts on keys [param key_a] and [param key_b]: finds how the whole sprite moves (see
## [signal motion_found]), letting go of everything before
func start(key_a: Dictionary, key_b: Dictionary) -> void:
	stop()
	a = key_a
	b = key_b
	_finding = true
	var task := Task.new(&"motion")
	_run(task, SpriteMotion.detect.bind(a, b))
	updated.emit()


## Lets go of everything: work running stops where it can, and what it makes is thrown
## away
func stop() -> void:
	_starts += 1
	for task in _running:
		if task.progress:
			task.progress.cancelled = true
	_finding = false
	_failed = false
	_asked = false
	_times = PackedFloat64Array()
	_pins = []
	_version = ""
	_prepared.clear()
	_made.clear()


## Asks for frames [param times] of the way between the keys (see
## [method InBetween.time_of]) and the one halfway, the whole sprite moving by
## [param motion], steered by [param pins] (see [method PieceMorph.frame]), instead of
## what was asked before. With [param times] empty, only the frame halfway is made, as
## while a pin is dragged.
func ask(motion: Vector2i, times: PackedFloat64Array, pins: Array[Dictionary] = []) -> void:
	_asks += 1
	_asked = true
	_failed = false
	_motion = motion
	_times = times
	_pins = pins.duplicate(true)
	var version := var_to_str([motion, _pins])
	if version != _version:
		_version = version
		_made.clear()
	# Pieces for another movement aren't needed any more
	for task in _running:
		if task.kind == &"pieces" and task.motion != motion and task.start == _starts:
			task.progress.cancelled = true
	_fill()
	updated.emit()


## What's being worked on
func get_stage() -> Stage:
	if _failed:
		return Stage.FAILED
	if not _asked:
		return Stage.MOTION if _finding else Stage.IDLE
	if not _prepared.has(_motion):
		return Stage.PIECES
	for time in _wanted():
		if not _made.has(time):
			return Stage.FRAMES
	return Stage.DONE


## Whether anything asked for is being worked on, see [method get_stage]
func is_working() -> bool:
	return get_stage() in [Stage.MOTION, Stage.PIECES, Stage.FRAMES]


## How far the stage got (see [method get_stage]), from 0 to 1: how much of the pieces
## were worked out, or how many of the frames asked for were made
func get_progress() -> float:
	match get_stage():
		Stage.PIECES:
			var task := _pieces_task(_motion)
			return task.progress.get_ratio() if task else 0.0
		Stage.FRAMES:
			var wanted := _wanted()
			var made := 0
			for time in wanted:
				if _made.has(time):
					made += 1
			return float(made) / wanted.size()
		Stage.DONE:
			return 1.0
	return 0.0


## The frame [param time] of the way between the keys, made for the movement and pins
## asked (see [method PieceMorph.frame]), or empty when it isn't made yet
func get_frame(time: float) -> Dictionary:
	return _made.get(time, {})


## The frames asked for (see [method ask]), in order, ready to add (see
## [method InBetween.finish]), or none while they aren't all made
func get_frames() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if get_stage() != Stage.DONE:
		return frames
	for i in _times.size():
		var made := _made[_times[i]]
		var frame := made.duplicate()
		frame.image = (made.image as Image).duplicate()
		frames.append(InBetween.finish(a, b, frame, i, _times[i]))
	return frames


## The times asked for, see [method ask]
func get_times() -> PackedFloat64Array:
	return _times


## The pins asked for, see [method ask]
func get_pins() -> Array[Dictionary]:
	return _pins


## How many pieces of work are running, also ones for what isn't asked any more
func count_running() -> int:
	return _running.size()


func _process(_delta: float) -> void:
	var changed := false
	for task: Task in _running.duplicate():
		if task.id >= 0:
			if not WorkerThreadPool.is_task_completed(task.id):
				continue
			WorkerThreadPool.wait_for_task_completion(task.id)
		_running.erase(task)
		if task.start == _starts:
			_finish(task)
			changed = true
	if _fill():
		changed = true
	# The pieces' progress moves on its own
	if changed or get_stage() == Stage.PIECES:
		updated.emit()
	set_process(not _running.is_empty())


## Keeps what [param task] made, if it's still wanted
func _finish(task: Task) -> void:
	match task.kind:
		&"motion":
			_finding = false
			# Frames are still made when it isn't found, as if the sprite stayed put
			motion_found.emit(task.result if task.result is Vector2i else Vector2i.ZERO)
		&"pieces":
			if task.result is PieceMorph:
				_prepared[task.motion] = task.result
			elif not task.progress.cancelled:
				_failed = true
		&"frame":
			if not task.result is Dictionary:
				_failed = _failed or task.version == _version
				return
			if task.version == _version:
				_made[task.time] = task.result
			if task.time == MIDDLE and task.motion == _motion and task.ask > _middle_ask:
				_middle_ask = task.ask
				middle_made.emit(task.result)


## Starts the work asked for that isn't running yet, while there's room: the pieces for
## the movement asked, then the frames, the one halfway first. Returns whether any started.
func _fill() -> bool:
	if not _asked or _failed:
		return false
	if not _prepared.has(_motion):
		if _running.size() >= slots or _pieces_task(_motion):
			return false
		var task := Task.new(&"pieces")
		task.motion = _motion
		task.progress = WorkProgress.new()
		_run(task, InBetween.prepare.bind(a, b, _motion, task.progress))
		return true
	var started := false
	for time in _wanted():
		if _running.size() >= slots:
			break
		if _made.has(time) or _frame_task(time, _version):
			continue
		# One middle frame at a time, as pins are dragged: the next one is for where they
		# are once it's made
		if time == MIDDLE and _frame_task(MIDDLE):
			continue
		var task := Task.new(&"frame")
		task.motion = _motion
		task.version = _version
		task.time = time
		_run(task, _frame_work(_prepared[_motion], time, _pins))
		started = true
	return started


## The frame halfway, then the frames asked for
func _wanted() -> PackedFloat64Array:
	var wanted := PackedFloat64Array([MIDDLE])
	for time in _times:
		if time != MIDDLE:
			wanted.append(time)
	return wanted


## Working out the pieces for [param motion], if it's running and not stopped
func _pieces_task(motion: Vector2i) -> Task:
	for task in _running:
		if (
			task.kind == &"pieces"
			and task.motion == motion
			and task.start == _starts
			and not task.progress.cancelled
		):
			return task
	return null


## Making the frame [param time] of the way, if it's running: for the movement and pins
## [param version], or any
func _frame_task(time: float, version := "") -> Task:
	for task in _running:
		if (
			task.kind == &"frame"
			and task.time == time
			and task.start == _starts
			and (version == "" or task.version == version)
		):
			return task
	return null


## Runs [param work] for [param task] on a worker thread, or right away in builds without
## threads (such as the web build), keeping what it returns in the task
func _run(task: Task, work: Callable) -> void:
	task.start = _starts
	task.ask = _asks
	_running.append(task)
	if OS.has_feature("threads"):
		task.id = WorkerThreadPool.add_task(_kept_in(task, work), true, "In-betweens")
	else:
		task.result = work.call()
	set_process(true)


## Calls [param work] and keeps what it returns in [param task]. Made where there's no
## self, so it can end after this is freed.
static func _kept_in(task: Task, work: Callable) -> Callable:
	return func() -> void: task.result = work.call()


## Makes the frame [param time] of the way from [param prepared], steered by
## [param pins]. Holds on to [param prepared] while it runs, though the pieces are let go.
static func _frame_work(prepared: PieceMorph, time: float, pins: Array[Dictionary]) -> Callable:
	return func() -> Dictionary: return prepared.frame(time, pins)


## A piece of work on a worker thread, see [method _run]
class Task:
	extends RefCounted

	## What it makes: &"motion", &"pieces" or &"frame"
	var kind: StringName
	## The movement it's for, and with the pins, as [member InBetweenMaker._version]
	var motion := Vector2i.ZERO
	var version := ""
	## How far between the keys the frame it makes is
	var time := 0.0
	## [member InBetweenMaker._starts] and [member InBetweenMaker._asks] when it started
	var start := 0
	var ask := 0
	## Tells how far working out the pieces got, and stops it
	var progress: WorkProgress
	## The worker thread task, or -1 when it ran right away
	var id := -1
	var result: Variant

	func _init(what: StringName) -> void:
		kind = what
