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
