class_name Cli
## Command-line mode, for build pipelines. Arguments go after "--":
##
## [codeblock]
## spritesheetbelli --headless -- --pack ./frames --out sheet.png --columns 8
## spritesheetbelli --headless -- --export hero.sbelli --out hero.png --sprites ./hero_frames
## [/codeblock]

const USAGE := """Usage: spritesheetbelli --headless -- <command> [options]

Commands:
  --pack <folder or images...>   Pack images (sorted by name) into a spritesheet
  --export <project.sbelli>      Export a saved project
  --help                         Show this help

Options:
  --out <file>                   Image (.png, .jpg, .webp) or project (.sbelli) to write
  --sprites <folder>             Also export every frame as its own PNG
  --columns <n>                  Frames per row when packing (default: all in one row)
  --sprite-size <width>x<height> Resize the sprites
  --padding <px>                 Empty pixels around the sheet
  --spacing <px>                 Empty pixels between cells
  --extrude <px>                 Repeat frame edges outward
  --metadata <json|godot>        Also write a TexturePacker JSON or Godot SpriteFrames file
  --fps <n>                      Animation speed in the metadata (default 12)"""

const COMMANDS: Array[String] = ["--pack", "--export", "--help"]


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
	sheet.set_export_settings(export.to_dictionary())
	if options.has("--sprite-size"):
		var size := _parse_size(options["--sprite-size"])
		if size == Vector2i.ZERO:
			say.call("Error: --sprite-size must look like 32x32.")
			return 2
		sheet.resize_sprites(size)

	var code := 0
	if options.has("--out"):
		code = _write(sheet, options["--out"], export, say)
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
		if arg == "--help":
			options[arg] = true
		elif arg == "--pack" or arg == "--export":
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
	if options.has("--pack") == options.has("--export"):
		return {"error": "use either --pack or --export."}
	if not options.has("--out") and not options.has("--sprites"):
		return {"error": "say where to write with --out or --sprites."}
	return options


static func _pack(sources: PackedStringArray, columns: int, say: Callable) -> Spritesheet:
	var paths: PackedStringArray = []
	for source in sources:
		if DirAccess.dir_exists_absolute(source):
			for file in DirAccess.get_files_at(source):
				if file.get_extension().to_lower() in SpritesheetExporter.IMAGE_EXTENSIONS:
					paths.append(source.path_join(file))
		else:
			paths.append(source)
	var sorted := Array(paths)
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)

	var images: Array[Image] = []
	for path: String in sorted:
		var img := Image.load_from_file(path)
		if img:
			img.resource_name = path.get_file()
			images.append(img)
		else:
			say.call("Warning: could not load %s" % path)

	var sheet := Spritesheet.new()
	if columns > 0 and not images.is_empty():
		sheet.set_grid_size(Vector2i(columns, ceili(images.size() / float(columns))))
	sheet.add_frames(images)
	return sheet


static func _write(sheet: Spritesheet, path: String, export: ExportOptions, say: Callable) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
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


static func _parse_size(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1])).max(Vector2i.ZERO)
