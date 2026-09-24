class_name SpritesheetPreview
extends Node2D
## Draws a spritesheet and handles selecting, moving and locking its cells.
##
## Everything is drawn by this node, so large sheets need no node per cell.
## Frame textures are cached per image and only created for new images.
##
## Mouse: click to select, Ctrl+click to toggle, Shift+click for a range, drag on empty
## space for a box selection, drag frames to move them (Alt+drag copies), click an
## empty cell to lock it. Middle drag or Space+drag pans, the wheel zooms.

## Emitted when the spritesheet or the selection changed
signal preview_updated
signal selection_changed
signal zoom_changed(zoom: float)
## The user clicked an empty cell to lock or unlock it
signal lock_requested(coord: Vector2i, locked: bool)
## The user dragged frames to another place
signal move_requested(coords: Array[Vector2i], offset: Vector2i, copy: bool)
## The cell under the mouse changed. (-1, -1) when outside the grid.
signal hover_changed(coord: Vector2i)
## The user double-clicked left of a row to name it
signal row_name_requested(row: int)

const LOCKED_COLOR := Color(0.85, 0.85, 0.85, 0.8)
const HOVER_COLOR := Color(1, 1, 1, 0.08)
const CHECKER_COLORS: Array[Color] = [Color(0.36, 0.36, 0.36), Color(0.42, 0.42, 0.42)]
const MAX_ZOOM := 32.0
const MIN_ZOOM := 0.02
## Minimum on-screen size of a cell for its index to be shown
const MIN_SIZE_TO_SHOW_INDEX := Vector2(40, 30)
const INDEX_FONT_SIZE := 14
## Mouse movement in pixels before a press becomes a drag
const DRAG_THRESHOLD := 4.0
const NO_CELL := Vector2i(-1, -1)

enum Drag { NONE, PENDING, BOX, MOVE, PAN }

@export var able_to_lock_spaces := true

# Set from Settings
var show_indices := true
var show_grid := true
var show_checkerboard := true
var grid_color := Color.WHITE
var background_color := Color.BLACK
var checker_size := 8
var zoom_speed := 0.2
var index_start := 0
var selection_color := AppTheme.DEFAULT_ACCENT

var spritesheet: Spritesheet = Spritesheet.new():
	set = set_spritesheet
var hovered_cell := NO_CELL

var _selected: Dictionary[Vector2i, bool] = {}
## Selection range start for Shift+click
var _anchor := NO_CELL
var _textures: Dictionary[Image, ImageTexture] = {}
var _checker := _make_checker_texture()

var _drag := Drag.NONE
var _drag_start_screen := Vector2.ZERO
var _drag_start_camera := Vector2.ZERO
var _drag_start_cell := NO_CELL
var _drag_additive := false
var _box_end_world := Vector2.ZERO
var _move_offset := Vector2i.ZERO
var _pan_key_held := false

@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Settings.changed.connect(apply_settings.unbind(1))
	apply_settings()


func apply_settings() -> void:
	show_grid = Settings.get_value(&"show_grid")
	show_indices = Settings.get_value(&"show_indices")
	show_checkerboard = Settings.get_value(&"show_checkerboard")
	grid_color = Settings.get_value(&"grid_color")
	background_color = Settings.get_value(&"background_color")
	checker_size = Settings.get_value(&"checker_size")
	zoom_speed = Settings.get_value(&"zoom_speed")
	index_start = Settings.get_value(&"index_start")
	selection_color = Settings.get_value(&"accent_color")
	queue_redraw()


func set_spritesheet(value: Spritesheet) -> void:
	if spritesheet and spritesheet.updated.is_connected(_on_spritesheet_updated):
		spritesheet.updated.disconnect(_on_spritesheet_updated)
	spritesheet = value
	spritesheet.updated.connect(_on_spritesheet_updated)
	_selected.clear()
	_on_spritesheet_updated()


func _on_spritesheet_updated() -> void:
	# Forget selections and textures of frames that are gone
	for coord: Vector2i in _selected.keys():
		if not spritesheet.has_frame(coord):
			_selected.erase(coord)
	var alive := {}
	for coord in spritesheet.frames:
		alive[spritesheet.get_frame_image(coord)] = true
	for img: Image in _textures.keys():
		if not alive.has(img):
			_textures.erase(img)
	queue_redraw()
	preview_updated.emit()


#region Coordinates


func screen_to_world(screen_position: Vector2) -> Vector2:
	return camera.position + screen_position / camera.zoom


func world_to_cell(world_position: Vector2) -> Vector2i:
	if spritesheet.sprite_size.x <= 0 or spritesheet.sprite_size.y <= 0:
		return NO_CELL
	var cell := Vector2i((world_position / Vector2(spritesheet.sprite_size)).floor())
	return cell if spritesheet.is_inside(cell) else NO_CELL


func cell_rect(coord: Vector2i) -> Rect2:
	return Rect2(Vector2(coord * spritesheet.sprite_size), Vector2(spritesheet.sprite_size))


func get_cell_at_screen_position(screen_position: Vector2) -> Vector2i:
	return world_to_cell(screen_to_world(screen_position))


#endregion

#region Selection


## Coordinates of the selected frames, in reading order
func get_selected_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in spritesheet.get_sorted_coords():
		if _selected.has(coord):
			coords.append(coord)
	return coords


func is_selected(coord: Vector2i) -> bool:
	return _selected.has(coord)


func set_selected_coords(coords: Array[Vector2i]) -> void:
	_selected.clear()
	for coord in coords:
		if spritesheet.has_frame(coord):
			_selected[coord] = true
	_selection_updated()


func select_all(select := true) -> void:
	var coords: Array[Vector2i] = []
	if select:
		coords = spritesheet.get_sorted_coords()
	set_selected_coords(coords)


func _toggle(coord: Vector2i) -> void:
	if _selected.has(coord):
		_selected.erase(coord)
	elif spritesheet.has_frame(coord):
		_selected[coord] = true
	_selection_updated()


## Selects every frame between the anchor and [param coord] in reading order
func _select_range(coord: Vector2i, additive: bool) -> void:
	if _anchor == NO_CELL:
		_anchor = coord
	var from := mini(spritesheet.index_of(_anchor), spritesheet.index_of(coord))
	var to := maxi(spritesheet.index_of(_anchor), spritesheet.index_of(coord))
	if not additive:
		_selected.clear()
	for c in spritesheet.frames:
		var index := spritesheet.index_of(c)
		if index >= from and index <= to:
			_selected[c] = true
	_selection_updated()


func _selection_updated() -> void:
	queue_redraw()
	selection_changed.emit()
	preview_updated.emit()


#endregion

#region View


## Zooms the camera keeping the point under [param anchor] (in viewport coordinates) in place
func set_zoom(value: float, anchor := Vector2.ZERO) -> void:
	value = clampf(value, MIN_ZOOM, MAX_ZOOM)
	var anchor_in_world := screen_to_world(anchor)
	camera.zoom = Vector2(value, value)
	camera.position = anchor_in_world - anchor / camera.zoom
	queue_redraw()
	zoom_changed.emit(value)


## Zooms by [param factor] around the centre of the view
func zoom_by(factor: float) -> void:
	set_zoom(camera.zoom.x * factor, get_viewport_rect().size / 2)


## Zooms and centres the view so the whole spritesheet is visible
func fit_to_view() -> void:
	const MARGIN := 40.0
	var content := Vector2(spritesheet.sprite_size * spritesheet.grid_size)
	var view := get_viewport_rect().size
	if content.x <= 0 or content.y <= 0 or view.x <= MARGIN * 2 or view.y <= MARGIN * 2:
		camera.position = -Vector2(50, 50) / camera.zoom
		queue_redraw()
		return
	# Row names are drawn left of the grid at a fixed size on screen
	var names_width := 0.0
	for row_name: String in spritesheet.row_names.values():
		names_width = maxf(names_width, ThemeDB.fallback_font.get_string_size(row_name).x + 16)
	var usable := view - Vector2(MARGIN * 2 + names_width, MARGIN * 2)
	var fit := usable / content
	set_zoom(minf(fit.x, fit.y))
	camera.position = content / 2 - (view + Vector2(names_width, 0)) / 2 / camera.zoom


## Whether cell indices are big enough on screen to be drawn
func is_index_visible() -> bool:
	var on_screen := Vector2(spritesheet.sprite_size) * camera.zoom
	return (
		show_indices
		and on_screen.x >= MIN_SIZE_TO_SHOW_INDEX.x
		and on_screen.y >= MIN_SIZE_TO_SHOW_INDEX.y
	)


#endregion

#region Input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE:
		_pan_key_held = event.pressed
		_update_cursor()
	elif event is InputEventKey and event.pressed and _handle_arrow_key(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		set_zoom(camera.zoom.x * event.factor, event.position)
	elif event is InputEventPanGesture:
		camera.position += event.delta * 10 / camera.zoom
		queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP when event.pressed:
			set_zoom(camera.zoom.x * (1 + zoom_speed * event.factor), event.position)
		MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
			set_zoom(camera.zoom.x / (1 + zoom_speed * event.factor), event.position)
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_start_drag(Drag.PAN, event.position)
			elif _drag == Drag.PAN:
				_end_drag()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(event)
			else:
				_on_left_release(event)
		MOUSE_BUTTON_RIGHT when event.pressed:
			# Right-clicking a frame outside the selection selects it for the context menu
			var cell := get_cell_at_screen_position(event.position)
			if spritesheet.has_frame(cell) and not is_selected(cell):
				set_selected_coords([cell] as Array[Vector2i])
				_anchor = cell


func _on_left_press(event: InputEventMouseButton) -> void:
	if event.double_click:
		var world := screen_to_world(event.position)
		var row := (
			floori(world.y / spritesheet.sprite_size.y) if spritesheet.sprite_size.y > 0 else -1
		)
		if world.x < 0 and row >= 0 and row < spritesheet.grid_size.y:
			row_name_requested.emit(row)
			return
	if _pan_key_held:
		_start_drag(Drag.PAN, event.position)
		return
	_start_drag(Drag.PENDING, event.position)
	_drag_start_cell = get_cell_at_screen_position(event.position)
	_drag_additive = event.is_command_or_control_pressed() or event.shift_pressed


func _on_left_release(event: InputEventMouseButton) -> void:
	var drag := _drag
	_end_drag()
	match drag:
		Drag.PENDING:
			_click(_drag_start_cell, event)
		Drag.BOX:
			_finish_box_selection()
		Drag.MOVE:
			if _move_offset != Vector2i.ZERO:
				move_requested.emit(get_selected_coords(), _move_offset, event.alt_pressed)
			_move_offset = Vector2i.ZERO
			queue_redraw()


## Arrow keys move the selection to the next frame in that direction; Shift extends it
func _handle_arrow_key(event: InputEventKey) -> bool:
	var directions := {
		KEY_LEFT: Vector2i.LEFT,
		KEY_RIGHT: Vector2i.RIGHT,
		KEY_UP: Vector2i.UP,
		KEY_DOWN: Vector2i.DOWN
	}
	if not directions.has(event.keycode) or spritesheet.is_empty():
		return false
	var direction: Vector2i = directions[event.keycode]
	var from := _anchor if spritesheet.has_frame(_anchor) else spritesheet.get_sorted_coords()[0]
	if _selected.is_empty():
		set_selected_coords([from] as Array[Vector2i])
		_anchor = from
		return true
	var cell := from + direction
	while spritesheet.is_inside(cell) and not spritesheet.has_frame(cell):
		cell += direction
	if not spritesheet.has_frame(cell):
		# Nothing further that way: keep only the current frame selected
		cell = from
	if not event.shift_pressed:
		_selected.clear()
	_selected[cell] = true
	_anchor = cell
	_selection_updated()
	return true


## A press and release without dragging
func _click(cell: Vector2i, event: InputEventMouseButton) -> void:
	var has_frame := spritesheet.has_frame(cell)
	if event.shift_pressed and has_frame:
		_select_range(cell, event.is_command_or_control_pressed())
	elif event.is_command_or_control_pressed():
		_toggle(cell)
		_anchor = cell
	elif has_frame:
		set_selected_coords([cell] as Array[Vector2i])
		_anchor = cell
	else:
		if not _selected.is_empty():
			select_all(false)
		elif cell != NO_CELL and able_to_lock_spaces:
			lock_requested.emit(cell, not spritesheet.is_locked(cell))


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_set_hovered_cell(get_cell_at_screen_position(event.position))
	match _drag:
		Drag.PAN:
			camera.position = (
				_drag_start_camera - (event.position - _drag_start_screen) / camera.zoom
			)
			queue_redraw()
		Drag.PENDING:
			if event.position.distance_to(_drag_start_screen) >= DRAG_THRESHOLD:
				_begin_real_drag()
		Drag.BOX:
			_box_end_world = screen_to_world(event.position)
			queue_redraw()
		Drag.MOVE:
			var cell := _cell_unclamped(screen_to_world(event.position))
			var offset := cell - _drag_start_cell
			# Keep every moved frame inside the positive quadrant
			for coord in _selected:
				offset = offset.max(-coord)
			if offset != _move_offset:
				_move_offset = offset
				queue_redraw()


## Turns a pending press into a box selection or a move
func _begin_real_drag() -> void:
	if spritesheet.has_frame(_drag_start_cell) and not _drag_additive:
		if not is_selected(_drag_start_cell):
			set_selected_coords([_drag_start_cell] as Array[Vector2i])
		_drag = Drag.MOVE
		_move_offset = Vector2i.ZERO
	else:
		_drag = Drag.BOX
		_box_end_world = screen_to_world(_drag_start_screen)
	_update_cursor()


func _finish_box_selection() -> void:
	var box := _box_rect()
	if not _drag_additive:
		_selected.clear()
	for coord in spritesheet.frames:
		if box.intersects(cell_rect(coord)):
			_selected[coord] = true
	_selection_updated()


func _box_rect() -> Rect2:
	var start := screen_to_world(_drag_start_screen)
	return Rect2(start, Vector2.ZERO).expand(_box_end_world)


func _cell_unclamped(world_position: Vector2) -> Vector2i:
	if spritesheet.sprite_size.x <= 0 or spritesheet.sprite_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i((world_position / Vector2(spritesheet.sprite_size)).floor())


func _start_drag(kind: Drag, screen_position: Vector2) -> void:
	_drag = kind
	_drag_start_screen = screen_position
	_drag_start_camera = camera.position
	_update_cursor()


func _end_drag() -> void:
	_drag = Drag.NONE
	queue_redraw()
	_update_cursor()


func _update_cursor() -> void:
	var shape := Input.CURSOR_ARROW
	if _drag == Drag.PAN or _pan_key_held:
		shape = Input.CURSOR_DRAG
	elif _drag == Drag.MOVE:
		shape = Input.CURSOR_MOVE
	Input.set_default_cursor_shape(shape)


func _set_hovered_cell(cell: Vector2i) -> void:
	if cell != hovered_cell:
		hovered_cell = cell
		queue_redraw()
		hover_changed.emit(cell)


#endregion

#region Drawing


func _draw() -> void:
	draw_rect(_visible_world_rect(), background_color)
	var cell_size := Vector2(spritesheet.sprite_size)
	if cell_size.x <= 0 or cell_size.y <= 0 or spritesheet.grid_size == Vector2i.ZERO:
		return
	var sheet_rect := Rect2(Vector2.ZERO, cell_size * Vector2(spritesheet.grid_size))
	var pixel := 1.0 / camera.zoom.x

	if show_checkerboard:
		# Checker squares stay the same size on screen
		var scale_factor := checker_size * pixel
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
		var rect := Rect2(sheet_rect.position / scale_factor, sheet_rect.size / scale_factor)
		draw_texture_rect(_checker, rect, true)
		draw_set_transform(Vector2.ZERO)

	var visible_rect := _visible_world_rect()
	var visible_cells := _visible_cells(visible_rect)
	for y in range(visible_cells.position.y, visible_cells.end.y):
		for x in range(visible_cells.position.x, visible_cells.end.x):
			var coord := Vector2i(x, y)
			var rect := cell_rect(coord)
			if spritesheet.has_frame(coord):
				_draw_frame(coord, rect)
			elif spritesheet.is_locked(coord):
				_draw_hatch(rect, LOCKED_COLOR, pixel)
			if coord == hovered_cell and _drag == Drag.NONE:
				draw_rect(rect, HOVER_COLOR)

	if show_grid:
		_draw_grid(cell_size, pixel)
	_draw_selection(pixel)
	if is_index_visible():
		_draw_indices(visible_cells)
	_draw_row_names(cell_size)
	if _drag == Drag.BOX:
		var box := _box_rect()
		draw_rect(box, Color(selection_color, 0.15))
		draw_rect(box, selection_color, false, pixel)


func _draw_frame(coord: Vector2i, rect: Rect2, modulate_color := Color.WHITE) -> void:
	var img := spritesheet.get_frame_image(coord)
	if not _textures.has(img):
		_textures[img] = ImageTexture.create_from_image(img)
	var in_cell := spritesheet.get_frame_rect_in_cell(coord)
	draw_texture_rect(
		_textures[img],
		Rect2(rect.position + Vector2(in_cell.position), in_cell.size),
		false,
		modulate_color
	)


func _draw_hatch(rect: Rect2, color: Color, pixel: float) -> void:
	const LINES := 5
	var step := rect.size / LINES
	for i in range(1, LINES * 2):
		var a := rect.position + Vector2(minf(i, LINES) * step.x, maxf(i - LINES, 0) * step.y)
		var b := rect.position + Vector2(maxf(i - LINES, 0) * step.x, minf(i, LINES) * step.y)
		draw_line(a, b, color, pixel)


func _draw_grid(cell_size: Vector2, pixel: float) -> void:
	var size := cell_size * Vector2(spritesheet.grid_size)
	for row in spritesheet.grid_size.y + 1:
		draw_line(
			Vector2(0, row * cell_size.y), Vector2(size.x, row * cell_size.y), grid_color, pixel
		)
	for column in spritesheet.grid_size.x + 1:
		draw_line(
			Vector2(column * cell_size.x, 0),
			Vector2(column * cell_size.x, size.y),
			grid_color,
			pixel
		)


func _draw_selection(pixel: float) -> void:
	for coord in _selected:
		var rect := cell_rect(coord)
		draw_rect(rect, Color(selection_color, 0.25))
		draw_rect(rect.grow(-pixel), selection_color, false, pixel * 2)

	# Ghosts of the frames being moved, where they would land
	if _drag == Drag.MOVE and _move_offset != Vector2i.ZERO:
		for coord in _selected:
			var target := cell_rect(coord + _move_offset)
			_draw_frame(coord, target, Color(1, 1, 1, 0.6))
			draw_rect(target.grow(-pixel), selection_color, false, pixel * 2)


func _draw_indices(visible_cells: Rect2i) -> void:
	var font := ThemeDB.fallback_font
	var inverse_zoom := Vector2.ONE / camera.zoom
	for coord in spritesheet.frames:
		if not visible_cells.has_point(coord):
			continue
		var rect := cell_rect(coord)
		# Text is drawn unscaled so it keeps the same size at any zoom
		draw_set_transform(rect.position, 0, inverse_zoom)
		var text := str(spritesheet.index_of(coord) + index_start)
		var position := Vector2(6, 4 + INDEX_FONT_SIZE)
		draw_string_outline(
			font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, INDEX_FONT_SIZE, 6, Color.BLACK
		)
		draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, INDEX_FONT_SIZE)
	draw_set_transform(Vector2.ZERO)


## Row names, right-aligned just left of the grid
func _draw_row_names(cell_size: Vector2) -> void:
	const FONT_SIZE := 13
	var font := ThemeDB.fallback_font
	for row in spritesheet.row_names:
		if row >= spritesheet.grid_size.y:
			continue
		var text: String = spritesheet.row_names[row]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var middle := Vector2(0, (row + 0.5) * cell_size.y)
		draw_set_transform(middle, 0, Vector2.ONE / camera.zoom)
		draw_string(
			font,
			Vector2(-width - 8, FONT_SIZE / 3.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			Color(0.8, 0.85, 1.0)
		)
	draw_set_transform(Vector2.ZERO)


## The range of cells on screen, so drawing skips the rest of large sheets
func _visible_cells(visible_rect: Rect2) -> Rect2i:
	var cell_size := Vector2(spritesheet.sprite_size)
	var start := Vector2i((visible_rect.position / cell_size).floor()).max(Vector2i.ZERO)
	var end := Vector2i((visible_rect.end / cell_size).ceil()).min(spritesheet.grid_size)
	return Rect2i(start, (end - start).max(Vector2i.ZERO))


func _visible_world_rect() -> Rect2:
	return Rect2(camera.position, get_viewport_rect().size / camera.zoom)


static func _make_checker_texture() -> ImageTexture:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, CHECKER_COLORS[0])
	img.set_pixel(1, 1, CHECKER_COLORS[0])
	img.set_pixel(1, 0, CHECKER_COLORS[1])
	img.set_pixel(0, 1, CHECKER_COLORS[1])
	return ImageTexture.create_from_image(img)

#endregion
