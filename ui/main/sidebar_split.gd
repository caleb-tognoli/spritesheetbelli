class_name SidebarSplit
extends RefCounted
## A sidebar next to the preview, as wide as it was last dragged by the handle on its
## inner edge: its width is remembered in a setting. Double-clicking the handle makes it
## as narrow as it can be again.

## The split container the sidebar is in, as its first or last part
var split: SplitContainer
var sidebar: Control
## The setting that remembers the width, in interface units: 0 for as narrow as it can be
var setting: StringName


func _init(split_container: SplitContainer, side: Control, width_setting: StringName) -> void:
	split = split_container
	sidebar = side
	setting = width_setting
	apply_width()
	split.drag_ended.connect(_on_drag_ended)
	split.get_drag_area_control().gui_input.connect(_on_handle_input)


## Gives the sidebar its remembered width, or as much of it as there's room for
func apply_width() -> void:
	split.split_offset = get_offset(Settings.get_value(setting), _is_first())


## The split offset for a sidebar [param width] wide: the width of the first part, or
## the width of the last part as a negative number. 0 is as narrow as it can be.
static func get_offset(width: int, sidebar_first: bool) -> int:
	return width if sidebar_first else -width


## The width to remember for a sidebar [param width] wide that can't be narrower than
## [param min_width]: 0 when it's as narrow as it can be, so it stays so when its
## content needs more or less room
static func get_remembered_width(width: float, min_width: float) -> int:
	return 0 if width <= min_width + 0.5 else roundi(width)


func reset_width() -> void:
	Settings.set_value(setting, 0)
	apply_width()


func _is_first() -> bool:
	return sidebar.get_index() == 0


func _on_drag_ended() -> void:
	var width := get_remembered_width(sidebar.size.x, sidebar.get_combined_minimum_size().x)
	Settings.set_value(setting, width)
	apply_width()


func _on_handle_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
		# Not the start of a drag
		split.get_drag_area_control().accept_event()
		reset_width()
