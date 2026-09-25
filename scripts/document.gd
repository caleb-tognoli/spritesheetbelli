class_name Document
extends RefCounted
## The open spritesheet with its file, unsaved state and undo history.
## Every user edit goes through [method perform] so it can be undone.

## Emitted when the path, unsaved state or undo history changes
signal changed

var spritesheet := Spritesheet.new()
## File the document was opened from or last saved to
var path := "":
	set(v):
		path = v
		changed.emit()
## Image the spritesheet was opened from or last exported to
var export_path := "":
	set(v):
		export_path = v
		changed.emit()
## Where the last export went (a file, or a folder of sprites), for exporting again
var last_export := "":
	set(v):
		last_export = v
		changed.emit()
## Whether there are changes since the last save or open
var is_dirty: bool:
	get:
		return undo_redo.get_version() != _saved_version

## What the history starts from, e.g. "Opened walk.png"
var history_start := "New spritesheet"
var undo_redo := UndoRedo.new()
var _saved_version := undo_redo.get_version()


func _notification(what: int) -> void:
	# UndoRedo is not reference counted
	if what == NOTIFICATION_PREDELETE and is_instance_valid(undo_redo):
		undo_redo.free()


## Runs [param edit] as one undoable step named [param action_name] and returns its result.
## Nothing is recorded when the spritesheet didn't change.
func perform(action_name: String, edit: Callable) -> Variant:
	var before := spritesheet.get_state()
	var result: Variant = spritesheet.batch(edit)
	var after := spritesheet.get_state()
	if Spritesheet.states_equal(before, after):
		return result

	# The saved state can't be reached again once a new branch of history starts
	if undo_redo.get_version() < _saved_version:
		_saved_version = -1
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(spritesheet.set_state.bind(after))
	undo_redo.add_undo_method(spritesheet.set_state.bind(before))
	undo_redo.commit_action(false)
	changed.emit()
	return result


func can_undo() -> bool:
	return undo_redo.has_undo()


func can_redo() -> bool:
	return undo_redo.has_redo()


func undo() -> void:
	if undo_redo.undo():
		changed.emit()


func redo() -> void:
	if undo_redo.redo():
		changed.emit()


## Names of the undoable steps, oldest first, including those that were undone
func get_history() -> PackedStringArray:
	var names: PackedStringArray = []
	for i in undo_redo.get_history_count():
		names.append(undo_redo.get_action_name(i))
	return names


## How many steps of [method get_history] are applied
func get_history_position() -> int:
	return undo_redo.get_current_action() + 1


## Undoes or redoes until [param position] steps of the history are applied
func go_to_history(position: int) -> void:
	position = clampi(position, 0, undo_redo.get_history_count())
	if position == get_history_position():
		return
	while get_history_position() > position and undo_redo.undo():
		pass
	while get_history_position() < position and undo_redo.redo():
		pass
	changed.emit()


func mark_saved() -> void:
	_saved_version = undo_redo.get_version()
	changed.emit()


## Replaces the whole state without undo history, e.g. when opening a file
func load_state(state: Dictionary, file_path := "", image_path := "") -> void:
	spritesheet.set_state(state)
	undo_redo.clear_history()
	path = file_path
	export_path = image_path
	last_export = ""
	var opened := file_path if file_path else image_path
	history_start = "Opened %s" % opened.get_file() if opened else "New spritesheet"
	mark_saved()


## Name shown to the user: the project file, else the image it came from
func get_display_name() -> String:
	if path:
		return path.get_file()
	return export_path.get_file()


## Empties the document and forgets its file and history. The new sheet resizes with
## the filter chosen in the settings.
func reset() -> void:
	load_state({"scale_filter": Settings.get_value(&"resize_filter")})
