class_name FileController
extends Node
## Opening, saving and adding files, with the dialogs they need. [member exports] writes
## exports.

## Filters of file dialogs, which translate what comes after the ;
const PROJECT_FILTER := "*.sbelli ; spritesheetbelli projects"  # L10n.mark
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.jpe, *.webp, *.gif ; Images"  # L10n.mark
# L10n.mark
const DATA_FILTER := "*.json, *.atlas ; Spritesheet data (TexturePacker, Aseprite, Phaser, libGDX)"
## What Godot calls the filters its file dialogs add, of every file the other filters take
## and of all files, which they translate like the others, also in native dialogs
const DIALOG_FILTER_NAMES := ["All Recognized", "All Files"]  # L10n.mark

@export var add_spritesheet_window: AddSpritesheetWindow

## True while the Add Spritesheet window shows a file picked with Open
var loading_opened_file := false
## The tab made to open a file in, closed again when opening is canceled, or null when
## the blank tab it was opened from is used, see [method open_in_tab]
var _opening_tab: Document = null
var set_filepath_when_opening_spritesheet := false
## Runs after the next successful save, e.g. closing the app after "Save"
var after_save: Callable
## Asks to save the documents with unsaved changes before they're closed, see
## [method confirm_unsaved_documents]
var unsaved_changes_dialog := ConfirmationDialog.new()
var after_unsaved_changes: Callable
## The documents [member unsaved_changes_dialog] asks about
var _asking: Array[Document] = []
var open_file_dialogs: Array[FileDialog] = []
var open_dialog := _create_file_dialog(
	L10n.mark("Open"), FileDialog.FILE_MODE_OPEN_FILE, [PROJECT_FILTER, IMAGE_FILTER, DATA_FILTER]
)
var save_project_dialog := _create_file_dialog(
	L10n.mark("Save Project"), FileDialog.FILE_MODE_SAVE_FILE, [PROJECT_FILTER]
)
var open_folder_dialog := _create_file_dialog(
	L10n.mark("Add Folder"), FileDialog.FILE_MODE_OPEN_DIR, []
)
var replace_image_dialog := _create_file_dialog(
	L10n.mark("Replace Image"), FileDialog.FILE_MODE_OPEN_FILE, [IMAGE_FILTER]
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
				L10n.mark("Replace image"),
				sheet.replace_frame.bind(_replace_coord, img, FrameSource.for_file(path))
			)
	)
	get_window().files_dropped.connect(open_dropped_files)
	# A dialog that closed without saying so (some native dialogs) would otherwise block
	# its button for good. The window only regains focus once the dialog is gone.
	# Not open_file_dialogs.clear: empty arrays are equal, so a second window's (in tests)
	# would count as connected already
	get_window().focus_entered.connect(func() -> void: open_file_dialogs.clear())

	# Loading the opened file is not an unsaved change
	add_spritesheet_window.frames_added.connect(
		func() -> void:
			if loading_opened_file:
				loading_opened_file = false
				Global.document.load_state(
					Global.spritesheet.get_state(), "", Global.document.export_path
				)
	)
	# Nothing was opened after all, so its tab goes, or shows the start screen again
	add_spritesheet_window.canceled.connect(
		func() -> void:
			if loading_opened_file:
				loading_opened_file = false
				if _opening_tab:
					Global.close_document(_opening_tab)
				else:
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
## [FolderWatcher]). Returns how many files were added. They go to the active document,
## even when another tab is chosen while they load.
static func add_image_files(
	paths: PackedStringArray,
	action_name := L10n.mark("Add sprites"),
	folders: PackedStringArray = []
) -> int:
	var document := Global.document
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
		func(done: int, total: int) -> void:
			Notify.progress(TranslationServer.translate("Loading images"), done, total)
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
		_linking(path, document)
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
	document.perform(
		action_name, _add_sprites.bind(document.spritesheet, imgs, sources, gifs, folders)
	)

	if not failed_files.is_empty():
		Notify.error(TranslationServer.translate("Could not load: %s.") % ", ".join(failed_files))
	return loaded.size() - failed_files.size()


## Adds [param imgs] as sprites to [param sheet], and an animation for each of
## [param gifs] that plays its frames, and links [param folders], see
## [method add_image_files]
static func _add_sprites(
	sheet: Spritesheet,
	imgs: Array[Image],
	sources: Array[Dictionary],
	gifs: Array[Dictionary],
	folders: PackedStringArray
) -> void:
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
	await add_image_files(paths, L10n.mark("Add sprites"), _to_link([folder]))


## Links [param folders], which have no images, as one undoable step, so images saved there
## are added (see [FolderWatcher]), and says so, or that they wait for Reload changed files.
## False when none is linked, as in a browser.
static func link_empty_folders(folders: PackedStringArray) -> bool:
	var linked := _to_link(folders)
	if linked.is_empty():
		return false
	var sheet := Global.spritesheet
	Global.document.perform(
		L10n.mark("Link folder"),
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
	var projects: PackedStringArray = []
	for path in paths:
		if ProjectFile.is_project_path(path):
			projects.append(path)
		elif DirAccess.dir_exists_absolute(path):
			images.append_array(get_images_in_folder(path))
			folders.append(path)
		elif is_image_path(path) or (SheetData.is_data_path(path) and paths.size() == 1):
			images.append(path)
	# Each in a tab of its own, and the images that came along are left alone
	if not projects.is_empty():
		for project in projects:
			await open_project(project)
		return

	if images.is_empty():
		if not link_empty_folders(folders):
			Notify.error(
				tr("Drop images, folders of images, a spritesheet data file or a project.")
			)
	elif images.size() == 1 and not DirAccess.dir_exists_absolute(paths[0]):
		await show_add_spritesheet_window(images[0])
	else:
		await add_image_files(images, L10n.mark("Add sprites"), _to_link(folders))


func show_add_spritesheet_window(spritesheet_path: String) -> void:
	await Notify.run_busy(
		tr("Opening %s") % spritesheet_path.get_file(),
		_show_add_spritesheet_window.bind(spritesheet_path)
	)


## Adds the frames of an animated GIF in a new row, named after the file, with an
## animation that plays them at the GIF's speed
func add_gif(path: String) -> void:
	var document := Global.document
	var gif: Dictionary = await Parallel.run(GifDecoder.load_file.bind(path))
	if gif.has("error"):
		set_filepath_when_opening_spritesheet = false
		Notify.error(tr(gif.error))
		return
	var opening := set_filepath_when_opening_spritesheet
	var anim_name := path.get_file().get_basename()
	if opening:
		set_filepath_when_opening_spritesheet = false
		Settings.add_recent_file(path)
		Thumbnails.make_for_image(path)
		var opened := Spritesheet.new()
		opened.set_frame_scale(Vector2.ONE, Settings.get_value(&"resize_filter"))
		GifDecoder.add_to_sheet(opened, gif, anim_name, path)
		var tab := open_in_tab()
		tab.load_state(opened.get_state())
		tab.set_history_start(L10n.mark("Opened %s"), path)
	else:
		_linking(path, document)
		document.perform(
			L10n.mark("Add GIF"),
			GifDecoder.add_to_sheet.bind(document.spritesheet, gif, anim_name, path)
		)


func _show_add_spritesheet_window(spritesheet_path: String) -> void:
	if GifDecoder.is_gif_path(spritesheet_path):
		await add_gif(spritesheet_path)
		return
	var document := Global.document
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

	# Loaded and looked into on worker threads, as that takes a while on big sheets
	var img: Image = await Parallel.run(
		func() -> Image: return Image.load_from_file(spritesheet_path)
	)
	if not img:
		set_filepath_when_opening_spritesheet = false
		Notify.error(tr("Could not load %s.") % spritesheet_path.get_file())
		return
	var prepared := await AddSpritesheetWindow.prepare(
		img,
		spritesheet_path,
		data,
		data_path,
		Settings.get_value(&"background_tolerance"),
		Settings.get_value(&"background_contiguous")
	)

	if set_filepath_when_opening_spritesheet:
		set_filepath_when_opening_spritesheet = false
		Settings.add_recent_file(spritesheet_path)
		Thumbnails.make_for_image(spritesheet_path)
		document = open_in_tab()
		document.export_path = spritesheet_path
		loading_opened_file = true
	else:
		# The sheet is added to the tab it was added from, also when another was chosen
		# while it loaded
		Global.switch_to(document)
	_linking(spritesheet_path, document)
	_linking(data_path, document)
	await add_spritesheet_window.setup(img, spritesheet_path, data, data_path, prepared)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func _create_unsaved_changes_dialog() -> void:
	unsaved_changes_dialog.title = "Unsaved changes"
	unsaved_changes_dialog.ok_button_text = "Save"
	unsaved_changes_dialog.get_ok_button().icon = MainActions.SAVE_ICON
	DialogButtons.apply(unsaved_changes_dialog, true)
	DialogButtons.add_alternative(unsaved_changes_dialog, L10n.mark("Don't Save"), &"discard")
	add_child(unsaved_changes_dialog)
	unsaved_changes_dialog.confirmed.connect(
		func() -> void: save_all(_asking.duplicate(), after_unsaved_changes)
	)
	unsaved_changes_dialog.custom_action.connect(
		func(_action: StringName) -> void:
			unsaved_changes_dialog.hide()
			after_unsaved_changes.call()
	)


## Runs [param then] right away, or after asking to save when the active document has
## unsaved changes, with [param question], untranslated, like "Save changes to %s before
## closing?", with the file's name in its %s
func confirm_unsaved_changes(question: String, then: Callable) -> void:
	confirm_unsaved_documents([Global.document] as Array[Document], question, "", then)


## Runs [param then] right away, or after asking to save those of [param documents] with
## unsaved changes: one with [param question], like in [method confirm_unsaved_changes],
## and several listed under [param question_many], untranslated, like "Save changes to
## these projects before quitting?". Its tab becomes active, or each one in turn while
## they're saved.
func confirm_unsaved_documents(
	documents: Array[Document], question: String, question_many: String, then: Callable
) -> void:
	var unsaved: Array[Document] = []
	for document in documents:
		if document.is_dirty and not document.spritesheet.is_empty():
			unsaved.append(document)
	if unsaved.is_empty():
		then.call()
		return
	after_unsaved_changes = then
	_asking = unsaved
	if unsaved.size() == 1:
		Global.switch_to(unsaved[0])
		var file_name := unsaved[0].path.get_file()
		if not file_name:
			file_name = tr("the spritesheet")
		unsaved_changes_dialog.dialog_text = tr(question) % file_name
		unsaved_changes_dialog.ok_button_text = L10n.mark("Save")
	else:
		var lines: PackedStringArray = [tr(question_many), ""]
		for title in DocumentTabs.get_titles(unsaved):
			lines.append("• " + title)
		unsaved_changes_dialog.dialog_text = "\n".join(lines)
		unsaved_changes_dialog.ok_button_text = L10n.mark("Save All")
	unsaved_changes_dialog.popup_centered()


## Saves each of [param documents] in turn, making its tab active, then runs
## [param then]. Stops when one isn't saved, e.g. when asking where to save it is canceled.
func save_all(documents: Array[Document], then := Callable()) -> void:
	if documents.is_empty():
		if then.is_valid():
			then.call()
		return
	Global.switch_to(documents[0])
	after_save = save_all.bind(documents.slice(1), then)
	save()


## Closes the tabs of [param documents], after asking to save those with unsaved changes,
## then runs [param then] unless that was canceled
func close_tabs(documents: Array[Document], then := Callable()) -> void:
	confirm_unsaved_documents(
		documents,
		L10n.mark("Save changes to %s before closing?"),
		L10n.mark("Save changes to these projects before closing them?"),
		func() -> void:
			for document in documents:
				Global.close_document(document)
			remember_session()
			if then.is_valid():
				then.call()
	)


## Runs [param quit] after asking to save the documents with unsaved changes, one with
## [param question] (see [method confirm_unsaved_changes]), and remembers the projects
## open in tabs for the next run, see [method remember_session]
func confirm_quit(
	quit: Callable, question := L10n.mark("Save changes to %s before quitting?")
) -> void:
	confirm_unsaved_documents(
		Global.documents.duplicate(),
		question,
		L10n.mark("Save changes to these projects before quitting?"),
		func() -> void:
			remember_session()
			quit.call()
	)


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
	var document := Global.document
	var base := document.get_name_path()
	var base_name := suggested_name(base, document.is_named_after_folder())
	return base.get_base_dir().path_join(base_name + "." + ProjectFile.EXTENSION)


## The name to suggest for a file named after [param base]: its name without the
## extension (all of it for a [param folder]), or "spritesheet"
static func suggested_name(base: String, folder := false) -> String:
	var base_name := base.get_file() if folder else base.get_file().get_basename()
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
	return await Notify.run_busy(tr("Saving"), _save_project.bind(path))


func _save_project(path: String) -> bool:
	var document := Global.document
	path = ProjectFile.with_extension(path)
	# Written on a worker thread, so the bar keeps going. Frame images are never changed in
	# place, so a copy of the state is enough.
	var copy := Spritesheet.new()
	copy.set_state(document.spritesheet.get_state())
	var extra := project_extra(path.get_base_dir())
	var error: Error = await Parallel.run(ProjectFile.save.bind(copy, path, extra))
	if error != OK:
		Notify.error(tr("Could not save %s (%s).") % [path.get_file(), error_string(error)])
		after_save = Callable()
		return false

	document.path = path
	document.mark_saved()
	remember_session()
	Settings.add_recent_file(path)
	Thumbnails.make_for_sheet(path, document.spritesheet)
	WebFiles.download(path)
	if after_save.is_valid():
		var action := after_save
		after_save = Callable()
		action.call()
	else:
		Notify.toast(tr("Saved %s") % path.get_file())
	return true


## Opens the project at [param path] in a tab of its own, or shows its tab when it's
## open already, see [method open_in_tab]
func open_project(path: String) -> bool:
	var open := Global.find_document(path)
	if open:
		Global.switch_to(open)
		return true
	return await Notify.run_busy(tr("Opening %s") % path.get_file(), _open_project.bind(path))


func _open_project(path: String) -> bool:
	var result: Dictionary = await Parallel.run(ProjectFile.load.bind(path))
	if result.has("error"):
		Notify.error(result.error)
		return false
	var document := open_in_tab()
	load_project(result, path, path.get_base_dir(), document)
	remember_session()
	Settings.add_recent_file(path)
	Thumbnails.make_for_sheet(path, document.spritesheet, false)
	return true


## Makes a tab active to open a file in and returns its document: the active one when
## nothing is open in it (see [method Document.is_blank]), else a new one after it
func open_in_tab() -> Document:
	_opening_tab = null
	if Global.document.is_blank():
		return Global.document
	_opening_tab = Document.new()
	_opening_tab.reset()
	Global.add_document(_opening_tab)
	return _opening_tab


## What a project of [param document] (the active one by default) saved in [param folder]
## holds besides the sheet: its export path, what it knows of the files its frames come
## from, and the preview's view, or the one it was left with when it's in the background
func project_extra(folder: String, document: Document = null) -> Dictionary:
	if document == null:
		document = Global.document
	var view: Dictionary = document.view_state.get("view", {})
	if document == Global.document:
		view = get_view.call()
	return {
		"export_path": document.export_path,
		"source_hashes": _hashes_to_json(document.source_hashes, folder),
		"folder_files": _folder_files_to_json(folder, document),
		"view": view_to_json(view),
	}


## Makes [param result] of [method ProjectFile.load] the content of [param document] (the
## active one by default), as the file at [param path]. [param folder] is where it was
## saved, which its relative paths start from.
func load_project(
	result: Dictionary, path: String, folder: String, document: Document = null
) -> void:
	if document == null:
		document = Global.document
	document.load_state(
		result.state,
		path,
		result.extra.get("export_path", ""),
		view_from_json(result.extra.get("view"))
	)
	document.source_hashes = _hashes_from_json(result.extra.get("source_hashes"), folder)
	document.folder_files = _folder_files_from_json(result.extra.get("folder_files"), folder)


## Reopens the projects of the last session in tabs when the setting is on, with the
## same one active, see [method remember_session]
func restore_session() -> void:
	if not Settings.get_value(&"restore_session"):
		return
	var paths: Array = Settings.get_value(&"last_session")
	var active_index: int = Settings.get_value(&"last_session_tab")
	var active: Document = null
	for i in paths.size():
		var path: Variant = paths[i]
		if not (path is String and FileAccess.file_exists(path)):
			continue
		if await open_project(path) and (i == active_index or active == null):
			active = Global.document
	if active:
		Global.switch_to(active)


## Remembers the projects open in tabs, those saved to a file, and which is active, to
## open them again in the next run, see [method restore_session]. An active tab without a
## file counts as the project before it.
func remember_session() -> void:
	var paths: Array[String] = []
	var active_index := 0
	for document in Global.documents:
		if document == Global.document:
			active_index = maxi(paths.size() - 1, 0)
		if ProjectFile.is_project_path(document.path):
			if document == Global.document:
				active_index = paths.size()
			paths.append(document.path)
	Settings.set_value(&"last_session", paths)
	Settings.set_value(&"last_session_tab", active_index)


## The files in [param args] (see [method OS.get_cmdline_args]) the app can open: those the
## file manager passes when a file is opened with the app
static func files_from_arguments(args: PackedStringArray) -> PackedStringArray:
	var paths: PackedStringArray = []
	for arg in args:
		if arg.begins_with("-") or not FileAccess.file_exists(arg):
			continue
		if ProjectFile.is_project_path(arg) or is_image_path(arg) or SheetData.is_data_path(arg):
			# Like the paths of dropped files
			paths.append(arg.replace("\\", "/") if OS.has_feature("windows") else arg)
	return paths


## Opens files the app was started with: one like Open, several like dropped files
func open_files(paths: PackedStringArray) -> void:
	if paths.size() == 1:
		await open_path(paths[0])
	else:
		await open_dropped_files(paths)


## Opens a project, or an image through the Add Spritesheet window, in a tab of its own.
## A file that's open already shows its tab instead.
func open_path(path: String) -> void:
	if ProjectFile.is_project_path(path):
		await open_project(path)
		return
	for document in Global.documents:
		if document.path.is_empty() and document.export_path == path:
			Global.switch_to(document)
			return
	set_filepath_when_opening_spritesheet = true
	await show_add_spritesheet_window(path)


## Frames of [param document] (the active one by default) are about to be linked to
## [param path], so it's watched again even if it was exported over before
static func _linking(path: String, document: Document = null) -> void:
	if document == null:
		document = Global.document
	var index := document.unwatched_paths.find(path)
	if index >= 0:
		document.unwatched_paths.remove_at(index)


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


## The images each linked folder of [param document] has, see
## [member Document.folder_files], for a project saved in [param folder]
static func _folder_files_to_json(folder: String, document: Document) -> Array:
	var result := []
	var files := document.folder_files
	for linked in document.spritesheet.linked_folders:
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


## A new tab, showing the start screen. The active tab is used when it shows it already.
func new_spritesheet() -> void:
	if not Global.document.is_blank():
		var document := Document.new()
		document.reset()
		Global.add_document(document)


## Opens a recent file in a tab of its own
func open_recent(path: String) -> void:
	if not FileAccess.file_exists(path):
		Notify.error(tr("%s no longer exists.") % path)
		return
	await open_path(path)


func open_spritesheet() -> void:
	popup_file_dialog(open_dialog)


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
