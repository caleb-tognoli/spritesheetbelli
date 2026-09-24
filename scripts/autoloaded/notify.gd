extends Node
## Message and confirmation dialogs usable from anywhere.

var message_dialog := AcceptDialog.new()
var confirm_dialog := ConfirmationDialog.new()
var _confirm_action: Callable
var _toasts := VBoxContainer.new()


func _ready() -> void:
	for dialog: AcceptDialog in [message_dialog, confirm_dialog]:
		dialog.dialog_autowrap = true
		dialog.min_size = Vector2i(400, 0)
		dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(dialog)
	confirm_dialog.confirmed.connect(
		func() -> void:
			var action := _confirm_action
			_confirm_action = Callable()
			if action.is_valid():
				action.call()
	)
	confirm_dialog.canceled.connect(func() -> void: _confirm_action = Callable())

	# Toasts stack at the bottom-right of the main window, above everything
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.position -= Vector2(16, 40)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(_toasts)


func message(title: String, text: String) -> void:
	message_dialog.title = title
	message_dialog.dialog_text = text
	_popup(message_dialog)


func error(text: String) -> void:
	message("Error", text)


## A short message that fades away on its own, for things that went well
func toast(text: String, seconds := 3.0) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	panel.add_child(label)
	_toasts.add_child(panel)
	var tween := panel.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


## Messages shown right now, newest last
func get_toasts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for panel in _toasts.get_children():
		if not panel.is_queued_for_deletion():
			texts.append((panel.get_child(0) as Label).text)
	return texts


## Asks for confirmation and runs [param action] if confirmed
func confirm(title: String, text: String, action: Callable, ok_text := "OK") -> void:
	confirm_dialog.title = title
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	_confirm_action = action
	_popup(confirm_dialog)


func _popup(dialog: AcceptDialog) -> void:
	dialog.reset_size()
	dialog.popup_centered()
