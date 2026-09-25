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
		text = sheet_json(sheet, frames, image_path.get_file(), size, options.animation_fps)
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


## The sheet's animations, or else one per row: each row with frames becomes one, named
## after the row. Without animations or row names, all frames form one "default" animation.
## Returns [code]{"name": String, "indices": Array, "durations": Array, "mode":
## SheetAnimation.Mode, "fps": float}[/code] with indices into [method grid_frames] and
## how many frames each is shown for; fps is 0 when not set.
static func animations(sheet: Spritesheet) -> Array[Dictionary]:
	var coords := sheet.get_sorted_coords()
	var result: Array[Dictionary] = []
	if not sheet.animations.is_empty():
		var index_of := {}
		for i in coords.size():
			index_of[coords[i]] = i
		for animation in sheet.animations:
			var indices := animation.get_frame_cells(sheet).map(
				func(cell: Vector2i) -> int: return index_of[cell]
			)
			if not indices.is_empty():
				result.append(
					{
						"name": animation.name,
						"indices": indices,
						"durations": Array(animation.get_frame_durations(sheet)),
						"mode": animation.mode,
						"fps": animation.fps
					}
				)
		return result
	if sheet.row_names.is_empty():
		result.append(
			{
				"name": "default",
				"indices": range(coords.size()),
				"durations": [],
				"mode": SheetAnimation.Mode.LOOP,
				"fps": 0.0
			}
		)
		return result
	var by_row := {}
	for i in coords.size():
		var row := coords[i].y
		if not by_row.has(row):
			by_row[row] = {
				"name": sheet.row_names.get(row, "row%d" % row),
				"indices": [],
				"durations": [],
				"mode": SheetAnimation.Mode.LOOP,
				"fps": 0.0,
			}
		by_row[row].indices.append(i)
	for row: int in by_row:
		result.append(by_row[row])
	return result


## TexturePacker-style JSON for [param frames] of [param sheet] (from [method grid_frames]
## or [method atlas_frames]), with its animations as frame tags and frame lists, and how
## long each frame is shown
static func sheet_json(
	sheet: Spritesheet, frames: Array[Dictionary], image_file: String, size: Vector2i, fps: float
) -> String:
	return texture_packer_json(
		frames,
		image_file,
		size,
		frame_tags(sheet),
		fps,
		frame_durations(sheet, fps),
		animation_frame_names(sheet, frames)
	)


## The frame names of every animation in playing order, by animation name, for animations
## that frame tags can't describe exactly. Empty when the sheet has no animations or rows.
static func animation_frame_names(sheet: Spritesheet, frames: Array[Dictionary]) -> Dictionary:
	var result := {}
	if sheet.row_names.is_empty() and sheet.animations.is_empty():
		return result
	for animation in animations(sheet):
		var names := []
		for index: int in animation.indices:
			names.append(frames[index].name)
		result[animation.name] = names
	return result


## How long each frame of [method grid_frames] is shown in milliseconds, by index: from
## the first animation it's in, at that animation's speed or else [param fps]. Frames in
## no animation are left out.
static func frame_durations(sheet: Spritesheet, fps: float) -> Dictionary:
	var result := {}
	for animation in animations(sheet):
		var animation_fps: float = animation.fps if animation.fps > 0 else fps
		if animation_fps <= 0:
			continue
		var indices: Array = animation.indices
		var durations: Array = animation.get("durations", [])
		for i in indices.size():
			if not result.has(indices[i]):
				var duration: float = durations[i] if i < durations.size() else 1.0
				result[indices[i]] = roundi(1000.0 * duration / animation_fps)
	return result


## Aseprite-style frame tags, one per named animation. Tags cover a range of frames, so an
## animation of scattered frames spans from its first to its last one.
static func frame_tags(sheet: Spritesheet) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	if sheet.row_names.is_empty() and sheet.animations.is_empty():
		return tags
	for animation in animations(sheet):
		var indices: Array = animation.indices
		var tag := {
			"name": animation.name,
			"from": indices[0],
			"to": indices[-1],
			"direction": "forward",
		}
		if indices[-1] < indices[0]:
			tag.direction = "reverse"
			tag.from = indices[-1]
			tag.to = indices[0]
		if animation.mode == SheetAnimation.Mode.PING_PONG:
			tag.direction = "pingpong"
		elif animation.mode == SheetAnimation.Mode.ONCE:
			tag.repeat = "1"
		tags.append(tag)
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
		var indices: Array = animation.indices.duplicate()
		var durations: Array = animation.get("durations", []).duplicate()
		durations.resize(indices.size())
		durations = durations.map(
			func(value: Variant) -> float: return 1.0 if value == null else float(value)
		)
		# SpriteFrames can't ping-pong, so the way back is written out
		if animation.get("mode") == SheetAnimation.Mode.PING_PONG:
			indices = SheetAnimation.ping_pong(indices)
			durations = SheetAnimation.ping_pong(durations)
		for i in indices.size():
			frame_texts.append(
				(
					'{\n"duration": %s,\n"texture": SubResource("AtlasTexture_%d")\n}'
					% [str(float(durations[i])), indices[i]]
				)
			)
		animation_texts.append(
			(
				'{\n"frames": [%s],\n"loop": %s,\n"name": &%s,\n"speed": %s\n}'
				% [
					", ".join(frame_texts),
					str(animation.get("mode") != SheetAnimation.Mode.ONCE),
					JSON.stringify(animation.name),
					str(float(animation.fps if animation.get("fps", 0.0) > 0 else fps))
				]
			)
		)
	lines.append("[resource]")
	lines.append("animations = [%s]" % ", ".join(animation_texts))
	return "\n".join(lines) + "\n"


## JSON in the TexturePacker "hash" format, readable by most engines and tools.
## [param tags] are added as Aseprite-style "frameTags", and with [param fps] each frame
## gets an Aseprite-style duration in milliseconds, or the one in [param durations] (by
## frame index, see [method frame_durations]). [param animation_names] lists the frames
## of each animation in "animations" (see [method animation_frame_names]).
static func texture_packer_json(
	frames: Array[Dictionary],
	image_file: String,
	image_size: Vector2i,
	tags: Array[Dictionary] = [],
	fps := 0.0,
	durations := {},
	animation_names := {},
) -> String:
	var entries := {}
	for index in frames.size():
		var frame := frames[index]
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
		if durations.has(index):
			entries[frame.name]["duration"] = durations[index]
		elif fps > 0:
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
	if not animation_names.is_empty():
		data.meta.animations = animation_names
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
