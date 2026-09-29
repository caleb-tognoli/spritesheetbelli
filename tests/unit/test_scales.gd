extends "res://tests/test_case.gd"

var dir := temp_path("scales")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	Settings.set_value(&"use_pivots", false)
	remove_dir(dir)


## A 4×4 checkerboard of red and blue, and a smaller green frame centred in its cell
static func make_sheet() -> Spritesheet:
	var checker := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:
			checker.set_pixel(x, y, Color.RED if (x + y) % 2 == 0 else Color.BLUE)
	var sheet := Spritesheet.new()
	sheet.add_frames([checker, make_image(Color.GREEN, Vector2i(2, 4))] as Array[Image])
	return sheet


func make_options(target: ExportOptions.Target, scales := "1, 2") -> ExportOptions:
	var options := ExportOptions.new()
	options.target = target
	options.scales = scales
	return options


## Whether [param big] is [param small] with every pixel made [param scale] × as big
func assert_scaled(big: Image, small: Image, scale: int, message: String) -> void:
	assert_eq(big.get_size(), small.get_size() * scale, message + ": size")
	for y in small.get_height():
		for x in small.get_width():
			var want := small.get_pixel(x, y)
			for at: Vector2i in [Vector2i(x, y) * scale, Vector2i(x, y) * scale + Vector2i.ONE]:
				if big.get_pixelv(at) != want:
					fail("%s: %s at %s, expected %s" % [message, big.get_pixelv(at), at, want])
					return


static func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_scales_and_names() -> void:
	var options := make_options(ExportOptions.Target.IMAGE, "2, 1 2,3")
	assert_eq(options.get_scales(), PackedInt32Array([1, 2, 3]), "sorted, each once")
	assert_eq(options.get_scale_error(), "")
	assert_eq(options.scaled_path("a/hero.png", 1), "a/hero.png", "no suffix at 1")
	assert_eq(options.scaled_path("a/hero.png", 2), "a/hero@2x.png")
	assert_eq(options.scaled_path("a/hero", 3), "a/hero@3x")
	options.scale_suffix = "-{scale}"
	assert_eq(options.scaled_path("a/hero.data.png", 2), "a/hero.data-2.png")
	options.scale_suffix = "_hd"
	assert_eq(
		options.get_scale_error(),
		"The scale suffix needs {scale} to name each scale's files apart."
	)
	options.scales = "1, 2"
	assert_eq(options.get_scale_error(), "", "one scale named apart from 1")
	for wrong: String in ["1, 1.5", "0", "x", "17"]:
		options.scales = wrong
		assert_ne(options.get_scale_error(), "", wrong)
		assert_ne(options.get_error(), "", wrong + " stops the export")
	options.scales = "1,2"
	options.target = ExportOptions.Target.SPRITES
	assert_eq(options.get_scales(), PackedInt32Array([1]), "sprites have no scales")
	assert_eq(ExportOptions.new().get_scales(), PackedInt32Array([1]))

	# Each scale's files, its data file named after its image
	var sheet := make_sheet()
	options = make_options(ExportOptions.Target.DATA)
	assert_eq(
		ExportFiles.get_paths(sheet, options, "a/hero"),
		PackedStringArray(["a/hero.png", "a/hero.json", "a/hero@2x.png", "a/hero@2x.json"])
	)
	options = make_options(ExportOptions.Target.ATLAS, "2")
	assert_eq(
		ExportFiles.get_paths(sheet, options, "a/hero.png"),
		PackedStringArray(["a/hero@2x.png", "a/hero@2x.json"])
	)
	var restored := ExportOptions.new()
	restored.apply(make_options(ExportOptions.Target.IMAGE, "1, 4").to_dictionary())
	assert_eq(restored.get_scales(), PackedInt32Array([1, 4]), "kept with the project")


func test_a_grid_sheet_at_twice_the_size() -> void:
	var sheet := make_sheet()
	var options := make_options(ExportOptions.Target.DATA)
	options.padding = 1
	options.spacing = 2
	options.extrude = 1
	var one := options.for_scale(1)
	var two := options.for_scale(2)
	var small := SpritesheetExporter.build_image(sheet, one)
	var big := SpritesheetExporter.build_image(sheet, two)
	assert_eq(small.get_size(), Vector2i(2 + 2 * 6 + 2, 2 + 6))
	assert_scaled(big, small, 2, "padding, spacing and extrusion scale too")

	# The data file of each scale, with its coordinates
	for at: ExportOptions in [one, two]:
		var image := dir.path_join(options.scaled_path("hero.png", at.scale))
		assert_eq(Metadata.write_for_image(sheet, at, image), OK)
	var small_data := read_json(dir.path_join("hero.json"))
	var big_data := read_json(dir.path_join("hero@2x.json"))
	assert_eq(big_data.meta.image, "hero@2x.png")
	assert_eq(big_data.meta.size, {"w": float(big.get_width()), "h": float(big.get_height())})
	for frame_name: String in small_data.frames:
		var frame: Dictionary = small_data.frames[frame_name].frame
		var scaled: Dictionary = big_data.frames[frame_name].frame
		for key: String in ["x", "y", "w", "h"]:
			assert_eq(scaled[key], frame[key] * 2, "%s %s" % [frame_name, key])
	var cell := SpritesheetExporter.get_cell_rect(sheet, sheet.get_sorted_coords()[1], two)
	assert_eq(big_data.frames["1.png"].frame.x, cell.position.x)
	assert_eq(cell, Rect2i(20, 4, 8, 8), "(padding + extrude + a cell + spacing) × 2")


func test_frames_are_resized_from_their_originals() -> void:
	var sheet := make_sheet()
	# Scaled 1.5 times: the 4×4 frame is 6×6 at 1, and 12×12 from the original at 2
	sheet.set_frame_scale(Vector2(1.5, 1.5))
	var frame := SpritesheetExporter.get_scaled_frame(sheet, Vector2i.ZERO, 2)
	var expected := sheet.frames[Vector2i.ZERO].duplicate() as Image
	expected.resize(12, 12, Image.INTERPOLATE_NEAREST)
	assert_eq(frame.get_data(), expected.get_data())
	assert_eq(sheet.sprite_size, Vector2i(6, 6))
	var at_two := make_options(ExportOptions.Target.IMAGE).for_scale(2)
	assert_eq(
		SpritesheetExporter.get_frame_rect(sheet, Vector2i.ZERO, at_two).size, Vector2i(12, 12)
	)
	# With the sheet's filter
	sheet.set_frame_scale(Vector2.ONE, Image.INTERPOLATE_BILINEAR)
	frame = SpritesheetExporter.get_scaled_frame(sheet, Vector2i.ZERO, 4)
	var blended := frame.get_pixel(3, 5)
	assert_true(blended != Color.RED and blended != Color.BLUE, "smooth: %s" % blended)


func test_an_atlas_at_twice_the_size() -> void:
	Settings.set_value(&"use_pivots", true)
	var sheet := make_sheet()
	var settings := sheet.atlas_settings
	settings.padding = 1
	sheet.set_atlas_settings(settings)
	var options := make_options(ExportOptions.Target.ATLAS)
	options.spacing = 1
	var small := AtlasPacker.write(sheet, options.for_scale(1), dir.path_join("atlas.png"))
	var big := AtlasPacker.write(sheet, options.for_scale(2), dir.path_join("atlas@2x.png"))
	assert_eq(small.error, OK)
	assert_eq(big.error, OK)
	assert_eq(
		big.paths,
		PackedStringArray([dir.path_join("atlas@2x.png"), dir.path_join("atlas@2x.json")])
	)
	assert_eq(big.size, small.size * 2)
	assert_scaled(
		Image.load_from_file(big.path), Image.load_from_file(small.path), 2, "the same layout"
	)
	var small_data := read_json(small.json_path)
	var big_data := read_json(big.json_path)
	for frame_name: String in small_data.frames:
		var frame: Dictionary = small_data.frames[frame_name]
		var scaled: Dictionary = big_data.frames[frame_name]
		for part: String in ["frame", "spriteSourceSize", "sourceSize"]:
			for key: String in frame[part]:
				assert_eq(scaled[part][key], frame[part][key] * 2, "%s %s" % [part, key])
		assert_eq(scaled.pivot, frame.pivot, "the pivot is a fraction")

	# A sheet in the packed layout, as its pages
	sheet.set_layout(Spritesheet.Layout.PACKED)
	var one := SpritesheetExporter.build_pages(sheet, options.for_scale(1))
	var two := SpritesheetExporter.build_pages(sheet, options.for_scale(2))
	assert_scaled(two[0], one[0], 2, "packed pages")


func test_css_shows_twice_the_size_on_retina_screens() -> void:
	var sheet := make_sheet()
	var options := make_options(ExportOptions.Target.DATA)
	options.grid_data = "css"
	var image := dir.path_join("hero.png")
	assert_eq(Metadata.write_for_image(sheet, options.for_scale(1), image), OK)
	var css := FileAccess.get_file_as_string(dir.path_join("hero.css"))
	assert_true('url("hero@2x.png")' in css, css)
	var size := SpritesheetExporter.get_image_size(sheet, options)
	assert_true("background-size: %dpx %dpx;" % [size.x, size.y] in css, "the size at 1")
	assert_true("min-resolution: 2dppx" in css)
	var twice := dir.path_join("hero@2x.png")
	assert_eq(Metadata.write_for_image(sheet, options.for_scale(2), twice), OK)
	assert_false("@media" in FileAccess.get_file_as_string(dir.path_join("hero@2x.css")))
	options.scales = "1, 3"
	assert_eq(Metadata.write_for_image(sheet, options.for_scale(1), image), OK)
	assert_false("@media" in FileAccess.get_file_as_string(dir.path_join("hero.css")), "no 2")

	# An atlas's pages, in SCSS
	options = make_options(ExportOptions.Target.ATLAS)
	options.atlas_data = "scss"
	var atlas := AtlasPacker.write(sheet, options.for_scale(1), dir.path_join("atlas.png"))
	var scss := FileAccess.get_file_as_string(atlas.json_path)
	assert_true('retina-image: "atlas@2x.png"' in scss, scss)


## Three 12×12 frames on pages of 16 px, a page each
static func make_paged_sheet() -> Spritesheet:
	var sheet := Spritesheet.new()
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		images.append(make_image(color, Vector2i(12, 12)))
	sheet.add_frames(images)
	var settings := sheet.atlas_settings
	settings.max_size = 16
	sheet.set_atlas_settings(settings)
	return sheet


func test_pages_are_numbered_before_the_suffix() -> void:
	assert_eq(SpritesheetExporter.get_page_path("a/hero@2x.png", 0, "@2x"), "a/hero_0@2x.png")
	assert_eq(SpritesheetExporter.get_page_path("a/hero@2x", 1, "@2x"), "a/hero_1@2x")
	assert_eq(SpritesheetExporter.get_page_path("a/hero.png", 1), "a/hero_1.png")
	assert_eq(
		SpritesheetExporter.get_page_paths("a/hero@2x.png", 1, "@2x"),
		PackedStringArray(["a/hero@2x.png"]),
		"one page isn't numbered"
	)

	# An atlas with a data file per page, at each scale
	var sheet := make_paged_sheet()
	var options := make_options(ExportOptions.Target.ATLAS)
	options.atlas_data = "json"
	var path := dir.path_join("atlas.png")
	var written := PackedStringArray()
	var pages := 0
	for scale in options.get_scales():
		var at := options.for_scale(scale)
		var result := AtlasPacker.write(sheet, at, options.scaled_path(path, scale))
		assert_eq(result.error, OK)
		written.append_array(result.paths)
		pages = result.pages
	assert_true(pages > 1, "pages: %d" % pages)
	assert_eq(ExportFiles.get_paths(sheet, options, path), written, "listed as written")
	for page in pages:
		for file: String in ["atlas_%d@2x.png", "atlas_%d@2x.json", "atlas_%d.png"]:
			assert_true(dir.path_join(file % page) in written, file % page)
	var data := read_json(dir.path_join("atlas_1@2x.json"))
	assert_eq(data.meta.image, "atlas_1@2x.png")
	assert_true("atlas_0@2x.json" in str(data.meta), "names the other pages: %s" % data.meta)

	# The retina image of each page
	options.atlas_data = "scss"
	var scss_path: String = AtlasPacker.write(sheet, options.for_scale(1), path).json_path
	var scss := FileAccess.get_file_as_string(scss_path)
	assert_true('retina-image: "atlas_1@2x.png"' in scss, scss)

	# A sheet in the packed layout, as images
	sheet.set_layout(Spritesheet.Layout.PACKED)
	options = make_options(ExportOptions.Target.IMAGE)
	var listed := ExportFiles.get_paths(sheet, options, path)
	assert_true(dir.path_join("atlas_1@2x.png") in listed, str(listed))
	var project := dir.path_join("pages.sbelli")
	assert_eq(ProjectFile.save(sheet, project), OK)
	var output: Array[String] = []
	var out := dir.path_join("out/pages.png")
	var args := ["--export", project, "--out", out, "--scales", "1,2"]
	assert_eq(await Cli.run(PackedStringArray(args), output), 0, str(output))
	assert_true(FileAccess.file_exists(dir.path_join("out/pages_1@2x.png")), str(output))
	assert_true(FileAccess.file_exists(dir.path_join("out/pages_1@2x.json")), "an atlas")


func test_strips_at_twice_the_size() -> void:
	var sheet := make_sheet()
	sheet.add_animation(SheetAnimation.create("walk", sheet.get_sorted_coords()))
	var options := make_options(ExportOptions.Target.STRIPS)
	var folder := dir.path_join("strips")
	var result := StripExporter.write(sheet, options, folder)
	assert_eq(result.error, OK)
	assert_eq(
		Array(result.paths),
		[folder.path_join("walk_strip2.png"), folder.path_join("walk@2x_strip2.png")],
		"the suffix before _strip, as GameMaker names the sprite walk@2x"
	)
	assert_eq(ExportFiles.get_paths(sheet, options, folder), result.paths, "listed as written")
	assert_scaled(
		Image.load_from_file(result.paths[1]),
		Image.load_from_file(result.paths[0]),
		2,
		"a strip at 2, a smaller frame in its cell too"
	)

	# Patterns of their own
	options.strip_name_pattern = "spr_{animation}_strip{count:2}.png"
	assert_eq(StripExporter.get_name_pattern(options, 2), "spr_{animation}@2x_strip{count:2}")
	assert_eq(StripExporter.get_name_pattern(options, 1), options.strip_name_pattern)
	options.strip_name_pattern = "{count}_{animation}"
	assert_eq(StripExporter.get_name_pattern(options, 2), "{count}_{animation}@2x", "at the end")
	options.scale_suffix = "_hd{scale}"
	assert_eq(StripExporter.get_strips(sheet, options, folder)[1].path.get_file(), "2_walk_hd2.png")


func test_command_line() -> void:
	var sheet := make_sheet()
	var project := dir.path_join("hero.sbelli")
	assert_eq(ProjectFile.save(sheet, project), OK)
	var output: Array[String] = []
	var out := dir.path_join("out/hero.png")
	var args := ["--export", project, "--out", out, "--metadata", "json", "--scales", "1,2"]
	assert_eq(await Cli.run(PackedStringArray(args), output), 0, str(output))
	for file: String in ["hero.png", "hero.json", "hero@2x.png", "hero@2x.json"]:
		assert_true(FileAccess.file_exists(dir.path_join("out").path_join(file)), file)
	assert_scaled(
		Image.load_from_file(dir.path_join("out/hero@2x.png")),
		Image.load_from_file(out),
		2,
		"from the command line"
	)
	args = ["--export", project, "--out", dir.path_join("atlas.png"), "--atlas", "--scales", "2"]
	assert_eq(await Cli.run(PackedStringArray(args), output), 0, str(output))
	assert_true(FileAccess.file_exists(dir.path_join("atlas@2x.json")))
	assert_false(FileAccess.file_exists(dir.path_join("atlas.json")), "only at 2")
	args = ["--export", project, "--out", out, "--scales", "1,x"]
	assert_eq(await Cli.run(PackedStringArray(args), output), 2, "not a scale")
	assert_eq(await Cli.run(PackedStringArray(["--export", project, "--scales", "2"]), output), 2)
	var strips := dir.path_join("strips")
	args = ["--export", project, "--strips", strips, "--scales", "1,2"]
	assert_eq(await Cli.run(PackedStringArray(args), output), 0, str(output))
	var files := Array(DirAccess.get_files_at(strips))
	files.sort()
	assert_eq(files, ["frame@2x_strip2.png", "frame_strip2.png"], "strips too")
	assert_true("--scales <n,n...>" in Cli.USAGE)

	# A project's own export at its scales
	var target := (
		ExportTarget
		. create(
			sheet,
			{
				"target": ExportOptions.Target.IMAGE,
				"scales": "1, 2",
				"scale_suffix": "_{scale}x",
				"path": dir.path_join("target/hero.png"),
			}
		)
	)
	sheet.set_export_settings(ExportTarget.settings_with(sheet, [target]))
	assert_eq(ProjectFile.save(sheet, project), OK)
	assert_eq(await Cli.run(PackedStringArray(["--export", project]), output), 0, str(output))
	assert_eq(Array(DirAccess.get_files_at(dir.path_join("target"))), ["hero.png", "hero_2x.png"])
