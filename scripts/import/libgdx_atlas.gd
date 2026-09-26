class_name LibgdxAtlas
## Reads libGDX texture atlases, also written by Spine and TexturePacker, into a
## [SheetData]. Both the old format (xy, size, orig, offset) and the new one (bounds,
## offsets, degrees) are read. Pages are separated by blank lines; a page starts with the
## name of its image, followed by its settings and then its regions.


static func parse(text: String) -> SheetData:
	var data := SheetData.new()
	data.format = "atlas"
	var frame: SheetData.Frame = null
	var index := -1
	var expecting_page := true
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			_finish(data, frame, index)
			frame = null
			expecting_page = true
			continue
		var colon := line.find(":")
		if colon < 0:
			_finish(data, frame, index)
			frame = null
			if expecting_page:
				data.pages.append(line)
				data.page_sizes.append(Vector2i.ZERO)
				expecting_page = false
			else:
				frame = SheetData.Frame.new()
				frame.name = line
				frame.page = data.pages.size() - 1
				frame.counter_clockwise = true
				index = -1
			continue
		expecting_page = false
		var key := line.substr(0, colon).strip_edges()
		var values := _numbers(line.substr(colon + 1))
		var value := line.substr(colon + 1).strip_edges()
		if frame == null:
			if key == "size" and values.size() >= 2 and not data.page_sizes.is_empty():
				data.page_sizes[-1] = Vector2i(values[0], values[1])
			continue
		match key:
			"xy" when values.size() >= 2:
				frame.rect.position = Vector2i(values[0], values[1])
			"size" when values.size() >= 2:
				frame.rect.size = Vector2i(values[0], values[1])
			"bounds" when values.size() >= 4:
				frame.rect = Rect2i(values[0], values[1], values[2], values[3])
			"orig" when values.size() >= 2:
				frame.source_size = Vector2i(values[0], values[1])
			"offset" when values.size() >= 2:
				frame.source_rect.position = Vector2i(values[0], values[1])
			"offsets" when values.size() >= 4:
				frame.source_rect.position = Vector2i(values[0], values[1])
				frame.source_size = Vector2i(values[2], values[3])
			"rotate":
				frame.rotated = value == "true" or value == "90"
			"index" when values.size() >= 1:
				index = values[0]
	_finish(data, frame, index)
	if data.frames.is_empty():
		data.error = "There are no frames in this data file."
		return data
	data.image_file = data.pages[0]
	return data


## Adds [param frame] to [param data] now that everything about it is read
static func _finish(data: SheetData, frame: SheetData.Frame, index: int) -> void:
	if frame == null or frame.rect.size.x <= 0 or frame.rect.size.y <= 0:
		return
	var size := frame.rect.size
	if frame.source_size == Vector2i.ZERO:
		frame.source_size = size
	# libGDX measures the offset from the bottom
	var from_bottom := frame.source_rect.position.y
	frame.source_rect = Rect2i(
		Vector2i(frame.source_rect.position.x, frame.source_size.y - from_bottom - size.y), size
	)
	if index >= 0:
		frame.name = "%s_%d" % [frame.name, index]
	data.frames.append(frame)


static func _numbers(text: String) -> Array[int]:
	var numbers: Array[int] = []
	for part in text.split(","):
		var trimmed := part.strip_edges()
		if trimmed.is_valid_int():
			numbers.append(int(trimmed))
	return numbers
