class_name AtlasFormats
## The data files written next to the pages of a packed atlas, telling game engines where
## each frame is. Frames are described by [method get_frames]; pages are
## [code]{"file": String, "size": Vector2i}[/code].

## Every format by id: its name, the extension of its file, whether it has a file per page,
## whether it can describe frames stored turned, and which way engines expect them turned
const FORMATS := {
	"json": {"name": "TexturePacker JSON (hash)", "extension": "json", "per_page": true},
	"json-array": {"name": "TexturePacker JSON (array)", "extension": "json", "per_page": true},
	"phaser": {"name": "Phaser 3 multi-atlas JSON", "extension": "json"},
	"atlas": {"name": "libGDX / Spine .atlas", "extension": "atlas", "counter_clockwise": true},
	"sparrow": {"name": "Sparrow / Starling XML", "extension": "xml", "per_page": true},
	"godot": {"name": "Godot SpriteFrames", "extension": "tres", "no_rotation": true},
}


static func get_extension(format: String) -> String:
	return FORMATS.get(format, FORMATS.json).extension


static func has_file_per_page(format: String) -> bool:
	return FORMATS.get(format, {}).get("per_page", false)


static func can_rotate(format: String) -> bool:
	return not FORMATS.get(format, {}).get("no_rotation", false)


## Whether engines reading [param format] expect turned frames turned counter-clockwise
static func is_counter_clockwise(format: String) -> bool:
	return FORMATS.get(format, {}).get("counter_clockwise", false)


## The frames of a packed atlas in reading order, from its regions (see
## [method AtlasPacker.get_regions]), with unique names from the sprite name pattern and
## how long each is shown with [param fps]
static func get_frames(
	sheet: Spritesheet, regions: Array, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var used := {}
	var durations := Metadata.frame_durations(sheet, options.animation_fps)
	for region: AtlasPacker.Region in regions:
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, region.coord, index_start
		)
		var unique := name
		var number := 2
		while used.has(unique):
			unique = "%s_%d" % [name, number]
			number += 1
		used[unique] = true
		var frame := {
			"name": unique + ".png",
			"coord": region.coord,
			"page": region.page,
			"rect": region.rect,
			"rotated": region.rotated,
			"source_rect": region.source_rect,
			"source_size": region.source_size,
			"pivot": region.pivot,
		}
		if durations.has(frames.size()):
			frame.duration = durations[frames.size()]
		elif options.animation_fps > 0:
			frame.duration = roundi(1000.0 / options.animation_fps)
		frames.append(frame)
	return frames


## Writes the data file (or one per page) for [param frames] on [param pages], named after
## [param base_path] without an extension. Returns [code]{"error": Error, "paths":
## PackedStringArray}[/code].
static func write(
	sheet: Spritesheet,
	format: String,
	frames: Array[Dictionary],
	pages: Array[Dictionary],
	base_path: String,
	fps: float
) -> Dictionary:
	var extension := get_extension(format)
	var names := Metadata.animation_frame_names(sheet, frames)
	var texts := {}  # Text by path
	if has_file_per_page(format) and pages.size() > 1:
		for page in pages.size():
			var path := "%s_%d.%s" % [base_path, page, extension]
			texts[path] = _page_text(sheet, format, _on_page(frames, page), pages[page], names)
	elif has_file_per_page(format):
		texts[base_path + "." + extension] = _page_text(sheet, format, frames, pages[0], names)
	else:
		var text: String
		match format:
			"phaser":
				text = phaser_json(frames, pages, names)
			"atlas":
				text = libgdx_atlas(frames, pages)
			"godot":
				var files := PackedStringArray()
				for page in pages:
					files.append(page.file)
				text = Metadata.sprite_frames_tres(
					_with_margins(frames), Metadata.animations(sheet), "", fps, files
				)
		texts[base_path + "." + extension] = text
	var result := {"error": OK, "paths": PackedStringArray()}
	for path: String in texts:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			result.error = FileAccess.get_open_error()
			return result
		file.store_string(texts[path])
		file.close()
		result.paths.append(path)
	return result


## A libGDX texture atlas, also read by Spine runtimes. Trimmed frames keep their original
## size and offset, which libGDX measures from the bottom. Turned frames are stored turned
## counter-clockwise, with their size before turning.
static func libgdx_atlas(frames: Array[Dictionary], pages: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for page in pages.size():
		var size: Vector2i = pages[page].size
		lines.append("")
		lines.append(pages[page].file)
		lines.append("size: %d, %d" % [size.x, size.y])
		lines.append("format: RGBA8888")
		lines.append("filter: Nearest, Nearest")
		lines.append("repeat: none")
		for frame in _on_page(frames, page):
			var rect: Rect2i = frame.rect
			var source: Rect2i = frame.source_rect
			var source_size: Vector2i = frame.source_size
			lines.append(str(frame.name).get_basename())
			lines.append("  rotate: %s" % str(frame.rotated).to_lower())
			lines.append("  xy: %d, %d" % [rect.position.x, rect.position.y])
			lines.append("  size: %d, %d" % [source.size.x, source.size.y])
			lines.append("  orig: %d, %d" % [source_size.x, source_size.y])
			lines.append("  offset: %d, %d" % [source.position.x, source_size.y - source.end.y])
			lines.append("  index: -1")
	return "\n".join(lines) + "\n"


## A Sparrow / Starling texture atlas. Turned frames are stored turned clockwise, and
## their size is as they are on the page.
static func sparrow_xml(frames: Array[Dictionary], image_file: String, size: Vector2i) -> String:
	var lines: PackedStringArray = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		(
			'<TextureAtlas imagePath="%s" width="%d" height="%d">'
			% [image_file.xml_escape(true), size.x, size.y]
		),
	]
	for frame in frames:
		var rect: Rect2i = frame.rect
		var source: Rect2i = frame.source_rect
		var source_size: Vector2i = frame.source_size
		var attributes := (
			'name="%s" x="%d" y="%d" width="%d" height="%d"'
			% [
				str(frame.name).get_basename().xml_escape(true),
				rect.position.x,
				rect.position.y,
				rect.size.x,
				rect.size.y
			]
		)
		if source.size != source_size:
			attributes += (
				' frameX="%d" frameY="%d" frameWidth="%d" frameHeight="%d"'
				% [-source.position.x, -source.position.y, source_size.x, source_size.y]
			)
		if frame.rotated:
			attributes += ' rotated="true"'
		var pivot: Vector2 = frame.pivot * Vector2(source_size)
		attributes += ' pivotX="%s" pivotY="%s"' % [_number(pivot.x), _number(pivot.y)]
		lines.append("\t<SubTexture %s/>" % attributes)
	lines.append("</TextureAtlas>")
	return "\n".join(lines) + "\n"


## A Phaser 3 multi-atlas: one JSON file with the frames of every page
static func phaser_json(
	frames: Array[Dictionary], pages: Array[Dictionary], animation_names := {}
) -> String:
	var textures := []
	for page in pages.size():
		var entries := []
		for frame in _on_page(frames, page):
			var entry := Metadata.texture_packer_entry(frame)
			entry.filename = str(frame.name).get_basename()
			entries.append(entry)
		var size: Vector2i = pages[page].size
		(
			textures
			. append(
				{
					"image": pages[page].file,
					"format": "RGBA8888",
					"size": {"w": size.x, "h": size.y},
					"scale": 1,
					"frames": entries,
				}
			)
		)
	var data := {
		"textures": textures,
		"meta":
		{
			"app": "spritesheetbelli",
			"version": ProjectSettings.get_setting("application/config/version", ""),
		},
	}
	if not animation_names.is_empty():
		data.meta.animations = animation_names
	return JSON.stringify(data, "\t", false)


## The data file of one page. [param animation_names] lists the frames of every
## animation by name, see [method Metadata.animation_frame_names].
static func _page_text(
	sheet: Spritesheet,
	format: String,
	frames: Array[Dictionary],
	page: Dictionary,
	animation_names: Dictionary
) -> String:
	if format == "sparrow":
		return sparrow_xml(frames, page.file, page.size)
	# Frame tags count frames, which only works when every frame is in the file
	var tags: Array[Dictionary] = []
	if frames.size() == sheet.frames.size():
		tags = Metadata.frame_tags(sheet)
	return Metadata.texture_packer_json(
		frames, page.file, page.size, tags, 0.0, {}, animation_names, format == "json-array"
	)


static func _on_page(frames: Array[Dictionary], page: int) -> Array[Dictionary]:
	return frames.filter(func(frame: Dictionary) -> bool: return frame.page == page)


## Frames with the margin that gives Godot's AtlasTexture their size before trimming
static func _with_margins(frames: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for frame in frames:
		var with_margin := frame.duplicate()
		var source: Rect2i = frame.source_rect
		var source_size: Vector2i = frame.source_size
		if source.size != source_size:
			with_margin.margin = Rect2i(source.position, source_size - source.size)
		result.append(with_margin)
	return result


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return String.num(value, 3)
