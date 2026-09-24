class_name AnimationPreview
extends PanelContainer
## Plays the selected frames (or every frame when fewer than two are selected)
## as an animation.

enum Mode { LOOP, PING_PONG, ONCE }

var preview: SpritesheetPreview
var fps := 12.0
var mode := Mode.LOOP
var playing := true:
	set(v):
		playing = v
		_play_button.text = "Pause" if playing else "Play"
		if playing and mode == Mode.ONCE and _position >= _coords.size() - 1:
			_position = 0

var _coords: Array[Vector2i] = []
var _position := 0
var _direction := 1
var _elapsed := 0.0
var _textures: Dictionary[Image, ImageTexture] = {}

var _display := TextureRect.new()
var _play_button := Button.new()
var _fps_spin := SpinBox.new()
var _mode_option := OptionButton.new()
var _info := Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(200, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	add_child(box)

	var stage := TextureRect.new()
	stage.texture = ImageUtils.checker_texture(6)
	stage.stretch_mode = TextureRect.STRETCH_TILE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(160, 140)
	box.add_child(stage)
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(_display)

	var controls := HBoxContainer.new()
	box.add_child(controls)
	_play_button.text = "Pause"
	_play_button.custom_minimum_size = Vector2(56, 0)
	_play_button.pressed.connect(func() -> void: playing = not playing)
	controls.add_child(_play_button)
	_fps_spin.min_value = 1
	_fps_spin.max_value = 60
	_fps_spin.value = fps
	_fps_spin.suffix = "fps"
	_fps_spin.tooltip_text = "Frames per second"
	_fps_spin.value_changed.connect(func(value: float) -> void: fps = value)
	controls.add_child(_fps_spin)
	for label: String in ["Loop", "Ping-pong", "Once"]:
		_mode_option.add_item(label)
	_mode_option.tooltip_text = "How the animation repeats"
	_mode_option.item_selected.connect(
		func(index: int) -> void:
			mode = index as Mode
			_direction = 1
	)
	controls.add_child(_mode_option)

	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)


func _ready() -> void:
	preview.preview_updated.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


## Picks up the current frames and selection
func refresh() -> void:
	if not preview or not visible:
		return
	var selected := preview.get_selected_coords()
	_coords = selected if selected.size() >= 2 else preview.spritesheet.get_sorted_coords()
	if _position >= _coords.size():
		_position = 0
	var alive := {}
	for coord in _coords:
		alive[preview.spritesheet.frames[coord]] = true
	for img: Image in _textures.keys():
		if not alive.has(img):
			_textures.erase(img)
	_show_current()


func _process(delta: float) -> void:
	if not visible or not playing or _coords.size() < 2:
		return
	_elapsed += delta
	var frame_time := 1.0 / fps
	while _elapsed >= frame_time:
		_elapsed -= frame_time
		step()


## Advances one frame according to the mode
func step() -> void:
	if _coords.size() < 2:
		return
	match mode:
		Mode.LOOP:
			_position = (_position + 1) % _coords.size()
		Mode.PING_PONG:
			if _position + _direction < 0 or _position + _direction >= _coords.size():
				_direction = -_direction
			_position += _direction
		Mode.ONCE:
			if _position >= _coords.size() - 1:
				playing = false
			else:
				_position += 1
	_show_current()


func get_current_coord() -> Vector2i:
	return _coords[_position] if _position < _coords.size() else SpritesheetPreview.NO_CELL


func _show_current() -> void:
	if _coords.is_empty():
		_display.texture = null
		_info.text = "No frames"
		return
	var coord := _coords[_position]
	var source := preview.spritesheet.frames[coord]
	if not _textures.has(source):
		_textures[source] = ImageTexture.create_from_image(
			preview.spritesheet.get_cell_image(coord)
		)
	_display.texture = _textures[source]
	var index: int = preview.spritesheet.index_of(coord) + Settings.get_value(&"index_start")
	_info.text = tr("Frame %d  (%d of %d)") % [index, _position + 1, _coords.size()]
