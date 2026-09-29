class_name Cli
## Command-line mode, for build pipelines. Arguments go after "--":
##
## [codeblock]
## spritesheetbelli --headless -- --pack ./frames --out sheet.png --columns 8
## spritesheetbelli --headless -- --export hero.sbelli --out hero.png --sprites ./hero_frames
## spritesheetbelli --headless -- --export hero.sbelli
## spritesheetbelli --headless -- --cut packed.png --detect --sprites ./frames
## spritesheetbelli --headless -- --cut atlas.json --layout packed --out atlas.sbelli
## [/codeblock]

const USAGE := """Usage: spritesheetbelli --headless -- <command> [options]

Commands:
  --pack <folder or images...>   Pack images (sorted by name) into a spritesheet
  --export <project.sbelli>      Export a saved project: to --out or --sprites, or
                                 without them to every export the project has, as
                                 set up in the Export dialog (paths are relative to
                                 the project)
  --cut <image>                  Cut a spritesheet or animated GIF into frames: with the
                                 data file next to it (TexturePacker, Aseprite or Phaser
                                 JSON, libGDX / Spine .atlas), else a grid guessed from
                                 the name or the gaps. A solid background colour, like
                                 magenta, is made transparent.
  --help                         Show this help

Options:
  --out <file>                   Image (.png, .jpg, .webp), animated GIF (.gif) or
                                 project (.sbelli) to write
  --sprites <folder>             Also export every frame as its own PNG
  --columns <n>                  Frames per row when packing (default: all in one row)
  --sprite-size <width>x<height> Resize the sprites
  --padding <px>                 Empty pixels around the sheet (or each atlas page)
  --spacing <px>                 Empty pixels between cells (or packed frames)
  --extrude <px>                 Repeat frame edges outward
  --metadata <format>            Also write a data file with the project's animations:
                                 json (TexturePacker hash), json-array, phaser,
                                 atlas (libGDX / Spine), sparrow (Starling XML),
                                 godot (SpriteFrames) or the id of a template in the
                                 user templates folder (its file name without
                                 .template)
  --fps <n>                      Animation speed in the data file and GIFs (default 12)
  --atlas                        Write --out as a packed atlas with a data file. Packed
                                 sheets are always written as atlases.
  --atlas-data <format>          The atlas's data file, one of the --metadata formats
                                 (default json)
  --template <file>              Write the data file (of the image or the atlas) from
                                 this template file. Sheets are packed when it only
                                 describes packed atlases.
  --animation <name>             The animation a GIF plays (default: the first one, or
                                 every frame when there are none)
  --scale <n>                    Make a GIF n times bigger

Packed layout:
  --layout <grid|packed>         Lay the frames out in a grid or packed on pages. A packed
                                 sheet cut with a data file or --detect keeps every
                                 frame where it is in the image.
  --max-size <px>                Pages are at most this wide and tall (default 4096)
  --rotate                       Frames may be turned 90° to fit
  --repack                       Pack a packed project again; pinned frames stay

Cutting:
  --grid <columns>x<rows>        Cut a grid of this size
  --data <file>                  Cut where this data file (.json or .atlas) says
  --detect                       Find the sprites by the transparency around them
  --join <px>                    With --detect, keep parts this close together
  --align <center|bottom>        With --detect, how to line the frames up
  --keep-background              Keep a solid background colour instead of making it
                                 transparent
  --tolerance <percent>          How different a pixel can be from the background colour
                                 and still be made transparent (default 10)"""

const COMMANDS: Array[String] = ["--pack", "--export", "--cut", "--help"]
## Options without a value
const FLAGS: Array[String] = [
	"--help", "--atlas", "--detect", "--rotate", "--repack", "--keep-background"
]
## Options of what --out is written as, which the exports of a project have their own of
const OUT_OPTIONS: Array[String] = [
	"--metadata", "--template", "--atlas-data", "--atlas", "--fps", "--animation", "--scale"
]


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

	var layout: String = options.get("--layout", "")
	if layout not in ["", "grid", "packed"]:
		say.call("Error: --layout must be grid or packed.")
		return 2
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
	var problem := _set_up_layout(sheet, layout, options)
	if problem:
		say.call("Error: " + problem)
		return 2

	var export := ExportOptions.new()
	export.use_defaults_of(sheet)
	export.apply(sheet.export_settings)
	for key: String in ["padding", "spacing", "extrude"]:
		if options.has("--" + key):
			export.set(key, int(options["--" + key]))
	problem = _set_data_format(export, options)
	if problem:
		say.call("Error: " + problem)
		return 2
	if options.has("--fps"):
		export.animation_fps = float(options["--fps"])
	if options.has("--animation"):
		export.gif_animation = options["--animation"]
		if export.get_gif_animation(sheet) == null:
			say.call("Error: there's no animation called %s." % export.gif_animation)
			return 2
	elif export.gif_animation.is_empty() and not sheet.animations.is_empty():
		export.gif_animation = sheet.animations[0].name
	if options.has("--scale"):
		export.gif_scale = clampi(int(options["--scale"]), 1, 16)
	sheet.set_export_settings(export.to_dictionary())
	if options.has("--sprite-size"):
		var size := _parse_size(options["--sprite-size"])
		if size == Vector2i.ZERO:
			say.call("Error: --sprite-size must look like 32x32.")
			return 2
		sheet.resize_sprites(size)

	if not options.has("--out") and not options.has("--sprites"):
		return await _run_targets(sheet, say)
	var code := 0
	if options.has("--out"):
		var out: String = options["--out"]
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var packed := sheet.layout == Spritesheet.Layout.PACKED
		var image := not ProjectFile.is_project_path(out) and not GifDecoder.is_gif_path(out)
		var custom := export.target == ExportOptions.Target.CUSTOM
		if image and export.get_template_error():
			say.call("Error: " + export.get_template_error())
			return 1
		if options.has("--atlas") or image and (packed or custom and export.packs(sheet)):
			code = _write_atlas(sheet, out, export, say)
		elif GifDecoder.is_gif_path(out):
			code = await _write_gif(sheet, out, export, say)
		else:
			code = _write(sheet, out, export, say)
	if options.has("--sprites") and code == 0:
		code = _write_sprites(sheet, options["--sprites"], export, say)
	return code


## Writes every export of the project, see [ExportTarget]. Returns the exit code.
static func _run_targets(sheet: Spritesheet, say: Callable) -> int:
	var targets := ExportTarget.list(sheet)
	if targets.is_empty():
		say.call(
			(
				"Error: the project has no exports. Add them in the Export dialog, or say "
				+ "where to write with --out or --sprites."
			)
		)
		return 1
	var code := 0
	for target in targets:
		if target.path.is_empty():
			say.call("Error: no file is picked for an export (%s)." % target.get_format_name())
			code = 1
		elif await _write_target(sheet, target, say) != 0:
			code = 1
	return code


## Writes one export of the project the way the app does. Returns the exit code.
static func _write_target(sheet: Spritesheet, target: ExportTarget, say: Callable) -> int:
	var export := target.options
	var path := ExportTarget.fit_path(target.path, export)
	if export.get_template_error():
		say.call("Error: " + export.get_template_error())
		return 1
	if export.target == ExportOptions.Target.SPRITES:
		return _write_sprites(sheet, path, export, say)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if export.packs(sheet):
		return _write_atlas(sheet, path, export, say)
	if export.target == ExportOptions.Target.GIF:
		return await _write_gif(sheet, path, export, say)
	if sheet.layout == Spritesheet.Layout.PACKED:
		return _write_pages(sheet, path, export, say)
	return _write(sheet, path, export, say)


## Sets the data files of [param export] from --metadata, --atlas-data and --template in
## [param options]. Returns what's wrong with them, or an empty string.
static func _set_data_format(export: ExportOptions, options: Dictionary) -> String:
	if options.has("--metadata") and options.has("--template"):
		return "use --metadata or --template, not both."
	for key: String in ["--metadata", "--atlas-data"]:
		var layout := "grid" if key == "--metadata" else "packed"
		if options.has(key) and not AtlasFormats.has_format(options[key], layout):
			var formats := AtlasFormats.get_formats(layout)
			return "%s must be one of %s." % [key, ", ".join(formats)]
	if options.has("--metadata"):
		export.target = ExportOptions.Target.DATA
		export.grid_data = options["--metadata"]
	if options.has("--atlas-data"):
		export.atlas_data = options["--atlas-data"]
	if options.has("--template"):
		export.target = ExportOptions.Target.CUSTOM
		export.custom_template = options["--template"]
	return ""


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
	if options.has("--out") or options.has("--sprites"):
		return options
	# A project without them writes its own exports
	if not options.has("--export"):
		return {"error": "say where to write with --out or --sprites."}
	for option in OUT_OPTIONS:
		if options.has(option):
			return {"error": "%s needs --out: the project's exports have their own." % option}
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
	var tolerance := SheetBackground.DEFAULT_TOLERANCE
	if options.has("--tolerance"):
		var percent: String = options["--tolerance"]
		if not percent.is_valid_float() or float(percent) < 0 or float(percent) > 100:
			return {"error": "--tolerance must be from 0 to 100.", "code": 2}
		tolerance = float(percent) / 100.0
	# A sheet on a solid colour has it made transparent, like Add Spritesheet does. Its
	# gaps are found in the keyed image even when the colour is kept.
	var background: Variant = SheetBackground.detect(img)
	var keyed := SheetBackground.remove(img, background, tolerance) if background != null else img
	var keep_background := options.has("--keep-background")
	var cut_from := img if keep_background else keyed

	if options.has("--detect"):
		var alignments := {
			"center": Spritesheet.Alignment.CENTER, "bottom": Spritesheet.Alignment.BOTTOM
		}
		var align: String = options.get("--align", "center")
		if not alignments.has(align):
			return {"error": "--align must be center or bottom.", "code": 2}
		var rows := SpriteDetector.detect(keyed, int(options.get("--join", "0")))
		var detected := SpriteDetector.to_spritesheet(
			cut_from, rows, alignments[align], "", options.get("--layout") == "packed"
		)
		return {"sheet": detected}
	# Without a grid, a data file next to the image says where the frames are
	if data == null and not options.has("--grid"):
		data_path = SheetData.find_for_image(path)
		if data_path:
			data = SheetData.load_file(data_path)
	if data:
		# Frames on other pages come from the pages' images
		var others: Array[Image] = []
		var pages := data.get_page_paths(data_path)
		for page in range(1, pages.size()):
			var other := Image.load_from_file(pages[page])
			if other and background != null and not keep_background:
				other = SheetBackground.remove(other, background, tolerance)
			others.append(other)
		var keep: bool = options.get("--layout") == "packed"
		return {"sheet": data.to_spritesheet(cut_from, "", "", keep, others)}

	var grid := GridGuesser.guess(keyed, path)
	if options.has("--grid"):
		grid = _parse_size(options["--grid"])
		if grid.x <= 0 or grid.y <= 0:
			return {"error": "--grid must look like 8x2.", "code": 2}
	var sliced := Slicer.slice(cut_from, grid)
	var sheet := Spritesheet.new()
	sheet.begin_batch()
	sheet.set_grid_size(grid)
	for coord: Vector2i in sliced.frames:
		sheet.set_frame(coord, sliced.frames[coord])
	sheet.end_batch()
	return {"sheet": sheet}


## Lays [param sheet] out as [param layout] ("grid", "packed" or "" to leave it) with the
## atlas settings in [param options]. Returns what's wrong with them, or an empty string.
static func _set_up_layout(sheet: Spritesheet, layout: String, options: Dictionary) -> String:
	var settings := sheet.atlas_settings
	if options.has("--max-size"):
		var max_size := int(options["--max-size"])
		if max_size < 16 or max_size > AtlasPacker.MAX_SIZE:
			return "--max-size must be from 16 to %d." % AtlasPacker.MAX_SIZE
		settings.max_size = max_size
	if options.has("--rotate"):
		settings.allow_rotation = true
	# A packed sheet's spacing belongs to how it's packed
	if layout == "packed" or sheet.layout == Spritesheet.Layout.PACKED:
		for key: String in ["padding", "spacing", "extrude"]:
			if options.has("--" + key):
				settings.set(key, int(options["--" + key]))
	sheet.begin_batch()
	sheet.set_atlas_settings(settings)
	if layout == "packed":
		sheet.set_layout(Spritesheet.Layout.PACKED)
	elif layout == "grid":
		sheet.set_layout(Spritesheet.Layout.GRID)
	sheet.end_batch()
	if options.has("--repack") and sheet.layout == Spritesheet.Layout.PACKED:
		sheet.set_placements(PackedLayout.arrange(sheet, true).placements)
	return ""


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
	if sheet.layout == Spritesheet.Layout.PACKED:
		say.call("Wrote %s: %s" % [path, PackedLayout.describe(sheet)])
		return 0
	var size := SpritesheetExporter.get_image_size(sheet, export)
	say.call(
		(
			"Wrote %s: %d frames, %d×%d grid, %d×%d px"
			% [path, sheet.frames.size(), sheet.grid_size.x, sheet.grid_size.y, size.x, size.y]
		)
	)
	return 0


static func _write_sprites(
	sheet: Spritesheet, folder: String, export: ExportOptions, say: Callable
) -> int:
	DirAccess.make_dir_recursive_absolute(folder)
	var errors: PackedStringArray = []
	var written := SpritesheetExporter.export_sprites(sheet, folder, errors, 0, export)
	for error in errors:
		say.call("Error: could not write %s" % error)
	say.call("Wrote %d sprites to %s" % [written.size(), folder])
	return 1 if errors else 0


## Writes each page of a packed sheet as an image, numbered when there are more
static func _write_pages(
	sheet: Spritesheet, path: String, export: ExportOptions, say: Callable
) -> int:
	var pages := SpritesheetExporter.build_pages(sheet, export)
	var paths := SpritesheetExporter.get_page_paths(path, pages.size())
	for i in pages.size():
		var error := SpritesheetExporter.save_image(pages[i], paths[i], export)
		if error != OK:
			say.call("Error: could not write %s (%s)" % [paths[i], error_string(error)])
			return 1
	say.call("Wrote %s: %s" % [", ".join(paths), PackedLayout.describe(sheet)])
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
