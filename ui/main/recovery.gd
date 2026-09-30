class_name Recovery
extends Node
## Crash recovery. While the document has unsaved changes, a copy of it is kept as a
## project in a folder of this run's own in [member folder], with the path and name of its
## file and when it was written: every few minutes (the [code]recovery_minutes[/code]
## setting, 0 for never) and right after big changes, like adding a spritesheet or
## repacking. It's written on a worker thread, so editing goes on meanwhile. Saving, or
## replacing the document, deletes it, and so does quitting.
## A folder left by a run that's no longer running is from a crash or an unclean exit:
## [member leftovers] lists those, see [RecoveryNotice], to recover or discard.
## Not in a browser, which never quits cleanly and has no process to check.

## Emitted when [member leftovers] changes
signal leftovers_changed

const COPY_FILE := "copy.sbelli"
## The path and name of the copy's file and when it was written
const INFO_FILE := "copy.json"
## Changing this many frames since the last copy, or moving them in the packed layout,
## writes a copy right away
const BIG_CHANGE_FRAMES := 16

## Where the copies are kept. Tests use their own folder.
static var folder := "user://recovery"
## Whether copies are kept, not in a browser
static var enabled := not WebFiles.is_web()
## The folders of runs in this process, which are running even though their process ID
## may be an older run's
static var _sessions: PackedStringArray = []

## Copies left by runs that didn't quit cleanly, newest first: [code]{"dir": String,
## "path": String, "name": String, "time": int}[/code], with the folder the copy is in,
## the file it was saved to (empty when it never was), its name (empty for Untitled) and
## when it was written, in seconds since 1970
var leftovers: Array[Dictionary] = []
## This run's folder, where its copy is written
var session_dir := ""
## Writes a copy every [code]recovery_minutes[/code]
var timer := Timer.new()
var files: FileController
## Offers [member leftovers] on the start screen
var notice: RecoveryNotice
## The worker task writing a copy, or -1
var _task := -1
## Whether another copy is to be written once [member _task] is done
var _pending := false
var _copy_queued := false
## Whether the document changed since the last copy
var _changed_since_copy := false
## The frames and their places when the last copy was written, or the document was
## saved or opened, to tell big changes
var _frames: Dictionary = {}
var _placements: Dictionary = {}


func _init() -> void:
	# Freed with it, also when it's never added, as in a browser or on the command line
	add_child(timer)


func _ready() -> void:
	set_process(false)
	if not enabled:
		return
	var started := int(Time.get_unix_time_from_system())
	session_dir = folder.path_join("%d_%d_%d" % [OS.get_process_id(), started, _sessions.size()])
	_sessions.append(session_dir)
	find_leftovers()
	timer.timeout.connect(save_copy_if_changed)
	_update_timer()
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"recovery_minutes":
				_update_timer()
	)
	Global.document.changed.connect(_on_document_changed)
	Global.document.loaded.connect(_on_document_loaded.unbind(1))
	_remember_frames()


## Quitting, after the unsaved changes were saved or not, deletes the copy. A crash
## leaves it for the next run to offer.
func _exit_tree() -> void:
	if enabled:
		delete_copy()


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		wait()
		if _pending:
			_pending = false
			save_copy()


## Uses [param controller] to open the copies it recovers, and offers them on
## [param start_screen], see [RecoveryNotice]
func setup(controller: FileController, start_screen: StartScreen = null) -> void:
	files = controller
	if start_screen:
		notice = RecoveryNotice.new()
		start_screen.add_notice(notice)
		notice.setup(self)


## Lists the copies left by runs that are no longer running, see [member leftovers], and
## deletes their folders that have none
func find_leftovers() -> void:
	leftovers.clear()
	if DirAccess.dir_exists_absolute(folder):
		for dir_name in DirAccess.get_directories_at(folder):
			var dir := folder.path_join(dir_name)
			if _is_running(dir):
				continue
			var info := read_info(dir)
			if info:
				leftovers.append(info)
			else:
				remove_dir(dir)
	leftovers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time > b.time)
	leftovers_changed.emit()


## The copy in [param dir] as listed in [member leftovers], or empty when there's none
static func read_info(dir: String) -> Dictionary:
	var copy := dir.path_join(COPY_FILE)
	if not FileAccess.file_exists(copy):
		return {}
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(INFO_FILE)))
	if not info is Dictionary:
		info = {}
	return {
		"dir": dir,
		"path": str(info.get("path", "")),
		"name": str(info.get("name", "")),
		"time": int(info.get("time", FileAccess.get_modified_time(copy))),
	}


## Whether the run that made [param dir] is still running: one in this process, or in
## another process that is, named by its ID
static func _is_running(dir: String) -> bool:
	if dir in _sessions:
		return true
	var pid := dir.get_file().get_slice("_", 0).to_int()
	return pid > 0 and pid != OS.get_process_id() and OS.is_process_running(pid)


## Whether a copy of the document is to be kept: when it has unsaved changes, and frames,
## and copies aren't turned off
func is_needed() -> bool:
	return (
		enabled
		and Settings.get_value(&"recovery_minutes") > 0
		and Global.document.is_dirty
		and not Global.spritesheet.is_empty()
	)


## Writes a copy if the document changed since the last one, see [method save_copy]
func save_copy_if_changed() -> void:
	if _changed_since_copy:
		save_copy()


## Writes a copy of the document in [member session_dir] on a worker thread, when it's
## needed (see [method is_needed]). While one is being written, the next one waits for it.
func save_copy() -> void:
	_copy_queued = false
	if not is_needed():
		return
	if _task >= 0:
		_pending = true
		return
	var document := Global.document
	# Frame images are never changed in place, so a copy of the state can be saved on
	# another thread while the sheet is edited
	var sheet := Spritesheet.new()
	sheet.set_state(Global.spritesheet.get_state())
	var extra := files.project_extra(session_dir) if files else {}
	var info := {
		"path": document.path,
		"name": document.get_display_name(),
		"time": int(Time.get_unix_time_from_system()),
	}
	_task = WorkerThreadPool.add_task(
		_write.bind(sheet, extra, info, session_dir), false, "Recovery copy"
	)
	set_process(true)
	_changed_since_copy = false
	_remember_frames()


## Waits for the copy being written, if any
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	set_process(false)


## Whether this run has a copy of the document
func has_copy() -> bool:
	return session_dir and FileAccess.file_exists(session_dir.path_join(COPY_FILE))


## Deletes the copy of the document, e.g. once it's saved
func delete_copy() -> void:
	_pending = false
	wait()
	if session_dir and DirAccess.dir_exists_absolute(session_dir):
		remove_dir(session_dir)


## Opens the copy [param leftover] of [member leftovers] as the document, with unsaved
## changes and the file it was saved to, if any, so Save writes there. It's then this
## run's copy. Returns false when it can't be read.
func recover(leftover: Dictionary) -> bool:
	var result := ProjectFile.load(leftover.dir.path_join(COPY_FILE))
	if result.has("error"):
		Notify.error(result.error)
		return false
	files.load_project(result, leftover.path, leftover.dir)
	var document := Global.document
	var shown_name: String = leftover.name if leftover.name else tr("Untitled")
	document.history_start = tr("Recovered %s") % shown_name
	document.mark_unsaved()
	# Written before the old copy is gone, so there's always one
	save_copy()
	wait()
	discard(leftover)
	return true


## Deletes the copy [param leftover] of [member leftovers]
func discard(leftover: Dictionary) -> void:
	remove_dir(leftover.dir)
	leftovers.erase(leftover)
	leftovers_changed.emit()


func _update_timer() -> void:
	var minutes: int = Settings.get_value(&"recovery_minutes")
	if minutes > 0:
		timer.start(minutes * 60.0)
	else:
		timer.stop()


func _on_document_changed() -> void:
	if not Global.document.is_dirty:
		# Saved, or undone back to what was
		if has_copy() or _task >= 0:
			delete_copy()
		_changed_since_copy = false
		_remember_frames()
		return
	_changed_since_copy = true
	if not _copy_queued and count_changed_frames() >= BIG_CHANGE_FRAMES:
		_copy_queued = true
		save_copy.call_deferred()


## Another document replaced this one, whose changes were saved or given up
func _on_document_loaded() -> void:
	delete_copy()
	_changed_since_copy = false
	_remember_frames()


## How many cells hold another frame, or have it placed elsewhere, than when the last
## copy was written, or the document was saved or opened
func count_changed_frames() -> int:
	var sheet := Global.spritesheet
	var count := 0
	for coord: Vector2i in sheet.frames:
		if (
			_frames.get(coord) != sheet.frames[coord]
			or _placements.get(coord) != sheet.placements.get(coord)
		):
			count += 1
	for coord: Vector2i in _frames:
		if not sheet.frames.has(coord):
			count += 1
	return count


func _remember_frames() -> void:
	_frames = Global.spritesheet.frames.duplicate()
	_placements = Global.spritesheet.placements.duplicate()


## Saves [param sheet] with [param extra] as the copy in [param dir], and [param info]
## next to it. The copy is written under another name first, so a crash meanwhile leaves
## the last one whole.
static func _write(sheet: Spritesheet, extra: Dictionary, info: Dictionary, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var temp := dir.path_join(COPY_FILE + ".tmp")
	var error := ProjectFile.save(sheet, temp, extra)
	if error == OK:
		error = DirAccess.rename_absolute(temp, dir.path_join(COPY_FILE))
	if error != OK:
		DirAccess.remove_absolute(temp)
		return
	var file := FileAccess.open(dir.path_join(INFO_FILE), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(info, "\t"))


## Like "2026-09-30 14:05", in the local time zone, for [param time] in seconds since 1970
static func describe_time(time: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var date := Time.get_datetime_dict_from_unix_time(time + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute]


## Deletes a folder and everything in it
static func remove_dir(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		remove_dir(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
