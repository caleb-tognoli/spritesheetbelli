class_name ImageUtils
## Image helpers shared by editing and export.

## Godot can't create images with more pixels than this
const MAX_PIXELS := 1 << 28
## Largest texture side, so bigger frames couldn't be shown in the preview
const MAX_TEXTURE_SIZE := 16384


## Why an image of [param size] can't be made or saved with [param extension], or an
## empty string when it can
static func size_problem(size: Vector2i, extension := "png") -> String:
	var limit := Image.MAX_WIDTH
	match extension.to_lower():
		"webp":
			limit = 16383
		"jpg", "jpeg", "jpe":
			limit = 65535
	if size.x > limit or size.y > limit:
		return (
			TranslationServer.translate(
				"The image would be %d×%d px, but %s images can be at most %d px wide and tall."
			)
			% [size.x, size.y, extension.to_upper(), limit]
		)
	if size.x * size.y > MAX_PIXELS:
		return (
			TranslationServer.translate(
				"The image would be %d×%d px, more than the %d million pixels Godot can handle."
			)
			% [size.x, size.y, MAX_PIXELS / 1000000]
		)
	return ""


## Makes pixels close to [param color] transparent. [param tolerance] is 0 to 1.
static func color_key(img: Image, color: Color, tolerance := 0.1) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Working on the raw bytes is much faster than get_pixel and set_pixel
	var data := img.get_data()
	var r := color.r8
	var g := color.g8
	var b := color.b8
	var max_distance := (tolerance * 255.0) ** 2 * 3.0
	for i in range(0, data.size(), 4):
		var dr := data[i] - r
		var dg := data[i + 1] - g
		var db := data[i + 2] - b
		if dr * dr + dg * dg + db * db <= max_distance:
			data[i + 3] = 0
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## [param img] with an outline of [param thickness] pixels in [param color] around its
## pixels. The image grows by the thickness on every side, so the outline always fits.
## The outline is round, or square with [param corners].
static func outline(img: Image, color: Color, thickness := 1, corners := false) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size() + Vector2i.ONE * thickness * 2
	var full := Rect2i(Vector2i.ZERO, size)
	var base := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	base.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ONE * thickness)
	var fill := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	fill.fill(color)
	var result := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	# The outline is the pixels, shifted by every offset within the thickness
	if corners:
		# A square grows the same across, then down, which is much quicker
		var wide := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		for x in range(-thickness, thickness + 1):
			wide.blit_rect_mask(base, base, full, Vector2i(x, 0))
		for y in range(-thickness, thickness + 1):
			result.blit_rect_mask(fill, wide, full, Vector2i(0, y))
	else:
		for y in range(-thickness, thickness + 1):
			for x in range(-thickness, thickness + 1):
				if x * x + y * y <= thickness * thickness:
					result.blit_rect_mask(fill, base, full, Vector2i(x, y))
	result.blend_rect(base, full, Vector2i.ZERO)
	return result


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
