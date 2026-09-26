extends "res://tests/test_case.gd"
## Switching between the grid and the packed layout in the main window

var main: Control
var sheet: Spritesheet


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	var images: Array[Image] = []
	for i in 3:
		images.append(make_image(Color.from_hsv(i / 4.0, 1, 1), Vector2i(8 + i * 4, 10)))
	Global.document.perform("Add", sheet.add_frames.bind(images))
	await get_tree().process_frame


func after_each() -> void:
	Settings.set_value(&"use_pivots", false)
	main.queue_free()
	Global.document.reset()


func menu_ids(title: String) -> Array:
	var menu_bar: MenuBar = main.get_node("%MenuBar")
	var menu: PopupMenu = menu_bar.get_node(title)
	var ids := []
	for i in menu.item_count:
		ids.append(menu.get_item_metadata(i))
	return ids


func test_switching_the_layout_can_be_undone() -> void:
	assert_true(Actions.is_checked(&"layout_grid"))
	Actions.run(&"layout_packed")
	assert_eq(sheet.layout, Spritesheet.Layout.PACKED)
	assert_eq(sheet.placements.size(), 3, "every frame has a place")
	assert_true(Actions.is_checked(&"layout_packed"))
	Global.document.undo()
	assert_eq(sheet.layout, Spritesheet.Layout.GRID)
	assert_true(sheet.placements.is_empty())


func test_menus_offer_what_the_layout_has() -> void:
	await get_tree().process_frame
	assert_true(&"insert_cell" in menu_ids("Frame"), "cells in the grid")
	assert_false(&"repack" in menu_ids("Frame"), "no packing in the grid")
	Actions.run(&"layout_packed")
	Actions.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var frame := menu_ids("Frame")
	assert_false(&"insert_cell" in frame, "no cells when packed")
	assert_true(&"repack" in frame)
	assert_true(&"pin_toggle" in frame)
	assert_false(Actions.is_enabled(&"insert_row"), "grid actions don't run")
	# No separators left dangling where grid actions were
	var menu: PopupMenu = main.get_node("%MenuBar").get_node("Frame")
	assert_false(menu.is_item_separator(menu.item_count - 1))
	for i in range(1, menu.item_count):
		assert_false(menu.is_item_separator(i) and menu.is_item_separator(i - 1), "double")


func test_the_sidebar_shows_the_atlas_settings_when_packed() -> void:
	var controller: LayoutController = main.layout_controller
	assert_false(controller.atlas_panel.visible)
	assert_true(main.grid_rows.is_visible_in_tree())
	controller.layout_packed_btn.pressed.emit()
	assert_true(controller.atlas_panel.visible)
	assert_false(main.grid_rows.is_visible_in_tree(), "no grid settings")
	# The Output section describes the pages, once
	assert_false("info" in controller.atlas_panel)
	assert_true("filled" in main.sheet_size.text, main.sheet_size.text)
	# Settings go through the undo history
	controller.atlas_panel.spacing.value = 3
	assert_eq(sheet.atlas_settings.spacing, 3)
	Global.document.undo()
	assert_eq(sheet.atlas_settings.spacing, 0)
	assert_eq(controller.atlas_panel.spacing.value, 0.0, "the panel follows")


func test_pinning_and_packing_again() -> void:
	Actions.run(&"layout_packed")
	var coord := Vector2i(1, 0)
	main.preview.set_selected_coords([coord] as Array[Vector2i])
	assert_false(Actions.is_checked(&"pin_toggle"))
	Actions.run(&"pin_toggle")
	assert_true(sheet.placements[coord].pinned)
	assert_true(Actions.is_checked(&"pin_toggle"))
	var moved := PackedLayout.moved(sheet, [coord] as Array[Vector2i], 0, Vector2i(100, 0))
	sheet.set_placements(moved)
	var pinned_at := PackedLayout.get_rect(sheet, coord)
	Actions.run(&"repack")
	assert_eq(PackedLayout.get_rect(sheet, coord), pinned_at, "pinned frames stay")
	Actions.run(&"pin_toggle")
	assert_false(sheet.placements[coord].pinned, "unpinned")


func test_toolbar_edits_every_frame_without_a_selection() -> void:
	Actions.run(&"layout_packed")
	main.preview.set_selected_coords([] as Array[Vector2i])
	assert_true(Actions.is_enabled(&"pin_toggle"))
	Actions.run(&"pin_toggle")
	for coord in sheet.placements:
		assert_true(sheet.placements[coord].pinned, "every frame pinned")
	assert_true(Actions.is_checked(&"pin_toggle"))
	Actions.run(&"pin_toggle")
	assert_false(sheet.placements[Vector2i(0, 0)].pinned)
	assert_true(Actions.is_enabled(&"align_top"))
	assert_true(Actions.is_enabled(&"trim"))
	assert_false(Actions.is_enabled(&"flip_h"), "transforms still need a selection")


func test_toolbar_order() -> void:
	var buttons: Dictionary = main.preview_area._action_buttons
	assert_true(buttons[&"pin_toggle"].get_index() < buttons[&"flip_h"].get_index())
	await get_tree().process_frame
	# Every shown separator has a shown button on each side
	var bar: HBoxContainer = main.preview_area._edit_bar
	var shown: Array[Control] = []
	for child: Control in bar.get_children():
		if child.visible:
			shown.append(child)
	assert_true(shown[0] is VSeparator, "after the tools")
	for i in range(1, shown.size()):
		assert_false(shown[i] is VSeparator and shown[i - 1] is VSeparator, "no empty group")
	assert_false(shown[-1] is VSeparator)


func test_pivots_are_opt_in() -> void:
	await get_tree().process_frame
	assert_false(Actions.is_available(&"tool_pivot"))
	assert_false(Actions.is_available(&"pivot_center"))
	assert_false(&"pivot_menu" in menu_ids("Frame"), "no Pivot menu")
	assert_false(main.preview_area.pivot_tool_btn.visible)
	assert_false(Actions.run(&"tool_pivot"), "no shortcut either")
	Settings.set_value(&"use_pivots", true)
	await get_tree().process_frame
	assert_true(main.preview_area.pivot_tool_btn.visible)
	Actions.run(&"tool_pivot")
	assert_eq(main.preview.tool, SpritesheetPreview.Tool.PIVOT)
	Settings.set_value(&"use_pivots", false)
	assert_eq(main.preview.tool, SpritesheetPreview.Tool.SELECT, "left with the setting")
	assert_ne(main.settings_window.get_control(&"use_pivots"), null)


func test_pivot_presets() -> void:
	Settings.set_value(&"use_pivots", true)
	assert_ne(Actions.get_action(&"pivot_top_left").icon, null)
	assert_ne(Actions.get_action(&"pivot_bottom_left").icon, null)
	main.preview.select_all()
	Actions.run(&"pivot_bottom")
	assert_eq(sheet.get_pivot(Vector2i(0, 0)), Vector2(4, 10))
	assert_eq(sheet.get_pivot(Vector2i(2, 0)), Vector2(8, 10), "each frame its own bottom")
	Actions.run(&"pivot_clear")
	assert_false(sheet.has_pivot(Vector2i(0, 0)))
	Actions.run(&"tool_pivot")
	assert_eq(main.preview.tool, SpritesheetPreview.Tool.PIVOT)
	assert_eq(Actions.get_shortcut_text(&"tool_pivot"), "E", "a shortcut like the other tools")
	assert_true(main.preview_area.pivot_tool_btn.button_pressed)


func test_packed_frames_are_described() -> void:
	Actions.run(&"layout_packed")
	var text := PreviewArea.describe_cell(sheet, Vector2i(0, 0))
	assert_true(text.begins_with("Frame 0"), text)
	assert_true("Page 1 at" in text, text)
	assert_true("3 frames" in main.sheet_info.text, main.sheet_info.text)


func test_the_toolbar_toggles_the_sprites_not_the_layout() -> void:
	var area: PreviewArea = main.preview_area
	assert_true(area._action_buttons.has(&"toggle_sprites"))
	assert_false(area._action_buttons.has(&"layout_grid"), "the sidebar switches layouts")
	assert_false(area._action_buttons.has(&"layout_packed"))


func test_the_preview_is_never_narrower_than_its_toolbar() -> void:
	var area: PreviewArea = main.preview_area
	var toolbar_width := area.toolbar.get_combined_minimum_size().x
	assert_true(toolbar_width > 0)
	assert_eq(area.get_combined_minimum_size().x, toolbar_width, "the splits keep room for it")
	var layout: Control = area.get_node("Layout")
	assert_eq(layout.grow_horizontal, Control.GROW_DIRECTION_END, "never over the sidebar")


func test_packing_again_from_the_sidebar() -> void:
	var panel: AtlasPanel = main.layout_controller.atlas_panel
	Actions.run(&"layout_packed")
	await get_tree().process_frame
	assert_true(panel.repack.is_visible_in_tree())
	assert_eq(panel.repack.text, "Repack", "the text fits in the sidebar")
	panel.pack_mode.select(panel.pack_mode.get_item_index(AtlasSettings.PackMode.KEEP))
	panel.pack_mode.item_selected.emit(panel.pack_mode.selected)
	var coord := Vector2i(1, 0)
	sheet.set_placements(PackedLayout.moved(sheet, [coord] as Array[Vector2i], 0, Vector2i(80, 0)))
	sheet.set_pinned([coord] as Array[Vector2i], false)
	var moved_to := PackedLayout.get_rect(sheet, coord)
	panel.repack.pressed.emit()
	assert_ne(PackedLayout.get_rect(sheet, coord), moved_to, "packed again")
	panel.repack.size.x = 40
	panel._fit_repack_text()
	assert_eq(panel.repack.text, "", "only the icon when narrow")
	assert_false(main.preview_area._action_buttons.has(&"repack"), "not in the toolbar")
	assert_true(main.preview_area._action_buttons.has(&"pin_toggle"), "with trim")
	var trim_index: int = main.preview_area._action_buttons[&"trim"].get_index()
	assert_eq(main.preview_area._action_buttons[&"pin_toggle"].get_index(), trim_index + 1)


func test_page_shapes_and_sharing_are_settings() -> void:
	Actions.run(&"layout_packed")
	var controller: LayoutController = main.layout_controller
	assert_false("dedupe" in controller.atlas_panel, "not in the sidebar")
	Settings.set_value(&"atlas_power_of_two", true)
	for size in PackedLayout.get_page_sizes(sheet):
		assert_eq(size, Vector2i(nearest_po2(size.x), nearest_po2(size.y)))
	Settings.set_value(&"atlas_power_of_two", false)
	var window: SettingsWindow = main.settings_window
	assert_ne(window.get_control(&"atlas_square"), null, "in the settings window")


func test_turning_and_trimming_are_toggles() -> void:
	var panel: AtlasPanel = main.layout_controller.atlas_panel
	Actions.run(&"layout_packed")
	assert_true(panel.trim.button_pressed, "trimmed by default")
	assert_eq(panel.trim.text, "", "icon only")
	panel.trim.button_pressed = false
	assert_false(sheet.atlas_settings.trim)
	var place: Dictionary = sheet.placements[Vector2i(0, 0)]
	assert_eq(place.src.size, sheet.frames[Vector2i(0, 0)].get_size(), "packed whole")
	Global.document.undo()
	assert_true(panel.trim.button_pressed)
	panel.allow_rotation.button_pressed = true
	assert_true(sheet.atlas_settings.allow_rotation)


func test_spacing_is_in_a_floating_panel() -> void:
	var panel: AtlasPanel = main.layout_controller.atlas_panel
	Actions.run(&"layout_packed")
	assert_eq(panel.gaps.text, "Spacing & Padding")
	assert_false(panel.spacing.is_visible_in_tree(), "in the panel, closed")
	panel.gaps.pressed.emit()
	assert_true(panel.gaps.popup.visible)
	panel.spacing.value = 2
	panel.extrude.value = 1
	assert_eq(sheet.atlas_settings.spacing, 2)
	assert_eq(panel.gaps.text, "Spacing 2 · Extrude 1", "says what's set")
	panel.gaps.popup.hide()


func test_the_grid_has_spacing_too() -> void:
	var gaps: SpacingDropdown = main.layout_controller.grid_gaps
	assert_true(gaps.is_visible_in_tree())
	var before: String = main.sheet_size.text
	gaps.spacing.value = 4
	assert_eq(ExportOptions.from_sheet(sheet).spacing, 4, "exports use it")
	assert_ne(main.sheet_size.text, before, "the output is bigger")
	Global.document.undo()
	assert_eq(ExportOptions.from_sheet(sheet).spacing, 0)
	assert_eq(gaps.spacing.value, 0.0, "follows undo")
	Actions.run(&"layout_packed")
	assert_false(gaps.is_visible_in_tree(), "the atlas has its own")


func test_frame_size_in_data_is_an_export_setting() -> void:
	Actions.run(&"layout_packed")
	Actions.run(&"export")
	var dialog: ExportDialog = main.export_dialog
	assert_true(dialog.frame_size.visible)
	dialog.frame_size.select(dialog.frame_size.get_item_index(ExportOptions.FrameSize.FRAME))
	dialog.frame_size.item_selected.emit(dialog.frame_size.selected)
	dialog.get_ok_button().pressed.emit()
	var options := ExportOptions.from_sheet(sheet)
	assert_eq(options.atlas_frame_size, ExportOptions.FrameSize.FRAME)
	main.files.export_file_dialog.hide()
	main.files.open_file_dialogs.clear()
