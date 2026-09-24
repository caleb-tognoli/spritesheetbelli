extends "res://tests/test_case.gd"

var sheet: Spritesheet
var dir := OS.get_user_data_dir().path_join("tests/export")


func before_each() -> void:
	sheet = Spritesheet.new()
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		imgs.append(make_image(color, Vector2i(4, 4)))
	sheet.add_frames(imgs)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func test_padding_and_spacing() -> void:
	var options := ExportOptions.new()
	options.padding = 2
	options.spacing = 1
	var img := SpritesheetExporter.build_image(sheet, options)
	assert_eq(img.get_size(), Vector2i(2 + 4 * 3 + 1 * 2 + 2, 2 + 4 + 2))
	assert_eq(img.get_pixel(1, 1).a, 0.0, "padding is empty")
	assert_color(img, Vector2i(2, 2), Color.RED)
	assert_eq(img.get_pixel(6, 2).a, 0.0, "spacing is empty")
	assert_color(img, Vector2i(7, 2), Color.GREEN)


func test_extrude_repeats_edges() -> void:
	var options := ExportOptions.new()
	options.extrude = 2
	var img := SpritesheetExporter.build_image(sheet, options)
	assert_eq(img.get_size(), Vector2i((4 + 4) * 3, 4 + 4))
	assert_color(img, Vector2i(0, 0), Color.RED, "corner filled")
	assert_color(img, Vector2i(7, 3), Color.RED, "right edge")
	assert_color(img, Vector2i(8, 3), Color.GREEN, "next frame's left extrusion")
	assert_eq(
		SpritesheetExporter.get_frame_rect(sheet, Vector2i(1, 0), options).position, Vector2i(10, 2)
	)


func test_background() -> void:
	var options := ExportOptions.new()
	options.background = Color.BLACK
	sheet.set_grid_size(Vector2i(4, 1))
	var img := SpritesheetExporter.build_image(sheet, options)
	assert_color(img, Vector2i(13, 1), Color.BLACK, "empty cell filled")


func test_sprite_name_pattern() -> void:
	sheet.set_row_name(0, "walk")
	var name := SpritesheetExporter.format_sprite_name(
		"{row_name}_{frame:2}", sheet, Vector2i(2, 0), 1
	)
	assert_eq(name, "walk_03")
	assert_eq(SpritesheetExporter.format_sprite_name("a/b{index}", sheet, Vector2i(1, 0)), "a_b1")


func test_existing_files_and_selection() -> void:
	var options := ExportOptions.new()
	SpritesheetExporter.export_sprites(sheet, dir, [], 0, options)
	options.existing_files = ExportOptions.Existing.SKIP
	var written := SpritesheetExporter.export_sprites(sheet, dir, [], 0, options)
	assert_eq(written.size(), 0, "skipped")
	options.existing_files = ExportOptions.Existing.OVERWRITE
	written = SpritesheetExporter.export_sprites(
		sheet, dir, [], 0, options, [Vector2i(1, 0)] as Array[Vector2i]
	)
	assert_eq(written, PackedStringArray([dir.path_join("1.png")]), "only the given frames")
	assert_eq(DirAccess.get_files_at(dir).size(), 3)


func test_settings_saved_in_project_and_undoable() -> void:
	var options := ExportOptions.new()
	options.background = Color(0.5, 0.25, 1)
	options.padding = 3
	options.sprite_name_pattern = "{row_name}"
	sheet.set_export_settings(options.to_dictionary())
	var path := dir.path_join("options.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	var back := ExportOptions.from_sheet(loaded)
	assert_eq(back.padding, 3)
	assert_eq(back.background, Color(0.5, 0.25, 1))
	assert_eq(back.sprite_name_pattern, "{row_name}")
