class_name ColorField
extends PanelContainer
## A colour setting as wide as the fields around it and framed like them: a swatch of the
## colour, its code, or "Transparent" while it's fully transparent, and with
## [member clearable] a button that makes it transparent again. Clicking anywhere on it
## opens the colour picker.

## The colour was picked or cleared
signal color_changed(color: Color)

const CLEAR_ICON := preload("res://assets/icons/Close.svg")

## The swatch, which opens the picker
var picker := ColorPickerButton.new()
var label := Label.new()
## Makes the colour transparent again, shown while it isn't, with [member clearable]
## Only as tall as its icon, so the field is as tall as a text field
var clear_button := TextureButton.new()
## Whether the colour can be transparent, and [member clear_button] makes it so
var clearable := false:
	set(value):
		clearable = value
		picker.edit_alpha = value
		_update()
var color: Color:
	get:
		return picker.color
	set(value):
		picker.color = value
		_update()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	picker.flat = true
	picker.custom_minimum_size = Vector2(32, 0)
	picker.focus_mode = Control.FOCUS_NONE
	# Clicks open it through the field, which shows its tooltip all over
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker.edit_alpha = false
	picker.get_picker().presets_visible = false
	picker.color_changed.connect(
		func(value: Color) -> void:
			_update()
			color_changed.emit(value)
	)
	row.add_child(picker)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	clear_button.texture_normal = CLEAR_ICON
	clear_button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	clear_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.self_modulate.a = 0.7
	clear_button.mouse_entered.connect(func() -> void: clear_button.self_modulate.a = 1.0)
	clear_button.mouse_exited.connect(func() -> void: clear_button.self_modulate.a = 0.7)
	clear_button.pressed.connect(
		func() -> void:
			color = Color.TRANSPARENT
			color_changed.emit(color)
	)
	row.add_child(clear_button)
	_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		# Framed like a text field, and as tall with the clear button hidden
		var frame := get_theme_stylebox(&"normal", &"LineEdit")
		# Overriding it changes the theme again
		if get_theme_stylebox(&"panel") != frame:
			add_theme_stylebox_override(&"panel", frame)
		var font := get_theme_font(&"font", &"LineEdit")
		var font_size := get_theme_font_size(&"font_size", &"LineEdit")
		custom_minimum_size.y = frame.get_minimum_size().y + font.get_height(font_size)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		LabelLink.activate(picker)
		accept_event()


func _update() -> void:
	var transparent := is_zero_approx(color.a)
	label.text = tr("Transparent") if transparent else "#" + color.to_html(color.a < 1)
	clear_button.visible = clearable and not transparent
