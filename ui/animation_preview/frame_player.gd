class_name FramePlayer
extends VBoxContainer
## Plays cells of a spritesheet, with buttons to go back to the first frame, play or
## pause, step to the previous or next frame, and show the previous frame faintly behind
## the current one (onion skin).

## The shown frame changed, e.g. to highlight it elsewhere
signal frame_changed(cell: Vector2i)

const PLAY_ICON := preload("res://assets/icons/Play.svg")
const PAUSE_ICON := preload("res://assets/icons/Pause.svg")
const START_ICON := preload("res://assets/icons/PlayStartBackwards.svg")
const PREVIOUS_ICON := preload("res://assets/icons/PagePrevious.svg")
const NEXT_ICON := preload("res://assets/icons/PageNext.svg")
const ONION_ICON := preload("res://assets/icons/Onion.svg")
## How visible the previous frame is with onion skin
const ONION_ALPHA := 0.3

var sheet: Spritesheet:
	set = set_sheet
var fps := 12.0
var mode := SheetAnimation.Mode.LOOP:
	set(value):
		if value != mode:
			mode = value
			_direction = 1
var playing := true:
	set = set_playing

var start_button := Button.new()
var play_button := Button.new()
var previous_button := Button.new()
var next_button := Button.new()
var onion_button := Button.new()
var counter := Label.new()
## Holds the buttons, so owners can add their own controls next to them
var controls := HBoxContainer.new()

## What [method set_cells] got, before skipping empty cells
var _source_cells: Array[Vector2i] = []
var _source_durations: Array[float] = []
var _cells: Array[Vector2i] = []
## How long each of [member _cells] is shown, in frames
var _durations: Array[float] = []
var _position := 0
var _direction := 1
var _elapsed := 0.0
var _textures: Dictionary[Image, ImageTexture] = {}
var _stage := TextureRect.new()
var _onion := TextureRect.new()
var _display := TextureRect.new()


func _init() -> void:
	_stage.texture = ImageUtils.checker_texture(6)
	_stage.stretch_mode = TextureRect.STRETCH_TILE
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(160, 120)
	add_child(_stage)
	for layer: TextureRect in [_onion, _display]:
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_stage.add_child(layer)
	_onion.modulate.a = ONION_ALPHA

	add_child(controls)
	for button: Button in [start_button, previous_button, play_button, next_button]:
		button.flat = true
		controls.add_child(button)
	start_button.icon = START_ICON
	start_button.tooltip_text = "Back to the first frame"
	start_button.pressed.connect(go_to_start)
	previous_button.icon = PREVIOUS_ICON
	previous_button.tooltip_text = "Previous frame"
	previous_button.pressed.connect(step.bind(-1))
	next_button.icon = NEXT_ICON
	next_button.tooltip_text = "Next frame"
	next_button.pressed.connect(step.bind(1))
	play_button.pressed.connect(func() -> void: playing = not playing)
	onion_button.flat = true
	onion_button.toggle_mode = true
	onion_button.icon = ONION_ICON
	onion_button.tooltip_text = "Onion skin: show the previous frame faintly"
	onion_button.toggled.connect(
		func(on: bool) -> void:
			if Settings.get_value(&"onion_skin") != on:
				Settings.set_value(&"onion_skin", on)
			_show_current()
	)
	controls.add_child(onion_button)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.theme_type_variation = &"StatusLabel"
	controls.add_child(counter)
	playing = true


func _ready() -> void:
	onion_button.set_pressed_no_signal(Settings.get_value(&"onion_skin"))
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"onion_skin":
				onion_button.button_pressed = Settings.get_value(&"onion_skin")
	)


func set_sheet(value: Spritesheet) -> void:
	if sheet and sheet.updated.is_connected(_on_sheet_updated):
		sheet.updated.disconnect(_on_sheet_updated)
	sheet = value
	if sheet:
		sheet.updated.connect(_on_sheet_updated)
	_textures.clear()


func set_playing(value: bool) -> void:
	playing = value
	play_button.icon = PAUSE_ICON if playing else PLAY_ICON
	play_button.tooltip_text = "Pause" if playing else "Play"
	# Playing a finished one-shot animation starts it over
	if playing and mode == SheetAnimation.Mode.ONCE and _position >= _cells.size() - 1:
		_position = 0
		_show_current()


## Plays [param cells] in order, each for its number of frames in [param durations]
## (1 when missing). Cells without a frame are skipped.
func set_cells(cells: Array[Vector2i], durations: Array[float] = []) -> void:
	var current := get_current_cell()
	_source_cells = cells.duplicate()
	_source_durations = durations.duplicate()
	_cells.clear()
	_durations.clear()
	for i in cells.size():
		if sheet == null or sheet.has_frame(cells[i]):
			_cells.append(cells[i])
			_durations.append(durations[i] if i < durations.size() else 1.0)
	# Stay on the same frame when it's still there
	_position = maxi(_cells.find(current), 0)
	_show_current()


func get_cells() -> Array[Vector2i]:
	return _cells


func get_current_cell() -> Vector2i:
	return _cells[_position] if _position < _cells.size() else Spritesheet.NO_CELL


## The frame shown before the current one while playing, or NO_CELL at the start of an
## animation that plays once
func get_previous_cell() -> Vector2i:
	if _cells.size() < 2:
		return Spritesheet.NO_CELL
	var previous := _position - _direction
	if mode == SheetAnimation.Mode.PING_PONG and (previous < 0 or previous >= _cells.size()):
		previous = _position + _direction
	elif mode == SheetAnimation.Mode.ONCE and previous < 0:
		return Spritesheet.NO_CELL
	return _cells[posmod(previous, _cells.size())]


## Shows the first frame, without changing whether it plays
func go_to_start() -> void:
	_position = 0
	_direction = 1
	_elapsed = 0.0
	_show_current()


## Shows the frame [param by] steps away, wrapping around, and stops playing
func step(by: int) -> void:
	playing = false
	if _cells.is_empty():
		return
	_position = posmod(_position + by, _cells.size())
	_show_current()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not playing or _cells.size() < 2:
		return
	_elapsed += delta
	while playing and _elapsed >= _frame_time():
		_elapsed -= _frame_time()
		_advance()


## Seconds the current frame is shown
func _frame_time() -> float:
	var duration := _durations[_position] if _position < _durations.size() else 1.0
	return duration / maxf(fps, 0.1)


## Moves to the next frame the way the animation repeats
func _advance() -> void:
	match mode:
		SheetAnimation.Mode.LOOP:
			_position = (_position + 1) % _cells.size()
		SheetAnimation.Mode.PING_PONG:
			if _position + _direction < 0 or _position + _direction >= _cells.size():
				_direction = -_direction
			_position += _direction
		SheetAnimation.Mode.ONCE:
			if _position >= _cells.size() - 1:
				playing = false
				return
			_position += 1
	_show_current()


func _on_sheet_updated() -> void:
	# Frames may have been edited or resized
	_textures.clear()
	set_cells(_source_cells, _source_durations)


func _show_current() -> void:
	var cell := get_current_cell()
	start_button.disabled = _cells.size() < 2
	previous_button.disabled = _cells.size() < 2
	next_button.disabled = _cells.size() < 2
	play_button.disabled = _cells.size() < 2
	if cell == Spritesheet.NO_CELL:
		_display.texture = null
		_onion.texture = null
		counter.text = tr("No frames")
		return
	_display.texture = _texture(cell)
	var previous := get_previous_cell()
	var show_onion := onion_button.button_pressed and previous != Spritesheet.NO_CELL
	_onion.texture = _texture(previous) if show_onion else null
	counter.text = "%d / %d" % [_position + 1, _cells.size()]
	frame_changed.emit(cell)


func _texture(cell: Vector2i) -> ImageTexture:
	var source := sheet.frames[cell]
	if not _textures.has(source):
		_textures[source] = ImageTexture.create_from_image(sheet.get_cell_image(cell))
	return _textures[source]
