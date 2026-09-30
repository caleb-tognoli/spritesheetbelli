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


func test_italian_has_every_message_with_the_same_placeholders() -> void:
	var italian: Translation = load("res://translations/it.po")
	assert_eq(italian.locale, "it")
	var placeholder := RegEx.create_from_string("%[-+0#]*\\d*(\\.\\d+)?[sdf]")
	var listed: PackedStringArray = ProjectSettings.get_setting(PotGenerator.SETTING)
	for path in listed:
		for message in PotGenerator.extract(path):
			var texts: Array[String] = [message.msgid]
			var context: String = message.context
			var translated: Array[String] = [italian.get_message(message.msgid, context)]
			if message.plural:
				texts.append(message.plural)
				translated = [
					italian.get_plural_message(message.msgid, message.plural, 1, context),
					italian.get_plural_message(message.msgid, message.plural, 2, context),
				]
			for i in translated.size():
				var source: String = texts[mini(i, texts.size() - 1)]
				assert_true(translated[i] != "", "not in it.po: " + source)
				var wanted := placeholder.search_all(source).map(
					func(found: RegExMatch) -> String: return found.get_string()
				)
				var got := placeholder.search_all(translated[i]).map(
					func(found: RegExMatch) -> String: return found.get_string()
				)
				assert_eq(got, wanted, "placeholders of " + source)


func test_italian_counts() -> void:
	TranslationServer.set_locale("it")
	var texts := [
		tr("Save"),
		tr_n("%d frame", "%d frames", 1) % 1,
		tr_n("%d frame", "%d frames", 2) % 2,
		tr_n("%d frame", "%d frames", 0) % 0,
	]
	TranslationServer.set_locale("en")
	assert_eq(texts, ["Salva", "1 frame", "2 frame", "0 frame"])


func test_the_way_a_sheet_is_cut_is_not_the_clipboards_cut() -> void:
	var window: AddSpritesheetWindow = (
		load("res://ui/add_spritesheet/add_spritesheet_window.tscn").instantiate()
	)
	add_child(window)
	var label := window.cut_option.get_parent().get_child(0) as Label
	TranslationServer.set_locale("it")
	var texts := [label.atr(label.text), tr("Cut")]
	TranslationServer.set_locale("en")
	window.free()
	assert_eq(texts, ["Ritaglio", "Taglia"])


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
	var main := await _open_main()
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


func test_the_language_setting_picks_the_locale() -> void:
	Settings.set_value(&"language", "it")
	assert_eq(TranslationServer.get_locale(), "it")
	Settings.set_value(&"language", "en")
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(L10n.get_locale("system"), OS.get_locale_language())
	Settings.set_value(&"language", Settings.DEFAULTS[&"language"])
	TranslationServer.set_locale("en")


func test_po_files_in_the_translations_folder_add_languages() -> void:
	var folder := temp_path("more translations")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("de.po"), FileAccess.WRITE)
	(
		file
		. store_string(
			(
				"\n"
				. join(
					[
						'msgid ""',
						'msgstr ""',
						'"Language: de\\n"',
						'"Content-Type: text/plain; charset=UTF-8\\n"',
						'"Plural-Forms: nplurals=2; plural=(n != 1);\\n"',
						"",
						'msgid "Save"',
						'msgstr "Speichern"',
						"",
						'msgid "%d frame"',
						'msgid_plural "%d frames"',
						'msgstr[0] "%d Bild"',
						'msgstr[1] "%d Bilder"',
					]
				)
			)
		)
	)
	file.close()
	var previous_dir := L10n.user_dir
	L10n.user_dir = folder
	L10n.load_user_translations()
	assert_true(["de", "German"] in L10n.get_languages(), str(L10n.get_languages()))
	TranslationServer.set_locale("de")
	var saved := tr("Save")
	var frames := [tr_n("%d frame", "%d frames", 1), tr_n("%d frame", "%d frames", 3)]
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(folder.path_join("de.po"))
	L10n.load_user_translations()
	L10n.user_dir = previous_dir
	assert_eq(saved, "Speichern")
	assert_eq(frames, ["%d Bild", "%d Bilder"])
	assert_false(["de", "German"] in L10n.get_languages(), "taken out when loaded again")


func test_settings_offer_the_languages() -> void:
	var settings := SettingsWindow.new()
	add_child(settings)
	var option := settings.get_control(&"language") as OptionButton
	assert_eq(option.get_item_text(0), "System")
	assert_eq(option.get_item_text(1), "English")
	option.select(1)
	option.item_selected.emit(1)
	assert_eq(Settings.get_value(&"language"), "en")
	settings.free()
	Settings.set_value(&"language", Settings.DEFAULTS[&"language"])
	TranslationServer.set_locale("en")


func test_the_window_follows_language_changes() -> void:
	var german := Translation.new()
	german.locale = "de"
	german.add_message("Add Sprite(s)…", "Sprites hinzufügen…")
	german.add_plural_message(
		"%d frame · %d×%d grid · %d×%d px",
		["%d Bild · %d×%d Raster · %d×%d px", "%d Bilder · %d×%d Raster · %d×%d px"]
	)
	TranslationServer.add_translation(german)
	var main := await _open_main()
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	TranslationServer.set_locale("de")
	var tooltip: String = main.add_sprites_btn.tooltip_text
	var info: String = main.sheet_info.text
	TranslationServer.set_locale("en")
	var english_tooltip: String = main.add_sprites_btn.tooltip_text
	TranslationServer.remove_translation(german)
	main.free()
	Global.document.reset()
	assert_true(tooltip.begins_with("Sprites hinzufügen ("), tooltip)
	assert_true(info.begins_with("1 Bild · "), info)
	assert_true(english_tooltip.begins_with("Add Sprite(s) ("), english_tooltip)


func test_names_are_not_translated() -> void:
	var main := await _open_main()
	var sheet := Global.spritesheet
	Global.document.perform("Add", sheet.add_frames.bind([make_image(Color.RED)] as Array[Image]))
	# Named like a word that has a translation
	sheet.add_animation(SheetAnimation.create("Loop", [Vector2i.ZERO] as Array[Vector2i]))
	main.animation_panel.refresh()
	Settings.set_value(&"show_sprites", true)
	var sprites: SpritesPanel = main.layout_controller.sprites_panel
	sprites.refresh()
	var list: ItemList = main.animation_panel.list
	var header := sprites.tree.get_root().get_first_child()
	var modes := [
		list.get_item_auto_translate_mode(1),
		header.get_auto_translate_mode(0),
		header.get_first_child().get_auto_translate_mode(0),
	]
	Settings.set_value(&"show_sprites", Settings.DEFAULTS[&"show_sprites"])
	main.free()
	Global.document.reset()
	assert_eq(
		modes,
		[
			Node.AUTO_TRANSLATE_MODE_DISABLED,
			Node.AUTO_TRANSLATE_MODE_DISABLED,
			Node.AUTO_TRANSLATE_MODE_DISABLED
		]
	)


## The main window, with a new document
func _open_main() -> Control:
	Global.document.reset()
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	return main


## Every script and scene in [param dir] and its folders
func _files(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "tscn"]:
			found.append(dir.path_join(file))
	return found
