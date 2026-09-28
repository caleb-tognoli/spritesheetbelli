extends "res://tests/test_case.gd"
## Remove Background Colour: previewed on the canvas without changing the sheet, removed as
## one step, closed without a trace, and picked from a frame with the eyedropper

var main: Control
var preview: SpritesheetPreview
var sheet: Spritesheet
var dialog: ColorKeyDialog


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	sheet = Global.spritesheet
	dialog = main.color_key_dialog
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


func test_the_preview_leaves_the_sheet_alone() -> void:
	select([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	Global.document.mark_saved()
	var history := Global.document.get_history()
	Actions.run(&"color_key")
	assert_true(dialog.visible)
	assert_eq(dialog.key.get_color(), Color.MAGENTA, "suggests the corner colour")
	assert_false(dialog.key.enabled_check.visible, "nothing to turn off")
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0, "removed in the preview")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(3, 3), Color.RED, "the sprite stays")
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA, "not selected")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA, "the sheet is the same")
	assert_eq(Global.document.get_history(), history, "nothing to undo")
	assert_false(Global.document.is_dirty, "nothing to save")

	# Other frames selected while open are previewed instead
	select([Vector2i(1, 0)] as Array[Vector2i])
	await settle()
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0).a, 0.0)
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "no longer selected")
	select([] as Array[Vector2i])
	await settle()
	assert_true(dialog.remove_button.disabled, "nothing to remove it from")


func test_remove_is_one_step_on_the_selected_frames() -> void:
	select([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	dialog.key.tolerance_field.value = 20
	var steps := Global.document.get_history().size()
	dialog.remove_button.pressed.emit()
	assert_false(dialog.visible, "closes")
	await settle()
	assert_eq(Global.document.get_history().size(), steps + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Remove background")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0).a, 0.0)
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(0, 0).a, 0.0)
	assert_eq(sheet.frames[Vector2i(1, 0)].get_pixel(0, 0), Color.MAGENTA, "not selected")
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(3, 3), Color.BLUE)
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA)
	Global.document.undo()
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA, "undone at once")
	assert_eq(sheet.frames[Vector2i(2, 0)].get_pixel(0, 0), Color.MAGENTA, "undone at once")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "the preview is gone")


func test_cancel_and_escape_show_the_frames_as_they_are() -> void:
	select([Vector2i(0, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0).a, 0.0)
	dialog.cancel_button.pressed.emit()
	assert_false(dialog.visible)
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "restored")
	# Changes made after closing don't bring the preview back
	dialog.key.tolerance_field.value = 30
	await settle()
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA)

	Actions.run(&"color_key")
	await settle()
	dialog.key.set_picking(true)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	dialog._input(escape)
	assert_false(dialog.key.is_picking(), "Escape puts the eyedropper away first")
	assert_true(dialog.visible)
	dialog._input(escape)
	assert_false(dialog.visible, "then closes")
	assert_eq(shown(Vector2i(0, 0)).get_pixel(0, 0), Color.MAGENTA, "restored")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_pixel(0, 0), Color.MAGENTA)


func test_the_eyedropper_picks_from_a_frame_as_it_is() -> void:
	select([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"color_key")
	await settle()
	# Headless windows have no size, so the preview is given one
	main.preview_area.container.stretch = false
	(preview.get_viewport() as SubViewport).size = Vector2i(600, 400)
	preview.fit_to_view()
	dialog.key.set_picking(true)
	assert_true(preview.picking)
	# The magenta corner of the second frame, shown transparent in the preview
	var target := preview.get_frame_world_rect(Vector2i(1, 0)).position + Vector2(0.5, 0.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (target - preview.camera.position) * preview.camera.zoom
	preview._unhandled_input(click)
	assert_eq(dialog.key.get_color(), Color.MAGENTA, "the frame's colour, not the preview's")
	assert_false(dialog.key.is_picking())
	# The green square of the same frame
	dialog.key.set_picking(true)
	click.position = (target + Vector2(3, 3) - preview.camera.position) * preview.camera.zoom
	preview._unhandled_input(click)
	assert_eq(dialog.key.get_color(), Color.GREEN)
	assert_eq(
		preview.get_selected_coords(),
		[Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i],
		"picking doesn't select"
	)
	await settle()
	assert_eq(shown(Vector2i(1, 0)).get_pixel(3, 3).a, 0.0, "previews the picked colour")
	assert_eq(shown(Vector2i(1, 0)).get_pixel(0, 0), Color.MAGENTA)


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
