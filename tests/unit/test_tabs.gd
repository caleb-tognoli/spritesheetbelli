extends "res://tests/test_case.gd"
## Several documents open at once, one per tab, see [member Global.documents] and
## [DocumentTabs]

var main: Control
var dir := temp_path("tabs_test")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Global.reset_documents()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame


func after_each() -> void:
	main.files.unsaved_changes_dialog.hide()
	main.queue_free()
	await get_tree().process_frame
	Global.reset_documents()
	Settings.reset_to_defaults()
	Settings.set_value(&"last_session", [])
	remove_dir(dir)


## Adds [param count] frames of [param color] to the active document as one undoable step
func add_frames(color: Color, count := 1) -> void:
	var imgs: Array[Image] = []
	for i in count:
		imgs.append(make_image(color))
	Global.document.perform("Add sprites", Global.spritesheet.add_frames.bind(imgs))


## Saves a project of [param count] frames of [param color] at [param file_name] in the
## test folder, without opening it, and returns its path
func make_project(file_name: String, color: Color, count := 1) -> String:
	var sheet := Spritesheet.new()
	var imgs: Array[Image] = []
	for i in count:
		imgs.append(make_image(color))
	sheet.add_frames(imgs)
	var path := dir.path_join(file_name)
	ProjectFile.save(sheet, path)
	return path


## A new tab, active, with nothing in it, like New
func new_tab() -> Document:
	main.files.new_spritesheet()
	return Global.document


## Checks the open documents are [param expected], in this order
func assert_tabs(expected: Array[Document], message := "") -> void:
	var indexes := expected.map(
		func(document: Document) -> int: return Global.documents.find(document)
	)
	assert_true(Global.documents == expected, "%s: %s" % [message, indexes])


func tab_titles() -> PackedStringArray:
	var tabs: DocumentTabs = main.tabs
	tabs.refresh()
	var titles: PackedStringArray = []
	for i in tabs.bar.tab_count:
		titles.append(tabs.bar.get_tab_title(i))
	return titles


func test_new_opens_a_tab() -> void:
	var first := Global.document
	main.files.new_spritesheet()
	assert_eq(Global.documents.size(), 1, "the start screen shows already")
	add_frames(Color.RED)
	var second := new_tab()
	assert_tabs([first, second] as Array[Document])
	assert_true(second.is_blank())
	assert_true(main.start_screen.visible, "the new tab shows the start screen")
	assert_eq(main.preview.spritesheet, second.spritesheet)
	Global.switch_to(first)
	assert_false(main.start_screen.visible)
	assert_eq(main.preview.spritesheet, first.spritesheet, "the preview shows the active one")
	assert_eq(tab_titles(), PackedStringArray(["Untitled(*)", "Untitled"]))


func test_opening_projects_opens_tabs() -> void:
	var walk := make_project("walk.sbelli", Color.RED)
	var run := make_project("run.sbelli", Color.BLUE, 2)
	var blank := Global.document
	assert_true(await main.files.open_project(walk))
	assert_eq(Global.documents.size(), 1, "in the blank tab")
	assert_true(Global.document == blank)
	assert_true(await main.files.open_project(run))
	assert_eq(Global.documents.size(), 2, "in a tab of its own")
	assert_eq(Global.spritesheet.frames.size(), 2)
	assert_eq(tab_titles(), PackedStringArray(["walk.sbelli", "run.sbelli"]))
	assert_true(await main.files.open_project(walk))
	assert_eq(Global.documents.size(), 2, "an open project isn't opened twice")
	assert_true(Global.document == blank, "its tab is shown")
	assert_false(main.files.unsaved_changes_dialog.visible, "nothing to ask")

	# Dropped together, each in a tab
	Global.close_document(Global.documents[1])
	await main.files.open_dropped_files(
		PackedStringArray([run, make_project("jump.sbelli", Color.GREEN)])
	)
	assert_eq(tab_titles(), PackedStringArray(["walk.sbelli", "run.sbelli", "jump.sbelli"]))


func test_each_tab_has_its_own_history() -> void:
	Settings.set_value(&"show_history", true)
	add_frames(Color.RED)
	var first := Global.document
	var second := new_tab()
	add_frames(Color.BLUE, 2)
	add_frames(Color.BLUE)
	assert_eq(main.history_panel.list.item_count, 3, "the start and two steps")
	Global.switch_to(first)
	assert_eq(main.history_panel.list.item_count, 2, "the other tab's history")
	Actions.run(&"undo")
	assert_true(first.spritesheet.is_empty(), "undone in the active tab")
	assert_eq(second.spritesheet.frames.size(), 3, "not in the other")
	assert_eq(main.sheet_info.text, "No frames. Add sprites or drop images here.")
	Global.switch_to(second)
	assert_true(main.sheet_info.text.begins_with("3 frames"), "the status bar follows")
	assert_eq(main.sprite_width.value, 16.0)


func test_a_tab_is_shown_as_it_was_left() -> void:
	add_frames(Color.RED, 6)
	var first := Global.document
	first.perform(
		"Add animation",
		func() -> void:
			first.spritesheet.add_animation(
				SheetAnimation.create("walk", [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
			)
	)
	var preview: SpritesheetPreview = main.preview
	var selection: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	preview.set_selected_coords(selection)
	main.animation_panel.select_animation(0)
	await get_tree().process_frame
	preview.set_zoom(3.0)
	var view := preview.get_view()

	new_tab()
	add_frames(Color.BLUE)
	await get_tree().process_frame
	assert_true(preview.get_selected_coords().is_empty(), "nothing selected in another")
	assert_eq(main.animation_panel.get_selected(), -1)

	Global.switch_to(first)
	await get_tree().process_frame
	assert_eq(preview.get_selected_coords(), selection, "the selection is back")
	assert_eq(main.animation_panel.get_selected(), 0, "and the chosen animation")
	assert_eq(preview.get_view().zoom, view.zoom, "and the zoom")
	assert_eq(preview.get_view().centre, view.centre)


func test_closing_a_tab() -> void:
	add_frames(Color.RED)
	var first := Global.document
	var second := new_tab()
	add_frames(Color.BLUE)
	var third := new_tab()
	Global.switch_to(second)
	main.files.close_tabs([second] as Array[Document])
	assert_true(main.files.unsaved_changes_dialog.visible, "asks to save it first")
	assert_eq(main.files.unsaved_changes_dialog.ok_button_text, "Save")
	main.files.unsaved_changes_dialog.custom_action.emit(&"discard")
	assert_tabs([first, third] as Array[Document], "Don't Save closes it")
	assert_true(Global.document == third, "the next tab becomes active")

	Actions.run(&"close_tab")
	assert_tabs([first] as Array[Document], "nothing to save")
	assert_true(Global.document == first, "the one before, when it was the last")

	main.files.close_tabs([first] as Array[Document])
	main.files.unsaved_changes_dialog.custom_action.emit(&"discard")
	assert_tabs([first] as Array[Document], "the last tab stays")
	assert_true(first.is_blank(), "emptied")
	assert_true(main.start_screen.visible)
	assert_false(Actions.is_enabled(&"close_tab"), "nothing to close")


func test_closing_several_unsaved_tabs_lists_them() -> void:
	add_frames(Color.RED)
	Global.document.path = dir.path_join("walk.sbelli")
	var first := Global.document
	var second := new_tab()
	add_frames(Color.BLUE)
	var third := new_tab()
	main.files.close_tabs(Global.documents.duplicate())
	var dialog: ConfirmationDialog = main.files.unsaved_changes_dialog
	assert_true(dialog.visible, "asks once")
	assert_eq(dialog.ok_button_text, "Save All")
	assert_eq(
		dialog.dialog_text,
		"Save changes to these projects before closing them?\n\n• walk.sbelli\n• Untitled"
	)
	dialog.hide()
	assert_eq(Global.documents.size(), 3, "Cancel keeps them")

	# Save All saves each in turn: the untitled one asks where
	main.files.close_tabs([first, second, third] as Array[Document])
	dialog.hide()
	dialog.confirmed.emit()
	await until_idle()
	assert_false(first.is_dirty, "saved to its file")
	assert_true(FileAccess.file_exists(first.path))
	assert_true(Global.document == second, "asking where to save the next one")
	assert_true(main.files.open_file_dialogs.has(main.files.save_project_dialog))
	main.files.save_project_dialog.file_selected.emit(dir.path_join("run.sbelli"))
	await until_idle()
	assert_false(second.is_dirty)
	assert_eq(Global.documents.size(), 1, "then closed")
	assert_true(Global.document == third and third.is_blank(), "the last one emptied")


func test_quitting_asks_about_every_unsaved_tab() -> void:
	var quits := [0]
	var quit := func() -> void: quits[0] += 1
	main.files.confirm_quit(quit)
	assert_eq(quits[0], 1, "nothing unsaved")
	add_frames(Color.RED)
	new_tab()
	main.files.confirm_quit(quit)
	var dialog: ConfirmationDialog = main.files.unsaved_changes_dialog
	assert_true(dialog.visible)
	assert_eq(dialog.dialog_text, "Save changes to the spritesheet before quitting?")
	assert_true(Global.document == Global.documents[0], "its tab is shown")
	dialog.hide()
	new_tab()
	add_frames(Color.BLUE)
	main.files.confirm_quit(quit)
	assert_true(dialog.dialog_text.begins_with("Save changes to these projects before quitting?"))
	dialog.custom_action.emit(&"discard")
	assert_eq(quits[0], 2, "Don't Save quits")
	assert_eq(Global.documents.size(), 3, "without closing the tabs, which are remembered")


func test_work_lands_in_the_tab_it_was_started_in() -> void:
	var image := dir.path_join("red.png")
	make_image(Color.RED).save_png(image)
	var first := Global.document
	add_frames(Color.BLUE)
	var done := [false]
	var add := func() -> void:
		await FileController.add_image_files(PackedStringArray([image]))
		done[0] = true
	add.call()
	assert_false(done[0], "loaded on worker threads")
	var second := new_tab()
	while not done[0]:
		await get_tree().process_frame
	assert_eq(first.spritesheet.frames.size(), 2, "added where it was started")
	assert_true(second.is_blank(), "not in the tab chosen meanwhile")
	assert_eq(tab_titles()[0], "red.png(*)", "its tab shows the change")


func test_tab_titles_tell_files_of_the_same_name_apart() -> void:
	var a := Document.new()
	a.path = "/projects/hero/walk.sbelli"
	var b := Document.new()
	b.path = "/projects/enemy/walk.sbelli"
	var c := Document.new()
	c.export_path = "/projects/run.png"
	var untitled := Document.new()
	assert_eq(
		DocumentTabs.get_titles([a, b, c, untitled] as Array[Document]),
		PackedStringArray(["hero/walk.sbelli", "enemy/walk.sbelli", "run.png", "Untitled"])
	)


func test_next_and_previous_tab() -> void:
	assert_false(Actions.is_enabled(&"next_tab"), "one tab")
	var first := Global.document
	add_frames(Color.RED)
	var second := new_tab()
	add_frames(Color.BLUE)
	var third := new_tab()
	Actions.run(&"next_tab")
	assert_true(Global.document == first, "round to the first")
	Actions.run(&"next_tab")
	assert_true(Global.document == second)
	Actions.run(&"previous_tab")
	Actions.run(&"previous_tab")
	assert_true(Global.document == third, "round to the last")


func test_the_tab_bar() -> void:
	var tabs: DocumentTabs = main.tabs
	add_frames(Color.RED)
	var first := Global.document
	var second := new_tab()
	tabs.refresh()
	assert_eq(tabs.bar.tab_count, 2)
	assert_eq(tabs.bar.current_tab, 1)
	tabs.bar.current_tab = 0
	assert_true(Global.document == first, "clicking a tab makes it active")
	Global.move_document(second, 0)
	assert_eq(tab_titles(), PackedStringArray(["Untitled", "Untitled(*)"]), "moved")
	tabs.new_button.pressed.emit()
	assert_eq(Global.documents.size(), 3, "+ opens a new tab")
	tabs.bar.tab_close_pressed.emit(2)
	assert_eq(Global.documents.size(), 2, "and its close button closes it")

	tabs.open_menu(0, Vector2.ZERO)
	assert_true(tabs.menu.visible)
	tabs.menu.hide()
	tabs.menu.id_pressed.emit(DocumentTabs.MenuItem.CLOSE_OTHERS)
	assert_true(main.files.unsaved_changes_dialog.visible, "the other one is unsaved")
	main.files.unsaved_changes_dialog.custom_action.emit(&"discard")
	assert_tabs([second] as Array[Document], "Close Other Tabs")


func test_session_reopens_the_projects_in_tabs() -> void:
	var walk := make_project("walk.sbelli", Color.RED)
	var run := make_project("run.sbelli", Color.BLUE)
	assert_true(await main.files.open_project(walk))
	assert_true(await main.files.open_project(run))
	new_tab()
	add_frames(Color.GREEN)
	Global.switch_to(Global.documents[0])
	main.files.remember_session()
	assert_eq(Settings.get_value(&"last_session"), [walk, run], "projects with a file only")
	assert_eq(Settings.get_value(&"last_session_tab"), 0)

	Settings.set_value(&"restore_session", true)
	Settings.set_value(&"last_session_tab", 1)
	Global.reset_documents()
	await main.files.restore_session()
	assert_eq(tab_titles(), PackedStringArray(["walk.sbelli", "run.sbelli"]))
	assert_eq(Global.document.path, run, "the active one is active again")


func test_a_copy_of_each_unsaved_tab_is_kept() -> void:
	var recovery: Recovery = main.recovery
	add_frames(Color.RED)
	var first := Global.document
	var second := new_tab()
	add_frames(Color.BLUE)
	recovery.save_copy_if_changed()
	recovery.wait()
	assert_true(recovery.has_copy(first))
	assert_true(recovery.has_copy(second))
	assert_ne(recovery.copy_dir(first), recovery.copy_dir(second), "each in its own folder")
	var copy := ProjectFile.load(recovery.copy_dir(first).path_join(Recovery.COPY_FILE))
	assert_color(copy.state.frames.values()[0], Vector2i.ZERO, Color.RED, "of its own sheet")

	var second_dir := recovery.copy_dir(second)
	main.files.close_tabs([second] as Array[Document])
	main.files.unsaved_changes_dialog.custom_action.emit(&"discard")
	assert_false(DirAccess.dir_exists_absolute(second_dir), "closing a tab deletes its copy")
	assert_true(recovery.has_copy(first), "the others stay")


func test_a_tab_left_right_after_opening_shows_its_whole_sheet() -> void:
	add_frames(Color.BLUE, 30)
	await get_tree().process_frame
	main.preview.set_zoom(5.0)
	var walk := make_project("walk.sbelli", Color.RED, 2)
	assert_true(await main.files.open_project(walk))
	var opened := Global.document
	# Before its view is shown, as when a session opens several projects
	new_tab()
	assert_eq(opened.view_state.view, {}, "the whole sheet, still to be shown")
	Global.switch_to(opened)
	await get_tree().process_frame
	assert_ne(main.preview.get_view().zoom, 5.0, "not the view of the tab it was opened from")
