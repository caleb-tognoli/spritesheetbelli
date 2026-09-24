class_name FileController
extends Node
## Opening, saving, exporting and adding files, with the dialogs they need.

const PROJECT_FILTER := "*.sbelli ; spritesheetbelli projects"
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.jpe, *.webp ; Images"

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
	"Open", FileDialog.FILE_MODE_OPEN_FILE, [PROJECT_FILTER, IMAGE_FILTER]
)
var save_project_dialog := _create_file_dialog(
	"Save Project", FileDialog.FILE_MODE_SAVE_FILE, [PROJECT_FILTER]
)
var open_folder_dialog := _create_file_dialog("Add Folder", FileDialog.FILE_MODE_OPEN_DIR, [])

@onready var open_sprites_dialog: FileDialog = $OpenSpritesDialog
@onready var open_spritesheet_dialog: FileDialog = $OpenSpritesheetDialog
@onready var save_sprites_dialog: FileDialog = $SaveSpritesDialog
@onready var export_image_dialog: FileDialog = $ExportImageDialog


func _ready() -> void:
	open_sprites_dialog.files_selected.connect(add_sprites_from_paths)
	open_spritesheet_dialog.file_selected.connect(show_add_spritesheet_window)
	open_dialog.file_selected.connect(open_path)
	save_sprites_dialog.dir_selected.connect(save_sprites)
	export_image_dialog.file_selected.connect(export_image_to)
	save_project_dialog.file_selected.connect(save_project)
	save_project_dialog.canceled.connect(func() -> void: after_save = Callable())
	open_folder_dialog.dir_selected.connect(add_sprites_from_folder)
	add_child(open_dialog)
	add_child(save_project_dialog)
	add_child(open_folder_dialog)
	get_window().files_dropped.connect(open_dropped_files)

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
		export_image_dialog,
		open_dialog,
		save_project_dialog,
		open_folder_dialog,
	]:
		var on_closed := func() -> void: open_file_dialogs.erase(dialog)
		dialog.canceled.connect(on_closed)
		dialog.file_selected.connect(on_closed.unbind(1))
		dialog.files_selected.connect(on_closed.unbind(1))
		dialog.dir_selected.connect(on_closed.unbind(1))


## Native file dialogs don't make the FileDialog visible, so calling popup() while
## one is already open spawns a second dialog, and each one emits its selection.
func popup_file_dialog(dialog: FileDialog) -> void:
	if dialog in open_file_dialogs:
		return
	open_file_dialogs.append(dialog)
	dialog.popup()


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

	var imgs: Array[Image] = []
	var failed_files: PackedStringArray = []
	for path in sorted_paths:
		var img := Image.load_from_file(path)
		if img:
			img.resource_name = path.get_file()
			imgs.append(img)
		else:
			failed_files.append(path.get_file())
	Global.document.perform("Add sprites", Global.spritesheet.add_frames.bind(imgs))

	if not failed_files.is_empty():
		Notify.error("Could not load: %s." % ", ".join(failed_files))


## Adds every image in [param folder] (not its subfolders), sorted by name
func add_sprites_from_folder(folder: String) -> void:
	var paths := get_images_in_folder(folder)
	if paths.is_empty():
		Notify.error("There are no images in %s." % folder.get_file())
		return
	add_sprites_from_paths(paths)


static func get_images_in_folder(folder: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	for file in DirAccess.get_files_at(folder):
		if is_image_path(file):
			paths.append(folder.path_join(file))
	return paths


static func is_image_path(path: String) -> bool:
	return path.get_extension().to_lower() in SpritesheetExporter.IMAGE_EXTENSIONS


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
		elif is_image_path(path):
			images.append(path)

	if images.is_empty():
		Notify.error("Drop images, folders of images or a .sbelli project.")
	elif images.size() == 1 and not DirAccess.dir_exists_absolute(paths[0]):
		show_add_spritesheet_window(images[0])
	else:
		add_sprites_from_paths(images)


func show_add_spritesheet_window(spritesheet_path: String) -> void:
	var img := Image.load_from_file(spritesheet_path)
	if not img:
		set_filepath_when_opening_spritesheet = false
		Notify.error("Could not load %s." % spritesheet_path.get_file())
		return

	if set_filepath_when_opening_spritesheet:
		set_filepath_when_opening_spritesheet = false
		Global.document.reset()
		Global.document.export_path = spritesheet_path
		loading_opened_file = true
	add_spritesheet_window.setup(img, spritesheet_path)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func save_sprites(folder: String) -> void:
	var errors: PackedStringArray = []
	var written := SpritesheetExporter.export_sprites(Global.spritesheet, folder, errors)
	if not errors.is_empty():
		Notify.error("Could not save: %s." % ", ".join(errors))
		return
	Notify.message(
		"Saved successfully", "Saved %d images to %s." % [written.size(), folder.get_file()]
	)


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
	unsaved_changes_dialog.dialog_text = "Save changes to %s before %s?" % [file_name, before]
	unsaved_changes_dialog.popup_centered()


## Saves the project to its file, or asks where to save. Returns true if saved right away.
func save() -> bool:
	if not ProjectFile.is_project_path(Global.document.path):
		save_as()
		return false
	return save_project(Global.document.path)


func save_as() -> void:
	var suggested := Global.document.path
	if suggested.is_empty() and Global.document.export_path:
		suggested = Global.document.export_path
	if suggested:
		save_project_dialog.current_path = ProjectFile.with_extension(suggested)
	popup_file_dialog(save_project_dialog)


func save_project(path: String) -> bool:
	path = ProjectFile.with_extension(path)
	var extra := {"export_path": Global.document.export_path}
	var error := ProjectFile.save(Global.spritesheet, path, extra)
	if error != OK:
		Notify.error("Could not save %s (%s)." % [path.get_file(), error_string(error)])
		after_save = Callable()
		return false

	Global.document.path = path
	Global.document.mark_saved()
	if after_save.is_valid():
		var action := after_save
		after_save = Callable()
		action.call()
	else:
		Notify.message("Saved", "Saved %s." % path.get_file())
	return true


func open_project(path: String) -> bool:
	var result := ProjectFile.load(path)
	if result.has("error"):
		Notify.error(result.error)
		return false
	Global.document.load_state(result.state, path, result.extra.get("export_path", ""))
	return true


## Opens a project, or an image through the Add Spritesheet window
func open_path(path: String) -> void:
	if ProjectFile.is_project_path(path):
		open_project(path)
	else:
		set_filepath_when_opening_spritesheet = true
		show_add_spritesheet_window(path)


## Exports the image to the last export path, or asks where
func export_image() -> void:
	if Global.document.export_path.is_empty():
		export_image_as()
	else:
		export_image_to(Global.document.export_path)


func export_image_as() -> void:
	if Global.document.export_path:
		export_image_dialog.current_path = Global.document.export_path
	popup_file_dialog(export_image_dialog)


func export_image_to(path: String) -> bool:
	if Global.spritesheet.is_empty():
		Notify.error("The spritesheet is empty.")
		return false

	var spritesheet_image := Global.spritesheet.get_image()
	path = SpritesheetExporter.with_image_extension(path)
	var options := ExportOptions.new()
	var error := SpritesheetExporter.save_image(spritesheet_image, path, options)

	if error != OK:
		Notify.error("Could not export to %s (%s)." % [path, error_string(error)])
		return false

	var message := "Exported %s in %s." % [path.get_file(), path.get_base_dir().get_file()]
	if (
		not SpritesheetExporter.supports_transparency(path)
		and ImageUtils.has_transparency(spritesheet_image)
		and not warned_about_jpg_transparency
	):
		warned_about_jpg_transparency = true
		message += (
			"\nJPG doesn't support transparency, so transparent areas were filled with %s."
			% ("white" if options.opaque_background == Color.WHITE else "the background colour")
		)
	Global.document.export_path = path
	Notify.message("Exported", message)
	return true


func new_spritesheet() -> void:
	confirm_unsaved_changes("creating a new one", Global.document.reset)


func open_spritesheet() -> void:
	# The spritesheet is only reset once a file is picked, so canceling keeps the current one
	confirm_unsaved_changes("opening another file", popup_file_dialog.bind(open_dialog))


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
