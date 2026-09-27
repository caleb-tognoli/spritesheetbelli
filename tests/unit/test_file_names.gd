extends "res://tests/test_case.gd"
## The names and folders suggested when saving and exporting, and the window title

## get_window_title() is static, so called on the script rather than the autoload
const GlobalScript := preload("res://scripts/autoloaded/global.gd")
const X := "C:/art/walk"
const Y := "C:/art/run"


func before_each() -> void:
	Global.document.reset()


func after_each() -> void:
	Global.document.reset()


## Adds frames linked to [param paths], like Add Sprites does
func add_linked(paths: Array[String], mode := Spritesheet.AddMode.FIRST_FREE) -> void:
	var imgs: Array[Image] = []
	var sources: Array[Dictionary] = []
	for path in paths:
		imgs.append(make_image(Color.RED))
		sources.append(FrameSource.for_file(path))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs, mode, sources))


func export_path(target := ExportOptions.Target.IMAGE) -> String:
	var options := ExportOptions.new()
	options.target = target
	return FileController.suggested_export_path(options)


func test_first_linked_frame_in_reading_order() -> void:
	var sheet := Spritesheet.new()
	assert_eq(FrameSource.get_first_path(sheet), "")
	sheet.set_frame(Vector2i(0, 1), make_image(Color.RED), FrameSource.for_file("b.png"))
	sheet.set_frame(Vector2i(3, 0), make_image(Color.RED), FrameSource.for_gif("a.gif", 2))
	sheet.set_frame(Vector2i(1, 0), make_image(Color.RED))
	assert_eq(FrameSource.get_first_path(sheet), "a.gif", "unlinked frames are skipped")
	sheet.set_frame(Vector2i(2, 0), make_image(Color.RED), FrameSource.for_file("c.png"))
	assert_eq(FrameSource.get_first_path(sheet), "c.png")


func test_nothing_to_name_it_after() -> void:
	assert_eq(FileController.suggested_project_path(), "spritesheet.sbelli", "no folder")
	assert_eq(export_path(), "spritesheet.png")
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	assert_eq(Global.document.get_display_name(), "", "pasted frames aren't linked")


func test_sprites_name_the_document() -> void:
	add_linked([X + "/walk_0.png", X + "/walk_1.png", X + "/walk_2.png", X + "/walk_3.png"])
	assert_eq(FileController.suggested_project_path(), X + "/walk_0.sbelli")
	assert_eq(export_path(), X + "/walk_0.png")
	assert_eq(export_path(ExportOptions.Target.ATLAS), X + "/walk_0_atlas.png")
	assert_eq(Global.document.get_display_name(), "walk_0.png")

	Global.document.reset()
	add_linked([Y + "/run_1.png"])
	assert_eq(FileController.suggested_project_path(), Y + "/run_1.sbelli", "after New")


func test_a_new_row_after_unlinked_frames() -> void:
	Global.spritesheet.add_frames([make_image(Color.RED)] as Array[Image])
	add_linked([Y + "/run_1.png"], Spritesheet.AddMode.NEW_ROW)
	assert_eq(export_path(), Y + "/run_1.png")


func test_opened_gif_is_named_after_it() -> void:
	var path := ProjectSettings.globalize_path("res://tests/fixtures/pillow.gif")
	var opened := Spritesheet.new()
	GifDecoder.add_to_sheet(opened, GifDecoder.load_file(path), "pillow", path)
	Global.document.load_state(opened.get_state())
	assert_eq(Global.document.export_path, "", "a GIF isn't where the sheet is exported")
	assert_eq(FileController.suggested_project_path(), path.get_basename() + ".sbelli")
	assert_eq(export_path(), path.get_basename() + ".png")


func test_project_image_and_export_come_first() -> void:
	add_linked([X + "/walk_0.png"])
	Global.document.export_path = "C:/sheets/hero_sheet.png"
	assert_eq(FileController.suggested_project_path(), "C:/sheets/hero_sheet.sbelli")
	assert_eq(export_path(), "C:/sheets/hero_sheet.png")

	Global.document.path = "C:/projects/myproj.sbelli"
	assert_eq(FileController.suggested_project_path(), "C:/projects/myproj.sbelli")
	assert_eq(export_path(), "C:/sheets/hero_sheet.png", "exports go where the last one went")
	Global.document.export_path = ""
	assert_eq(export_path(), "C:/projects/myproj.png")

	Global.document.path = ""
	Global.document.export_path = "C:/out/custom_name.png"
	assert_eq(FileController.suggested_project_path(), "C:/out/custom_name.sbelli")
	assert_eq(export_path(), "C:/out/custom_name.png")


func test_window_title() -> void:
	var app := (
		"%s %s"
		% [
			ProjectSettings.get_setting("application/config/name"),
			ProjectSettings.get_setting("application/config/version", "")
		]
	)
	var document := Document.new()
	assert_eq(GlobalScript.get_window_title(document), "Untitled - " + app)
	document.perform(
		"Add", document.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	assert_eq(GlobalScript.get_window_title(document), "(*) Untitled - " + app)
	document.load_state({}, "C:/projects/myproj.sbelli")
	assert_eq(GlobalScript.get_window_title(document), "myproj.sbelli - " + app)


func test_dialogs_get_a_name_and_keep_their_folder() -> void:
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var files: FileController = main.files
	var folder := OS.get_user_data_dir().path_join("tests")
	files.save_project_dialog.current_dir = folder
	files.save_project_dialog.current_file = ""
	files.save_as()
	assert_eq(files.save_project_dialog.current_dir, folder, "no folder to suggest")
	assert_eq(files.save_project_dialog.current_file, "spritesheet.sbelli")
	files.save_project_dialog.hide()
	files.open_file_dialogs.clear()

	add_linked([folder.path_join("walk_0.png")])
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.SPRITES
	Global.spritesheet.set_export_settings(options.to_dictionary())
	files.save_sprites_dialog.current_dir = "C:/"
	files.choose_export_path()
	assert_eq(files.save_sprites_dialog.current_dir, folder)
	assert_eq(files.save_sprites_dialog.title, "Export Sprites")
	files.save_sprites_dialog.hide()
	files.open_file_dialogs.clear()
	main.queue_free()


func test_picked_data_file_brings_its_image() -> void:
	var upload := WebFiles.UPLOAD_DIR
	var picked := PackedStringArray([upload + "/hero.png", upload + "/hero.json"])
	assert_eq(FileController.main_picked_file(picked), upload + "/hero.json")
	picked = PackedStringArray([upload + "/a.gif"])
	assert_eq(FileController.main_picked_file(picked), upload + "/a.gif")
	assert_true(".gif" in WebFiles.IMAGE_TYPES)
