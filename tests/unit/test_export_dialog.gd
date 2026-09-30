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
	assert_true(await main.files.exports.export_to(path), case)
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
	await export_and_compare(
		"godot",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.DATA
			o.grid_data = "godot"
	)
	await export_and_compare("json", target.call(ExportOptions.Target.DATA), "hero.json")
	await export_and_compare("gif", target.call(ExportOptions.Target.GIF))
	await export_and_compare(
		"gifs",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.GIF
			o.gif_every_animation = true,
		"out"
	)
	await export_and_compare("strips", target.call(ExportOptions.Target.STRIPS), "out")
	await export_and_compare(
		"strip scales",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.STRIPS
			o.scales = "1, 2",
		"out"
	)
	await export_and_compare(
		"scales",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.DATA
			o.grid_data = "godot"
			o.scales = "1, 2, 3"
	)
	await export_and_compare(
		"atlas scales",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.ATLAS
			o.scales = "1, 2"
	)
	# Pages, each with a data file, numbered before the suffix: hero_0@2x.json
	var before := sheet.atlas_settings
	var small := sheet.atlas_settings
	small.max_size = 64
	sheet.set_atlas_settings(small)
	await export_and_compare(
		"atlas page scales",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.ATLAS
			o.atlas_data = "json"
			o.scales = "1, 2"
	)
	assert_true(FileAccess.file_exists(dir.path_join("atlas page scales/hero_1@2x.json")))
	sheet.set_atlas_settings(before)
	set_options(func(o: ExportOptions) -> void: o.scales = "1")
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
	dialog.select_type(ExportOptions.Target.IMAGE)
	assert_false(dialog.files_info.visible, "one file")
	dialog.select_type(ExportOptions.Target.DATA)
	assert_true(dialog.files_info.visible)
	assert_eq(dialog.files_info.text, "Files: spritesheet.png, spritesheet.json")
	dialog.select_type(ExportOptions.Target.ATLAS)
	assert_eq(dialog.files_info.text, "Files: spritesheet_atlas.png, spritesheet_atlas.json")
	dialog.select_type(ExportOptions.Target.GIF)
	assert_false(dialog.files_info.visible)

	var images: Array[Image] = []
	for i in 7:
		images.append(make_image(Color.WHITE))
	sheet.add_frames(images)
	dialog.refresh()
	dialog.select_type(ExportOptions.Target.SPRITES)
	assert_eq(dialog.files_info.text, "Files: 0.png, 1.png, 2.png, 3.png … 6 more")
	assert_false(dialog.pattern_example.visible, "the files show the names")
	dialog.only_selected.button_pressed = true
	dialog.get_selected_coords = func() -> Array[Vector2i]: return [Vector2i(2, 0)]
	dialog.only_selected.toggled.emit(true)
	assert_eq(dialog.files_info.text, "Files: 2.png")
	assert_false(dialog.files_info.visible, "one file")
	assert_true(dialog.output_info.text.begins_with("1 image of"), dialog.output_info.text)


func test_tokens_list_and_insert() -> void:
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(2, 0)] as Array[Vector2i]))
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.DATA)
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
	dialog.select_type(ExportOptions.Target.DATA)
	assert_eq(dialog.pattern.text, "{animation}_{animation_frame}", "the default with animations")
	assert_eq(dialog.pattern_example.text, "For example: run_1.png, run_0.png, frame_0.png")


func test_default_name_pattern_follows_the_sheet() -> void:
	assert_eq(ExportOptions.from_sheet(sheet).sprite_name_pattern, "{index}")
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(0, 0)] as Array[Vector2i]))
	var options := ExportOptions.from_sheet(sheet)
	assert_eq(options.sprite_name_pattern, "{animation}_{animation_frame}")
	assert_false(options.to_dictionary().has("sprite_name_pattern"), "a default, not stored")

	# Closing without changing it keeps it a default
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.SPRITES)
	assert_eq(dialog.pattern.line_edit.placeholder_text, "{animation}_{animation_frame}")
	dialog.hide()
	var stored := func() -> Dictionary: return ExportTarget.list(sheet)[0].to_dictionary()
	assert_eq(stored.call().target, ExportOptions.Target.SPRITES)
	assert_false(stored.call().has("sprite_name_pattern"))

	# A pattern that's set is kept, also when it's the default without animations
	options.sprite_name_pattern = "{index}"
	sheet.set_export_settings(options.to_dictionary())
	var round_trip := ExportOptions.new()
	round_trip.apply(sheet.export_settings)
	assert_eq(round_trip.to_dictionary().sprite_name_pattern, "{index}")
	assert_eq(ExportOptions.from_sheet(sheet).sprite_name_pattern, "{index}")
	var target := ExportTarget.create(sheet, {"sprite_name_pattern": "{index}"})
	sheet.set_export_settings(ExportTarget.settings_with(sheet, [target]))
	assert_eq(stored.call().sprite_name_pattern, "{index}")
	Actions.run(&"export")
	assert_eq(dialog.pattern.text, "{index}")
	dialog.only_selected.toggled.emit(false)
	dialog.hide()
	assert_eq(stored.call().sprite_name_pattern, "{index}", "still set")
	Actions.run(&"export")
	dialog.pattern.text = ""
	dialog.pattern.text_changed.emit("")
	dialog.hide()
	assert_false(stored.call().has("sprite_name_pattern"), "emptied: the default")


func test_transparent_background_says_so() -> void:
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.IMAGE)
	assert_true(dialog.transparent_label.visible)
	assert_eq(dialog.transparent_label.text, "Transparent")
	dialog.background_picker.color = Color.RED
	dialog.background_picker.color_changed.emit(Color.RED)
	assert_false(dialog.transparent_label.visible)


func test_opens_on_the_export_last_selected() -> void:
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.IMAGE)
	dialog.add()
	dialog.select_type(ExportOptions.Target.GIF)
	dialog.hide()
	Actions.run(&"export")
	assert_eq(dialog.target_list.item_count, 2)
	assert_eq(dialog.get_options().target, ExportOptions.Target.GIF)
	dialog.select(0)
	dialog.hide()
	Actions.run(&"export")
	assert_eq(dialog.get_options().target, ExportOptions.Target.IMAGE)


## Writes a template file of the user's own in the test's folder
func write_template(file_name: String, text: String) -> String:
	var path := dir.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


## Picks [param path] in the dialog's template field, as typing it does
func pick_template(path: String) -> void:
	dialog.template_file.line_edit.text = path
	dialog.template_file.line_edit.text_changed.emit(path)


func test_custom_template() -> void:
	var names := write_template(
		"names.template",
		"{{! name: Names\nextension: txt\nlayouts: grid\n}}\n{{#frames}}{{name}} {{x}}\n{{/frames}}"
	)
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.CUSTOM)
	assert_true(dialog.template_file.visible)
	assert_false(dialog.grid_data.visible, "its own template, not a list")
	assert_eq(dialog.template_error.text, "Pick a template file.")
	assert_true(dialog.get_ok_button().disabled)
	pick_template(names)
	assert_false(dialog.template_error.visible)
	assert_false(dialog.get_ok_button().disabled)
	assert_eq(dialog.files_info.text, "Files: spritesheet.png, spritesheet.txt")
	assert_true(dialog.pattern.visible, "like an image and data file")
	assert_false(dialog.frame_size.visible)
	dialog.hide()
	assert_eq(ExportTarget.list(sheet)[0].options.custom_template, names, "remembered")
	await export_and_compare(
		"custom",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.CUSTOM
			o.custom_template = names
	)
	var text := FileAccess.get_file_as_string(dir.path_join("custom/hero.txt"))
	assert_eq(text, "0 0\n1 40\n2 80\n")

	# A template only for atlases packs the sheet, with a file per page
	var pages := write_template(
		"pages.template",
		"{{! extension: pg\nper_page: true\nlayouts: packed\n}}\n{{image}}{{#frames}} {{name}}{{/frames}}"
	)
	var settings := sheet.atlas_settings
	settings.max_size = 64
	sheet.set_atlas_settings(settings)
	Actions.run(&"export")
	pick_template(pages)
	assert_true(dialog.frame_size.visible, "like a packed atlas")
	assert_true(
		dialog.files_info.text.begins_with("Files: hero_0.png, hero_1.png"), dialog.files_info.text
	)
	await export_and_compare(
		"custom_pages", func(o: ExportOptions) -> void: o.custom_template = pages
	)
	assert_eq(files_in(dir.path_join("custom_pages")).size(), 6, "3 pages and 3 data files")
	var page := FileAccess.get_file_as_string(dir.path_join("custom_pages/hero_1.pg"))
	assert_eq(page, "hero_1.png 1")
	dialog.hide()


func test_template_errors_stop_the_export() -> void:
	var broken := write_template("broken.template", "{{#frames}}\n{{name | pad}}\n{{/frames}}")
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.CUSTOM)
	pick_template(broken)
	assert_true(dialog.template_error.visible)
	assert_eq(dialog.template_error.text, "broken.template: line 2: pad takes 1 argument, not 0")
	assert_true(dialog.get_ok_button().disabled)
	pick_template(dir.path_join("nowhere.template"))
	assert_true(dialog.template_error.text.begins_with("Could not find"), "a file that isn't there")
	dialog.hide()

	# Exporting again with a template broken since
	set_options(
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.CUSTOM
			o.custom_template = broken
	)
	assert_false(await main.files.exports.export_to(dir.path_join("broken.png")))
	assert_true(Notify.message_dialog.visible, "says why")
	assert_true("line 2" in Notify.message_dialog.dialog_text, Notify.message_dialog.dialog_text)
	Notify.message_dialog.hide()
	assert_false(FileAccess.file_exists(dir.path_join("broken.png")), "nothing written")


func test_data_formats_list_the_users_templates() -> void:
	DirAccess.make_dir_recursive_absolute(AtlasFormats.user_dir)
	var tiles := AtlasFormats.user_dir.path_join("tiles.template")
	var file := FileAccess.open(tiles, FileAccess.WRITE)
	file.store_string("{{! name: Tiles\nextension: tiles\nlayouts: grid\n}}\n{{frame_count}}")
	file.close()
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.DATA)
	var listed := func(button: OptionButton) -> Array:
		return range(button.item_count).map(button.get_item_metadata)
	assert_eq(listed.call(dialog.grid_data)[-1], "tiles", "after a separator")
	assert_true(dialog.grid_data.is_item_separator(dialog.grid_data.item_count - 2))
	assert_false("tiles" in listed.call(dialog.atlas_data), "for grids only")
	assert_true(dialog.templates_folder.visible)
	dialog.grid_data.select(dialog.grid_data.item_count - 1)
	dialog.grid_data.item_selected.emit(dialog.grid_data.selected)
	assert_eq(dialog.files_info.text, "Files: spritesheet.png, spritesheet.tiles")
	dialog.hide()
	await export_and_compare(
		"user",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.DATA
			o.grid_data = "tiles"
	)
	assert_eq(FileAccess.get_file_as_string(dir.path_join("user/hero.tiles")), "3")
	DirAccess.remove_absolute(tiles)
	AtlasFormats.refresh()


## A template of the user's with a bundled one's id is listed with the user's, marked as
## theirs, and exported with, until it's taken out
func test_the_users_template_replaces_a_bundled_one() -> void:
	DirAccess.make_dir_recursive_absolute(AtlasFormats.user_dir)
	var json := AtlasFormats.user_dir.path_join("json.template")
	var file := FileAccess.open(json, FileAccess.WRITE)
	file.store_string("{{! name: TexturePacker JSON (hash)\nextension: json\n}}\nmine")
	file.close()
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.DATA)
	var button := dialog.grid_data
	var names := range(button.item_count).map(button.get_item_text)
	var ids := range(button.item_count).map(button.get_item_metadata)
	assert_eq(ids.count("json"), 1, "listed once")
	var at := ids.find("json")
	assert_eq(names[at], "TexturePacker JSON (hash) (yours)")
	assert_true(button.is_item_separator(at - 1), "after a separator")
	assert_true(
		dialog.atlas_data.get_item_text(dialog.atlas_data.item_count - 1).ends_with(" (yours)")
	)
	button.select(at)
	button.item_selected.emit(at)
	assert_eq(dialog.files_info.text, "Files: spritesheet.png, spritesheet.json")
	dialog.hide()
	assert_eq(ExportTarget.list(sheet)[0].options.grid_data, "json", "picked by its id")
	await export_and_compare(
		"replaced",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.DATA
			o.grid_data = "json"
	)
	assert_eq(FileAccess.get_file_as_string(dir.path_join("replaced/hero.json")), "mine")
	# Taken out, the bundled one is back once the dialog looks again
	DirAccess.remove_absolute(json)
	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.DATA)
	names = range(button.item_count).map(button.get_item_text)
	assert_true("TexturePacker JSON (hash)" in names, str(names))
	assert_false(names.any(func(n: String) -> bool: return n.ends_with(" (yours)")), str(names))
	assert_eq(range(button.item_count).filter(button.is_item_separator), [], "no user's")
	dialog.hide()
	await export_and_compare(
		"bundled",
		func(o: ExportOptions) -> void:
			o.target = ExportOptions.Target.DATA
			o.grid_data = "json"
	)
	var text := FileAccess.get_file_as_string(dir.path_join("bundled/hero.json"))
	assert_true(text.begins_with("{"), text)
