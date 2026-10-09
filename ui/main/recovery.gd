class_name Recovery
extends Node
## Crash recovery. While a document has unsaved changes, a copy of it is kept as a project
## in a folder of its own, in a folder of this run's own in [member folder], with the path
## and name of its file and when it was written: every few minutes (the
## [code]recovery_minutes[/code] setting, 0 for never) and right after big changes, like
## adding a spritesheet or repacking. Each open tab has its own copy. It's written on a
## worker thread, so editing goes on meanwhile. Saving, replacing the document or closing
## its tab deletes it, and so does quitting.
## A folder left by a run that's no longer running is from a crash or an unclean exit:
## [member leftovers] lists the copies in those, see [RecoveryNotice], to recover or
## discard. A run writes the time in its folder every minute, see [constant ALIVE_FILE], so
## a folder whose process ID has since been given to another program counts as left too.
## Not in a browser, which never quits cleanly and has no process to check.

## Emitted when [member leftovers] changes
signal leftovers_changed

const COPY_FILE := "copy.sbelli"
## The path and name of the copy's file and when it was written
const INFO_FILE := "copy.json"
## When the run last said it's running, in seconds since 1970. It says so every
## [constant ALIVE_SECONDS]; a folder whose time is [constant ALIVE_TIMEOUT] old is left
## by a crash, even when a process with its ID is running: another program that got the
## ID, which operating systems give out again.
const ALIVE_FILE := "alive"
const ALIVE_SECONDS := 60.0
## Long enough for a busy run to catch up, as its time is written on the main thread
const ALIVE_TIMEOUT := 300
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
## Whether a process with the given ID is running. Tests stand in for it.
static var is_process_running: Callable = OS.is_process_running

## Copies left by runs that didn't quit cleanly, newest first: [code]{"dir": String,
## "path": String, "name": String, "time": int}[/code], with the folder the copy is in,
## the file it was saved to (empty when it never was), its name (empty for Untitled) and
## when it was written, in seconds since 1970
var leftovers: Array[Dictionary] = []
## This run's folder, with a folder for the copy of each document, see [method copy_dir]
var session_dir := ""
## Writes a copy every [code]recovery_minutes[/code]
var timer := Timer.new()
## Writes the time in [member session_dir] every [constant ALIVE_SECONDS], see
## [constant ALIVE_FILE]
var alive_timer := Timer.new()
var files: FileController
## Offers [member leftovers] on the start screen
var notice: RecoveryNotice
## What's known of the copy of each open document, by document
var _copies: Dictionary[Document, DocumentCopy] = {}
## The name of the folder of the next document's copy
var _next_copy := 1


func _init() -> void:
	# Freed with it, also when it's never added, as in a browser or on the command line
	add_child(timer)
	add_child(alive_timer)


func _ready() -> void:
	set_process(false)
	if not enabled:
		return
	var started := _now()
	session_dir = folder.path_join("%d_%d_%d" % [OS.get_process_id(), started, _sessions.size()])
	_sessions.append(session_dir)
	find_leftovers()
	timer.timeout.connect(save_copy_if_changed)
	_update_timer()
	alive_timer.timeout.connect(say_alive)
	alive_timer.start(ALIVE_SECONDS)
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"recovery_minutes":
				_update_timer()
	)
	Global.documents_changed.connect(_follow_documents)
	_follow_documents()


## Quitting, after the unsaved changes were saved or not, deletes the copies. A crash
## leaves them for the next run to offer.
func _exit_tree() -> void:
	if enabled:
		for document: Document in _copies.keys():
			delete_copy(document)


func _process(_delta: float) -> void:
	var writing := false
	for document: Document in _copies.keys():
		var copy := _copies[document]
		if copy.task >= 0 and WorkerThreadPool.is_task_completed(copy.task):
			_wait_for(copy)
			if copy.pending:
				copy.pending = false
				save_copy(document)
		writing = writing or copy.task >= 0
	set_process(writing)


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
			var found := false
			for copy_name in DirAccess.get_directories_at(dir):
				var info := read_info(dir.path_join(copy_name))
				if info:
					leftovers.append(info)
					found = true
			if not found:
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
## another process that is, named by its ID, and that said so lately
static func _is_running(dir: String) -> bool:
	if dir in _sessions:
		return true
	var pid := dir.get_file().get_slice("_", 0).to_int()
	if pid <= 0 or pid == OS.get_process_id() or not is_process_running.call(pid):
		return false
	var said := FileAccess.get_file_as_string(dir.path_join(ALIVE_FILE))
	return said.is_valid_int() and _now() - said.to_int() < ALIVE_TIMEOUT


## Writes the time in [member session_dir], while it has a copy, see [constant ALIVE_FILE]
func say_alive() -> void:
	if session_dir and DirAccess.dir_exists_absolute(session_dir):
		write_alive(session_dir, _now())


## Writes [param time] in [param dir] as when its run last said it's running
static func write_alive(dir: String, time: int) -> void:
	var file := FileAccess.open(dir.path_join(ALIVE_FILE), FileAccess.WRITE)
	if file:
		file.store_string(str(time))


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Whether a copy of [param document] (the active one by default) is to be kept: when it
## has unsaved changes, and frames, and copies aren't turned off
func is_needed(document: Document = null) -> bool:
	document = _or_active(document)
	return (
		enabled
		and Settings.get_value(&"recovery_minutes") > 0
		and document.is_dirty
		and not document.spritesheet.is_empty()
	)


## Writes a copy of each document that changed since its last one, see [method save_copy]
func save_copy_if_changed() -> void:
	for document: Document in _copies.keys():
		if _copies[document].changed_since_copy:
			save_copy(document)


## The folder of the copy of [param document] (the active one by default), in
## [member session_dir]. Empty when copies aren't kept.
func copy_dir(document: Document = null) -> String:
	var copy: DocumentCopy = _copies.get(_or_active(document))
	return session_dir.path_join(copy.dir_name) if session_dir and copy else ""


## Writes a copy of [param document] (the active one by default) in its
## [method copy_dir] on a worker thread, when it's needed (see [method is_needed]). While
## one is being written, the next one waits for it.
func save_copy(document: Document = null) -> void:
	document = _or_active(document)
	var copy: DocumentCopy = _copies.get(document)
	if copy == null:
		return
	copy.queued = false
	if not is_needed(document):
		return
	if copy.task >= 0:
		copy.pending = true
		return
	# Frame images are never changed in place, so a copy of the state can be saved on
	# another thread while the sheet is edited
	var sheet := Spritesheet.new()
	sheet.set_state(document.spritesheet.get_state())
	var dir := copy_dir(document)
	var extra := files.project_extra(dir, document) if files else {}
	var info := {
		"path": document.path,
		"name": document.get_display_name(),
		"time": _now(),
	}
	# The folder says the run is running before the copy is in it
	DirAccess.make_dir_recursive_absolute(dir)
	say_alive()
	copy.task = WorkerThreadPool.add_task(
		_write.bind(sheet, extra, info, dir), false, "Recovery copy"
	)
	set_process(true)
	copy.changed_since_copy = false
	copy.remember_frames(document.spritesheet)


## Waits for the copies being written, if any
func wait() -> void:
	for copy: DocumentCopy in _copies.values():
		_wait_for(copy)
	set_process(false)


func _wait_for(copy: DocumentCopy) -> void:
	if copy.task >= 0:
		WorkerThreadPool.wait_for_task_completion(copy.task)
		copy.task = -1


## Whether this run has a copy of [param document], the active one by default
func has_copy(document: Document = null) -> bool:
	var dir := copy_dir(document)
	return dir != "" and FileAccess.file_exists(dir.path_join(COPY_FILE))


## Deletes the copy of [param document] (the active one by default), e.g. once it's
## saved, and this run's folder once it has no copy left
func delete_copy(document: Document = null) -> void:
	var copy: DocumentCopy = _copies.get(_or_active(document))
	if copy == null:
		return
	copy.pending = false
	_wait_for(copy)
	var dir := copy_dir(document)
	if dir and DirAccess.dir_exists_absolute(dir):
		remove_dir(dir)
	if (
		session_dir
		and DirAccess.dir_exists_absolute(session_dir)
		and DirAccess.get_directories_at(session_dir).is_empty()
	):
		remove_dir(session_dir)


## Opens the copy [param leftover] of [member leftovers] in a tab, with unsaved changes and
## the file it was saved to, if any, so Save writes there. It's then this run's copy.
## Returns false when it can't be read.
func recover(leftover: Dictionary) -> bool:
	var result := ProjectFile.load(leftover.dir.path_join(COPY_FILE))
	if result.has("error"):
		Notify.error(result.error)
		return false
	var document := files.open_in_tab()
	files.load_project(result, leftover.path, leftover.dir, document)
	var shown_name: String = leftover.name if leftover.name else tr("Untitled")
	document.set_history_start(L10n.mark("Recovered %s"), shown_name)
	document.mark_unsaved()
	# Written before the old copy is gone, so there's always one
	save_copy(document)
	wait()
	discard(leftover)
	return true


## Deletes the copy [param leftover] of [member leftovers], and the folder of its run once
## it has no other
func discard(leftover: Dictionary) -> void:
	var dir: String = leftover.dir
	remove_dir(dir)
	var run_dir := dir.get_base_dir()
	if DirAccess.dir_exists_absolute(run_dir) and DirAccess.get_directories_at(run_dir).is_empty():
		remove_dir(run_dir)
	leftovers.erase(leftover)
	leftovers_changed.emit()


func _update_timer() -> void:
	var minutes: int = Settings.get_value(&"recovery_minutes")
	if minutes > 0:
		timer.start(minutes * 60.0)
	else:
		timer.stop()


## Keeps a copy for each open document, and deletes those of closed ones, whose changes
## were saved or given up
func _follow_documents() -> void:
	for document: Document in _copies.keys():
		if document not in Global.documents:
			delete_copy(document)
			document.changed.disconnect(_copies[document].on_changed)
			document.loaded.disconnect(_copies[document].on_loaded)
			_copies.erase(document)
	for document in Global.documents:
		if _copies.has(document):
			continue
		var copy := DocumentCopy.new()
		copy.dir_name = str(_next_copy)
		_next_copy += 1
		copy.remember_frames(document.spritesheet)
		_copies[document] = copy
		copy.on_changed = _on_document_changed.bind(document)
		copy.on_loaded = _on_document_loaded.bind(document).unbind(1)
		document.changed.connect(copy.on_changed)
		document.loaded.connect(copy.on_loaded)


func _on_document_changed(document: Document) -> void:
	var copy := _copies[document]
	if not document.is_dirty:
		# Saved, or undone back to what was
		if has_copy(document) or copy.task >= 0:
			delete_copy(document)
		copy.changed_since_copy = false
		copy.remember_frames(document.spritesheet)
		return
	copy.changed_since_copy = true
	if not copy.queued and count_changed_frames(document) >= BIG_CHANGE_FRAMES:
		copy.queued = true
		save_copy.call_deferred(document)


## Another document replaced this one, whose changes were saved or given up
func _on_document_loaded(document: Document) -> void:
	delete_copy(document)
	var copy := _copies[document]
	copy.changed_since_copy = false
	copy.remember_frames(document.spritesheet)


## How many cells of [param document] (the active one by default) hold another frame, or
## have it placed elsewhere, than when its last copy was written, or it was saved or opened
func count_changed_frames(document: Document = null) -> int:
	document = _or_active(document)
	var copy := _copies[document]
	var sheet := document.spritesheet
	var count := 0
	for coord: Vector2i in sheet.frames:
		if (
			copy.frames.get(coord) != sheet.frames[coord]
			or copy.placements.get(coord) != sheet.placements.get(coord)
		):
			count += 1
	for coord: Vector2i in copy.frames:
		if not sheet.frames.has(coord):
			count += 1
	return count


static func _or_active(document: Document) -> Document:
	return document if document else Global.document


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


## What's known of the copy of one document
class DocumentCopy:
	extends RefCounted
	## The name of its folder in [member Recovery.session_dir]
	var dir_name := ""
	## The worker task writing it, or -1
	var task := -1
	## Whether another copy is to be written once [member task] is done
	var pending := false
	## Whether a copy is to be written at the end of the frame, after a big change
	var queued := false
	## Whether the document changed since the last copy
	var changed_since_copy := false
	## The frames and their places when the last copy was written, or the document was
	## saved or opened, to tell big changes
	var frames: Dictionary = {}
	var placements: Dictionary = {}
	## Connected to the document's signals
	var on_changed: Callable
	var on_loaded: Callable

	func remember_frames(sheet: Spritesheet) -> void:
		frames = sheet.frames.duplicate()
		placements = sheet.placements.duplicate()
