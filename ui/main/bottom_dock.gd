class_name BottomDock
extends VBoxContainer
## The docks under the sheet's preview, like the Godot editor's bottom panel: a row of
## buttons along the bottom, one for each dock. Pressing one shows its dock above the row,
## in place of the one shown, and pressing it again hides it, leaving only the row.
## The handle on the top edge of a shown dock makes it taller, up to half the window. Every
## dock is as tall, remembered in the bottom_dock_height setting.

## Another dock was shown, or the one shown was hidden
signal dock_changed

## The shortest a shown dock gets, with the row of buttons
const MIN_HEIGHT := 160

## The row of buttons, under the dock shown
var bar := HBoxContainer.new()

## The button of each dock
var _buttons: Dictionary[Control, Button] = {}
var _shown: Control
## The split between the sheet's preview and the docks
var _split: SplitContainer


func _init() -> void:
	add_theme_constant_override("separation", 0)
	var bar_panel := PanelContainer.new()
	bar_panel.theme_type_variation = &"SidebarPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_child(bar)
	bar_panel.add_child(margin)
	# Always last, under the docks
	add_child(bar_panel, false, Node.INTERNAL_MODE_BACK)


func _ready() -> void:
	_split = get_parent() as SplitContainer
	if not _split:
		return
	_split.drag_ended.connect(_on_height_dragged)
	_split.dragged.connect(func(_offset: int) -> void: _clamp_height())
	_split.get_drag_area_control().gui_input.connect(_on_handle_input)
	get_viewport().size_changed.connect(apply_height)
	apply_height()


## Adds [param dock], hidden, with a button called [param title] that shows it. Returns
## the button.
func add_dock(dock: Control, title: String) -> Button:
	if dock.get_parent() != self:
		add_child(dock)
	dock.visible = false
	dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.theme_type_variation = &"ToolbarButton"
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(
		func(on: bool) -> void:
			if on:
				show_dock(dock)
			elif _shown == dock:
				show_dock(null)
	)
	bar.add_child(button)
	_buttons[dock] = button
	return button


## Shows [param dock] and hides the others, or hides them all with null
func show_dock(dock: Control) -> void:
	if dock == _shown:
		return
	_shown = dock
	for each: Control in _buttons:
		each.visible = each == dock
		_buttons[each].set_pressed_no_signal(each == dock)
	apply_height()
	dock_changed.emit()


## The dock shown, or null
func get_shown() -> Control:
	return _shown


func get_button(dock: Control) -> Button:
	return _buttons.get(dock)


## The height a shown dock gets: the remembered one, within its limits
func get_height() -> int:
	return clampi(Settings.get_value(&"bottom_dock_height"), MIN_HEIGHT, get_max_height())


## Half the window, but never below the smallest height
func get_max_height() -> int:
	return maxi(MIN_HEIGHT, int(get_viewport_rect().size.y / 2))


## Gives the shown dock its remembered height, or only the row of buttons without one
func apply_height() -> void:
	if not _split:
		return
	var open := _shown != null
	custom_minimum_size.y = MIN_HEIGHT if open else 0
	_split.collapsed = not open
	_split.dragging_enabled = open
	_split.split_offset = -get_height() if open else 0


## Keeps the height dragged within its limits
func _clamp_height() -> void:
	if -_split.split_offset > get_max_height():
		_split.split_offset = -get_max_height()


func _on_height_dragged() -> void:
	var height := clampi(-_split.split_offset, MIN_HEIGHT, get_max_height())
	Settings.set_value(&"bottom_dock_height", height)
	apply_height()


func _on_handle_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		# Not the start of a drag: back to the first height
		_split.get_drag_area_control().accept_event()
		Settings.set_value(&"bottom_dock_height", Settings.DEFAULTS[&"bottom_dock_height"])
		apply_height()
