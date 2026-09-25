class_name GifDecoder
## Reads animated (and still) GIFs into whole frames, the way they're shown: each frame
## is drawn over what the previous ones left, following their disposal methods.

const EXTENSION := "gif"


static func is_gif_path(path: String) -> bool:
	return path.get_extension().to_lower() == EXTENSION


## Reads the GIF at [param path], see [method decode]
static func load_file(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"error": TranslationServer.translate("Could not open %s.") % path.get_file()}
	var result := decode(bytes)
	for frame: Image in result.get("frames", []):
		frame.resource_name = path.get_file()
	return result


## Returns [code]{"frames": Array[Image], "delays": Array[float], "loop": bool}[/code]
## with the delays in seconds, or [code]{"error": String}[/code].
static func decode(bytes: PackedByteArray) -> Dictionary:
	var header := bytes.slice(0, 6).get_string_from_ascii()
	if bytes.size() < 13 or header not in ["GIF87a", "GIF89a"]:
		return {"error": "This isn't a GIF image."}
	var size := Vector2i(bytes.decode_u16(6), bytes.decode_u16(8))
	if size.x <= 0 or size.y <= 0:
		return {"error": "This GIF is empty."}
	var flags := bytes[10]
	var at := 13
	var global_palette := PackedByteArray()
	if flags & 0x80:
		var palette_size := 3 << ((flags & 0x07) + 1)
		global_palette = bytes.slice(at, at + palette_size)
		at += palette_size

	var frames: Array[Image] = []
	var delays: Array[float] = []
	var loop := false
	var canvas := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	# From the graphic control extension before each image
	var delay := 0.0
	var transparent := -1
	var disposal := 0
	while at < bytes.size():
		var block := bytes[at]
		at += 1
		if block == 0x3B:  # Trailer
			break
		if block == 0x21:  # Extension
			if at >= bytes.size():
				break
			var label := bytes[at]
			at += 1
			var data := _read_sub_blocks(bytes, at)
			at = data.end
			var content: PackedByteArray = data.bytes
			if label == 0xF9 and content.size() >= 4:
				disposal = (content[0] >> 2) & 0x07
				delay = content.decode_u16(1) / 100.0
				transparent = content[3] if content[0] & 1 else -1
			elif label == 0xFF and content.slice(0, 11).get_string_from_ascii() == "NETSCAPE2.0":
				loop = true
			continue
		if block != 0x2C:  # Anything but an image here means the file is damaged
			break
		if at + 9 > bytes.size():
			break
		var rect := Rect2i(
			bytes.decode_u16(at),
			bytes.decode_u16(at + 2),
			bytes.decode_u16(at + 4),
			bytes.decode_u16(at + 6)
		)
		var image_flags := bytes[at + 8]
		at += 9
		var palette := global_palette
		if image_flags & 0x80:
			var palette_size := 3 << ((image_flags & 0x07) + 1)
			palette = bytes.slice(at, at + palette_size)
			at += palette_size
		if at >= bytes.size():
			break
		var min_code_size := bytes[at]
		at += 1
		var data := _read_sub_blocks(bytes, at)
		at = data.end
		var indices := decompress(data.bytes, min_code_size, rect.size.x * rect.size.y)
		if image_flags & 0x40:
			indices = _deinterlace(indices, rect.size)

		var before := canvas.duplicate() as Image if disposal == 3 else null
		_draw(canvas, rect, indices, palette, transparent)
		frames.append(canvas.duplicate())
		delays.append(delay)
		match disposal:
			2:  # Back to the background, which is transparent
				canvas.fill_rect(rect, Color(0, 0, 0, 0))
			3:  # Back to how it was before this frame
				canvas = before
		delay = 0.0
		transparent = -1
		disposal = 0
	if frames.is_empty():
		return {"error": "This GIF has no frames."}
	return {"frames": frames, "delays": delays, "loop": loop}


## GIF's LZW decompression of [param data] into at most [param count] palette indices
static func decompress(data: PackedByteArray, min_code_size: int, count: int) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(count)
	min_code_size = clampi(min_code_size, 2, 11)
	var clear_code := 1 << min_code_size
	var end_code := clear_code + 1
	# Each code is its prefix code followed by one index; first is the index it starts with
	var prefixes := PackedInt32Array()
	var suffixes := PackedByteArray()
	var firsts := PackedByteArray()
	var lengths := PackedInt32Array()
	for table: Variant in [prefixes, lengths]:
		table.resize(4096)
	suffixes.resize(4096)
	firsts.resize(4096)
	for code in clear_code:
		prefixes[code] = -1
		suffixes[code] = code
		firsts[code] = code
		lengths[code] = 1
	var code_size := min_code_size + 1
	var next_code := end_code + 1
	var previous := -1
	var written := 0
	var bit_buffer := 0
	var bit_count := 0
	var at := 0
	while written < count:
		while bit_count < code_size and at < data.size():
			bit_buffer |= data[at] << bit_count
			bit_count += 8
			at += 1
		if bit_count < code_size:
			break
		var code := bit_buffer & ((1 << code_size) - 1)
		bit_buffer >>= code_size
		bit_count -= code_size
		if code == clear_code:
			code_size = min_code_size + 1
			next_code = end_code + 1
			previous = -1
			continue
		if code == end_code:
			break
		if previous < 0:
			if code >= clear_code:
				break
			output[written] = code
			written += 1
			previous = code
			continue
		var known := code < next_code
		if not known and code != next_code:
			break  # Damaged data
		if next_code < 4096:
			prefixes[next_code] = previous
			suffixes[next_code] = firsts[code] if known else firsts[previous]
			firsts[next_code] = firsts[previous]
			lengths[next_code] = lengths[previous] + 1
			next_code += 1
			if next_code == 1 << code_size and code_size < 12:
				code_size += 1
		# Write the code's indices from the last one back
		var length := mini(lengths[code], count - written)
		var walk := code
		for skip in lengths[code] - length:
			walk = prefixes[walk]
		for i in range(length - 1, -1, -1):
			output[written + i] = suffixes[walk]
			walk = prefixes[walk]
		written += length
		previous = code
	return output


## Draws palette [param indices] of [param rect] onto [param canvas], skipping the
## [param transparent] index
static func _draw(
	canvas: Image,
	rect: Rect2i,
	indices: PackedByteArray,
	palette: PackedByteArray,
	transparent: int
) -> void:
	var colors := palette.size() / 3
	var width := canvas.get_width()
	var visible := rect.intersection(Rect2i(Vector2i.ZERO, canvas.get_size()))
	var pixels := canvas.get_data()
	for y in range(visible.position.y, visible.end.y):
		var row := (y - rect.position.y) * rect.size.x - rect.position.x
		for x in range(visible.position.x, visible.end.x):
			var index := indices[row + x]
			if index == transparent or index >= colors:
				continue
			var at := (y * width + x) * 4
			pixels[at] = palette[index * 3]
			pixels[at + 1] = palette[index * 3 + 1]
			pixels[at + 2] = palette[index * 3 + 2]
			pixels[at + 3] = 255
	canvas.set_data(width, canvas.get_height(), false, Image.FORMAT_RGBA8, pixels)


## Rows of an interlaced image back in order: every 8th row from 0, every 8th from 4,
## every 4th from 2, then every 2nd from 1
static func _deinterlace(indices: PackedByteArray, size: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(indices.size())
	var source_row := 0
	for pass_rows: Vector2i in [Vector2i(0, 8), Vector2i(4, 8), Vector2i(2, 4), Vector2i(1, 2)]:
		for row in range(pass_rows.x, size.y, pass_rows.y):
			var from := source_row * size.x
			for x in size.x:
				result[row * size.x + x] = indices[from + x]
			source_row += 1
	return result


## The bytes of the data sub-blocks starting at [param at], and where they end
static func _read_sub_blocks(bytes: PackedByteArray, at: int) -> Dictionary:
	var result := PackedByteArray()
	while at < bytes.size():
		var length := bytes[at]
		at += 1
		if length == 0:
			break
		result.append_array(bytes.slice(at, at + length))
		at += length
	return {"bytes": result, "end": at}
