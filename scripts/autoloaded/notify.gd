extends Node
## Message and confirmation dialogs usable from anywhere. Their text is shown as given, so
## translate it first.

const ERROR_ICON := preload("res://assets/icons/StatusWarning.svg")

var message_dialog := AcceptDialog.new()
## The text of [member message_dialog], below [member message_icon]
var message_label := Label.new()
## Shown above errors
var message_icon := TextureRect.new()
var confirm_dialog := ConfirmationDialog.new()
var _confirm_action: Callable
var _toasts := VBoxContainer.new()
## Holds the overlay, over the window on top, see [method _show_overlay]. It's made again
## when it was freed with that window.
var _progress_layer: OverlayLayer
var _progress_overlay: ColorRect
var _progress_label: Label
var _progress_bar: ProgressBar
var _progress_started := 0
## Counts busy runs and hidings, so a run that ended doesn't show the overlay later
var _busy_runs := 0


func _ready() -> void:
	for dialog: AcceptDialog in [message_dialog, confirm_dialog]:
		dialog.dialog_autowrap = true
		dialog.min_size = Vector2i(400, 0)
		DialogButtons.apply(dialog, true)
		add_child(dialog)
		_return_when_hidden(dialog)
	_build_message(message_dialog)
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
	_build_progress_overlay()


func message(title: String, text: String) -> void:
	_show_message(title, text, false)


func error(text: String) -> void:
	_show_message(tr("Error"), text, true)


func _show_message(title: String, text: String, is_error: bool) -> void:
	message_dialog.title = title
	message_label.text = text
	message_icon.visible = is_error
	_popup(message_dialog)


## The message's own label rather than the dialog's, for an icon to go above it
func _build_message(dialog: AcceptDialog) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	dialog.add_child(box)
	message_icon.texture = ERROR_ICON
	message_icon.custom_minimum_size = Vector2(32, 32)
	message_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	message_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(message_icon)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.custom_minimum_size = Vector2(360, 0)
	box.add_child(message_label)


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
	if now - _progress_started < 250 and not is_progress_visible():
		return
	_show_overlay()
	_progress_overlay.modulate.a = 1.0
	_progress_bar.indeterminate = false
	_progress_label.text = tr("%s %d of %d") % [text, done, total]
	_progress_bar.max_value = maxi(total, 1)
	_progress_bar.value = done


## Runs [param work] and returns its result, awaiting it when it's a coroutine. The
## overlay blocks clicks and keys while it runs, and shows once the work has taken a quarter
## second, like [method progress]. What takes long in the work is to be done on worker
## threads (see [Parallel]), as the bar only moves while the window can draw. Within other
## work, the overlay that one shows says [param text] until this is done.
func run_busy(text: String, work: Callable) -> Variant:
	if is_progress_visible():
		var outer := _progress_label.text
		_progress_label.text = text + "…"
		var inner_result: Variant = await work.call()
		if is_progress_visible():
			_progress_label.text = outer
		return inner_result
	_busy_runs += 1
	var run := _busy_runs
	_show_overlay()
	_progress_label.text = text + "…"
	# How long it takes is unknown
	_progress_bar.indeterminate = true
	_progress_overlay.modulate.a = 0.0
	get_tree().create_timer(0.25).timeout.connect(
		func() -> void:
			if run == _busy_runs and is_progress_visible():
				_progress_overlay.modulate.a = 1.0
	)
	var result: Variant = await work.call()
	hide_progress()
	return result


func hide_progress() -> void:
	_busy_runs += 1
	_progress_started = 0
	if not is_instance_valid(_progress_layer):
		return
	_progress_overlay.visible = false
	_progress_overlay.modulate.a = 1.0
	# Back here, so it isn't freed with the window it was shown over
	if _progress_layer.get_parent() != self:
		_progress_layer.reparent(self, false)


func is_progress_visible() -> bool:
	return is_instance_valid(_progress_overlay) and _progress_overlay.visible


## Shows the overlay over the window on top, e.g. Add Spritesheet: windows aren't embedded
## in the main one, so it would be hidden behind them there
func _show_overlay() -> void:
	if not is_instance_valid(_progress_layer):
		_build_progress_overlay()
	var host := _top_window(null)
	if _progress_layer.get_parent() != host:
		_progress_layer.reparent(host, false)
	_progress_overlay.visible = true


func _build_progress_overlay() -> void:
	_progress_layer = OverlayLayer.new()
	_progress_overlay = ColorRect.new()
	_progress_label = Label.new()
	_progress_bar = ProgressBar.new()
	# Above the toasts
	_progress_layer.layer = 101
	_progress_layer.overlay = _progress_overlay
	add_child(_progress_layer)
	_progress_overlay.color = Color(0, 0, 0, 0.35)
	_progress_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_progress_overlay.visible = false
	_progress_layer.add_child(_progress_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BusyPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)
	box.add_child(_progress_label)
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 6
	box.add_child(_progress_bar)


## Messages shown right now, newest last
func get_toasts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for panel in _toasts.get_children():
		if not panel.is_queued_for_deletion():
			texts.append((panel.get_child(0) as Label).text)
	return texts


## Asks for confirmation and runs [param action] if confirmed, with [param ok_text] and
## [param ok_icon] on the button that confirms
func confirm(
	title: String, text: String, action: Callable, ok_text := "OK", ok_icon: Texture2D = null
) -> void:
	confirm_dialog.title = title
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	confirm_dialog.get_ok_button().icon = ok_icon
	_confirm_action = action
	_popup(confirm_dialog)


## Shows [param dialog] over whatever is open. A modal window can only be opened from the
## window on top, so the dialog moves there while it's shown, e.g. over Settings.
func _popup(dialog: AcceptDialog) -> void:
	var host := _top_window(dialog)
	if dialog.get_parent() != host:
		dialog.reparent(host, false)
	dialog.reset_size()
	dialog.popup_centered()


## The innermost visible modal window, or the main window when none is open
func _top_window(except: Window) -> Window:
	var top: Window = get_tree().root
	var depth := -1
	for node in get_tree().root.find_children("*", "Window", true, false):
		var window := node as Window
		if window == except or not window.visible or not window.exclusive:
			continue
		var window_depth := window.get_path().get_name_count()
		if window_depth > depth:
			top = window
			depth = window_depth
	return top


## Brings a dialog back once closed, so it isn't freed with the window it was shown over
func _return_when_hidden(dialog: AcceptDialog) -> void:
	dialog.visibility_changed.connect(
		func() -> void:
			if not dialog.visible and dialog.get_parent() != self:
				dialog.reparent.call_deferred(self, false)
	)


## The layer of the progress overlay, which blocks keys in the window it's in as the overlay
## blocks clicks: shortcuts would change what's being worked on
class OverlayLayer:
	extends CanvasLayer

	var overlay: Control

	func _input(event: InputEvent) -> void:
		if overlay.visible and event is InputEventKey:
			get_viewport().set_input_as_handled()
