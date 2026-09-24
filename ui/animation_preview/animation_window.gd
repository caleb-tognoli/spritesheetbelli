class_name AnimationWindow
extends AcceptDialog
## A bigger preview where animations are made and edited: which frames (a range or the
## selected ones), how fast and how they repeat. Every change can be undone.

const ADD_ICON := preload("res://assets/icons/Add.svg")
const REMOVE_ICON := preload("res://assets/icons/Remove.svg")
const ANIMATION_ICON := preload("res://assets/icons/Animation.svg")
const MODE_ICONS := {
	SheetAnimation.Mode.ONCE: preload("res://assets/icons/PlayStart.svg"),
	SheetAnimation.Mode.LOOP: preload("res://assets/icons/Loop.svg"),
	SheetAnimation.Mode.PING_PONG: preload("res://assets/icons/PingPongLoop.svg"),
}
## Order of the types in the menu
const MODES: Array[SheetAnimation.Mode] = [
	SheetAnimation.Mode.ONCE, SheetAnimation.Mode.LOOP, SheetAnimation.Mode.PING_PONG
]

## Where selected frames come from
var preview: SpritesheetPreview
var list := ItemList.new()
var add_button := Button.new()
var remove_button := Button.new()
var player := FramePlayer.new()
var name_edit := LineEdit.new()
var from_spin := SpinBox.new()
var to_spin := SpinBox.new()
var use_selection_button := Button.new()
var frames_info := Label.new()
var fps_spin := SpinBox.new()
var mode_option := OptionButton.new()
var empty_hint := Label.new()

var _properties := GridContainer.new()
var _updating := false


func _init() -> void:
	title = "Animations"
	ok_button_text = "Close"
	min_size = Vector2i(720, 480)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	layout.add_child(left)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(16, 16)
	left.add_child(list)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	add_button.text = "New"
	add_button.icon = ADD_ICON
	add_button.tooltip_text = "A new animation of the selected frames, or of every frame"
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(add_button)
	remove_button.icon = REMOVE_ICON
	remove_button.tooltip_text = "Delete the animation"
	buttons.add_child(remove_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	layout.add_child(right)
	player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player.custom_minimum_size = Vector2(360, 260)
	right.add_child(player)
	empty_hint.text = "No animations yet.\nSelect frames in the sheet and press New."
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.theme_type_variation = &"StatusLabel"
	right.add_child(empty_hint)

	_properties.columns = 2
	_properties.add_theme_constant_override("h_separation", 16)
	_properties.add_theme_constant_override("v_separation", 8)
	right.add_child(_properties)
	name_edit.placeholder_text = "walk"
	_add_property("Name", name_edit)

	var range_box := HBoxContainer.new()
	for spin: SpinBox in [from_spin, to_spin]:
		spin.min_value = 0
		spin.allow_greater = true
		spin.tooltip_text = "Cell numbers as shown in the sheet"
	var from_label := Label.new()
	from_label.text = "From"
	range_box.add_child(from_label)
	range_box.add_child(from_spin)
	var to_label := Label.new()
	to_label.text = "to"
	range_box.add_child(to_label)
	range_box.add_child(to_spin)
	use_selection_button.text = "Use Selected"
	use_selection_button.tooltip_text = "Play the frames selected in the sheet, in order"
	range_box.add_child(use_selection_button)
	_add_property("Frames", range_box)
	frames_info.theme_type_variation = &"StatusLabel"
	_add_property("", frames_info)

	fps_spin.min_value = 0.5
	fps_spin.max_value = 120
	fps_spin.step = 0.5
	fps_spin.suffix = "fps"
	fps_spin.tooltip_text = "Frames per second"
	_add_property("Speed", fps_spin)
	for mode in MODES:
		mode_option.add_icon_item(MODE_ICONS[mode], SheetAnimation.MODE_NAMES[mode], mode)
	mode_option.tooltip_text = "Once plays to the end, Loop starts over, Ping-pong plays back"
	_add_property("Type", mode_option)

	list.item_selected.connect(func(_index: int) -> void: _show_selected())
	add_button.pressed.connect(add_animation)
	remove_button.pressed.connect(remove_animation)
	name_edit.text_submitted.connect(func(_text: String) -> void: _apply())
	name_edit.focus_exited.connect(_apply)
	from_spin.value_changed.connect(func(_value: float) -> void: _apply_range())
	to_spin.value_changed.connect(func(_value: float) -> void: _apply_range())
	use_selection_button.pressed.connect(use_selection)
	fps_spin.value_changed.connect(func(_value: float) -> void: _apply())
	mode_option.item_selected.connect(func(_index: int) -> void: _apply())


func _ready() -> void:
	player.sheet = Global.spritesheet
	Global.spritesheet.updated.connect(
		func() -> void:
			if visible:
				refresh()
	)
	for spin: SpinBox in [from_spin, to_spin, fps_spin]:
		spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		SpinScroll.enable(spin)


## Shows the window with the animation at [param index] selected (-1: the first)
func open(index := -1) -> void:
	refresh()
	if list.item_count > 0:
		list.select(clampi(index, 0, list.item_count - 1))
	_show_selected()
	popup_centered()


## Index of the selected animation, or -1
func get_selected() -> int:
	var selected := list.get_selected_items()
	return selected[0] if not selected.is_empty() else -1


## Rebuilds the list of animations, keeping the selection
func refresh() -> void:
	var selected := get_selected()
	list.clear()
	for animation in Global.spritesheet.animations:
		list.add_item(animation.name, ANIMATION_ICON)
	if list.item_count > 0:
		list.select(clampi(selected, 0, list.item_count - 1))
	_show_selected()


## A new animation of the selected frames, or of every frame, selected for editing
func add_animation() -> void:
	var sheet := Global.spritesheet
	var cells := _selected_cells()
	if cells.is_empty():
		cells = sheet.get_sorted_coords()
	var anim_name := sheet.get_unique_animation_name(_suggest_name(cells))
	var index: int = Global.document.perform(
		"New animation", sheet.add_animation.bind(SheetAnimation.create(anim_name, cells))
	)
	refresh()
	list.select(index)
	_show_selected()
	name_edit.grab_focus()
	name_edit.select_all()


func remove_animation() -> void:
	var index := get_selected()
	if index >= 0:
		Global.document.perform("Delete animation", Global.spritesheet.remove_animation.bind(index))


## Makes the selected animation play the frames selected in the sheet
func use_selection() -> void:
	var cells := _selected_cells()
	if cells.is_empty():
		Notify.message("Use Selected", "Select frames in the sheet first.")
		return
	_edit(func(animation: SheetAnimation) -> void: animation.cells = cells)


func _show_selected() -> void:
	var index := get_selected()
	var has_animation := index >= 0
	_properties.visible = has_animation
	player.visible = has_animation
	remove_button.disabled = not has_animation
	empty_hint.visible = not has_animation
	if not has_animation:
		return
	var sheet := Global.spritesheet
	var animation := sheet.animations[index]
	_updating = true
	if not name_edit.has_focus():
		name_edit.text = animation.name
	var start: int = Settings.get_value(&"index_start")
	var cells := animation.cells
	var first := sheet.index_of(cells[0]) if not cells.is_empty() else 0
	var last := sheet.index_of(cells[-1]) if not cells.is_empty() else 0
	for spin: SpinBox in [from_spin, to_spin]:
		spin.min_value = start
	from_spin.set_value_no_signal(first + start)
	to_spin.set_value_no_signal(last + start)
	var frame_count := animation.get_frame_cells(sheet).size()
	frames_info.text = tr("%d frames") % frame_count
	if not _is_range(cells):
		frames_info.text = tr("%d frames, picked one by one") % frame_count
	fps_spin.set_value_no_signal(animation.fps)
	mode_option.select(mode_option.get_item_index(animation.mode))
	_updating = false
	player.fps = animation.fps
	player.mode = animation.mode
	player.set_cells(animation.cells)


func _apply() -> void:
	if _updating or get_selected() < 0:
		return
	var new_name := name_edit.text.strip_edges()
	_edit(
		func(animation: SheetAnimation) -> void:
			if new_name:
				animation.name = new_name
			animation.fps = fps_spin.value
			animation.mode = mode_option.get_selected_id() as SheetAnimation.Mode
	)


## Plays every cell from the From number to the To number, backwards when To is smaller
func _apply_range() -> void:
	if _updating:
		return
	var sheet := Global.spritesheet
	var start: int = Settings.get_value(&"index_start")
	var first := int(from_spin.value) - start
	var last := int(to_spin.value) - start
	var cells: Array[Vector2i] = []
	var step := 1 if last >= first else -1
	for index in range(first, last + step, step):
		cells.append(sheet.coord_of(index))
	_edit(func(animation: SheetAnimation) -> void: animation.cells = cells)


## Changes the selected animation with [param change] as one undoable step
func _edit(change: Callable) -> void:
	var index := get_selected()
	if index < 0:
		return
	var sheet := Global.spritesheet
	var animation := sheet.animations[index]
	change.call(animation)
	Global.document.perform("Edit animation", sheet.set_animation.bind(index, animation))


func _selected_cells() -> Array[Vector2i]:
	return preview.get_selected_coords() if preview else ([] as Array[Vector2i])


## A row's name when all the cells are in one named row
func _suggest_name(cells: Array[Vector2i]) -> String:
	var sheet := Global.spritesheet
	if not cells.is_empty() and cells.all(func(c: Vector2i) -> bool: return c.y == cells[0].y):
		return sheet.row_names.get(cells[0].y, "animation")
	return "animation"


## Whether [param cells] are consecutive cells in reading order
func _is_range(cells: Array[Vector2i]) -> bool:
	var sheet := Global.spritesheet
	if cells.size() < 2:
		return true
	var step := sheet.index_of(cells[1]) - sheet.index_of(cells[0])
	if absi(step) != 1:
		return false
	for i in range(2, cells.size()):
		if sheet.index_of(cells[i]) - sheet.index_of(cells[i - 1]) != step:
			return false
	return true


func _add_property(text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	_properties.add_child(label)
	_properties.add_child(control)
