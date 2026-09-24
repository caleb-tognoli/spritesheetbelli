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
## Whether there are changes since the last save or open
var is_dirty: bool:
	get:
		return undo_redo.get_version() != _saved_version

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


func mark_saved() -> void:
	_saved_version = undo_redo.get_version()
	changed.emit()


## Replaces the whole state without undo history, e.g. when opening a file
func load_state(state: Dictionary, file_path := "") -> void:
	spritesheet.set_state(state)
	undo_redo.clear_history()
	path = file_path
	mark_saved()


## Empties the document and forgets its file and history
func reset() -> void:
	load_state({})
