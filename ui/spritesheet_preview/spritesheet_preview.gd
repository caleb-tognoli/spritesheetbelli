class_name SpritesheetPreview
extends Node2D
## Draws a spritesheet and handles selecting, moving and locking its cells. The grid is
## drawn by [GridView]. A sheet in the packed layout is shown as its pages instead, see
## [PackedView]: frames are dragged to any place on a page, and there are no cells to lock.
##
## Everything is drawn by this node, so large sheets need no node per cell.
## Frame textures are cached per image and only created for new images. Other images can
## be shown in place of frames' own, see [method show_instead].
##
## Mouse: click a frame to select it, Ctrl+click to toggle it, Shift+click for a range,
## click an empty cell to lock or unlock it, and anywhere else to select nothing. Dragging
## a frame moves it, with the rest of the selection when it's selected, showing where it
## would land; dragging from anywhere else draws a selection box, which adds to the
## selection with Shift and toggles with Ctrl, also from a frame. With pivots on, the
## frame under the mouse shows its pivot, dragged to move it. Middle drag or Space+drag
## pans, the wheel zooms. With [member picking] on, a click picks the colour under the
## mouse instead. Esc puts back what's being dragged.
##
## Keys: arrows move the selected frames inside their cells, or on their page, a pixel at
## a time, 8 with Shift, or onto the next guide with Shift+Alt; Ctrl+arrows add the next
## frame that way to the selection.

## Emitted when the spritesheet or the selection changed
signal preview_updated
signal selection_changed
signal zoom_changed(zoom: float)
## The user clicked an empty cell to lock or unlock it
signal lock_requested(coord: Vector2i, locked: bool)
## The user dragged frames to another place
@warning_ignore("unused_signal")
signal move_requested(coords: Array[Vector2i], offset: Vector2i)
## The user pressed arrow keys to move frames inside their cells
signal nudge_requested(coords: Array[Vector2i], offset: Vector2i)
## The user pressed Shift+Alt+arrow to move frames onto the next guide in [param direction]
signal guide_snap_requested(coords: Array[Vector2i], direction: Vector2i)
## The cell under the mouse changed. (-1, -1) when outside the grid or the preview. Also
## emitted when the sheet changes, since what's in the cell may have.
signal hover_changed(coord: Vector2i)
## The pixel under the mouse changed, see [member hovered_pixel]
signal pixel_hovered
## With [member picking] on, the user clicked a pixel of a frame shown in [param color]
signal color_picked(color: Color)
## The user dragged packed frames, or moved them with arrow keys, by [param offset] onto
## [param page]
signal placement_move_requested(coords: Array[Vector2i], page: int, offset: Vector2i)
## The user dragged the pivot of frames to [param pivot], in unscaled pixels of the frame
signal pivot_requested(coords: Array[Vector2i], pivot: Vector2)
## The user dragged frames out of the preview, to drop them elsewhere, see
## [member drag_frames_out]. Dragged back over the preview, they move there again, see
## [method carry_back].
signal frames_dragged_out(coords: Array[Vector2i])

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
## Pixels Shift+arrow keys move frames
const BIG_NUDGE := 8

enum Drag { NONE, PENDING, BOX, MOVE, PAN, PIVOT }
## What a press turns into once dragged
enum Press { BOX, MOVE, PIVOT }
## How a selection box changes the selection
enum Box { REPLACE, ADD, TOGGLE }

## The cursor while something is pressed, before it's dragged
const PRESS_HINTS: Dictionary[Press, CanvasCursor.Hint] = {
	Press.BOX: CanvasCursor.Hint.NONE,
	Press.MOVE: CanvasCursor.Hint.MOVE,
	Press.PIVOT: CanvasCursor.Hint.POINT,
}

@export var able_to_lock_spaces := true
## When off, frames can't be moved and dragging always selects
@export var able_to_move_frames := true
## When on, frames dragged out of the preview stop moving there and go with
## [signal frames_dragged_out] instead, e.g. into an animation's timeline
var drag_frames_out := false
## When on, clicking picks the colour under the mouse, see [signal color_picked], instead
## of selecting
var picking := false:
	set(value):
		picking = value
		update_cursor()
## Where the cursor is shown and frames dragged out are dropped back, over the whole view
var surface: Control

# Set from Settings
var show_indices := true
var show_grid := true
var show_pixel_grid := true
var show_checkerboard := true
var grid_color := Color.WHITE
var background_color := Color.BLACK
var checker_size := 8
var zoom_speed := 0.2
var index_start := 0
var selection_color := AppTheme.DEFAULT_ACCENT
## Opacity of the accent colour over selected frames
var selection_tint := 0.25

var spritesheet: Spritesheet = Spritesheet.new():
	set = set_spritesheet
var hovered_cell := NO_CELL
## The whole pixel of the preview last under the mouse, see [method PixelGrid.probe]
var hovered_pixel := Vector2i.ZERO
## Where the cells are when the sheet is a grid
var grid_view := GridView.new()
## Where things are when the sheet is packed
var packed_view := PackedView.new()
## Names of animations on the grid, once enabled
var animation_labels := AnimationLabels.new()
## The pivots of the frames, to drag them
var pivots := PivotHandles.new()
## The frames being moved
var mover := FrameMover.new()
## Lines repeated in every cell to line frames up against, with the rulers
var guides := GuideLines.new()

var _selected: Dictionary[Vector2i, bool] = {}
## Selection range start for Shift+click
var _anchor := NO_CELL
var _textures: Dictionary[Image, ImageTexture] = {}
## Images shown in place of frame images, by the frame image, see [method show_instead]
var _shown_instead: Dictionary[Image, Image] = {}
var _checker := ImageUtils.checker_texture(1, CHECKER_COLORS[0], CHECKER_COLORS[1])
## Wheel notches not zoomed by yet: touchpads scroll by parts of a notch, which add up to
## a whole zoom step with pixel-perfect zoom
var _wheel_notches := 0.0

var _drag := Drag.NONE
var _press := Press.BOX
var _box_mode := Box.REPLACE
var _drag_start_screen := Vector2.ZERO
var _drag_start_camera := Vector2.ZERO
var _drag_start_cell := NO_CELL
var _box_end_world := Vector2.ZERO
var _pan_key_held := false
var _drag_start_world := Vector2.ZERO

@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	# Over the whole view whatever the camera does, letting the mouse through to the preview
	var layer := CanvasLayer.new()
	add_child(layer)
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_PASS
	surface.set_drag_forwarding(Callable(), _can_drop_back, _drop_back)
	layer.add_child(surface)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Settings.changed.connect(apply_settings.unbind(1))
	Global.theme_applied.connect(apply_settings)
	apply_settings()


func apply_settings() -> void:
	show_grid = Settings.get_value(&"show_grid")
	show_pixel_grid = Settings.get_value(&"show_pixel_grid")
	show_indices = Settings.get_value(&"show_indices")
	show_checkerboard = Settings.get_value(&"show_checkerboard")
	grid_color = Settings.get_value(&"grid_color")
	background_color = Settings.get_value(&"background_color")
	checker_size = Settings.get_value(&"checker_size")
	zoom_speed = Settings.get_value(&"zoom_speed")
	index_start = Settings.get_value(&"index_start")
	selection_color = Global.accent_color
	selection_tint = Settings.get_value(&"selection_tint") / 100.0
	pivots.shown = Settings.get_value(&"use_pivots")
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
	# Textures of scaled images the sheet keeps stay too, e.g. to undo a resize quickly
	var alive := spritesheet.scaled_frames.get_cached_images()
	for coord in spritesheet.frames:
		alive[spritesheet.frames[coord]] = true
	for img: Image in _shown_instead.values():
		alive[img] = true
	for img: Image in _textures.keys():
		if not alive.has(img):
			_textures.erase(img)
	packed_view.update(spritesheet)
	grid_view.update(spritesheet)
	animation_labels.update(spritesheet, grid_view)
	queue_redraw()
	if hovered_cell != NO_CELL:
		hover_changed.emit(hovered_cell)
	preview_updated.emit()


## Whether the sheet is shown packed instead of as a grid
func is_packed() -> bool:
	return spritesheet.layout == Spritesheet.Layout.PACKED


## Whether nothing is being dragged, panned or pressed
func is_idle() -> bool:
	return _drag == Drag.NONE and not _pan_key_held


#region Coordinates


func screen_to_world(screen_position: Vector2) -> Vector2:
	return camera.position + screen_position / camera.zoom


func world_to_cell(world_position: Vector2) -> Vector2i:
	if spritesheet.sprite_size.x <= 0 or spritesheet.sprite_size.y <= 0:
		return NO_CELL
	var cell := grid_view.get_cell_unclamped(world_position)
	return cell if spritesheet.is_inside(cell) else NO_CELL


func cell_rect(coord: Vector2i) -> Rect2:
	return grid_view.get_cell_rect(coord)


## The cell under [param screen_position], or in the packed layout the frame there
func get_cell_at_screen_position(screen_position: Vector2) -> Vector2i:
	if is_packed():
		return packed_view.get_frame_at(screen_to_world(screen_position))
	return world_to_cell(screen_to_world(screen_position))


## Where a frame is drawn: its cell, or its place in the packed layout
func get_frame_world_rect(coord: Vector2i) -> Rect2:
	return packed_view.get_frame_rect(coord) if is_packed() else cell_rect(coord)


## Where a frame's pivot (in unscaled pixels of the frame) is in the preview
func pivot_to_world(coord: Vector2i, pivot: Vector2) -> Vector2:
	if is_packed():
		return packed_view.pivot_to_world(coord, pivot)
	var in_cell := spritesheet.get_frame_rect_in_cell(coord)
	return cell_rect(coord).position + Vector2(in_cell.position) + pivot * spritesheet.frame_scale


## The pivot (in unscaled pixels of the frame) at [param world]
func world_to_pivot(coord: Vector2i, world: Vector2) -> Vector2:
	if is_packed():
		return packed_view.world_to_pivot(coord, world)
	var in_cell := spritesheet.get_frame_rect_in_cell(coord)
	var local := world - cell_rect(coord).position - Vector2(in_cell.position)
	return local / spritesheet.frame_scale


#endregion

#region Selection


## Coordinates of the selected frames, in reading order
func get_selected_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in spritesheet.get_sorted_coords():
		if _selected.has(coord):
			coords.append(coord)
	return coords


## Whether a frame is selected, quicker than [method get_selected_coords] for menus
func has_selection() -> bool:
	return _selected.keys().any(spritesheet.has_frame)


func is_selected(coord: Vector2i) -> bool:
	return _selected.has(coord)


func set_selected_coords(coords: Array[Vector2i]) -> void:
	_selected.clear()
	for coord in coords:
		if spritesheet.has_frame(coord):
			_selected[coord] = true
	_selection_updated()


## Selects nothing and forgets where Shift+click ranges start, e.g. for another document
func clear_selection() -> void:
	_anchor = NO_CELL
	select_all(false)


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
	update_cursor()
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


## Zooms by [param factor] around the centre of the view, or to the next whole zoom that
## way with pixel-perfect zoom, see [PixelZoom]
func zoom_by(factor: float, anchor := get_viewport_rect().size / 2) -> void:
	set_zoom(PixelZoom.zoom_by(self, camera.zoom.x, factor), anchor)


## Zooms to 100% around the centre, or the whole zoom nearest it with pixel-perfect zoom
func reset_zoom() -> void:
	set_zoom(PixelZoom.actual_size(self), get_viewport_rect().size / 2)


## Zooms and centres the view so the whole spritesheet is visible
func fit_to_view() -> void:
	const MARGIN := 40.0
	var content := grid_view.content_size
	var view := get_viewport_rect().size
	if is_packed():
		var pages := packed_view.get_content_rect()
		if pages.has_area() and view.x > MARGIN * 2 and view.y > MARGIN * 2:
			var room := (view - Vector2.ONE * MARGIN * 2) / pages.size
			set_zoom(PixelZoom.fitting(self, minf(room.x, room.y)))
			camera.position = pages.get_center() - view / 2 / camera.zoom
			return
	if content.x <= 0 or content.y <= 0 or view.x <= MARGIN * 2 or view.y <= MARGIN * 2:
		# An empty sheet is shown at 100%
		if content.x <= 0 or content.y <= 0:
			set_zoom(1)
		camera.position = -Vector2(50, 50) / camera.zoom
		queue_redraw()
		return
	# Names of animations in the margins stay the same size, so they get room of their own
	var labels := animation_labels.get_margins()
	var space := view - Vector2.ONE * MARGIN * 2 - Vector2(labels.x + labels.z, labels.y + labels.w)
	var fit := space.max(Vector2.ONE) / content
	set_zoom(PixelZoom.fitting(self, minf(fit.x, fit.y)))
	var corner := Vector2.ONE * MARGIN + Vector2(labels.x, labels.y)
	camera.position = -(corner + (space - content * camera.zoom) / 2) / camera.zoom


## Where the view looks, to show the same place again with [method set_view]: the zoom
## and the point in the middle of the view, in pixels of the sheet. The middle rather
## than the corner, so a window of another size shows the same place.
func get_view() -> Dictionary:
	return {"centre": screen_to_world(get_viewport_rect().size / 2), "zoom": camera.zoom.x}


## Shows a view from [method get_view]
func set_view(view: Dictionary) -> void:
	set_zoom(view.zoom)
	camera.position = view.centre - get_viewport_rect().size / 2 / camera.zoom
	queue_redraw()


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


func _input(event: InputEvent) -> void:
	# Before Esc selects nothing
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and _cancel_drag():
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Frames dragged out come back through the surface, see carry_back
	if mover.carried and event is InputEventMouse:
		return
	if animation_labels.handle_input(self, event):
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.keycode == KEY_SPACE:
		_pan_key_held = key.pressed
		update_cursor()
	elif key and key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_META]:
		# They turn dragging a frame into drawing a box
		update_cursor()
	elif key and key.pressed and _handle_arrow_key(key):
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
			_zoom_with_wheel(event.factor, event.position)
		MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
			_zoom_with_wheel(-event.factor, event.position)
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


## Zooms in by [param notches] of the wheel, or out when negative, keeping the point under
## [param anchor] in place
func _zoom_with_wheel(notches: float, anchor: Vector2) -> void:
	if not PixelZoom.is_on():
		var factor := 1 + zoom_speed * absf(notches)
		set_zoom(camera.zoom.x * (factor if notches > 0 else 1 / factor), anchor)
		return
	# A whole zoom step per notch
	if signf(notches) != signf(_wheel_notches):
		_wheel_notches = 0
	_wheel_notches += notches
	if absf(_wheel_notches) < 1 - PixelZoom.EPSILON:
		return
	_wheel_notches = 0
	zoom_by(1 + zoom_speed if notches > 0 else 1 / (1 + zoom_speed), anchor)


func _on_left_press(event: InputEventMouseButton) -> void:
	if _pan_key_held:
		_start_drag(Drag.PAN, event.position)
		return
	if picking:
		var pixel := Vector2i(screen_to_world(event.position).floor())
		var info := PixelGrid.probe(self, get_cell_at_screen_position(event.position), pixel)
		if info.has("color"):
			color_picked.emit(info.color)
		return
	_drag_start_world = screen_to_world(event.position)
	_drag_start_cell = get_cell_at_screen_position(event.position)
	var toggling := event.is_command_or_control_pressed()
	var adding := event.shift_pressed
	_box_mode = Box.TOGGLE if toggling else (Box.ADD if adding else Box.REPLACE)
	pivots.hover(self, event.position)
	if not (toggling or adding) and pivots.is_hovered(self):
		_press = Press.PIVOT
	elif _drags_frame(_drag_start_cell, toggling or adding):
		_press = Press.MOVE
	else:
		_press = Press.BOX
	_start_drag(Drag.PENDING, event.position)


func _on_left_release(event: InputEventMouseButton) -> void:
	var drag := _drag
	_end_drag()
	match drag:
		Drag.PENDING:
			_click(_drag_start_cell, event)
		Drag.BOX:
			_finish_box_selection()
		Drag.MOVE:
			mover.put_down(self)
		Drag.PIVOT:
			pivot_requested.emit(pivots.targets, pivots.pivot)
			pivots.release()
			queue_redraw()


## Puts back what's being dragged, as it was before the press. Whether something was.
func _cancel_drag() -> bool:
	if _drag not in [Drag.PENDING, Drag.BOX, Drag.MOVE, Drag.PIVOT]:
		return false
	mover.drop()
	pivots.release()
	_end_drag()
	return true


## Arrow keys move the selected frames inside their cells, or on their page, by a pixel or
## 8 with Shift, or onto the next guide with Shift+Alt; Ctrl+arrow adds the next frame
## that way to the selection. Whether [param event] was handled. Ctrl+Shift and Alt are
## left to shortcuts, like moving rows.
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
	if event.alt_pressed or event.is_command_or_control_pressed():
		return _handle_modified_arrow(event, direction)
	if not able_to_move_frames:
		return false
	if _selected.is_empty():
		return true
	var step := direction * (BIG_NUDGE if event.shift_pressed else 1)
	var coords := get_selected_coords()
	if is_packed():
		# Frames that wouldn't fit where they'd go stay put
		var page: int = spritesheet.placements[coords[0]].page
		if not PackedLayout.moved(spritesheet, coords, page, step).is_empty():
			placement_move_requested.emit(coords, page, step)
	else:
		nudge_requested.emit(coords, step)
	return true


## Ctrl+arrow adds the next frame that way to the selection, and Shift+Alt+arrow moves the
## selected frames onto the next guide that way. Whether [param event] was handled.
func _handle_modified_arrow(event: InputEventKey, direction: Vector2i) -> bool:
	if not event.alt_pressed and not event.shift_pressed:
		_extend_selection(direction)
		return true
	if not event.alt_pressed or not event.shift_pressed or event.is_command_or_control_pressed():
		return false
	if able_to_move_frames and guides.shown and not _selected.is_empty():
		guide_snap_requested.emit(get_selected_coords(), direction)
	return true


## Adds the next frame from the last one picked in [param direction] to the selection, or
## picks the first frame when none is
func _extend_selection(direction: Vector2i) -> void:
	var from := _anchor if spritesheet.has_frame(_anchor) else spritesheet.get_sorted_coords()[0]
	if _selected.is_empty():
		set_selected_coords([from] as Array[Vector2i])
		_anchor = from
		return
	var cell := from + direction
	if is_packed():
		cell = packed_view.get_neighbour(from, direction)
	while spritesheet.is_inside(cell) and not spritesheet.has_frame(cell):
		cell += direction
	if not spritesheet.has_frame(cell):
		# Nothing further that way
		cell = from
	_selected[cell] = true
	_anchor = cell
	_selection_updated()


## A press and release without dragging
func _click(cell: Vector2i, event: InputEventMouseButton) -> void:
	var toggling := event.is_command_or_control_pressed()
	if spritesheet.has_frame(cell):
		if event.shift_pressed:
			_select_range(cell, toggling)
		elif toggling:
			_toggle(cell)
			_anchor = cell
		else:
			set_selected_coords([cell] as Array[Vector2i])
			_anchor = cell
	elif cell != NO_CELL and able_to_lock_spaces and not is_packed():
		# The selection stays: clicking outside the cells selects nothing
		lock_requested.emit(cell, not spritesheet.is_locked(cell))
	elif not (toggling or event.shift_pressed) and not _selected.is_empty():
		select_all(false)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_out(event.position):
		return
	var pixel := Vector2i(screen_to_world(event.position).floor())
	if pixel != hovered_pixel:
		hovered_pixel = pixel
		pixel_hovered.emit()
	_set_hovered_cell(get_cell_at_screen_position(event.position))
	if _drag == Drag.NONE and pivots.hover(self, event.position):
		queue_redraw()
	match _drag:
		Drag.PAN:
			camera.position = (
				_drag_start_camera - (event.position - _drag_start_screen) / camera.zoom
			)
			queue_redraw()
		Drag.PENDING:
			if event.position.distance_to(_drag_start_screen) >= DRAG_THRESHOLD:
				_begin_real_drag()
				_update_drag(event.position)
		_:
			_update_drag(event.position)
	update_cursor()


## Follows the mouse at [param screen_position] with the box, the frames or the pivot
## being dragged
func _update_drag(screen_position: Vector2) -> void:
	var world := screen_to_world(screen_position)
	var changed := true
	match _drag:
		Drag.BOX:
			_box_end_world = world
		Drag.PIVOT:
			pivots.drag_to(self, world)
		Drag.MOVE:
			changed = mover.follow(self, world)
	if changed:
		queue_redraw()


## Hands the frames being moved over with [signal frames_dragged_out] when they're
## dragged out of the preview, see [member drag_frames_out]. Whether they were.
func _drag_out(screen_position: Vector2) -> bool:
	if not drag_frames_out or _drag != Drag.MOVE or get_viewport_rect().has_point(screen_position):
		return false
	mover.carried = true
	_end_drag()
	frames_dragged_out.emit(mover.lifted.duplicate())
	return true


## Moves the frames dragged out, see [signal frames_dragged_out], again while they're
## back over the preview at [param screen_position], showing where they'd land
func carry_back(screen_position: Vector2) -> void:
	if not mover.carried:
		return
	if _drag != Drag.MOVE:
		_drag = Drag.MOVE
		mover.show_card(false)
	_set_hovered_cell(get_cell_at_screen_position(screen_position))
	_update_drag(screen_position)
	queue_redraw()
	update_cursor()


## Stops showing where the frames dragged out would land, once they're off the preview
func carry_away() -> void:
	if mover.carried and _drag == Drag.MOVE:
		_drag = Drag.NONE
		mover.show_card(true)
		queue_redraw()


func _can_drop_back(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("sheet_preview") == get_instance_id()):
		return false
	carry_back(at)
	return mover.carried


## Frames dragged out and dropped back move where they're dropped
func _drop_back(at: Vector2, _data: Variant) -> void:
	carry_back(at)
	if _drag == Drag.MOVE:
		mover.put_down(self)
	_end_carry()


func _end_carry() -> void:
	mover.drop()
	_end_drag()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and mover.carried:
		_end_carry()


## Turns a pending press into a box selection, a move or moving a pivot
func _begin_real_drag() -> void:
	match _press:
		Press.PIVOT:
			_drag = Drag.PIVOT
			pivots.grab(self, pivots.hovered, _drag_start_world)
		Press.MOVE:
			# The selection moves when the frame is in it, else the frame alone
			if not is_selected(_drag_start_cell):
				set_selected_coords([_drag_start_cell] as Array[Vector2i])
				_anchor = _drag_start_cell
			_drag = Drag.MOVE
			mover.lift(self, get_selected_coords(), _drag_start_world)
		Press.BOX:
			_drag = Drag.BOX
			_box_end_world = _drag_start_world
	update_cursor()


## Whether pressing [param cell] and dragging moves it, see [method _begin_real_drag]: a
## frame, when frames can move and the press doesn't draw a box with Shift or Ctrl
func _drags_frame(cell: Vector2i, boxing: bool) -> bool:
	return able_to_move_frames and not boxing and spritesheet.has_frame(cell)


## The frames being moved, in reading order
func _get_lifted_coords() -> Array[Vector2i]:
	return mover.lifted if _drag == Drag.MOVE else ([] as Array[Vector2i])


## The frames whose cells, or places on the pages, touch [param rect]
func get_frames_in(rect: Rect2) -> Array[Vector2i]:
	if is_packed():
		return packed_view.get_frames_in(rect)
	var coords: Array[Vector2i] = []
	for coord in spritesheet.frames:
		if rect.intersects(cell_rect(coord)):
			coords.append(coord)
	return coords


func _finish_box_selection() -> void:
	var coords := get_frames_in(_box_rect())
	if _box_mode == Box.REPLACE:
		_selected.clear()
	for coord in coords:
		if _box_mode == Box.TOGGLE and _selected.has(coord):
			_selected.erase(coord)
		else:
			_selected[coord] = true
	_selection_updated()


func _box_rect() -> Rect2:
	var start := screen_to_world(_drag_start_screen)
	return Rect2(start, Vector2.ZERO).expand(_box_end_world)


func _start_drag(kind: Drag, screen_position: Vector2) -> void:
	_drag = kind
	_drag_start_screen = screen_position
	_drag_start_camera = camera.position
	update_cursor()


func _end_drag() -> void:
	_drag = Drag.NONE
	queue_redraw()
	update_cursor()


## Shows the cursor for what pressing or dragging where the mouse is does, see
## [method get_cursor_hint]
func update_cursor() -> void:
	CanvasCursor.apply(surface, get_cursor_hint())


## What pressing or dragging where the mouse is does, or what's being dragged: panning,
## picking a colour, moving frames, drawing a box, moving a pivot or clicking a name
func get_cursor_hint() -> CanvasCursor.Hint:
	if _drag == Drag.PAN or _pan_key_held:
		return CanvasCursor.Hint.PAN
	if picking:
		return CanvasCursor.Hint.PICK
	match _drag:
		Drag.MOVE:
			return CanvasCursor.Hint.MOVE if mover.fits else CanvasCursor.Hint.FORBIDDEN
		Drag.BOX:
			return CanvasCursor.Hint.BOX
		Drag.PIVOT, Drag.PENDING:
			return CanvasCursor.Hint.POINT if _drag == Drag.PIVOT else PRESS_HINTS[_press]
	return _hover_hint()


## What pressing or dragging does where the mouse is, over a name, a pivot or a frame
func _hover_hint() -> CanvasCursor.Hint:
	if mover.carried:
		return CanvasCursor.Hint.NONE
	if animation_labels.hovered >= 0:
		return CanvasCursor.Hint.LINK
	if pivots.is_hovered(self):
		return CanvasCursor.Hint.POINT
	var boxing := (
		Input.is_key_pressed(KEY_SHIFT)
		or Input.is_key_pressed(KEY_CTRL)
		or Input.is_key_pressed(KEY_META)
	)
	return CanvasCursor.Hint.GRAB if _drags_frame(hovered_cell, boxing) else CanvasCursor.Hint.NONE


## Forgets the cell under the mouse, e.g. when the mouse leaves the preview or another
## document opens. Frames dragged out stop showing where they'd land.
func clear_hover() -> void:
	carry_away()
	pivots.hovered = NO_CELL
	_set_hovered_cell(NO_CELL)
	update_cursor()


func _set_hovered_cell(cell: Vector2i) -> void:
	if cell != hovered_cell:
		hovered_cell = cell
		queue_redraw()
		hover_changed.emit(cell)


#endregion

#region Drawing


func _draw() -> void:
	draw_rect(_visible_world_rect(), background_color)
	if is_packed():
		_draw_packed()
		return
	var cell_size := Vector2(spritesheet.sprite_size)
	if cell_size.x <= 0 or cell_size.y <= 0 or spritesheet.grid_size == Vector2i.ZERO:
		return
	var pixel := 1.0 / camera.zoom.x
	var visible_rect := _visible_world_rect()
	# Frames being moved leave their cells
	var lifted := _as_set(_get_lifted_coords())
	var hovered := hovered_cell if _drag == Drag.NONE else NO_CELL
	grid_view.draw(self, visible_rect, pixel, lifted, hovered)
	guides.draw(self, grid_view.get_visible_cells(visible_rect), pixel)
	_draw_selection(pixel)
	animation_labels.draw(self)
	if is_index_visible():
		_draw_indices(grid_view.get_visible_cells(visible_rect))
	pivots.draw(self, pixel, _drag == Drag.MOVE)
	_draw_box(pixel)


## The pages, the selection and where dragged frames would go
func _draw_packed() -> void:
	var pixel := 1.0 / camera.zoom.x
	var visible_rect := _visible_world_rect()
	packed_view.draw(self, visible_rect, pixel, _as_set(_get_lifted_coords()))
	var hovered := packed_view.get_frame_rect(hovered_cell)
	if spritesheet.placements.has(hovered_cell) and _drag == Drag.NONE:
		draw_rect(hovered, HOVER_COLOR)
	for coord in _selected:
		var rect := packed_view.get_frame_rect(coord)
		draw_rect(rect, Color(selection_color, selection_tint))
		draw_rect(rect.grow(-pixel), selection_color, false, pixel * 2)
	if _drag == Drag.MOVE:
		mover.draw(self, pixel)
	if show_indices:
		for coord in packed_view.get_frames_in(visible_rect):
			var rect := packed_view.get_frame_rect(coord)
			if rect.size * camera.zoom >= MIN_SIZE_TO_SHOW_INDEX:
				_draw_index(coord, rect)
		draw_set_transform(Vector2.ZERO)
	pivots.draw(self, pixel, _drag == Drag.MOVE)
	_draw_box(pixel)


func _draw_box(pixel: float) -> void:
	if _drag == Drag.BOX:
		var box := _box_rect()
		draw_rect(box, Color(selection_color, 0.15))
		draw_rect(box, selection_color, false, pixel)


## Checker squares behind transparent pixels, the same size on screen at any zoom
func draw_checkerboard(rect: Rect2, pixel: float) -> void:
	var scale_factor := checker_size * pixel
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	draw_texture_rect(_checker, Rect2(rect.position / scale_factor, rect.size / scale_factor), true)
	draw_set_transform(Vector2.ZERO)


## Shows each image of [param images] in place of the frame image it's keyed by, already
## at the sheet's scale, without changing the sheet, e.g. to preview an edit. Frames whose
## image changed show their own again. Empty shows every frame's own image.
func show_instead(images: Dictionary[Image, Image]) -> void:
	for img: Image in _shown_instead.values():
		_textures.erase(img)
	_shown_instead = images
	queue_redraw()


## The texture to draw a frame with, and how many of its pixels make a scaled pixel.
## While frames are scaled in the background, the original is stretched instead.
func get_frame_texture(coord: Vector2i) -> Dictionary:
	var img := spritesheet.frames[coord]
	var shown_scale := spritesheet.frame_scale
	var instead: Image = _shown_instead.get(img)
	if instead and instead.get_size() == spritesheet.scaled_frames.scaled_size(img.get_size()):
		img = instead
		shown_scale = Vector2.ONE
	elif spritesheet.scaled_frames.is_ready(coord) or not spritesheet.scaled_frames.is_preparing():
		img = spritesheet.get_frame_image(coord)
		shown_scale = Vector2.ONE
	if not _textures.has(img):
		_textures[img] = ImageTexture.create_from_image(img)
	return {"texture": _textures[img], "scale": shown_scale}


func _draw_selection(pixel: float) -> void:
	for coord in _selected:
		var rect := cell_rect(coord)
		draw_rect(rect, Color(selection_color, selection_tint))
		draw_rect(rect.grow(-pixel), selection_color, false, pixel * 2)
	if _drag == Drag.MOVE:
		mover.draw(self, pixel)


func _draw_indices(visible_cells: Rect2i) -> void:
	for coord in spritesheet.frames:
		if not visible_cells.has_point(coord) or _is_index_under_label(coord):
			continue
		_draw_index(coord, cell_rect(coord))
	draw_set_transform(Vector2.ZERO)


## Whether an animation's name is drawn where the frame's number would be
func _is_index_under_label(coord: Vector2i) -> bool:
	var corner := (cell_rect(coord).position - camera.position) * camera.zoom
	return animation_labels.covers(Rect2(corner + Vector2(4, 2), Vector2(36, INDEX_FONT_SIZE + 6)))


## The frame's number in the top-left corner of [param rect]
func _draw_index(coord: Vector2i, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	# Text is drawn unscaled so it keeps the same size at any zoom
	draw_set_transform(rect.position, 0, Vector2.ONE / camera.zoom)
	var text := str(spritesheet.index_of(coord) + index_start)
	var text_position := Vector2(6, 4 + INDEX_FONT_SIZE)
	draw_string_outline(
		font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, INDEX_FONT_SIZE, 6, Color.BLACK
	)
	draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, INDEX_FONT_SIZE)


func _visible_world_rect() -> Rect2:
	return Rect2(camera.position, get_viewport_rect().size / camera.zoom)


static func _as_set(coords: Array[Vector2i]) -> Dictionary[Vector2i, bool]:
	var coords_set: Dictionary[Vector2i, bool] = {}
	for coord in coords:
		coords_set[coord] = true
	return coords_set

#endregion
