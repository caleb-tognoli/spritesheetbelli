class_name OutputPathField
extends HBoxContainer
## A field for where an export writes, with a Browse… button that emits
## [signal browse_pressed]: [method browse] then asks with a file dialog, which asks before
## writing over a file, or picks a folder for sprites.

signal path_changed(path: String)
signal browse_pressed

## What file dialogs call files of each extension
const NAMES := {  # L10n.mark
	&"png": "PNG Images",
	&"jpg": "JPEG Images",
	&"webp": "WebP Images",
	&"gif": "GIF Images",
}
const PATTERNS := {"jpg": "*.jpg, *.jpeg, *.jpe"}

var line_edit := LineEdit.new()
var browse_button := Button.new()
var file_dialog := FileDialog.new()
## Runs once with the path picked in the file dialog
var _then := Callable()

var path: String:
	get:
		return line_edit.text.strip_edges()
	set(value):
		line_edit.text = value
		# The file name at the end shows, not the start of a long path
		line_edit.caret_column = value.length()


func _init() -> void:
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.placeholder_text = "Asked when exporting"
	add_child(line_edit)
	browse_button.text = "Browse…"
	browse_button.tooltip_text = "Pick where to export"
	add_child(browse_button)
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	add_child(file_dialog)

	line_edit.text_changed.connect(func(_text: String) -> void: path_changed.emit(path))
	browse_button.pressed.connect(browse_pressed.emit)
	file_dialog.file_selected.connect(_on_picked)
	file_dialog.dir_selected.connect(_on_picked)
	file_dialog.canceled.connect(func() -> void: _then = Callable())


## Asks where to export a file with [param extension], or a folder when it's empty,
## starting from the path in the field or else [param suggested]. [param then] runs with
## the path picked. A folder is asked for with [param folder_title], translated, or else
## "Export Sprites".
func browse(suggested: String, extension: String, then := Callable(), folder_title := "") -> void:
	var start := path if path else suggested
	file_dialog.file_mode = (
		FileDialog.FILE_MODE_OPEN_DIR if extension.is_empty() else FileDialog.FILE_MODE_SAVE_FILE
	)
	# After the mode, which sets a title of its own
	if extension:
		file_dialog.title = tr("Export")
	else:
		file_dialog.title = folder_title if folder_title else tr("Export Sprites")
	file_dialog.filters = []
	if extension:
		var pattern: String = PATTERNS.get(extension, "*." + extension)
		var kind := tr(NAMES[extension]) if NAMES.has(extension) else extension.to_upper()
		file_dialog.filters = ["%s ; %s" % [pattern, kind]]
	# Cancelling a native dialog clears the name, so it's always set
	if start.get_base_dir():
		file_dialog.current_dir = start.get_base_dir()
	if extension:
		file_dialog.current_file = start.get_file()
	_then = then
	file_dialog.popup_centered()


func _on_picked(picked: String) -> void:
	path = picked
	path_changed.emit(picked)
	if _then.is_valid():
		var then := _then
		_then = Callable()
		then.call(picked)
