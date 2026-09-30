extends "res://tests/test_case.gd"
## Text is translatable: every file with some is listed for the POT, which is up to date,
## and counts say "1 frame" but "2 frames"

const PotGenerator := preload("res://_dev/generate_pot.gd")


func test_tests_run_in_english() -> void:
	assert_eq(TranslationServer.get_locale(), "en")


func test_every_file_with_text_is_listed_for_the_pot() -> void:
	var listed: PackedStringArray = ProjectSettings.get_setting(PotGenerator.SETTING)
	for path in _files("res://scripts") + _files("res://ui"):
		if not PotGenerator.extract(path).is_empty():
			assert_true(path in listed, path + " has text, but isn't in POT Generation")
	for path in listed:
		assert_true(FileAccess.file_exists(path), path + " is listed but doesn't exist")


func test_the_pot_is_up_to_date() -> void:
	var listed: PackedStringArray = ProjectSettings.get_setting(PotGenerator.SETTING)
	var pot := FileAccess.get_file_as_string(PotGenerator.POT_PATH).replace("\r\n", "\n")
	assert_true(pot == PotGenerator.generate(listed), "out of date: run res://_dev/generate_pot.gd")


func test_the_pot_has_what_scripts_translate() -> void:
	var source := """
const NAMES := {  # L10n.mark
	&"png": "PNG images",
	&"jpg": "JPEG " + "images",
}
# L10n.mark
const FILTER := "*.png ; Images"
const IDS := ["not text"]

func show() -> void:
	label.text = "Label"
	button.tooltip_text = "On" if on else "Off"
	var text = "Local"
	title.text = "%d frames" % count
	menu.add_item("Item", 3)
	list.set_item_tooltip(0, "Tooltip")
	shown = tr("Shown") + L10n.mark("Later") + tr("Door", "furniture")
	count = tr_n("%d file", "%d files", n) + TranslationServer.translate("Static")
	long = tr(
		(
			"Split "
			+ "in parts"
		)
	)
	# tr("A comment")
	skipped = tr(some_variable) + tr("")
"""
	var found: Array[String] = []
	for message in PotGenerator.extract_script(source):
		var text: String = message.msgid
		if message.plural:
			text += " / " + message.plural
		if message.context:
			text += " (%s)" % message.context
		found.append(text)
	assert_eq(
		found,
		(
			[
				"PNG images",
				"JPEG images",
				"Images",
				"Label",
				"On",
				"Off",
				"Item",
				"Tooltip",
				"Shown",
				"Later",
				"Door (furniture)",
				"%d file / %d files",
				"Static",
				"Split in parts",
			]
			as Array[String]
		)
	)


func test_the_pot_has_what_scenes_translate() -> void:
	var scene := """
[node name="Label" type="Label"]
text = "Shown"
tooltip_text = "What it is"

[node name="Name" type="Label"]
auto_translate_mode = 2
text = "walk.png"

[node name="Menu" type="OptionButton"]
popup/item_0/text = "First"
"""
	var found: Array[String] = []
	for message in PotGenerator.extract_scene(scene):
		found.append(message.msgid)
	assert_eq(found, ["Shown", "What it is", "First"] as Array[String])


func test_plural_entries_have_msgid_plural() -> void:
	var pot := PotGenerator.generate(["res://ui/main/main_ui.gd"] as PackedStringArray)
	assert_true(
		'msgid "%d selected"\nmsgid_plural "%d selected"\nmsgstr[0] ""\nmsgstr[1] ""' in pot
	)


func test_one_frame_is_singular() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(0, 0)] as Array[Vector2i]))
	sheet.add_animation(SheetAnimation.create("run", sheet.get_sorted_coords()))
	assert_eq(AnimationLabels.describe(sheet, 0), "1 frame · 12 fps · loop")
	assert_eq(AnimationLabels.describe(sheet, 1), "2 frames · 12 fps · loop")


func test_the_status_bar_counts_frames() -> void:
	Global.document.reset()
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	main.update_sheet_info()
	assert_true(main.sheet_info.text.begins_with("1 frame · "), main.sheet_info.text)
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	main.update_sheet_info()
	assert_true(main.sheet_info.text.begins_with("2 frames · "), main.sheet_info.text)
	main.free()
	Global.document.reset()


func test_the_reload_question_counts_edited_frames() -> void:
	var dialog := ReloadDialog.new()
	add_child(dialog)
	dialog.ask("C:/art/walk.png", 3, 1, 2, false)
	assert_true("1 of its 3 frames was edited here" in dialog.message.text, dialog.message.text)
	assert_eq(dialog.for_all_check.text, "Do the same for the other 2 changed files")
	dialog.ask("C:/art/walk.png", 3, 2, 1, false)
	assert_true("2 of its 3 frames were edited here" in dialog.message.text, dialog.message.text)
	assert_eq(dialog.for_all_check.text, "Do the same for the other changed file")
	dialog.free()


## Every script and scene in [param dir] and its folders
func _files(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "tscn"]:
			found.append(dir.path_join(file))
	return found
