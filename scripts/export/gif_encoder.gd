class_name GifEncoder
## Writes animated GIFs. Every frame shares one palette of up to 255 colours plus
## transparency; sheets with more colours are reduced to a fixed palette.

## Pixels less opaque than this are transparent, GIF has no partial transparency
const ALPHA_CUTOFF := 128
## Palette index of transparent pixels
const TRANSPARENT := 0
const MAX_COLORS := 255
## Levels of red, green and blue in the palette used when there are too many colours
const REDUCED_LEVELS := Vector3i(6, 7, 6)
## Palette indices are compressed as bytes
const LZW_MIN_CODE_SIZE := 8
## LZW tables hold at most this many codes
const MAX_CODE := 4096


## An animated GIF of [param frames], which all have the same size, each shown for its
## number of seconds in [param delays]. With [param loop] it plays forever, otherwise once.
static func encode(
	frames: Array[Image], delays: Array[float], loop := true, on_progress := Callable()
) -> PackedByteArray:
	var size := frames[0].get_size()
	var datas: Array[PackedByteArray] = []
	for frame in frames:
		var img := frame
		if img.get_format() != Image.FORMAT_RGBA8:
			img = frame.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		datas.append(img.get_data())
	var palette := build_palette(datas)

	var encoded := await Parallel.map(
		datas.size(),
		func(i: int) -> PackedByteArray: return _compress(_indices(datas[i], palette)),
		on_progress
	)

	var out := StreamPeerBuffer.new()
	out.big_endian = false
	out.put_data("GIF89a".to_ascii_buffer())
	out.put_u16(size.x)
	out.put_u16(size.y)
	out.put_u8(0xF0 | (palette.bits - 1))  # Global colour table, 8 bits per channel
	out.put_u8(TRANSPARENT)  # Background colour
	out.put_u8(0)  # Square pixels
	out.put_data(palette.table)
	if loop:
		out.put_data(PackedByteArray([0x21, 0xFF, 0x0B]))
		out.put_data("NETSCAPE2.0".to_ascii_buffer())
		out.put_data(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))
	# Delays are in hundredths of a second: round the running total, so rounding errors
	# don't add up over long animations
	var elapsed := 0.0
	var written := 0
	for i in frames.size():
		elapsed += delays[i] if i < delays.size() else 0.1
		var delay := maxi(roundi(elapsed * 100) - written, 1)
		written += delay
		# Graphic control: clear the frame before the next, transparent index
		out.put_data(PackedByteArray([0x21, 0xF9, 0x04, (2 << 2) | 1]))
		out.put_u16(delay)
		out.put_u8(TRANSPARENT)
		out.put_u8(0)
		out.put_u8(0x2C)  # Image descriptor, the whole canvas
		out.put_u16(0)
		out.put_u16(0)
		out.put_u16(size.x)
		out.put_u16(size.y)
		out.put_u8(0)
		out.put_data(encoded[i])
	out.put_u8(0x3B)
	return out.data_array


## The frames and delays of [param animation] in [param sheet] as [method encode] takes
## them: [code]{"frames": Array[Image], "delays": Array[float], "loop": bool}[/code].
## Without an animation, every frame is played at [param fps]. Frames are scaled up
## [param scale] times with sharp pixels, over [param background].
static func animation_frames(
	sheet: Spritesheet,
	animation: SheetAnimation,
	fps := 12.0,
	scale := 1,
	background := Color.TRANSPARENT
) -> Dictionary:
	var cells := sheet.get_sorted_coords()
	var durations: Array[float] = []
	var loop := true
	if animation:
		cells = animation.get_playback_cells(sheet)
		durations = animation.get_playback_durations(sheet)
		fps = animation.fps
		loop = animation.mode != SheetAnimation.Mode.ONCE
	var frames: Array[Image] = []
	var delays: Array[float] = []
	var size := sheet.sprite_size * maxi(scale, 1)
	for i in cells.size():
		var cell := sheet.get_cell_image(cells[i])
		var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(background if background.a > 0 else Color(0, 0, 0, 0))
		if scale > 1:
			cell = cell.duplicate()
			cell.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		img.blend_rect(cell, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
		frames.append(img)
		delays.append((durations[i] if i < durations.size() else 1.0) / maxf(fps, 0.1))
	return {"frames": frames, "delays": delays, "loop": loop}


## The colours of RGBA8 [param datas]: [code]{"table": PackedByteArray, "bits": int,
## "index_of": Dictionary, "reduced": bool}[/code]. index_of maps 0xRRGGBB to palette
## indices; when there are too many colours, it's empty and colours are reduced.
static func build_palette(datas: Array[PackedByteArray]) -> Dictionary:
	var index_of := {}
	var reduced := false
	for data in datas:
		for i in range(0, data.size(), 4):
			if data[i + 3] < ALPHA_CUTOFF:
				continue
			var key := (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if not index_of.has(key):
				if index_of.size() >= MAX_COLORS:
					reduced = true
					break
				index_of[key] = index_of.size() + 1
		if reduced:
			break
	var colors: Array[int] = [0]
	if reduced:
		index_of.clear()
		for r in REDUCED_LEVELS.x:
			for g in REDUCED_LEVELS.y:
				for b in REDUCED_LEVELS.z:
					colors.append(
						(
							(_level(r, REDUCED_LEVELS.x) << 16)
							| (_level(g, REDUCED_LEVELS.y) << 8)
							| _level(b, REDUCED_LEVELS.z)
						)
					)
	else:
		colors.append_array(index_of.keys())
	var bits := 1
	while (1 << bits) < colors.size():
		bits += 1
	var table := PackedByteArray()
	table.resize(3 << bits)
	for i in colors.size():
		table[i * 3] = (colors[i] >> 16) & 0xFF
		table[i * 3 + 1] = (colors[i] >> 8) & 0xFF
		table[i * 3 + 2] = colors[i] & 0xFF
	return {"table": table, "bits": bits, "index_of": index_of, "reduced": reduced}


## The palette index of every pixel of RGBA8 [param data]
static func _indices(data: PackedByteArray, palette: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data.size() / 4)
	var index_of: Dictionary = palette.index_of
	var reduced: bool = palette.reduced
	var levels := REDUCED_LEVELS
	for i in result.size():
		var at := i * 4
		if data[at + 3] < ALPHA_CUTOFF:
			result[i] = TRANSPARENT
		elif reduced:
			var r := roundi(data[at] * (levels.x - 1) / 255.0)
			var g := roundi(data[at + 1] * (levels.y - 1) / 255.0)
			var b := roundi(data[at + 2] * (levels.z - 1) / 255.0)
			result[i] = 1 + (r * levels.y + g) * levels.z + b
		else:
			result[i] = index_of[(data[at] << 16) | (data[at + 1] << 8) | data[at + 2]]
	return result


## GIF's LZW compression of palette [param indices], as the code size byte and data
## sub-blocks
static func _compress(indices: PackedByteArray) -> PackedByteArray:
	var clear_code := 1 << LZW_MIN_CODE_SIZE
	var end_code := clear_code + 1
	var next_code := end_code + 1
	var code_size := LZW_MIN_CODE_SIZE + 1
	var table := {}  # (prefix code << 8 | index) to code
	var stream := PackedByteArray()
	# Codes are packed least significant bit first
	var buffer := clear_code
	var bit_count := code_size
	var prefix := indices[0]
	for i in range(1, indices.size()):
		var index := indices[i]
		var key := (prefix << 8) | index
		var code: int = table.get(key, -1)
		if code >= 0:
			prefix = code
			continue
		buffer |= prefix << bit_count
		bit_count += code_size
		while bit_count >= 8:
			stream.append(buffer & 0xFF)
			buffer >>= 8
			bit_count -= 8
		if next_code == MAX_CODE:
			# The table is full: start a new one
			buffer |= clear_code << bit_count
			bit_count += code_size
			next_code = end_code + 1
			code_size = LZW_MIN_CODE_SIZE + 1
			table.clear()
		else:
			if next_code >= 1 << code_size:
				code_size += 1
			table[key] = next_code
			next_code += 1
		prefix = index
	for code: int in [prefix, end_code]:
		buffer |= code << bit_count
		bit_count += code_size
		while bit_count >= 8:
			stream.append(buffer & 0xFF)
			buffer >>= 8
			bit_count -= 8
	if bit_count > 0:
		stream.append(buffer & 0xFF)

	var result := PackedByteArray([LZW_MIN_CODE_SIZE])
	for start in range(0, stream.size(), 255):
		var block := stream.slice(start, start + 255)
		result.append(block.size())
		result.append_array(block)
	result.append(0)
	return result


static func _level(level: int, levels: int) -> int:
	return roundi(level * 255.0 / (levels - 1))
