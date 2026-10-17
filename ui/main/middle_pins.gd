class_name MiddlePins
extends Control
## The frame halfway between two keys, big enough to pin (see [method InBetween.middle]).
## Clicking the sprite adds a pin, dragging a pin moves that spot, right-clicking a pin
## takes it away. A pin left where it was holds its spot still. Pins are in sheet space,
## the same place frames are put in, see [member pins].

## Emitted when [member pins] change: with [param done] false while a pin is dragged, and
## true once it's let go, added, taken away or all cleared
signal pins_changed(done: bool)

## On-screen size of a pin
const SIZE := 5.0
## How near a pin on screen pressing grabs it
const REACH := 9.0
## How much room is left around the keys to drag pins into, as a part of their longest side
const MARGIN := 0.125

## The pins, each [code]{"at": Vector2, "to": Vector2}[/code] in sheet space: a pixel of the
## sprite as the middle frame shows it without pins, and where it should be. A pin with
## [code]at[/code] and [code]to[/code] the same holds its spot still.
var pins: Array[Dictionary] = []
## The part of the sheet shown, see [method show_keys]
var area := Rect2i(0, 0, 1, 1)
## The pin being dragged, or -1
var dragged := -1

var _texture: ImageTexture
## Where the dragged pin is from the mouse in sheet space, so it doesn't jump when grabbed
var _grab := Vector2.ZERO


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Shows the room around keys [param a] and [param b] (see [method InBetween.key_of]), with
## nothing on it and no pins, until [method show_frame]
func show_keys(a: Dictionary, b: Dictionary) -> void:
	var keys := Rect2i(a.origin, (a.image as Image).get_size())
	keys = keys.merge(Rect2i(b.origin, (b.image as Image).get_size()))
	area = keys.grow(maxi(2, ceili(maxi(keys.size.x, keys.size.y) * MARGIN)))
	_texture = null
	remove_all(false)


## Shows [param frame], an image with where it's placed (its [code]origin[/code]), cut to
## [member area]
func show_frame(frame: Dictionary) -> void:
	var canvas := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
	var img: Image = frame.image
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), frame.origin - area.position)
	_texture = ImageTexture.create_from_image(canvas)
	queue_redraw()


## Whether a frame is shown, so it can be pinned
func has_frame() -> bool:
	return _texture != null


## Takes every pin away, telling with [signal pins_changed] when [param notify]
func remove_all(notify := true) -> void:
	dragged = -1
	if pins.is_empty():
		return
	pins.clear()
	queue_redraw()
	if notify:
		pins_changed.emit(true)


## How many times bigger than the sheet the frame shows: a whole number when it fits
## more than once, so pixels stay square
func get_zoom() -> float:
	var fit := minf(size.x / area.size.x, size.y / area.size.y)
	return floorf(fit) if fit >= 1.0 else fit


## Where the frame shows, centred
func get_picture_rect() -> Rect2:
	var shown := Vector2(area.size) * get_zoom()
	return Rect2(((size - shown) / 2.0).floor(), shown)


## The point of the sheet at [param at] on screen
func to_sheet(at: Vector2) -> Vector2:
	return Vector2(area.position) + (at - get_picture_rect().position) / get_zoom()


## Where [param point] of the sheet is on screen, the opposite of [method to_sheet]
func to_screen(point: Vector2) -> Vector2:
	return get_picture_rect().position + (point - Vector2(area.position)) * get_zoom()


## Where pin [param index] shows on screen: in the middle of the pixel it's on
func get_handle(index: int) -> Vector2:
	return to_screen(pins[index].to + Vector2(0.5, 0.5))


## The pin at [param at] on screen, the one on top when they're close, or -1
func pin_at(at: Vector2) -> int:
	for i in range(pins.size() - 1, -1, -1):
		if get_handle(i).distance_to(at) <= REACH:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if not has_frame():
			return
		var index := pin_at(button.position)
		if index < 0:
			var spot := _pixel_at(button.position)
			pins.append({"at": spot, "to": spot})
			index = pins.size() - 1
			queue_redraw()
		dragged = index
		_grab = pins[index].to - to_sheet(button.position)
		accept_event()
	elif button and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if dragged >= 0:
			dragged = -1
			pins_changed.emit(true)
			accept_event()
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		var index := pin_at(button.position)
		if index >= 0 and dragged < 0:
			pins.remove_at(index)
			queue_redraw()
			pins_changed.emit(true)
			accept_event()
	var motion := event as InputEventMouseMotion
	if motion and dragged >= 0:
		var to := (to_sheet(motion.position) + _grab).round()
		to = to.clamp(Vector2(area.position), Vector2(area.end - Vector2i.ONE))
		if to != pins[dragged].to:
			pins[dragged].to = to
			queue_redraw()
			pins_changed.emit(false)
	elif motion:
		var on_pin := pin_at(motion.position) >= 0
		mouse_default_cursor_shape = Control.CURSOR_MOVE if on_pin else Control.CURSOR_CROSS


## The pixel of the sheet at [param at] on screen, kept in [member area]
func _pixel_at(at: Vector2) -> Vector2:
	var pixel := to_sheet(at).floor()
	return pixel.clamp(Vector2(area.position), Vector2(area.end - Vector2i.ONE))


func _draw() -> void:
	if _texture:
		draw_texture_rect(_texture, get_picture_rect(), false)
	var accent := Global.accent_color
	var half := Vector2(0.5, 0.5)
	for i in pins.size():
		var to := get_handle(i)
		if pins[i].at == pins[i].to:
			# Holds still: a light square
			var square := Rect2(to - Vector2(SIZE, SIZE) * 0.8, Vector2(SIZE, SIZE) * 1.6)
			draw_rect(square.grow(1.0), Color.BLACK)
			draw_rect(square, Color.WHITE)
			continue
		# Moved: a line from where the spot was to a round handle in the accent colour
		var at := to_screen(pins[i].at + half)
		draw_line(at, to, Color.BLACK, 3.0)
		draw_line(at, to, accent, 1.0)
		draw_circle(at, 2.5, Color.BLACK)
		draw_circle(at, 1.5, Color.WHITE)
		draw_circle(to, SIZE + 1.0, Color.BLACK)
		draw_circle(to, SIZE, accent)
