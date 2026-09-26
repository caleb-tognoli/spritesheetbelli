class_name FileController
extends Node
## Opening, saving, exporting and adding files, with the dialogs they need.

const PROJECT_FILTER := "*.sbelli ; spritesheetbelli projects"
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.jpe, *.webp, *.gif ; Images"
const DATA_FILTER := "*.json, *.atlas ; Spritesheet data (TexturePacker, Aseprite, Phaser, libGDX)"
## Work above these sizes shows a "please wait" overlay first
const SLOW_PIXELS := 4_000_000
const SLOW_FILE_BYTES := 4_000_000

@export var add_spritesheet_window: AddSpritesheetWindow

var warned_about_jpg_transparency := false
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
## Returns the selected frames, for exporting only those
var get_selected_coords := func() -> Array[Vector2i]: return []

@onready var open_sprites_dialog: FileDialog = $OpenSpritesDialog
@onready var open_spritesheet_dialog: FileDialog = $OpenSpritesheetDialog
@onready var save_sprites_dialog: FileDialog = $SaveSpritesDialog
@onready var export_file_dialog: FileDialog = $ExportFileDialog


func _ready() -> void:
	open_spritesheet_dialog.filters = [IMAGE_FILTER, DATA_FILTER]
	open_sprites_dialog.files_selected.connect(add_sprites_from_paths)
	open_spritesheet_dialog.file_selected.connect(show_add_spritesheet_window)
	open_dialog.file_selected.connect(open_path)
	save_sprites_dialog.dir_selected.connect(export_to)
	export_file_dialog.file_selected.connect(export_to)
	save_project_dialog.file_selected.connect(save_project)
	save_project_dialog.canceled.connect(func() -> void: after_save = Callable())
	open_folder_dialog.dir_selected.connect(add_sprites_from_folder)
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
	add_spritesheet_window.canceled.connect(func() -> void: loading_opened_file = false)

	_create_unsaved_changes_dialog()
	for dialog: FileDialog in [
		open_sprites_dialog,
		open_spritesheet_dialog,
		save_sprites_dialog,
		export_file_dialog,
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
	var base_name := Global.document.get_display_name().get_basename()
	if base_name.is_empty():
		base_name = "spritesheet"
	match dialog:
		open_sprites_dialog:
			WebFiles.pick(images, true, add_sprites_from_paths)
		open_folder_dialog:
			WebFiles.pick(images, true, add_sprites_from_paths, true)
		open_spritesheet_dialog, replace_image_dialog:
			WebFiles.pick(
				images,
				false,
				func(paths: PackedStringArray) -> void: dialog.file_selected.emit(paths[0])
			)
		open_dialog:
			WebFiles.pick(
				".sbelli," + images,
				false,
				func(paths: PackedStringArray) -> void: dialog.file_selected.emit(paths[0])
			)
		save_project_dialog:
			dialog.file_selected.emit(WebFiles.output_path(base_name + ".sbelli"))
		export_file_dialog:
			dialog.file_selected.emit(WebFiles.output_path(dialog.current_file))
		save_sprites_dialog:
			var folder := WebFiles.output_path(base_name + "_sprites")
			DirAccess.make_dir_recursive_absolute(folder)
			for file in DirAccess.get_files_at(folder):
				DirAccess.remove_absolute(folder.path_join(file))
			dialog.dir_selected.emit(folder)


func add_sprites_from_paths(paths: PackedStringArray) -> void:
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
	var failed_files: PackedStringArray = []
	for i in loaded.size():
		var path := sorted_paths[i]
		if loaded[i].is_empty():
			failed_files.append(path.get_file())
		_linking(path)
		var is_gif := GifDecoder.is_gif_path(path)
		for frame: int in loaded[i].size():
			imgs.append(loaded[i][frame])
			sources.append(
				FrameSource.for_gif(path, frame) if is_gif else FrameSource.for_file(path)
			)
	Global.document.perform(
		"Add sprites",
		Global.spritesheet.add_frames.bind(imgs, Settings.get_value(&"add_mode"), sources)
	)

	if not failed_files.is_empty():
		Notify.error(tr("Could not load: %s.") % ", ".join(failed_files))


## Asks for an image to replace the frame at [param coord]
func replace_frame_image(coord: Vector2i) -> void:
	_replace_coord = coord
	popup_file_dialog(replace_image_dialog)


## Adds every image in [param folder] (not its subfolders), sorted by name
func add_sprites_from_folder(folder: String) -> void:
	var paths := get_images_in_folder(folder)
	if paths.is_empty():
		Notify.error(tr("There are no images in %s.") % folder.get_file())
		return
	await add_sprites_from_paths(paths)


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
## Add Spritesheet window, several images or folders are added as sprites.
func open_dropped_files(paths: PackedStringArray) -> void:
	var images: PackedStringArray = []
	for path in paths:
		if ProjectFile.is_project_path(path):
			confirm_unsaved_changes("opening another file", open_project.bind(path))
			return
		if DirAccess.dir_exists_absolute(path):
			images.append_array(get_images_in_folder(path))
		elif is_image_path(path) or (SheetData.is_data_path(path) and paths.size() == 1):
			images.append(path)

	if images.is_empty():
		Notify.error("Drop images, folders of images, a spritesheet data file or a project.")
	elif images.size() == 1 and not DirAccess.dir_exists_absolute(paths[0]):
		await show_add_spritesheet_window(images[0])
	else:
		await add_sprites_from_paths(images)


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
		Global.document.reset()
	var row_name := path.get_file().get_basename()
	_linking(path)
	if opening:
		var opened := Spritesheet.new()
		opened.set_frame_scale(Vector2.ONE, Settings.get_value(&"resize_filter"))
		GifDecoder.add_to_sheet(opened, gif, row_name, path)
		Global.document.load_state(opened.get_state())
		Global.document.history_start = "Opened %s" % path.get_file()
	else:
		Global.document.perform(
			"Add GIF", GifDecoder.add_to_sheet.bind(Global.spritesheet, gif, row_name, path)
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
		Global.document.reset()
		Global.document.export_path = spritesheet_path
		loading_opened_file = true
	_linking(spritesheet_path)
	_linking(data_path)
	add_spritesheet_window.setup(img, spritesheet_path, data, data_path)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func save_sprites(folder: String) -> bool:
	return await Notify.run_busy("Exporting sprites", _save_sprites.bind(folder), _is_big_sheet())


func _save_sprites(folder: String) -> bool:
	var errors: PackedStringArray = []
	var options := ExportOptions.from_sheet(Global.spritesheet)
	var coords: Array[Vector2i] = []
	if options.only_selected:
		coords = get_selected_coords.call()
		if coords.is_empty():
			(
				Notify
				. error(
					'No frames are selected. Select frames or turn off "Only selected frames" when exporting.'
				)
			)
			return false
	var written := SpritesheetExporter.export_sprites(
		Global.spritesheet, folder, errors, Settings.get_value(&"index_start"), options, coords
	)
	unlink_overwritten(written)
	if not errors.is_empty():
		Notify.error(tr("Could not save: %s.") % ", ".join(errors))
		return false
	WebFiles.download_folder(folder, folder.get_file() + ".zip")
	Notify.toast(tr("Saved %d images to %s.") % [written.size(), folder.get_file()])
	return true


func _create_unsaved_changes_dialog() -> void:
	unsaved_changes_dialog.title = "Unsaved changes"
	unsaved_changes_dialog.ok_button_text = "Save"
	unsaved_changes_dialog.add_button("Don't Save", true, "discard")
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
	var suggested := Global.document.path
	if suggested.is_empty() and Global.document.export_path:
		suggested = Global.document.export_path
	if suggested:
		save_project_dialog.current_path = ProjectFile.with_extension(suggested)
	popup_file_dialog(save_project_dialog)


func save_project(path: String) -> bool:
	return await Notify.run_busy("Saving", _save_project.bind(path), _is_big_sheet())


func _save_project(path: String) -> bool:
	path = ProjectFile.with_extension(path)
	var extra := {
		"export_path": Global.document.export_path,
		"last_export": Global.document.last_export,
		"source_hashes": _hashes_to_json(Global.document.source_hashes, path.get_base_dir()),
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
	Global.document.load_state(result.state, path, result.extra.get("export_path", ""))
	Global.document.last_export = str(result.extra.get("last_export", ""))
	Global.document.source_hashes = _hashes_from_json(
		result.extra.get("source_hashes"), path.get_base_dir()
	)
	Settings.set_value(&"last_session", path)
	Settings.add_recent_file(path)
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


## Asks where to export, following the sheet's export settings. The file dialog asks
## before overwriting a file.
func choose_export_path() -> void:
	var options := ExportOptions.from_sheet(Global.spritesheet)
	if options.target == ExportOptions.Target.SPRITES:
		popup_file_dialog(save_sprites_dialog)
		return
	var extension := options.get_file_extension()
	var names := {
		"png": "PNG Images", "jpg": "JPEG Images", "webp": "WebP Images", "gif": "GIF Images"
	}
	var patterns := {
		"png": "*.png", "jpg": "*.jpg, *.jpeg, *.jpe", "webp": "*.webp", "gif": "*.gif"
	}
	export_file_dialog.filters = ["%s ; %s" % [patterns[extension], names[extension]]]
	export_file_dialog.title = "Export"
	var suggested := suggested_export_path(options)
	export_file_dialog.current_dir = suggested.get_base_dir()
	export_file_dialog.current_file = suggested.get_file()
	popup_file_dialog(export_file_dialog)


## Where to suggest exporting: next to the last export or the project, named after it
static func suggested_export_path(options: ExportOptions) -> String:
	var document := Global.document
	var base := document.export_path if document.export_path else document.path
	var folder := base.get_base_dir()
	var base_name := base.get_file().get_basename()
	if base_name.is_empty():
		base_name = "spritesheet"
	if options.target == ExportOptions.Target.ATLAS and not base_name.ends_with("_atlas"):
		base_name += "_atlas"
	if options.target == ExportOptions.Target.GIF and options.gif_animation:
		base_name += "_" + options.gif_animation.validate_filename()
	return folder.path_join(base_name + "." + options.get_file_extension())


## Exports to [param path] what the sheet's export settings say
func export_to(path: String) -> bool:
	var exported := false
	match ExportOptions.from_sheet(Global.spritesheet).target:
		ExportOptions.Target.ATLAS:
			exported = await export_atlas(path)
		ExportOptions.Target.GIF:
			exported = await export_gif(path)
		ExportOptions.Target.SPRITES:
			exported = await save_sprites(path)
		_:
			exported = await export_image_to(path)
	if exported:
		Global.document.last_export = path
	return exported


## Exports the same way to the same place as last time, without asking
func export_again() -> bool:
	var path := Global.document.last_export
	if path.is_empty():
		return false
	var options := ExportOptions.from_sheet(Global.spritesheet)
	var extension := options.get_file_extension()
	# The export type changed since: same name, the new type's extension
	if extension and path.get_extension().to_lower() != extension:
		path = path.get_basename() + "." + extension
	return await export_to(path)


## Writes the animation chosen in the export settings as an animated GIF
func export_gif(path: String) -> bool:
	var sheet := Global.spritesheet
	var result := await GifEncoder.write(
		sheet,
		ExportOptions.from_sheet(sheet),
		path,
		func(done: int, total: int) -> void: Notify.progress("Making the GIF", done, total)
	)
	Notify.hide_progress()
	if result.error == ERR_DOES_NOT_EXIST:
		Notify.error("The animation has no frames.")
		return false
	if result.error != OK:
		Notify.error(tr("Could not export to %s (%s).") % [result.path, error_string(result.error)])
		return false
	unlink_overwritten([result.path])
	WebFiles.download(result.path)
	Notify.toast(tr("Exported %s (%d frames).") % [result.path.get_file(), result.frames])
	return true


func export_image_to(path: String) -> bool:
	return await Notify.run_busy("Exporting", _export_image_to.bind(path), _is_big_sheet())


func _export_image_to(path: String) -> bool:
	if Global.spritesheet.is_empty():
		Notify.error("The spritesheet is empty.")
		return false

	var options := ExportOptions.from_sheet(Global.spritesheet)
	path = SpritesheetExporter.with_image_extension(path)
	if Global.spritesheet.layout == Spritesheet.Layout.PACKED:
		return _export_pages(path, options)
	var problem := ImageUtils.size_problem(
		SpritesheetExporter.get_image_size(Global.spritesheet, options), path.get_extension()
	)
	if problem:
		Notify.error(problem + "\n" + tr("Make the sprites smaller or use fewer cells."))
		return false
	var spritesheet_image := Global.spritesheet.get_image(options)
	var error := SpritesheetExporter.save_image(spritesheet_image, path, options)

	if error != OK:
		Notify.error(tr("Could not export to %s (%s).") % [path, error_string(error)])
		return false
	unlink_overwritten([path])

	var message := tr("Exported %s in %s.") % [path.get_file(), path.get_base_dir().get_file()]
	var metadata_error := Metadata.write_for_image(
		Global.spritesheet, options, path, Settings.get_value(&"index_start")
	)
	if metadata_error != OK:
		Notify.error(tr("Could not write the metadata (%s).") % error_string(metadata_error))
		return false
	WebFiles.download(path)
	if options.metadata != ExportOptions.MetadataFormat.NONE:
		unlink_overwritten([Metadata.get_path_for_image(path, options)])
		message += tr("\nAlso wrote %s.") % Metadata.get_path_for_image(path, options).get_file()
		WebFiles.download(Metadata.get_path_for_image(path, options))
	if (
		not SpritesheetExporter.supports_transparency(path)
		and ImageUtils.has_transparency(spritesheet_image)
		and not warned_about_jpg_transparency
	):
		warned_about_jpg_transparency = true
		message += (
			tr("\nJPG doesn't support transparency, so transparent areas were filled with %s.")
			% (
				tr("white")
				if options.opaque_background == Color.WHITE
				else tr("the background colour")
			)
		)
	Global.document.export_path = path
	Notify.toast(message, 7.0 if "\n" in message else 3.0)
	return true


## Writes each page of the packed sheet as an image, numbered when there are more
func _export_pages(path: String, options: ExportOptions) -> bool:
	var pages := SpritesheetExporter.build_pages(Global.spritesheet, options)
	var paths := SpritesheetExporter.get_page_paths(path, pages.size())
	for i in pages.size():
		var problem := ImageUtils.size_problem(pages[i].get_size(), path.get_extension())
		if problem:
			Notify.error(problem)
			return false
		var error := SpritesheetExporter.save_image(pages[i], paths[i], options)
		if error != OK:
			Notify.error(tr("Could not export to %s (%s).") % [paths[i], error_string(error)])
			return false
		WebFiles.download(paths[i])
	unlink_overwritten(paths)
	Global.document.export_path = path
	if paths.size() == 1:
		Notify.toast(tr("Exported %s in %s.") % [path.get_file(), path.get_base_dir().get_file()])
	else:
		Notify.toast(tr("Exported %d pages, from %s.") % [paths.size(), paths[0].get_file()])
	return true


## Packs trimmed frames tightly and writes the atlas PNG with a JSON file next to it
func export_atlas(path: String) -> bool:
	return await Notify.run_busy("Packing the atlas", _export_atlas.bind(path), _is_big_sheet())


func _export_atlas(path: String) -> bool:
	var sheet := Global.spritesheet
	var result := AtlasPacker.write(
		sheet, ExportOptions.from_sheet(sheet), path, Settings.get_value(&"index_start")
	)
	if result.error == ERR_OUT_OF_MEMORY:
		Notify.error(tr("The frames don't fit in a %d px atlas.") % AtlasPacker.MAX_SIZE)
		return false
	if result.error == ERR_UNAVAILABLE:
		Notify.error(tr(result.message))
		return false
	if result.error != OK:
		Notify.error(tr("Could not export the atlas (%s).") % error_string(result.error))
		return false
	unlink_overwritten(result.paths)
	for written: String in result.paths:
		WebFiles.download(written)
	var size: Vector2i = result.size
	if result.pages > 1:
		Notify.toast(
			(
				tr("Packed %d frames on %d pages, from %s, and %s.")
				% [result.frames, result.pages, result.path.get_file(), result.json_path.get_file()]
			)
		)
		return true
	Notify.toast(
		(
			tr("Packed %d frames into %s (%d×%d px) and %s.")
			% [result.frames, result.path.get_file(), size.x, size.y, result.json_path.get_file()]
		)
	)
	return true


## Frames linked to files that were just written over would be cut from what
## spritesheetbelli made, with their edits made twice, so they're unlinked instead
func unlink_overwritten(paths: PackedStringArray) -> void:
	var document := Global.document
	var unlinked: PackedStringArray = []
	for path in paths:
		if path not in document.unwatched_paths:
			document.unwatched_paths.append(path)
		document.source_hashes.erase(path)
		if FrameSource.unlink(Global.spritesheet, path) > 0:
			unlinked.append(path.get_file())
	if not unlinked.is_empty():
		Notify.toast(
			(
				tr("Frames from %s are no longer linked to it, since the export wrote over it.")
				% ", ".join(unlinked)
			),
			6.0
		)


## Frames are about to be linked to [param path], so it's watched again even if it was
## exported over before
func _linking(path: String) -> void:
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


static func _is_big_sheet() -> bool:
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
