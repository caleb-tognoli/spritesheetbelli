class_name InBetweenDialog
extends ConfirmationDialog
## Makes frames between two key frames, see [InBetween]: how many, and where they go.
## They're made in the background (see [InBetweenMaker]) and show as they're made. At the
## top, the keys one over the other like onion skin, to pin spots of the sprite where
## they should be halfway between them (see [MiddlePins]): every frame passes through the
## pins; beside it, the settings, each explained when hovered. Below, the keys and the frames
## between them, played with the animation player's controls (see [FramePlayer]), and
## listed beside it: clicking one shows it in the player. A line at the bottom says what's
## being worked on. Generate adds the frames once they're all made: right away, or as soon
## as they are. Opened from the sheet with two frames selected, or from an animation's
## timeline.

## Emitted with the frames made, to add between keys [param a] and [param b], see
## [method InBetween.add]
signal inbetweens_chosen(
	a: Vector2i,
	b: Vector2i,
	frames: Array[Dictionary],
	place: int,
	to_animations: bool,
	keep_length: bool,
)

## Side of each frame in the list
const TILE := 72
## Side of the frame halfway between the keys, to pin, at least: it grows with the window
const VIEW := 320
## Width of the settings and of the list of frames
const SIDE := 320
## How fast the preview plays when no animation shows the keys, like a new animation
const DEFAULT_FPS := 12.0
## Most movement that can be typed, in pixels
const MAX_MOTION := 4096

var motion_x := SpinBox.new()
var motion_y := SpinBox.new()
## Puts the movement found back, after one was typed
var find_motion_button := Button.new()
var count_spin := SpinBox.new()
var spacing_option := OptionButton.new()
var place_option := OptionButton.new()
var animations_check := CheckBox.new()
## Whether the new frames share the time of the key before them, see
## [method SheetAnimation.insert_between]
var keep_length_check := CheckBox.new()
## How fast the preview plays, as the animation of the keys does
var preview_fps := DEFAULT_FPS
## The keys with the frames between them, in order, see [InBetweenTile]
var frame_list := HFlowContainer.new()
## Plays the keys and the frames between them made so far
var player := FramePlayer.new()
## The keys, with the pins every frame passes through. They're for these keys and this
## movement only, so they're cleared when either changes.
var pins_view := MiddlePins.new()
var clear_pins_button := Button.new()
## Makes the frames
var maker := InBetweenMaker.new()
## What's being worked on, and how far it got
var status_label := Label.new()
var progress_bar := ProgressBar.new()

var _sheet: Spritesheet
var _a := Vector2i.ZERO
var _b := Vector2i.ZERO
var _keys: Array[Dictionary] = []
## The tiles of [member frame_list]: the keys first and last
var _tiles: Array[InBetweenTile] = []
## What the player plays, the pictures of [member _tiles]
var _played: Array[Texture2D] = []
## The part of the sheet the list and the player show: where the keys and every frame
## made are
var _area := Rect2i()
## The movement found, once it is, and whether one was typed instead, so the one found
## doesn't replace it
var _found_motion: Variant = null
var _motion_edited := false
## Whether Generate was pressed before every frame was made: they're added once they are
var _adding := false
var _status_spinner := BusySpinner.new()
## What can't change once Generate is pressed
var _settings: Array[Control] = []


func _init() -> void:
	title = "Generate In-Betweens"
	ok_button_text = "Generate"
	get_ok_button().icon = MainActions.ICONS[&"generate_inbetweens"]
	# The frames may still be being made: they're added, and the window closed, once they are
	dialog_hide_on_ok = false
	DialogButtons.apply(self)
	add_child(maker)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(top)
	var canvas := PixelPicture.new()
	canvas.custom_minimum_size = Vector2(VIEW, VIEW)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.add_child(pins_view)
	top.add_child(canvas)
	top.add_child(_build_settings())
	box.add_child(HSeparator.new())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(bottom)
	player.custom_minimum_size = Vector2(VIEW, 240)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(player)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = SIDE
	frame_list.add_theme_constant_override("h_separation", 4)
	frame_list.add_theme_constant_override("v_separation", 4)
	frame_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(frame_list)
	bottom.add_child(scroll)

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 8)
	status.custom_minimum_size.y = 20
	box.add_child(status)
	status.add_child(_status_spinner)
	status_label.theme_type_variation = &"StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_child(status_label)
	progress_bar.max_value = 1.0
	progress_bar.step = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(200, 6)
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(progress_bar)

	player.frame_shown.connect(func(cell: Vector2i) -> void: _highlight(cell.x))
	maker.motion_found.connect(_on_motion_found)
	maker.updated.connect(_refresh)
	for spin: SpinBox in [motion_x, motion_y]:
		spin.value_changed.connect(
			func(_value: float) -> void:
				_motion_edited = true
				_motion_changed()
		)
	find_motion_button.pressed.connect(
		func() -> void:
			_motion_edited = false
			_motion_changed()
	)
	pins_view.pins_changed.connect(_on_pins_changed)
	clear_pins_button.pressed.connect(pins_view.remove_all)
	count_spin.value_changed.connect(
		func(_value: float) -> void:
			_fill_list()
			_ask()
	)
	spacing_option.item_selected.connect(func(_index: int) -> void: _ask())
	animations_check.toggled.connect(func(on: bool) -> void: keep_length_check.disabled = not on)
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(
		func() -> void:
			if not visible:
				player.playing = false
				_adding = false
				maker.stop()
	)


func _ready() -> void:
	for spin: SpinBox in [motion_x, motion_y, count_spin]:
		SpinScroll.enable(spin)


## How many frames, how they're spread, how the sprite moves and where the frames go,
## each explained when hovered
func _build_settings() -> Control:
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	settings.custom_minimum_size.x = SIDE
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	settings.add_child(grid)

	var count_label := _option_label("Frames", grid)
	count_spin.min_value = 1
	count_spin.max_value = InBetween.MAX_COUNT
	count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(count_spin)
	HelpTooltip.explain(
		L10n.mark("Frames"),
		L10n.mark("How many frames to make between the keys"),
		[count_label, count_spin]
	)

	var spacing_label := _option_label("Spacing", grid)
	for spacing: InBetween.Spacing in InBetween.SPACING_NAMES:
		spacing_option.add_item(InBetween.SPACING_NAMES[spacing], spacing)
	spacing_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spacing_option)
	HelpTooltip.explain(
		L10n.mark("Spacing"),
		L10n.mark(
			(
				"How the frames are spread between the keys. Easing in bunches them up near the "
				+ "first key so the sprite starts slowly, easing out near the second so it stops "
				+ "slowly."
			)
		),
		[spacing_label, spacing_option]
	)

	var motion_label := _option_label("Movement", grid)
	var motion_row := HBoxContainer.new()
	motion_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for spin: SpinBox in [motion_x, motion_y]:
		spin.min_value = -MAX_MOTION
		spin.max_value = MAX_MOTION
		spin.suffix = "px"
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		motion_row.add_child(spin)
	find_motion_button.icon = preload("res://assets/icons/Reload.svg")
	find_motion_button.flat = true
	find_motion_button.tooltip_text = "Use the movement found by lining the keys up"
	find_motion_button.disabled = true
	motion_row.add_child(find_motion_button)
	grid.add_child(motion_row)
	HelpTooltip.explain(
		L10n.mark("Movement"),
		L10n.mark(
			(
				"How far the whole sprite moves from the first key to the second, across and "
				+ "down, in pixels. It's found by lining the keys up: type another one if it's "
				+ "wrong, or 0 for none."
			)
		),
		[motion_label, motion_x, motion_y]
	)

	var place_label := _option_label("Place", grid)
	place_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(place_option)
	HelpTooltip.explain(
		L10n.mark("Place"),
		L10n.mark("Where the new frames go in the sheet"),
		[place_label, place_option]
	)

	animations_check.text = "Add to animations"
	settings.add_child(animations_check)
	HelpTooltip.explain(
		L10n.mark("Add to animations"),
		L10n.mark(
			(
				"Play the new frames between the keys wherever an animation plays them one "
				+ "after the other"
			)
		),
		[animations_check]
	)
	keep_length_check.text = "Keep animation length"
	settings.add_child(keep_length_check)
	HelpTooltip.explain(
		L10n.mark("Keep animation length"),
		L10n.mark(
			(
				"The new frames share the time of the key before them, so the animations last "
				+ "as long as before"
			)
		),
		[keep_length_check]
	)
	clear_pins_button.text = "Clear pins"
	clear_pins_button.icon = preload("res://assets/icons/Clear.svg")
	clear_pins_button.tooltip_text = "Take every pin away"
	clear_pins_button.disabled = true
	clear_pins_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings.add_child(clear_pins_button)
	LabelLink.link(count_label, count_spin)
	LabelLink.link(spacing_label, spacing_option)
	LabelLink.link(motion_label, motion_x)
	LabelLink.link(place_label, place_option)
	_settings.append_array([count_spin, spacing_option, motion_x, motion_y, find_motion_button])
	_settings.append_array([place_option, animations_check, keep_length_check])
	_settings.append_array([pins_view, clear_pins_button])
	return settings


## A label saying [param text], added to [param grid]
func _option_label(text: String, grid: GridContainer) -> Label:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	return label


## Shows frames between keys [param a] and [param b] of [param sheet], with the settings
## used last and the movement found, played at [param fps], or else as fast as an
## animation of the keys plays
func open(sheet: Spritesheet, a: Vector2i, b: Vector2i, fps := 0.0) -> void:
	_sheet = sheet
	_a = a
	_b = b
	_keys = [InBetween.key_of(sheet, a), InBetween.key_of(sheet, b)]
	_adding = false
	_lock(false)
	pins_view.show_keys(_keys[0], _keys[1])
	clear_pins_button.disabled = true
	_area = pins_view.area
	preview_fps = fps if fps > 0 else _animation_fps(sheet, a, b)
	player.fps = preview_fps
	player.mode = SheetAnimation.Mode.LOOP
	player.stage.export_color = ExportOptions.from_sheet(sheet).background
	count_spin.set_value_no_signal(Settings.get_value(&"inbetween_count"))
	motion_x.set_value_no_signal(0)
	motion_y.set_value_no_signal(0)
	_found_motion = null
	_motion_edited = false
	find_motion_button.disabled = true
	var spacing_index := spacing_option.get_item_index(Settings.get_value(&"inbetween_spacing"))
	spacing_option.select(maxi(spacing_index, 0))
	_fill_places()
	var played_by_animations := false
	for animation in sheet.animations:
		if animation.count_between(a, b) > 0:
			played_by_animations = true
	animations_check.visible = played_by_animations
	animations_check.button_pressed = true
	keep_length_check.visible = played_by_animations
	keep_length_check.disabled = false
	keep_length_check.button_pressed = Settings.get_value(&"inbetween_keep_length")
	for tile in _tiles:
		frame_list.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	_played.clear()
	_fill_list()
	player.go_to_start()
	player.playing = true
	player.stage.fit()
	# Frames are made once the movement is found, see _on_motion_found
	maker.start(_keys[0], _keys[1])
	popup_centered()


## Whether every frame is made, so Generate adds them right away
func is_ready() -> bool:
	return maker.get_stage() == InBetweenMaker.Stage.DONE


## How fast an animation playing keys [param a] and [param b] one after the other plays,
## or else one with either of them, or else a new animation
static func _animation_fps(sheet: Spritesheet, a: Vector2i, b: Vector2i) -> float:
	var with_a_key := 0.0
	for animation in sheet.animations:
		if animation.count_between(a, b) > 0:
			return animation.fps
		if with_a_key == 0.0 and (a in animation.cells or b in animation.cells):
			with_a_key = animation.fps
	return with_a_key if with_a_key > 0.0 else DEFAULT_FPS


## The places to choose from: right after the first key only in the grid layout, where
## frames move along
func _fill_places() -> void:
	place_option.clear()
	for place: InBetween.Place in InBetween.PLACE_NAMES:
		if place != InBetween.Place.AFTER_FIRST or _sheet.layout == Spritesheet.Layout.GRID:
			place_option.add_item(InBetween.PLACE_NAMES[place], place)
	var index := place_option.get_item_index(Settings.get_value(&"inbetween_place"))
	place_option.select(maxi(index, 0))


## How far between the keys each frame asked for is, see [method InBetween.time_of]
func _times() -> PackedFloat64Array:
	var times := PackedFloat64Array()
	var count := int(count_spin.value)
	var spacing := spacing_option.get_selected_id() as InBetween.Spacing
	for i in count:
		times.append(InBetween.time_of(i, count, spacing))
	return times


## The movement typed or found, see [method InBetween.prepare]
func _motion() -> Vector2i:
	return Vector2i(int(motion_x.value), int(motion_y.value))


## Asks for the frames as the fields say, once the movement is known: only the middle one
## while a pin is dragged, see [method InBetweenMaker.ask]
func _ask() -> void:
	if _found_motion == null and not _motion_edited:
		return
	var dragging := pins_view.dragged >= 0
	maker.ask(_motion(), PackedFloat64Array() if dragging else _times(), pins_view.pins)


func _on_motion_found(motion: Vector2i) -> void:
	_found_motion = motion
	if _motion_edited:
		find_motion_button.disabled = _adding
		return
	motion_x.set_value_no_signal(motion.x)
	motion_y.set_value_no_signal(motion.y)
	_ask()


## Asks for frames with the movement typed, or the one found when it's not: the middle
## frame moves under the pins, so they're cleared
func _motion_changed() -> void:
	if not _motion_edited and _found_motion != null:
		motion_x.set_value_no_signal(_found_motion.x)
		motion_y.set_value_no_signal(_found_motion.y)
	find_motion_button.disabled = not _motion_edited or _found_motion == null
	pins_view.show_keys(_keys[0], _keys[1])
	clear_pins_button.disabled = true
	_ask()


## Remakes the middle frame while a pin is dragged, and every frame once it's let go
func _on_pins_changed(_done: bool) -> void:
	clear_pins_button.disabled = pins_view.pins.is_empty()
	_ask()


## As many tiles in the list as frames asked for, between the keys
func _fill_list() -> void:
	var count := int(count_spin.value)
	if _tiles.is_empty():
		for key in _keys:
			var tile := _new_tile()
			tile.label.text = tr("Key")
			tile.tooltip_text = tr("Key frame")
			tile.show_frame(key, _texture_of(key))
			_tiles.append(tile)
	while _tiles.size() - 2 < count:
		var tile := _new_tile()
		tile.stale = true
		_tiles.insert(_tiles.size() - 1, tile)
	while _tiles.size() - 2 > count:
		var tile: InBetweenTile = _tiles.pop_at(_tiles.size() - 2)
		frame_list.remove_child(tile)
		tile.queue_free()
	for i in _tiles.size():
		frame_list.move_child(_tiles[i], i)
		if i > 0 and i < _tiles.size() - 1:
			_tiles[i].label.text = str(i)
			_tiles[i].tooltip_text = tr("In-between %d") % i
	_refresh()


func _new_tile() -> InBetweenTile:
	var tile := InBetweenTile.new(TILE)
	frame_list.add_child(tile)
	tile.pressed.connect(func() -> void: _show_tile(_tiles.find(tile)))
	return tile


## Shows what's made and what's being worked on
func _refresh() -> void:
	if _tiles.is_empty():
		return
	var stage := maker.get_stage()
	var working := maker.is_working()
	var dragging := pins_view.dragged >= 0
	var times := _times()
	var area := _area
	for i in times.size():
		var frame := maker.get_frame(times[i])
		if not frame.is_empty():
			area = area.merge(_rect_of(frame))
	# A frame reaching out of what's shown: everything is shown again, smaller
	if area != _area:
		_area = area
		for tile in _tiles:
			if not tile.frame.is_empty():
				tile.show_frame(tile.frame, _texture_of(tile.frame))
	for i in times.size():
		var tile := _tiles[i + 1]
		var frame := maker.get_frame(times[i])
		if not frame.is_empty() and not is_same(frame, tile.frame):
			tile.show_frame(frame, _texture_of(frame))
		tile.stale = frame.is_empty()
		tile.busy = tile.stale and working and not dragging
	var pictures: Array[Texture2D] = []
	for tile in _tiles:
		pictures.append(tile.picture.texture)
	if pictures != _played:
		_played = pictures
		player.set_pictures(pictures)
	if _adding and stage == InBetweenMaker.Stage.FAILED:
		_adding = false
		_lock(false)
	_show_status(stage, dragging)
	if _adding and stage == InBetweenMaker.Stage.DONE:
		_add()


## Says what's being worked on, or that the frames are ready
func _show_status(stage: InBetweenMaker.Stage, dragging: bool) -> void:
	var count := int(count_spin.value)
	_status_spinner.visible = maker.is_working()
	progress_bar.visible = stage in [InBetweenMaker.Stage.PIECES, InBetweenMaker.Stage.FRAMES]
	progress_bar.value = maker.get_progress()
	status_label.theme_type_variation = &"StatusLabel"
	match stage:
		InBetweenMaker.Stage.MOTION:
			status_label.text = tr("Finding how the sprite moves…")
		InBetweenMaker.Stage.PIECES:
			status_label.text = tr("Following every piece…")
		InBetweenMaker.Stage.FRAMES:
			if dragging:
				status_label.text = tr("The other frames are made when the pin is let go")
				progress_bar.visible = false
			elif maker.get_frame(InBetweenMaker.MIDDLE).is_empty():
				status_label.text = tr("Making the frame halfway…")
			else:
				var made := 0
				for time in _times():
					if not maker.get_frame(time).is_empty():
						made += 1
				status_label.text = tr("Making frames: %d of %d") % [made, count]
		InBetweenMaker.Stage.DONE:
			status_label.text = tr_n("%d frame ready", "%d frames ready", count) % count
		InBetweenMaker.Stage.FAILED:
			status_label.text = tr("The frames couldn't be made")
			status_label.theme_type_variation = &"ErrorLabel"
		_:
			status_label.text = ""
	get_ok_button().disabled = _adding or stage == InBetweenMaker.Stage.FAILED


## Where [param frame] is placed in the sheet
static func _rect_of(frame: Dictionary) -> Rect2i:
	return Rect2i(frame.origin, (frame.image as Image).get_size())


## [param frame] on [member _area], for the list and the player
func _texture_of(frame: Dictionary) -> ImageTexture:
	var canvas := Image.create_empty(_area.size.x, _area.size.y, false, Image.FORMAT_RGBA8)
	var img: Image = frame.image
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), frame.origin - _area.position)
	return ImageTexture.create_from_image(canvas)


## Shows the frame of the tile at [param index] in the player, paused
func _show_tile(index: int) -> void:
	player.playing = false
	var cell := player.get_cells().find(Vector2i(index, 0))
	if cell >= 0:
		player.go_to(cell)
	_highlight(index)


## Highlights the tile at [param index] in the list, the one the player shows
func _highlight(index: int) -> void:
	for i in _tiles.size():
		_tiles[i].current = i == index


## Keeps the settings and pins from changing, once Generate is pressed
func _lock(locked: bool) -> void:
	for control in _settings:
		if control is BaseButton:
			(control as BaseButton).disabled = locked
		elif control is SpinBox:
			(control as SpinBox).editable = not locked
	pins_view.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	ok_button_text = "Generating…" if locked else "Generate"
	if not locked:
		find_motion_button.disabled = not _motion_edited or _found_motion == null
		clear_pins_button.disabled = pins_view.pins.is_empty()
		keep_length_check.disabled = not animations_check.button_pressed


## Adds the frames once they're all made
func _on_confirmed() -> void:
	_adding = true
	_lock(true)
	_refresh()


func _add() -> void:
	var frames := maker.get_frames()
	var place := place_option.get_selected_id()
	Settings.set_value(&"inbetween_count", int(count_spin.value))
	Settings.set_value(&"inbetween_place", place)
	Settings.set_value(&"inbetween_spacing", spacing_option.get_selected_id())
	var to_animations := animations_check.visible and animations_check.button_pressed
	if to_animations:
		Settings.set_value(&"inbetween_keep_length", keep_length_check.button_pressed)
	var keep_length := to_animations and keep_length_check.button_pressed
	hide()
	_lock(false)
	inbetweens_chosen.emit(_a, _b, frames, place, to_animations, keep_length)
