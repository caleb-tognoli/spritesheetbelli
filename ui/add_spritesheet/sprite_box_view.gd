class_name SpriteBoxView
extends Control
## The image being cut, with a numbered box over each sprite, to edit the boxes by hand
## (see [SpriteBoxes]); [SpriteBoxEditor] keeps the history. Boxes are numbered in reading
## order, the order their frames are added in.
##
## Mouse: click a box to select it, Shift or Ctrl+click for several. Drag inside a box to
## move the selected boxes, drag an edge or a corner to resize a box, drag on empty space
## to draw a new box, and Ctrl+drag across boxes to merge them. Middle drag or Space+drag
## pans, the wheel zooms. With [member picking] on, a click picks the colour under the
## mouse instead.

## The boxes were changed by hand, see [member boxes]
signal edited
signal selection_changed
signal zoom_changed(zoom: float)
## With [member picking] on, the user clicked a pixel shown in [param color]
signal color_picked(color: Color)
signal undo_requested
signal redo_requested
## A box is being moved, resized or drawn, see [method get_dragged_box], or was
signal dragged

const MAX_ZOOM := 32.0
const MIN_ZOOM := 0.02
## Space around the image when it's fitted in the view
const MARGIN := 40.0
## Mouse movement in pixels before a press becomes a drag
const DRAG_THRESHOLD := 4.0
## How far from an edge on screen it can still be dragged
const EDGE_REACH := 5.0
const HANDLE_SIZE := 6.0
## Smallest box on screen that gets a number
const MIN_SIZE_FOR_NUMBER := Vector2(20, 18)
const NUMBER_FONT_SIZE := 13
const HOVER_COLOR := Color(1, 1, 1, 0.12)

enum Drag { NONE, PENDING, PAN, MOVE, RESIZE, DRAW, MERGE }

## The boxes, in no particular order: [method get_number] says their order
var boxes: Array[Rect2i] = []
## The indices of the selected boxes, in the order they were selected
var selected: Array[int] = []
## When on, clicking picks the colour under the mouse, see [signal color_picked], instead
## of editing the boxes
var picking := false:
	set(value):
		picking = value
		_update_cursor()
var image: Image
var zoom := 1.0
## Where the top-left corner of the image is in the view
var pan := Vector2(50, 50)

var background_color := Color.BLACK
var box_color := Color.WHITE
var selection_color := AppTheme.DEFAULT_ACCENT
var selection_tint := 0.25
var show_checkerboard := true
var zoom_speed := 0.2
var index_start := 0

var _texture: ImageTexture
var _checker: ImageTexture
## The number of each box, by index
var _numbers := PackedInt32Array()
## Whether the view is fitted to the image, and fits again when resized, until it's zoomed
## or panned: a view shown for the first time only has its size later
var _fitted := false
var _wheel_notches := 0.0
var _pan_key_held := false
var _hover_box := -1
var _hover_edges := 0
var _drag := Drag.NONE
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
## Where the image was when panning started
var _press_pan := Vector2.ZERO
## The box pressed, and which of its edges when an edge was
var _press_box := -1
var _press_edges := 0
var _press_additive := false
var _press_merges := false
## Where the mouse is while dragging, in pixels of the image
var _drag_world := Vector2.ZERO


func _init() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(
		func() -> void:
			if _fitted:
				fit_to_view()
	)
	mouse_exited.connect(func() -> void: _set_hover(-1, 0))


func _ready() -> void:
	Settings.changed.connect(apply_settings.unbind(1))
	apply_settings()


func apply_settings() -> void:
	background_color = Settings.get_value(&"background_color")
	box_color = Color(Settings.get_value(&"grid_color"), 1.0)
	selection_color = Settings.get_value(&"accent_color")
	selection_tint = Settings.get_value(&"selection_tint") / 100.0
	show_checkerboard = Settings.get_value(&"show_checkerboard")
	_checker = ImageUtils.checker_texture(Settings.get_value(&"checker_size"))
	zoom_speed = Settings.get_value(&"zoom_speed")
	index_start = Settings.get_value(&"index_start")
	_numbers = SpriteBoxes.get_numbers(boxes, index_start)
	queue_redraw()


## Shows [param img] under the boxes
func set_image(img: Image) -> void:
	image = img
	_texture = ImageTexture.create_from_image(img) if img else null
	queue_redraw()


## Shows [param new_boxes] with [param new_selected] selected, without [signal edited]
func set_boxes(new_boxes: Array[Rect2i], new_selected: Array[int] = []) -> void:
	var was_selected := selected
	boxes = new_boxes.duplicate()
	var kept: Array[int] = []
	kept.assign(new_selected.filter(func(index: int) -> bool: return index < boxes.size()))
	selected = kept
	_numbers = SpriteBoxes.get_numbers(boxes, index_start)
	_set_hover(-1, 0)
	queue_redraw()
	if selected != was_selected:
		selection_changed.emit()


func get_image_rect() -> Rect2i:
	return Rect2i(Vector2i.ZERO, image.get_size() if image else Vector2i.ZERO)


## The number shown on the box at [param index]
func get_number(index: int) -> int:
	return _numbers[index]


func select(indices: Array[int]) -> void:
	if indices != selected:
		selected = indices.duplicate()
		queue_redraw()
		selection_changed.emit()


func select_all() -> void:
	select(Array(range(boxes.size()), TYPE_INT, "", null))


## Removes the selected boxes
func remove_selected() -> void:
	if not selected.is_empty():
		_commit(SpriteBoxes.remove(boxes, selected), [] as Array[int])


## Joins the selected boxes into one, selected
func merge_selected() -> void:
	if selected.size() >= 2:
		var merged := SpriteBoxes.merge(boxes, selected)
		_commit(merged, [merged.size() - 1] as Array[int])


## Takes [param new_boxes] as edited by hand
func _commit(new_boxes: Array[Rect2i], new_selected: Array[int]) -> void:
	set_boxes(new_boxes, new_selected)
	edited.emit()


#region View


func screen_to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - pan) / zoom


func world_to_screen(world_position: Vector2) -> Vector2:
	return pan + world_position * zoom


## Zooms keeping the point under [param anchor] (in the view) in place
func set_zoom(value: float, anchor := size / 2) -> void:
	value = clampf(value, MIN_ZOOM, MAX_ZOOM)
	var anchor_in_world := screen_to_world(anchor)
	zoom = value
	pan = anchor - anchor_in_world * zoom
	_fitted = false
	queue_redraw()
	zoom_changed.emit(zoom)


## Zooms by [param factor], or to the next whole zoom that way with pixel-perfect zoom, see
## [PixelZoom]
func zoom_by(factor: float, anchor := size / 2) -> void:
	if PixelZoom.is_on():
		set_zoom(PixelZoom.step(zoom, factor), anchor)
	else:
		set_zoom(zoom * factor, anchor)


## Zooms and centres the view so the whole image is visible, and keeps it so when the
## view is resized until it's zoomed or panned
func fit_to_view() -> void:
	var content := Vector2(get_image_rect().size)
	var room := size - Vector2.ONE * MARGIN * 2
	if content.x <= 0 or content.y <= 0 or room.x <= 0 or room.y <= 0:
		set_zoom(1)
		pan = Vector2(50, 50)
	else:
		var fit := room / content
		var value := minf(fit.x, fit.y)
		set_zoom(PixelZoom.round_down(value) if PixelZoom.is_on() else value)
		pan = ((size - content * zoom) / 2).round()
	_fitted = true
	queue_redraw()


## Zooms in by [param notches] of the wheel, or out when negative, keeping the point under
## [param anchor] in place
func _zoom_with_wheel(notches: float, anchor: Vector2) -> void:
	if not PixelZoom.is_on():
		var factor := 1 + zoom_speed * absf(notches)
		set_zoom(zoom * (factor if notches > 0 else 1 / factor), anchor)
		return
	# A whole zoom step per notch
	if signf(notches) != signf(_wheel_notches):
		_wheel_notches = 0
	_wheel_notches += notches
	if absf(_wheel_notches) < 1 - PixelZoom.EPSILON:
		return
	_wheel_notches = 0
	zoom_by(1 + zoom_speed if notches > 0 else 1 / (1 + zoom_speed), anchor)


func _pan_by(offset: Vector2) -> void:
	pan += offset
	_fitted = false
	queue_redraw()


#endregion

#region Input


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom * event.factor, event.position)
	elif event is InputEventPanGesture:
		_pan_by(-event.delta * 10)
	elif event is InputEventKey:
		if _handle_key(event):
			accept_event()


func _handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_SPACE:
		_pan_key_held = event.pressed
		_update_cursor()
		return true
	if not event.pressed or _drag != Drag.NONE:
		return false
	# Exact, so Ctrl+Shift+Z is only redo
	if event.is_action(&"redo", true):
		redo_requested.emit()
	elif event.is_action(&"undo", true):
		undo_requested.emit()
	elif event.is_action(&"delete_frames", true):
		remove_selected()
	elif event.is_action(&"select_all", true):
		select_all()
	elif event.is_action(&"zoom_in", true):
		zoom_by(1.25)
	elif event.is_action(&"zoom_out", true):
		zoom_by(0.8)
	elif event.is_action(&"zoom_fit", true):
		fit_to_view()
	elif event.is_action(&"zoom_reset", true):
		set_zoom(1)
	else:
		return false
	return true


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP when event.pressed:
			_zoom_with_wheel(event.factor, event.position)
		MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
			_zoom_with_wheel(-event.factor, event.position)
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_start_pan(event.position)
			elif _drag == Drag.PAN:
				_end_drag()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(event)
			elif _drag != Drag.NONE:
				_on_left_release()
		_:
			return
	accept_event()


func _start_pan(screen_position: Vector2) -> void:
	_drag = Drag.PAN
	_press_screen = screen_position
	_press_pan = pan
	_update_cursor()


func _on_left_press(event: InputEventMouseButton) -> void:
	grab_focus()
	if _pan_key_held:
		_start_pan(event.position)
		return
	var world := screen_to_world(event.position)
	if picking:
		var pixel := Vector2i(world.floor())
		if image and get_image_rect().has_point(pixel):
			color_picked.emit(image.get_pixelv(pixel))
		return
	_press_screen = event.position
	_press_world = world
	_drag_world = world
	_press_additive = event.shift_pressed or event.is_command_or_control_pressed()
	_press_merges = event.is_command_or_control_pressed()
	_press_box = -1
	_press_edges = 0
	if not _press_merges:
		var hit := _find_edges(world)
		_press_box = hit.x
		_press_edges = hit.y
	if _press_box < 0:
		_press_box = SpriteBoxes.find_at(boxes, world)
	# A box pressed alone is selected right away, to drag it
	if not _press_additive and _press_box >= 0 and _press_box not in selected:
		select([_press_box] as Array[int])
	_drag = Drag.PENDING
	queue_redraw()


func _on_left_release() -> void:
	var drag := _drag
	var result := _get_drag_result()
	_end_drag()
	match drag:
		Drag.PENDING:
			_click()
		Drag.MOVE, Drag.RESIZE, Drag.DRAW, Drag.MERGE:
			if result.boxes != boxes or result.selected != selected:
				_commit(result.boxes, result.selected)
	queue_redraw()
	dragged.emit()


## A press and release in place: selects the box there, or adds it to the selection or
## takes it out with Shift or Ctrl. Clicking empty space selects nothing.
func _click() -> void:
	var indices: Array[int] = []
	if _press_additive:
		indices = selected.duplicate()
	if _press_box in indices:
		indices.erase(_press_box)
	elif _press_box >= 0:
		indices.append(_press_box)
	select(indices)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var world := screen_to_world(event.position)
	match _drag:
		Drag.NONE:
			var hit := _find_edges(world) if not picking else Vector2i(-1, 0)
			if hit.x >= 0:
				_set_hover(hit.x, hit.y)
			else:
				_set_hover(-1 if picking else SpriteBoxes.find_at(boxes, world), 0)
			return
		Drag.PAN:
			_pan_by(_press_pan + event.position - _press_screen - pan)
			return
		Drag.PENDING:
			if event.position.distance_to(_press_screen) < DRAG_THRESHOLD:
				return
			_begin_drag()
	_drag_world = world
	queue_redraw()
	dragged.emit()


## A press that moved far enough is a drag: merging with Ctrl, resizing from an edge,
## moving from inside a box, and drawing a new box elsewhere
func _begin_drag() -> void:
	if _press_merges:
		_drag = Drag.MERGE
	elif _press_edges:
		_drag = Drag.RESIZE
	elif _press_box >= 0:
		_drag = Drag.MOVE
		# Shift+dragging a box moves it with the selection
		if _press_box not in selected:
			var indices := selected.duplicate()
			indices.append(_press_box)
			select(indices)
	else:
		_drag = Drag.DRAW
	_update_cursor()


## The boxes and the selection as they'd be if the drag ended here:
## [code]{"boxes": Array[Rect2i], "selected": Array[int], "sweep": Rect2i}[/code], where
## sweep (a Rect2) is the rectangle drawn to make a box or to merge boxes
func _get_drag_result() -> Dictionary:
	var bounds := get_image_rect()
	var result := {"boxes": boxes, "selected": selected, "sweep": Rect2()}
	match _drag:
		Drag.MOVE:
			var offset := Vector2i((_drag_world - _press_world).round())
			result.boxes = SpriteBoxes.move(boxes, selected, offset, bounds)
		Drag.RESIZE:
			var changed := boxes.duplicate()
			var to := Vector2i(_drag_world.round())
			changed[_press_box] = SpriteBoxes.resize(boxes[_press_box], _press_edges, to, bounds)
			result.boxes = changed
		Drag.DRAW:
			var box := SpriteBoxes.from_corners(
				Vector2i(_press_world.floor()), Vector2i(_drag_world.floor()), bounds
			)
			var drawn := boxes.duplicate()
			drawn.append(box)
			result.boxes = drawn
			result.selected = [drawn.size() - 1] as Array[int]
			result.sweep = Rect2(box)
		Drag.MERGE:
			var sweep := Rect2(_press_world, Vector2.ZERO).expand(_drag_world)
			result.sweep = sweep
			var touched := SpriteBoxes.touching(boxes, sweep)
			if touched.size() >= 2:
				var merged := SpriteBoxes.merge(boxes, touched)
				result.boxes = merged
				result.selected = [merged.size() - 1] as Array[int]
	return result


## The box being moved (the one pressed), resized or drawn, where it would be if the drag
## ended now, or an empty rectangle
func get_dragged_box() -> Rect2i:
	match _drag:
		Drag.MOVE, Drag.RESIZE:
			return _get_drag_result().boxes[_press_box]
		Drag.DRAW:
			return Rect2i(_get_drag_result().sweep)
	return Rect2i()


func _end_drag() -> void:
	_drag = Drag.NONE
	_update_cursor()


## The box whose edges are under [param world] and which ones, as (index, edges), or
## (-1, 0). Selected boxes come first, then the smallest.
func _find_edges(world: Vector2) -> Vector2i:
	var reach := EDGE_REACH / zoom
	for index in selected:
		var edges := SpriteBoxes.edges_at(boxes[index], world, reach)
		if edges:
			return Vector2i(index, edges)
	var found := Vector2i(-1, 0)
	for index in boxes.size():
		var edges := SpriteBoxes.edges_at(boxes[index], world, reach)
		if edges and (found.x < 0 or boxes[index].get_area() < boxes[found.x].get_area()):
			found = Vector2i(index, edges)
	return found


func _set_hover(index: int, edges: int) -> void:
	if index != _hover_box or edges != _hover_edges:
		_hover_box = index
		_hover_edges = edges
		_update_cursor()
		queue_redraw()


func _update_cursor() -> void:
	mouse_default_cursor_shape = _pick_cursor_shape()


## Arrows over edges to resize, the move cursor over boxes and a cross where a box would
## be drawn
func _pick_cursor_shape() -> Control.CursorShape:
	if _drag == Drag.PAN or _pan_key_held:
		return Control.CURSOR_DRAG
	if picking:
		return Control.CURSOR_CROSS
	var edges := _press_edges if _drag == Drag.RESIZE else _hover_edges
	if _drag in [Drag.NONE, Drag.RESIZE] and edges:
		var horizontal := edges & (SpriteBoxes.LEFT | SpriteBoxes.RIGHT)
		var vertical := edges & (SpriteBoxes.TOP | SpriteBoxes.BOTTOM)
		if horizontal and vertical:
			var falling := (
				edges
				in [SpriteBoxes.LEFT | SpriteBoxes.TOP, SpriteBoxes.RIGHT | SpriteBoxes.BOTTOM]
			)
			return Control.CURSOR_FDIAGSIZE if falling else Control.CURSOR_BDIAGSIZE
		return Control.CURSOR_HSIZE if horizontal else Control.CURSOR_VSIZE
	if _drag == Drag.MOVE or (_drag == Drag.NONE and _hover_box >= 0):
		return Control.CURSOR_MOVE
	return Control.CURSOR_CROSS


#endregion

#region Drawing


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if image == null:
		return
	var image_rect := Rect2(pan, Vector2(image.get_size()) * zoom)
	if show_checkerboard:
		draw_texture_rect(_checker, image_rect, true)
	draw_texture_rect(_texture, image_rect, false)

	var result := _get_drag_result() if _drag != Drag.NONE else {}
	var shown: Array[Rect2i] = result.get("boxes", boxes)
	var shown_selected: Array[int] = result.get("selected", selected)
	var numbers := _numbers if shown == boxes else SpriteBoxes.get_numbers(shown, index_start)
	# Boxes a Ctrl+drag would merge
	var merging: Array[int] = []
	if _drag == Drag.MERGE:
		merging = SpriteBoxes.touching(boxes, result.sweep)
		shown = boxes
		shown_selected = selected
		numbers = _numbers
	for index in shown.size():
		var rect := _box_on_screen(shown[index])
		var on := index in shown_selected or index in merging
		if on:
			draw_rect(rect, Color(selection_color, selection_tint))
		elif index == _hover_box and _drag == Drag.NONE:
			draw_rect(rect, HOVER_COLOR)
		# A dark line around each box, so it shows on light art too
		draw_rect(rect.grow(0.5), Color(0, 0, 0, 0.6), false, 1)
		if on:
			draw_rect(rect.grow(-1), selection_color, false, 2)
		else:
			draw_rect(rect.grow(-0.5), box_color, false, 1)
	for index in shown.size():
		var rect := _box_on_screen(shown[index])
		if rect.size.x >= MIN_SIZE_FOR_NUMBER.x and rect.size.y >= MIN_SIZE_FOR_NUMBER.y:
			_draw_number(numbers[index], rect.position)
	if _drag != Drag.MERGE:
		for index in shown_selected:
			_draw_handles(_box_on_screen(shown[index]))
	if _drag in [Drag.DRAW, Drag.MERGE]:
		var sweep := _box_on_screen(result.sweep)
		draw_rect(sweep, Color(selection_color, 0.15))
		draw_rect(sweep.grow(-0.5), selection_color, false, 1)


func _box_on_screen(rect: Rect2) -> Rect2:
	return Rect2(world_to_screen(rect.position).round(), (rect.size * zoom).round())


## Squares at the corners and the middles of the edges of a selected box, where it's
## resized. Only the corners on a small box.
func _draw_handles(rect: Rect2) -> void:
	var points: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]
	if minf(rect.size.x, rect.size.y) >= HANDLE_SIZE * 4:
		var middle := rect.get_center()
		(
			points
			. append_array(
				[
					Vector2(middle.x, rect.position.y),
					Vector2(rect.end.x, middle.y),
					Vector2(middle.x, rect.end.y),
					Vector2(rect.position.x, middle.y),
				]
			)
		)
	for point in points:
		var handle := Rect2(point - Vector2.ONE * HANDLE_SIZE / 2, Vector2.ONE * HANDLE_SIZE)
		draw_rect(handle.grow(1), Color.BLACK)
		draw_rect(handle, selection_color)


## [param number] in the top-left corner at [param corner], like the frame numbers of the
## spritesheet preview
func _draw_number(number: int, corner: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var text_position := corner + Vector2(4, 2 + NUMBER_FONT_SIZE)
	var text := str(number)
	draw_string_outline(
		font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_FONT_SIZE, 5, Color.BLACK
	)
	draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_FONT_SIZE)

#endregion
