class_name SpacingDropdown
extends OptionsDropdown
## Padding, spacing and extruded edges in a floating panel, for the grid and the atlas
## sections of the sidebar

## The user changed a value
signal values_changed

var padding := SpinBox.new()
var spacing := SpinBox.new()
var extrude := SpinBox.new()

var _updating := false


func _init() -> void:
	super("Spacing & Padding")
	tooltip_text = "Empty pixels between frames and around the sheet, and extruded edges"
	for entry: Array in [
		[spacing, "Spacing", "Empty pixels between frames"],
		[padding, "Padding", "Empty pixels around the whole sheet or each page"],
		[
			extrude,
			"Extrude edges",
			(
				"Repeats each frame's edge pixels outward, so scaled or filtered sprites "
				+ "don't pick up their neighbours' colours"
			)
		],
	]:
		var spin: SpinBox = entry[0]
		spin.max_value = 256
		spin.suffix = "px"
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		spin.select_all_on_focus = true
		spin.custom_minimum_size.x = 110
		spin.value_changed.connect(_changed.unbind(1))
		add_field(
			entry[1],
			spin,
			entry[2],
			func() -> void: spin.value = 0,
			func() -> bool: return spin.value == 0
		)
	summarize = _summary


func _ready() -> void:
	for spin: SpinBox in [padding, spacing, extrude]:
		SpinScroll.enable(spin)


## Shows [param values] without telling about it
func set_values(padding_px: int, spacing_px: int, extrude_px: int) -> void:
	_updating = true
	padding.set_value_no_signal(padding_px)
	spacing.set_value_no_signal(spacing_px)
	extrude.set_value_no_signal(extrude_px)
	_updating = false
	update_text()


func _changed() -> void:
	update_text()
	if not _updating:
		values_changed.emit()


func _summary() -> String:
	var parts: PackedStringArray = []
	for entry: Array in [[spacing, "Spacing %d"], [padding, "Padding %d"], [extrude, "Extrude %d"]]:
		var spin: SpinBox = entry[0]
		if spin.value > 0:
			parts.append(tr(entry[1]) % spin.value)
	return " · ".join(parts)
