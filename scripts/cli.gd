class_name Cli
## Command-line mode, for build pipelines. Arguments go after "--":
##
## [codeblock]
## spritesheetbelli --headless -- --pack ./frames --out sheet.png --columns 8
## spritesheetbelli --headless -- --export hero.sbelli --out hero.png --sprites ./hero_frames
## spritesheetbelli --headless -- --cut packed.png --detect --sprites ./frames
## [/codeblock]

const USAGE := """Usage: spritesheetbelli --headless -- <command> [options]

Commands:
  --pack <folder or images...>   Pack images (sorted by name) into a spritesheet
  --export <project.sbelli>      Export a saved project
  --cut <image>                  Cut a spritesheet or animated GIF into frames: with the
                                 data file next to it (TexturePacker or Aseprite JSON),
                                 else a grid guessed from the name or the gaps
  --help                         Show this help

Options:
  --out <file>                   Image (.png, .jpg, .webp), animated GIF (.gif) or
                                 project (.sbelli) to write
  --sprites <folder>             Also export every frame as its own PNG
  --columns <n>                  Frames per row when packing (default: all in one row)
  --sprite-size <width>x<height> Resize the sprites
  --padding <px>                 Empty pixels around the sheet
  --spacing <px>                 Empty pixels between cells
  --extrude <px>                 Repeat frame edges outward
  --metadata <json|godot>        Also write a TexturePacker JSON or Godot SpriteFrames file
  --fps <n>                      Animation speed in the metadata and GIFs (default 12)
  --atlas                        Write --out as a packed atlas with a JSON file
  --atlas-data <format>          The atlas's data file: json (TexturePacker hash),
                                 json-array, phaser, atlas (libGDX / Spine),
                                 sparrow (Starling XML) or godot (SpriteFrames)
  --animation <name>             The animation a GIF plays (default: the first one, or
                                 every frame when there are none)
  --scale <n>                    Make a GIF n times bigger

Cutting:
  --grid <columns>x<rows>        Cut a grid of this size
  --data <file.json>             Cut where this data file says
  --detect                       Find the sprites by the transparency around them
  --join <px>                    With --detect, keep parts this close together
  --align <center|bottom>        With --detect, how to line the frames up"""

const COMMANDS: Array[String] = ["--pack", "--export", "--cut", "--help"]
## Options without a value
const FLAGS: Array[String] = ["--help", "--atlas", "--detect"]


## Whether [param args] ask for command-line mode
static func is_cli(args: PackedStringArray) -> bool:
	for arg in args:
		if arg in COMMANDS:
			return true
	return false


## Runs the command and returns the exit code: 0 on success, 1 on errors, 2 on bad usage.
## Messages go to [param output], or are printed when it's not given.
static func run(args: PackedStringArray, output: Array[String] = []) -> int:
	var say := func(line: String) -> void:
		output.append(line)
		print(line)
	var options := _parse(args)
	if options.has("error"):
		say.call("Error: %s\n\n%s" % [options.error, USAGE])
		return 2
	if options.has("--help"):
		say.call(USAGE)
		return 0

	var sheet: Spritesheet
	if options.has("--pack"):
		sheet = _pack(options["--pack"], int(options.get("--columns", "0")), say)
	elif options.has("--cut"):
		var cut := _cut(options["--cut"][0], options)
		if cut.has("error"):
			say.call("Error: %s" % cut.error)
			return cut.get("code", 1)
		sheet = cut.sheet
	else:
		var loaded := ProjectFile.load(options["--export"][0])
		if loaded.has("error"):
			say.call("Error: %s" % loaded.error)
			return 1
		sheet = Spritesheet.new()
		sheet.set_state(loaded.state)
	if sheet == null or sheet.is_empty():
		say.call("Error: there are no frames to export.")
		return 1

	var export := ExportOptions.new()
	export.apply(sheet.export_settings)
	for key: String in ["padding", "spacing", "extrude"]:
		if options.has("--" + key):
			export.set(key, int(options["--" + key]))
	if options.has("--metadata"):
		var formats := {
			"json": ExportOptions.MetadataFormat.JSON, "godot": ExportOptions.MetadataFormat.GODOT
		}
		if not formats.has(options["--metadata"]):
			say.call("Error: --metadata must be json or godot.")
			return 2
		export.metadata = formats[options["--metadata"]]
	if options.has("--fps"):
		export.animation_fps = float(options["--fps"])
	if options.has("--animation"):
		export.gif_animation = options["--animation"]
		if export.get_gif_animation(sheet) == null:
			say.call("Error: there's no animation called %s." % export.gif_animation)
			return 2
	elif export.gif_animation.is_empty() and not sheet.animations.is_empty():
		export.gif_animation = sheet.animations[0].name
	if options.has("--atlas-data"):
		if not AtlasFormats.FORMATS.has(options["--atlas-data"]):
			say.call(
				"Error: --atlas-data must be one of %s." % ", ".join(AtlasFormats.FORMATS.keys())
			)
			return 2
		export.atlas_data = options["--atlas-data"]
	if options.has("--scale"):
		export.gif_scale = clampi(int(options["--scale"]), 1, 16)
	sheet.set_export_settings(export.to_dictionary())
	if options.has("--sprite-size"):
		var size := _parse_size(options["--sprite-size"])
		if size == Vector2i.ZERO:
			say.call("Error: --sprite-size must look like 32x32.")
			return 2
		sheet.resize_sprites(size)

	var code := 0
	if options.has("--out"):
		var out: String = options["--out"]
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		if options.has("--atlas"):
			code = _write_atlas(sheet, out, export, say)
		elif GifDecoder.is_gif_path(out):
			code = await _write_gif(sheet, out, export, say)
		else:
			code = _write(sheet, out, export, say)
	if options.has("--sprites") and code == 0:
		var folder: String = options["--sprites"]
		DirAccess.make_dir_recursive_absolute(folder)
		var errors: PackedStringArray = []
		var written := SpritesheetExporter.export_sprites(sheet, folder, errors, 0, export)
		for error in errors:
			say.call("Error: could not write %s" % error)
		say.call("Wrote %d sprites to %s" % [written.size(), folder])
		code = 1 if errors else code
	return code


static func _parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg in FLAGS:
			options[arg] = true
		elif arg in ["--pack", "--export", "--cut"]:
			var values: PackedStringArray = []
			while i + 1 < args.size() and not args[i + 1].begins_with("--"):
				i += 1
				values.append(args[i])
			if values.is_empty():
				return {"error": "%s needs a file or folder." % arg}
			options[arg] = values
		elif arg.begins_with("--"):
			if i + 1 >= args.size():
				return {"error": "%s needs a value." % arg}
			i += 1
			options[arg] = args[i]
		i += 1
	if options.has("--help"):
		return options
	var commands := ["--pack", "--export", "--cut"].filter(
		func(command: String) -> bool: return options.has(command)
	)
	if commands.size() != 1:
		return {"error": "use one of --pack, --export or --cut."}
	if not options.has("--out") and not options.has("--sprites"):
		return {"error": "say where to write with --out or --sprites."}
	return options


static func _pack(sources: PackedStringArray, columns: int, say: Callable) -> Spritesheet:
	var paths: PackedStringArray = []
	for source in sources:
		if DirAccess.dir_exists_absolute(source):
			for file in DirAccess.get_files_at(source):
				if FileController.is_image_path(file):
					paths.append(source.path_join(file))
		else:
			paths.append(source)
	var sorted := Array(paths)
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)

	var images: Array[Image] = []
	for path: String in sorted:
		var frames := ImageLoader.load_frames(path)
		if frames.is_empty():
			say.call("Warning: could not load %s" % path)
		images.append_array(frames)

	var sheet := Spritesheet.new()
	if columns > 0 and not images.is_empty():
		sheet.set_grid_size(Vector2i(columns, ceili(images.size() / float(columns))))
	sheet.add_frames(images)
	return sheet


## Cuts the image at [param path] the way [param options] say. Returns
## [code]{"sheet": Spritesheet}[/code], or [code]{"error": String, "code": int}[/code].
static func _cut(path: String, options: Dictionary) -> Dictionary:
	if GifDecoder.is_gif_path(path):
		var gif := GifDecoder.load_file(path)
		if gif.has("error"):
			return gif
		var from_gif := Spritesheet.new()
		GifDecoder.add_to_sheet(from_gif, gif, path.get_file().get_basename())
		return {"sheet": from_gif}

	var data_path: String = options.get("--data", "")
	if SheetData.is_data_path(path):
		data_path = path
	var data: SheetData = null
	if data_path:
		data = SheetData.load_file(data_path)
		if data.error:
			return {"error": data.error}
		if SheetData.is_data_path(path):
			path = data.get_image_path(data_path)
	var img := Image.load_from_file(path)
	if img == null:
		return {"error": "could not load %s." % path}

	if options.has("--detect"):
		var alignments := {
			"center": Spritesheet.Alignment.CENTER, "bottom": Spritesheet.Alignment.BOTTOM
		}
		var align: String = options.get("--align", "center")
		if not alignments.has(align):
			return {"error": "--align must be center or bottom.", "code": 2}
		var rows := SpriteDetector.detect(img, int(options.get("--join", "0")))
		return {"sheet": SpriteDetector.to_spritesheet(img, rows, alignments[align])}
	# Without a grid, a data file next to the image says where the frames are
	if data == null and not options.has("--grid"):
		data_path = SheetData.find_for_image(path)
		if data_path:
			data = SheetData.load_file(data_path)
	if data:
		return {"sheet": data.to_spritesheet(img)}

	var grid := GridGuesser.guess(img, path)
	if options.has("--grid"):
		grid = _parse_size(options["--grid"])
		if grid.x <= 0 or grid.y <= 0:
			return {"error": "--grid must look like 8x2.", "code": 2}
	var sliced := Slicer.slice(img, grid)
	var sheet := Spritesheet.new()
	sheet.begin_batch()
	sheet.set_grid_size(grid)
	for coord: Vector2i in sliced.frames:
		sheet.set_frame(coord, sliced.frames[coord])
	sheet.end_batch()
	return {"sheet": sheet}


static func _write(sheet: Spritesheet, path: String, export: ExportOptions, say: Callable) -> int:
	var error: Error
	if ProjectFile.is_project_path(path):
		error = ProjectFile.save(sheet, path)
	else:
		path = SpritesheetExporter.with_image_extension(path)
		var problem := ImageUtils.size_problem(
			SpritesheetExporter.get_image_size(sheet, export), path.get_extension()
		)
		if problem:
			say.call("Error: " + problem)
			return 1
		error = SpritesheetExporter.save_image(sheet.get_image(export), path, export)
	if error == OK and not ProjectFile.is_project_path(path):
		error = Metadata.write_for_image(sheet, export, path)
	if error != OK:
		say.call("Error: could not write %s (%s)" % [path, error_string(error)])
		return 1
	var size := SpritesheetExporter.get_image_size(sheet, export)
	say.call(
		(
			"Wrote %s: %d frames, %d×%d grid, %d×%d px"
			% [path, sheet.frames.size(), sheet.grid_size.x, sheet.grid_size.y, size.x, size.y]
		)
	)
	return 0


static func _write_atlas(
	sheet: Spritesheet, path: String, export: ExportOptions, say: Callable
) -> int:
	var result := AtlasPacker.write(sheet, export, path)
	if result.error == ERR_OUT_OF_MEMORY:
		say.call("Error: the frames don't fit in a %d px atlas." % AtlasPacker.MAX_SIZE)
		return 1
	if result.error == ERR_UNAVAILABLE:
		say.call("Error: " + result.message)
		return 1
	if result.error != OK:
		say.call("Error: could not write %s (%s)" % [result.path, error_string(result.error)])
		return 1
	var size: Vector2i = result.size
	if result.pages > 1:
		say.call(
			(
				"Wrote %d pages from %s and %s: %d frames"
				% [result.pages, result.path, result.json_path.get_file(), result.frames]
			)
		)
		return 0
	say.call(
		(
			"Wrote %s and %s: %d frames, %d×%d px"
			% [result.path, result.json_path.get_file(), result.frames, size.x, size.y]
		)
	)
	return 0


static func _write_gif(
	sheet: Spritesheet, path: String, export: ExportOptions, say: Callable
) -> int:
	var result := await GifEncoder.write(sheet, export, path)
	if result.error != OK:
		say.call("Error: could not write %s (%s)" % [result.path, error_string(result.error)])
		return 1
	say.call("Wrote %s: %d frames" % [result.path, result.frames])
	return 0


static func _parse_size(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1])).max(Vector2i.ZERO)
