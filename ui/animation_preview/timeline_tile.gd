class_name TimelineTile
extends PanelContainer
## A frame in an [AnimationTimeline]: its picture with its place in the animation on a
## badge and a button to take it out, a short label, and how long it's shown.

signal remove_pressed
signal duration_changed(duration: float)

const REMOVE_ICON := preload("res://assets/icons/Close.svg")
## The narrowest a tile gets, so its duration field fits
const MIN_WIDTH := 58

## Where the frame is in the animation, from 0
var index := 0
var picture := TextureRect.new()
## The place in the animation, from 1, over the picture's top-left corner
var badge := Label.new()
## Takes the frame out, over the picture's top-right corner while hovered or selected
var remove_button := Button.new()
var label := Label.new()
var duration_spin := SpinBox.new()
var selected := false:
	set = set_selected

## The full label, before it's shortened to fit
var _text := ""
var _hovered := false
## Holds the picture and what's over it
var _frame := Control.new()


func _init() -> void:
	theme_type_variation = &"TimelineFrame"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_frame)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(picture)
	badge.theme_type_variation = &"TimelineBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(badge)
	remove_button.icon = REMOVE_ICON
	remove_button.theme_type_variation = &"TimelineRemoveButton"
	remove_button.focus_mode = Control.FOCUS_NONE
	remove_button.tooltip_text = "Take the frame out"
	remove_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	remove_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	remove_button.visible = false
	remove_button.pressed.connect(remove_pressed.emit)
	_frame.add_child(remove_button)

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
	box.add_child(duration_spin)

	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func _ready() -> void:
	SpinScroll.enable(duration_spin)


## Shows the frame at [param frame_index] of the animation: [param texture] (null for an
## empty cell), [param text] shortened to fit, shown [param duration] long
func show_frame(
	frame_index: int, texture: Texture2D, text: String, tooltip: String, duration: float
) -> void:
	index = frame_index
	picture.texture = texture
	badge.text = str(frame_index + 1)
	_text = text
	_fit_label()
	tooltip_text = tooltip
	duration_spin.set_value_no_signal(duration)


## Makes the picture [param side] pixels square, and the tile at least as wide as its
## duration field
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


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_update_look()


func _update_look() -> void:
	if selected:
		theme_type_variation = &"TimelineFrameSelected"
	else:
		theme_type_variation = &"TimelineFrameHover" if _hovered else &"TimelineFrame"
	remove_button.visible = _hovered or selected


## Shortens the label at its end to fit the tile
func _fit_label() -> void:
	if label.size.x <= 0 or not is_inside_tree():
		label.text = _text
		return
	var width := label.size.x - label.get_theme_stylebox(&"normal").get_minimum_size().x
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	label.text = AnimationTimeline.fit_text(_text, font, font_size, width)
