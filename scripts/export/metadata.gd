class_name Metadata
## Describes where frames are in an exported image, for game engines. The files are
## written from the templates of [AtlasFormats].


## Writes the data file chosen in [param options] (see [method ExportOptions.get_image_data])
## next to an exported image
static func write_for_image(
	sheet: Spritesheet, options: ExportOptions, image_path: String, index_start := 0
) -> Error:
	var format := options.get_image_data()
	if not format:
		return OK
	if AtlasFormats.get_error(format):
		push_error(AtlasFormats.get_error(format))
		return ERR_PARSE_ERROR
	var page := {
		"file": image_path.get_file(),
		"size": SpritesheetExporter.get_image_size(sheet, options),
	}
	var retina := options.get_retina_path(image_path)
	if retina:
		page.retina_image = retina.get_file()
	var data := TemplateData.build(
		grid_frames(sheet, options, index_start),
		animations(sheet, false),
		[page] as Array[Dictionary],
		options.animation_fps,
		TemplateData.grid_values(sheet, options)
	)
	var file := FileAccess.open(get_path_for_image(image_path, options), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(AtlasFormats.render(format, data))
	file.close()
	return OK


## The data file next to [param image_path], named after it without the image's extension:
## "hero.png" gives "hero.json" and "hero.json.png" gives "hero.json.json"
static func get_path_for_image(image_path: String, options: ExportOptions) -> String:
	var format := SpritesheetExporter.get_image_format(image_path)
	var base := SpritesheetExporter.without_extension(image_path, format)
	return base + "." + AtlasFormats.get_extension(options.get_image_data())


## Every frame of a grid export in reading order, with its cell in the image and a unique
## name from the sprite name pattern. When pivots are turned on in Settings, each has a
## pivot across its cell, as an atlas's frames do: its own, or the atlas's default.
static func grid_frames(
	sheet: Spritesheet, options: ExportOptions, index_start := 0
) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var used := {}
	var with_pivots: bool = Settings.get_value(&"use_pivots")
	for coord in sheet.get_sorted_coords():
		var name := SpritesheetExporter.format_sprite_name(
			options.sprite_name_pattern, sheet, coord, index_start
		)
		var frame := {
			"name": unique_name(name, used) + ".png",
			"coord": coord,
			"cell": coord.y * sheet.grid_size.x + coord.x,
			"rect": SpritesheetExporter.get_cell_rect(sheet, coord, options),
		}
		if with_pivots:
			frame.pivot = grid_pivot(sheet, coord)
		frames.append(frame)
	return frames


## The pivot of the frame at [param coord] of a grid sheet, from 0 to 1 across its cell:
## its own, or the atlas's default (see [method AtlasPacker.get_regions])
static func grid_pivot(sheet: Spritesheet, coord: Vector2i) -> Vector2:
	if not sheet.has_pivot(coord):
		return sheet.atlas_settings.default_pivot
	var in_cell := sheet.get_frame_rect_in_cell(coord).position
	var pivot := sheet.get_pivot(coord) * sheet.frame_scale + Vector2(in_cell)
	return pivot / Vector2(sheet.sprite_size.max(Vector2i.ONE))


## [param name], or with _2, _3… after it when it's in [param used] already, which it's
## then added to. Data files name every frame differently, as engines look frames up by
## name.
static func unique_name(name: String, used: Dictionary) -> String:
	var unique := name
	var number := 2
	while used.has(unique):
		unique = "%s_%d" % [name, number]
		number += 1
	used[unique] = true
	return unique


## The sheet's animations. Without any, all frames form one "default" animation, so a
## SpriteFrames resource still has something to play, unless [param with_default] is
## false.
## Returns [code]{"name": String, "indices": Array, "durations": Array, "mode":
## SheetAnimation.Mode, "fps": float, "color": Color}[/code] with indices into
## [method grid_frames] and how many frames each is shown for; fps is 0 when not set, and
## the "default" animation has no colour.
static func animations(sheet: Spritesheet, with_default := true) -> Array[Dictionary]:
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
				(
					result
					. append(
						{
							"name": animation.name,
							"indices": indices,
							"durations": Array(animation.get_frame_durations(sheet)),
							"mode": animation.mode,
							"fps": animation.fps,
							"color": animation.color,
						}
					)
				)
		return result
	if with_default:
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


## TexturePacker-style JSON for [param frames] of [param sheet] (from [method grid_frames]
## or [method AtlasFormats.get_frames]), with its animations as frame tags and frame
## lists, and how long each frame is shown
static func sheet_json(
	sheet: Spritesheet, frames: Array[Dictionary], image_file: String, size: Vector2i, fps: float
) -> String:
	var page := {"file": image_file, "size": size}
	var data := TemplateData.build(
		frames, animations(sheet, false), [page] as Array[Dictionary], fps
	)
	return AtlasFormats.render("json", data)


## How long each frame of [method grid_frames] is shown in milliseconds, by index: from
## the first animation it's in, at that animation's speed or else [param fps]. Frames in
## no animation are left out.
static func frame_durations(sheet: Spritesheet, fps: float) -> Dictionary:
	return TemplateData.frame_durations(animations(sheet), fps)


## A Godot SpriteFrames resource using the image next to it, with [param animation_list]
## from [method animations]
## The images can be the pages of a packed atlas: [param image_files] replaces
## [param image_file] then, and frames say which "page" they're on.
static func sprite_frames_tres(
	frames: Array[Dictionary],
	animation_list: Array[Dictionary],
	image_file: String,
	fps: float,
	image_files := PackedStringArray(),
) -> String:
	if image_files.is_empty():
		image_files = [image_file]
	var pages: Array[Dictionary] = []
	for file in image_files:
		pages.append({"file": file, "size": Vector2i.ZERO})
	return AtlasFormats.render("godot", TemplateData.build(frames, animation_list, pages, fps))


## JSON in the TexturePacker "hash" format, readable by most engines and tools, for
## [param frames] on one image
static func texture_packer_json(
	frames: Array[Dictionary], image_file: String, image_size: Vector2i
) -> String:
	var page := {"file": image_file, "size": image_size}
	var data := TemplateData.build(frames, [], [page] as Array[Dictionary], 0.0)
	return AtlasFormats.render("json", data)
