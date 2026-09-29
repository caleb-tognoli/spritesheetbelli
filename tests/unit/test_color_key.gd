extends "res://tests/test_case.gd"
## Remove Background Colour, in a panel dropped down from the canvas toolbar: previewed on
## the canvas without changing the sheet, removed as one step on Confirm, closed without a
## trace by Cancel, Escape or clicking away, and picked from a frame with the eyedropper.
## Clicks on the canvas select frames while it's open.

var main: Control
var preview: SpritesheetPreview
var sheet: Spritesheet
var color_key: ColorKeyPreview
var dropdown: ColorKeyDropdown


func before_each() -> void:
	Global.document.reset()
	# Remembered between runs, so each test starts from the default
	Settings.set_value(&"background_tolerance", SheetBackground.DEFAULT_TOLERANCE)
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	sheet = Global.spritesheet
	color_key = main.color_key
	dropdown = color_key.dropdown
	Global.document.perform(
		"Add",
		sheet.add_frames.bind(
			(
				[magenta_sprite(Color.RED), magenta_sprite(Color.GREEN), magenta_sprite(Color.BLUE)]
				as Array[Image]
			)
		)
	)
	await get_tree().process_frame


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


## A red, green or blue square on magenta
static func magenta_sprite(color: Color) -> Image:
	var img := make_image(Color.MAGENTA, Vector2i(8, 8))
	img.fill_rect(Rect2i(2, 2, 4, 4), color)
	return img


## The image the preview shows for the frame at [param coord]
func shown(coord: Vector2i) -> Image:
	var texture: ImageTexture = preview.get_frame_texture(coord).texture
	return texture.get_image()


## Waits for the preview to be worked out on worker threads
func settle() -> void:
	for i in 5:
		await get_tree().process_frame


func select(coords: Array[Vector2i]) -> void:
	preview.set_selected_coords(coords)


func press(button_index: MouseButton, at: Vector2) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button_index
	click.pressed = true
	click.position = at
	return click


func escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


func test_the_button_is_in_the_toolbar() -> void:
	assert_true(dropdown.is_inside_tree())
	assert_true(main.preview_area.toolbar.is_ancestor_of(dropdown))
	assert_eq(dropdown.icon, ColorKeyDropdown.EYEDROPPER_ICON)
	assert_eq(dropdown.tooltip_text, Actions.get_tooltip(&"color_key"))
	assert_false(dropdown.disabled)
	Global.document.perform("Clear", sheet.remove_frames.bind(sheet.get_sorted_coords()))
	await get_tree().process_frame
	assert_true(dropdown.disabled, "nothing to remove it from")
	assert_false(Actions.is_enabled(&"color_key"))


func test_the_preview_leaves_the_sheet_alone() -> void:
	select([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	Global.document.mark_saved()
	var history := Global.document.get_history()
	Actions.run(&"color_key")
	assert_true(dropdown.is_open())
	assert_eq(dropdown.get_color(), Color.MAGENTA, "suggests the corner colour")
	assert_true(dropdown.is_on())
	assert_false(dropdown.enabled_check.visible, "nothing to turn off")
	assert_eq(dropdown.note.text, "In 2 selected frames")
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0, "removed in the preview")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(3, 3), Color.RED, "the sprite stays")
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA, "not selected")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA, "the sheet is the same")
	assert_eq(Global.document.get_history(), history, "nothing to undo")
	assert_false(Global.document.is_dirty, "nothing to save")

	# Other frames selected while open (with the keyboard) are previewed instead
	select([Vector2i(1, 0)] as Array[Vector2i])
	await settle()
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0).a, 0.0)
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "no longer selected")
	assert_eq(dropdown.note.text, "In 1 selected frames")


func test_confirm_is_one_step_on_the_selected_frames() -> void:
	select([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	dropdown.tolerance_field.value = 20
	var steps := Global.document.get_history().size()
	dropdown.confirm_button.pressed.emit()
	assert_false(dropdown.is_open(), "closes")
	await settle()
	assert_eq(Global.document.get_history().size(), steps + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Remove background")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0).a, 0.0)
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(0, 0).a, 0.0)
	assert_eq(sheet.frames[Vector2i(1, 0)].get_pixel(0, 0), Color.MAGENTA, "not selected")
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(3, 3), Color.BLUE)
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA)
	assert_eq(Settings.get_value(&"background_tolerance"), 0.2, "remembered")
	Global.document.undo()
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA, "undone at once")
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(0, 0), Color.MAGENTA, "undone at once")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "the preview is gone")


func test_every_frame_when_none_are_selected() -> void:
	select([] as Array[Vector2i])
	assert_true(Actions.is_enabled(&"color_key"), "enabled with frames")
	Actions.run(&"color_key")
	await settle()
	assert_eq(dropdown.note.text, "In all 3 frames")
	assert_false(dropdown.confirm_button.disabled)
	for x in 3:
		assert_eq(shown(Vector2i(x, 0)).get_pixel(0, 0).a, 0.0, "previewed in %d" % x)
	var steps := Global.document.get_history().size()
	dropdown.confirm()
	await settle()
	assert_eq(Global.document.get_history().size(), steps + 1, "one step")
	for x in 3:
		assert_eq(sheet.frames[Vector2i(x, 0)].get_pixel(0, 0).a, 0.0, "removed in %d" % x)
		assert_eq(sheet.frames[Vector2i(x, 0)].get_pixel(3, 3).a, 1.0)
	Global.document.undo()
	for x in 3:
		assert_eq(sheet.frames[Vector2i(x, 0)].get_pixel(0, 0), Color.MAGENTA)


func test_cancel_escape_and_clicking_away_leave_the_frames() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	var steps := Global.document.get_history().size()
	Actions.run(&"color_key")
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0)
	dropdown.tolerance_field.value = 30
	dropdown.cancel_button.pressed.emit()
	assert_false(dropdown.is_open())
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "restored")
	assert_eq(Settings.get_value(&"background_tolerance"), 0.1, "not remembered")
	# Changes made after closing don't bring the preview back
	dropdown.tolerance_field.value = 40
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA)

	Actions.run(&"color_key")
	await settle()
	dropdown.set_picking(true)
	dropdown._input(escape())
	assert_false(dropdown.is_picking(), "Escape puts the eyedropper away first")
	assert_true(dropdown.is_open())
	dropdown._on_popup_input(escape())
	assert_false(dropdown.is_open(), "then closes, also from the panel")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "restored")

	Actions.run(&"color_key")
	await settle()
	dropdown._input(escape())
	assert_false(dropdown.is_open(), "Escape closes it")

	# Clicking the toolbar, the sidebar, or right-clicking the canvas for its
	# menu closes it
	var canvas: Vector2 = main.preview_area.stage.get_global_rect().get_center()
	var toolbar: Vector2 = main.preview_area.toolbar.get_global_rect().get_center()
	var sidebar: Vector2 = main.export_btn.get_global_rect().get_center()
	for away: Array in [
		[MOUSE_BUTTON_LEFT, toolbar], [MOUSE_BUTTON_LEFT, sidebar], [MOUSE_BUTTON_RIGHT, canvas]
	]:
		Actions.run(&"color_key")
		await settle()
		assert_true(dropdown.is_open())
		dropdown._input(press(MOUSE_BUTTON_WHEEL_UP, away[1]))
		assert_true(dropdown.is_open(), "the wheel zooms")
		dropdown._input(press(away[0], away[1]))
		assert_false(dropdown.is_open(), "clicking away closes it: %s" % [away])
		assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "restored")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA)
	assert_eq(Global.document.get_history().size(), steps, "nothing to undo")

	# The button closes it again
	Actions.run(&"color_key")
	dropdown.pressed.emit()
	assert_false(dropdown.is_open())


func test_the_eyedropper_picks_from_a_frame_as_it_is() -> void:
	select([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	await settle()
	# Headless windows have no size, so the preview is given one
	main.preview_area.container.stretch = false
	(preview.get_viewport() as SubViewport).size = Vector2i(600, 400)
	preview.fit_to_view()
	dropdown.set_picking(true)
	assert_true(preview.picking)
	# The magenta corner of the second frame, shown transparent in the preview
	var target := preview.get_frame_world_rect(Vector2i(1, 0)).position + Vector2(0.5, 0.5)
	var click := press(MOUSE_BUTTON_LEFT, (target - preview.camera.position) * preview.camera.zoom)
	# The click reaches the preview rather than closing the panel
	var on_preview := press(
		MOUSE_BUTTON_LEFT, main.preview_area.container.get_global_rect().get_center()
	)
	dropdown._input(on_preview)
	assert_true(dropdown.is_open(), "picking")
	preview._unhandled_input(click)
	assert_eq(dropdown.get_color(), Color.MAGENTA, "the frame's colour, not the preview's")
	assert_false(dropdown.is_picking())
	assert_true(dropdown.is_open(), "stays open")
	# The green square of the same frame
	dropdown.set_picking(true)
	click.position = (target + Vector2(3, 3) - preview.camera.position) * preview.camera.zoom
	preview._unhandled_input(click)
	assert_eq(dropdown.get_color(), Color.GREEN)
	assert_eq(
		preview.get_selected_coords(),
		[Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i],
		"picking doesn't select"
	)
	await settle()
	assert_eq(shown(Vector2i(1, 0)).get_pixel(3, 3).a, 0.0, "previews the picked colour")
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA)


func test_clicks_on_the_canvas_select_and_the_preview_follows() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	await settle()
	# Headless windows have no size, so the preview is given one
	main.preview_area.container.stretch = false
	(preview.get_viewport() as SubViewport).size = Vector2i(600, 400)
	preview.fit_to_view()
	var canvas: Vector2 = main.preview_area.stage.get_global_rect().get_center()
	# Middle-dragging pans
	dropdown._input(press(MOUSE_BUTTON_MIDDLE, canvas))
	assert_true(dropdown.is_open(), "stays open")

	var at := func(coord: Vector2i) -> Vector2:
		var world := preview.get_frame_world_rect(coord).get_center()
		return (world - preview.camera.position) * preview.camera.zoom
	# A press at [param point] in the preview, which goes past the panel first, in the window
	var press_on := func(point: Vector2, ctrl := false) -> InputEventMouseButton:
		var down := press(MOUSE_BUTTON_LEFT, main.preview_area.stage.global_position + point)
		down.ctrl_pressed = ctrl
		dropdown._input(down)
		assert_true(dropdown.is_open(), "stays open")
		down.position = point
		preview._unhandled_input(down)
		return down
	var click := func(point: Vector2, ctrl := false) -> void:
		var release := press_on.call(point, ctrl).duplicate() as InputEventMouseButton
		release.pressed = false
		preview._unhandled_input(release)

	click.call(at.call(Vector2i(2, 0)))
	assert_eq(preview.get_selected_coords(), [Vector2i(2, 0)] as Array[Vector2i], "selects")
	await settle()
	assert_eq(color_key.get_target_coords(), [Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(shown(Vector2i(2, 0)).get_pixel(0, 0).a, 0.0, "previewed")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "no longer selected")
	assert_eq(dropdown.note.text, "In 1 selected frames")

	click.call(at.call(Vector2i(1, 0)), true)
	await settle()
	assert_eq(
		color_key.get_target_coords(), [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i], "Ctrl"
	)
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0).a, 0.0)

	# A box from before the first frame to the middle of the second
	var start: Vector2 = at.call(Vector2i(0, 0)) - Vector2(30, 30)
	press_on.call(start)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	for point: Vector2 in [start + Vector2(10, 10), at.call(Vector2i(1, 0))]:
		motion.position = point
		preview._unhandled_input(motion)
	var up := press(MOUSE_BUTTON_LEFT, at.call(Vector2i(1, 0)))
	up.pressed = false
	preview._unhandled_input(up)
	await settle()
	assert_eq(
		color_key.get_target_coords(), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "box"
	)
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0)
	assert_eq(shown(Vector2i(2, 0)).get_pixel(0, 0), Color.MAGENTA)

	# With none selected, every frame is worked on
	preview.select_all(false)
	await settle()
	assert_eq(dropdown.note.text, "In all 3 frames")
	for x in 3:
		assert_eq(shown(Vector2i(x, 0)).get_pixel(0, 0).a, 0.0, "previewed in %d" % x)
	assert_true(dropdown.is_open())
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA, "only previewed")
	dropdown.cancel()


func test_the_tolerance_is_remembered() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	assert_eq(dropdown.get_tolerance(), SheetBackground.DEFAULT_TOLERANCE)
	dropdown.tolerance_field.value = 25
	dropdown.confirm()
	assert_eq(Settings.get_value(&"background_tolerance"), 0.25)
	await settle()
	Settings.set_value(&"background_tolerance", 0.3)
	Actions.run(&"color_key")
	assert_eq(dropdown.get_tolerance(), 0.3, "as Add Spritesheet left it")
	dropdown.cancel()


func test_changes_in_one_frame_are_keyed_once() -> void:
	Actions.run(&"color_key")
	await settle()
	var passes := color_key.passes
	assert_eq(passes, 1, "opening previews")
	# Like dragging in the colour picker
	for i in 20:
		dropdown.set_key(true, Color(1, 0, 1 - i * 0.01), 0.1)
		dropdown.changed.emit()
	await settle()
	assert_eq(color_key.passes, passes + 1, "one keying pass")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 1.0, "the last colour isn't magenta")
	dropdown.set_key(true, Color.MAGENTA, 0.1)
	dropdown.changed.emit()
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0)
	dropdown.cancel()


func test_the_preview_is_at_the_sheets_scale() -> void:
	Global.document.perform("Scale", sheet.set_frame_scale.bind(Vector2(2, 2)))
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	await settle()
	var img := shown(Vector2i(0, 0))
	assert_eq(img.get_size(), Vector2i(16, 16))
	assert_eq(img.get_pixel(1, 1).a, 0.0)
	assert_eq(img.get_pixel(6, 6), Color.RED)
	assert_eq(preview.get_frame_texture(Vector2i(0, 0)).scale, Vector2.ONE)
