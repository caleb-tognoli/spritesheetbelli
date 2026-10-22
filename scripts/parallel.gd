class_name Parallel
## Runs work on worker threads while the window stays responsive.


## Calls [param work] with each index from 0 to [param count] - 1 and returns the results
## in order. Runs on worker threads, or spread over frames in builds without threads (such
## as the web build). [param on_progress] is called with (done, total) every frame.
static func map(count: int, work: Callable, on_progress := Callable()) -> Array:
	var results := []
	results.resize(count)
	if count == 0:
		return results
	var tree := Engine.get_main_loop() as SceneTree
	if not OS.has_feature("threads"):
		var frame_start := Time.get_ticks_msec()
		for i in count:
			results[i] = work.call(i)
			if Time.get_ticks_msec() - frame_start > 30:
				if on_progress.is_valid():
					on_progress.call(i + 1, count)
				await tree.process_frame
				frame_start = Time.get_ticks_msec()
		return results
	var mutex := Mutex.new()
	var run_one := func(i: int) -> void:
		var value: Variant = work.call(i)
		mutex.lock()
		results[i] = value
		mutex.unlock()
	var task := WorkerThreadPool.add_group_task(run_one, count)
	while not WorkerThreadPool.is_group_task_completed(task):
		if on_progress.is_valid():
			on_progress.call(WorkerThreadPool.get_group_processed_element_count(task), count)
		await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	return results


## Calls [param work] on a worker thread and returns its result, while the window keeps
## drawing. Calls it right away in builds without threads.
static func run(work: Callable) -> Variant:
	return (await map(1, func(_i: int) -> Variant: return work.call()))[0]


## Splits the indices from 0 to [param count] - 1 into runs of at least [param least]
## (fewer when there are fewer), calls [param work] with each run's start and end (past its
## last) on threads of their own at once, on half the processor's threads at most, and
## returns what each returned, in order; waits for them all. Calls it once with the whole
## range in builds without threads. Unlike [method map] it can be called from a worker
## thread: waiting there for other worker threads can stall when there are few.
static func split(count: int, least: int, work: Callable) -> Array:
	var runs := 1
	if OS.has_feature("threads"):
		var most := ceili(float(count) / maxi(least, 1))
		runs = clampi(mini(OS.get_processor_count() / 2, most), 1, 16)
	if runs <= 1:
		return [work.call(0, count)]
	var results := []
	results.resize(runs)
	var threads: Array[Thread] = []
	for k in range(1, runs):
		var thread := Thread.new()
		thread.start(work.bind(count * k / runs, count * (k + 1) / runs))
		threads.append(thread)
	results[0] = work.call(0, count / runs)
	for k in threads.size():
		results[k + 1] = threads[k].wait_to_finish()
	return results


## Calls [param work] with each index from 0 to [param count] - 1, on threads of their own
## at once (see [method split]) unless [param threaded] is false, and returns the results
## in order
static func each(count: int, work: Callable, threaded := true) -> Array:
	if not threaded:
		return _each_of(0, count, work)
	var results := []
	for part: Array in split(count, 1, _each_of.bind(work)):
		results.append_array(part)
	return results


static func _each_of(start: int, end: int, work: Callable) -> Array:
	var results := []
	for i in range(start, end):
		results.append(work.call(i))
	return results
