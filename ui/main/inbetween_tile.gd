class_name InBetweenTile
extends PanelContainer
## A frame in the strip of Generate In-Betweens (see [InBetweenDialog]): its picture with a
## label under it. A frame that isn't made yet shows what it showed before, faded, with a
## spinner turning over it while it's being made. The frame the preview shows is
## highlighted, and clicking one shows it there.

signal pressed

var picture := PixelPicture.new()
var label := Label.new()
## The frame shown (see [method InBetween.key_of]), or empty
var frame := {}
## Whether [member frame] isn't the frame asked for, or there's none yet: it's faded
var stale := false:
	set(value):
		if value != stale:
			stale = value
			picture.opacity = 0.35 if stale else 1.0
## Whether the frame is being made: a spinner turns over it
var busy := false:
	set(value):
		if value != busy:
			busy = value
			_spinner.visible = busy
## Whether the preview shows it
var current := false:
	set(value):
		if value != current:
			current = value
			_update_style()

var _spinner := BusySpinner.new()
var _hovered := false


func _init(side: int) -> void:
	theme_type_variation = &"TimelineFrame"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	picture.custom_minimum_size = Vector2(side, side)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	_spinner.custom_minimum_size = Vector2(24, 24)
	_spinner.size = _spinner.custom_minimum_size
	_spinner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_spinner.visible = false
	picture.add_child(_spinner)
	label.theme_type_variation = &"StatusLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	mouse_entered.connect(
		func() -> void:
			_hovered = true
			_update_style()
	)
	mouse_exited.connect(
		func() -> void:
			_hovered = false
			_update_style()
	)


## Shows [param shown] as [param texture]
func show_frame(shown: Dictionary, texture: Texture2D) -> void:
	frame = shown
	picture.texture = texture


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _update_style() -> void:
	if current:
		theme_type_variation = &"TimelineFrameSelected"
	elif _hovered:
		theme_type_variation = &"TimelineFrameHover"
	else:
		theme_type_variation = &"TimelineFrame"
	label.theme_type_variation = &"TimelineLabelSelected" if current else &"StatusLabel"
