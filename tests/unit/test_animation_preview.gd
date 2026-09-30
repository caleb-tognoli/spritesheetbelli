extends "res://tests/test_case.gd"
## The animation panel under the preview: collapsing, its height, the list, the preview's
## controls and editing in the details

## Settings the panel remembers, put back after each test
const PANEL_SETTINGS: Array[StringName] = [
	&"animation_panel",
	&"bottom_dock_height",
	&"animation_preview_width",
	&"animation_list_width",
	&"animation_frames_text",
	&"animation_background",
	&"animation_background_color",
	&"pixel_perfect_zoom",
]

var main: Control
var panel: AnimationPanel
var animation: AnimationPreview


func before_each() -> void:
	Settings.set_value(&"animation_panel", "open")
	await open_main()
	var imgs: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		imgs.append(make_image(color))
	Global.document.perform("Add", Global.spritesheet.add_frames.bind(imgs))


func open_main() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	panel = main.animation_panel
	animation = panel.animation_preview


func after_each() -> void:
	main.queue_free()
	Global.document.reset()
	for key in PANEL_SETTINGS:
		Settings.set_value(key, Settings.DEFAULTS[key])


func layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## Adds an animation of [param cells] called [param anim_name]
func add_animation(anim_name: String, cells: Array[Vector2i], fps := 12.0) -> SheetAnimation:
	var added := SheetAnimation.create(anim_name, cells, fps)
	Global.document.perform("New animation", Global.spritesheet.add_animation.bind(added))
	return added


func test_p_hides_and_shows_it() -> void:
	var events := InputMap.action_get_events(&"toggle_animation")
	assert_eq((events[0] as InputEventKey).keycode, KEY_P)
	var dock := panel.dock
	assert_true(panel.is_expanded())
	assert_true(Actions.is_checked(&"toggle_animation"))
	assert_true(panel.dock_button.button_pressed, "its dock button is pressed")
	assert_eq(panel.dock_button.text, "Animation")
	await layout()
	var tall := dock.size.y
	var row := dock.bar.get_combined_minimum_size().y
	Actions.run(&"toggle_animation")
	await layout()
	assert_false(panel.is_expanded())
	assert_false(panel.visible, "hidden")
	assert_false(panel.dock_button.button_pressed)
	assert_true(dock.bar.is_visible_in_tree(), "the row of buttons stays")
	assert_eq(dock.size.y, row, "only the row")
	assert_false(Actions.is_checked(&"toggle_animation"), "unchecked in the menu")
	assert_eq(Settings.get_value(&"animation_panel"), "closed", "remembered")
	panel.dock_button.button_pressed = true
	await layout()
	assert_true(panel.is_expanded(), "its button shows it again")
	assert_eq(dock.size.y, tall, "as tall as before")
	assert_eq(Settings.get_value(&"animation_panel"), "open")
	panel.dock_button.button_pressed = false
	assert_false(panel.is_expanded(), "and pressing it again hides it")
	assert_false(main.preview_area._action_buttons.has(&"toggle_animation"), "not in the toolbar")


func test_one_dock_shows_at_a_time() -> void:
	var dock := panel.dock
	var other := Control.new()
	var button := dock.add_dock(other, "Other")
	assert_eq(button.get_index(), panel.dock_button.get_index() + 1, "in the row")
	assert_false(other.visible)
	button.button_pressed = true
	assert_eq(dock.get_shown(), other)
	assert_true(other.visible)
	assert_false(panel.visible, "in place of the animation panel")
	assert_false(panel.dock_button.button_pressed)
	assert_eq(Settings.get_value(&"animation_panel"), "closed")
	Actions.run(&"toggle_animation")
	assert_true(panel.visible)
	assert_false(other.visible)
	assert_false(button.button_pressed)
	panel.set_expanded(false)
	assert_eq(dock.get_shown(), null, "none")


func test_dock_button_has_an_icon_and_room() -> void:
	var dock := panel.dock
	var button := panel.dock_button
	assert_eq(button.icon, AnimationPanel.ANIMATION_ICON, "the Animation menu's icon")
	assert_eq(button.theme_type_variation, &"DockButton")
	var box := button.get_theme_stylebox("normal")
	var tool_box := panel.get_theme_stylebox("normal", &"ToolbarButton")
	assert_true(box.content_margin_left > tool_box.content_margin_left, "more room than a tool")
	await layout()
	var shown_gap := dock.bar.global_position.y - panel.get_global_rect().end.y
	assert_eq(shown_gap, float(BottomDock.GAP), "room between the dock and its button")
	panel.set_expanded(false)
	await layout()
	var bar_panel: Control = dock.bar.get_parent().get_parent()
	assert_eq(dock.bar.global_position.y, bar_panel.global_position.y, "none without a dock")


func test_hidden_until_the_sheet_has_animations() -> void:
	main.queue_free()
	Settings.set_value(&"animation_panel", "auto")
	await open_main()
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind([make_image(Color.RED)] as Array[Image])
	)
	assert_false(panel.is_expanded(), "hidden at first")
	assert_true(panel.dock.bar.is_visible_in_tree(), "with its button in the row")
	assert_eq(Settings.get_value(&"animation_panel"), "auto")
	add_animation("walk", [Vector2i(0, 0)] as Array[Vector2i])
	assert_true(panel.is_expanded(), "opens with the first animation")
	assert_eq(Settings.get_value(&"animation_panel"), "open")
	panel.toggle()
	add_animation("run", [Vector2i(0, 0)] as Array[Vector2i])
	assert_false(panel.is_expanded(), "only once: then it stays as it was left")


func test_height_is_clamped_and_remembered() -> void:
	await layout()
	var dock := panel.dock
	var split: SplitContainer = dock.get_parent()
	var half := int(panel.get_viewport_rect().size.y / 2)
	assert_eq(dock.get_max_height(), half)
	assert_eq(dock.size.y, float(Settings.get_value(&"bottom_dock_height")))
	split.split_offset = -200
	split.drag_ended.emit()
	assert_eq(Settings.get_value(&"bottom_dock_height"), 200)
	split.split_offset = -half - 100
	split.dragged.emit(split.split_offset)
	assert_eq(split.split_offset, -half, "no taller than half the window")
	split.drag_ended.emit()
	assert_eq(Settings.get_value(&"bottom_dock_height"), half)
	split.split_offset = -40
	split.drag_ended.emit()
	assert_eq(Settings.get_value(&"bottom_dock_height"), BottomDock.MIN_HEIGHT)
	await layout()
	assert_eq(dock.size.y, float(BottomDock.MIN_HEIGHT), "no shorter than the smallest")
	Settings.set_value(&"bottom_dock_height", 5000)
	dock.apply_height()
	assert_eq(dock.get_height(), half, "a remembered height fits the window")


func test_preview_is_square_until_dragged() -> void:
	await layout()
	var columns := panel.columns
	assert_eq(columns.split_offset, roundi(columns.size.y), "as wide as it's tall")
	columns.split_offset = 400
	columns.drag_ended.emit()
	assert_eq(Settings.get_value(&"animation_preview_width"), 400)
	await layout()
	assert_eq(animation.size.x, 400.0)


## Plays one frame's worth of time
func advance() -> void:
	animation.player._process(1.0 / animation.player.fps + 0.0001)


func current() -> Vector2i:
	return animation.player.get_current_cell()


func test_loops_through_all_frames() -> void:
	var seen: Array[Vector2i] = [current()]
	for i in 3:
		advance()
		seen.append(current())
	assert_eq(
		seen, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i]
	)


func test_ping_pong() -> void:
	animation.player.mode = SheetAnimation.Mode.PING_PONG
	var seen: Array[int] = []
	for i in 5:
		advance()
		seen.append(current().x)
	assert_eq(seen, [1, 2, 1, 0, 1] as Array[int])


func test_once_stops_at_the_end() -> void:
	animation.player.mode = SheetAnimation.Mode.ONCE
	for i in 5:
		advance()
	assert_eq(current(), Vector2i(2, 0))
	assert_false(animation.player.playing)
	animation.player.play_button.pressed.emit()
	assert_eq(current(), Vector2i(0, 0), "playing again starts over")


func test_pause_and_back_to_start() -> void:
	advance()
	advance()
	animation.player.play_button.pressed.emit()
	assert_false(animation.player.playing, "paused")
	advance()
	assert_eq(current(), Vector2i(2, 0), "stays while paused")
	animation.player.play_button.pressed.emit()
	advance()
	assert_eq(current(), Vector2i(0, 0), "resumes where it was")
	advance()
	animation.player.start_button.pressed.emit()
	assert_eq(current(), Vector2i(0, 0))
	assert_true(animation.player.playing, "keeps playing from the start")


func test_previous_and_next_frame_stop_playing() -> void:
	animation.player.next_button.pressed.emit()
	assert_eq(current(), Vector2i(1, 0))
	assert_false(animation.player.playing)
	animation.player.previous_button.pressed.emit()
	animation.player.previous_button.pressed.emit()
	assert_eq(current(), Vector2i(2, 0), "wraps around")


func test_scrub_sets_the_frame() -> void:
	var player := animation.player
	var scrub := player.scrub
	assert_eq(scrub.max_value, 2.0, "a step per frame")
	scrub.drag_started.emit()
	assert_false(player.playing, "paused while dragging")
	scrub.value = 2
	assert_eq(current(), Vector2i(2, 0))
	assert_eq(player.counter.text, "3 / 3")
	scrub.drag_ended.emit(true)
	assert_true(player.playing, "plays on after")
	advance()
	assert_eq(scrub.value, 0.0, "follows the playing")


func test_plays_only_selected_frames() -> void:
	assert_eq(panel.list.get_item_text(0), "All frames", "nothing selected")
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(panel.list.get_item_text(0), "Selected frames")
	advance()
	assert_eq(current(), Vector2i(2, 0))
	advance()
	assert_eq(current(), Vector2i(0, 0))


func test_choosing_in_the_list_plays_it() -> void:
	var walk := add_animation("walk", [Vector2i(2, 0), Vector2i(1, 0)] as Array[Vector2i], 5)
	assert_eq(panel.list.item_count, 2, "the frames and walk")
	assert_eq(panel.list.get_item_text(1), "walk")
	panel.list.select(1)
	panel.list.item_selected.emit(1)
	assert_eq(animation.get_animation_index(), 0)
	assert_eq(animation.player.fps, 5.0)
	assert_eq(animation.player.get_cells(), walk.cells)
	assert_eq(panel.detail.name_edit.text, "walk", "shown in the details")
	panel.list.select(0)
	panel.list.item_selected.emit(0)
	assert_eq(animation.get_animation_index(), -1)
	assert_eq(animation.player.get_cells().size(), 3, "every frame again")
	assert_true(panel.detail.empty_hint.visible, "nothing to edit")


func test_edit_opens_the_details() -> void:
	panel.set_expanded(false)
	add_animation("walk", [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(Actions.get_action(&"edit_animations").label, "Edit")
	Actions.run(&"edit_animations")
	assert_true(panel.is_expanded())
	assert_eq(panel.detail.get_animation_index(), 0, "the first animation")
	assert_true(panel.detail.name_edit.has_focus())


func test_zoom_and_pan() -> void:
	Settings.set_value(&"pixel_perfect_zoom", "on")
	await layout()
	var stage := animation.player.stage
	assert_eq(stage.content_size, Vector2i(16, 16))
	assert_true(stage.fitted)
	assert_eq(stage.zoom, stage.get_fit_zoom())
	assert_eq(stage.zoom, roundf(stage.zoom), "fits by whole zooms")
	var fit_zoom := stage.zoom
	stage.zoom_by_notches(1)
	var speed: float = Settings.get_value(&"zoom_speed")
	assert_eq(stage.zoom, PixelZoom.step(fit_zoom, 1 + speed), "a whole step")
	assert_false(stage.fitted)
	for i in 10:
		stage.zoom_by_notches(1)
	assert_true(stage.can_pan(), "bigger than the stage")
	var before := stage.get_frame_rect(stage.texture)
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_LEFT
	drag.pressed = true
	stage._gui_input(drag)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 5)
	stage._gui_input(motion)
	assert_eq(stage.get_frame_rect(stage.texture).position, before.position + Vector2(10, 5))
	motion.relative = Vector2(100000, 0)
	stage._gui_input(motion)
	assert_eq(stage.get_frame_rect(stage.texture).position.x, 0.0, "never past the edge")
	animation.player.fit_button.pressed.emit()
	assert_eq(stage.zoom, fit_zoom, "fitted again")
	assert_true(stage.fitted)


func test_zoom_steps_in_screen_pixels_with_the_interface_scaled() -> void:
	Settings.set_value(&"pixel_perfect_zoom", "on")
	Settings.set_value(&"ui_scale", 1.5)
	await layout()
	var stage := animation.player.stage
	assert_true(stage.fitted)
	var on_screen := stage.zoom * 1.5
	assert_true(absf(on_screen - roundf(on_screen)) < 0.001, "fits at whole screen pixels")
	assert_true(stage.zoom * 16 <= stage.size.x and stage.zoom * 16 <= stage.size.y, "fits")
	var fit_zoom := stage.zoom
	stage.zoom_by_notches(1)
	var speed: float = Settings.get_value(&"zoom_speed")
	assert_true(absf(stage.zoom - PixelZoom.step(fit_zoom, 1 + speed, 1.5)) < 0.001, "a step")
	on_screen = stage.zoom * 1.5
	assert_true(absf(on_screen - roundf(on_screen)) < 0.001, "at whole screen pixels")
	stage.zoom_by_notches(-1)
	assert_true(absf(stage.zoom - fit_zoom) < 0.001, "and back")
	Settings.set_value(&"ui_scale", Settings.DEFAULTS[&"ui_scale"])


func test_background_choice() -> void:
	var player := animation.player
	var stage := player.stage
	assert_eq(stage.background, FrameStage.Background.CHECKERBOARD)
	var menu := player.background_button.get_popup()
	menu.id_pressed.emit(2)
	assert_eq(stage.background, FrameStage.Background.EXPORT)
	assert_eq(Settings.get_value(&"animation_background"), "export", "remembered")
	var sheet := Global.spritesheet
	var settings := sheet.export_settings.duplicate()
	settings.background = Color.YELLOW
	Global.document.perform("Export", sheet.set_export_settings.bind(settings))
	assert_eq(stage.export_color, Color.YELLOW, "the export's own")
	menu.id_pressed.emit(1)
	assert_eq(stage.background, FrameStage.Background.COLOR)
	assert_true(player.color_popup.visible, "a colour to pick")
	player.color_picker.color_changed.emit(Color.BLUE)
	assert_eq(stage.background_color, Color.BLUE)
	player.color_popup.hide()


func test_editing_in_the_details() -> void:
	var window: AnimationDetail = panel.detail
	var sheet := Global.spritesheet
	main.preview.set_selected_coords([Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_true(window.empty_hint.visible, "no animations yet")
	panel.new_button.pressed.emit()
	assert_eq(sheet.animations.size(), 1)
	assert_eq(sheet.animations[0].cells, [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(panel.list.get_selected_items(), [1] as PackedInt32Array, "chosen in the list")
	assert_eq(animation.get_animation_index(), 0, "and played")
	assert_eq(window.frames_edit.text, "1, 2")
	window.frames_edit.text = "2-0, 2"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i],
		"frames by number, in the typed order"
	)
	assert_eq(animation.player.get_cells().size(), 4, "the preview follows")
	window.frames_edit.text = "1, oops"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_true("oops" in window.frames_info.text, "explains what it couldn't read")
	assert_eq(sheet.animations[0].cells.size(), 4, "unchanged")
	window.fps_spin.value = 20
	window.mode_option.select(window.mode_option.get_item_index(SheetAnimation.Mode.PING_PONG))
	window.mode_option.item_selected.emit(window.mode_option.selected)
	assert_eq(sheet.animations[0].fps, 20.0)
	assert_eq(sheet.animations[0].mode, SheetAnimation.Mode.PING_PONG)
	window.name_edit.text = "run"
	window.name_edit.text_submitted.emit("run")
	assert_eq(sheet.animations[0].name, "run")
	assert_eq(panel.list.get_item_text(1), "run", "renamed in the list")
	Global.document.undo()
	assert_eq(sheet.animations[0].name, "animation", "undoable")
	assert_eq(window.name_edit.text, "animation")
	Global.document.undo()
	assert_eq(sheet.animations[0].mode, SheetAnimation.Mode.LOOP, "each edit a step")
	panel.mirror_button.pressed.emit()
	assert_eq(sheet.animations.size(), 2, "mirrored")
	assert_eq(window.get_animation_index(), 1, "the copy is chosen")
	panel.delete_button.pressed.emit()
	assert_eq(sheet.animations.size(), 1)
	assert_eq(window.get_animation_index(), 0, "the one before it")
	panel.delete_button.pressed.emit()
	assert_true(sheet.animations.is_empty())
	assert_eq(animation.get_animation_index(), -1, "the frames play again")


func test_list_buttons() -> void:
	await layout()
	assert_eq(panel.new_button.get_parent().get_index(), 0, "New at the top of the list")
	var buttons: Array[Button] = [panel.duplicate_button, panel.mirror_button, panel.delete_button]
	for button in buttons:
		assert_eq(button.get_parent(), panel.new_button.get_parent(), "next to New")
		assert_false(button.visible, "only for an animation")
		assert_ne(button.tooltip_text, "")
	var row := panel.new_button.get_parent() as Control
	var width := row.get_combined_minimum_size().x
	panel.new_button.pressed.emit()
	for button in buttons:
		assert_true(button.is_visible_in_tree())
	assert_eq(row.get_combined_minimum_size().x, width, "the list keeps its width")
	assert_false("mirror_button" in panel.detail, "not in the details")
	assert_false("add_button" in panel.detail, "frames are dragged to the timeline instead")
	panel.list.select(0)
	panel.list.item_selected.emit(0)
	for button in buttons:
		assert_false(button.visible, "not for the frames")


func test_duplicate() -> void:
	var sheet := Global.spritesheet
	var walk := SheetAnimation.create(
		"walk", [Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i], 8
	)
	walk.durations = [2.0, 1.0] as Array[float]
	walk.mode = SheetAnimation.Mode.PING_PONG
	Global.document.perform("New animation", sheet.add_animation.bind(walk))
	panel.select_animation(0)
	var steps := Global.document.undo_redo.get_history_count()
	panel.duplicate_button.pressed.emit()
	assert_eq(sheet.animations.size(), 2)
	assert_eq(Global.document.undo_redo.get_history_count(), steps + 1, "one step")
	assert_eq(Global.document.get_history()[-1], "Duplicate animation")
	var copy := sheet.animations[1]
	assert_eq(copy.name, "walk_2", "a name of its own")
	assert_eq(copy.cells, walk.cells, "the same frames")
	assert_eq(copy.durations, walk.durations)
	assert_eq(copy.fps, 8.0)
	assert_eq(copy.mode, SheetAnimation.Mode.PING_PONG)
	assert_ne(copy.color, sheet.animations[0].color, "a colour of its own")
	assert_eq(panel.get_selected(), 1, "the copy is chosen")
	assert_eq(panel.detail.name_edit.text, "walk_2")
	panel.duplicate_button.pressed.emit()
	assert_eq(sheet.animations[2].name, "walk_3", "a copy of walk_2 counts on")
	Global.document.undo()
	Global.document.undo()
	assert_eq(sheet.animations.size(), 1, "undone")
	assert_eq(panel.get_selected(), 0)
	assert_eq(Actions.get_action(&"duplicate_animation").label, "Duplicate Animation")
	assert_true(Actions.run(&"duplicate_animation"), "also in the Animation menu")
	assert_eq(sheet.animations.size(), 2)


func test_preview_fits_its_buttons_on_one_row() -> void:
	await layout()
	var controls := animation.player.controls
	var width := 0.0
	for child: Control in controls.get_children():
		width += child.get_combined_minimum_size().x
	assert_true(width > 0)
	assert_true(animation.get_combined_minimum_size().x >= width, "never narrower than them")
	panel.columns.split_offset = 10
	panel.columns.drag_ended.emit()
	await layout()
	assert_true(animation.size.x >= width, "even dragged narrow")
	var first := controls.get_child(0) as Control
	for child: Control in controls.get_children():
		assert_eq(child.position.y, first.position.y, "one row")


func test_frames_past_the_end_are_outside_the_sheet() -> void:
	var window: AnimationDetail = panel.detail
	var sheet := Global.spritesheet
	# A 4×1 grid with an empty cell at the end
	Global.document.perform("Grid", sheet.set_grid_size.bind(Vector2i(4, 1)))
	panel.new_button.pressed.emit()
	window.frames_edit.text = "0-3"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_true("1 empty cell is skipped" in window.frames_info.text, window.frames_info.text)
	assert_false("outside" in window.frames_info.text)
	window.frames_edit.text = "0, 1, 8, 9"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_true("2 are outside the sheet" in window.frames_info.text, window.frames_info.text)
	assert_false("empty" in window.frames_info.text, "not empty cells")
	window.frames_edit.text = "3, 9"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_true(
		"(1 empty cell is skipped, 1 is outside the sheet)" in window.frames_info.text,
		window.frames_info.text
	)


func test_onion_skin_shows_the_previous_frame() -> void:
	var sheet := Spritesheet.new()
	for i in 3:
		sheet.add_frames([make_image(Color(i / 3.0, 0, 0))] as Array[Image])
	var player := FramePlayer.new()
	add_child(player)
	player.sheet = sheet
	player.set_cells(sheet.get_sorted_coords())
	assert_eq(player.get_previous_cell(), Vector2i(2, 0), "loops back to the last frame")
	player.mode = SheetAnimation.Mode.ONCE
	assert_eq(player.get_previous_cell(), Spritesheet.NO_CELL, "nothing before the start")
	player.step(1)
	assert_eq(player.get_previous_cell(), Vector2i(0, 0))

	Settings.set_value(&"onion_skin", true)
	assert_true(player.onion_button.button_pressed, "follows the setting")
	assert_true(player.stage.onion != null, "previous frame shown")
	player.onion_button.button_pressed = false
	assert_true(player.stage.onion == null, "hidden again")
	assert_false(Settings.get_value(&"onion_skin"), "remembered")
	player.queue_free()


func test_frames_are_shown_by_name_when_they_have_one() -> void:
	var sheet := Global.spritesheet
	sheet.rename_frame(Vector2i(1, 0), "idle")
	var window: AnimationDetail = panel.detail
	main.preview.set_selected_coords([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	panel.new_button.pressed.emit()
	assert_eq(window.frames_edit.text, "0, idle", "no toggle: names always")
	window.frames_edit.text = "idle, 2, 0"
	window.frames_edit.text_submitted.emit(window.frames_edit.text)
	assert_eq(
		sheet.animations[0].cells,
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)] as Array[Vector2i],
		"names and numbers both read"
	)
	assert_false("names_button" in window)
