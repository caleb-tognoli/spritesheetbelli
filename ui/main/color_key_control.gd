class_name ColorKeyControl
extends HBoxContainer
## "Make [swatch] transparent", with an eyedropper and a tolerance: a colour to make
## transparent, like a sheet's background. The colour comes from the swatch's picker, or
## from clicking a preview with the eyedropper, see [method watch_preview]. Choosing a
## colour turns it on. With [method set_always_on], there's no turning it off.

## It was turned on or off, or its colour or tolerance changed. Changes can come many at
## once, e.g. while dragging in the picker.
signal changed
## The eyedropper was turned on or off
signal picking_changed(on: bool)

const EYEDROPPER_ICON := preload("res://assets/icons/ColorPick.svg")

## Makes the colour transparent when pressed
var enabled_check := CheckBox.new()
## Shown instead of [member enabled_check] once [method set_always_on]
var _make_label := Label.new()
var swatch := ColorPickerButton.new()
var eyedropper := Button.new()
## How different a pixel can be from the colour, in percent
var tolerance_field := SpinBox.new()


func _init() -> void:
	add_theme_constant_override("separation", 6)
	enabled_check.text = "Make"
	enabled_check.tooltip_text = "Makes this colour transparent before cutting"
	add_child(enabled_check)
	_make_label.text = "Make"
	_make_label.visible = false
	add_child(_make_label)
	swatch.custom_minimum_size = Vector2(32, 0)
	swatch.edit_alpha = false
	swatch.tooltip_text = "The colour to make transparent"
	swatch.color_changed.connect(
		func(_color: Color) -> void:
			enabled_check.set_pressed_no_signal(true)
			_update_tolerance()
			changed.emit()
	)
	add_child(swatch)
	var transparent_label := Label.new()
	transparent_label.text = "transparent"
	add_child(transparent_label)
	LabelLink.link(transparent_label, enabled_check)
	enabled_check.toggled.connect(
		func(_on: bool) -> void:
			_update_tolerance()
			changed.emit()
	)

	eyedropper.icon = EYEDROPPER_ICON
	eyedropper.flat = true
	eyedropper.toggle_mode = true
	eyedropper.focus_mode = Control.FOCUS_NONE
	eyedropper.tooltip_text = "Pick the colour by clicking the preview"
	eyedropper.toggled.connect(picking_changed.emit)
	add_child(eyedropper)

	var tolerance_label := Label.new()
	tolerance_label.text = "Tolerance"
	add_child(tolerance_label)
	tolerance_field.max_value = 100
	tolerance_field.suffix = "%"
	tolerance_field.select_all_on_focus = true
	tolerance_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tolerance_field.tooltip_text = "How different a pixel can be and still be made transparent"
	tolerance_field.value_changed.connect(
		func(value: float) -> void:
			# What Add Spritesheet and Remove Background Colour start with next time
			Settings.set_value(&"background_tolerance", value / 100.0)
			if is_on():
				changed.emit()
	)
	add_child(tolerance_field)
	LabelLink.link(tolerance_label, tolerance_field)
	SpinScroll.enable(tolerance_field)
	set_key(false, Color.MAGENTA)


func is_on() -> bool:
	return enabled_check.button_pressed


func get_color() -> Color:
	return swatch.color


## How different a pixel can be from the colour, from 0 to 1, see [method ImageUtils.color_key]
func get_tolerance() -> float:
	return tolerance_field.value / 100.0


## Shows [param color] with [param tolerance] (0 to 1), made transparent when [param on],
## without [signal changed]
func set_key(on: bool, color: Color, tolerance := SheetBackground.DEFAULT_TOLERANCE) -> void:
	enabled_check.set_pressed_no_signal(on)
	swatch.color = Color(color, 1.0)
	tolerance_field.set_value_no_signal(roundf(tolerance * 100.0))
	_update_tolerance()


func is_picking() -> bool:
	return eyedropper.button_pressed


## Turns the eyedropper on or off, with [signal picking_changed]
func set_picking(on: bool) -> void:
	eyedropper.button_pressed = on


## Makes [param color] transparent, as picked with the eyedropper, and puts the eyedropper
## away. Transparent pixels have no colour to pick, so the eyedropper stays out for another
## click.
func pick(color: Color) -> void:
	if color.a <= 0.0:
		return
	set_key(true, color, get_tolerance())
	set_picking(false)
	changed.emit()


## Always makes the colour transparent, for places where that's the point, like removing
## a background colour from frames: a plain "Make" takes the checkbox's place
func set_always_on() -> void:
	enabled_check.visible = false
	_make_label.visible = true
	set_key(true, get_color(), get_tolerance())


## Lets the eyedropper pick colours by clicking [param preview]
func watch_preview(preview: SpritesheetPreview) -> void:
	picking_changed.connect(func(on: bool) -> void: preview.picking = on)
	preview.color_picked.connect(pick)


## The tolerance only matters when the colour is made transparent
func _update_tolerance() -> void:
	tolerance_field.editable = is_on()
