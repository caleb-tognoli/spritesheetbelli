class_name FileController
extends Node
## Opening, saving, exporting and adding files, with the dialogs they need.

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

@onready var open_sprites_dialog: FileDialog = $OpenSpritesDialog
@onready var open_spritesheet_dialog: FileDialog = $OpenSpritesheetDialog
@onready var save_sprites_dialog: FileDialog = $SaveSpritesDialog
@onready var save_spritesheet_dialog: FileDialog = $SaveSpritesheetDialog


func _ready() -> void:
	open_sprites_dialog.files_selected.connect(add_sprites_from_paths)
	open_spritesheet_dialog.file_selected.connect(show_add_spritesheet_window)
	open_spritesheet_dialog.canceled.connect(func(): set_filepath_when_opening_spritesheet = false)
	save_sprites_dialog.dir_selected.connect(save_sprites)
	save_spritesheet_dialog.file_selected.connect(save_spritesheet)
	save_spritesheet_dialog.canceled.connect(func(): after_save = Callable())

	# Loading the opened file is not an unsaved change
	add_spritesheet_window.frames_added.connect(
		func():
			if loading_opened_file:
				loading_opened_file = false
				Global.document.load_state(Global.spritesheet.get_state(), Global.document.path)
	)
	add_spritesheet_window.canceled.connect(func(): loading_opened_file = false)

	_create_unsaved_changes_dialog()
	for dialog: FileDialog in [
		open_sprites_dialog,
		open_spritesheet_dialog,
		save_sprites_dialog,
		save_spritesheet_dialog,
	]:
		var on_closed := func(): open_file_dialogs.erase(dialog)
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
	sorted_paths.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)

	var imgs: Array[Image] = []
	var failed_files: PackedStringArray = []
	for path in sorted_paths:
		var img := Image.load_from_file(path)
		if img:
			imgs.append(img)
		else:
			failed_files.append(path.get_file())
	Global.document.perform("Add sprites", Global.spritesheet.add_frames.bind(imgs))

	if not failed_files.is_empty():
		Notify.error("Could not load: %s." % ", ".join(failed_files))


func show_add_spritesheet_window(spritesheet_path: String) -> void:
	var img := Image.load_from_file(spritesheet_path)
	if not img:
		set_filepath_when_opening_spritesheet = false
		Notify.error("Could not load %s." % spritesheet_path.get_file())
		return

	if set_filepath_when_opening_spritesheet:
		set_filepath_when_opening_spritesheet = false
		Global.document.reset()
		Global.document.path = spritesheet_path
		loading_opened_file = true
	add_spritesheet_window.setup(img)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func save_sprites(folder: String):
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
		func():
			after_save = after_unsaved_changes
			save()
	)
	unsaved_changes_dialog.custom_action.connect(
		func(_action: StringName):
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


## Saves to the current file, or asks where to save. Returns true if saved right away.
func save() -> bool:
	if Global.document.path.is_empty():
		popup_file_dialog(save_spritesheet_dialog)
		return false
	return save_spritesheet(Global.document.path)


func save_spritesheet(path: String) -> bool:
	if Global.spritesheet.is_empty():
		Notify.error("The spritesheet is empty.")
		return false

	var spritesheet_image := Global.spritesheet.get_image()
	path = SpritesheetExporter.with_image_extension(path)
	var options := ExportOptions.new()
	var error := SpritesheetExporter.save_image(spritesheet_image, path, options)

	if error != OK:
		Notify.error("Could not save spritesheet to %s (%s)." % [path, error_string(error)])
		after_save = Callable()
		return false

	var message := "Saved %s in %s." % [path.get_file(), path.get_base_dir().get_file()]
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
	Global.document.path = path
	Global.document.mark_saved()
	if after_save.is_valid():
		var action := after_save
		after_save = Callable()
		action.call()
	else:
		Notify.message("Saved successfully", message)
	return true


func new_spritesheet():
	confirm_unsaved_changes("creating a new one", Global.document.reset)


func open_spritesheet():
	# The spritesheet is only reset once a file is picked, so canceling keeps the current one
	var open_spritesheet_internal := func():
		set_filepath_when_opening_spritesheet = true
		popup_file_dialog(open_spritesheet_dialog)

	confirm_unsaved_changes("opening another file", open_spritesheet_internal)
