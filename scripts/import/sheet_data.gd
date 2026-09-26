class_name SheetData
extends RefCounted
## Where the frames of a packed spritesheet are, read from the data file exported with it:
## TexturePacker JSON, as a hash or an array, and Aseprite JSON, which is the same format.
## Trimmed and rotated frames are restored to how they were drawn.

const EXTENSIONS: PackedStringArray = ["json"]


class Frame:
	var name := ""
	## Where the frame is in the image. For rotated frames, the size before rotating.
	var rect: Rect2i
	## Stored turned 90° clockwise in the image
	var rotated := false
	## Where the trimmed pixels were in the untrimmed frame
	var source_rect: Rect2i
	## Size of the untrimmed frame
	var source_size: Vector2i
	## How long the frame is shown in milliseconds, 0 when not given
	var duration := 0


## The image the data belongs to, relative to the data file. Empty when not given.
var image_file := ""
var frames: Array[Frame] = []
## Aseprite-style frame tags: [code]{"name": String, "from": int, "to": int,
## "direction": String, "repeat": int}[/code], with valid frame indices only
var tags: Array[Dictionary] = []
## Frames of each animation in playing order, by animation name, from the "animations"
## that spritesheetbelli writes: [code]{"walk": Array[int]}[/code] of frame indices
var animation_frames: Dictionary[String, Array] = {}
## Why the data couldn't be read, or empty
var error := ""


static func is_data_path(path: String) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS


## The data file next to [param image_path] with the same name, when there is one that
## describes that image. Returns an empty string otherwise.
static func find_for_image(image_path: String) -> String:
	var data_path := image_path.get_basename() + ".json"
	if not FileAccess.file_exists(data_path):
		return ""
	var data := load_file(data_path)
	if data.error or data.frames.is_empty():
		return ""
	if data.image_file and data.image_file.get_file() != image_path.get_file():
		return ""
	return data_path


static func load_file(path: String) -> SheetData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var data := SheetData.new()
		data.error = TranslationServer.translate("Could not open %s.") % path.get_file()
		return data
	return parse_json(text)


static func parse_json(text: String) -> SheetData:
	var data := SheetData.new()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		data.error = "This isn't a spritesheet data file."
		return data
	var meta: Dictionary = parsed.get("meta", {}) if parsed.get("meta") is Dictionary else {}
	var entries: Variant = parsed.get("frames")
	# Phaser multi-atlases keep frames per texture
	if entries == null and parsed.get("textures") is Array and not parsed.textures.is_empty():
		var texture: Variant = parsed.textures[0]
		if texture is Dictionary:
			entries = texture.get("frames")
			data.image_file = str(texture.get("image", ""))
	if entries is Dictionary:
		for key: String in entries:
			if entries[key] is Dictionary:
				data._add_frame(key, entries[key])
	elif entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				data._add_frame(str(entry.get("filename", entry.get("name", ""))), entry)
	if data.frames.is_empty():
		data.error = "There are no frames in this data file."
		return data
	if meta.get("image") is String:
		data.image_file = meta.image
	for tag: Variant in meta.get("frameTags", []):
		if tag is Dictionary:
			data._add_tag(tag)
	if meta.get("animations") is Dictionary:
		data._add_animation_frames(meta.animations)
	return data


## The image file next to the data file at [param data_path]
func get_image_path(data_path: String) -> String:
	if image_file.is_empty():
		return data_path.get_basename() + ".png"
	return data_path.get_base_dir().path_join(image_file)


## Every frame of [param img], untrimmed and unrotated, named after its entry
func cut(img: Image) -> Array[Image]:
	var images: Array[Image] = []
	for frame in frames:
		images.append(cut_frame(img, frame))
	return images


## The frame named [param frame_name] from [param img], or null when there's none
func cut_named(img: Image, frame_name: String) -> Image:
	for frame in frames:
		if frame.name == frame_name:
			return cut_frame(img, frame)
	return null


## [param frame] from [param img], untrimmed and unrotated, named after its entry
static func cut_frame(img: Image, frame: Frame) -> Image:
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var stored := frame.rect
	if frame.rotated:
		stored.size = Vector2i(stored.size.y, stored.size.x)
	var pixels := img.get_region(stored.intersection(bounds))
	if frame.rotated:
		pixels.rotate_90(COUNTERCLOCKWISE)
	if pixels.get_format() != Image.FORMAT_RGBA8:
		pixels.convert(Image.FORMAT_RGBA8)
	var full := pixels
	if frame.source_size != pixels.get_size() or frame.source_rect.position != Vector2i.ZERO:
		var size := frame.source_size.max(frame.source_rect.position + pixels.get_size())
		full = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		var source := Rect2i(Vector2i.ZERO, pixels.get_size())
		full.blit_rect(pixels, source, frame.source_rect.position)
	full.resource_name = frame.name
	return full


## A spritesheet of the frames. Tags that don't overlap become named rows, with the
## frames between them in rows of their own; otherwise the frames fill a square grid.
## Every tag becomes an animation. With the paths of the image and of this data file,
## the frames are linked to them, see [FrameSource].
func to_spritesheet(img: Image, image_path := "", data_path := "") -> Spritesheet:
	var images := cut(img)
	var cells: Array[Vector2i] = []
	var row_names: Dictionary[int, String] = {}
	var tag_rows := _rows_by_tag()
	if tag_rows.is_empty():
		var columns := ceili(sqrt(images.size()))
		for i in images.size():
			cells.append(Vector2i(i % columns, i / columns))
	else:
		for row in tag_rows.size():
			var group: Dictionary = tag_rows[row]
			if group.name:
				row_names[row] = group.name
			for column: int in group.count:
				cells.append(Vector2i(column, row))

	var sheet := Spritesheet.new()
	sheet.begin_batch()
	for i in images.size():
		var source := {}
		if image_path and data_path:
			source = FrameSource.for_data(image_path, data_path, frames[i].name)
		sheet.set_frame(cells[i], images[i], source)
	for row in row_names:
		sheet.set_row_name(row, row_names[row])
	for tag in tags:
		var tag_cells: Array[Vector2i] = []
		var indices: Array = range(tag.from, tag.to + 1)
		if tag.direction in ["reverse", "pingpong_reverse"]:
			indices.reverse()
		# The exact frames when they're listed, which tags can't always describe
		if animation_frames.has(tag.name):
			indices = animation_frames[tag.name]
		var seconds: Array[float] = []
		for i: int in indices:
			tag_cells.append(cells[i])
			seconds.append(frames[i].duration / 1000.0)
		var animation := SheetAnimation.create_timed(tag.name, tag_cells, seconds)
		if tag.direction.begins_with("pingpong"):
			animation.mode = SheetAnimation.Mode.PING_PONG
		elif tag.repeat == 1:
			animation.mode = SheetAnimation.Mode.ONCE
		sheet.add_animation(animation)
	sheet.end_batch()
	return sheet


## Rows of frames when tags don't overlap: [code]{"name": String, "count": int}[/code]
## in frame order, or empty
func _rows_by_tag() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if tags.is_empty():
		return rows
	var starts := {}
	for tag in tags:
		starts[tag.from] = tag
	var i := 0
	while i < frames.size():
		if starts.has(i):
			var tag: Dictionary = starts[i]
			rows.append({"name": tag.name, "count": tag.to - tag.from + 1})
			i = tag.to + 1
			continue
		# Frames that aren't in a tag, up to the next one
		var end := i
		while end < frames.size() and not starts.has(end):
			end += 1
		rows.append({"name": "", "count": end - i})
		i = end
	# Overlapping tags leave some tag unused
	var used := rows.filter(func(row: Dictionary) -> bool: return row.name != "").size()
	if used != tags.size():
		rows.clear()
	return rows


func _add_frame(frame_name: String, entry: Dictionary) -> void:
	var rect := _read_rect(entry.get("frame"))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var frame := Frame.new()
	frame.name = frame_name
	frame.rect = rect
	frame.rotated = entry.get("rotated") == true
	frame.source_size = rect.size
	var source_size: Variant = entry.get("sourceSize")
	if source_size is Dictionary:
		frame.source_size = Vector2i(int(source_size.get("w", 0)), int(source_size.get("h", 0)))
	frame.source_rect = Rect2i(Vector2i.ZERO, rect.size)
	if entry.get("spriteSourceSize") is Dictionary:
		frame.source_rect = _read_rect(entry.spriteSourceSize)
	frame.source_size = frame.source_size.max(Vector2i.ONE)
	frame.duration = maxi(0, int(entry.get("duration", 0)))
	frames.append(frame)


func _add_animation_frames(lists: Dictionary) -> void:
	var index_of := {}
	for i in frames.size():
		index_of[frames[i].name] = i
	for animation_name: Variant in lists:
		if not lists[animation_name] is Array:
			continue
		var indices := []
		for frame_name: Variant in lists[animation_name]:
			if index_of.has(frame_name):
				indices.append(index_of[frame_name])
		if not indices.is_empty():
			animation_frames[str(animation_name)] = indices


func _add_tag(tag: Dictionary) -> void:
	var from := int(tag.get("from", -1))
	var to := int(tag.get("to", -1))
	if from < 0 or to < from or to >= frames.size():
		return
	(
		tags
		. append(
			{
				"name": str(tag.get("name", "animation")),
				"from": from,
				"to": to,
				"direction": str(tag.get("direction", "forward")),
				"repeat": int(tag.get("repeat", 0)),
			}
		)
	)


static func _read_rect(value: Variant) -> Rect2i:
	if not value is Dictionary:
		return Rect2i()
	return Rect2i(
		int(value.get("x", 0)),
		int(value.get("y", 0)),
		int(value.get("w", 0)),
		int(value.get("h", 0))
	)
