class_name Document
extends RefCounted
## The open spritesheet with its file, unsaved state and undo history.
## Every user edit goes through [method perform] so it can be undone. The sheet's export
## settings are saved with it but aren't undone, except those of its layout.

## Emitted when the path, unsaved state or undo history changes
signal changed
## Emitted when a sheet was opened or a new one started, with the view to show, see
## [method load_state]
signal loaded(view: Dictionary)

## Export settings that are part of the sheet's layout, so undone with it. The others are
## choices of how to export, which the History doesn't show.
const LAYOUT_EXPORT_KEYS: Array[StringName] = [&"padding", &"spacing", &"extrude"]

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
		return undo_redo.get_version() != _saved_version or _export_choices() != _saved_choices

## What the history starts from, e.g. "Opened walk.png"
var history_start := "New spritesheet"
## The MD5 of each file linked frames came from, when they were last cut from it, to tell
## when it changes. Not part of the undo history.
var source_hashes: Dictionary[String, String] = {}
## Files that were exported over, so frames that undoing links to them again aren't
## reloaded from what spritesheetbelli wrote
var unwatched_paths: PackedStringArray = []
var undo_redo := UndoRedo.new()
var _saved_version := undo_redo.get_version()
## The export choices when last saved or opened. They aren't undo steps, so the version of
## the history can't tell when they changed.
var _saved_choices := {}


func _notification(what: int) -> void:
	# UndoRedo is not reference counted
	if what == NOTIFICATION_PREDELETE and is_instance_valid(undo_redo):
		undo_redo.free()


## Runs [param edit] as one undoable step named [param action_name] and returns its result.
## Nothing is recorded when the spritesheet didn't change, or only its export choices did.
func perform(action_name: String, edit: Callable) -> Variant:
	var before := _undoable_state()
	var choices := _export_choices()
	var result: Variant = spritesheet.batch(edit)
	var after := _undoable_state()
	if Spritesheet.states_equal(before, after):
		# Not a step, but still a change to save
		if _export_choices() != choices:
			changed.emit()
		return result

	# The saved state can't be reached again once a new branch of history starts
	if undo_redo.get_version() < _saved_version:
		_saved_version = -1
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(_restore.bind(after))
	undo_redo.add_undo_method(_restore.bind(before))
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
	_saved_choices = _export_choices()
	changed.emit()


## Replaces the whole state without undo history, e.g. when opening a file. [param view]
## is where the preview looked when the project was saved (see
## [method SpritesheetPreview.get_view]), or empty to show the whole sheet.
func load_state(state: Dictionary, file_path := "", image_path := "", view := {}) -> void:
	spritesheet.set_state(state)
	undo_redo.clear_history()
	source_hashes.clear()
	unwatched_paths.clear()
	path = file_path
	export_path = image_path
	last_export = ""
	var opened := file_path if file_path else image_path
	history_start = "Opened %s" % opened.get_file() if opened else "New spritesheet"
	mark_saved()
	loaded.emit(view)


## Name shown to the user: the file of [method get_name_path], empty when there's none
func get_display_name() -> String:
	return get_name_path().get_file()


## The file the document is named after: the project, else the image it came from or was
## exported to, else the file its first linked frame came from
func get_name_path() -> String:
	if path:
		return path
	if export_path:
		return export_path
	return FrameSource.get_first_path(spritesheet)


## Empties the document and forgets its file and history. The new sheet resizes with
## the filter chosen in the settings.
func reset() -> void:
	load_state({"scale_filter": Settings.get_value(&"resize_filter")})


## The sheet's state without its export choices, which aren't undone
func _undoable_state() -> Dictionary:
	var state := spritesheet.get_state()
	var export := {}
	for key in LAYOUT_EXPORT_KEYS:
		if state.export.has(key):
			export[key] = state.export[key]
	state.export = export
	return state


## The sheet's export settings that aren't part of its layout
func _export_choices() -> Dictionary:
	var choices := spritesheet.export_settings.duplicate()
	for key in LAYOUT_EXPORT_KEYS:
		choices.erase(key)
	return choices


## Goes back or forward to [param state] from the history, keeping the export choices
func _restore(state: Dictionary) -> void:
	var export: Dictionary = state.export.duplicate()
	export.merge(_export_choices())
	var restored := state.duplicate()
	restored.export = export
	spritesheet.set_state(restored)
