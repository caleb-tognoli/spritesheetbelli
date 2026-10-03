class_name AnimationTimeline
extends PanelContainer
## An animation's frames in playing order, left to right, as [TimelineTile]s: each with
## its picture, a short label and how long it's shown. Frames
## are dragged to reorder them (Alt+drag copies them), taken out with × or Delete, picked
## by clicking (Ctrl and Shift pick more) or with a box, and added by dropping frames of
## the sheet on it, see [method frames_drag_data]. Changes aren't made here but sent with
## [signal frames_edited], so each is one undoable step.

## The frames should become [param cells], shown [param durations] long, as the step
## [param action_name]
signal frames_edited(action_name: String, cells: Array[Vector2i], durations: Array[float])

## Sides of the pictures, which follow the height given with [method fit_height]
const MIN_PICTURE := 24
const MAX_PICTURE := 128
const MARKER_WIDTH := 3.0
## How near either end dragging scrolls, and how fast, in pixels per second
const SCROLL_MARGIN := 32.0
const SCROLL_SPEED := 900.0
## The kind of drag data of frames of the sheet, see [method frames_drag_data]
const FRAMES_DRAG := "sheet_frames"
## The kind of drag data of frames moved within a timeline
const TIMELINE_DRAG := "timeline_frames"

var sheet: Spritesheet
var scroll := ScrollContainer.new()
## The tiles, in playing order
var row := HBoxContainer.new()
var empty_hint := Label.new()

var _cells: Array[Vector2i] = []
## How long each of [member _cells] is shown, one for each
var _durations: Array[float] = []
var _selected: Dictionary[int, bool] = {}
## Where Shift+click picks from
var _anchor := -1
## A selected tile pressed without Ctrl or Shift, picked alone on release unless dragged
var _pressed_selected := -1
var _picture_size := MIN_PICTURE
var _available_height := 0.0
var _textures: Dictionary[Image, ImageTexture] = {}
## Draws where dropped frames would go and the selection box, over the tiles
var _overlay := Control.new()
## Measures the height of a tile around its picture
var _probe := TimelineTile.new()
## Where dropped frames would go, or -1
var _drop_index := -1
var _boxing := false
## The selection when the box started, which it adds to with Ctrl or Shift
var _box_base: Dictionary[int, bool] = {}
## Where the box started in [member row], so it scrolls with the tiles, and where it ends
var _box_start := Vector2.ZERO
var _box_end := Vector2.ZERO


func _init() -> void:
	theme_type_variation = &"TimelinePanel"
	focus_mode = Control.FOCUS_ALL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	# Tabbing through the durations shows each
	scroll.follow_focus = true
	add_child(scroll)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(row)
	empty_hint.text = "Drag frames here from the sheet or the Sprites panel"
	empty_hint.theme_type_variation = &"StatusLabel"
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(empty_hint)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.clip_contents = true
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_probe.visible = false
	_overlay.add_child(_probe)

	row.gui_input.connect(_on_row_input)
	# Frames can be dropped anywhere, also after the last one
	for target: Control in [self, scroll, row]:
		target.set_drag_forwarding(Callable(), _can_drop.bind(target), _drop.bind(target))
	resized.connect(_apply_picture_size)
	Settings.changed.connect(_on_setting_changed)
	set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			set_process(true)
		NOTIFICATION_DRAG_END:
			_drop_index = -1
			_overlay.queue_redraw()
		NOTIFICATION_THEME_CHANGED:
			_apply_picture_size.call_deferred()


## Shows [param cells] of [param frames_sheet] in playing order, shown [param durations]
## long (missing ones are 1). What's picked stays picked.
func show_frames(
	frames_sheet: Spritesheet, cells: Array[Vector2i], durations: Array[float] = []
) -> void:
	sheet = frames_sheet
	_cells = cells.duplicate()
	_durations.clear()
	for i in _cells.size():
		_durations.append(durations[i] if i < durations.size() else 1.0)
	for i: int in _selected.keys():
		if i >= _cells.size():
			_selected.erase(i)
	if _anchor >= _cells.size():
		_anchor = -1
	_update_tiles()


## The cells shown, in playing order
func get_cells() -> Array[Vector2i]:
	return _cells.duplicate()


## How long each frame is shown, one for each of [method get_cells]
func get_durations() -> Array[float]:
	return _durations.duplicate()


## The tile of the frame at [param index]
func get_tile(index: int) -> TimelineTile:
	return row.get_child(index) as TimelineTile


## Gives the timeline [param height] pixels: the pictures get what's left of it around
## them, within [constant MIN_PICTURE] and [constant MAX_PICTURE]
func fit_height(height: float) -> void:
	_available_height = height
	_apply_picture_size()


func get_picture_size() -> int:
	return _picture_size


#region Picking


## The picked frames, in playing order
func get_selected() -> Array[int]:
	var indices: Array[int] = []
	indices.assign(_selected.keys())
	indices.sort()
	return indices


## Picks the frames at [param indices] only
func select(indices: Array[int]) -> void:
	_selected.clear()
	for i in indices:
		if i >= 0 and i < _cells.size():
			_selected[i] = true
	_show_selection()


func select_all() -> void:
	var every: Array[int] = []
	every.assign(range(_cells.size()))
	select(every)


#endregion

#region Changes


## Adds [param cells] at [param at] of the frames, or after the last with -1, and picks
## them
func insert_cells(cells: Array[Vector2i], at := -1) -> void:
	if cells.is_empty():
		return
	if at < 0 or at > _cells.size():
		at = _cells.size()
	var new_cells := _cells.duplicate()
	var new_durations := _durations.duplicate()
	for i in cells.size():
		new_cells.insert(at + i, cells[i])
		new_durations.insert(at + i, 1.0)
	_selected.clear()
	for i in cells.size():
		_selected[at + i] = true
	_anchor = at
	frames_edited.emit(L10n.mark("Add frames"), new_cells, new_durations)


## Moves the frames at [param indices] to [param to], counted before moving them, keeping
## their order, and picks them
func move_frames(indices: Array[int], to: int) -> void:
	var moving := _valid_indices(indices)
	if moving.is_empty():
		return
	to = clampi(to, 0, _cells.size())
	var new_cells: Array[Vector2i] = []
	var new_durations: Array[float] = []
	var at := to
	for i in _cells.size():
		if i in moving:
			if i < to:
				at -= 1
			continue
		new_cells.append(_cells[i])
		new_durations.append(_durations[i])
	for i in moving.size():
		new_cells.insert(at + i, _cells[moving[i]])
		new_durations.insert(at + i, _durations[moving[i]])
	_selected.clear()
	for i in moving.size():
		_selected[at + i] = true
	_anchor = at
	if new_cells == _cells and new_durations == _durations:
		_show_selection()
		return
	frames_edited.emit(L10n.mark("Move frames"), new_cells, new_durations)


## Puts copies of the frames at [param indices] at [param to], keeping their order and how
## long they're shown, and picks the copies
func copy_frames(indices: Array[int], to: int) -> void:
	var copying := _valid_indices(indices)
	if copying.is_empty():
		return
	to = clampi(to, 0, _cells.size())
	var new_cells := _cells.duplicate()
	var new_durations := _durations.duplicate()
	for i in copying.size():
		new_cells.insert(to + i, _cells[copying[i]])
		new_durations.insert(to + i, _durations[copying[i]])
	_selected.clear()
	for i in copying.size():
		_selected[to + i] = true
	_anchor = to
	frames_edited.emit(L10n.mark("Duplicate frames"), new_cells, new_durations)


## Takes the frames at [param indices] out
func remove_frames(indices: Array[int]) -> void:
	var removing := _valid_indices(indices)
	if removing.is_empty():
		return
	var new_cells: Array[Vector2i] = []
	var new_durations: Array[float] = []
	for i in _cells.size():
		if i not in removing:
			new_cells.append(_cells[i])
			new_durations.append(_durations[i])
	_selected.clear()
	_anchor = -1
	frames_edited.emit(L10n.mark("Remove frames"), new_cells, new_durations)


## Shows the frame at [param index] [param duration] frames long
func set_duration(index: int, duration: float) -> void:
	if index < 0 or index >= _cells.size() or is_equal_approx(_durations[index], duration):
		return
	var new_durations := _durations.duplicate()
	new_durations[index] = duration
	frames_edited.emit(L10n.mark("Frame duration"), _cells.duplicate(), new_durations)


#endregion

#region Labels


## Short labels for frames named [param names]: without the start they all have in
## common, cut after a separator or where letters and digits meet, so walk_01 to walk_12
## are 01 to 12. Names that would be left empty keep it all, and so does a single name.
## Empty names stay empty.
static func short_labels(names: PackedStringArray) -> PackedStringArray:
	var distinct: PackedStringArray = []
	for frame_name in names:
		if frame_name and frame_name not in distinct:
			distinct.append(frame_name)
	var cut := 0
	if distinct.size() > 1:
		cut = distinct[0].length()
		for frame_name in distinct:
			var length := 0
			while (
				length < mini(cut, frame_name.length())
				and frame_name[length] == distinct[0][length]
			):
				length += 1
			cut = length
		while cut > 0 and not _cuts_all_cleanly(distinct, cut):
			cut -= 1
	var labels: PackedStringArray = []
	for frame_name in names:
		labels.append(frame_name.substr(cut))
	return labels


## [param text] as long as fits in [param width] pixels in [param font], cut at its end
## with an ellipsis. Never cut at its start.
static func fit_text(text: String, font: Font, font_size: int, width: float) -> String:
	var width_of := func(shown: String) -> float:
		return font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width_of.call(text) <= width:
		return text
	var length := text.length() - 1
	while length > 1 and width_of.call(text.left(length) + "…") > width:
		length -= 1
	return text.left(length) + "…"


static func _cuts_all_cleanly(names: PackedStringArray, at: int) -> bool:
	for frame_name in names:
		if not _cuts_cleanly(frame_name, at):
			return false
	return true


## Whether [param frame_name] cut after [param at] characters leaves something readable:
## the cut is after a separator, or where letters and digits meet
static func _cuts_cleanly(frame_name: String, at: int) -> bool:
	if at >= frame_name.length():
		return false
	var before := frame_name[at - 1]
	var after := frame_name[at]
	if not _is_word_character(before):
		return true
	return _is_word_character(after) and before.is_valid_int() != after.is_valid_int()


static func _is_word_character(character: String) -> bool:
	return character.is_valid_int() or character.to_lower() != character.to_upper()


#endregion

#region Dragging


## Drag data of [param cells] of the sheet, in the order they're added when dropped on a
## timeline
static func frames_drag_data(cells: Array[Vector2i]) -> Dictionary:
	return {"type": FRAMES_DRAG, "cells": cells.duplicate()}


## Whether [param data] is frames of the sheet being dragged, see [method frames_drag_data]
static func is_frames_drag(data: Variant) -> bool:
	return (
		data is Dictionary
		and data.get("type") == FRAMES_DRAG
		and not data.get("cells", []).is_empty()
	)


## What follows the mouse while dragging [param cells] of [param frames_sheet]: the first
## few pictures fanned out, with how many there are
static func drag_preview(frames_sheet: Spritesheet, cells: Array[Vector2i]) -> Control:
	var holder := Control.new()
	holder.modulate.a = 0.85
	var shown := cells.filter(frames_sheet.has_frame).slice(0, 3)
	shown.reverse()
	for i in shown.size():
		var card := PanelContainer.new()
		card.theme_type_variation = &"TimelineFrameHover"
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(frames_sheet.frames[shown[i]])
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.custom_minimum_size = Vector2.ONE * 48
		card.add_child(picture)
		# Held by the middle, a little off so the drop marker stays visible
		card.position = Vector2(-16, -16) + Vector2.ONE * 6 * (shown.size() - 1 - i)
		holder.add_child(card)
	if cells.size() > 1:
		var count := Label.new()
		count.theme_type_variation = &"TimelineBadge"
		count.text = str(cells.size())
		count.position = Vector2(-20, -20)
		holder.add_child(count)
	return holder


func _get_tile_drag(_at: Vector2, tile: TimelineTile) -> Variant:
	_pressed_selected = -1
	if not _selected.has(tile.index):
		select([tile.index] as Array[int])
		_anchor = tile.index
	var indices := get_selected()
	var cells: Array[Vector2i] = []
	for i in indices:
		cells.append(_cells[i])
	tile.set_drag_preview(drag_preview(sheet, cells))
	return {"type": TIMELINE_DRAG, "indices": indices, "timeline": get_instance_id()}


## Accepts frames of the sheet and of this timeline, and shows where they'd go
func _can_drop(at: Vector2, data: Variant, over: Control) -> bool:
	if not _accepts(data):
		return false
	_drop_index = _insert_index(_to_row(at, over).x)
	_overlay.queue_redraw()
	return true


## Adds dropped frames of the sheet, or moves frames of this timeline where dropped, or
## copies them there with Alt
func _drop(at: Vector2, data: Variant, over: Control) -> void:
	var index := _insert_index(_to_row(at, over).x)
	_drop_index = -1
	_overlay.queue_redraw()
	if data.type == FRAMES_DRAG:
		var cells: Array[Vector2i] = []
		cells.assign(data.cells)
		insert_cells(cells, index)
	elif Input.is_key_pressed(KEY_ALT):
		copy_frames(data.indices, index)
	else:
		move_frames(data.indices, index)
	grab_focus()


func _accepts(data: Variant) -> bool:
	if not data is Dictionary or sheet == null:
		return false
	match data.get("type"):
		FRAMES_DRAG:
			return not data.get("cells", []).is_empty()
		TIMELINE_DRAG:
			return data.get("timeline") == get_instance_id()
	return false


## [param at] in [param over] in the coordinates of [member row]
func _to_row(at: Vector2, over: Control) -> Vector2:
	var global := over.get_global_transform() * at
	return row.get_global_transform().affine_inverse() * global


## Where frames dropped at [param x] in [member row] go: before the first frame whose
## middle is right of it
func _insert_index(x: float) -> int:
	for i in row.get_child_count():
		if x < (row.get_child(i) as Control).get_rect().get_center().x:
			return i
	return row.get_child_count()


## Scrolls while dragging near either end, and follows the mouse with the box or where
## frames would go
func _process(delta: float) -> void:
	var dropping := (
		get_viewport().gui_is_dragging() and _accepts(get_viewport().gui_get_drag_data())
	)
	if not _boxing and not dropping:
		set_process(false)
		return
	var mouse := scroll.get_local_mouse_position()
	var inside := Rect2(Vector2.ZERO, scroll.size).has_point(mouse)
	if dropping and not inside:
		if _drop_index >= 0:
			_drop_index = -1
			_overlay.queue_redraw()
		return
	var speed := 0.0
	if mouse.x < SCROLL_MARGIN:
		speed = -SCROLL_SPEED * (1 - maxf(mouse.x, 0) / SCROLL_MARGIN)
	elif mouse.x > scroll.size.x - SCROLL_MARGIN:
		speed = SCROLL_SPEED * (1 - maxf(scroll.size.x - mouse.x, 0) / SCROLL_MARGIN)
	if speed != 0:
		scroll.scroll_horizontal += roundi(speed * delta)
	if _boxing:
		_box_end = row.get_local_mouse_position()
		_update_box()
	elif dropping:
		_drop_index = _insert_index(row.get_local_mouse_position().x)
	_overlay.queue_redraw()


#endregion

#region Input


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed:
		return
	if key.keycode in [KEY_DELETE, KEY_BACKSPACE] and key.get_modifiers_mask() == 0:
		remove_frames(get_selected())
		accept_event()
	elif key.keycode == KEY_A and key.is_command_or_control_pressed():
		select_all()
		accept_event()
	elif key.keycode == KEY_ESCAPE and not _selected.is_empty():
		select([])
		accept_event()


## Clicking picks the frame: Ctrl adds or takes it out, Shift picks from the last one
## picked. Pressing a picked frame keeps the others picked until released, so they can be
## dragged together.
func _on_tile_input(event: InputEvent, tile: TimelineTile) -> void:
	var click := event as InputEventMouseButton
	if not click or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var index := tile.index
	if not click.pressed:
		if _pressed_selected == index:
			select([index] as Array[int])
		_pressed_selected = -1
		return
	grab_focus()
	if click.shift_pressed and _anchor >= 0:
		if not click.is_command_or_control_pressed():
			_selected.clear()
		for i in range(mini(_anchor, index), maxi(_anchor, index) + 1):
			_selected[i] = true
		_show_selection()
	elif click.is_command_or_control_pressed():
		if _selected.has(index):
			_selected.erase(index)
		else:
			_selected[index] = true
		_anchor = index
		_show_selection()
	elif _selected.has(index):
		_pressed_selected = index
		_anchor = index
	else:
		select([index] as Array[int])
		_anchor = index
	tile.accept_event()


## Dragging between or after the frames draws a box that picks the frames it touches
func _on_row_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			grab_focus()
			_boxing = true
			_box_base = {}
			if click.shift_pressed or click.is_command_or_control_pressed():
				_box_base = _selected.duplicate()
			_box_start = click.position
			_box_end = click.position
			_update_box()
			set_process(true)
		elif _boxing:
			_boxing = false
			_overlay.queue_redraw()
		row.accept_event()
	elif event is InputEventMouseMotion and _boxing:
		_box_end = (event as InputEventMouseMotion).position
		_update_box()
		_overlay.queue_redraw()


func _update_box() -> void:
	var box := Rect2(_box_start, Vector2.ZERO).expand(_box_end)
	_selected = _box_base.duplicate()
	for tile: TimelineTile in row.get_children():
		if box.intersects(tile.get_rect(), true):
			_selected[tile.index] = true
	_show_selection()


#endregion


func _update_tiles() -> void:
	while row.get_child_count() > _cells.size():
		var last := row.get_child(row.get_child_count() - 1)
		row.remove_child(last)
		last.queue_free()
	while row.get_child_count() < _cells.size():
		row.add_child(_new_tile())
	var labels := _labels()
	for i in _cells.size():
		var tile := row.get_child(i) as TimelineTile
		tile.show_frame(i, _thumbnail(_cells[i]), labels[i], _tooltip(_cells[i]), _durations[i])
		tile.set_picture_size(_picture_size)
	empty_hint.visible = _cells.is_empty()
	_show_selection()
	# Pictures no longer shown aren't kept
	var shown := {}
	for cell in _cells:
		if sheet.has_frame(cell):
			shown[sheet.frames[cell]] = true
	for img: Image in _textures.keys():
		if not shown.has(img):
			_textures.erase(img)


## Frames without a name are numbered from the index_start setting
func _on_setting_changed(key: StringName) -> void:
	if key == &"index_start" and sheet:
		_update_tiles()


func _new_tile() -> TimelineTile:
	var tile := TimelineTile.new()
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.gui_input.connect(_on_tile_input.bind(tile))
	tile.remove_pressed.connect(func() -> void: remove_frames([tile.index] as Array[int]))
	tile.duration_changed.connect(func(duration: float) -> void: set_duration(tile.index, duration))
	tile.set_drag_forwarding(_get_tile_drag.bind(tile), _can_drop.bind(tile), _drop.bind(tile))
	# Its fields take dropped frames too
	for target: Control in [
		tile.remove_button, tile.duration_spin, tile.duration_spin.get_line_edit()
	]:
		target.set_drag_forwarding(Callable(), _can_drop.bind(target), _drop.bind(target))
	return tile


func _show_selection() -> void:
	for tile: TimelineTile in row.get_children():
		tile.selected = _selected.has(tile.index)


## What each frame is labelled with: the part of its name that differs from the others,
## or its number without a name
func _labels() -> PackedStringArray:
	var names: PackedStringArray = []
	for cell in _cells:
		names.append(
			sheet.frames[cell].resource_name.get_basename() if sheet.has_frame(cell) else ""
		)
	var labels := short_labels(names)
	var start: int = Settings.get_value(&"index_start")
	for i in _cells.size():
		if labels[i]:
			continue
		if not sheet.has_frame(_cells[i]):
			labels[i] = tr("Empty") if sheet.is_inside(_cells[i]) else tr("Outside")
		else:
			labels[i] = str(sheet.index_of(_cells[i]) + start)
	return labels


## The frame's full name and size, or why it's skipped
func _tooltip(cell: Vector2i) -> String:
	var number: int = sheet.index_of(cell) + Settings.get_value(&"index_start")
	if not sheet.is_inside(cell):
		return tr("Cell %d is outside the sheet: skipped") % number
	if not sheet.has_frame(cell):
		return tr("Cell %d is empty: skipped") % number
	var img := sheet.frames[cell]
	var frame_name := img.resource_name.get_basename()
	if frame_name.is_empty():
		frame_name = tr("Frame %d") % number
	return "%s\n%d×%d px" % [frame_name, img.get_width(), img.get_height()]


func _thumbnail(cell: Vector2i) -> Texture2D:
	if not sheet.has_frame(cell):
		return null
	var img := sheet.frames[cell]
	if not _textures.has(img):
		_textures[img] = ImageTexture.create_from_image(img)
	return _textures[img]


## Sizes the pictures to the height given, see [method fit_height]
func _apply_picture_size() -> void:
	if not is_inside_tree():
		return
	var around := (
		get_theme_stylebox(&"panel").get_minimum_size().y
		+ scroll.get_h_scroll_bar().get_combined_minimum_size().y
		+ _probe.get_combined_minimum_size().y
		- _probe.get_picture_size()
	)
	_picture_size = clampi(floori(_available_height - around), MIN_PICTURE, MAX_PICTURE)
	_probe.set_picture_size(_picture_size)
	row.custom_minimum_size.y = _probe.get_combined_minimum_size().y
	for tile: TimelineTile in row.get_children():
		tile.set_picture_size(_picture_size)


## [param indices] that are frames, sorted, without repeats
func _valid_indices(indices: Array[int]) -> Array[int]:
	var valid: Array[int] = []
	for i in indices:
		if i >= 0 and i < _cells.size() and i not in valid:
			valid.append(i)
	valid.sort()
	return valid


func _draw_overlay() -> void:
	var accent := Global.accent_color
	var to_overlay := _overlay.get_global_transform().affine_inverse()
	if _drop_index >= 0:
		var gap := float(row.get_theme_constant(&"separation"))
		var x := 0.0
		if _drop_index < row.get_child_count():
			x = (row.get_child(_drop_index) as Control).get_global_rect().position.x - gap / 2
		elif row.get_child_count() > 0:
			x = (row.get_child(-1) as Control).get_global_rect().end.x + gap / 2
		else:
			x = row.get_global_rect().position.x + gap
		x = (to_overlay * Vector2(x, 0)).x
		_overlay.draw_rect(Rect2(x - MARKER_WIDTH / 2, 0, MARKER_WIDTH, _overlay.size.y), accent)
	if _boxing:
		var from_row := to_overlay * row.get_global_transform()
		var box := Rect2(from_row * _box_start, Vector2.ZERO).expand(from_row * _box_end)
		_overlay.draw_rect(box, Color(accent, 0.2))
		_overlay.draw_rect(box, accent, false, 1.0)
