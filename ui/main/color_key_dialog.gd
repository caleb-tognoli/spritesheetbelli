class_name ColorKeyDialog
extends ConfirmationDialog
## Asks which colour to make transparent, and how close a pixel must be to it.

## Emitted with the chosen colour and tolerance (0 to 1)
signal color_chosen(color: Color, tolerance: float)

var picker := ColorPickerButton.new()
var tolerance := SpinBox.new()


func _init() -> void:
	title = "Remove Background Colour"
	ok_button_text = "Remove"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	add_child(grid)

	var color_label := Label.new()
	color_label.text = "Colour to make transparent"
	grid.add_child(color_label)
	picker.custom_minimum_size = Vector2(80, 0)
	picker.edit_alpha = false
	grid.add_child(picker)

	var tolerance_label := Label.new()
	tolerance_label.text = "Tolerance"
	grid.add_child(tolerance_label)
	tolerance.min_value = 0
	tolerance.max_value = 100
	tolerance.value = 10
	tolerance.suffix = "%"
	tolerance.tooltip_text = "How different a pixel can be from the colour and still be removed"
	grid.add_child(tolerance)

	confirmed.connect(func() -> void: color_chosen.emit(picker.color, tolerance.value / 100.0))


## Opens the dialog suggesting the top-left pixel of [param sample], usually the background
func open(sample: Image) -> void:
	if sample and not sample.is_empty():
		picker.color = Color(sample.get_pixel(0, 0), 1.0)
	popup_centered()
