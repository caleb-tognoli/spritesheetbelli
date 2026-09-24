class_name SpinScroll
## Ctrl+mouse wheel over a SpinBox steps its value without clicking it first.
## (The plain wheel keeps scrolling the panel the field is in.)


static func enable(spin: SpinBox) -> void:
	var handler := func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed):
			return
		if not event.is_command_or_control_pressed() or not spin.editable:
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				spin.value += spin.step
			MOUSE_BUTTON_WHEEL_DOWN:
				spin.value -= spin.step
			_:
				return
		spin.accept_event()
	spin.gui_input.connect(handler)
	spin.get_line_edit().gui_input.connect(handler)
