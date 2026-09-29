extends "res://tests/test_case.gd"

var main: Control
var dir := temp_path("export_dialog")
var sheet: Spritesheet
var dialog: ExportDialog


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		images.append(make_image(color, Vector2i(40, 40)))
	sheet.add_frames(images)
	dialog = main.export_dialog


func after_each() -> void:
	dialog.hide()
	main.queue_free()
	Global.document.reset()


## Sets the sheet's export settings with [param change] made to them
func set_options(change: Callable) -> void:
	var options := ExportOptions.from_sheet(sheet)
	change.call(options)
	var settings := options.to_dictionary()
	settings.target = options.target
	sheet.set_export_settings(settings)


## The files [method FileController.export_to] writes to [param path] in a folder of its
## own, next to what [method ExportFiles.get_paths] says it writes
func export_and_compare(case: String, change: Callable, file_name := "hero.png") -> void:
	set_options(change)
	var folder := dir.path_join(case)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(file_name)
	var options := ExportOptions.from_sheet(sheet)
	var index_start: int = Settings.get_value(&"index_start")
	var expected := ExportFiles.get_paths(sheet, options, path, [], index_start, true)
	var before := Array(files_in(folder))
	assert_true(await main.files.export_to(path), case)
	var written := Array(files_in(folder)).filter(func(f: String) -> bool: return f not in before)
	var names := Array(expected).map(func(p: String) -> String: return p.trim_prefix(folder + "/"))
	written.sort()
	names.sort()
	assert_eq(written, names, case)
	Notify.message_dialog.hide()


func files_in(folder: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		files.append(file)
	for sub in DirAccess.get_directories_at(folder):
		for file in DirAccess.get_files_at(folder.path_join(sub)):
			files.append(sub.path_join(file))
	return files


func test_files_listed_are_the_files_written() -> void:
	sheet.add_animation(
		SheetAnimation.create("walk", [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	)
	var target := func(t: ExportOptions.Target) -> Callable:
		return func(o: ExportOptions) -> void: o.target = t
	await export_and_compare("image", target.call(ExportOptions.Target.IMAGE))
	await export_and_compare(
		"jpg",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.IMAGE
			o.image_format = "jpg",
		"hero"
	)
	await export_and_compare("godot", target.call(ExportOptions.Target.GODOT))
	await export_and_compare("json", target.call(ExportOptions.Target.JSON), "hero.json")
	await export_and_compare("gif", target.call(ExportOptions.Target.GIF))
	await export_and_compare("atlas", target.call(ExportOptions.Target.ATLAS))

	# Sprites: names taken by a file already there or by a frame before are numbered
	var sprites := dir.path_join("sprites/out")
	DirAccess.make_dir_recursive_absolute(sprites)
	make_image(Color.WHITE).save_png(sprites.path_join("frame.png"))
	var by_animation := func(o: ExportOptions) -> void:
		o.target = ExportOptions.Target.SPRITES
		o.sprite_name_pattern = "{animation}"
	await export_and_compare("sprites", by_animation, "out")
	assert_true(FileAccess.file_exists(sprites.path_join("walk(1).png")))
	assert_true(FileAccess.file_exists(sprites.path_join("frame(1).png")))
	var skip := func(o: ExportOptions) -> void:
		o.target = ExportOptions.Target.SPRITES
		o.sprite_name_pattern = "{index}"
		o.existing_files = ExportOptions.Existing.SKIP
	DirAccess.make_dir_recursive_absolute(dir.path_join("skip/out"))
	make_image(Color.WHITE).save_png(dir.path_join("skip/out/1.png"))
	await export_and_compare("skip", skip, "out")

	# Several pages, with a data file for each or one for all
	var settings := sheet.atlas_settings
	settings.max_size = 64
	sheet.set_atlas_settings(settings)
	await export_and_compare("pages", target.call(ExportOptions.Target.ATLAS))
	assert_eq(files_in(dir.path_join("pages")).size(), 6, "3 pages and 3 data files")
	await export_and_compare(
		"phaser",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.ATLAS
			o.atlas_data = "phaser"
	)
	assert_eq(files_in(dir.path_join("phaser")).size(), 4, "3 pages and one data file")
	sheet.set_layout(Spritesheet.Layout.PACKED)
	await export_and_compare("packed_pages", target.call(ExportOptions.Target.IMAGE))
	assert_eq(files_in(dir.path_join("packed_pages")).size(), 3)
	await export_and_compare(
		"packed_atlas",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.ATLAS
			o.atlas_data = "sparrow"
	)


func test_dialog_lists_the_files_of_an_export() -> void:
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.IMAGE)
	assert_false(dialog.files_info.visible, "one file")
	dialog.select_target(ExportOptions.Target.JSON)
	assert_true(dialog.files_info.visible)
	assert_eq(dialog.files_info.text, "Files: spritesheet.png, spritesheet.json")
	dialog.select_target(ExportOptions.Target.ATLAS)
	assert_eq(dialog.files_info.text, "Files: spritesheet_atlas.png, spritesheet_atlas.json")
	dialog.select_target(ExportOptions.Target.GIF)
	assert_false(dialog.files_info.visible)

	var images: Array[Image] = []
	for i in 7:
		images.append(make_image(Color.WHITE))
	sheet.add_frames(images)
	dialog.refresh()
	dialog.select_target(ExportOptions.Target.SPRITES)
	assert_eq(dialog.files_info.text, "Files: 0.png, 1.png, 2.png, 3.png … 6 more")
	assert_false(dialog.pattern_example.visible, "the files show the names")
	dialog.only_selected.button_pressed = true
	dialog.get_selected_coords = func() -> Array[Vector2i]: return [Vector2i(2, 0)]
	dialog.only_selected.toggled.emit(true)
	assert_eq(dialog.files_info.text, "Files: 2.png")
	assert_false(dialog.files_info.visible, "one file")
	assert_true(dialog.output_info.text.begins_with("1 images"), dialog.output_info.text)


func test_tokens_list_and_insert() -> void:
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(2, 0)] as Array[Vector2i]))
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.JSON)
	var field := dialog.pattern
	field.text = "hero_"
	field.line_edit.caret_column = 5
	field.tokens_button.pressed.emit()
	assert_true(field.popup.visible)
	var cells := field.tokens.get_children()
	assert_eq(cells.size(), SpritesheetExporter.SPRITE_NAME_TOKENS.size() * 3)
	var tokens := cells.filter(func(c: Node) -> bool: return c is Button)
	var animation: Button = tokens[SpritesheetExporter.SPRITE_NAME_TOKENS.keys().find("animation")]
	assert_eq(animation.text, "{animation}")
	var example: Label = cells[cells.find(animation) + 2]
	assert_eq(example.text, "walk", "from the frame in an animation")
	animation.pressed.emit()
	assert_false(field.popup.visible)
	assert_eq(field.text, "hero_{animation}", "at the caret")
	assert_true(dialog.pattern_example.text.begins_with("For example: hero_walk.png"))

	field.line_edit.select(5, 16)
	field.insert_token("index")
	assert_eq(field.text, "hero_{index}", "in place of the selection")
	assert_false(field.warning.visible)
	field.line_edit.text = "{anim}_{index:}_{row:2}"
	field.line_edit.text_changed.emit(field.line_edit.text)
	assert_true(field.warning.visible)
	assert_eq(field.warning.text, "Unknown tokens: {anim}, {index:}")


func test_unknown_tokens() -> void:
	assert_eq(SpritesheetExporter.get_unknown_tokens("{index:3}_{name}"), PackedStringArray())
	assert_eq(
		SpritesheetExporter.get_unknown_tokens("{Index}{x}{x}{ row }"),
		PackedStringArray(["{Index}", "{x}", "{ row }"])
	)
	var named := SpritesheetExporter.format_sprite_name("{anim}_{index}", sheet, Vector2i(1, 0))
	assert_eq(named, "{anim}_1", "kept as it is")


func test_examples_prefer_frames_in_animations() -> void:
	var images: Array[Image] = [make_image(Color.WHITE)]
	sheet.add_frames(images)
	sheet.add_animation(
		SheetAnimation.create("run", [Vector2i(3, 0), Vector2i(1, 0)] as Array[Vector2i])
	)
	assert_eq(
		SpritesheetExporter.get_example_coords(sheet),
		[Vector2i(1, 0), Vector2i(3, 0), Vector2i(0, 0)] as Array[Vector2i]
	)
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.JSON)
	assert_eq(dialog.pattern.text, "{animation}_{animation_frame}", "the default with animations")
	assert_eq(dialog.pattern_example.text, "For example: run_1.png, run_0.png, frame_0.png")


func test_default_name_pattern_follows_the_sheet() -> void:
	assert_eq(ExportOptions.from_sheet(sheet).sprite_name_pattern, "{index}")
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(0, 0)] as Array[Vector2i]))
	var options := ExportOptions.from_sheet(sheet)
	assert_eq(options.sprite_name_pattern, "{animation}_{animation_frame}")
	assert_false(options.to_dictionary().has("sprite_name_pattern"), "a default, not stored")

	# Confirming without changing it keeps it a default
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.SPRITES)
	assert_eq(dialog.pattern.line_edit.placeholder_text, "{animation}_{animation_frame}")
	dialog.get_ok_button().pressed.emit()
	main.files.save_sprites_dialog.hide()
	main.files.open_file_dialogs.clear()
	assert_false(sheet.export_settings.has("sprite_name_pattern"))

	# A pattern that's set is kept, also when it's the default without animations
	options.sprite_name_pattern = "{index}"
	sheet.set_export_settings(options.to_dictionary())
	var round_trip := ExportOptions.new()
	round_trip.apply(sheet.export_settings)
	assert_eq(round_trip.to_dictionary().sprite_name_pattern, "{index}")
	assert_eq(ExportOptions.from_sheet(sheet).sprite_name_pattern, "{index}")
	Actions.run(&"export")
	dialog.pattern.text = ""
	dialog.get_ok_button().pressed.emit()
	main.files.save_sprites_dialog.hide()
	main.files.open_file_dialogs.clear()
	assert_false(sheet.export_settings.has("sprite_name_pattern"), "emptied: the default")


func test_transparent_background_says_so() -> void:
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.IMAGE)
	assert_true(dialog.transparent_label.visible)
	assert_eq(dialog.transparent_label.text, "Transparent")
	dialog.background_picker.color = Color.RED
	dialog.background_picker.color_changed.emit(Color.RED)
	assert_false(dialog.transparent_label.visible)


func test_opens_on_the_export_last_used_in_the_project() -> void:
	Actions.run(&"export")
	dialog.select_target(ExportOptions.Target.IMAGE)
	dialog.image_format.select(ExportOptions.IMAGE_FORMATS.find("webp"))
	dialog.image_format.item_selected.emit(dialog.image_format.selected)
	dialog.get_ok_button().pressed.emit()
	main.files.export_file_dialog.hide()
	main.files.open_file_dialogs.clear()
	var path := dir.path_join("last_used")
	assert_true(await main.files.save_project(path))
	Notify.message_dialog.hide()

	Global.document.reset()
	assert_eq(ExportOptions.from_sheet(Global.spritesheet).image_format, "png", "a new project")
	assert_true(await main.files.open_project(path + ".sbelli"))
	Actions.run(&"export")
	assert_eq(dialog.get_options().target, ExportOptions.Target.IMAGE)
	assert_eq(dialog.get_options().image_format, "webp")
	dialog.select_target(ExportOptions.Target.GIF)
	dialog.get_ok_button().pressed.emit()
	main.files.export_file_dialog.hide()
	main.files.open_file_dialogs.clear()
	Actions.run(&"export")
	assert_eq(dialog.get_options().target, ExportOptions.Target.GIF)
