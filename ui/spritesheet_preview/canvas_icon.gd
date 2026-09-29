class_name CanvasIcon
extends RefCounted
## An icon drawn over the sprites of a [SpritesheetPreview], like the lock on locked cells.
## Over sprites both themes look the same, so it keeps its own colours.
##
## It's drawn from a raster of its SVG made at the size it takes on screen, a texture
## pixel on each screen pixel. Stretching the icon's own small raster instead would make
## it blocky, as the preview samples textures with the nearest filter for the sprites.

## The SVG, and its size at scale 1
var _source: String
var _base_size: float
## The rasters made so far, by size in screen pixels
var _rasters: Dictionary[int, ImageTexture] = {}


func _init(icon: DPITexture) -> void:
	_source = icon.get_source()
	_base_size = icon.get_width() / icon.base_scale


## Draws the icon over the square [param rect] of the preview, in world coordinates,
## snapped to whole screen pixels
func draw(canvas: SpritesheetPreview, rect: Rect2, modulate := Color.WHITE) -> void:
	# From the world to the pixels the preview is rendered to
	var zoom := canvas.camera.zoom
	var to_screen := (
		canvas.get_viewport().get_final_transform()
		* Transform2D(0, zoom, 0, -canvas.camera.position * zoom)
	)
	var pixels := roundi(rect.size.x * to_screen.get_scale().x)
	if pixels <= 0:
		return
	var texture := get_raster(pixels)
	var on_screen := Rect2(Vector2.ZERO, texture.get_size())
	on_screen.position = (to_screen * rect.get_center() - on_screen.size / 2).round()
	canvas.draw_set_transform_matrix(to_screen.affine_inverse())
	canvas.draw_texture_rect(texture, on_screen, false, modulate)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## The icon rasterised [param pixels] wide, made once for each size
func get_raster(pixels: int) -> ImageTexture:
	if not _rasters.has(pixels):
		var svg := DPITexture.create_from_string(_source, pixels / _base_size)
		_rasters[pixels] = ImageTexture.create_from_image(svg.get_image())
	return _rasters[pixels]
