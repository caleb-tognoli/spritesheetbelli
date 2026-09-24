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
	var sprite_name := SpritesheetExporter.format_sprite_name(
		"{row_name}_{frame:2}", sheet, Vector2i(2, 0), 1
	)
	assert_eq(sprite_name, "walk_03")
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


func test_json_metadata_with_tags() -> void:
	sheet.move_frame(Vector2i(2, 0), Vector2i(0, 1))
	sheet.set_grid_size(Vector2i(2, 2))
	sheet.set_row_name(0, "idle")
	sheet.set_row_name(1, "walk")
	var options := ExportOptions.new()
	options.metadata = ExportOptions.MetadataFormat.JSON
	options.spacing = 2
	var path := dir.path_join("meta.png")
	assert_eq(SpritesheetExporter.save_image(sheet.get_image(options), path), OK)
	assert_eq(Metadata.write_for_image(sheet, options, path), OK)
	var json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(dir.path_join("meta.json"))
	)
	assert_eq(json.frames.size(), 3)
	assert_eq(
		json.frames["1.png"].frame, {"x": 6.0, "y": 0.0, "w": 4.0, "h": 4.0}, "spacing applied"
	)
	assert_eq(json.meta.frameTags.size(), 2)
	assert_eq(
		json.meta.frameTags[1], {"name": "walk", "from": 2.0, "to": 2.0, "direction": "forward"}
	)


func test_godot_sprite_frames() -> void:
	sheet.set_row_name(0, "run")
	var options := ExportOptions.new()
	options.metadata = ExportOptions.MetadataFormat.GODOT
	options.animation_fps = 8
	var path := dir.path_join("hero.png")
	assert_eq(Metadata.write_for_image(sheet, options, path), OK)
	var text := FileAccess.get_file_as_string(dir.path_join("hero.tres"))
	assert_true(text.begins_with('[gd_resource type="SpriteFrames"'))
	assert_true(text.contains('path="hero.png"'), "texture next to the resource")
	assert_true(text.contains("region = Rect2(8, 0, 4, 4)"))
	assert_true(text.contains('"name": &"run"'))
	assert_true(text.contains('"speed": 8.0'))
	# The resource must be valid for Godot's parser
	var copy := "res://_metadata_check.tres"
	var file := FileAccess.open(copy, FileAccess.WRITE)
	file.store_string(text.replace('path="hero.png"', 'path="res://icon.svg"'))
	file.close()
	var frames: SpriteFrames = ResourceLoader.load(copy, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy))
	assert_true(frames != null, "loads as SpriteFrames")
	if frames:
		assert_eq(frames.get_frame_count(&"run"), 3)
		assert_eq(frames.get_animation_speed(&"run"), 8.0)


func test_default_animation_without_row_names() -> void:
	var animations := Metadata.animations(sheet)
	assert_eq(animations.size(), 1)
	assert_eq(animations[0].name, "default")
	assert_eq(animations[0].indices, [0, 1, 2])


func test_projects_with_one_file_per_frame_still_open() -> void:
	var path := dir.path_join("legacy.sbelli")
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("frames/1_0.png")
	zip.write_file(make_image(Color.BLUE, Vector2i(6, 6)).save_png_to_buffer())
	zip.close_file()
	zip.start_file("project.json")
	var data := {
		"format": "spritesheetbelli",
		"version": 1,
		"grid_size": [2, 1],
		"frames": [{"cell": [1, 0], "file": "frames/1_0.png"}],
	}
	zip.write_file(JSON.stringify(data).to_utf8_buffer())
	zip.close_file()
	zip.close()
	var loaded := ProjectFile.load(path)
	assert_false(loaded.has("error"), str(loaded.get("error")))
	assert_color(loaded.state.frames[Vector2i(1, 0)], Vector2i.ZERO, Color.BLUE)
