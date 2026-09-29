class_name FileController
extends Node
## Opening, saving and adding files, with the dialogs they need. [member exports] writes
## exports.

const PROJECT_FILTER := "*.sbelli ; spritesheetbelli projects"
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.jpe, *.webp, *.gif ; Images"
const DATA_FILTER := "*.json, *.atlas ; Spritesheet data (TexturePacker, Aseprite, Phaser, libGDX)"
## Work above these sizes shows a "please wait" overlay first
const SLOW_PIXELS := 4_000_000
const SLOW_FILE_BYTES := 4_000_000

@export var add_spritesheet_window: AddSpritesheetWindow

## True while the Add Spritesheet window shows a file picked with Open
var loading_opened_file := false
var set_filepath_when_opening_spritesheet := false
## Runs after the next successful save, e.g. closing the app after "Save"
var after_save: Callable
var unsaved_changes_dialog := ConfirmationDialog.new()
var after_unsaved_changes: Callable
var open_file_dialogs: Array[FileDialog] = []
var open_dialog := _create_file_dialog(
	"Open", FileDialog.FILE_MODE_OPEN_FILE, [PROJECT_FILTER, IMAGE_FILTER, DATA_FILTER]
)
var save_project_dialog := _create_file_dialog(
	"Save Project", FileDialog.FILE_MODE_SAVE_FILE, [PROJECT_FILTER]
)
var open_folder_dialog := _create_file_dialog("Add Folder", FileDialog.FILE_MODE_OPEN_DIR, [])
var replace_image_dialog := _create_file_dialog(
	"Replace Image", FileDialog.FILE_MODE_OPEN_FILE, [IMAGE_FILTER]
)
var _replace_coord := Vector2i.ZERO
## Writes exports, see [ExportController]
var exports := ExportController.new()
## Returns the preview's view (see [method SpritesheetPreview.get_view]), saved with projects
var get_view := func() -> Dictionary: return {}

@onready var open_sprites_dialog: FileDialog = $OpenSpritesDialog
@onready var open_spritesheet_dialog: FileDialog = $OpenSpritesheetDialog


func _ready() -> void:
	open_sprites_dialog.filters = [IMAGE_FILTER]
	open_spritesheet_dialog.filters = [IMAGE_FILTER, DATA_FILTER]
	open_sprites_dialog.files_selected.connect(add_sprites_from_paths)
	open_spritesheet_dialog.file_selected.connect(show_add_spritesheet_window)
	open_dialog.file_selected.connect(open_path)
	save_project_dialog.file_selected.connect(save_project)
	save_project_dialog.canceled.connect(func() -> void: after_save = Callable())
	open_folder_dialog.dir_selected.connect(add_sprites_from_folder)
	add_child(exports)
	add_child(open_dialog)
	add_child(save_project_dialog)
	add_child(open_folder_dialog)
	add_child(replace_image_dialog)
	replace_image_dialog.file_selected.connect(
		func(path: String) -> void:
			var img := Image.load_from_file(path)
			if not img:
				Notify.error(tr("Could not load %s.") % path.get_file())
				return
			img.resource_name = path.get_file()
			_linking(path)
			var sheet := Global.spritesheet
			Global.document.perform(
				"Replace image",
				sheet.replace_frame.bind(_replace_coord, img, FrameSource.for_file(path))
			)
	)
	get_window().files_dropped.connect(open_dropped_files)
	# A dialog that closed without saying so (some native dialogs) would otherwise block
	# its button for good. The window only regains focus once the dialog is gone.
	get_window().focus_entered.connect(open_file_dialogs.clear)

	# Loading the opened file is not an unsaved change
	add_spritesheet_window.frames_added.connect(
		func() -> void:
			if loading_opened_file:
				loading_opened_file = false
				Global.document.load_state(
					Global.spritesheet.get_state(), "", Global.document.export_path
				)
	)
	# Nothing was opened after all, so the start screen shows again
	add_spritesheet_window.canceled.connect(
		func() -> void:
			if loading_opened_file:
				loading_opened_file = false
				Global.document.reset()
	)

	_create_unsaved_changes_dialog()
	for dialog: FileDialog in [
		open_sprites_dialog,
		open_spritesheet_dialog,
		open_dialog,
		save_project_dialog,
		open_folder_dialog,
		replace_image_dialog,
	]:
		var on_closed := func() -> void: open_file_dialogs.erase(dialog)
		dialog.canceled.connect(on_closed)
		dialog.file_selected.connect(on_closed.unbind(1))
		dialog.files_selected.connect(on_closed.unbind(1))
		dialog.dir_selected.connect(on_closed.unbind(1))


## Native file dialogs don't make the FileDialog visible, so calling popup() while
## one is already open spawns a second dialog, and each one emits its selection.
func popup_file_dialog(dialog: FileDialog) -> void:
	if WebFiles.is_web():
		_web_file_dialog(dialog)
		return
	if dialog in open_file_dialogs:
		return
	open_file_dialogs.append(dialog)
	dialog.popup()


## In a browser, file dialogs can't reach the user's files: opening uses the browser's
## file picker and saving writes into the browser, then downloads the file
func _web_file_dialog(dialog: FileDialog) -> void:
	var images := WebFiles.IMAGE_TYPES
	var images_and_data := images + "," + WebFiles.DATA_TYPES
	# A data file is picked along with its image, so they land in the same folder
	var emit_main := func(paths: PackedStringArray) -> void:
		if not paths.is_empty():
			dialog.file_selected.emit(main_picked_file(paths))
	match dialog:
		open_sprites_dialog:
			WebFiles.pick(images, true, add_sprites_from_paths)
		open_folder_dialog:
			WebFiles.pick(images, true, add_sprites_from_paths, true)
		open_spritesheet_dialog:
			WebFiles.pick(images_and_data, true, emit_main)
		replace_image_dialog:
			WebFiles.pick(images, false, emit_main)
		open_dialog:
			WebFiles.pick(".%s,%s" % [ProjectFile.EXTENSION, images_and_data], true, emit_main)
		save_project_dialog:
			dialog.file_selected.emit(WebFiles.output_path(suggested_project_path()))


## Of files picked together in a browser, the one to open: a data file, which brings its
## image along, else the first one
static func main_picked_file(paths: PackedStringArray) -> String:
	for path in paths:
		if SheetData.is_data_path(path):
			return path
	return paths[0]


func add_sprites_from_paths(paths: PackedStringArray) -> void:
	await add_image_files(paths)


## Loads the images at [param paths] and adds them as sprites, sorted by name, as one
## undoable step named [param action_name] that also links [param folders] (see
## [FolderWatcher]). Returns how many files were added.
static func add_image_files(
	paths: PackedStringArray, action_name := "Add sprites", folders: PackedStringArray = []
) -> int:
	# The OS dialog doesn't return files in the order they were selected
	# (Windows puts the last clicked file first), so sort them by name instead.
	var sorted_paths: Array[String] = []
	for path in paths:
		if path not in sorted_paths:
			sorted_paths.append(path)
	sorted_paths.sort_custom(
		func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0
	)

	var loaded := await ImageLoader.load_all_frames(
		PackedStringArray(sorted_paths),
		func(done: int, total: int) -> void: Notify.progress("Loading images", done, total)
	)
	Notify.hide_progress()
	var imgs: Array[Image] = []
	var sources: Array[Dictionary] = []
	# Each GIF, with the index of its first frame in imgs and its name
	var gifs: Array[Dictionary] = []
	var failed_files: PackedStringArray = []
	for i in loaded.size():
		var path := sorted_paths[i]
		var frames: Array = loaded[i].frames
		if frames.is_empty():
			failed_files.append(path.get_file())
		_linking(path)
		var is_gif := GifDecoder.is_gif_path(path)
		if is_gif and not frames.is_empty():
			gifs.append(
				{"gif": loaded[i], "first": imgs.size(), "name": path.get_file().get_basename()}
			)
		for frame: int in frames.size():
			imgs.append(frames[frame])
			sources.append(
				FrameSource.for_gif(path, frame) if is_gif else FrameSource.for_file(path)
			)
	Global.document.perform(action_name, _add_sprites.bind(imgs, sources, gifs, folders))

	if not failed_files.is_empty():
		Notify.error(TranslationServer.translate("Could not load: %s.") % ", ".join(failed_files))
	return loaded.size() - failed_files.size()


## Adds [param imgs] as sprites, and an animation for each of [param gifs] that plays
## its frames, and links [param folders], see [method add_image_files]
static func _add_sprites(
	imgs: Array[Image],
	sources: Array[Dictionary],
	gifs: Array[Dictionary],
	folders: PackedStringArray
) -> void:
	var sheet := Global.spritesheet
	for folder in folders:
		sheet.link_folder(folder)
	var coords := sheet.add_frames(imgs, Settings.get_value(&"add_mode"), sources)
	# Images that can't be added are skipped, which would shift the GIFs' frames
	if coords.size() != imgs.size():
		return
	for gif in gifs:
		var first: int = gif.first
		var cells := coords.slice(first, first + gif.gif.frames.size())
		GifDecoder.add_animation(sheet, gif.gif, cells, gif.name)


## Asks for an image to replace the frame at [param coord]
func replace_frame_image(coord: Vector2i) -> void:
	_replace_coord = coord
	popup_file_dialog(replace_image_dialog)


## Adds every image in [param folder] (not its subfolders), sorted by name, and links the
## folder so images added to it later are added too, also when it has none yet
func add_sprites_from_folder(folder: String) -> void:
	var paths := get_images_in_folder(folder)
	if paths.is_empty():
		if not link_empty_folders([folder]):
			Notify.error(tr("There are no images in %s.") % folder.get_file())
		return
	await add_image_files(paths, "Add sprites", _to_link([folder]))


## Links [param folders], which have no images, as one undoable step, so images saved there
## are added (see [FolderWatcher]), and says so, or that they wait for Reload changed files.
## False when none is linked, as in a browser.
static func link_empty_folders(folders: PackedStringArray) -> bool:
	var linked := _to_link(folders)
	if linked.is_empty():
		return false
	var sheet := Global.spritesheet
	Global.document.perform(
		"Link folder",
		func() -> void:
			for folder in linked:
				sheet.link_folder(folder)
	)
	var names: PackedStringArray = []
	for folder in linked:
		names.append(folder.get_file() if folder.get_file() else folder)
	var notice := TranslationServer.translate("Watching %s for new images.")
	if not Settings.get_value(&"watch_sources"):
		notice = TranslationServer.translate("Linked %s, paused: Reload changed files is off.")
	Notify.toast(notice % ", ".join(names))
	return true


## [param folders] as linked folders, with the images they have now as the ones they
## had (see [method FolderWatcher.remember]). None in a browser, which can't follow them.
static func _to_link(folders: PackedStringArray) -> PackedStringArray:
	var linked: PackedStringArray = []
	if FolderWatcher.in_browser:
		return linked
	for folder in folders:
		folder = folder.simplify_path()
		FolderWatcher.remember(folder)
		linked.append(folder)
	return linked


static func get_images_in_folder(folder: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	for file in DirAccess.get_files_at(folder):
		if is_image_path(file):
			paths.append(folder.path_join(file))
	return paths


static func is_image_path(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return extension in SpritesheetExporter.IMAGE_EXTENSIONS or extension == GifDecoder.EXTENSION


## Files dropped on the window: a project is opened, one image goes through the
## Add Spritesheet window, several images or folders are added as sprites, linking the
## folders like Add Folder, also those without images.
func open_dropped_files(paths: PackedStringArray) -> void:
	var images: PackedStringArray = []
	var folders: PackedStringArray = []
	for path in paths:
		if ProjectFile.is_project_path(path):
			confirm_unsaved_changes("opening another file", open_project.bind(path))
			return
		if DirAccess.dir_exists_absolute(path):
			images.append_array(get_images_in_folder(path))
			folders.append(path)
		elif is_image_path(path) or (SheetData.is_data_path(path) and paths.size() == 1):
			images.append(path)

	if images.is_empty():
		if not link_empty_folders(folders):
			Notify.error("Drop images, folders of images, a spritesheet data file or a project.")
	elif images.size() == 1 and not DirAccess.dir_exists_absolute(paths[0]):
		await show_add_spritesheet_window(images[0])
	else:
		await add_image_files(images, "Add sprites", _to_link(folders))


func show_add_spritesheet_window(spritesheet_path: String) -> void:
	await Notify.run_busy(
		"Opening %s" % spritesheet_path.get_file(),
		_show_add_spritesheet_window.bind(spritesheet_path),
		is_big_file(spritesheet_path)
	)


## Adds the frames of an animated GIF in a new row, named after the file, with an
## animation that plays them at the GIF's speed
func add_gif(path: String) -> void:
	var gif := GifDecoder.load_file(path)
	if gif.has("error"):
		set_filepath_when_opening_spritesheet = false
		Notify.error(tr(gif.error))
		return
	var opening := set_filepath_when_opening_spritesheet
	if opening:
		set_filepath_when_opening_spritesheet = false
		Settings.add_recent_file(path)
		Thumbnails.make_for_image(path)
		Global.document.reset()
	var anim_name := path.get_file().get_basename()
	_linking(path)
	if opening:
		var opened := Spritesheet.new()
		opened.set_frame_scale(Vector2.ONE, Settings.get_value(&"resize_filter"))
		GifDecoder.add_to_sheet(opened, gif, anim_name, path)
		Global.document.load_state(opened.get_state())
		Global.document.history_start = "Opened %s" % path.get_file()
	else:
		Global.document.perform(
			"Add GIF", GifDecoder.add_to_sheet.bind(Global.spritesheet, gif, anim_name, path)
		)


func _show_add_spritesheet_window(spritesheet_path: String) -> void:
	if GifDecoder.is_gif_path(spritesheet_path):
		add_gif(spritesheet_path)
		return
	# A data file brings its image, and an image brings the data file next to it
	var data: SheetData = null
	var data_path := ""
	if SheetData.is_data_path(spritesheet_path):
		data_path = spritesheet_path
		data = SheetData.load_file(data_path)
		if data.error:
			set_filepath_when_opening_spritesheet = false
			Notify.error(tr(data.error))
			return
		spritesheet_path = data.get_image_path(data_path)
	else:
		data_path = SheetData.find_for_image(spritesheet_path)
		if data_path:
			data = SheetData.load_file(data_path)

	var img := Image.load_from_file(spritesheet_path)
	if not img:
		set_filepath_when_opening_spritesheet = false
		Notify.error(tr("Could not load %s.") % spritesheet_path.get_file())
		return

	if set_filepath_when_opening_spritesheet:
		set_filepath_when_opening_spritesheet = false
		Settings.add_recent_file(spritesheet_path)
		Thumbnails.make_for_image(spritesheet_path)
		Global.document.reset()
		Global.document.export_path = spritesheet_path
		loading_opened_file = true
	_linking(spritesheet_path)
	_linking(data_path)
	add_spritesheet_window.setup(img, spritesheet_path, data, data_path)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func _create_unsaved_changes_dialog() -> void:
	unsaved_changes_dialog.title = "Unsaved changes"
	unsaved_changes_dialog.ok_button_text = "Save"
	DialogButtons.apply(unsaved_changes_dialog)
	unsaved_changes_dialog.add_button("Don't Save", false, "discard")
	add_child(unsaved_changes_dialog)
	unsaved_changes_dialog.confirmed.connect(
		func() -> void:
			after_save = after_unsaved_changes
			save()
	)
	unsaved_changes_dialog.custom_action.connect(
		func(_action: StringName) -> void:
			unsaved_changes_dialog.hide()
			after_unsaved_changes.call()
	)


## Runs [param then] right away, or after asking to save when there are unsaved changes
func confirm_unsaved_changes(before: String, then: Callable) -> void:
	if not Global.document.is_dirty or Global.spritesheet.is_empty():
		then.call()
		return
	after_unsaved_changes = then
	var file_name := Global.document.path.get_file() if Global.document.path else "the spritesheet"
	unsaved_changes_dialog.dialog_text = tr("Save changes to %s before %s?") % [file_name, before]
	unsaved_changes_dialog.popup_centered()


## Saves the project to its file, or asks where to save. Returns true if saved right away.
func save() -> bool:
	if not ProjectFile.is_project_path(Global.document.path):
		save_as()
		return false
	return await save_project(Global.document.path)


func save_as() -> void:
	_suggest(save_project_dialog, suggested_project_path())
	popup_file_dialog(save_project_dialog)


## Where to suggest saving the project: next to the file the document is named after, see
## [method Document.get_name_path], with its name
static func suggested_project_path() -> String:
	var base := Global.document.get_name_path()
	return base.get_base_dir().path_join(suggested_name(base) + "." + ProjectFile.EXTENSION)


## The name to suggest for a file named after [param base]: its name without the
## extension, or "spritesheet"
static func suggested_name(base: String) -> String:
	var base_name := base.get_file().get_basename()
	return base_name if base_name else "spritesheet"


## Points [param dialog] at [param path]. The file name is always set, since cancelling a
## native dialog clears it; without a folder, the dialog stays in the last one it was in.
static func _suggest(dialog: FileDialog, path: String) -> void:
	# In a browser, the dialog never opens: only the name is used
	if path.get_base_dir() and not WebFiles.is_web():
		dialog.current_dir = path.get_base_dir()
	if dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		dialog.current_file = path.get_file()


func save_project(path: String) -> bool:
	return await Notify.run_busy("Saving", _save_project.bind(path), is_big_sheet())


func _save_project(path: String) -> bool:
	path = ProjectFile.with_extension(path)
	var extra := {
		"export_path": Global.document.export_path,
		"source_hashes": _hashes_to_json(Global.document.source_hashes, path.get_base_dir()),
		"folder_files": _folder_files_to_json(path.get_base_dir()),
		"view": view_to_json(get_view.call()),
	}
	var error := ProjectFile.save(Global.spritesheet, path, extra)
	if error != OK:
		Notify.error(tr("Could not save %s (%s).") % [path.get_file(), error_string(error)])
		after_save = Callable()
		return false

	Global.document.path = path
	Global.document.mark_saved()
	Settings.set_value(&"last_session", path)
	Settings.add_recent_file(path)
	Thumbnails.make_for_sheet(path, Global.spritesheet)
	WebFiles.download(path)
	if after_save.is_valid():
		var action := after_save
		after_save = Callable()
		action.call()
	else:
		Notify.toast(tr("Saved %s") % path.get_file())
	return true


func open_project(path: String) -> bool:
	return await Notify.run_busy(
		"Opening %s" % path.get_file(), _open_project.bind(path), is_big_file(path)
	)


func _open_project(path: String) -> bool:
	var result := ProjectFile.load(path)
	if result.has("error"):
		Notify.error(result.error)
		return false
	Global.document.load_state(
		result.state,
		path,
		result.extra.get("export_path", ""),
		view_from_json(result.extra.get("view"))
	)
	Global.document.source_hashes = _hashes_from_json(
		result.extra.get("source_hashes"), path.get_base_dir()
	)
	Global.document.folder_files = _folder_files_from_json(
		result.extra.get("folder_files"), path.get_base_dir()
	)
	Settings.set_value(&"last_session", path)
	Settings.add_recent_file(path)
	Thumbnails.make_for_sheet(path, Global.spritesheet, false)
	return true


## Reopens the last project when the setting is on
func restore_session() -> void:
	var last: String = Settings.get_value(&"last_session")
	if Settings.get_value(&"restore_session") and last and FileAccess.file_exists(last):
		open_project(last)


## Opens a project, or an image through the Add Spritesheet window
func open_path(path: String) -> void:
	if ProjectFile.is_project_path(path):
		open_project(path)
	else:
		set_filepath_when_opening_spritesheet = true
		show_add_spritesheet_window(path)


## Frames are about to be linked to [param path], so it's watched again even if it was
## exported over before
static func _linking(path: String) -> void:
	var index := Global.document.unwatched_paths.find(path)
	if index >= 0:
		Global.document.unwatched_paths.remove_at(index)


static func _hashes_to_json(hashes: Dictionary[String, String], folder: String) -> Array:
	var result := []
	for path in hashes:
		(
			result
			. append(
				{
					"path": path,
					"relative": FrameSource.relative_path(path, folder),
					"md5": hashes[path],
				}
			)
		)
	return result


static func _hashes_from_json(value: Variant, folder: String) -> Dictionary[String, String]:
	var hashes: Dictionary[String, String] = {}
	if not value is Array:
		return hashes
	for entry: Variant in value:
		if entry is Dictionary and entry.get("path") is String and entry.get("md5") is String:
			hashes[FrameSource.resolve_path(entry.path, entry.get("relative"), folder)] = entry.md5
	return hashes


## The images each linked folder has, see [member Document.folder_files], for a project
## saved in [param folder]
static func _folder_files_to_json(folder: String) -> Array:
	var result := []
	var files := Global.document.folder_files
	for linked in Global.spritesheet.linked_folders:
		if files.has(linked):
			var relative := FrameSource.relative_folder_path(linked, folder)
			result.append({"path": linked, "relative": relative, "files": files[linked]})
	return result


static func _folder_files_from_json(
	value: Variant, folder: String
) -> Dictionary[String, PackedStringArray]:
	var files: Dictionary[String, PackedStringArray] = {}
	if not value is Array:
		return files
	for entry: Variant in value:
		if entry is Dictionary and entry.get("path") is String and entry.get("files") is Array:
			var linked := FrameSource.resolve_path(entry.path, entry.get("relative"), folder)
			files[linked] = PackedStringArray(entry.files)
	return files


## A view from [method SpritesheetPreview.get_view] as JSON
static func view_to_json(view: Dictionary) -> Dictionary:
	if not view.get("centre") is Vector2 or not view.get("zoom") is float:
		return {}
	return {"centre": [view.centre.x, view.centre.y], "zoom": view.zoom}


## A view saved with [method view_to_json], or empty when there's none
static func view_from_json(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var centre: Variant = value.get("centre")
	var zoom: Variant = value.get("zoom")
	if not centre is Array or centre.size() < 2 or not (zoom is float or zoom is int):
		return {}
	if zoom <= 0:
		return {}
	return {"centre": Vector2(float(centre[0]), float(centre[1])), "zoom": float(zoom)}


func new_spritesheet() -> void:
	confirm_unsaved_changes("creating a new one", Global.document.reset)


## Opens a recent file, asking to save changes first
func open_recent(path: String) -> void:
	if not FileAccess.file_exists(path):
		Notify.error("%s no longer exists." % path)
		return
	confirm_unsaved_changes("opening another file", open_path.bind(path))


func open_spritesheet() -> void:
	# The spritesheet is only reset once a file is picked, so canceling keeps the current one
	confirm_unsaved_changes("opening another file", popup_file_dialog.bind(open_dialog))


static func is_big_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() > SLOW_FILE_BYTES


## Whether work on the sheet takes long enough to show a "please wait" overlay
static func is_big_sheet() -> bool:
	var sheet := Global.spritesheet
	var pixels := 0
	for coord in sheet.frames:
		var size := sheet.get_frame_rect_in_cell(coord).size
		pixels += size.x * size.y
	return pixels > SLOW_PIXELS


static func _create_file_dialog(
	dialog_title: String, mode: FileDialog.FileMode, filters: PackedStringArray
) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = dialog_title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.use_native_dialog = true
	return dialog
