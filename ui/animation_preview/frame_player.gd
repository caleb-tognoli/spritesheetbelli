class_name FramePlayer
extends VBoxContainer
## Plays cells of a spritesheet on a [FrameStage], with a bar to scrub through them, and
## buttons to go back to the first frame, play or pause, step to the previous or next
## frame, show the previous frame faintly behind the current one (onion skin), choose
## what's behind the frames and fit them in the stage again.

const PLAY_ICON := preload("res://assets/icons/Play.svg")
const PAUSE_ICON := preload("res://assets/icons/Pause.svg")
const START_ICON := preload("res://assets/icons/PlayStartBackwards.svg")
const PREVIOUS_ICON := preload("res://assets/icons/PagePrevious.svg")
const NEXT_ICON := preload("res://assets/icons/PageNext.svg")
const ONION_ICON := preload("res://assets/icons/Onion.svg")
const FIT_ICON := preload("res://assets/icons/CenterView.svg")
## The background choices, in the menu's order, with the value of the
## animation_background setting for each
const BACKGROUNDS := [  # L10n.mark
	[FrameStage.Background.CHECKERBOARD, "Checkerboard", &"checkerboard"],
	[FrameStage.Background.COLOR, "Colour…", &"color"],
	[FrameStage.Background.EXPORT, "Export Background", &"export"],
]

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

var stage := FrameStage.new()
## Drags through the frames, or jumps to one
var scrub := HSlider.new()
var start_button := Button.new()
var play_button := Button.new()
var previous_button := Button.new()
var next_button := Button.new()
var onion_button := Button.new()
var background_button := MenuButton.new()
var fit_button := Button.new()
var counter := Label.new()
## Holds the buttons, on one row: the player is never narrower than they are together
var controls := HBoxContainer.new()
## Where the background colour is picked
var color_popup := PopupPanel.new()
var color_picker := ColorPicker.new()

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
## Whether it was playing when scrubbing started, to play on after
var _played_before_scrub := false
var _updating_scrub := false
## The small checkerboard of the background button
var _swatch_checker := ImageUtils.checker_texture(3)


func _init() -> void:
	add_theme_constant_override("separation", 2)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(80, 60)
	add_child(stage)

	var scrub_row := HBoxContainer.new()
	add_child(scrub_row)
	scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scrub.step = 1
	scrub.theme_type_variation = &"ScrubBar"
	scrub.focus_mode = Control.FOCUS_NONE
	scrub.tooltip_text = "Drag to go through the frames, or click to jump to one"
	scrub_row.add_child(scrub)
	counter.custom_minimum_size.x = 48
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.theme_type_variation = &"StatusLabel"
	scrub_row.add_child(counter)

	controls.add_theme_constant_override("separation", 0)
	add_child(controls)
	for button: Button in [start_button, previous_button, play_button, next_button, onion_button]:
		button.theme_type_variation = &"ToolbarButton"
		button.focus_mode = Control.FOCUS_NONE
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
	onion_button.toggle_mode = true
	onion_button.icon = ONION_ICON
	onion_button.tooltip_text = "Onion skin: show the previous frame faintly"
	onion_button.toggled.connect(
		func(on: bool) -> void:
			if Settings.get_value(&"onion_skin") != on:
				Settings.set_value(&"onion_skin", on)
			_show_current()
	)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	_build_background_button()
	fit_button.theme_type_variation = &"ToolbarButton"
	fit_button.focus_mode = Control.FOCUS_NONE
	fit_button.icon = FIT_ICON
	fit_button.tooltip_text = "Fit the frames in the preview. Scroll to zoom."
	fit_button.pressed.connect(stage.fit)
	controls.add_child(fit_button)

	scrub.value_changed.connect(
		func(value: float) -> void:
			if not _updating_scrub:
				go_to(int(value))
	)
	scrub.drag_started.connect(
		func() -> void:
			_played_before_scrub = playing
			playing = false
	)
	scrub.drag_ended.connect(
		func(_changed: bool) -> void:
			if _played_before_scrub:
				playing = true
	)
	playing = true


func _build_background_button() -> void:
	background_button.theme_type_variation = &"ToolbarButton"
	background_button.focus_mode = Control.FOCUS_NONE
	background_button.flat = false
	background_button.tooltip_text = "Background: a checkerboard, a colour or the export's"
	# Room for the swatch drawn over it, as for an icon
	var blank := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	background_button.icon = ImageTexture.create_from_image(blank)
	background_button.draw.connect(_draw_swatch)
	controls.add_child(background_button)
	var menu := background_button.get_popup()
	for i in BACKGROUNDS.size():
		menu.add_radio_check_item(BACKGROUNDS[i][1], i)
	menu.id_pressed.connect(
		func(id: int) -> void:
			Settings.set_value(&"animation_background", BACKGROUNDS[id][2])
			if BACKGROUNDS[id][0] == FrameStage.Background.COLOR:
				_pick_color()
	)
	color_picker.edit_alpha = false
	color_picker.presets_visible = false
	color_picker.color_changed.connect(
		func(color: Color) -> void: Settings.set_value(&"animation_background_color", color)
	)
	color_popup.add_child(color_picker)
	add_child(color_popup)


func _ready() -> void:
	onion_button.set_pressed_no_signal(Settings.get_value(&"onion_skin"))
	Settings.changed.connect(
		func(key: StringName) -> void:
			if key == &"onion_skin":
				onion_button.button_pressed = Settings.get_value(&"onion_skin")
			elif key in [&"animation_background", &"animation_background_color"]:
				_show_background()
			# Whole zooms are whole screen pixels, see PixelZoom
			elif key in [&"pixel_perfect_zoom", &"ui_scale"] and stage.fitted:
				stage.fit()
	)
	_show_background()


func set_sheet(value: Spritesheet) -> void:
	if sheet and sheet.updated.is_connected(_on_sheet_updated):
		sheet.updated.disconnect(_on_sheet_updated)
	sheet = value
	if sheet:
		sheet.updated.connect(_on_sheet_updated)
		stage.export_color = ExportOptions.from_sheet(sheet).background
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
	# Frames are shown in their cells, which are all as big
	var has_cells := sheet != null and not _cells.is_empty()
	stage.content_size = sheet.sprite_size if has_cells else Vector2i.ZERO
	_show_current()


func get_cells() -> Array[Vector2i]:
	return _cells


func get_current_cell() -> Vector2i:
	return _cells[_position] if _position < _cells.size() else Spritesheet.NO_CELL


## Position of the shown frame in [method get_cells]
func get_current_index() -> int:
	return _position


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


## Shows the frame at [param index] in [method get_cells], without changing whether it
## plays
func go_to(index: int) -> void:
	if _cells.is_empty():
		return
	_position = clampi(index, 0, _cells.size() - 1)
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
	# Frames may have been edited or resized, and the export background changed
	_textures.clear()
	stage.export_color = ExportOptions.from_sheet(sheet).background
	set_cells(_source_cells, _source_durations)


func _show_current() -> void:
	var cell := get_current_cell()
	var few := _cells.size() < 2
	for button: Button in [start_button, previous_button, next_button, play_button]:
		button.disabled = few
	_updating_scrub = true
	scrub.max_value = maxi(_cells.size() - 1, 0)
	scrub.value = _position
	scrub.editable = not few
	_updating_scrub = false
	if cell == Spritesheet.NO_CELL:
		stage.texture = null
		stage.onion = null
		counter.text = tr("No frames")
		return
	stage.texture = _texture(cell)
	var previous := get_previous_cell()
	var show_onion := onion_button.button_pressed and previous != Spritesheet.NO_CELL
	stage.onion = _texture(previous) if show_onion else null
	counter.text = "%d / %d" % [_position + 1, _cells.size()]


func _texture(cell: Vector2i) -> ImageTexture:
	var source := sheet.frames[cell]
	if not _textures.has(source):
		_textures[source] = ImageTexture.create_from_image(sheet.get_cell_image(cell))
	return _textures[source]


func _show_background() -> void:
	var chosen: String = Settings.get_value(&"animation_background")
	var index := 0
	for i in BACKGROUNDS.size():
		if BACKGROUNDS[i][2] == chosen:
			index = i
	stage.background = BACKGROUNDS[index][0]
	stage.background_color = Settings.get_value(&"animation_background_color")
	var menu := background_button.get_popup()
	for i in menu.item_count:
		menu.set_item_checked(i, i == index)
	background_button.queue_redraw()


func _pick_color() -> void:
	color_picker.color = Settings.get_value(&"animation_background_color")
	var below := background_button.get_screen_transform() * Vector2(0, background_button.size.y)
	color_popup.popup(Rect2i(Vector2i(below), Vector2i.ZERO))


## What's behind the frames, drawn as a small square on the background button
func _draw_swatch() -> void:
	var side := 14.0
	var rect := Rect2((background_button.size - Vector2(side, side)) / 2, Vector2(side, side))
	background_button.draw_texture_rect(_swatch_checker, rect, true)
	match stage.background:
		FrameStage.Background.COLOR:
			background_button.draw_rect(rect, stage.background_color)
		FrameStage.Background.EXPORT:
			background_button.draw_rect(rect, stage.export_color)
	var edge := background_button.get_theme_color("font_color", &"StatusLabel")
	background_button.draw_rect(rect, edge, false, 1.0)
