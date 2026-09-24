extends Control

@onready var add_spritesheet_window: AddSpritesheetWindow = $AddSpritesheetWindow
@onready var open_sprites_dialog: FileDialog = $OpenSpritesDialog
@onready var open_spritesheet_dialog: FileDialog = $OpenSpritesheetDialog
@onready var save_sprites_dialog: FileDialog = $SaveSpritesDialog
@onready var save_spritesheet_dialog: FileDialog = $SaveSpritesheetDialog
@onready var notification_dialog: AcceptDialog = $NotificationDialog
@onready var confirmation_dialog: ConfirmationDialog = $ConfirmationDialog
@onready var preview_area: Control = %PreviewArea
@onready var grid_rows: LineEdit = %GridRows
@onready var grid_columns: LineEdit = %GridColumns
@onready var sprite_width: LineEdit = %SpriteWidth
@onready var sprite_height: LineEdit = %SpriteHeight
@onready var add_sprites_btn: Button = %AddSprites
@onready var add_spritesheet_btn: Button = %AddSpritesheet
@onready var spritesheet_width: Label = %SpritesheetWidth
@onready var spritesheet_height: Label = %SpritesheetHeight

var set_filepath_when_opening_spritesheet: bool = false
var pending_confirm_action: Callable
var open_file_dialogs: Array[FileDialog] = []
var warned_about_jpg_transparency := false


func _ready() -> void:
	preview_area.spritesheet_preview.spritesheet = Global.spritesheet
	set_text_params(Global.spritesheet)
	disable_if_empty()

	Global.spritesheet.updated.connect(set_text_params.bind(Global.spritesheet))
	Global.spritesheet.updated.connect(disable_if_empty)
	open_spritesheet_dialog.file_selected.connect(show_add_spritesheet_window)
	open_spritesheet_dialog.canceled.connect(func(): set_filepath_when_opening_spritesheet = false)
	add_sprites_btn.pressed.connect(popup_file_dialog.bind(open_sprites_dialog))
	add_spritesheet_btn.pressed.connect(popup_file_dialog.bind(open_spritesheet_dialog))
	save_sprites_dialog.dir_selected.connect(save_sprites)
	save_spritesheet_dialog.file_selected.connect(save_spritesheet)
	grid_rows.text_submitted.connect(
		func(str_rows): set_spritesheet_grid_size(Global.spritesheet.grid_size.x, int(str_rows))
	)
	grid_columns.text_submitted.connect(
		func(str_columns):
			set_spritesheet_grid_size(int(str_columns), Global.spritesheet.grid_size.y)
	)
	sprite_width.text_submitted.connect(
		func(str_width):
			if Global.spritesheet.sprite_size.x <= 0:
				return
			var width: int = int(str_width)
			var height: int = (
				(Global.spritesheet.sprite_size.y * width) / Global.spritesheet.sprite_size.x
			)
			resize_sprites(Vector2i(width, height))
	)
	sprite_height.text_submitted.connect(
		func(str_height):
			if Global.spritesheet.sprite_size.y <= 0:
				return
			var height: int = int(str_height)
			var width: int = (
				(Global.spritesheet.sprite_size.x * height) / Global.spritesheet.sprite_size.y
			)
			resize_sprites(Vector2i(width, height))
	)
	open_sprites_dialog.files_selected.connect(add_sprites_from_paths)
	confirmation_dialog.confirmed.connect(
		func():
			var action := pending_confirm_action
			pending_confirm_action = Callable()
			if action.is_valid():
				action.call()
	)
	confirmation_dialog.canceled.connect(func(): pending_confirm_action = Callable())

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
	Global.spritesheet.add_frames(imgs)

	if not failed_files.is_empty():
		show_notification_dialog("Error", "Could not load: %s." % ", ".join(failed_files))


func resize_sprites(new_size: Vector2i) -> void:
	if new_size.x <= 0 or new_size.y <= 0:
		set_text_params(Global.spritesheet)
		return
	Global.spritesheet.resize_sprites(new_size)


func set_text_params(spritesheet: Spritesheet) -> void:
	grid_rows.text = str(spritesheet.grid_size.y)
	grid_columns.text = str(spritesheet.grid_size.x)
	sprite_width.text = str(spritesheet.sprite_size.x)
	sprite_height.text = str(spritesheet.sprite_size.y)
	spritesheet_width.text = str(spritesheet.sprite_size.x * spritesheet.grid_size.x)
	spritesheet_height.text = str(spritesheet.sprite_size.y * spritesheet.grid_size.y)


func disable_if_empty():
	var is_empty := Global.spritesheet.is_empty()
	grid_rows.editable = not is_empty
	grid_columns.editable = not is_empty
	sprite_width.editable = not is_empty
	sprite_height.editable = not is_empty


func show_add_spritesheet_window(spritesheet_path: String) -> void:
	var img := Image.load_from_file(spritesheet_path)
	if not img:
		set_filepath_when_opening_spritesheet = false
		show_notification_dialog("Error", "Could not load %s." % spritesheet_path.get_file())
		return

	if set_filepath_when_opening_spritesheet:
		set_filepath_when_opening_spritesheet = false
		Global.reset_spritesheet()
		Global.filepath = spritesheet_path
	add_spritesheet_window.setup(img)
	add_spritesheet_window.popup_centered(get_window().size * 0.8)


func show_notification_dialog(title: String, dialog_text: String):
	notification_dialog.title = title
	notification_dialog.dialog_text = dialog_text
	notification_dialog.popup_centered()


func show_confirmation_dialog(title: String, dialog_text: String, confirm_action: Callable):
	confirmation_dialog.title = title
	confirmation_dialog.dialog_text = dialog_text
	pending_confirm_action = confirm_action
	confirmation_dialog.popup_centered()


func set_spritesheet_grid_size(columns: int, rows: int):
	var frames_outside_count := Global.spritesheet.count_frames_outside(Vector2i(columns, rows))
	var spritesheet_set_size := Global.spritesheet.set_grid_size.bind(Vector2i(columns, rows))

	if frames_outside_count > 0:
		show_confirmation_dialog(
			"Confirm resize",
			(
				"Resizing the grid to %d×%d would delete %d sprites."
				% [columns, rows, frames_outside_count]
			),
			spritesheet_set_size
		)
	else:
		spritesheet_set_size.call()
	# Show the current size again if the change was canceled or not possible
	set_text_params(Global.spritesheet)


func save_sprites(folder: String):
	var errors: PackedStringArray = []
	var written := SpritesheetExporter.export_sprites(Global.spritesheet, folder, errors)
	if not errors.is_empty():
		show_notification_dialog("Error", "Could not save: %s." % ", ".join(errors))
		return
	show_notification_dialog(
		"Saved successfully", "Saved %d images to %s." % [written.size(), folder.get_file()]
	)


func save_spritesheet(path: String):
	var spritesheet_image := Global.spritesheet.get_image()

	if spritesheet_image.get_size() == Vector2i.ZERO:
		show_notification_dialog("Error", "The spritesheet is empty.")
		return

	path = SpritesheetExporter.with_image_extension(path)
	var options := ExportOptions.new()
	var error := SpritesheetExporter.save_image(spritesheet_image, path, options)

	if error != OK:
		show_notification_dialog(
			"Error", "Could not save spritesheet to %s (%s)." % [path, error_string(error)]
		)
		return

	var message := "Saved spritesheet to %s." % [path.get_base_dir().get_file()]
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
	show_notification_dialog("Saved successfully", message)
	Global.filepath = path
	Global.has_unsaved_changes = false


func new_spritesheet():
	if Global.has_unsaved_changes and not Global.spritesheet.is_empty():
		show_confirmation_dialog(
			"New spritesheet", "Unsaved progress will be lost", Global.reset_spritesheet
		)
	else:
		Global.reset_spritesheet()


func open_spritesheet():
	# The spritesheet is only reset once a file is picked, so canceling keeps the current one
	var open_spritesheet_internal := func():
		set_filepath_when_opening_spritesheet = true
		popup_file_dialog(open_spritesheet_dialog)

	if Global.has_unsaved_changes and not Global.spritesheet.is_empty():
		show_confirmation_dialog(
			"Open spritesheet", "Unsaved progress will be lost", open_spritesheet_internal
		)
	else:
		open_spritesheet_internal.call()
