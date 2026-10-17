class_name ImageUtils
## Image helpers shared by editing and export.

## Godot can't create images with more pixels than this
const MAX_PIXELS := 1 << 28
## Largest texture side, so bigger frames couldn't be shown in the preview
const MAX_TEXTURE_SIZE := 16384
## Images with at least this many pixels are colour keyed on worker threads
const THREADED_PIXELS := 1 << 18


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


## Makes pixels close to [param color] transparent. [param tolerance] is 0 to 1. With
## [param contiguous], only those reaching the edges of the image through each other (up,
## down, left and right, not diagonally) are, so the same colour inside sprites stays.
## Transparent pixels are passed through, like a margin around a frame. Big images are
## keyed in parts on worker threads, so trying tolerances on a whole sheet stays quick.
static func color_key(img: Image, color: Color, tolerance := 0.1, contiguous := false) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Working on the raw bytes is much faster than get_pixel and set_pixel
	var data := img.get_data()
	var max_distance := (tolerance * 255.0) ** 2 * 3.0
	if contiguous:
		var mask := _in_parts(
			data,
			func(part: PackedByteArray) -> PackedByteArray:
				return _match_bytes(part, color, max_distance)
		)
		# Pixels reach each other across the parts, so the fill can't be split
		_fill_from_edges(data, mask, img.get_width(), img.get_height())
	else:
		data = _in_parts(
			data,
			func(part: PackedByteArray) -> PackedByteArray:
				_key_bytes(part, color, max_distance)
				return part
		)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## [param work] done on the RGBA pixels in [param data], joined: in parts on worker
## threads when there are many
static func _in_parts(data: PackedByteArray, work: Callable) -> PackedByteArray:
	var pixels := data.size() / 4
	# Only the main thread waits for others, so work already on a worker thread stays there
	var on_main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	if pixels < THREADED_PIXELS or not OS.has_feature("threads") or not on_main:
		return work.call(data)
	var count := OS.get_processor_count() * 2
	var parts := []
	parts.resize(count)
	var mutex := Mutex.new()
	var work_on_part := func(i: int) -> void:
		var part: PackedByteArray = work.call(
			data.slice(pixels * i / count * 4, pixels * (i + 1) / count * 4)
		)
		mutex.lock()
		parts[i] = part
		mutex.unlock()
	var task := WorkerThreadPool.add_group_task(work_on_part, count)
	WorkerThreadPool.wait_for_group_task_completion(task)
	var result := PackedByteArray()
	for part: PackedByteArray in parts:
		result.append_array(part)
	return result


## Whether each of the RGBA pixels in [param data] can be filled through by
## [method _fill_from_edges]: 1 when it's transparent or within [param max_distance]
## (squared) of [param color], else 0
static func _match_bytes(
	data: PackedByteArray, color: Color, max_distance: float
) -> PackedByteArray:
	var r := color.r8
	var g := color.g8
	var b := color.b8
	var mask := PackedByteArray()
	mask.resize(data.size() / 4)
	for p in mask.size():
		var i := p * 4
		var dr := data[i] - r
		var dg := data[i + 1] - g
		var db := data[i + 2] - b
		mask[p] = 1 if data[i + 3] == 0 or dr * dr + dg * dg + db * db <= max_distance else 0
	return mask


## Clears the alpha of the RGBA pixels in [param data], [param width] by [param height],
## that [param mask] (from [method _match_bytes]) lets through from the edges, up, down,
## left and right. A row at a time: each run of pixels found is filled whole, and the runs
## touching it above and below are filled after.
static func _fill_from_edges(
	data: PackedByteArray, mask: PackedByteArray, width: int, height: int
) -> void:
	var stack := PackedInt32Array()
	for x in width:
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y in range(1, height - 1):
		stack.append(y * width)
		stack.append(y * width + width - 1)
	while not stack.is_empty():
		var p := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		# Filled since, or not to be
		if mask[p] != 1:
			continue
		var row := p - p % width
		var left := p
		while left > row and mask[left - 1] == 1:
			left -= 1
		var right := p
		while right < row + width - 1 and mask[right + 1] == 1:
			right += 1
		var has_above := row > 0
		var has_below := row + width < mask.size()
		# Whether the pixel before was already put on the stack as part of a run
		var above_queued := false
		var below_queued := false
		for q in range(left, right + 1):
			mask[q] = 2
			data[q * 4 + 3] = 0
			if has_above:
				var open := mask[q - width] == 1
				if open and not above_queued:
					stack.append(q - width)
				above_queued = open
			if has_below:
				var open := mask[q + width] == 1
				if open and not below_queued:
					stack.append(q + width)
				below_queued = open


## Clears the alpha of the RGBA pixels in [param data] within [param max_distance] (squared)
## of [param color]
static func _key_bytes(data: PackedByteArray, color: Color, max_distance: float) -> void:
	var r := color.r8
	var g := color.g8
	var b := color.b8
	for i in range(0, data.size(), 4):
		var dr := data[i] - r
		var dg := data[i + 1] - g
		var db := data[i + 2] - b
		if dr * dr + dg * dg + db * db <= max_distance:
			data[i + 3] = 0


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
