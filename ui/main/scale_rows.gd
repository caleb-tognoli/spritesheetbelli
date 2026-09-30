class_name ScaleRows
extends RefCounted
## The rows of the Export dialog for the scales an image, data file or atlas export is
## written at (see [member ExportOptions.scales]) and the suffix naming the files of each.

signal changed

var scales := LineEdit.new()
var suffix := NamePatternField.new()


## Adds the rows to [param grid] of [param dialog], see [method ExportDialog.add_row]
func add_to(dialog: ExportDialog, grid: GridContainer) -> void:
	var defaults := ExportOptions.new()
	scales.placeholder_text = defaults.scales
	scales.tooltip_text = (
		"The sizes to write the export at, like 1, 2: each is the sheet that many times "
		+ "bigger, with its own data file. Frames are resized from their original images "
		+ "with the sheet's filter; padding, spacing and extrusion grow with them."
	)
	dialog.add_row(grid, L10n.mark("Scales"), scales, ExportOptions.SCALED_TARGETS)
	suffix.use_tokens(
		ExportOptions.SCALE_TOKENS, func() -> Dictionary: return {"scale": 2}, "scale"
	)
	suffix.line_edit.placeholder_text = defaults.scale_suffix
	suffix.line_edit.custom_minimum_size = Vector2(120, 0)
	suffix.tooltip_text = (
		"Added to the names of the files of each scale but 1, before the extension: "
		+ "hero@2x.png and hero@2x.json, pages hero_0@2x.png, strips walk@2x_strip8.png"
	)
	suffix.line_edit.tooltip_text = suffix.tooltip_text
	var several := func(options: ExportOptions) -> bool:
		return options.get_scales() != PackedInt32Array([1])
	dialog.add_row(
		grid, L10n.mark("Scale suffix"), suffix, ExportOptions.SCALED_TARGETS, "", several
	)
	scales.text_changed.connect(changed.emit.unbind(1))
	suffix.text_changed.connect(changed.emit.unbind(1))


## Shows the settings of [param options]
func show_options(options: ExportOptions) -> void:
	scales.text = options.scales
	suffix.text = options.scale_suffix


## Takes the settings shown into [param options]. Empty fields are the defaults.
func apply(options: ExportOptions) -> void:
	if scales.text.strip_edges():
		options.scales = scales.text.strip_edges()
	if suffix.text.strip_edges():
		options.scale_suffix = suffix.text.strip_edges()
