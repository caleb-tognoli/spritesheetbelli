class_name InBetweenDialog
extends ConfirmationDialog
## Makes frames between two key frames, see [InBetween]: how many, and where they go,
## shown between the keys and played. The frame halfway between the keys shows big, to pin
## spots of the sprite where they should be, see [MiddlePins]: every frame passes through
## them. Opened from the sheet with two frames selected, or from an animation's timeline.

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

## Side of each frame in the preview
const TILE := 72
const PLAYER := 120
## Side of the frame halfway between the keys, to pin
const MIDDLE := 240
## How fast the preview plays when no animation shows the keys, like a new animation
const DEFAULT_FPS := 12.0
## Most movement that can be typed, in pixels
const MAX_MOTION := 4096

var motion_x := SpinBox.new()
var motion_y := SpinBox.new()
var count_spin := SpinBox.new()
var spacing_option := OptionButton.new()
var place_option := OptionButton.new()
var animations_check := CheckBox.new()
## Whether the new frames share the time of the key before them, see
## [method SheetAnimation.insert_between]
var keep_length_check := CheckBox.new()
## How fast the preview plays, as the animation of the keys does
var preview_fps := DEFAULT_FPS
## The keys with the frames between them, in order
var strip := HBoxContainer.new()
## Plays the keys and the frames between them
var player := TextureRect.new()
## The frame halfway between the keys, with the pins every frame passes through. They're
## for these keys and this movement only, so they're cleared when either changes.
var pins_view := MiddlePins.new()
var clear_pins_button := Button.new()

var _sheet: Spritesheet
var _a := Vector2i.ZERO
var _b := Vector2i.ZERO
var _keys: Array[Dictionary] = []
## The frames made for the fields as they are, see [method InBetween.generate]
var _frames: Array[Dictionary] = []
## Counts the frames asked for, so only the last ones are shown
var _passes := 0
## Counts the times the dialog was opened or closed, so the movement found is only used
## for the keys it was found for
var _openings := 0
var _played: Array[ImageTexture] = []
var _play_index := 0
var _timer := Timer.new()
var _motion_row := HBoxContainer.new()
var _motion_label := Label.new()
var _animations_info := Label.new()
## Says how far following every piece got, while it takes a while. Hidden by making it
## clear, so the window keeps its size.
var _working := HBoxContainer.new()
var _progress_bar := ProgressBar.new()
## Where the pieces of the keys went (see [method InBetween.prepare]), by the movement of
## the whole sprite
var _prepared: Dictionary[Vector2i, PieceMorph] = {}
## Preparing for [member _preparing] on a worker thread, or null
var _work: WorkProgress
var _preparing := Vector2i.ZERO
## Whether the movement was typed, so the one found later doesn't replace it
var _motion_edited := false
var _checker := ImageUtils.checker_texture(6)
## The pins [member _frames] were made with
var _frames_pins: Array[Dictionary] = []
## Counts the times the middle frame was asked for, so only the last one is shown
var _middle_passes := 0
## Whether the middle frame is being made while a pin is dragged, and whether the pins
## changed meanwhile, so it's made again once it's done
var _middle_busy := false
var _middle_stale := false


func _init() -> void:
	title = "Generate In-Betweens"
	ok_button_text = "Generate"
	get_ok_button().icon = MainActions.ICONS[&"generate_inbetweens"]
	DialogButtons.apply(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var previews := HBoxContainer.new()
	previews.add_theme_constant_override("separation", 12)
	box.add_child(previews)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(TILE * 5 + 16, PLAYER)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("separation", 4)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(strip)
	previews.add_child(scroll)
	previews.add_child(_framed(player, PLAYER))
	player.tooltip_text = "The keys and the frames between them, played"

	var work := HBoxContainer.new()
	work.add_theme_constant_override("separation", 16)
	box.add_child(work)
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 8)
	work.add_child(middle)
	var pins_tile := _checkered(MIDDLE)
	pins_tile.add_child(pins_view)
	middle.add_child(pins_tile)
	pins_view.tooltip_text = "The frame halfway between the keys"
	var pins_hint := Label.new()
	pins_hint.text = (
		"Click to pin a spot, drag a pin to move it, right-click to take it away. Frames "
		+ "pass through what you pin."
	)
	pins_hint.theme_type_variation = &"StatusLabel"
	pins_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pins_hint.custom_minimum_size.x = MIDDLE
	middle.add_child(pins_hint)
	clear_pins_button.text = "Clear pins"
	clear_pins_button.icon = preload("res://assets/icons/Clear.svg")
	clear_pins_button.tooltip_text = "Take every pin away"
	clear_pins_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	clear_pins_button.disabled = true
	middle.add_child(clear_pins_button)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	work.add_child(settings)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	settings.add_child(grid)

	_motion_label.text = "Movement"
	grid.add_child(_motion_label)
	for spin: SpinBox in [motion_x, motion_y]:
		spin.min_value = -MAX_MOTION
		spin.max_value = MAX_MOTION
		spin.suffix = "px"
		spin.tooltip_text = (
			"How far the sprite moves from the first key to the second, found by lining "
			+ "them up"
		)
		_motion_row.add_child(spin)
	motion_x.prefix = "x"
	motion_y.prefix = "y"
	grid.add_child(_motion_row)

	var count_label := Label.new()
	count_label.text = "Frames"
	grid.add_child(count_label)
	count_spin.min_value = 1
	count_spin.max_value = InBetween.MAX_COUNT
	count_spin.tooltip_text = "How many frames to make between the keys"
	grid.add_child(count_spin)

	var spacing_label := Label.new()
	spacing_label.text = "Spacing"
	grid.add_child(spacing_label)
	for spacing: InBetween.Spacing in InBetween.SPACING_NAMES:
		spacing_option.add_item(InBetween.SPACING_NAMES[spacing], spacing)
	spacing_option.tooltip_text = (
		"How the frames are spread between the keys. Easing in bunches them up near the "
		+ "first key so the sprite starts slowly, easing out near the second so it stops "
		+ "slowly."
	)
	grid.add_child(spacing_option)

	var place_label := Label.new()
	place_label.text = "Place"
	grid.add_child(place_label)
	place_option.tooltip_text = "Where the new frames go in the sheet"
	grid.add_child(place_option)

	animations_check.text = "Add to animations"
	animations_check.tooltip_text = (
		"Play the new frames between the keys wherever an animation plays them one after "
		+ "the other"
	)
	settings.add_child(animations_check)
	_animations_info.theme_type_variation = &"StatusLabel"
	_animations_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_animations_info.custom_minimum_size.x = 240
	settings.add_child(_animations_info)
	keep_length_check.text = "Keep their length"
	keep_length_check.tooltip_text = (
		"The new frames share the time of the key before them, so the animations last as "
		+ "long as before"
	)
	settings.add_child(keep_length_check)
	var working_label := Label.new()
	working_label.text = "Following every piece…"
	working_label.theme_type_variation = &"StatusLabel"
	_working.add_child(working_label)
	_progress_bar.max_value = 1.0
	_progress_bar.step = 0.0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_working.add_child(_progress_bar)
	_working.modulate.a = 0.0
	box.add_child(_working)
	LabelLink.link(_motion_label, motion_x)
	LabelLink.link(count_label, count_spin)
	LabelLink.link(spacing_label, spacing_option)
	LabelLink.link(place_label, place_option)

	_timer.timeout.connect(_play_next)
	add_child(_timer)
	for spin: SpinBox in [motion_x, motion_y]:
		spin.value_changed.connect(
			func(_value: float) -> void:
				_motion_edited = true
				_clear_pins_quietly()
				_generate()
		)
	pins_view.pins_changed.connect(_on_pins_changed)
	clear_pins_button.pressed.connect(pins_view.remove_all)
	count_spin.value_changed.connect(func(_value: float) -> void: _generate())
	spacing_option.item_selected.connect(func(_index: int) -> void: _generate())
	animations_check.toggled.connect(func(on: bool) -> void: keep_length_check.disabled = not on)
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(
		func() -> void:
			if not visible:
				_timer.stop()
				_passes += 1
				_openings += 1
				_middle_passes += 1
				_cancel_preparing()
	)


func _ready() -> void:
	for spin: SpinBox in [motion_x, motion_y, count_spin]:
		SpinScroll.enable(spin)


## Shows frames between keys [param a] and [param b] of [param sheet], with the settings
## used last and the movement found, played at [param fps], or else as fast as an
## animation of the keys plays
func open(sheet: Spritesheet, a: Vector2i, b: Vector2i, fps := 0.0) -> void:
	_sheet = sheet
	_a = a
	_b = b
	_keys = [InBetween.key_of(sheet, a), InBetween.key_of(sheet, b)]
	_frames.clear()
	_prepared.clear()
	pins_view.show_keys(_keys[0], _keys[1])
	_clear_pins_quietly()
	_cancel_preparing()
	preview_fps = fps if fps > 0 else _animation_fps(sheet, a, b)
	_timer.wait_time = 1.0 / preview_fps
	count_spin.set_value_no_signal(Settings.get_value(&"inbetween_count"))
	motion_x.set_value_no_signal(0)
	motion_y.set_value_no_signal(0)
	_motion_edited = false
	var spacing_index := spacing_option.get_item_index(Settings.get_value(&"inbetween_spacing"))
	spacing_option.select(maxi(spacing_index, 0))
	_fill_places()
	var names: PackedStringArray = []
	for animation in sheet.animations:
		if animation.count_between(a, b) > 0:
			names.append(animation.name)
	animations_check.visible = not names.is_empty()
	_animations_info.visible = not names.is_empty()
	animations_check.button_pressed = true
	keep_length_check.visible = not names.is_empty()
	keep_length_check.disabled = false
	keep_length_check.button_pressed = Settings.get_value(&"inbetween_keep_length")
	_animations_info.text = tr("Where these frames play one after the other: %s") % ", ".join(names)
	_show_preview()
	popup_centered()
	# Finding the movement can take a moment with big frames. Until then, frames are made
	# without it.
	_openings += 1
	var opening := _openings
	_generate()
	var motion: Vector2i = await Parallel.run(SpriteMotion.detect.bind(_keys[0], _keys[1]))
	# A movement typed meanwhile stays
	if opening != _openings or _motion_edited:
		return
	motion_x.set_value_no_signal(motion.x)
	motion_y.set_value_no_signal(motion.y)
	# The middle frame moves under the pins
	_clear_pins_quietly()
	_generate()


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


## Makes the frames, and the one halfway between the keys, on worker threads, passing
## through the pins, then shows them
func _generate() -> void:
	_passes += 1
	var pass_number := _passes
	get_ok_button().disabled = true
	var a := _keys[0]
	var b := _keys[1]
	var count := int(count_spin.value)
	var motion := _motion()
	var spacing: InBetween.Spacing = spacing_option.get_selected_id()
	if not _prepared.has(motion) and (_work == null or _preparing != motion):
		_prepare(a, b, motion)
	while not _prepared.has(motion):
		await get_tree().process_frame
		if pass_number != _passes:
			return
	var prepared := _prepared[motion]
	var pins := _pins()
	_middle_passes += 1
	var middle_pass := _middle_passes
	# The middle frame last
	var frames := await Parallel.map(
		count + 1,
		func(i: int) -> Dictionary:
			if i == count:
				return InBetween.middle(prepared, pins)
			return InBetween.generate_one(a, b, i, count, prepared, spacing, pins)
	)
	if middle_pass == _middle_passes:
		pins_view.show_frame(frames[count])
	if pass_number != _passes:
		return
	frames.resize(count)
	_frames.assign(frames)
	_frames_pins = pins
	_show_preview()
	get_ok_button().disabled = false


## Remakes only the middle frame with the pins as they are, while one is dragged, on a
## worker thread. While it's being made, the pins only change what's made next.
func _refresh_middle() -> void:
	if _middle_busy:
		_middle_stale = true
		return
	_middle_busy = true
	_middle_stale = true
	while _middle_stale and _prepared.has(_motion()):
		_middle_stale = false
		_middle_passes += 1
		var middle_pass := _middle_passes
		var frame: Dictionary = await Parallel.run(
			InBetween.middle.bind(_prepared[_motion()], _pins())
		)
		if middle_pass == _middle_passes:
			pins_view.show_frame(frame)
	_middle_busy = false


## The pins as they are, to make frames with
func _pins() -> Array[Dictionary]:
	return pins_view.pins.duplicate(true)


## The movement typed or found, see [method InBetween.prepare]
func _motion() -> Vector2i:
	return Vector2i(int(motion_x.value), int(motion_y.value))


## Remakes the middle frame while a pin is dragged, and every frame once it's let go
func _on_pins_changed(done: bool) -> void:
	clear_pins_button.disabled = pins_view.pins.is_empty()
	if done:
		_generate()
	else:
		_refresh_middle()


## Takes the pins away without remaking the frames, when they no longer fit the middle
## frame
func _clear_pins_quietly() -> void:
	pins_view.remove_all(false)
	clear_pins_button.disabled = true


## Prepares keys [param a] and [param b] with the whole sprite moving by [param motion]
## (see [member _prepared]) on a worker thread, showing how far it got, instead of
## anything else
func _prepare(a: Dictionary, b: Dictionary, motion: Vector2i) -> void:
	_cancel_preparing()
	var work := WorkProgress.new()
	_work = work
	_preparing = motion
	_progress_bar.value = 0.0
	_working.modulate.a = 1.0
	var found := await Parallel.map(
		1,
		func(_i: int) -> PieceMorph: return InBetween.prepare(a, b, motion, work),
		func(_done: int, _total: int) -> void: _progress_bar.value = work.get_ratio()
	)
	if work.cancelled:
		return
	_prepared[motion] = found[0]
	_work = null
	_working.modulate.a = 0.0


## Stops preparing, see [method _prepare]
func _cancel_preparing() -> void:
	if _work:
		_work.cancelled = true
		_work = null
	_working.modulate.a = 0.0


## Shows the keys with the frames between them where they're placed, all alike
func _show_preview() -> void:
	var shown: Array[Dictionary] = [_keys[0]]
	shown.append_array(_frames)
	shown.append(_keys[1])
	var area := Rect2i()
	for i in shown.size():
		var rect := Rect2i(shown[i].origin, (shown[i].image as Image).get_size())
		area = rect if i == 0 else area.merge(rect)
	_played.clear()
	for frame in shown:
		var canvas := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
		var img: Image = frame.image
		canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), frame.origin - area.position)
		_played.append(ImageTexture.create_from_image(canvas))
	for child in strip.get_children():
		strip.remove_child(child)
		child.queue_free()
	for i in _played.size():
		var picture := TextureRect.new()
		picture.texture = _played[i]
		var tile := _framed(picture, TILE)
		var is_key := i == 0 or i == _played.size() - 1
		tile.tooltip_text = tr("Key frame") if is_key else tr("In-between %d") % i
		strip.add_child(tile)
	_play_index = 0
	player.texture = _played[0]
	_timer.start()


## [param picture] on a checkerboard, [param side] wide and tall, scaled to fit without
## blurring
func _framed(picture: TextureRect, side: int) -> Control:
	var tile := _checkered(side)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_PASS
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(picture)
	return tile


## A checkerboard [param side] wide and tall
func _checkered(side: int) -> Control:
	var tile := TextureRect.new()
	tile.texture = _checker
	tile.stretch_mode = TextureRect.STRETCH_TILE
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.custom_minimum_size = Vector2(side, side)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tile


func _play_next() -> void:
	if _played.is_empty():
		return
	_play_index = (_play_index + 1) % _played.size()
	player.texture = _played[_play_index]


func _on_confirmed() -> void:
	if _frames.is_empty():
		return
	var place := place_option.get_selected_id()
	Settings.set_value(&"inbetween_count", int(count_spin.value))
	Settings.set_value(&"inbetween_place", place)
	Settings.set_value(&"inbetween_spacing", spacing_option.get_selected_id())
	var to_animations := animations_check.visible and animations_check.button_pressed
	if to_animations:
		Settings.set_value(&"inbetween_keep_length", keep_length_check.button_pressed)
	var keep_length := to_animations and keep_length_check.button_pressed
	inbetweens_chosen.emit(_a, _b, _frames.duplicate(), place, to_animations, keep_length)
