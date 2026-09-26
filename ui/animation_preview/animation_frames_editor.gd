class_name AnimationFramesEditor
extends Window
## Puts an animation's frames together by hand: sprites are dragged (or double-clicked)
## from the sheet into a timeline, where they're dragged or moved with their arrows, and
## each gets how long it's shown. Applying gives the frames as text, like the Frames field
## of the Animations window, with [signal frames_chosen]. Closing with changes asks first:
## a plain window rather than a dialog, since dialogs close before they can ask.

## The frames as typed in the Frames field, e.g. "idle, 3-5, 6*2"
signal frames_chosen(text: String)

const THUMBNAIL_SIZE := 56
const REMOVE_ICON := preload("res://assets/icons/Close.svg")
const LEFT_ICON := preload("res://assets/icons/PagePrevious.svg")
const RIGHT_ICON := preload("res://assets/icons/PageNext.svg")
const APPLY_ICON := preload("res://assets/icons/Save.svg")
const MARKER_WIDTH := 3.0

var sheet: Spritesheet
## Sprites of the sheet, to drag into the timeline
var palette := HFlowContainer.new()
## The frames in playing order, left to right
var timeline := HBoxContainer.new()
var player := FramePlayer.new()
var info := Label.new()
var ok_button := Button.new()
var cancel_button := Button.new()
## Asks before closing with changes
var discard_dialog := ConfirmationDialog.new()

## The frames in playing order, each [code]{"cell": Vector2i, "duration": float}[/code]
var _frames: Array[Dictionary] = []
## The frames when opened, to tell whether they changed
var _opened_with: Array[Dictionary] = []
## Names that stand for frame numbers, by number, see [method SheetAnimation.format_numbers]
var _labels := {}
var _textures: Dictionary[Image, ImageTexture] = {}
## Where a dragged frame would go
var _marker := ColorRect.new()
var _empty_hint := Label.new()


func _init() -> void:
	visible = false
	transient = true
	exclusive = true
	wrap_controls = true
	min_size = Vector2i(820, 580)
	# Looks like a dialog: its panel, and its buttons spread along the bottom
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	background.add_child(content)
	var layout := VBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	content.add_child(layout)
	var buttons := HBoxContainer.new()
	for button: Button in [null, ok_button, null, cancel_button, null]:
		if button == null:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			buttons.add_child(spacer)
			continue
		button.custom_minimum_size.x = 80
		buttons.add_child(button)
	ok_button.text = "Apply"
	ok_button.icon = APPLY_ICON
	cancel_button.text = "Cancel"
	content.add_child(buttons)

	# The sheet's sprites and the preview above, the timeline below
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 12)
	layout.add_child(top)
	var sprites := PanelContainer.new()
	sprites.theme_type_variation = &"EditorSection"
	sprites.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprites.tooltip_text = "Drag sprites into the timeline below, or double-click them"
	sprites.add_child(_scroll(palette, false))
	palette.add_theme_constant_override("h_separation", 6)
	palette.add_theme_constant_override("v_separation", 6)
	top.add_child(sprites)
	var side := VBoxContainer.new()
	player.custom_minimum_size = Vector2(240, 240)
	player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(player)
	info.theme_type_variation = &"StatusLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(info)
	top.add_child(side)

	var strip := PanelContainer.new()
	strip.theme_type_variation = &"TimelinePanel"
	strip.custom_minimum_size = Vector2(0, 190)
	strip.add_child(_scroll(timeline, true))
	timeline.add_theme_constant_override("separation", 8)
	_empty_hint.text = "Drag sprites here, or double-click them"
	_empty_hint.theme_type_variation = &"StatusLabel"
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_empty_hint)
	layout.add_child(strip)
	# Frames can be dropped anywhere in the timeline, also after the last one
	timeline.set_drag_forwarding(Callable(), _can_drop_at.bind(null), _drop_at.bind(null))
	strip.set_drag_forwarding(Callable(), _can_drop_at.bind(strip), _drop_at.bind(strip))

	_marker.top_level = true
	_marker.visible = false
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_marker)

	discard_dialog.title = "Discard changes"
	discard_dialog.dialog_text = "The frames changed. Discard the changes?"
	discard_dialog.ok_button_text = "Discard"
	discard_dialog.cancel_button_text = "Keep Editing"
	discard_dialog.confirmed.connect(hide)
	add_child(discard_dialog)
	ok_button.pressed.connect(
		func() -> void:
			hide()
			frames_chosen.emit(get_frames_text())
	)
	cancel_button.pressed.connect(request_close)
	close_requested.connect(request_close)
	window_input.connect(
		func(event: InputEvent) -> void:
			if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
				request_close()
	)
	background.ready.connect(
		func() -> void:
			background.add_theme_stylebox_override(
				"panel", background.get_theme_stylebox("panel", "AcceptDialog")
			)
	)


func _ready() -> void:
	_marker.color = Settings.get_value(&"accent_color")


func get_ok_button() -> Button:
	return ok_button


func get_cancel_button() -> Button:
	return cancel_button


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_marker.visible = false


## Shows [param cells] of [param frames_sheet] shown [param durations] long, playing at
## [param fps] as [param play_mode], for the animation [param animation_name]. Numbers in
## [param labels] are shown as their names.
func open(
	frames_sheet: Spritesheet,
	cells: Array[Vector2i],
	durations: Array[float],
	fps: float,
	play_mode: SheetAnimation.Mode,
	labels := {},
	animation_name := "",
) -> void:
	sheet = frames_sheet
	title = tr("Edit Animation - %s") % animation_name if animation_name else tr("Edit Animation")
	_labels = labels
	_frames.clear()
	for i in cells.size():
		_frames.append(
			{"cell": cells[i], "duration": durations[i] if i < durations.size() else 1.0}
		)
	_opened_with = _frames.duplicate(true)
	player.sheet = sheet
	player.fps = fps
	player.mode = play_mode
	_build_palette()
	_rebuild_timeline()
	popup_centered()


## Whether the frames changed since opening
func has_changes() -> bool:
	return _frames != _opened_with


## The frames as typed in the Frames field
func get_frames_text() -> String:
	var start: int = Settings.get_value(&"index_start")
	var numbers: Array[int] = []
	var durations: Array[float] = []
	for frame in _frames:
		numbers.append(sheet.index_of(frame.cell) + start)
		durations.append(frame.duration)
	return SheetAnimation.format_numbers(numbers, durations, _labels)


## The frames in playing order, see [member _frames]
func get_frames() -> Array[Dictionary]:
	return _frames.duplicate(true)


## Adds [param cell] at [param index] of the frames, or at the end
func insert_frame(cell: Vector2i, index := -1) -> void:
	var frame := {"cell": cell, "duration": 1.0}
	if index < 0 or index >= _frames.size():
		_frames.append(frame)
	else:
		_frames.insert(index, frame)
	_rebuild_timeline()


## Moves the frame at [param from] to [param to], as counted before moving it
func move_frame(from: int, to: int) -> void:
	var frame: Dictionary = _frames.pop_at(from)
	_frames.insert(to - 1 if to > from else to, frame)
	_rebuild_timeline()


func remove_frame(index: int) -> void:
	_frames.remove_at(index)
	_rebuild_timeline()


func set_duration(index: int, duration: float) -> void:
	_frames[index].duration = duration
	_update_player()


## Closes, or with changes first asks whether to discard them
func request_close() -> void:
	if discard_dialog.visible:
		return
	if has_changes():
		discard_dialog.popup_centered()
	else:
		hide()


func _build_palette() -> void:
	for child in palette.get_children():
		child.queue_free()
	for cell in sheet.get_sorted_coords():
		var button := Button.new()
		button.icon = _thumbnail(cell)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text = _label(cell)
		button.clip_text = true
		button.custom_minimum_size = Vector2(THUMBNAIL_SIZE + 8, THUMBNAIL_SIZE + 26)
		button.tooltip_text = sheet.frames[cell].resource_name.get_basename()
		button.focus_mode = Control.FOCUS_NONE
		button.gui_input.connect(
			func(event: InputEvent) -> void:
				var click := event as InputEventMouseButton
				if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
					insert_frame(cell)
		)
		button.set_drag_forwarding(
			func(_at: Vector2) -> Variant:
				button.set_drag_preview(_drag_preview(cell))
				return {"cell": cell},
			Callable(),
			Callable()
		)
		palette.add_child(button)


func _rebuild_timeline() -> void:
	for child in timeline.get_children():
		timeline.remove_child(child)
		child.queue_free()
	for i in _frames.size():
		timeline.add_child(_card(i))
	_empty_hint.visible = _frames.is_empty()
	_update_player()


## A frame in the timeline: buttons to move it and take it out, its picture, number or
## name, and how long it's shown
func _card(index: int) -> Control:
	var cell: Vector2i = _frames[index].cell
	var card := PanelContainer.new()
	card.theme_type_variation = &"TimelineFrame"
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.tooltip_text = tr("Frame %d of the animation. Drag it to move it.") % (index + 1)
	card.mouse_entered.connect(func() -> void: card.theme_type_variation = &"TimelineFrameHover")
	card.mouse_exited.connect(func() -> void: card.theme_type_variation = &"TimelineFrame")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	var left := _small_button(LEFT_ICON, "Move left")
	left.disabled = index == 0
	left.pressed.connect(move_frame.bind(index, index - 1))
	buttons.add_child(left)
	var right := _small_button(RIGHT_ICON, "Move right")
	right.disabled = index == _frames.size() - 1
	right.pressed.connect(move_frame.bind(index, index + 2))
	buttons.add_child(right)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(gap)
	var remove := _small_button(REMOVE_ICON, "Take the frame out")
	remove.pressed.connect(remove_frame.bind(index))
	buttons.add_child(remove)
	box.add_child(buttons)

	var thumbnail := TextureRect.new()
	thumbnail.texture = _thumbnail(cell)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.custom_minimum_size = Vector2.ONE * THUMBNAIL_SIZE
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumbnail)
	var label := Label.new()
	label.text = _label(cell)
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 76
	box.add_child(label)
	var duration := SpinBox.new()
	duration.min_value = 0.25
	duration.max_value = 100
	duration.step = 0.25
	duration.suffix = "×"
	duration.value = _frames[index].duration
	duration.select_all_on_focus = true
	duration.custom_minimum_size.x = 76
	duration.tooltip_text = "How long it's shown: 2 is twice as long as a frame"
	duration.value_changed.connect(func(value: float) -> void: set_duration(index, value))
	box.add_child(duration)
	card.set_drag_forwarding(
		func(_at: Vector2) -> Variant:
			card.set_drag_preview(_drag_preview(cell))
			return {"index": index},
		_can_drop_at.bind(card),
		_drop_at.bind(card)
	)
	return card


## Accepts sprites and frames, and shows where they'd go
func _can_drop_at(at: Vector2, data: Variant, over: Control) -> bool:
	if not (data is Dictionary and (data.has("cell") or data.has("index"))):
		return false
	_show_marker(_insert_index(_to_timeline(at, over)))
	return true


## Puts dropped sprites, or moved frames, where they were dropped
func _drop_at(at: Vector2, data: Variant, over: Control) -> void:
	_marker.visible = false
	var index := _insert_index(_to_timeline(at, over))
	if data.has("cell"):
		insert_frame(data.cell, index)
	else:
		move_frame(data.index, index)


## [param at] in [param over] (the timeline when null) in the timeline's coordinates
func _to_timeline(at: Vector2, over: Control) -> Vector2:
	if over == null:
		return at
	return at + over.global_position - timeline.global_position


## Where a frame dropped at [param at] in the timeline goes: before the first frame whose
## middle is right of it
func _insert_index(at: Vector2) -> int:
	var cards := timeline.get_children()
	for i in cards.size():
		if at.x < (cards[i] as Control).get_rect().get_center().x:
			return i
	return cards.size()


## A line between the frames where one dropped now would go
func _show_marker(index: int) -> void:
	var cards := timeline.get_children()
	var gap := float(timeline.get_theme_constant(&"separation"))
	var rect := timeline.get_global_rect()
	var x := rect.position.x
	if index < cards.size():
		x = (cards[index] as Control).global_position.x - gap / 2
	elif not cards.is_empty():
		x = (cards[-1] as Control).get_global_rect().end.x + gap / 2
	var height := rect.size.y if cards.is_empty() else (cards[0] as Control).size.y
	_marker.global_position = Vector2(x - MARKER_WIDTH / 2, rect.position.y)
	_marker.size = Vector2(MARKER_WIDTH, height)
	_marker.visible = true


func _update_player() -> void:
	var cells: Array[Vector2i] = []
	var durations: Array[float] = []
	for frame in _frames:
		cells.append(frame.cell)
		durations.append(frame.duration)
	player.set_cells(cells, durations)
	var total := 0.0
	for duration in durations:
		total += duration
	info.text = tr("%d frames, %.2f s") % [_frames.size(), total / maxf(player.fps, 0.01)]


## The frame's name when it stands for it, else its number
func _label(cell: Vector2i) -> String:
	var number: int = sheet.index_of(cell) + Settings.get_value(&"index_start")
	return _labels.get(number, str(number))


func _thumbnail(cell: Vector2i) -> Texture2D:
	if not sheet.has_frame(cell):
		return null
	var img := sheet.frames[cell]
	if not _textures.has(img):
		_textures[img] = ImageTexture.create_from_image(img)
	return _textures[img]


## What follows the mouse while dragging: the sprite on a frame's card
func _drag_preview(cell: Vector2i) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"TimelineFrameHover"
	card.modulate.a = 0.85
	var picture := TextureRect.new()
	picture.texture = _thumbnail(cell)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2.ONE * THUMBNAIL_SIZE
	card.add_child(picture)
	# Held by the middle, a little off so the drop marker stays visible
	var holder := Control.new()
	holder.add_child(card)
	card.position = -Vector2.ONE * THUMBNAIL_SIZE / 2 + Vector2(8, 8)
	return holder


static func _small_button(icon: Texture2D, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = icon
	button.flat = true
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_constant_override("icon_max_width", 12)
	return button


static func _scroll(content: Control, horizontal: bool) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if horizontal:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll
