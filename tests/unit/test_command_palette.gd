extends "res://tests/test_case.gd"

var main: Control
var palette: CommandPalette
var dir := temp_path("command_palette")


func before_each() -> void:
	remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.set_value(&"command_palette_recent", [])
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	palette = main.command_palette
	Global.spritesheet.add_frames(
		[make_image(Color.RED), make_image(Color.GREEN), make_image(Color.BLUE)] as Array[Image]
	)
	await get_tree().process_frame


func after_each() -> void:
	palette.hide()
	Notify.message_dialog.hide()
	main.queue_free()
	Global.document.reset()
	Settings.set_value(&"command_palette_recent", [])


func press(keycode: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.command_or_control_autoremap = ctrl
	event.shift_pressed = shift
	get_viewport().push_input(event)
	await get_tree().process_frame


## The texts listed, in order
func listed() -> Array[String]:
	var texts: Array[String] = []
	for item in palette.list.get_root().get_children():
		texts.append(item.get_text(0))
	return texts


func find_entry(text: String) -> CommandPalette.Entry:
	for entry in palette.get_entries():
		if entry.text == text:
			return entry
	return null


func type(text: String) -> void:
	palette.search.text = text
	palette.search.text_changed.emit(text)


func test_fuzzy_score() -> void:
	assert_true(CommandPalette.fuzzy_score("flh", "Frame › Flip Horizontally") > 0)
	assert_true(CommandPalette.fuzzy_score("FLIP h", "Flip Horizontally") > 0, "any case, spaces")
	assert_eq(CommandPalette.fuzzy_score("hlf", "Flip Horizontally"), -1, "in order")
	assert_eq(CommandPalette.fuzzy_score("xyz", "Flip Horizontally"), -1)
	assert_eq(CommandPalette.fuzzy_score("", "Flip"), 0)
	assert_true(
		(
			CommandPalette.fuzzy_score("fit", "Fit to View")
			> CommandPalette.fuzzy_score("fit", "Outfit")
		),
		"words starting with it first"
	)
	assert_true(
		(
			CommandPalette.fuzzy_score("zoom", "Zoom In")
			> CommandPalette.fuzzy_score("zoom", "Z o o m")
		),
		"letters next to each other first"
	)
	assert_true(
		CommandPalette.fuzzy_score("ab", "a xab") > CommandPalette.fuzzy_score("ab", "a xb"),
		"the best place, not the first"
	)


func test_ranking() -> void:
	palette.open(main.preview_area)
	type("flh")
	assert_eq(listed()[0], "Frame › Flip Horizontally")
	type("fit")
	assert_eq(listed()[0], "View › Fit to View")
	type("top")
	assert_true("Frame › Align in Cell › Top" in listed(), "in a submenu")
	type("qqqq")
	assert_true(listed().is_empty())
	assert_true(palette._no_match.visible, "says nothing matches")
	type("")
	assert_eq(listed()[0], "File › New", "in the order of the menus")
	assert_false("Help › Command Palette…" in listed(), "not itself")


func test_opens_with_its_shortcut_and_escape_closes() -> void:
	assert_eq(
		Actions.get_shortcut_texts(CommandPalette.ID),
		PackedStringArray(["Ctrl+Shift+P", "Ctrl+K"]),
		"and a key browsers leave alone"
	)
	assert_true(CommandPalette.ID in MainMenuBar.MENUS["Help"])
	await press(KEY_P, true, true)
	assert_true(palette.visible)
	await get_tree().process_frame
	assert_true(palette.search.has_focus(), "ready to type")
	var flip := find_entry("Frame › Flip Horizontally")
	assert_eq(flip.shortcut, "H")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_false(palette.visible, "Escape closes it")
	assert_eq(Global.spritesheet.frames.size(), 3, "and runs nothing")


func test_browser_key() -> void:
	CommandPalette.use_other_key()
	assert_eq(Actions.get_shortcut_text(CommandPalette.ID), "Ctrl+K")
	CommandPalette.use_other_key()
	assert_eq(Actions.get_shortcut_text(CommandPalette.ID), "Ctrl+Shift+P", "put back")


func test_runs_the_selected_entry() -> void:
	Actions.run(&"select_all")
	var before: Image = Global.spritesheet.frames[Vector2i.ZERO]
	palette.open(main.preview_area)
	type("flip")
	# Down selects the next one, Flip Vertically
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	palette.search.gui_input.emit(down)
	assert_eq(palette.get_selected().text, "Frame › Flip Vertically")
	var up := down.duplicate()
	up.keycode = KEY_UP
	palette.search.gui_input.emit(up)
	assert_eq(palette.get_selected_index(), 0, "Up selects the one before")
	palette.search.gui_input.emit(up)
	assert_eq(palette.get_selected_index(), 0, "the first stays selected")
	type("flh")
	palette.search.text_submitted.emit(palette.search.text)
	assert_false(palette.visible, "closes")
	assert_ne(Global.spritesheet.frames[Vector2i.ZERO], before, "flipped")
	assert_eq(CommandPalette.get_recent(), PackedStringArray(["flip_h"]))


func test_clicking_an_entry_runs_it() -> void:
	palette.open(main.preview_area)
	type("fit")
	palette.list.item_mouse_selected.emit(Vector2.ZERO, MOUSE_BUTTON_LEFT)
	assert_false(palette.visible)
	assert_eq(CommandPalette.get_recent(), PackedStringArray(["zoom_fit"]))


func test_disabled_entries_say_why_and_dont_run() -> void:
	main.preview.set_selected_coords([] as Array[Vector2i])
	await get_tree().process_frame
	var flip := find_entry("Frame › Flip Horizontally")
	assert_eq(flip.disabled_reason, "No frames selected")
	assert_eq(find_entry("Edit › Paste").disabled_reason, "Nothing copied")
	assert_eq(find_entry("Frame › Replace Image…").disabled_reason, "No frames selected")
	assert_eq(find_entry("View › Zoom In").disabled_reason, "", "enabled")
	palette.open(main.preview_area)
	type("flh")
	assert_eq(palette.list.get_root().get_child(0).get_text(1), "No frames selected")
	var before: Image = Global.spritesheet.frames[Vector2i.ZERO]
	assert_false(palette.run_selected())
	assert_true(palette.visible, "stays open")
	assert_eq(Global.spritesheet.frames[Vector2i.ZERO], before, "not run")
	assert_true(CommandPalette.get_recent().is_empty())
	palette.hide()
	Global.document.reset()
	assert_eq(find_entry("File › Save").disabled_reason, "No frames yet")


func test_unavailable_entries_come_last() -> void:
	var sheet := Global.spritesheet
	var repack := find_entry("Frame › Pack Again")
	assert_true(repack.unavailable, "listed in the grid layout")
	assert_eq(repack.disabled_reason, "Only in the packed layout")
	assert_eq(find_entry("Frame › Pivot › Centre").disabled_reason, "Pivots are off")
	assert_false(find_entry("Frame › Rows › Insert Row").unavailable)
	CommandPalette.remember("repack")
	palette.open(main.preview_area)
	var texts := listed()
	var unavailable := palette._shown.map(
		func(entry: CommandPalette.Entry) -> bool: return entry.unavailable
	)
	var first := unavailable.find(true)
	assert_true(first > texts.find("View › Zoom In"), "after the available ones")
	assert_true(first > texts.find("Edit › Paste"), "and the disabled ones")
	assert_eq(unavailable.slice(first).count(false), 0, "at the bottom")
	assert_true(texts.find("Frame › Pack Again") >= first, "even when run last")
	var item: TreeItem = palette.list.get_root().get_child(texts.find("Frame › Pack Again"))
	assert_eq(item.get_text(1), "Only in the packed layout")
	assert_eq(item.get_custom_color(0), palette.list.get_theme_color(&"font_disabled_color"))
	type("pack")
	assert_eq(listed()[0], "View › Packed Layout")
	assert_eq(listed()[-1], "Frame › Pack Again", "after the ones that match")
	palette.select(listed().size() - 1)
	assert_false(palette.run_selected(), "doesn't run")
	assert_eq(sheet.layout, Spritesheet.Layout.GRID)
	palette.hide()
	sheet.set_layout(Spritesheet.Layout.PACKED)
	assert_false(find_entry("Frame › Pack Again").unavailable)
	var insert_row := find_entry("Frame › Rows › Insert Row")
	assert_true(insert_row.unavailable)
	assert_eq(insert_row.disabled_reason, "Only in the grid layout")


func test_disabled_actions_say_their_own_reason() -> void:
	var reason := func(id: StringName) -> String: return Actions.get_disabled_reason(id)
	var sheet := Global.spritesheet
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(reason.call(&"replace_image"), "Select a single frame")
	assert_eq(reason.call(&"move_row_up"), "Already the top row")
	assert_eq(reason.call(&"move_row_down"), "Already the bottom row")
	assert_eq(reason.call(&"reload_source"), "Not loaded from a file")
	assert_eq(reason.call(&"duplicate_animation"), "No animations yet")
	sheet.add_animation(SheetAnimation.create("walk", sheet.get_sorted_coords()))
	assert_eq(reason.call(&"mirror_animation"), "No animation chosen")
	assert_eq(reason.call(&"repack"), "Only in the packed layout")
	Settings.set_value(&"use_pivots", false)
	assert_eq(reason.call(&"pivot_center"), "Pivots are off")
	Settings.set_value(&"use_pivots", Settings.DEFAULTS[&"use_pivots"])
	sheet.set_layout(Spritesheet.Layout.PACKED)
	assert_eq(reason.call(&"insert_row"), "Only in the grid layout")
	assert_eq(reason.call(&"animation_labels"), "Only in the grid layout")
	sheet.set_layout(Spritesheet.Layout.GRID)
	assert_eq(reason.call(&"animation_labels"), "", "enabled")

	Global.document.reset()
	await get_tree().process_frame
	assert_eq(reason.call(&"flip_h"), "No frames yet", "before no frames selected")
	assert_eq(reason.call(&"animation_from_row"), "No frames yet")
	assert_eq(reason.call(&"undo"), "Nothing to undo")
	assert_eq(ActionReasons.first_failing([func() -> bool: return true, "Never"]), "")


func test_recent_first() -> void:
	CommandPalette.remember("zoom_in")
	CommandPalette.remember("zoom_fit")
	CommandPalette.remember("zoom_in")
	assert_eq(CommandPalette.get_recent(), PackedStringArray(["zoom_in", "zoom_fit"]))
	palette.open(main.preview_area)
	assert_eq(listed().slice(0, 3), ["View › Zoom In", "View › Fit to View", "File › New"])
	type("fi")
	assert_eq(listed()[0], "View › Fit to View", "the recent ones that match")
	for i in 20:
		CommandPalette.remember("action_%d" % i)
	assert_eq(CommandPalette.get_recent().size(), CommandPalette.MAX_RECENT, "only the last few")


func test_plays_animations() -> void:
	var sheet := Global.spritesheet
	sheet.add_animation(SheetAnimation.create("walk", [Vector2i(0, 0), Vector2i(1, 0)]))
	sheet.add_animation(SheetAnimation.create("jump", [Vector2i(2, 0)]))
	main.animation_panel.set_expanded(false)
	palette.open(main.preview_area)
	type("jump")
	assert_eq(listed()[0], "Play: jump")
	assert_true(palette.run_selected())
	assert_true(main.animation_panel.is_expanded(), "opens the animation panel")
	assert_eq(main.animation_panel.get_selected(), 1, "playing it")
	assert_eq(CommandPalette.get_recent(), PackedStringArray(["play:jump"]))


func test_writes_export_targets() -> void:
	var sheet := Global.spritesheet
	var hero := ExportTarget.create(sheet)
	hero.options.target = ExportOptions.Target.IMAGE
	hero.path = dir.path_join("hero.png")
	var unpicked := ExportTarget.create(sheet)
	unpicked.options.target = ExportOptions.Target.GIF
	var settings := ExportTarget.settings_with(sheet, [hero, unpicked] as Array[ExportTarget])
	sheet.set_export_settings(settings)
	var entry := find_entry("Export: hero.png · PNG")
	assert_ne(entry, null, "listed")
	assert_ne(find_entry("Export: No file picked yet · GIF"), null)
	palette.open(main.preview_area)
	type("hero")
	assert_eq(palette.get_selected().text, "Export: hero.png · PNG")
	assert_true(palette.run_selected())
	for i in 5:
		await get_tree().process_frame
	assert_true(FileAccess.file_exists(dir.path_join("hero.png")), "written")
	assert_false(main.export_dialog.visible)
	find_entry("Export: No file picked yet · GIF").run.call()
	assert_true(main.export_dialog.visible, "asks where")
	main.export_dialog.hide()
