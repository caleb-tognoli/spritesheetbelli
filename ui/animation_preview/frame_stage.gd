class_name FrameStage
extends Control
## Where [FramePlayer] shows its frames, over a checkerboard, a colour or the export
## background. The frames fit the stage until it's zoomed with the wheel (by whole
## levels with pixel-perfect zoom, see [PixelZoom]); zoomed in, dragging moves around.
## Double-clicking fits them again.

## The zoom changed, by the wheel, fitting or resizing
signal zoom_changed(zoom: float)

enum Background { CHECKERBOARD, COLOR, EXPORT }

const MIN_ZOOM := 1.0 / 16
const MAX_ZOOM := 64.0
## Room around fitted frames
const MARGIN := 6.0
## How visible the previous frame is with onion skin
const ONION_ALPHA := 0.3

## The frame shown
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## The previous frame, shown faintly behind [member texture], or null
var onion: Texture2D:
	set(value):
		onion = value
		queue_redraw()
## Size of the biggest frame, which fitting makes room for, so the zoom stays the same
## while playing
var content_size := Vector2i.ZERO:
	set(value):
		if value != content_size:
			content_size = value
			_update_zoom()
var background := Background.CHECKERBOARD:
	set(value):
		background = value
		queue_redraw()
var background_color := Color.WHITE:
	set(value):
		background_color = value
		queue_redraw()
## Colour behind the frames in the export, over the checkerboard when see-through
var export_color := Color.TRANSPARENT:
	set(value):
		export_color = value
		queue_redraw()
## Lines over the frames across x and y, in pixels from the top-left corner of their
## cells, see [method Spritesheet.get_guides]
var guides: Array[PackedInt32Array] = []:
	set(value):
		guides = value
		queue_redraw()
var zoom := 1.0
## Whether the zoom follows the stage's size, see [method fit]
var fitted := true

## Where the frames' centre is from the stage's centre, in pixels
var _pan := Vector2.ZERO
var _panning := false
## Wheel notches not yet turned into a whole zoom step
var _wheel_notches := 0.0
var _checker := ImageUtils.checker_texture(6)


func _init() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_zoom)


## Zooms so the biggest frame fits, and follows the stage's size again
func fit() -> void:
	fitted = true
	_pan = Vector2.ZERO
	_update_zoom()


## The zoom at which the biggest frame fits the stage, a whole one with pixel-perfect zoom
func get_fit_zoom() -> float:
	if content_size.x <= 0 or content_size.y <= 0:
		return 1.0
	var room := (size - Vector2.ONE * MARGIN * 2) / Vector2(content_size)
	var fitting := maxf(minf(room.x, room.y), MIN_ZOOM)
	return clampf(PixelZoom.fitting(self, fitting), MIN_ZOOM, MAX_ZOOM)


## Zooms to [param value] keeping the point under [param anchor] (in the stage's pixels)
## in place, and stops fitting
func set_zoom(value: float, anchor := size / 2) -> void:
	value = clampf(value, MIN_ZOOM, MAX_ZOOM)
	var centre := size / 2 + _pan
	var from_centre := (anchor - centre) / zoom
	zoom = value
	fitted = false
	_pan = anchor - from_centre * zoom - size / 2
	_clamp_pan()
	queue_redraw()
	zoom_changed.emit(zoom)


## Zooms in by [param notches] of the wheel, or out when negative, like the sheet's preview
func zoom_by_notches(notches: float, anchor := size / 2) -> void:
	var speed: float = Settings.get_value(&"zoom_speed")
	if not PixelZoom.is_on():
		var factor := 1 + speed * absf(notches)
		set_zoom(zoom * (factor if notches > 0 else 1 / factor), anchor)
		return
	# A whole zoom step per notch
	if signf(notches) != signf(_wheel_notches):
		_wheel_notches = 0
	_wheel_notches += notches
	if absf(_wheel_notches) < 1 - PixelZoom.EPSILON:
		return
	_wheel_notches = 0
	set_zoom(PixelZoom.zoom_by(self, zoom, 1 + speed if notches > 0 else 1 / (1 + speed)), anchor)


## Whether the frames are bigger than the stage, so dragging moves around
func can_pan() -> bool:
	var shown := Vector2(content_size) * zoom
	return shown.x > size.x + 0.5 or shown.y > size.y + 0.5


## Where [param frame] is drawn: centred, moved by panning, on whole pixels
func get_frame_rect(frame: Texture2D) -> Rect2:
	var shown := frame.get_size() * zoom
	return Rect2(((size - shown) / 2 + _pan).round(), shown)


func _update_zoom() -> void:
	if fitted:
		var fit_zoom := get_fit_zoom()
		if fit_zoom != zoom:
			zoom = fit_zoom
			zoom_changed.emit(zoom)
	_clamp_pan()
	queue_redraw()


## Keeps the frames covering the stage while panning, and centred along a side they fit
func _clamp_pan() -> void:
	var room := (Vector2(content_size) * zoom - size).max(Vector2.ZERO) / 2
	_pan = _pan.clamp(-room, room)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_checker, rect, true)
	if background == Background.COLOR:
		draw_rect(rect, background_color)
	elif background == Background.EXPORT:
		draw_rect(rect, export_color)
	if onion:
		draw_texture_rect(onion, get_frame_rect(onion), false, Color(1, 1, 1, ONION_ALPHA))
	if texture:
		draw_texture_rect(texture, get_frame_rect(texture), false)
		_draw_guides(get_frame_rect(texture))


## [member guides] across the stage, in the frame's cell at [param cell]
func _draw_guides(cell: Rect2) -> void:
	for axis in guides.size():
		for in_cell in guides[axis]:
			if in_cell < 0 or in_cell > cell.size[axis] / zoom:
				continue
			var from := Vector2.ZERO
			var to := size
			from[axis] = roundf(cell.position[axis] + in_cell * zoom)
			to[axis] = from[axis]
			draw_line(from, to, GuideLines.COLOR)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP when button.pressed:
				zoom_by_notches(button.factor if button.factor else 1.0, button.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN when button.pressed:
				zoom_by_notches(-(button.factor if button.factor else 1.0), button.position)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
					fit()
				_panning = button.pressed and can_pan()
				accept_event()
	var motion := event as InputEventMouseMotion
	if motion:
		mouse_default_cursor_shape = Control.CURSOR_DRAG if can_pan() else Control.CURSOR_ARROW
		if _panning:
			_pan += motion.relative
			_clamp_pan()
			queue_redraw()
	elif event is InputEventPanGesture:
		_pan -= (event as InputEventPanGesture).delta * 10
		_clamp_pan()
		queue_redraw()
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom * (event as InputEventMagnifyGesture).factor, event.position)
