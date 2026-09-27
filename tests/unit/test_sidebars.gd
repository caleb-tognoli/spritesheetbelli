extends "res://tests/test_case.gd"
## The sidebars on both sides of the preview: dragged wider, remembered, and as wide in
## both layouts

const MAIN := preload("res://ui/main/main.tscn")

var main: Control
var sidebar: Control
var panels: Control


func before_each() -> void:
	Settings.set_value(&"sidebar_width", 0)
	Settings.set_value(&"panels_width", 0)
	Settings.set_value(&"show_history", true)
	Global.document.reset()
	main = MAIN.instantiate()
	add_child(main)
	sidebar = main.get_node("%Sidebar")
	panels = main.layout_controller.side_split
	var images: Array[Image] = []
	for i in 3:
		images.append(make_image(Color.from_hsv(i / 3.0, 1, 1)))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(images))
	await layout()


func after_each() -> void:
	main.queue_free()
	Global.document.reset()
	for key: StringName in [&"sidebar_width", &"panels_width", &"show_history", &"show_sprites"]:
		Settings.set_value(key, Settings.DEFAULTS[key])


func layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_offsets_and_remembered_widths() -> void:
	assert_eq(SidebarSplit.get_offset(300, true), 300, "the first part's width")
	assert_eq(SidebarSplit.get_offset(300, false), -300, "the last part's, from the end")
	assert_eq(SidebarSplit.get_offset(0, false), 0, "as narrow as it can be")
	assert_eq(SidebarSplit.get_remembered_width(248, 248), 0, "narrowest")
	assert_eq(SidebarSplit.get_remembered_width(248.4, 248), 0, "rounding")
	assert_eq(SidebarSplit.get_remembered_width(200, 248), 0, "never below the smallest")
	assert_eq(SidebarSplit.get_remembered_width(301.6, 248), 302)


func test_the_sidebar_is_as_wide_in_both_layouts() -> void:
	var width := sidebar.size.x
	var preview_x: float = main.preview_area.global_position.x
	var sections: Control = main.sheet_size.get_parent()
	var atlas: Control = main.layout_controller.atlas_panel
	assert_true(sections.size.x >= atlas.get_combined_minimum_size().x, "fits the atlas panel")
	Actions.run(&"layout_packed")
	await layout()
	assert_eq(sidebar.size.x, width, "packed")
	assert_eq(main.preview_area.global_position.x, preview_x, "the preview doesn't move")
	assert_true(sections.size.x >= main.grid_rows.get_parent().get_combined_minimum_size().x)
	Actions.run(&"layout_grid")
	await layout()
	assert_eq(sidebar.size.x, width, "grid again")


func test_the_panels_are_as_wide_with_one_or_both() -> void:
	var width := panels.size.x
	assert_true(width >= main.layout_controller.sprites_panel.get_combined_minimum_size().x)
	Settings.set_value(&"show_sprites", true)
	await layout()
	assert_eq(panels.size.x, width, "the sprites fit too")


func test_dragged_widths_are_remembered() -> void:
	var split: HSplitContainer = main.split
	split.split_offset = 320
	await layout()
	split.drag_ended.emit()
	assert_eq(Settings.get_value(&"sidebar_width"), 320)
	var preview_split: HSplitContainer = main.preview_split
	preview_split.split_offset = -300
	await layout()
	preview_split.drag_ended.emit()
	assert_eq(Settings.get_value(&"panels_width"), 300)
	Settings.set_value(&"show_sprites", true)
	await layout()
	assert_eq(panels.size.x, 300.0, "opening the sprites keeps the width")

	main.queue_free()
	main = MAIN.instantiate()
	add_child(main)
	await layout()
	assert_eq(main.get_node("%Sidebar").size.x, 320.0, "next time")
	assert_eq(main.layout_controller.side_split.size.x, 300.0)


func test_double_clicking_the_handle_resets_the_width() -> void:
	var narrowest := sidebar.size.x
	Settings.set_value(&"sidebar_width", 400)
	main.sidebar_split.apply_width()
	await layout()
	assert_eq(sidebar.size.x, 400.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	main.split.get_drag_area_control().gui_input.emit(click)
	await layout()
	assert_eq(Settings.get_value(&"sidebar_width"), 0)
	assert_eq(sidebar.size.x, narrowest)
	Settings.set_value(&"panels_width", 400)
	main.panels_split.apply_width()
	main.preview_split.get_drag_area_control().gui_input.emit(click)
	assert_eq(Settings.get_value(&"panels_width"), 0, "the panels too")
