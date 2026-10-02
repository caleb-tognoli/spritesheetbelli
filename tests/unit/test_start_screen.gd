extends "res://tests/test_case.gd"

var main: Control
var start: StartScreen
var dir := temp_path("start")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.clear_recent_files()
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	start = main.start_screen
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	await get_tree().process_frame
	Global.document.reset()
	Settings.clear_recent_files()
	Thumbnails.enabled = true
	remove_dir(dir)
	if DirAccess.dir_exists_absolute(Thumbnails.folder):
		remove_dir(Thumbnails.folder)


## A project with one red frame, saved at [param file_name]
func save_project(file_name: String) -> String:
	var path := dir.path_join(file_name)
	var sheet := Spritesheet.new()
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	ProjectFile.save(sheet, path)
	return path


## The texts of the labels on [param card]: its name, then its folder and when it was
## changed, or "Not found"
func texts_of(card: Button) -> PackedStringArray:
	var texts: PackedStringArray = []
	for label in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func close_button_of(card: Button) -> Button:
	return card.find_children("*", "Button", true, false)[0] as Button


## The Locate… button of a missing file's card, or null
func locate_button_of(card: Button) -> Button:
	for button: Button in card.find_children("*", "Button", true, false):
		if button.text == "Locate…":
			return button
	return null


func test_shown_while_nothing_is_open() -> void:
	assert_true(start.visible, "a new document")
	assert_eq(start.get_parent(), main.editor.get_parent(), "over the editor")
	Global.document.perform(
		"Add sprites", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	assert_false(start.visible, "hidden once it has frames")
	Global.document.undo()
	assert_false(start.visible, "the frames can still be redone")
	Global.document.reset()
	assert_true(start.visible, "back on New")
	Global.document.export_path = dir.path_join("sheet.png")
	assert_false(start.visible, "hidden with a file")
	Global.document.reset()
	Global.document.path = dir.path_join("a.sbelli")
	assert_false(start.visible)


func test_buttons_run_actions() -> void:
	var labels: PackedStringArray = []
	for id in start.action_buttons:
		var button := start.action_buttons[id]
		labels.append(button.text)
		var action := Actions.get_action(id)
		assert_eq(button.icon, action.icon)
		assert_true(button.tooltip_text.begins_with(action.label.trim_suffix("…")), "tooltip")
	assert_eq(labels, PackedStringArray(["Open…", "Add Spritesheet…", "Add Sprite(s)…", ""]))
	# Add Folder is only an icon, right of Add Sprite(s)
	var sprites := start.action_buttons[&"add_sprites"]
	var folder := start.action_buttons[&"add_folder"]
	assert_eq(folder.get_parent(), sprites.get_parent(), "together")
	assert_eq(folder.get_index(), sprites.get_index() + 1)
	assert_eq(sprites.get_parent().get_parent(), start.buttons)
	assert_eq(folder.custom_minimum_size.x, folder.custom_minimum_size.y, "square")
	sprites.pressed.emit()
	assert_eq(main.files.open_file_dialogs, [main.files.open_sprites_dialog] as Array[FileDialog])
	main.files.open_sprites_dialog.canceled.emit()
	main.files.open_sprites_dialog.hide()


func test_recent_files_with_a_missing_one() -> void:
	var project := save_project("walk.sbelli")
	var missing := dir.path_join("gone.png")
	Settings.add_recent_file(missing)
	Settings.add_recent_file(project)
	assert_eq(start.cards.keys(), [project, missing], "listed when the list changes")
	assert_true(start.recent_list.visible)
	await get_tree().process_frame
	var texts := texts_of(start.cards[project])
	assert_eq(texts[0], "walk.sbelli")
	assert_true(dir.ends_with(texts[1].trim_prefix("…")), "its folder, got %s" % texts[1])
	assert_eq(texts[2], "Just now", "when it was changed")
	assert_true(start.cards[project].tooltip_text.begins_with(project + "\nChanged "), "tooltip")
	assert_false(start.cards[project].disabled)
	assert_eq(texts_of(start.cards[missing]), PackedStringArray(["gone.png", "Not found"]))
	assert_true(start.cards[missing].disabled, "can't be opened")
	var placeholder := start.thumbnails[missing].texture
	assert_true(placeholder != null and not placeholder is ImageTexture, "placeholder")
	assert_true(start.thumbnails[project].texture is DPITexture, "none made yet")

	assert_false(start.empty_hint.visible)
	Settings.clear_recent_files()
	assert_false(start.recent_list.visible, "nothing to list")
	assert_true(start.empty_hint.visible, "says where they'll be")


func test_a_missing_file_is_located() -> void:
	var first := save_project("first.sbelli")
	var moved := save_project("moved.sbelli")
	var missing := dir.path_join("gone/deeper/walk.sbelli")
	Settings.add_recent_file(missing)
	Settings.add_recent_file(first)
	assert_eq(locate_button_of(start.cards[first]), null, "only when missing")
	# Its thumbnail from before it was moved
	var thumbnail := Thumbnails.folder.path_join("%s_1.png" % missing.md5_text())
	DirAccess.make_dir_recursive_absolute(Thumbnails.folder)
	make_image(Color.GREEN).save_png(thumbnail)

	locate_button_of(start.cards[missing]).pressed.emit()
	var dialog := start.locate_dialog
	assert_eq(dialog.title, "Locate walk.sbelli")
	assert_eq(dialog.filters, PackedStringArray([FileController.PROJECT_FILTER]))
	assert_eq(dialog.current_dir.trim_suffix("/"), dir, "the nearest folder that's there")
	dialog.hide()
	dialog.file_selected.emit(moved)
	await get_tree().process_frame
	assert_eq(Global.document.path, moved, "opened")
	assert_eq(Settings.get_recent_files(), PackedStringArray([moved, first]))
	assert_false(FileAccess.file_exists(thumbnail), "the old thumbnail is gone")


func test_a_located_file_takes_the_missing_ones_place() -> void:
	var files := PackedStringArray([dir.path_join("a.png"), dir.path_join("b.png")])
	Settings.add_recent_file(files[1])
	Settings.add_recent_file(files[0])
	Settings.add_recent_file(dir.path_join("gone.png"))
	Settings.add_recent_file(dir.path_join("first.png"))
	Settings.replace_recent_file(dir.path_join("gone.png"), dir.path_join("found.png"))
	assert_eq(
		Settings.get_recent_files(),
		PackedStringArray(
			[dir.path_join("first.png"), dir.path_join("found.png"), files[0], files[1]]
		)
	)
	# Already listed further down: moved up in its place
	Settings.replace_recent_file(dir.path_join("found.png"), files[1])
	assert_eq(
		Settings.get_recent_files(),
		PackedStringArray([dir.path_join("first.png"), files[1], files[0]])
	)


func test_an_image_is_located_among_images() -> void:
	var missing := dir.path_join("gone.png")
	Settings.add_recent_file(missing)
	locate_button_of(start.cards[missing]).pressed.emit()
	start.locate_dialog.hide()
	assert_eq(start.locate_dialog.filters, PackedStringArray([FileController.IMAGE_FILTER]))
	assert_eq(StartScreen.nearest_folder("Z:/not/there/at/all.png"), "Z:/")


func test_long_paths_lose_their_start() -> void:
	var label := Label.new()
	add_child(label)
	label.size.x = 80
	var path := "C:/Users/someone/Documents/Games/slime/sprites"
	var shown := StartScreen.trim_start(label, path)
	assert_true(shown.begins_with("…"), "cut")
	assert_true(path.ends_with(shown.trim_prefix("…")), "keeps the end")
	label.size.x = 2000
	assert_eq(StartScreen.trim_start(label, path), path, "whole when it fits")
	label.queue_free()


func test_forget() -> void:
	var project := save_project("walk.sbelli")
	var other := save_project("run.sbelli")
	Settings.add_recent_file(project)
	Settings.add_recent_file(other)
	close_button_of(start.cards[project]).pressed.emit()
	assert_eq(Settings.get_recent_files(), PackedStringArray([other]), "forgotten")
	assert_eq(start.cards.keys(), [other])
	assert_true(FileAccess.file_exists(project), "the file stays")


func test_open_from_it() -> void:
	var project := save_project("walk.sbelli")
	Settings.add_recent_file(project)
	start.cards[project].pressed.emit()
	await get_tree().process_frame
	assert_eq(Global.document.path, project, "opened")
	assert_eq(Global.spritesheet.frames.size(), 1)
	assert_false(start.visible)
	Global.document.reset()
	assert_true(start.visible, "back after New")


func test_thumbnail_written_on_save() -> void:
	var path := dir.path_join("saved.sbelli")
	Global.spritesheet.add_frames(
		[make_image(Color.RED), make_image(Color.BLUE, Vector2i(16, 32))] as Array[Image]
	)
	# An older thumbnail of the same file, which the new one replaces
	var old := Thumbnails.folder.path_join("%s_1.png" % path.md5_text())
	DirAccess.make_dir_recursive_absolute(Thumbnails.folder)
	make_image(Color.GREEN).save_png(old)
	assert_true(await main.files.save_project(path))
	Thumbnails.wait_for_all()
	var thumbnail := Thumbnails.load_image(path)
	assert_true(thumbnail != null, "written")
	assert_eq(thumbnail.get_size(), Vector2i(32, 32), "the sheet as exported")
	assert_color(thumbnail, Vector2i(0, 8), Color.RED)
	assert_color(thumbnail, Vector2i(16, 0), Color.BLUE)
	assert_false(FileAccess.file_exists(old), "the old one is gone")

	Global.document.reset()
	assert_true(start.thumbnails[path].texture is ImageTexture, "shown")


func test_thumbnail_reused_when_unchanged() -> void:
	var project := save_project("walk.sbelli")
	# Made by an earlier open of the file as it is now
	DirAccess.make_dir_recursive_absolute(Thumbnails.folder)
	make_image(Color.GREEN, Vector2i(4, 4)).save_png(Thumbnails.get_path_for(project))
	assert_true(await main.files.open_project(project))
	assert_false(Thumbnails.is_making(project), "not made again")
	assert_color(Thumbnails.load_image(project), Vector2i.ZERO, Color.GREEN)

	# Opening a file without one makes it
	var other := save_project("run.sbelli")
	assert_true(Thumbnails.load_image(other) == null)
	assert_true(await main.files.open_project(other))
	Thumbnails.wait_for_all()
	assert_color(Thumbnails.load_image(other), Vector2i.ZERO, Color.RED)
	Thumbnails.forget(other)
	assert_true(Thumbnails.load_image(other) == null, "forgotten")


func test_image_thumbnail_from_the_file() -> void:
	var path := dir.path_join("big.png")
	var img := make_image(Color.RED, Vector2i(1024, 512))
	img.fill_rect(Rect2i(512, 0, 512, 512), Color.BLUE)
	img.save_png(path)
	Settings.add_recent_file(path)
	assert_true(Thumbnails.is_making(path), "made when listed")
	Thumbnails.wait_for_all()
	start.refresh()
	var texture := start.thumbnails[path].texture
	assert_true(texture is ImageTexture, "shown")
	var thumbnail := texture.get_image()
	assert_eq(thumbnail.get_size(), Vector2i(256, 128), "fitted")
	var left := thumbnail.get_pixel(10, 10)
	var right := thumbnail.get_pixel(Thumbnails.SIZE - 10, 10)
	assert_true(left.r > 0.9 and left.b < 0.1, "red on the left, got %s" % left)
	assert_true(right.b > 0.9 and right.r < 0.1, "blue on the right, got %s" % right)


func test_canceled_opening_shows_it_again() -> void:
	var path := dir.path_join("sheet.png")
	make_image(Color.RED, Vector2i(32, 16)).save_png(path)
	await main.files.open_path(path)
	assert_false(start.visible, "opening")
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	window.canceled.emit()
	window.hide()
	assert_true(start.visible, "nothing was opened")
	assert_eq(Global.document.export_path, "")


func test_web() -> void:
	var project := save_project("walk.sbelli")
	Settings.add_recent_file(project)
	start.in_browser = true
	start.refresh()
	assert_true(start.cards.is_empty(), "no recent files in a browser")
	assert_false(start.recent_list.visible)
	assert_false(start.empty_hint.visible, "there won't be any")
	assert_eq(start.action_buttons.size(), 4, "the buttons stay")
	var card := start._make_card(dir.path_join("gone.png"))
	assert_eq(locate_button_of(card), null, "nothing to locate in a browser")
	card.free()
	assert_true(start.drop_hint.visible, "and the drop hint")

	Thumbnails.enabled = false
	Thumbnails.make_for_sheet(project, Global.spritesheet)
	assert_false(Thumbnails.is_making(project), "no thumbnails in a browser")


func test_covers_the_editor() -> void:
	await get_tree().process_frame
	var status_bar: Control = main.status_bar
	assert_true(start.get_global_rect().encloses(main.split.get_global_rect()))
	assert_true(
		start.get_global_rect().encloses(status_bar.get_global_rect()), "and the status bar"
	)
	assert_eq(main.editor.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_DISABLED)
	assert_false(Actions.is_enabled(&"toggle_history"), "the editor's actions can't run")
	assert_eq(Actions.get_disabled_reason(&"toggle_history"), "Nothing open")
	assert_true(Actions.is_enabled(&"open"))
	Global.document.perform(
		"Add sprites", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	assert_false(start.visible, "shown once something is open")
	assert_eq(main.editor.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_INHERITED)
	assert_true(Actions.is_enabled(&"toggle_history"))
	assert_true(Actions.is_enabled(&"zoom_fit"))


func test_as_wide_as_five_cards_at_most() -> void:
	for i in 7:
		Settings.add_recent_file(dir.path_join("%d.png" % i))
	await get_tree().process_frame
	await get_tree().process_frame
	var width := StartScreen.MAX_COLUMNS * StartScreen.CARD_SIZE.x + 4 * StartScreen.CARD_GAP
	assert_true(main.size.x > width + 100, "room for more")
	assert_eq(start.recent_list.size.x, width)
	assert_eq(start.drop_zone.size.x, width, "lined up with the cards")
	var sixth := start.cards[dir.path_join("1.png")]
	assert_eq(sixth.position.x, 0.0, "on the next row, under the first card")


func test_says_how_long_ago() -> void:
	var now := 1_800_000_000
	var ages := [
		StartScreen.describe_age(now - 5, now),
		StartScreen.describe_age(now - 60, now),
		StartScreen.describe_age(now - 150, now),
		StartScreen.describe_age(now - 3600, now),
		StartScreen.describe_age(now - 5 * 3600, now),
		StartScreen.describe_age(now - 30 * 3600, now),
		StartScreen.describe_age(now - 3 * 86400, now),
		StartScreen.describe_age(now + 100, now),
	]
	assert_eq(
		ages,
		[
			"Just now",
			"1 minute ago",
			"2 minutes ago",
			"1 hour ago",
			"5 hours ago",
			"Yesterday",
			"3 days ago",
			"Just now",
		]
	)
	var week_ago := now - 8 * 86400
	assert_eq(StartScreen.describe_age(week_ago, now), StartScreen.format_date(week_ago))


func test_dates_are_local() -> void:
	var bias: int = Time.get_time_zone_from_system().bias
	var local := {"year": 2026, "month": 9, "day": 12, "hour": 14, "minute": 3, "second": 0}
	var time := Time.get_unix_time_from_datetime_dict(local) - bias * 60
	assert_eq(StartScreen.format_date(time), "12 Sep 2026")
	assert_eq(StartScreen.format_date(time, true), "12 Sep 2026, 14:03")
	TranslationServer.set_locale("it")
	var italian := [StartScreen.format_date(time), StartScreen.describe_age(0, 7200)]
	TranslationServer.set_locale("en")
	assert_eq(italian, ["12 set 2026", "2 ore fa"])


## Presses [param keycode] in the window
func press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)


func test_arrow_keys_start_on_the_first_card() -> void:
	var first := save_project("first.sbelli")
	var second := save_project("second.sbelli")
	Settings.add_recent_file(second)
	Settings.add_recent_file(first)
	assert_true(get_viewport().gui_get_focus_owner() == null, "nothing at first")
	press(KEY_DOWN)
	assert_eq(get_viewport().gui_get_focus_owner(), start.cards[first])
	press(KEY_DELETE)
	assert_eq(Settings.get_recent_files(), PackedStringArray([second]), "forgotten")
	assert_eq(get_viewport().gui_get_focus_owner(), start.cards[second], "the next one")
	press(KEY_ESCAPE)
	assert_true(get_viewport().gui_get_focus_owner() == null, "nothing again")
	press(KEY_LEFT)
	press(KEY_DELETE)
	assert_eq(get_viewport().gui_get_focus_owner(), start.action_buttons[&"open"], "none left")
	press(KEY_ESCAPE)


func test_enter_locates_a_missing_file() -> void:
	var missing := dir.path_join("gone.png")
	Settings.add_recent_file(missing)
	press(KEY_RIGHT)
	press(KEY_ENTER)
	assert_eq(start.locate_dialog.title, "Locate gone.png")
	start.locate_dialog.hide()
	press(KEY_ESCAPE)


func test_menu_of_a_recent_file() -> void:
	var project := save_project("walk.sbelli")
	var missing := dir.path_join("gone.png")
	Settings.add_recent_file(missing)
	Settings.add_recent_file(project)
	var menu := start.card_menu
	start.open_menu(project, Vector2.ZERO)
	var items: PackedStringArray = []
	for i in menu.item_count:
		items.append(menu.get_item_text(i))
	assert_eq(
		items,
		PackedStringArray(
			["Open", "Show in File Manager", "Copy Path", "", "Remove from Recent Files"]
		)
	)
	menu.id_pressed.emit(StartScreen.MenuItem.FORGET)
	menu.hide()
	assert_eq(Settings.get_recent_files(), PackedStringArray([missing]), "forgotten")

	start.open_menu(missing, Vector2.ZERO)
	assert_eq(menu.get_item_text(0), "Locate…", "instead of opening it")
	var show := menu.get_item_index(StartScreen.MenuItem.SHOW)
	assert_true(menu.is_item_disabled(show), "nothing to show")
	menu.id_pressed.emit(StartScreen.MenuItem.LOCATE)
	menu.hide()
	assert_eq(start.locate_dialog.title, "Locate gone.png")
	start.locate_dialog.hide()


func test_open_from_the_menu() -> void:
	var project := save_project("walk.sbelli")
	Settings.add_recent_file(project)
	start.open_menu(project, Vector2.ZERO)
	start.card_menu.id_pressed.emit(StartScreen.MenuItem.OPEN)
	start.card_menu.hide()
	await get_tree().process_frame
	assert_eq(Global.document.path, project, "opened")
