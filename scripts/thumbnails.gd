class_name Thumbnails
## Small previews of recent files for the start screen (see [StartScreen]), cached as PNGs
## in [member folder]. Each is named after a hash of its file's path and the file's modified
## time, so a file changed since has none, and the old one is replaced by the next.
## Thumbnails are made on worker threads: [method take_finished] tells when they're ready.
## A browser has no recent files to show them for, so none are made there.

## Thumbnails fit in a square this big
const SIZE := 256

static var folder := "user://thumbnails"
## Whether thumbnails are made, not in a browser
static var enabled := not WebFiles.is_web()
## Worker tasks making thumbnails, by the file they're for
static var _tasks: Dictionary[String, int] = {}


## Where the thumbnail of [param file] as it is now goes, or empty when it doesn't exist
static func get_path_for(file: String) -> String:
	if not FileAccess.file_exists(file):
		return ""
	return folder.path_join("%s_%d.png" % [file.md5_text(), FileAccess.get_modified_time(file)])


## The thumbnail of [param file] as it is now, or null when there's none yet
static func load_image(file: String) -> Image:
	var path := get_path_for(file)
	if not path or not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


## Makes the thumbnail of the project saved at [param file] from [param sheet] as it's
## exported. When [param replace] is false, one made from the file as it is now is kept.
static func make_for_sheet(file: String, sheet: Spritesheet, replace := true) -> void:
	var target := _target(file, replace)
	if not target:
		return
	# Frame images are never changed in place, so a copy of the state can be drawn on
	# another thread while the sheet is edited
	var copy := Spritesheet.new()
	copy.set_state(sheet.get_state())
	var options := ExportOptions.from_sheet(sheet)
	options.scale = 1
	_start(file, func() -> void: _save(render(copy, options), target))


## Makes the thumbnail of the image file [param file] from the file, unless it has one
static func make_for_image(file: String) -> void:
	var target := _target(file, false)
	if target:
		_start(file, func() -> void: _save(_load_first_frame(file), target))


## Whether a thumbnail of [param file] is being made
static func is_making(file: String) -> bool:
	return _tasks.has(file)


## The files whose thumbnails were made since last asked. Call it now and then, from the
## main thread, so the worker tasks are released.
static func take_finished() -> PackedStringArray:
	var finished: PackedStringArray = []
	for file: String in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[file]):
			WorkerThreadPool.wait_for_task_completion(_tasks[file])
			_tasks.erase(file)
			finished.append(file)
	return finished


## Waits until every thumbnail is made, e.g. before quitting
static func wait_for_all() -> PackedStringArray:
	var finished: PackedStringArray = []
	for file: String in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[file])
		finished.append(file)
	_tasks.clear()
	return finished


## Deletes the thumbnails of [param file]
static func forget(file: String) -> void:
	if _tasks.has(file):
		WorkerThreadPool.wait_for_task_completion(_tasks[file])
		_tasks.erase(file)
	_remove_others(file.md5_text(), "")


## [param sheet] as it's exported with [param options], its first page when packed, fitted
## in [constant SIZE]. Null when it has no frames.
static func render(sheet: Spritesheet, options: ExportOptions) -> Image:
	if sheet.is_empty():
		return null
	var img: Image
	if sheet.layout == Spritesheet.Layout.PACKED:
		var pages := SpritesheetExporter.build_pages(sheet, options)
		img = pages[0] if not pages.is_empty() else null
	else:
		img = SpritesheetExporter.build_image(sheet, options)
	return fit(img)


## [param img] made smaller to fit in [constant SIZE], or as it is when it already fits
static func fit(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	var longest := maxi(img.get_width(), img.get_height())
	if longest <= SIZE:
		return img
	var factor := float(SIZE) / longest
	var size := (Vector2(img.get_size()) * factor).round().max(Vector2.ONE)
	img.resize(int(size.x), int(size.y), Image.INTERPOLATE_LANCZOS)
	return img


## Where the thumbnail of [param file] goes, or empty when none is to be made: in a
## browser, for a file that doesn't exist, or when it has one and [param replace] is false
static func _target(file: String, replace: bool) -> String:
	if not enabled:
		return ""
	var target := get_path_for(file)
	if not target or (not replace and FileAccess.file_exists(target)):
		return ""
	return target


## Runs [param work] on a worker thread, after what was already making the thumbnail of
## [param file], which would otherwise delete the new one when it's done
static func _start(file: String, work: Callable) -> void:
	if _tasks.has(file):
		WorkerThreadPool.wait_for_task_completion(_tasks[file])
	_tasks[file] = WorkerThreadPool.add_task(work, false, "Thumbnail")


## Saves [param img] fitted at [param target] and deletes the older thumbnails of its file
static func _save(img: Image, target: String) -> void:
	img = fit(img)
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if img.save_png(target) == OK:
		var file_name := target.get_file()
		_remove_others(file_name.get_slice("_", 0), file_name, target.get_base_dir())


## Deletes the thumbnails in [param dir] of the file whose path hashes to [param prefix],
## except [param keep]
static func _remove_others(prefix: String, keep: String, dir := folder) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file_name in DirAccess.get_files_at(dir):
		if file_name.begins_with(prefix + "_") and file_name != keep:
			DirAccess.remove_absolute(dir.path_join(file_name))


static func _load_first_frame(file: String) -> Image:
	var frames := ImageLoader.load_frames(file)
	return frames[0] if not frames.is_empty() else null
