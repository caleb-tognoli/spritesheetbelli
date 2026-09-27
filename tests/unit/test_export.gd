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
	var sprite_name := SpritesheetExporter.format_sprite_name(
		"{row}_{column}_{frame:2}", sheet, Vector2i(2, 0), 1
	)
	assert_eq(sprite_name, "0_2_03")
	assert_eq(SpritesheetExporter.format_sprite_name("a/b{index}", sheet, Vector2i(1, 0)), "a_b1")


func test_animation_tokens() -> void:
	var pattern := "{animation}_{animation_frame:2}"
	assert_eq(
		SpritesheetExporter.format_sprite_name(pattern, sheet, Vector2i(2, 0), 1),
		"frame_03",
		"without an animation, its index"
	)
	sheet.add_animation(
		SheetAnimation.create("walk", [Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i])
	)
	sheet.add_animation(SheetAnimation.create("idle", [Vector2i(1, 0)] as Array[Vector2i]))
	assert_eq(SpritesheetExporter.format_sprite_name(pattern, sheet, Vector2i(2, 0)), "walk_00")
	assert_eq(
		SpritesheetExporter.format_sprite_name(pattern, sheet, Vector2i(1, 0), 1),
		"walk_02",
		"the first animation, counted from the setting"
	)
	assert_eq(SpritesheetExporter.format_sprite_name(pattern, sheet, Vector2i(0, 0)), "frame_00")


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
	options.sprite_name_pattern = "{animation}"
	sheet.set_export_settings(options.to_dictionary())
	var path := dir.path_join("options.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	var back := ExportOptions.from_sheet(loaded)
	assert_eq(back.padding, 3)
	assert_eq(back.background, Color(0.5, 0.25, 1))
	assert_eq(back.sprite_name_pattern, "{animation}")


func test_json_metadata_with_tags() -> void:
	sheet.move_frame(Vector2i(2, 0), Vector2i(0, 1))
	sheet.set_grid_size(Vector2i(2, 2))
	sheet.add_animation(
		SheetAnimation.create("idle", [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	)
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(0, 1)] as Array[Vector2i]))
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
	sheet.add_animation(SheetAnimation.create("run", sheet.get_sorted_coords(), 8))
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


func test_rows_are_not_animations() -> void:
	sheet.move_frame(Vector2i(2, 0), Vector2i(0, 1))
	sheet.set_grid_size(Vector2i(2, 2))
	assert_eq(Metadata.frame_tags(sheet), [] as Array[Dictionary])
	var frames := Metadata.grid_frames(sheet, ExportOptions.new())
	assert_eq(Metadata.animation_frame_names(sheet, frames), {})
	var json: Dictionary = JSON.parse_string(
		Metadata.sheet_json(sheet, frames, "a.png", Vector2i(8, 8), 12)
	)
	assert_eq(json.meta.frameTags, [])
	assert_false(json.meta.has("animations"))
	# SpriteFrames get every frame in one "default" animation, which AnimatedSprite2D plays
	var animations := Metadata.animations(sheet)
	assert_eq(animations.size(), 1)
	assert_eq(animations[0].name, "default")
	assert_eq(animations[0].indices, [0, 1, 2])
	var options := ExportOptions.new()
	options.metadata = ExportOptions.MetadataFormat.GODOT
	var path := dir.path_join("rows.png")
	assert_eq(Metadata.write_for_image(sheet, options, path), OK)
	var text := FileAccess.get_file_as_string(dir.path_join("rows.tres"))
	assert_eq(text.count('"name": &'), 1, text)
	assert_true(text.contains('"name": &"default"'))


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


func test_too_big_images_are_explained() -> void:
	assert_eq(ImageUtils.size_problem(Vector2i(4096, 4096)), "")
	assert_true("WEBP" in ImageUtils.size_problem(Vector2i(20000, 10), "webp"))
	assert_true("million" in ImageUtils.size_problem(Vector2i(20000, 20000)))


func test_export_targets() -> void:
	var options := ExportOptions.new()
	options.apply({"metadata": ExportOptions.MetadataFormat.GODOT})
	assert_eq(options.target, ExportOptions.Target.GODOT, "projects from before targets")
	options.target = ExportOptions.Target.IMAGE
	options.image_format = "webp"
	assert_eq(options.get_file_extension(), "webp")
	assert_eq(options.metadata, ExportOptions.MetadataFormat.NONE)
	options.target = ExportOptions.Target.JSON
	assert_eq(options.get_file_extension(), "png", "JSON goes with a PNG")
	assert_true(options.writes_sheet_image())
	var restored := ExportOptions.new()
	restored.apply(options.to_dictionary())
	assert_eq(restored.target, ExportOptions.Target.JSON)
	assert_eq(restored.image_format, "webp")


func test_animations_in_metadata() -> void:
	var walk := SheetAnimation.create(
		"walk", [Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i], 6
	)
	walk.mode = SheetAnimation.Mode.ONCE
	sheet.add_animation(walk)
	var list := Metadata.animations(sheet)
	assert_eq(list.size(), 1, "no default animation besides it")
	assert_eq(list[0].indices, [2, 0])
	var tres := Metadata.sprite_frames_tres(
		Metadata.grid_frames(sheet, ExportOptions.new()), list, "a.png", 12
	)
	assert_true('"loop": false' in tres, "once doesn't loop")
	assert_true('"speed": 6.0' in tres, "its own speed")
	var tags := Metadata.frame_tags(sheet)
	assert_eq(tags[0].direction, "reverse")
	assert_eq(tags[0].repeat, "1")


func test_typed_extensions_are_stripped() -> void:
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.JSON
	# Typed name: the image and the data file written
	var cases := {
		"hero": ["hero.png", "hero.json"],
		"hero.json": ["hero.png", "hero.json"],
		"hero.png": ["hero.png", "hero.json"],
		"hero.json.png": ["hero.png", "hero.json"],
		"hero.webp": ["hero.png", "hero.json"],
		"hero.v2": ["hero.v2.png", "hero.v2.json"],
		"HERO.PNG": ["HERO.png", "HERO.json"],
		"HERO.JSON": ["HERO.png", "HERO.json"],
	}
	for typed: String in cases:
		var image := SpritesheetExporter.with_extension(
			dir.path_join(typed), options.get_file_extension()
		)
		assert_eq(image.get_file(), cases[typed][0], typed)
		assert_eq(Metadata.get_path_for_image(image, options).get_file(), cases[typed][1], typed)
	options.target = ExportOptions.Target.GODOT
	var godot := SpritesheetExporter.with_extension("hero.tres", options.get_file_extension())
	assert_eq([godot, Metadata.get_path_for_image(godot, options)], ["hero.png", "hero.tres"])
	assert_eq(SpritesheetExporter.strip_written_extensions("a.v2/hero"), "a.v2/hero")
	assert_eq(SpritesheetExporter.format_sprite_name("{index}.PNG", sheet, Vector2i(1, 0)), "1")


func test_the_format_decides_the_extension() -> void:
	var options := ExportOptions.new()
	# Typed name, chosen format: the image written
	var cases := [
		["hero.png", "jpg", "hero.jpg"],
		["hero", "webp", "hero.webp"],
		["hero.v2", "jpg", "hero.v2.jpg"],
		["HERO.PNG", "png", "HERO.png"],
		["hero.jpeg", "jpg", "hero.jpg"],
		["hero.JPG", "webp", "hero.webp"],
		["hero.webp.json", "png", "hero.png"],
	]
	for case: Array in cases:
		options.image_format = case[1]
		var image := SpritesheetExporter.with_extension(case[0], options.get_file_extension())
		assert_eq(image, case[2], "%s as %s" % [case[0], case[1]])
	# On the command line, the name picks the format
	assert_eq(SpritesheetExporter.with_image_extension("hero.JPEG"), "hero.jpg")
	assert_eq(SpritesheetExporter.with_image_extension("hero.WebP"), "hero.webp")
	assert_eq(SpritesheetExporter.with_image_extension("hero.json"), "hero.png")
	assert_eq(SpritesheetExporter.with_image_extension("hero.v2"), "hero.v2.png")


func test_typed_extensions_are_stripped_for_atlases() -> void:
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.ATLAS
	var cases := {
		"hero": ["hero.png", "hero.json"],
		"hero.json": ["hero.png", "hero.json"],
		"hero.png": ["hero.png", "hero.json"],
		"hero.v2": ["hero.v2.png", "hero.v2.json"],
		"HERO.PNG": ["HERO.png", "HERO.json"],
	}
	for typed: String in cases:
		var result := AtlasPacker.write(sheet, options, dir.path_join(typed))
		assert_eq(result.error, OK, typed)
		assert_eq(result.path.get_file(), cases[typed][0], typed)
		assert_eq(result.json_path.get_file(), cases[typed][1], typed)
	options.atlas_data = "sparrow"
	var sparrow := AtlasPacker.write(sheet, options, dir.path_join("hero.xml"))
	assert_eq(sparrow.json_path.get_file(), "hero.xml")

	# Pages are numbered after the stripped name
	sheet.resize_sprites(Vector2i(16, 16))
	var settings := AtlasSettings.new()
	settings.max_size = 16
	sheet.set_atlas_settings(settings)
	options.atlas_data = "json"
	var pages := AtlasPacker.write(sheet, options, dir.path_join("paged.json"))
	assert_eq(pages.pages, 3)
	var files := Array(pages.paths).map(func(path: String) -> String: return path.get_file())
	files.sort()
	assert_eq(
		files,
		[
			"paged_0.json",
			"paged_0.png",
			"paged_1.json",
			"paged_1.png",
			"paged_2.json",
			"paged_2.png"
		]
	)


func test_typed_extensions_are_stripped_for_gifs() -> void:
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.GIF
	for typed: String in ["hero", "hero.json", "hero.png", "HERO.GIF"]:
		var result: Dictionary = await GifEncoder.write(sheet, options, dir.path_join(typed))
		assert_eq(result.error, OK, typed)
		assert_eq(result.path.get_file().to_lower(), "hero.gif", typed)
	var kept: Dictionary = await GifEncoder.write(sheet, options, dir.path_join("hero.v2"))
	assert_eq(kept.path.get_file(), "hero.v2.gif")
