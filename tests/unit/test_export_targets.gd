extends "res://tests/test_case.gd"

var main: Control
var dir := temp_path("export_targets")
var sheet: Spritesheet
var dialog: ExportDialog


func before_each() -> void:
	remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		images.append(make_image(color, Vector2i(8, 8)))
	sheet.add_frames(images)
	dialog = main.export_dialog


func after_each() -> void:
	ExportController.in_browser = WebFiles.is_web()
	dialog.hide()
	Notify.message_dialog.hide()
	main.queue_free()
	Global.document.reset()


## A target of the sheet of [param type] writing to [param file] in the test's folder
func make_target(type: ExportOptions.Target, file: String, settings := {}) -> ExportTarget:
	var target := ExportTarget.create(sheet, settings)
	target.options.target = type
	target.path = dir.path_join(file) if file else ""
	return target


func set_targets(targets: Array[ExportTarget]) -> void:
	Global.document.perform(
		"Export targets", sheet.set_export_settings.bind(ExportTarget.settings_with(sheet, targets))
	)


## Types a path in the dialog's field for where the selected target writes
func type_path(path: String) -> void:
	dialog.output.line_edit.text = path
	dialog.output.line_edit.text_changed.emit(path)


func test_targets_are_saved_with_the_project_relative_to_it() -> void:
	var steps := Global.document.get_history().size()
	Actions.run(&"export")
	dialog.image_format.select(ExportOptions.IMAGE_FORMATS.find("webp"))
	dialog.image_format.item_selected.emit(dialog.image_format.selected)
	var image := dir.path_join("out/hero.webp")
	type_path(image)
	dialog.add()
	dialog.select_type(ExportOptions.Target.GIF)
	dialog.hide()
	assert_true(Global.document.is_dirty, "a change to save")
	assert_eq(Global.document.get_history().size(), steps, "not an undo step")
	assert_eq(ExportTarget.list(sheet)[0].path, image, "absolute while unsaved")
	assert_eq(main.export_btn.text, "Export… (2)")

	var project := dir.path_join("projects/hero.sbelli")
	DirAccess.make_dir_recursive_absolute(project.get_base_dir())
	assert_true(await main.files.save_project(project))
	assert_false(Global.document.is_dirty)
	var zip := ZIPReader.new()
	zip.open(project)
	var data: Dictionary = JSON.parse_string(zip.read_file("project.json").get_string_from_utf8())
	zip.close()
	var saved: Dictionary = JSON.to_native(data.export)
	assert_eq(saved.targets[0].path, "../out/hero.webp", "relative to the project")
	assert_false(saved.targets[1].has("path"), "none picked")

	Global.document.reset()
	assert_true(ExportTarget.list(sheet).is_empty())
	assert_eq(main.export_btn.text, "Export…")
	assert_true(await main.files.open_project(project))
	var targets := ExportTarget.list(sheet)
	assert_eq(targets.size(), 2)
	assert_eq(targets[0].path, image, "absolute again")
	assert_eq(targets[0].options.image_format, "webp")
	assert_eq(targets[1].options.target, ExportOptions.Target.GIF)
	assert_eq(targets[1].path, "")
	assert_false(Global.document.is_dirty)

	# Moved with its exports: they're written next to it again
	var moved := dir.path_join("moved/projects/hero.sbelli")
	DirAccess.make_dir_recursive_absolute(moved.get_base_dir())
	DirAccess.copy_absolute(project, moved)
	var loaded := ProjectFile.load(moved)
	var moved_target := ExportTarget.create(sheet, loaded.state.export.targets[0])
	assert_eq(moved_target.path, dir.path_join("moved/out/hero.webp"))


func test_a_new_target_is_kept_once_changed() -> void:
	Actions.run(&"export")
	assert_eq(dialog.target_list.item_count, 1, "a new one")
	assert_true(dialog.remove_target.disabled, "nothing to remove")
	assert_true(dialog.export_all.disabled, "one to export")
	dialog.hide()
	assert_true(ExportTarget.list(sheet).is_empty(), "not kept untouched")
	assert_false(Global.document.is_dirty)

	Actions.run(&"export")
	dialog.select_type(ExportOptions.Target.SPRITES)
	assert_eq(dialog.target_list.get_item_text(0), "No file picked yet · Sprites")
	dialog.hide()
	assert_eq(ExportTarget.list(sheet).size(), 1, "changed: kept")

	Actions.run(&"export")
	dialog.duplicate_selected()
	assert_eq(dialog.target_list.item_count, 2)
	assert_false(dialog.export_all.disabled)
	dialog.remove_selected()
	dialog.remove_selected()
	assert_eq(dialog.target_list.item_count, 1, "a new one in place of the last")
	dialog.hide()
	assert_true(ExportTarget.list(sheet).is_empty(), "every one removed")


func test_changing_the_format_changes_the_extension() -> void:
	set_targets([make_target(ExportOptions.Target.IMAGE, "hero.png")])
	Actions.run(&"export")
	assert_eq(dialog.output.path, dir.path_join("hero.png"))
	assert_eq(dialog.target_list.get_item_text(0), "hero.png · PNG")
	dialog.image_format.select(ExportOptions.IMAGE_FORMATS.find("jpg"))
	dialog.image_format.item_selected.emit(dialog.image_format.selected)
	assert_eq(dialog.output.path, dir.path_join("hero.jpg"))
	dialog.select_type(ExportOptions.Target.SPRITES)
	assert_eq(dialog.output.path, dir.path_join("hero"), "a folder")
	dialog.select_type(ExportOptions.Target.GIF)
	assert_eq(dialog.output.path, dir.path_join("hero.gif"))
	dialog.select_type(ExportOptions.Target.DATA)
	assert_eq(dialog.files_info.text, "Files: hero.png, hero.json", "named after it")
	type_path(dir.path_join("typed"))
	assert_eq(dialog.output.path, dir.path_join("typed"), "as typed")
	assert_eq(dialog.files_info.text, "Files: typed.png, typed.json")

	assert_eq(ExportTarget.fit_path("a/hero.data.png", options_of("webp")), "a/hero.data.webp")
	assert_eq(ExportTarget.fit_path("a/hero.json", options_of("png")), "a/hero.json.png")
	assert_eq(ExportTarget.fit_path("a/HERO.JPEG", options_of("jpg")), "a/HERO.JPEG")
	assert_eq(ExportTarget.fit_path("", options_of("png")), "")


func options_of(format: String) -> ExportOptions:
	var options := ExportOptions.new()
	options.image_format = format
	return options


func test_export_all_writes_every_target() -> void:
	sheet.add_animation(SheetAnimation.create("walk", sheet.get_sorted_coords()))
	set_targets(
		[
			make_target(ExportOptions.Target.IMAGE, "all/hero.png"),
			make_target(ExportOptions.Target.DATA, "all/data.png", {"grid_data": "godot"}),
			make_target(ExportOptions.Target.ATLAS, "all/atlas.png"),
			make_target(ExportOptions.Target.SPRITES, "all/sprites"),
			make_target(ExportOptions.Target.GIF, "all/walk.gif", {"gif_animation": "walk"}),
		]
	)
	DirAccess.make_dir_recursive_absolute(dir.path_join("all"))
	Actions.run(&"export")
	assert_eq(dialog.target_list.item_count, 5)
	assert_false(dialog.export_all.disabled)
	dialog.custom_action.emit(ExportDialog.EXPORT_ALL)
	for i in 5:
		await get_tree().process_frame
	assert_false(dialog.visible)
	for file: String in [
		"hero.png",
		"data.png",
		"data.tres",
		"atlas.png",
		"atlas.json",
		"walk.gif",
		"sprites/walk_0.png"
	]:
		assert_true(FileAccess.file_exists(dir.path_join("all").path_join(file)), file)
	assert_false(Notify.message_dialog.visible, Notify.message_dialog.dialog_text)
	var toasts := "\n".join(Notify.get_toasts())
	assert_true("Exported hero.png in all." in toasts, toasts)
	assert_true("Saved 3 images to sprites." in toasts, toasts)
	assert_true("Exported walk.gif (3 frames)." in toasts, toasts)


func test_export_writes_the_selected_target() -> void:
	set_targets(
		[
			make_target(ExportOptions.Target.IMAGE, "one.png"),
			make_target(ExportOptions.Target.IMAGE, "two.png"),
		]
	)
	Actions.run(&"export")
	dialog.select(1)
	dialog.get_ok_button().pressed.emit()
	await get_tree().process_frame
	assert_false(dialog.visible)
	assert_false(FileAccess.file_exists(dir.path_join("one.png")))
	assert_true(FileAccess.file_exists(dir.path_join("two.png")))


func test_export_again() -> void:
	Global.document.reset()
	assert_false(Actions.is_enabled(&"export_again"), "nothing to export")
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	await get_tree().process_frame
	assert_true(Actions.is_enabled(&"export_again"))

	# Without targets: the dialog, to set one up
	Actions.run(&"export_again")
	await get_tree().process_frame
	assert_true(dialog.visible)
	dialog.hide()
	set_targets([make_target(ExportOptions.Target.GIF, "")])
	Actions.run(&"export_again")
	await get_tree().process_frame
	assert_true(dialog.visible, "none knows where to write")
	dialog.hide()

	# Every target, one without a file said to need one
	set_targets(
		[
			make_target(ExportOptions.Target.IMAGE, "again.png"),
			make_target(ExportOptions.Target.GIF, "again.png"),
			make_target(ExportOptions.Target.ATLAS, ""),
		]
	)
	assert_false(await main.files.exports.export_again())
	assert_false(dialog.visible)
	assert_true(FileAccess.file_exists(dir.path_join("again.png")))
	assert_true(FileAccess.file_exists(dir.path_join("again.gif")), "its own extension")
	assert_true(Notify.message_dialog.visible)
	assert_eq(
		Notify.message_dialog.dialog_text, "Pick where to export TexturePacker JSON (hash) atlas."
	)
	Notify.message_dialog.hide()

	DirAccess.remove_absolute(dir.path_join("again.png"))
	var targets := ExportTarget.list(sheet)
	targets.pop_back()
	set_targets(targets)
	assert_true(await main.files.exports.export_again())
	assert_true(FileAccess.file_exists(dir.path_join("again.png")), "written again")
	assert_false(Notify.message_dialog.visible)


func test_in_a_browser_targets_are_downloaded() -> void:
	ExportController.in_browser = true
	Actions.run(&"export")
	assert_false(dialog.output.visible, "no path to pick")
	assert_eq(dialog.target_list.get_item_text(0), "spritesheet.png · PNG")
	dialog.select_type(ExportOptions.Target.GIF)
	assert_eq(dialog.target_list.get_item_text(0), "spritesheet.gif · GIF")
	dialog.get_ok_button().pressed.emit()
	await get_tree().process_frame
	assert_false(dialog.visible, "exported without asking where")
	assert_false(dialog.output.file_dialog.visible)
	var written := WebFiles.OUTPUT_DIR.path_join("spritesheet.gif")
	assert_true(FileAccess.file_exists(written))
	var targets := ExportTarget.list(sheet)
	assert_eq(targets.size(), 1)
	assert_eq(targets[0].path, "", "no path kept")
	assert_false(targets[0].to_dictionary().has("path"))
	DirAccess.remove_absolute(written)

	# Exporting again downloads them all
	set_targets([targets[0], make_target(ExportOptions.Target.SPRITES, "")])
	assert_true(await main.files.exports.export_again())
	assert_true(FileAccess.file_exists(written))
	var sprites := WebFiles.OUTPUT_DIR.path_join("spritesheet_sprites")
	assert_eq(DirAccess.get_files_at(sprites).size(), 3)
	DirAccess.remove_absolute(written)
	remove_dir(sprites)
