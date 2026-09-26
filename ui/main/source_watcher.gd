class_name SourceWatcher
extends Node
## Notices when the files linked frames came from change on disk (see [FrameSource]) and
## asks whether to reload them. Files that change while the app is in the background are
## asked about once it's back in front.

## Seconds between looks at the files
const INTERVAL := 1.0
## Files written this many seconds ago or less are read again on every look
const RECENT_SECONDS := 2

var dialog := ReloadDialog.new()
var timer := Timer.new()
## Changed files waiting to be asked about, in the order they changed
var changed_paths: PackedStringArray = []
## When each file was last looked at, so only files written since are read
var _checked_times: Dictionary[String, int] = {}
## Hashes of files that just changed, to wait until they're done being written
var _settling: Dictionary[String, String] = {}
var _reloading := false


func _ready() -> void:
	timer.wait_time = INTERVAL
	timer.timeout.connect(
		func() -> void:
			if not is_enabled():
				return
			check()
			if get_window().has_focus():
				ask_next()
	)
	add_child(timer)
	timer.start()
	add_child(dialog)
	dialog.chosen.connect(_on_chosen)


func is_enabled() -> bool:
	return Settings.get_value(&"watch_sources") and not WebFiles.is_web()


## Call when the app comes back in front: files may have been edited in the meantime
func on_focus_in() -> void:
	if is_enabled():
		check()
		ask_next()


## Looks for linked files that changed, adding them to [member changed_paths]. A file
## counts as changed once it stays the same for two looks, as programs can take a while
## to write it. Missing files are skipped: some programs save by deleting and renaming.
func check() -> void:
	var document := Global.document
	for path in FrameSource.get_sheet_paths(Global.spritesheet):
		if (
			path in document.unwatched_paths
			or path in changed_paths
			or not FileAccess.file_exists(path)
		):
			continue
		var time := FileAccess.get_modified_time(path)
		var known := document.source_hashes.has(path)
		# Times are in whole seconds, so a file written again within a second looks the same
		var recent := time >= Time.get_unix_time_from_system() - RECENT_SECONDS
		if known and _checked_times.get(path) == time and not recent and not _settling.has(path):
			continue
		var md5 := FileAccess.get_md5(path)
		if not known:
			# First seen: the frames were just cut from it
			document.source_hashes[path] = md5
			_checked_times[path] = time
		elif md5 == document.source_hashes[path]:
			_settling.erase(path)
			_checked_times[path] = time
		elif _settling.get(path) != md5:
			_settling[path] = md5
		else:
			_settling.erase(path)
			_checked_times[path] = time
			changed_paths.append(path)


## Asks about the first changed file, unless something is being asked or reloaded
func ask_next() -> void:
	if dialog.visible or _reloading or _is_busy():
		return
	# Files no frame comes from anymore, e.g. after deleting the frames, aren't asked about
	var linked := FrameSource.get_sheet_paths(Global.spritesheet)
	var still_linked: PackedStringArray = []
	for path in changed_paths:
		if path in linked and path not in Global.document.unwatched_paths:
			still_linked.append(path)
	changed_paths = still_linked
	if changed_paths.is_empty():
		return
	var path := changed_paths[0]
	var others_edited := false
	for other in changed_paths.slice(1):
		others_edited = others_edited or count_edited(other) > 0
	dialog.ask(
		path,
		FrameSource.get_linked(Global.spritesheet, path).size(),
		count_edited(path),
		changed_paths.size() - 1,
		others_edited
	)


## How many frames from [param path] were edited here
static func count_edited(path: String) -> int:
	var sheet := Global.spritesheet
	var count := 0
	for coord in FrameSource.get_linked(sheet, path):
		if FrameSource.has_edits(sheet.frame_sources[coord]):
			count += 1
	return count


func _on_chosen(choice: ReloadDialog.Choice, for_all: bool) -> void:
	if changed_paths.is_empty():
		return
	var paths := changed_paths.duplicate() if for_all else changed_paths.slice(0, 1)
	changed_paths = changed_paths.slice(paths.size())
	if choice == ReloadDialog.Choice.IGNORE:
		for path in paths:
			_remember(path)
	else:
		await reload(paths, choice == ReloadDialog.Choice.KEEP_EDITS)
	ask_next.call_deferred()


## Cuts every frame that came from [param paths] again, as one undoable step
func reload(paths: PackedStringArray, keep_edits: bool) -> void:
	var coords: Array[Vector2i] = []
	for path in paths:
		# Before reading, so changes made while reloading are noticed
		_remember(path)
		for coord in FrameSource.get_linked(Global.spritesheet, path):
			if coord not in coords:
				coords.append(coord)
	var action_name := (
		"Reload %s" % paths[0].get_file() if paths.size() == 1 else "Reload %d files" % paths.size()
	)
	await reload_frames(coords, keep_edits, action_name)


## Cuts the linked frames at [param coords] again from their files, keeping the edits
## made here or not, as one undoable step. Returns how many frames were reloaded.
func reload_frames(coords: Array[Vector2i], keep_edits: bool, action_name: String) -> int:
	var sheet := Global.spritesheet
	var sources: Array[Dictionary] = []
	var old_images: Array[Image] = []
	var keys: PackedStringArray = []
	for coord in coords:
		var source: Dictionary = sheet.frame_sources[coord]
		sources.append(source)
		old_images.append(sheet.frames[coord])
		var key := FrameSource.get_load_key(source)
		if key not in keys:
			keys.append(key)
	_reloading = true
	var progress := func(done: int, total: int) -> void: Notify.progress("Reloading", done, total)
	var files := await Parallel.map(
		keys.size(), func(i: int) -> Variant: return FrameSource.load_key(keys[i]), progress
	)
	var loaded := {}
	for i in keys.size():
		loaded[keys[i]] = files[i]
	var results := await Parallel.map(
		coords.size(),
		func(i: int) -> Dictionary:
			var pixels := FrameSource.cut(sources[i], loaded)
			if pixels == null:
				return {}
			return FrameSource.rebuild(sources[i], pixels, keep_edits),
		progress
	)
	Notify.hide_progress()
	_reloading = false

	var reloaded := 0
	for i in coords.size():
		if not results[i].is_empty():
			(results[i].image as Image).resource_name = old_images[i].resource_name
			reloaded += 1
	Global.document.perform(
		action_name,
		func() -> void:
			for i in coords.size():
				# Frames that were moved or edited in the meantime are left alone
				if results[i].is_empty() or sheet.frames.get(coords[i]) != old_images[i]:
					continue
				var source := sources[i] if keep_edits else FrameSource.without_edits(sources[i])
				sheet.set_frame(coords[i], results[i].image, source, results[i].origin)
	)
	if reloaded < coords.size():
		Notify.toast(
			(
				tr("%d frames weren't found in the changed files and were left as they were.")
				% (coords.size() - reloaded)
			),
			6.0
		)
	return reloaded


## Whether a dialog or window is open, or something is in progress: asking then would get
## in the way, so it waits until it's closed
func _is_busy() -> bool:
	if Notify.is_progress_visible():
		return true
	for node in get_tree().root.find_children("*", "Window", true, false):
		var window := node as Window
		if window != dialog and window.visible and window.exclusive:
			return true
	return false


## Takes the file as it is now as what its frames were cut from
func _remember(path: String) -> void:
	if FileAccess.file_exists(path):
		Global.document.source_hashes[path] = FileAccess.get_md5(path)
		_checked_times[path] = FileAccess.get_modified_time(path)
	_settling.erase(path)
