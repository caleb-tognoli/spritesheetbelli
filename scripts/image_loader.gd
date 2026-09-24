class_name ImageLoader
## Loads images on worker threads so the window stays responsive.


## Loads [param paths] in parallel. Returns the images in the same order, with null for
## files that couldn't be loaded. [param on_progress] is called with (done, total) every frame.
static func load_all(paths: PackedStringArray, on_progress := Callable()) -> Array[Image]:
	var images: Array[Image] = []
	images.resize(paths.size())
	if paths.is_empty():
		return images
	var mutex := Mutex.new()
	var load_one := func(i: int) -> void:
		var img := Image.load_from_file(paths[i])
		if img:
			img.resource_name = paths[i].get_file()
		mutex.lock()
		images[i] = img
		mutex.unlock()
	var task := WorkerThreadPool.add_group_task(load_one, paths.size())
	var tree := Engine.get_main_loop() as SceneTree
	while not WorkerThreadPool.is_group_task_completed(task):
		if on_progress.is_valid():
			on_progress.call(WorkerThreadPool.get_group_processed_element_count(task), paths.size())
		await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	return images
