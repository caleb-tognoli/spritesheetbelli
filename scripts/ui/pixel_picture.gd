class_name PixelPicture
extends Control
## A picture over a checkerboard, centred and as big as fits: a whole number of times its
## size when it fits more than once, so its pixels stay square.

## Side of the checkerboard's squares
const SQUARE := 6

static var _checker: ImageTexture

var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## How opaque the picture is, e.g. faded while it's being made again
var opacity := 1.0:
	set(value):
		opacity = value
		queue_redraw()


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	clip_contents = true


## Where a picture [param picture] big shows in [param room]: centred, as big as fits, a
## whole number of times its size when it fits more than once
static func fit(picture: Vector2, room: Vector2) -> Rect2:
	if picture.x <= 0.0 or picture.y <= 0.0:
		return Rect2(room / 2.0, Vector2.ZERO)
	var zoom := minf(room.x / picture.x, room.y / picture.y)
	if zoom >= 1.0:
		zoom = floorf(zoom)
	var shown := picture * zoom
	return Rect2(((room - shown) / 2.0).floor(), shown)


func _draw() -> void:
	if _checker == null:
		_checker = ImageUtils.checker_texture(SQUARE)
	draw_texture_rect(_checker, Rect2(Vector2.ZERO, size), true)
	if texture:
		var rect := fit(texture.get_size(), size)
		draw_texture_rect(texture, rect, false, Color(1, 1, 1, opacity))
