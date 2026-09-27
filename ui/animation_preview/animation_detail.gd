class_name AnimationDetail
extends ScrollContainer
## Where the animation chosen in the animation panel is edited: its name, which frames
## (sprite numbers, names and ranges such as "0-3, 5, idle", or put together in
## [AnimationFramesEditor]), how fast and how it repeats. It's also mirrored or deleted
## here. Every change can be undone.

## A mirrored copy was added at [param index]
signal animation_added(index: int)

const REMOVE_ICON := preload("res://assets/icons/Remove.svg")
const MIRROR_ICON := preload("res://assets/icons/MirrorX.svg")
const MODE_ICONS := {
	SheetAnimation.Mode.ONCE: preload("res://assets/icons/PlayStart.svg"),
	SheetAnimation.Mode.LOOP: preload("res://assets/icons/Loop.svg"),
	SheetAnimation.Mode.PING_PONG: preload("res://assets/icons/PingPongLoop.svg"),
}
## Order of the types in the menu
const MODES: Array[SheetAnimation.Mode] = [
	SheetAnimation.Mode.ONCE, SheetAnimation.Mode.LOOP, SheetAnimation.Mode.PING_PONG
]

var delete_button := Button.new()
var mirror_button := Button.new()
var name_edit := LineEdit.new()
var frames_edit := LineEdit.new()
## Opens [member frames_editor] to put the frames together by dragging them
var edit_frames_button := Button.new()
var frames_editor := AnimationFramesEditor.new()
var frames_info := Label.new()
var fps_spin := SpinBox.new()
var mode_option := OptionButton.new()
## Says what to do while no animation is chosen
var empty_hint := Label.new()

## The animation edited, or -1
var _index := -1
var _properties := GridContainer.new()
var _updating := false
## The name and frames last shown, to tell them from what's typed
var _shown_name := ""
var _shown_frames := ""


func _init() -> void:
	# Never so wide that the panel makes the sidebars narrower: it scrolls instead
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_hint.theme_type_variation = &"StatusLabel"
	box.add_child(empty_hint)

	_properties.columns = 2
	_properties.add_theme_constant_override("h_separation", 12)
	_properties.add_theme_constant_override("v_separation", 6)
	box.add_child(_properties)
	name_edit.placeholder_text = "walk"
	var name_row := HBoxContainer.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	mirror_button.icon = MIRROR_ICON
	mirror_button.tooltip_text = "Mirrored copy: the frames flipped into a new row"
	name_row.add_child(mirror_button)
	delete_button.icon = REMOVE_ICON
	delete_button.tooltip_text = "Delete the animation"
	name_row.add_child(delete_button)
	_add_property("Name", name_row)

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
	LabelLink.link(type_label, mode_option)
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
	frames_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frames_info.custom_minimum_size.x = 120
	_add_property("", frames_info)

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
	mode_option.item_selected.connect(func(_item: int) -> void: _apply())


func _ready() -> void:
	fps_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	SpinScroll.enable(fps_spin)
	show_animation(_index)


## Shows the animation at [param index] to edit, or a hint with -1
func show_animation(index: int) -> void:
	_index = index if index < Global.spritesheet.animations.size() else -1
	refresh()


## Index of the animation edited, or -1
func get_animation_index() -> int:
	return _index


## Starts editing the name
func focus_name() -> void:
	if _index >= 0:
		name_edit.grab_focus()
		name_edit.select_all()


## Shows the animation's current name, frames, speed and type
func refresh() -> void:
	var sheet := Global.spritesheet
	if _index >= sheet.animations.size():
		_index = -1
	var has_animation := _index >= 0
	_properties.visible = has_animation
	empty_hint.visible = not has_animation
	if not has_animation:
		empty_hint.text = (
			tr("Choose an animation to edit it.")
			if sheet.animations
			else tr("No animations yet.\nSelect frames in the sheet and press New.")
		)
		return
	var animation := sheet.animations[_index]
	_updating = true
	# What's being typed stays, but what was shown follows, e.g. when undoing
	if not name_edit.has_focus() or name_edit.text == _shown_name:
		name_edit.text = animation.name
	_shown_name = animation.name
	var frames_text := _format_cells(animation.cells, animation.durations)
	if not frames_edit.has_focus() or frames_edit.text == _shown_frames:
		frames_edit.text = frames_text
	_shown_frames = frames_text
	_show_frames_info(animation, sheet)
	fps_spin.set_value_no_signal(animation.fps)
	mode_option.select(mode_option.get_item_index(animation.mode))
	_updating = false


## Adds a mirrored copy of the animation
func mirror_animation() -> void:
	if _index < 0:
		return
	var added: int = Global.document.perform(
		"Mirror animation", SheetAnimation.mirror.bind(Global.spritesheet, _index)
	)
	if added >= 0:
		animation_added.emit(added)


## Opens the animation's frames in [member frames_editor]
func edit_frames() -> void:
	if _index < 0:
		return
	var animation := Global.spritesheet.animations[_index]
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
	if _index >= 0:
		Global.document.perform(
			"Delete animation", Global.spritesheet.remove_animation.bind(_index)
		)


func _apply() -> void:
	if _updating or _index < 0 or _index >= Global.spritesheet.animations.size():
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
	if _updating or _index < 0 or _index >= Global.spritesheet.animations.size():
		return
	var parsed := SheetAnimation.parse_numbers(frames_edit.text, _frame_names())
	if parsed.has("error"):
		frames_info.text = (
			tr('Can\'t read "%s". Use numbers, names and ranges like 0-3, 5*2') % parsed.error
		)
		frames_info.theme_type_variation = &"ErrorLabel"
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
	refresh()


func _show_frames_info(animation: SheetAnimation, sheet: Spritesheet) -> void:
	var with_frames := animation.get_frame_cells(sheet).size()
	var total := animation.cells.size()
	frames_info.theme_type_variation = &"StatusLabel"
	frames_info.text = tr("%d frames") % with_frames
	if with_frames > 0:
		frames_info.text += tr(", %.2f s") % animation.get_length(sheet)
	# Numbers past the end of the sheet aren't empty cells of it
	var outside := animation.cells.filter(
		func(cell: Vector2i) -> bool: return not sheet.is_inside(cell)
	)
	var skipped := PackedStringArray()
	if total - outside.size() > with_frames:
		skipped.append(tr("%d empty cells are skipped") % (total - outside.size() - with_frames))
	if outside:
		skipped.append(tr("%d are outside the sheet") % outside.size())
	if skipped:
		frames_info.text += " (%s)" % ", ".join(skipped)


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


## Changes the animation with [param change] as one undoable step
func _edit(change: Callable) -> void:
	var sheet := Global.spritesheet
	var animation := sheet.animations[_index]
	change.call(animation)
	Global.document.perform("Edit animation", sheet.set_animation.bind(_index, animation))


func _add_property(text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	_properties.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LabelLink.link(label, control)
	_properties.add_child(control)
