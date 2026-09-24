extends Node
## Message and confirmation dialogs usable from anywhere.

var message_dialog := AcceptDialog.new()
var confirm_dialog := ConfirmationDialog.new()
var _confirm_action: Callable
var _toasts := VBoxContainer.new()
var _progress_overlay := ColorRect.new()
var _progress_label := Label.new()
var _progress_bar := ProgressBar.new()
var _progress_started := 0


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
	_build_progress_overlay(layer)


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


## Shows a progress bar over the window, which also blocks clicks. Nothing appears for
## the first quarter second, so quick tasks don't flash it.
func progress(text: String, done: int, total: int) -> void:
	var now := Time.get_ticks_msec()
	if _progress_started == 0:
		_progress_started = now
	if now - _progress_started < 250 and not _progress_overlay.visible:
		return
	_progress_overlay.visible = true
	_progress_label.text = "%s %d of %d" % [text, done, total]
	_progress_bar.max_value = maxi(total, 1)
	_progress_bar.value = done


func hide_progress() -> void:
	_progress_started = 0
	_progress_overlay.visible = false


func is_progress_visible() -> bool:
	return _progress_overlay.visible


func _build_progress_overlay(layer: CanvasLayer) -> void:
	_progress_overlay.color = Color(0, 0, 0, 0.35)
	_progress_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_progress_overlay.visible = false
	layer.add_child(_progress_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)
	box.add_child(_progress_label)
	_progress_bar.show_percentage = false
	box.add_child(_progress_bar)


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
