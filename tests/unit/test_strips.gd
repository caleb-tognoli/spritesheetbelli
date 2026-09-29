extends "res://tests/test_case.gd"

const COLORS: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]

var folder := temp_path("strips")


func after_each() -> void:
	remove_dir(folder)


## Four frames in a row, the last two smaller, centred in 8×8 cells
static func make_sheet() -> Spritesheet:
	var sheet := Spritesheet.new()
	var images: Array[Image] = []
	for i in COLORS.size():
		images.append(make_image(COLORS[i], Vector2i(8, 8) if i < 2 else Vector2i(4, 6)))
	sheet.add_frames(images)
	return sheet


func strip_options() -> ExportOptions:
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.STRIPS
	return options


func test_a_strip_of_each_animation() -> void:
	var sheet := make_sheet()
	var coords := sheet.get_sorted_coords()
	sheet.add_animation(SheetAnimation.create("walk", [coords[2], coords[0], coords[2]]))
	sheet.add_animation(SheetAnimation.create("idle", [coords[1]]))
	sheet.add_animation(SheetAnimation.create("empty", [] as Array[Vector2i]))
	var options := strip_options()
	assert_eq(options.get_file_extension(), "", "a folder")
	var result := StripExporter.write(sheet, options, folder)
	assert_eq(result.error, OK)
	assert_eq(
		Array(result.paths),
		[folder.path_join("walk_strip3.png"), folder.path_join("idle_strip1.png")],
		"frames in no animation and animations without frames are left out"
	)
	assert_eq(ExportFiles.get_paths(sheet, options, folder), result.paths, "listed as written")

	# Frames side by side, each in a cell, in the animation's order, nothing between them
	var walk := Image.load_from_file(folder.path_join("walk_strip3.png"))
	assert_eq(walk.get_size(), Vector2i(24, 8))
	assert_color(walk, Vector2i(0, 0), Color(0, 0, 0, 0), "a smaller frame in its cell")
	assert_color(walk, Vector2i(3, 3), Color.BLUE)
	assert_color(walk, Vector2i(8, 0), Color.RED)
	assert_color(walk, Vector2i(15, 7), Color.RED)
	assert_color(walk, Vector2i(19, 3), Color.BLUE)
	var idle := Image.load_from_file(folder.path_join("idle_strip1.png"))
	assert_eq(idle.get_size(), Vector2i(8, 8))
	assert_color(idle, Vector2i(4, 4), Color.GREEN)

	# A pattern of its own, a background
	options.strip_name_pattern = "spr_{animation}_strip{count}.png"
	options.background = Color.WHITE
	result = StripExporter.write(sheet, options, folder)
	assert_eq(result.paths[0].get_file(), "spr_walk_strip3.png")
	walk = Image.load_from_file(result.paths[0])
	assert_color(walk, Vector2i(0, 0), Color.WHITE)


func test_a_sheet_without_animations_is_one_strip() -> void:
	var sheet := make_sheet()
	var strips := StripExporter.get_strips(sheet, strip_options(), folder)
	assert_eq(strips.size(), 1)
	assert_eq(strips[0].path.get_file(), "frame_strip4.png")
	assert_eq(StripExporter.build_strip(sheet, strips[0].cells).get_size(), Vector2i(32, 8))
	var result := StripExporter.write(Spritesheet.new(), strip_options(), folder)
	assert_eq(result.error, ERR_DOES_NOT_EXIST, "nothing to write")


func test_command_line() -> void:
	var sheet := make_sheet()
	sheet.add_animation(SheetAnimation.create("walk", sheet.get_sorted_coords().slice(0, 2)))
	var project := folder.path_join("hero.sbelli")
	DirAccess.make_dir_recursive_absolute(folder)
	assert_eq(ProjectFile.save(sheet, project), OK)
	var output: Array[String] = []
	var strips := folder.path_join("out")
	var args := PackedStringArray(["--export", project, "--strips", strips])
	assert_eq(await Cli.run(args, output), 0, str(output))
	assert_eq(output[-1], "Wrote 1 strips to %s" % strips)
	assert_eq(Array(DirAccess.get_files_at(strips)), ["walk_strip2.png"])
	assert_true("--strips <folder>" in Cli.USAGE)

	# A project's own export
	var target := ExportTarget.create(
		sheet, {"target": ExportOptions.Target.STRIPS, "path": folder.path_join("target")}
	)
	sheet.set_export_settings(ExportTarget.settings_with(sheet, [target]))
	assert_eq(ProjectFile.save(sheet, project), OK)
	assert_eq(await Cli.run(PackedStringArray(["--export", project]), output), 0, str(output))
	assert_true(FileAccess.file_exists(folder.path_join("target/walk_strip2.png")))
