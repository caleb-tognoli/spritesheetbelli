class_name AnimationDetail
extends ScrollContainer
## Where the animation chosen in the animation panel is edited: its name, speed, type and
## colour on one line, and its frames below on an [AnimationTimeline], where they're
## dragged into place, taken out and timed. Frames of the sheet are added by dragging them
## there, from the sheet or the Sprites panel. Frames as text shows them typed instead:
## sprite numbers, names and ranges such as "0-3, 5, idle". Every change can be undone.

const TEXT_ICON := preload("res://assets/icons/FrameNumbers.svg")
const MODE_ICONS := {
	SheetAnimation.Mode.ONCE: preload("res://assets/icons/PlayStart.svg"),
	SheetAnimation.Mode.LOOP: preload("res://assets/icons/Loop.svg"),
	SheetAnimation.Mode.PING_PONG: preload("res://assets/icons/PingPongLoop.svg"),
}
## Order of the types in the menu
const MODES: Array[SheetAnimation.Mode] = [
	SheetAnimation.Mode.ONCE, SheetAnimation.Mode.LOOP, SheetAnimation.Mode.PING_PONG
]
const SEPARATION := 6

var name_edit := LineEdit.new()
var fps_spin := SpinBox.new()
var mode_option := OptionButton.new()
## Its colour, changed as one step when the picker closes
var color_button := ColorPickerButton.new()
var timeline := AnimationTimeline.new()
## Shows or hides the frames as text, remembered in the animation_frames_text setting
var frames_text_button := Button.new()
var frames_edit := LineEdit.new()
var frames_info := Label.new()
## Says what to do while no animation is chosen
var empty_hint := Label.new()

## The animation edited, or -1
var _index := -1
var _margin := MarginContainer.new()
var _content := VBoxContainer.new()
var _fields := HBoxContainer.new()
## The frames as text, and what they come to
var _frames_text := HBoxContainer.new()
var _updating := false
## The name and frames last shown, to tell them from what's typed
var _shown_name := ""
var _shown_frames := ""


func _init() -> void:
	# Never so wide that the panel makes the sidebars narrower: it scrolls instead
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 8)
	_margin.add_theme_constant_override("margin_bottom", 6)
	add_child(_margin)
	var box := VBoxContainer.new()
	_margin.add_child(box)

	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_hint.theme_type_variation = &"StatusLabel"
	box.add_child(empty_hint)

	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", SEPARATION)
	box.add_child(_content)
	_build_fields()
	_content.add_child(_fields)

	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(timeline)

	frames_edit.placeholder_text = "0-7"
	frames_edit.tooltip_text = (
		"Sprite numbers as shown in the sheet, or sprite names, in playing order. Ranges "
		+ "like 0-7 count up, 7-0 counts down. Separate them with commas: 0-3, 5, 8, idle\n"
		+ 'Names with spaces go in quotes: "jump up", walk_0-walk_3\n'
		+ "Add *2 to show a frame twice as long: 0-3, 4*2, 5*0.5"
	)
	frames_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_edit.size_flags_stretch_ratio = 2
	_frames_text.add_theme_constant_override("separation", 12)
	_frames_text.add_child(frames_edit)
	frames_info.theme_type_variation = &"StatusLabel"
	frames_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frames_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_info.custom_minimum_size.x = 120
	_frames_text.add_child(frames_info)
	_content.add_child(_frames_text)

	frames_text_button.toggled.connect(show_frames_text)
	name_edit.text_submitted.connect(func(_text: String) -> void: _apply())
	name_edit.focus_exited.connect(_apply)
	frames_edit.text_submitted.connect(func(_text: String) -> void: _apply_frames())
	frames_edit.focus_exited.connect(_apply_frames)
	fps_spin.value_changed.connect(func(_value: float) -> void: _apply())
	mode_option.item_selected.connect(func(_item: int) -> void: _apply())
	color_button.popup_closed.connect(_apply_color)
	timeline.frames_edited.connect(_on_frames_edited)
	resized.connect(_fit_timeline)
	_fields.resized.connect(_fit_timeline)


func _ready() -> void:
	fps_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	SpinScroll.enable(fps_spin)
	# Frame numbers start from the index_start setting
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"index_start":
				refresh()
	)
	frames_text_button.set_pressed_no_signal(Settings.get_value(&"animation_frames_text"))
	_frames_text.visible = frames_text_button.button_pressed
	show_animation(_index)


## Shows the animation at [param index] to edit, or a hint with -1
func show_animation(index: int) -> void:
	index = index if index < Global.spritesheet.animations.size() else -1
	if index != _index:
		timeline.select([])
	_index = index
	refresh()


## Index of the animation edited, or -1
func get_animation_index() -> int:
	return _index


## Starts editing the name
func focus_name() -> void:
	if _index >= 0:
		name_edit.grab_focus()
		name_edit.select_all()


## Shows the frames as text under the timeline, or hides them, and remembers it
func show_frames_text(shown: bool) -> void:
	frames_text_button.set_pressed_no_signal(shown)
	_frames_text.visible = shown
	if Settings.get_value(&"animation_frames_text") != shown:
		Settings.set_value(&"animation_frames_text", shown)
	_fit_timeline()


## Shows the animation's current name, frames, speed and type
func refresh() -> void:
	var sheet := Global.spritesheet
	if _index >= sheet.animations.size():
		_index = -1
	var has_animation := _index >= 0
	_content.visible = has_animation
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
	if not color_button.get_popup().visible:
		color_button.color = animation.color
	timeline.show_frames(sheet, animation.cells, animation.durations)
	_updating = false


## The name, speed, type and colour on one line, then the frames as text button
func _build_fields() -> void:
	_fields.add_theme_constant_override("separation", SEPARATION)
	name_edit.placeholder_text = "walk"
	name_edit.tooltip_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.x = 80
	_fields.add_child(name_edit)
	fps_spin.min_value = 0.5
	fps_spin.max_value = 120
	fps_spin.step = 0.5
	fps_spin.suffix = "fps"
	fps_spin.tooltip_text = "Speed, in frames per second"
	_fields.add_child(fps_spin)
	for each_mode in MODES:
		mode_option.add_icon_item(
			MODE_ICONS[each_mode], SheetAnimation.MODE_NAMES[each_mode], each_mode
		)
	mode_option.tooltip_text = "Once plays to the end, Loop starts over, Ping-pong plays back"
	_fields.add_child(mode_option)
	color_button.edit_alpha = false
	color_button.get_picker().presets_visible = false
	color_button.custom_minimum_size.x = 40
	color_button.tooltip_text = "Colour: of its label on the grid, and in the list"
	_fields.add_child(color_button)
	frames_text_button.icon = TEXT_ICON
	frames_text_button.toggle_mode = true
	frames_text_button.tooltip_text = "Frames as text: numbers, names and ranges like 0-3, 5*2"
	frames_text_button.theme_type_variation = &"ToolbarButton"
	frames_text_button.focus_mode = Control.FOCUS_NONE
	_fields.add_child(frames_text_button)


## Gives the timeline the height the other rows leave, so its tiles fit a short panel
func _fit_timeline() -> void:
	var used := (
		_margin.get_theme_constant(&"margin_top")
		+ _margin.get_theme_constant(&"margin_bottom")
		+ _fields.get_combined_minimum_size().y
		+ SEPARATION
	)
	if _frames_text.visible:
		used += _frames_text.get_combined_minimum_size().y + SEPARATION
	if get_h_scroll_bar().visible:
		used += get_h_scroll_bar().size.y
	timeline.fit_height(size.y - used)


func _on_frames_edited(
	action_name: String, cells: Array[Vector2i], durations: Array[float]
) -> void:
	if _index < 0:
		return
	_edit(
		func(animation: SheetAnimation) -> void:
			animation.cells = cells
			animation.durations = durations,
		action_name
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


## Gives the animation the colour picked, once the picker closes
func _apply_color() -> void:
	if _index >= 0 and _index < Global.spritesheet.animations.size():
		var color := color_button.color
		_edit(
			func(animation: SheetAnimation) -> void: animation.color = color, "Recolour animation"
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


## Changes the animation with [param change] as one undoable step called
## [param action_name]
func _edit(change: Callable, action_name := "Edit animation") -> void:
	var sheet := Global.spritesheet
	var animation := sheet.animations[_index]
	change.call(animation)
	Global.document.perform(action_name, sheet.set_animation.bind(_index, animation))
