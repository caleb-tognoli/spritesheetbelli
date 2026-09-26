class_name SheetData
extends RefCounted
## Where the frames of a packed spritesheet are, read from the data file exported with it:
## TexturePacker JSON, as a hash or an array, Aseprite JSON, which is the same format,
## Phaser multi-atlases and libGDX / Spine .atlas files (see [LibgdxAtlas]). Trimmed and
## rotated frames are restored to how they were drawn.

const EXTENSIONS: PackedStringArray = ["json", "atlas"]


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
	## The page (image) the frame is on
	var page := 0
	## Stored turned counter-clockwise instead, like libGDX does
	var counter_clockwise := false
	## From 0 to 1 across the untrimmed frame, or (-1, -1) when not given
	var pivot := Vector2(-1, -1)


## The image the data belongs to, relative to the data file. Empty when not given.
var image_file := ""
## Every page's image, relative to the data file, when there's more than one
var pages: PackedStringArray = []
## Size of each page, when the data file gives it
var page_sizes: Array[Vector2i] = []
## Which [constant AtlasFormats.FORMATS] the data file is in
var format := "json"
## Data files of the other pages of a TexturePacker multipack, relative to this one
var related_files: PackedStringArray = []
## The frame names of each animation, as the data file lists them
var _animation_names := {}
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
	for extension in EXTENSIONS:
		var data_path := image_path.get_basename() + "." + extension
		if not FileAccess.file_exists(data_path):
			continue
		var data := load_file(data_path)
		if data.error or data.frames.is_empty():
			continue
		if data.image_file and data.image_file.get_file() != image_path.get_file():
			continue
		return data_path
	return ""


static func load_file(path: String) -> SheetData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var unreadable := SheetData.new()
		unreadable.error = TranslationServer.translate("Could not open %s.") % path.get_file()
		return unreadable
	if path.get_extension().to_lower() == "atlas":
		return LibgdxAtlas.parse(text)
	var data := parse_json(text)
	# TexturePacker multipacks: every page has a file, naming the others
	for related in data.related_files:
		var other := parse_json(
			FileAccess.get_file_as_string(path.get_base_dir().path_join(related))
		)
		if other.error:
			continue
		if data.pages.is_empty():
			data.pages.append(data.image_file)
		for frame in other.frames:
			frame.page = data.pages.size()
			data.frames.append(frame)
		data.pages.append(other.image_file)
		data.page_sizes.append(other.page_sizes[0] if other.page_sizes else Vector2i.ZERO)
	if data.related_files:
		# Animations can list frames on any page
		data.animation_frames.clear()
		data._add_animation_frames(data._animation_names)
	return data


static func parse_json(text: String) -> SheetData:
	var data := SheetData.new()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		data.error = "This isn't a spritesheet data file."
		return data
	var meta: Dictionary = parsed.get("meta", {}) if parsed.get("meta") is Dictionary else {}
	var entries: Variant = parsed.get("frames")
	if entries is Array:
		data.format = "json-array"
	data._add_frames(entries, 0)
	# Phaser multi-atlases keep frames per texture, each its own page
	if entries == null and parsed.get("textures") is Array:
		data.format = "phaser"
		for texture: Variant in parsed.textures:
			if texture is Dictionary:
				data._add_frames(texture.get("frames"), data.pages.size())
				data.pages.append(str(texture.get("image", "")))
				data.page_sizes.append(_read_size(texture.get("size")))
		if not data.pages.is_empty():
			data.image_file = data.pages[0]
	if data.frames.is_empty():
		data.error = "There are no frames in this data file."
		return data
	if meta.get("image") is String:
		data.image_file = meta.image
	if meta.get("size") is Dictionary and data.page_sizes.is_empty():
		data.page_sizes.append(_read_size(meta.size))
	if meta.get("related_multi_packs") is Array:
		for related: Variant in meta.related_multi_packs:
			data.related_files.append(str(related))
	for tag: Variant in meta.get("frameTags", []):
		if tag is Dictionary:
			data._add_tag(tag)
	if meta.get("animations") is Dictionary:
		data._animation_names = meta.animations
		data._add_animation_frames(meta.animations)
	return data


## The image file next to the data file at [param data_path]
func get_image_path(data_path: String) -> String:
	if image_file.is_empty():
		return data_path.get_basename() + ".png"
	return data_path.get_base_dir().path_join(image_file)


## The image of every page, next to the data file at [param data_path]
func get_page_paths(data_path: String) -> PackedStringArray:
	var paths: PackedStringArray = [get_image_path(data_path)]
	for page in range(1, pages.size()):
		paths.append(data_path.get_base_dir().path_join(pages[page]))
	return paths


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
		pixels.rotate_90(CLOCKWISE if frame.counter_clockwise else COUNTERCLOCKWISE)
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
## the frames are linked to them, see [FrameSource]. Frames on other pages are cut from
## [param other_pages], in order, and left out when their page is missing.
## With [param keep_layout], the sheet is packed with every frame where it is in the
## image, so exporting it again keeps the places engines know.
func to_spritesheet(
	img: Image,
	image_path := "",
	data_path := "",
	keep_layout := false,
	other_pages: Array[Image] = []
) -> Spritesheet:
	var page_images: Array[Image] = [img]
	page_images.append_array(other_pages)
	var page_paths: PackedStringArray = [image_path]
	if data_path:
		page_paths = get_page_paths(data_path)
		page_paths[0] = image_path
	var images: Array[Image] = []
	for frame in frames:
		var page_image: Image = page_images[frame.page] if frame.page < page_images.size() else null
		images.append(cut_frame(page_image, frame) if page_image else null)
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
	var places := {}
	var page_size := Vector2i.ONE
	for i in images.size():
		if images[i] == null:
			continue
		var frame := frames[i]
		var source := {}
		if image_path and data_path and frame.page < page_paths.size():
			source = FrameSource.for_data(page_paths[frame.page], data_path, frame.name)
		sheet.set_frame(cells[i], images[i], source)
		if frame.pivot.x >= 0:
			var pivot := frame.pivot * Vector2(images[i].get_size())
			sheet.set_pivots([cells[i]] as Array[Vector2i], pivot)
		var src := Rect2i(frame.source_rect.position, frame.rect.size)
		places[cells[i]] = PackedLayout.new_place(
			frame.page, frame.rect.position, src, frame.rotated
		)
		var stored := PackedLayout.get_rect_of(places[cells[i]])
		page_size = page_size.max(stored.end)
	for size in page_sizes:
		page_size = page_size.max(size)
	if keep_layout:
		PackedLayout.adopt(sheet, places, page_size)
		var export := ExportOptions.new()
		export.apply(sheet.export_settings)
		export.target = ExportOptions.Target.ATLAS
		export.atlas_data = format
		export.sprite_name_pattern = "{name}"
		sheet.set_export_settings(export.to_dictionary())
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
	# Animations listed by frame name without a tag, as multipacks have them
	for animation_name: String in animation_frames:
		if tags.any(func(tag: Dictionary) -> bool: return tag.name == animation_name):
			continue
		var listed_cells: Array[Vector2i] = []
		var listed_seconds: Array[float] = []
		for i: int in animation_frames[animation_name]:
			if images[i]:
				listed_cells.append(cells[i])
				listed_seconds.append(frames[i].duration / 1000.0)
		if listed_cells:
			sheet.add_animation(
				SheetAnimation.create_timed(animation_name, listed_cells, listed_seconds)
			)
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


## Adds the frames of a "frames" hash or array on [param page]
func _add_frames(entries: Variant, page: int) -> void:
	if entries is Dictionary:
		for key: String in entries:
			if entries[key] is Dictionary:
				_add_frame(key, entries[key], page)
	elif entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				_add_frame(str(entry.get("filename", entry.get("name", ""))), entry, page)


func _add_frame(frame_name: String, entry: Dictionary, page := 0) -> void:
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
	frame.page = page
	var pivot: Variant = entry.get("pivot")
	if pivot is Dictionary and pivot.has("x") and pivot.has("y"):
		frame.pivot = Vector2(float(pivot.x), float(pivot.y))
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


static func _read_size(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i.ZERO
	return Vector2i(int(value.get("w", 0)), int(value.get("h", 0)))


static func _read_rect(value: Variant) -> Rect2i:
	if not value is Dictionary:
		return Rect2i()
	return Rect2i(
		int(value.get("x", 0)),
		int(value.get("y", 0)),
		int(value.get("w", 0)),
		int(value.get("h", 0))
	)
