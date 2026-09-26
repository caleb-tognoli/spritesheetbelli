class_name AnimationWindow
extends AcceptDialog
## A bigger preview where animations are made and edited: which frames (sprite numbers,
## names and ranges such as "0-3, 5, idle", or put together in [AnimationFramesEditor]),
## how fast and how they repeat. Every change can be undone.

const ADD_ICON := preload("res://assets/icons/Add.svg")
const REMOVE_ICON := preload("res://assets/icons/Remove.svg")
const MIRROR_ICON := preload("res://assets/icons/MirrorX.svg")
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
var new_button := Button.new()
var delete_button := Button.new()
var mirror_button := Button.new()
var player := FramePlayer.new()
var name_edit := LineEdit.new()
var frames_edit := LineEdit.new()
## Opens [member frames_editor] to put the frames together by dragging them
var edit_frames_button := Button.new()
var frames_editor := AnimationFramesEditor.new()
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
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	new_button.text = "New"
	new_button.icon = ADD_ICON
	new_button.tooltip_text = "A new animation of the selected frames, or of every frame"
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(new_button)
	mirror_button.icon = MIRROR_ICON
	mirror_button.tooltip_text = "Mirrored copy: the frames flipped into a new row"
	buttons.add_child(mirror_button)
	delete_button.icon = REMOVE_ICON
	delete_button.tooltip_text = "Delete the animation"
	buttons.add_child(delete_button)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(16, 16)
	left.add_child(list)

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

	# Speed and type share a row
	var timing := HBoxContainer.new()
	timing.add_theme_constant_override("separation", 12)
	fps_spin.min_value = 0.5
	fps_spin.max_value = 120
	fps_spin.step = 0.5
	fps_spin.suffix = "fps"
	fps_spin.tooltip_text = "Frames per second"
	fps_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timing.add_child(fps_spin)
	var type_label := Label.new()
	type_label.text = "Type"
	timing.add_child(type_label)
	for each_mode in MODES:
		mode_option.add_icon_item(
			MODE_ICONS[each_mode], SheetAnimation.MODE_NAMES[each_mode], each_mode
		)
	mode_option.tooltip_text = "Once plays to the end, Loop starts over, Ping-pong plays back"
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timing.add_child(mode_option)
	_add_property("Speed", timing)

	frames_edit.placeholder_text = "0-7"
	frames_edit.tooltip_text = (
		"Sprite numbers as shown in the sheet, or sprite names, in playing order. Ranges "
		+ "like 0-7 count up, 7-0 counts down. Separate them with commas: 0-3, 5, 8, idle\n"
		+ 'Names with spaces go in quotes: "jump up", walk_0-walk_3\n'
		+ "Add *2 to show a frame twice as long: 0-3, 4*2, 5*0.5"
	)
	edit_frames_button.text = "Edit…"
	edit_frames_button.tooltip_text = "Drag sprites into place and set how long each is shown"
	var frames_row := HBoxContainer.new()
	frames_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_row.add_child(frames_edit)
	frames_row.add_child(edit_frames_button)
	_add_property("Frames", frames_row)
	frames_info.theme_type_variation = &"StatusLabel"
	_add_property("", frames_info)

	list.item_selected.connect(func(_index: int) -> void: _show_selected())
	new_button.pressed.connect(add_animation)
	delete_button.pressed.connect(remove_animation)
	mirror_button.pressed.connect(mirror_animation)
	name_edit.text_submitted.connect(func(_text: String) -> void: _apply())
	name_edit.focus_exited.connect(_apply)
	frames_edit.text_submitted.connect(func(_text: String) -> void: _apply_frames())
	frames_edit.focus_exited.connect(_apply_frames)
	edit_frames_button.pressed.connect(edit_frames)
	frames_editor.frames_chosen.connect(
		func(text: String) -> void:
			frames_edit.text = text
			_apply_frames()
	)
	add_child(frames_editor)
	fps_spin.value_changed.connect(func(_value: float) -> void: _apply())
	mode_option.item_selected.connect(func(_index: int) -> void: _apply())


func _ready() -> void:
	player.sheet = Global.spritesheet
	Global.spritesheet.updated.connect(
		func() -> void:
			if visible:
				refresh()
	)
	fps_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	SpinScroll.enable(fps_spin)


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


## Adds a mirrored copy of the selected animation and selects it
func mirror_animation() -> void:
	var index := get_selected()
	if index < 0:
		return
	var added: int = Global.document.perform(
		"Mirror animation", SheetAnimation.mirror.bind(Global.spritesheet, index)
	)
	refresh()
	if added >= 0:
		list.select(added)
		_show_selected()


## Opens the selected animation's frames in [member frames_editor]
func edit_frames() -> void:
	var index := get_selected()
	if index < 0:
		return
	var animation := Global.spritesheet.animations[index]
	var durations: Array[float] = []
	for i in animation.cells.size():
		durations.append(animation.get_duration(i))
	frames_editor.open(
		Global.spritesheet,
		animation.cells,
		durations,
		animation.fps,
		animation.mode,
		_labels(),
		animation.name
	)


func remove_animation() -> void:
	var index := get_selected()
	if index >= 0:
		Global.document.perform("Delete animation", Global.spritesheet.remove_animation.bind(index))


func _show_selected() -> void:
	var index := get_selected()
	var has_animation := index >= 0
	_properties.visible = has_animation
	player.visible = has_animation
	delete_button.disabled = not has_animation
	mirror_button.disabled = not has_animation
	empty_hint.visible = not has_animation
	if not has_animation:
		return
	var sheet := Global.spritesheet
	var animation := sheet.animations[index]
	_updating = true
	if not name_edit.has_focus():
		name_edit.text = animation.name
	if not frames_edit.has_focus():
		frames_edit.text = _format_cells(animation.cells, animation.durations)
	_show_frames_info(animation, sheet)
	fps_spin.set_value_no_signal(animation.fps)
	mode_option.select(mode_option.get_item_index(animation.mode))
	_updating = false
	player.fps = animation.fps
	player.mode = animation.mode
	player.set_cells(animation.cells, animation.durations)


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


## Plays the sprites whose numbers are typed in the frames field
func _apply_frames() -> void:
	if _updating or get_selected() < 0:
		return
	var parsed := SheetAnimation.parse_numbers(frames_edit.text, _frame_names())
	if parsed.has("error"):
		frames_info.text = (
			tr('Can\'t read "%s". Use numbers, names and ranges like 0-3, 5*2') % parsed.error
		)
		frames_info.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		return
	var sheet := Global.spritesheet
	var start: int = Settings.get_value(&"index_start")
	var cells: Array[Vector2i] = []
	var durations: Array[float] = []
	for i: int in parsed.numbers.size():
		var number: int = parsed.numbers[i]
		if number >= start:
			cells.append(sheet.coord_of(number - start))
			durations.append(parsed.durations[i])
	var timed := durations.any(func(duration: float) -> bool: return duration != 1.0)
	if not timed:
		durations.clear()
	_edit(
		func(animation: SheetAnimation) -> void:
			animation.cells = cells
			animation.durations = durations
	)
	_show_selected()


func _show_frames_info(animation: SheetAnimation, sheet: Spritesheet) -> void:
	var with_frames := animation.get_frame_cells(sheet).size()
	var total := animation.cells.size()
	frames_info.remove_theme_color_override("font_color")
	frames_info.text = tr("%d frames") % with_frames
	if with_frames > 0:
		frames_info.text += tr(", %.2f s") % animation.get_length(sheet)
	if total > with_frames:
		frames_info.text += tr(" (%d empty cells are skipped)") % (total - with_frames)


## The numbers of [param cells] as typed in the frames field
func _format_cells(cells: Array[Vector2i], durations: Array[float] = []) -> String:
	var start: int = Settings.get_value(&"index_start")
	var numbers: Array[int] = []
	for cell in cells:
		numbers.append(Global.spritesheet.index_of(cell) + start)
	return SheetAnimation.format_numbers(numbers, durations, _labels())


## Names that frames are shown by, by number. Only names that are unique, so they read
## back as the same frame.
func _labels() -> Dictionary:
	var labels := {}
	var names := _frame_names()
	for frame_name: String in names:
		labels[names[frame_name]] = frame_name
	return labels


## The number of every frame with a name of its own, by that name. Frames that share a
## name are left out, since the name can't tell them apart.
func _frame_names() -> Dictionary:
	var sheet := Global.spritesheet
	var start: int = Settings.get_value(&"index_start")
	var names := {}
	var shared := {}
	for coord in sheet.get_sorted_coords():
		var frame_name := sheet.frames[coord].resource_name.get_basename()
		if frame_name.is_empty():
			continue
		if names.has(frame_name):
			shared[frame_name] = true
		names[frame_name] = sheet.index_of(coord) + start
	for frame_name: String in shared:
		names.erase(frame_name)
	return names


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


func _add_property(text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	_properties.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LabelLink.link(label, control)
	_properties.add_child(control)
