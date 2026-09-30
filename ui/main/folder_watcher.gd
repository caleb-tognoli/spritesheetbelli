class_name FolderWatcher
extends Node
## Follows the images in the sheet's linked folders (see [method Spritesheet.link_folder]):
## new ones are added as sprites, placed as the "add_mode" setting says, and frames whose
## files were deleted can be removed. A file deleted while one with the same content
## appears was renamed: its frames are linked to the new name. Only images right in the
## folder count, not those in its subfolders, like Add Folder.
## [SourceWatcher] says when to look and when to apply what changed, so it looks as often,
## is turned off by the same setting and waits until the app is in front.

## How many deleted files the dialog names
const MAX_NAMES := 5

## Whether it runs in a browser, which only gets copies of the files picked, so folders
## aren't linked there and linked ones aren't shown. Tests change it to act as the web build.
static var in_browser := WebFiles.is_web()

var dialog := ConfirmationDialog.new()
## True while new files are being added
var working := false
## What changed in each folder once every file is done being written:
## [code]{"added": PackedStringArray, "deleted": PackedStringArray}[/code], full paths
var _pending: Dictionary[String, Dictionary] = {}
## Hashes of new files, to wait until they're done being written, by path
var _settling: Dictionary[String, String] = {}
## Known files seen missing once, to wait for a second look: some programs save by
## deleting and renaming
var _missing: Dictionary[String, bool] = {}
## Files whose frames the dialog asks about removing
var _deleted_paths: PackedStringArray = []


func _init() -> void:
	dialog.title = "Files Deleted"
	dialog.ok_button_text = "Remove"
	dialog.cancel_button_text = "Keep"
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(400, 0)
	DialogButtons.apply(dialog)
	dialog.confirmed.connect(_remove_deleted)
	dialog.canceled.connect(func() -> void: _deleted_paths.clear())


func _ready() -> void:
	add_child(dialog)


## Takes the images in [param folder] now as the ones it has, so only files added or
## deleted from now on count. Call before linking it.
static func remember(folder: String) -> void:
	Global.document.folder_files[folder] = get_image_names(folder)


## The names of the images right in [param folder], see [method FileController.is_image_path]
static func get_image_names(folder: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for file in DirAccess.get_files_at(folder):
		if FileController.is_image_path(file):
			names.append(file)
	return names


## Looks for images added to or deleted from the linked folders. A folder's changes count
## once every new file stayed the same for two looks and every deleted one stayed gone,
## so a renamed file is seen deleted and added at once. A folder that's gone is left
## alone: it may be on a drive that's unplugged.
func check() -> void:
	if in_browser:
		return
	var document := Global.document
	var linked := FrameSource.get_sheet_paths(Global.spritesheet)
	var looked_at := {}
	_pending.clear()
	for folder in Global.spritesheet.linked_folders:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var names := get_image_names(folder)
		if not document.folder_files.has(folder):
			document.folder_files[folder] = names
			continue
		var known := document.folder_files[folder]
		var settled := true
		var added: PackedStringArray = []
		for file in names:
			var path := folder.path_join(file)
			if file in known:
				continue
			# Linked already, e.g. a deleted file whose frames were kept is back
			if path in linked:
				known.append(file)
				document.folder_files[folder] = known
				continue
			looked_at[path] = true
			var md5 := FileAccess.get_md5(path)
			if md5 and _settling.get(path) == md5:
				added.append(path)
			else:
				_settling[path] = md5
				settled = false
		var deleted: PackedStringArray = []
		for file in known:
			var path := folder.path_join(file)
			if file in names:
				continue
			looked_at[path] = true
			if _missing.has(path):
				deleted.append(path)
			else:
				_missing[path] = true
				settled = false
		if settled and not (added.is_empty() and deleted.is_empty()):
			_pending[folder] = {"added": added, "deleted": deleted}
	# Forgets files that were added or deleted and aren't anymore
	for path: String in _settling.keys():
		if not looked_at.has(path):
			_settling.erase(path)
	for path: String in _missing.keys():
		if not looked_at.has(path):
			_missing.erase(path)


## Whether [method check] found changes to apply
func has_changes() -> bool:
	return not _pending.is_empty()


## Applies the changes [method check] found: links frames to renamed files, adds new files
## as one undoable step and asks whether to remove the frames of deleted ones
func apply() -> void:
	if working or dialog.visible or _pending.is_empty():
		return
	var document := Global.document
	var new_names := {}
	var added: PackedStringArray = []
	var deleted: PackedStringArray = []
	var folder_names: PackedStringArray = []
	for folder: String in _pending:
		# Unlinked, or another project was opened since the look
		if folder not in Global.spritesheet.linked_folders or not document.folder_files.has(folder):
			continue
		var changes: Dictionary = _pending[folder]
		# The new files by hash, less those that are renamed ones
		var hashes := {}
		for path: String in changes.added:
			hashes[path] = _settling[path]
			_settling.erase(path)
		for path: String in changes.deleted:
			_missing.erase(path)
			var md5: String = document.source_hashes.get(path, "")
			var new_path: Variant = hashes.find_key(md5) if md5 else null
			if new_path != null:
				hashes.erase(new_path)
				new_names[path] = new_path
			else:
				deleted.append(path)
		var files := document.folder_files[folder]
		for path: String in changes.deleted:
			var index := files.find(path.get_file())
			if index >= 0:
				files.remove_at(index)
		for path: String in changes.added:
			files.append(path.get_file())
		document.folder_files[folder] = files
		if not hashes.is_empty():
			added.append_array(PackedStringArray(hashes.keys()))
			folder_names.append(folder.get_file())
	_pending.clear()

	if not new_names.is_empty():
		_follow_renames(new_names)
	if not added.is_empty():
		working = true
		var count := await FileController.add_image_files(added, L10n.mark("Add new sprites"))
		working = false
		if count > 0:
			Notify.toast(
				(
					tr_n("Added %d new sprite from %s.", "Added %d new sprites from %s.", count)
					% [count, ", ".join(folder_names)]
				)
			)
	_ask_about_deleted(deleted)


## Links the frames of each renamed file in [param new_names] (old path: new path) to its
## new name, as one undoable step
func _follow_renames(new_names: Dictionary) -> void:
	var sheet := Global.spritesheet
	var document := Global.document
	for path: String in new_names:
		if document.source_hashes.has(path):
			document.source_hashes[new_names[path]] = document.source_hashes[path]
			document.source_hashes.erase(path)
	document.perform(
		L10n.mark("Follow renamed files"),
		func() -> void:
			for coord: Vector2i in sheet.frame_sources.keys():
				var source: Dictionary = sheet.frame_sources[coord]
				if new_names.has(source.get("path")):
					var moved := source.duplicate(true)
					moved.path = new_names[source.path]
					sheet.set_frame(
						coord, sheet.frames[coord], moved, FrameSource.get_origin(sheet, coord)
					)
	)


## Asks whether to remove the frames of [param paths], if any is left
func _ask_about_deleted(paths: PackedStringArray) -> void:
	_deleted_paths.append_array(paths)
	var frames := _count_deleted_frames()
	if frames == 0:
		_deleted_paths.clear()
		return
	var names: PackedStringArray = []
	for path in _deleted_paths.slice(0, MAX_NAMES):
		names.append(path.get_file())
	if _deleted_paths.size() > MAX_NAMES:
		names.append("…")
	dialog.dialog_text = (
		(
			tr_n(
				"Remove %d frame whose file was deleted?",
				"Remove %d frames whose files were deleted?",
				frames
			)
			% frames
		)
		+ "\n\n"
		+ ", ".join(names)
	)
	dialog.popup_centered()


func _count_deleted_frames() -> int:
	var count := 0
	for path in _deleted_paths:
		count += FrameSource.get_linked(Global.spritesheet, path).size()
	return count


func _remove_deleted() -> void:
	var coords: Array[Vector2i] = []
	for path in _deleted_paths:
		coords.append_array(FrameSource.get_linked(Global.spritesheet, path))
	_deleted_paths.clear()
	Global.document.perform(
		L10n.mark("Remove frames of deleted files"), Global.spritesheet.remove_frames.bind(coords)
	)
