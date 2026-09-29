class_name AnimationFilesRows
extends RefCounted
## The rows of the Export dialog for exports that write a file for each animation into a
## folder (see [AnimationFiles]): how a GIF of each animation is named, with an example.

signal changed

const T := ExportOptions.Target
## Files named in the example
const EXAMPLES := 3

var gif_pattern := NamePatternField.new()
var gif_example := Label.new()


## Adds the rows to [param grid] of [param dialog], see [method ExportDialog.add_row]
func add_to(dialog: ExportDialog, grid: GridContainer) -> void:
	var every := func(options: ExportOptions) -> bool: return options.gif_every_animation
	_set_up(gif_pattern, "How each GIF is named, with tokens such as {animation} filled in")
	gif_pattern.line_edit.placeholder_text = ExportOptions.new().gif_name_pattern
	dialog.add_row(grid, "File names", gif_pattern, [T.GIF], "", every)
	gif_example.theme_type_variation = &"StatusLabel"
	gif_example.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gif_example.custom_minimum_size = Vector2(200, 0)
	dialog.add_row(grid, "", gif_example, [T.GIF], "", every)


## Shows the settings of [param options]
func show_options(options: ExportOptions) -> void:
	gif_pattern.text = options.gif_name_pattern


## Takes the settings shown into [param options]. An empty pattern is the default.
func apply(options: ExportOptions) -> void:
	if gif_pattern.text.strip_edges():
		options.gif_name_pattern = gif_pattern.text


## Shows what the files of [param options] are named, from [param files], the paths it
## writes
func update(options: ExportOptions, files: PackedStringArray) -> void:
	var names := PackedStringArray()
	if options.target == T.GIF:
		for path in files.slice(0, EXAMPLES):
			names.append(path.get_file())
	gif_example.text = tr("For example: %s") % ", ".join(names) if names else ""


func _set_up(field: NamePatternField, tooltip: String) -> void:
	field.use_tokens(
		AnimationFiles.TOKENS,
		func() -> Dictionary: return AnimationFiles.get_example_values(Global.spritesheet),
		"count"
	)
	field.line_edit.custom_minimum_size = Vector2(120, 0)
	field.tooltip_text = tooltip
	field.line_edit.tooltip_text = tooltip
	field.text_changed.connect(changed.emit.unbind(1))
