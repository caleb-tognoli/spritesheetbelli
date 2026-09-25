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
## pixels (those at least half opaque). The image grows by the thickness on every side,
## so the outline always fits. With [param corners], diagonal neighbours are outlined too,
## which makes square corners instead of round ones.
static func outline(img: Image, color: Color, thickness := 1, corners := false) -> Image:
	var size := img.get_size() + Vector2i.ONE * thickness * 2
	var result := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	result.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ONE * thickness)
	var data := result.get_data()
	var solid := PackedByteArray()
	solid.resize(size.x * size.y)
	for i in solid.size():
		solid[i] = 1 if data[i * 4 + 3] >= 128 else 0
	var inside := solid.duplicate()
	var neighbours: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	if corners:
		neighbours.append_array(
			[Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
		)
	# Grow the solid area one pixel at a time
	for step in thickness:
		var grown := solid.duplicate()
		for y in size.y:
			for x in size.x:
				if solid[y * size.x + x]:
					continue
				for offset in neighbours:
					var n := Vector2i(x, y) + offset
					if n.x >= 0 and n.y >= 0 and n.x < size.x and n.y < size.y:
						if solid[n.y * size.x + n.x]:
							grown[y * size.x + x] = 1
							break
		solid = grown
	var rgba := PackedByteArray([color.r8, color.g8, color.b8, color.a8])
	for i in solid.size():
		if solid[i] and not inside[i]:
			for channel in 4:
				data[i * 4 + channel] = rgba[channel]
	result.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
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
