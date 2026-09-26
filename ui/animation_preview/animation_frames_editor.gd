class_name AnimationFramesEditor
extends ConfirmationDialog
## Puts an animation's frames together by hand: sprites are dragged (or double-clicked)
## from the sheet into a timeline, where they're dragged to reorder and each gets how long
## it's shown. Applying gives the frames as text, like the Frames field of the Animations
## window, with [signal frames_chosen].

## The frames as typed in the Frames field, e.g. "idle, 3-5, 6*2"
signal frames_chosen(text: String)

const THUMBNAIL_SIZE := 56
const REMOVE_ICON := preload("res://assets/icons/Close.svg")

var sheet: Spritesheet
## Sprites of the sheet, to drag into the timeline
var palette := HFlowContainer.new()
## The frames in playing order
var timeline := HFlowContainer.new()
var player := FramePlayer.new()
var info := Label.new()
var clear_button := Button.new()

## The frames in playing order, each [code]{"cell": Vector2i, "duration": float}[/code]
var _frames: Array[Dictionary] = []
## Names that stand for frame numbers, by number, see [method SheetAnimation.format_numbers]
var _labels := {}
var _textures: Dictionary[Image, ImageTexture] = {}


func _init() -> void:
	title = "Edit Frames"
	ok_button_text = "Apply"
	min_size = Vector2i(820, 580)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 12)
	layout.add_child(top)
	var sprites := VBoxContainer.new()
	sprites.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sprites)
	sprites.add_child(_heading("Sprites", "Drag them into the frames below, or double-click"))
	sprites.add_child(_scroll(palette))
	player.custom_minimum_size = Vector2(240, 240)
	top.add_child(player)

	var frames_header := HBoxContainer.new()
	var frames_heading := _heading(
		"Frames", "Drag to reorder. The number is how long each is shown."
	)
	frames_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_header.add_child(frames_heading)
	info.theme_type_variation = &"StatusLabel"
	frames_header.add_child(info)
	clear_button.text = "Clear"
	clear_button.tooltip_text = "Remove every frame"
	clear_button.pressed.connect(
		func() -> void:
			_frames.clear()
			_rebuild_timeline()
	)
	frames_header.add_child(clear_button)
	layout.add_child(frames_header)
	var timeline_scroll := _scroll(timeline)
	timeline_scroll.custom_minimum_size = Vector2(0, 190)
	timeline_scroll.size_flags_vertical = Control.SIZE_FILL
	layout.add_child(timeline_scroll)
	# Frames can be dropped anywhere in the timeline, also after the last one
	timeline.set_drag_forwarding(Callable(), _can_drop_at.bind(null), _drop_at.bind(null))
	confirmed.connect(func() -> void: frames_chosen.emit(get_frames_text()))


## Shows [param cells] of [param frames_sheet] shown [param durations] long, playing at
## [param fps] as [param play_mode]. Numbers in [param labels] are shown as their names.
func open(
	frames_sheet: Spritesheet,
	cells: Array[Vector2i],
	durations: Array[float],
	fps: float,
	play_mode: SheetAnimation.Mode,
	labels := {},
) -> void:
	sheet = frames_sheet
	_labels = labels
	_frames.clear()
	for i in cells.size():
		_frames.append(
			{"cell": cells[i], "duration": durations[i] if i < durations.size() else 1.0}
		)
	player.sheet = sheet
	player.fps = fps
	player.mode = play_mode
	_build_palette()
	_rebuild_timeline()
	popup_centered()


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
	_update_player()


## A frame in the timeline: its picture, number or name, how long it's shown and a button
## to take it out
func _card(index: int) -> Control:
	var cell: Vector2i = _frames[index].cell
	var card := PanelContainer.new()
	card.theme_type_variation = &"PreviewOverlay"
	card.tooltip_text = tr("Frame %d of the animation") % (index + 1)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var thumbnail := TextureRect.new()
	thumbnail.texture = _thumbnail(cell)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.custom_minimum_size = Vector2.ONE * THUMBNAIL_SIZE
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumbnail)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = _label(cell)
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var remove := Button.new()
	remove.icon = REMOVE_ICON
	remove.flat = true
	remove.tooltip_text = "Take the frame out"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(remove_frame.bind(index))
	row.add_child(remove)
	box.add_child(row)
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


func _can_drop_at(_at: Vector2, data: Variant, _over: Control) -> bool:
	return data is Dictionary and (data.has("cell") or data.has("index"))


## Puts dropped sprites, or moved frames, where they were dropped
func _drop_at(at: Vector2, data: Variant, over: Control) -> void:
	if over:
		at += over.position
	var index := _insert_index(at)
	if data.has("cell"):
		insert_frame(data.cell, index)
	else:
		move_frame(data.index, index)


## Where a frame dropped at [param at] in the timeline goes: before the first frame it's
## left of or above
func _insert_index(at: Vector2) -> int:
	var cards := timeline.get_children()
	for i in cards.size():
		var rect := (cards[i] as Control).get_rect()
		if at.y < rect.position.y or (at.y <= rect.end.y and at.x < rect.get_center().x):
			return i
	return cards.size()


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
	clear_button.disabled = _frames.is_empty()


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


func _drag_preview(cell: Vector2i) -> Control:
	var preview := TextureRect.new()
	preview.texture = _thumbnail(cell)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2.ONE * THUMBNAIL_SIZE
	preview.modulate.a = 0.8
	return preview


static func _heading(text: String, tooltip: String) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.theme_type_variation = &"HeaderSmall"
	return label


static func _scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("h_separation", 6)
	content.add_theme_constant_override("v_separation", 6)
	scroll.add_child(content)
	return scroll
