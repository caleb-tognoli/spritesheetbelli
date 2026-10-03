class_name TimelineTile
extends PanelContainer
## A frame in an [AnimationTimeline]: its picture, a short label, how long it's shown and
## a button to take it out.

signal remove_pressed
signal duration_changed(duration: float)

const REMOVE_ICON := preload("res://assets/icons/Close.svg")
## The narrowest a tile gets, so its duration field and remove button fit
const MIN_WIDTH := 58

## Where the frame is in the animation, from 0
var index := 0
var picture := TextureRect.new()
var label := Label.new()
var duration_spin := SpinBox.new()
## Takes the frame out, right of its duration
var remove_button := Button.new()
var selected := false:
	set = set_selected

## The full label, before it's shortened to fit
var _text := ""
var _hovered := false
## Holds the picture over its well
var _frame := Control.new()


func _init() -> void:
	theme_type_variation = &"TimelineFrame"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_frame)
	var well := Panel.new()
	well.theme_type_variation = &"TimelineWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(well)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(picture)

	label.theme_type_variation = &"StatusLabel"
	# Names of frames, or text translated where it's made
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shortened to fit, see _fit_label(), rather than widening the tile
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.resized.connect(_fit_label)
	box.add_child(label)

	duration_spin.min_value = 0.1
	duration_spin.max_value = 100
	duration_spin.step = 0.1
	duration_spin.custom_arrow_step = 0.5
	duration_spin.prefix = "×"
	duration_spin.select_all_on_focus = true
	duration_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	duration_spin.tooltip_text = "How long it's shown: 2 is twice as long as a frame"
	duration_spin.get_line_edit().theme_type_variation = &"TimelineDurationEdit"
	duration_spin.value_changed.connect(duration_changed.emit)
	duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 2)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(duration_spin)
	remove_button.icon = REMOVE_ICON
	remove_button.theme_type_variation = &"TimelineRemoveButton"
	remove_button.focus_mode = Control.FOCUS_NONE
	remove_button.tooltip_text = "Take the frame out"
	remove_button.pressed.connect(remove_pressed.emit)
	controls.add_child(remove_button)
	box.add_child(controls)

	# Its fields stop the mouse, which counts as leaving the tile, so they're asked too
	for target: Control in [self, remove_button, duration_spin, duration_spin.get_line_edit()]:
		target.mouse_entered.connect(_update_hovered, CONNECT_DEFERRED)
		target.mouse_exited.connect(_update_hovered, CONNECT_DEFERRED)


func _ready() -> void:
	SpinScroll.enable(duration_spin)


## Shows the frame at [param frame_index] of the animation: [param texture] (null for an
## empty cell), [param text] shortened to fit, shown [param duration] long
func show_frame(
	frame_index: int, texture: Texture2D, text: String, tooltip: String, duration: float
) -> void:
	index = frame_index
	picture.texture = texture
	_text = text
	_fit_label()
	tooltip_text = tooltip
	duration_spin.set_value_no_signal(duration)


## Makes the picture [param side] pixels square, and the tile at least as wide as its
## duration field and remove button
func set_picture_size(side: int) -> void:
	_frame.custom_minimum_size = Vector2(maxi(side, MIN_WIDTH), side)


func get_picture_size() -> int:
	return int(_frame.custom_minimum_size.y)


func set_selected(value: bool) -> void:
	selected = value
	_update_look()


## The label as shown, maybe shortened
func get_label_text() -> String:
	return label.text


## Hovered while the mouse is over the tile or anything in it
func _update_hovered() -> void:
	if not is_inside_tree():
		return
	var over := get_viewport().gui_get_hovered_control()
	var hovered := over != null and (over == self or is_ancestor_of(over))
	if hovered != _hovered:
		_hovered = hovered
		_update_look()


func _update_look() -> void:
	if selected:
		theme_type_variation = &"TimelineFrameSelected"
	else:
		theme_type_variation = &"TimelineFrameHover" if _hovered else &"TimelineFrame"
	label.theme_type_variation = &"TimelineLabelSelected" if selected else &"StatusLabel"


## Shortens the label at its end to fit the tile
func _fit_label() -> void:
	if label.size.x <= 0 or not is_inside_tree():
		label.text = _text
		return
	var width := label.size.x - label.get_theme_stylebox(&"normal").get_minimum_size().x
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	label.text = AnimationTimeline.fit_text(_text, font, font_size, width)
