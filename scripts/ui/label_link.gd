class_name LabelLink
## Makes clicking a setting's label act on its control, like clicking a checkbox's own
## text: dropdowns open, fields get the cursor and checkboxes toggle.


static func link(label: Label, control: Control) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				activate(control)
				label.accept_event()
	)


## Does what clicking [param control] would, or its first input for a container
static func activate(control: Control) -> void:
	var target := _find_input(control)
	if target == null or not target.is_visible_in_tree():
		return
	if target is BaseButton and (target as BaseButton).disabled:
		return
	if target is OptionButton:
		(target as OptionButton).show_popup()
	elif target is ColorPickerButton:
		var picker := target as ColorPickerButton
		var below := picker.get_screen_position() + Vector2(0, picker.size.y)
		picker.get_popup().popup(Rect2i(Vector2i(below), Vector2i.ZERO))
	elif target is CheckBox or target is CheckButton:
		var check := target as BaseButton
		check.button_pressed = not check.button_pressed
	elif target is SpinBox:
		var line_edit := (target as SpinBox).get_line_edit()
		line_edit.grab_focus()
		line_edit.select_all()
	elif target is LineEdit:
		(target as LineEdit).grab_focus()
		(target as LineEdit).select_all()
	else:
		target.grab_focus()


static func _find_input(control: Control) -> Control:
	if control is BaseButton or control is LineEdit or control is SpinBox:
		return control
	for child in control.get_children():
		if child is Control:
			var found := _find_input(child)
			if found:
				return found
	return null
