class_name TemplateFileField
extends HBoxContainer
## A field for the path of a template file (see [Template]) with a Pick… button: a file
## dialog, or in a browser its file picker, which copies the file into the browser's
## storage so it can be read by path.

signal path_changed(path: String)

## The file dialog's filter, which it translates. It adds one of all files itself.
const FILTER := "*.template ; Templates"  # L10n.mark

var line_edit := LineEdit.new()
var pick_button := Button.new()
var file_dialog := FileDialog.new()

var path: String:
	get:
		return line_edit.text.strip_edges()
	set(value):
		line_edit.text = value
		# The file name at the end shows, not the start of a long path
		line_edit.caret_column = value.length()


func _init() -> void:
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.placeholder_text = "No template picked"
	add_child(line_edit)
	pick_button.text = "Pick…"
	pick_button.tooltip_text = "Pick a template file"
	add_child(pick_button)
	file_dialog.title = "Pick a Template"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = [FILTER]
	add_child(file_dialog)

	line_edit.text_changed.connect(func(_text: String) -> void: path_changed.emit(path))
	pick_button.pressed.connect(pick)
	file_dialog.file_selected.connect(_on_picked)


## Asks for a template file, starting where the current one is
func pick() -> void:
	if WebFiles.is_web():
		WebFiles.pick(
			"." + AtlasFormats.EXTENSION,
			false,
			func(paths: PackedStringArray) -> void:
				if paths:
					_on_picked(paths[0])
		)
		return
	if path:
		file_dialog.current_path = path
	file_dialog.popup_centered()


func _on_picked(picked: String) -> void:
	path = picked
	path_changed.emit(picked)
