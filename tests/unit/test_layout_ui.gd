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
	assert_true("filled" in controller.atlas_panel.info.text, controller.atlas_panel.info.text)
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


func test_pivot_presets() -> void:
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
