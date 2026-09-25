class_name OutlineDialog
extends ConfirmationDialog
## Asks for the colour and thickness of an outline around the selected frames.

## Emitted with the chosen outline
signal outline_chosen(color: Color, thickness: int, corners: bool)

var picker := ColorPickerButton.new()
var thickness := SpinBox.new()
var corners := CheckBox.new()


func _init() -> void:
	title = "Add Outline"
	ok_button_text = "Add"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)

	var color_label := Label.new()
	color_label.text = "Colour"
	grid.add_child(color_label)
	picker.custom_minimum_size = Vector2(80, 0)
	picker.color = Color.BLACK
	grid.add_child(picker)

	var thickness_label := Label.new()
	thickness_label.text = "Thickness"
	grid.add_child(thickness_label)
	thickness.min_value = 1
	thickness.max_value = 16
	thickness.suffix = "px"
	grid.add_child(thickness)

	grid.add_child(Control.new())
	corners.text = "Fill corners"
	corners.tooltip_text = "Also outline diagonally, for square corners instead of round ones"
	grid.add_child(corners)
	LabelLink.link(color_label, picker)
	LabelLink.link(thickness_label, thickness)

	confirmed.connect(
		func() -> void:
			outline_chosen.emit(picker.color, int(thickness.value), corners.button_pressed)
	)


func _ready() -> void:
	SpinScroll.enable(thickness)
