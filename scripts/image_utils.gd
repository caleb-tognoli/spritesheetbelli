class_name ImageUtils
## Image helpers shared by editing and export.


## Makes pixels close to [param color] transparent. [param tolerance] is 0 to 1.
static func color_key(img: Image, color: Color, tolerance := 0.1) -> void:
	var max_distance := tolerance * tolerance * 3.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var distance := (
				(c.r - color.r) * (c.r - color.r)
				+ (c.g - color.g) * (c.g - color.g)
				+ (c.b - color.b) * (c.b - color.b)
			)
			if distance <= max_distance:
				img.set_pixel(x, y, Color(c, 0.0))


## Whether any pixel is not fully opaque
static func has_transparency(img: Image) -> bool:
	return img.detect_alpha() != Image.ALPHA_NONE


## Draws [param img] over a solid [param background], removing transparency
static func flatten(img: Image, background: Color) -> Image:
	var flat := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(background, 1.0))
	flat.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	return flat


## A tileable checkerboard texture with squares of [param square] pixels
static func checker_texture(
	square: int, dark := Color(0.36, 0.36, 0.36), light := Color(0.42, 0.42, 0.42)
) -> ImageTexture:
	var img := Image.create_empty(square * 2, square * 2, false, Image.FORMAT_RGBA8)
	img.fill(light)
	img.fill_rect(Rect2i(0, 0, square, square), dark)
	img.fill_rect(Rect2i(square, square, square, square), dark)
	return ImageTexture.create_from_image(img)
