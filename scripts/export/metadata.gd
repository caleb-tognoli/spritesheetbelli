class_name Metadata
## Describes where frames are in an exported image, for game engines.

const EXTENSIONS := {
	ExportOptions.MetadataFormat.JSON: "json",
	ExportOptions.MetadataFormat.GODOT: "tres",
}


## Writes the metadata chosen in [param options] next to an exported image
static func write_for_image(
	sheet: Spritesheet, options: ExportOptions, image_path: String, index_start := 0
) -> Error:
	if options.metadata == ExportOptions.MetadataFormat.NONE:
		return OK
	var frames := grid_frames(sheet, options, index_start)
	var size := SpritesheetExporter.get_image_size(sheet, options)
	var text: String
	if options.metadata == ExportOptions.MetadataFormat.GODOT:
		text = sprite_frames_tres(
			frames, animations(sheet), image_path.get_file(), options.animation_fps
		)
	else:
		text = texture_packer_json(
			frames, image_path.get_file(), size, frame_tags(sheet), options.animation_fps
		)
	var file := FileAccess.open(get_path_for_image(image_path, options), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


static func get_path_for_image(image_path: String, options: ExportOptions) -> String:
	return image_path.get_basename() + "." + EXTENSIONS.get(options.metadata, "json")


## Every frame of a grid export in reading order, with its cell in the image
static func grid_frames(
	sheet: Spritesheet, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for coord in sheet.get_sorted_coords():
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, coord, index_start
		)
		(
			frames
			. append(
				{
					"name": name + ".png",
					"coord": coord,
					"rect": SpritesheetExporter.get_cell_rect(sheet, coord, options),
				}
			)
		)
	return frames


## Animations from rows: each row with frames becomes one, named after the row.
## Returns [code]{"name": String, "indices": Array}[/code] with indices into
## [method grid_frames]. Without any row names, all frames form one "default" animation.
static func animations(sheet: Spritesheet) -> Array[Dictionary]:
	var coords := sheet.get_sorted_coords()
	var result: Array[Dictionary] = []
	if sheet.row_names.is_empty():
		result.append({"name": "default", "indices": range(coords.size())})
		return result
	var by_row := {}
	for i in coords.size():
		var row := coords[i].y
		if not by_row.has(row):
			by_row[row] = {"name": sheet.row_names.get(row, "row%d" % row), "indices": []}
		by_row[row].indices.append(i)
	for row: int in by_row:
		result.append(by_row[row])
	return result


## Aseprite-style frame tags, one per named animation
static func frame_tags(sheet: Spritesheet) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	if sheet.row_names.is_empty():
		return tags
	for animation in animations(sheet):
		var indices: Array = animation.indices
		tags.append(
			{"name": animation.name, "from": indices[0], "to": indices[-1], "direction": "forward"}
		)
	return tags


## A Godot SpriteFrames resource using the image next to it, one animation per row
static func sprite_frames_tres(
	frames: Array[Dictionary], animation_list: Array[Dictionary], image_file: String, fps: float
) -> String:
	var lines: PackedStringArray = [
		'[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (frames.size() + 2),
		"",
		'[ext_resource type="Texture2D" path="%s" id="1_sheet"]' % image_file,
		"",
	]
	for i in frames.size():
		var rect: Rect2i = frames[i].rect
		lines.append('[sub_resource type="AtlasTexture" id="AtlasTexture_%d"]' % i)
		lines.append('atlas = ExtResource("1_sheet")')
		lines.append(
			(
				"region = Rect2(%d, %d, %d, %d)"
				% [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			)
		)
		lines.append("")
	var animation_texts: PackedStringArray = []
	for animation in animation_list:
		var frame_texts: PackedStringArray = []
		for index: int in animation.indices:
			frame_texts.append(
				'{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_%d")\n}' % index
			)
		animation_texts.append(
			(
				'{\n"frames": [%s],\n"loop": true,\n"name": &%s,\n"speed": %s\n}'
				% [", ".join(frame_texts), JSON.stringify(animation.name), str(float(fps))]
			)
		)
	lines.append("[resource]")
	lines.append("animations = [%s]" % ", ".join(animation_texts))
	return "\n".join(lines) + "\n"


## JSON in the TexturePacker "hash" format, readable by most engines and tools.
## [param tags] are added as Aseprite-style "frameTags", and with [param fps] each frame
## gets an Aseprite-style duration in milliseconds.
static func texture_packer_json(
	frames: Array[Dictionary],
	image_file: String,
	image_size: Vector2i,
	tags: Array[Dictionary] = [],
	fps := 0.0,
) -> String:
	var entries := {}
	for frame in frames:
		var rect: Rect2i = frame.rect
		var source: Rect2i = frame.get("source_rect", Rect2i(Vector2i.ZERO, rect.size))
		var source_size: Vector2i = frame.get("source_size", rect.size)
		entries[frame.name] = {
			"frame": _rect(rect),
			"rotated": false,
			"trimmed": source.size != source_size,
			"spriteSourceSize": _rect(source),
			"sourceSize": {"w": source_size.x, "h": source_size.y},
		}
		if fps > 0:
			entries[frame.name]["duration"] = roundi(1000.0 / fps)
	var data := {
		"frames": entries,
		"meta":
		{
			"app": "spritesheetbelli",
			"version": ProjectSettings.get_setting("application/config/version", ""),
			"image": image_file,
			"format": "RGBA8888",
			"size": {"w": image_size.x, "h": image_size.y},
			"scale": "1",
			"frameTags": tags,
		},
	}
	return JSON.stringify(data, "\t", false)


## Frames of a packed atlas, named with the sheet's sprite name pattern
static func atlas_frames(
	sheet: Spritesheet, regions: Array, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for region: AtlasPacker.Region in regions:
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, region.coord, index_start
		)
		(
			frames
			. append(
				{
					"name": name + ".png",
					"rect": region.rect,
					"source_rect": region.source_rect,
					"source_size": region.source_size,
				}
			)
		)
	return frames


static func _rect(rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
