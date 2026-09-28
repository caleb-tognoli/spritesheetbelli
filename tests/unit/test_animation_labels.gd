extends "res://tests/test_case.gd"
## Names of animations on the grid: which shapes get one and where, how overlapping ones
## are told apart, the choices of which to show, and what clicking them does

const Layout := preload("res://ui/spritesheet_preview/animation_label_layout.gd")
const GRID := Vector2i(6, 4)

var main: Control
var sheet: Spritesheet
var preview: SpritesheetPreview
var controls: AnimationLabelControls


func after_each() -> void:
	if main:
		main.queue_free()
		main = null
	Global.document.reset()


## Cells from pairs of numbers: [0, 0, 1, 0] is (0, 0), (1, 0)
static func cells_of(numbers: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in range(0, numbers.size(), 2):
		cells.append(Vector2i(numbers[i], numbers[i + 1]))
	return cells


## The cells of a row from [param from] to [param to], either way
static func row(y: int, from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var step := 1 if to >= from else -1
	for x in range(from, to + step, step):
		cells.append(Vector2i(x, y))
	return cells


static func column(x: int, from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var step := 1 if to >= from else -1
	for y in range(from, to + step, step):
		cells.append(Vector2i(x, y))
	return cells


func shape_of(cells: Array[Vector2i], grid := GRID) -> int:
	return Layout.classify(cells, grid).shape


func assert_run(
	cells: Array[Vector2i], shape: int, side: int, line: int, opens: bool, closes: bool
) -> void:
	var label := Layout.classify(cells, GRID)
	var text := var_to_str(cells)
	assert_eq(label.shape, shape, text)
	assert_eq(label.side, side, text + " side")
	assert_eq(label.line, line, text + " line")
	assert_eq(label.opens, opens, text + " opens")
	assert_eq(label.closes, closes, text + " closes")


func test_repeats_count_once_where_first_shown() -> void:
	assert_eq(Layout.distinct_cells(cells_of([0, 0, 1, 0, 1, 0, 2, 0, 1, 0])), row(0, 0, 2))
	# A ping-pong written out, and a held frame, are still the run 0-5
	var ping_pong := row(1, 0, 5) + row(1, 4, 1)
	assert_run(ping_pong, Layout.Shape.ROW, Layout.Side.LEFT, 1, false, false)
	assert_run(row(1, 0, 3) + row(1, 3, 3), Layout.Shape.ROW, Layout.Side.LEFT, 1, false, true)
	assert_eq(Layout.classify(ping_pong, GRID).cells, row(1, 0, 5), "cells without repeats")


func test_row_runs() -> void:
	assert_run(row(0, 0, 5), Layout.Shape.ROW, Layout.Side.LEFT, 0, false, false)
	assert_run(row(2, 0, 3), Layout.Shape.ROW, Layout.Side.LEFT, 2, false, true)
	assert_run(row(2, 2, 5), Layout.Shape.ROW, Layout.Side.LEFT, 2, true, false)
	assert_run(row(3, 1, 4), Layout.Shape.ROW, Layout.Side.LEFT, 3, true, true)
	# Right to left: named in the right margin, marked where it ends on the left
	assert_run(row(1, 5, 0), Layout.Shape.ROW, Layout.Side.RIGHT, 1, false, false)
	assert_run(row(1, 5, 2), Layout.Shape.ROW, Layout.Side.RIGHT, 1, false, true)
	assert_run(row(1, 3, 0), Layout.Shape.ROW, Layout.Side.RIGHT, 1, true, false)
	# A single frame is a row of one
	assert_run(cells_of([3, 2]), Layout.Shape.ROW, Layout.Side.LEFT, 2, true, true)
	assert_run(cells_of([0, 2]), Layout.Shape.ROW, Layout.Side.LEFT, 2, false, true)


func test_column_runs() -> void:
	assert_run(column(2, 0, 3), Layout.Shape.COLUMN, Layout.Side.TOP, 2, false, false)
	assert_run(column(2, 0, 1), Layout.Shape.COLUMN, Layout.Side.TOP, 2, false, true)
	assert_run(column(4, 1, 2), Layout.Shape.COLUMN, Layout.Side.TOP, 4, true, true)
	assert_run(column(0, 3, 0), Layout.Shape.COLUMN, Layout.Side.BOTTOM, 0, false, false)
	assert_run(column(5, 3, 2), Layout.Shape.COLUMN, Layout.Side.BOTTOM, 5, false, true)
	assert_run(column(5, 2, 0), Layout.Shape.COLUMN, Layout.Side.BOTTOM, 5, true, false)


func test_blocks() -> void:
	# Whole rows of a rectangle, in reading order
	assert_eq(shape_of(row(1, 1, 3) + row(2, 1, 3)), Layout.Shape.BLOCK, "rows")
	assert_eq(shape_of(row(0, 0, 1) + row(1, 0, 1) + row(2, 0, 1)), Layout.Shape.BLOCK, "2×3")
	# Whole columns
	assert_eq(shape_of(column(1, 0, 2) + column(2, 0, 2)), Layout.Shape.BLOCK, "columns")
	# Rows as wide as the grid
	assert_eq(
		shape_of(row(0, 0, 2) + row(1, 0, 2), Vector2i(3, 3)), Layout.Shape.BLOCK, "full rows"
	)
	var label := Layout.classify(row(1, 1, 3) + row(2, 1, 3), GRID)
	assert_eq(label.side, Layout.Side.NONE, "outlined, not in a margin")
	assert_true(Layout.is_outlined(label))


func test_areas() -> void:
	# 8 frames in a 6-column grid wrapped onto the next row
	assert_eq(shape_of(row(0, 0, 5) + row(1, 0, 1)), Layout.Shape.AREA, "wrapping")
	assert_eq(shape_of(row(0, 3, 5) + row(1, 0, 1)), Layout.Shape.AREA, "wrapping from the middle")
	# L-shapes, either way round
	assert_eq(shape_of(row(0, 0, 2) + column(2, 1, 3)), Layout.Shape.AREA, "L")
	assert_eq(shape_of(column(0, 0, 2) + row(2, 1, 3)), Layout.Shape.AREA, "L down then right")
	# Back and forth along rows
	assert_eq(shape_of(row(0, 0, 2) + row(1, 2, 0)), Layout.Shape.AREA, "snaking")
	# Rows of a rectangle that aren't whole or in reading order
	assert_eq(shape_of(row(1, 1, 3) + row(2, 3, 2)), Layout.Shape.AREA, "a row short")
	assert_eq(shape_of(cells_of([0, 0, 1, 0, 1, 1, 0, 1])), Layout.Shape.AREA, "round a square")
	var label := Layout.classify(row(0, 0, 5) + row(1, 0, 1), GRID)
	assert_true(Layout.is_outlined(label))
	assert_eq(Layout.get_slot(label), Vector3i(Layout.Side.NONE, 0, 0), "named at its first frame")


func test_scattered_or_out_of_order_get_none() -> void:
	assert_eq(shape_of([] as Array[Vector2i]), Layout.Shape.NONE, "empty")
	assert_eq(shape_of(cells_of([0, 0, 2, 0])), Layout.Shape.NONE, "a gap")
	assert_eq(shape_of(cells_of([0, 0, 2, 0, 1, 0])), Layout.Shape.NONE, "out of order")
	assert_eq(shape_of(cells_of([1, 0, 0, 0, 2, 0])), Layout.Shape.NONE, "out of order")
	assert_eq(shape_of(cells_of([0, 0, 1, 1])), Layout.Shape.NONE, "diagonal")
	assert_eq(shape_of(cells_of([3, 0, 0, 3])), Layout.Shape.NONE, "far apart")
	assert_eq(shape_of(row(0, 2, 0) + row(1, 2, 0)), Layout.Shape.NONE, "rows right to left")
	assert_eq(shape_of(row(0, 0, 1) + row(0, 3, 4)), Layout.Shape.NONE, "a row with a gap")
	assert_eq(shape_of(row(1, 4, 5) + row(0, 0, 1)), Layout.Shape.NONE, "wrapping backwards")
	assert_eq(shape_of(row(0, 0, 6)), Layout.Shape.NONE, "outside the grid")
	assert_eq(shape_of(row(0, 0, 1), Vector2i.ZERO), Layout.Shape.NONE, "no grid")


## Labels as [method AnimationLabels.update] makes them: classified, in animation order
static func labels_of(animations: Array) -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	for i in animations.size():
		var cells: Array[Vector2i] = []
		cells.assign(animations[i])
		var label := AnimationLabelLayout.classify(cells, GRID)
		label.index = i
		labels.append(label)
	return labels


func test_labels_apart_keep_the_interface_colours() -> void:
	var arranged := Layout.arrange(
		labels_of([row(0, 0, 5), row(1, 0, 5), column(3, 2, 3), row(2, 0, 2) + row(3, 0, 2)])
	)
	for i in arranged.size():
		assert_false(arranged[i].colored, "label %d isn't coloured" % i)
		assert_eq(arranged[i].stack, 0)
		assert_eq(arranged[i].stack_size, 1)
		assert_eq(arranged[i].inset, 0)


func test_labels_in_the_same_margin_stack() -> void:
	# Two runs in the first row, both named in its left margin, and one in the right
	var arranged := Layout.arrange(
		labels_of([row(0, 0, 2), row(0, 3, 5), row(1, 0, 5), row(0, 5, 3), column(1, 2, 3)])
	)
	assert_eq([arranged[0].stack, arranged[0].stack_size], [0, 2], "first above")
	assert_eq([arranged[1].stack, arranged[1].stack_size], [1, 2], "second below")
	assert_true(arranged[0].colored and arranged[1].colored, "both coloured")
	assert_false(arranged[2].colored, "another row")
	# The right-to-left run shares cells with the second run, not its margin
	assert_eq([arranged[3].stack, arranged[3].stack_size], [0, 1])
	assert_true(arranged[3].colored, "shares cells")
	assert_false(arranged[4].colored, "a column elsewhere")
	# Columns named above the same column stack too
	arranged = Layout.arrange(labels_of([column(2, 0, 1), column(2, 2, 3)]))
	assert_eq([arranged[0].stack, arranged[1].stack], [0, 1])
	assert_true(arranged[0].colored and arranged[1].colored)
	# Runs the other way are named in the other margin
	arranged = Layout.arrange(labels_of([column(2, 0, 1), column(2, 3, 2)]))
	assert_false(arranged[0].colored or arranged[1].colored)


func test_outlines_around_the_same_cells_are_inset() -> void:
	var block := row(0, 0, 2) + row(1, 0, 2)
	var wrapped := row(1, 1, 5) + row(2, 0, 1)
	var arranged := Layout.arrange(
		labels_of([block, wrapped, row(0, 1, 2) + row(1, 1, 2), row(3, 0, 5) + row(2, 5, 5), block])
	)
	assert_eq(arranged[0].inset, 0, "first outline")
	assert_eq(arranged[1].inset, 1, "inside the first, whose cells it shares")
	assert_eq(arranged[2].inset, 2, "inside both")
	assert_eq(arranged[3].inset, 0, "shares none with the others")
	assert_eq(arranged[4].inset, 3, "the same cells again")
	assert_true(arranged[0].colored and arranged[1].colored and arranged[2].colored)
	assert_false(arranged[3].colored)
	# Outlines named at the same frame stack their names
	assert_eq([arranged[0].stack, arranged[4].stack, arranged[4].stack_size], [0, 1, 2])
	# An outline that shares no cells with an earlier one takes the first step free
	arranged = Layout.arrange(labels_of([block, row(3, 0, 1) + row(2, 1, 1), wrapped]))
	assert_eq([arranged[0].inset, arranged[1].inset, arranged[2].inset], [0, 0, 1])


func test_runs_and_outlines_sharing_cells_are_coloured() -> void:
	var arranged := Layout.arrange(labels_of([row(0, 0, 5), row(0, 0, 2) + row(1, 0, 2)]))
	assert_true(arranged[0].colored and arranged[1].colored)
	assert_eq(arranged[1].inset, 0, "runs aren't outlined, so the outline isn't inset")


func test_text_is_never_drawn_over_text() -> void:
	var wanted: Array[Rect2] = [
		Rect2(0, 0, 40, 16), Rect2(10, 4, 40, 16), Rect2(100, 0, 20, 16), Rect2(0, 0, 40, 16)
	]
	var away: Array[Vector2] = [Vector2.LEFT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var placed := Layout.place(wanted, away, 2)
	assert_eq(placed[0], wanted[0], "the first stays")
	assert_eq(placed[1], Rect2(-42, 4, 40, 16), "moved left, past the first")
	assert_eq(placed[2], wanted[2], "room where it is")
	assert_eq(placed[3], Rect2(0, 18, 40, 16), "moved down past the first")
	for i in placed.size():
		for j in i:
			assert_false(placed[i].intersects(placed[j]), "%d and %d apart" % [i, j])
	# Without room, it isn't drawn
	var crowded := Layout.place(
		[Rect2(0, 0, 40, 16), Rect2(0, 0, 40, 16)] as Array[Rect2],
		[Vector2.RIGHT, Vector2.RIGHT] as Array[Vector2],
		2,
		0
	)
	assert_false(crowded[1].has_area())


func test_tooltip() -> void:
	var tooltip_sheet := Spritesheet.new()
	tooltip_sheet.set_grid_size(GRID)
	for cell in row(0, 0, 5):
		tooltip_sheet.set_frame(cell, make_image(Color.RED))
	var animation := SheetAnimation.create("walk", row(0, 0, 5))
	tooltip_sheet.add_animation(animation)
	animation.fps = 7.5
	animation.mode = SheetAnimation.Mode.PING_PONG
	animation.cells = row(0, 0, 0)
	tooltip_sheet.add_animation(animation)
	assert_eq(AnimationLabels.describe(tooltip_sheet, 0), "6 frames · 12 fps · loop")
	assert_eq(AnimationLabels.describe(tooltip_sheet, 1), "1 frame · 7.5 fps · ping-pong")


## The main window with a 6×4 sheet: walk in the first row, jump down the fourth column,
## hurt in the corner and a scattered one, which can't be named
func open_main() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	sheet = Global.spritesheet
	preview = main.preview
	controls = main.preview_area.label_controls
	Global.document.perform(
		"Add",
		func() -> void:
			sheet.set_grid_size(GRID)
			for y in GRID.y:
				for x in GRID.x:
					sheet.set_frame(Vector2i(x, y), make_image(Color.RED))
			sheet.add_animation(SheetAnimation.create("walk", row(0, 0, 3)))
			sheet.add_animation(SheetAnimation.create("jump", column(4, 1, 3)))
			sheet.add_animation(SheetAnimation.create("hurt", cells_of([5, 3, 5, 2, 4, 0])))
			sheet.add_animation(SheetAnimation.create("scattered", cells_of([0, 3, 2, 1])))
	)
	# After the view fits the new frames, the grid starts 100 px from the view's corner
	await get_tree().process_frame
	preview.camera.position = Vector2(-25, -25)
	preview.set_zoom(4)


func labelled_names() -> Array:
	return preview.animation_labels.labels.map(func(label: Dictionary) -> String: return label.name)


func test_choices_of_labels() -> void:
	await open_main()
	assert_eq(labelled_names(), ["walk", "jump"], "the scattered ones aren't named")
	assert_eq(AnimationLabels.get_labelled(sheet), [0, 1] as Array[int])
	controls.set_label_shown(0, false)
	assert_false(sheet.animations[0].show_label)
	assert_eq(labelled_names(), ["jump"], "hidden")
	assert_eq(Global.document.get_history()[-1], "Hide label")
	Global.document.undo()
	assert_eq(labelled_names(), ["walk", "jump"], "undone")
	# The flyover's eyes
	controls.open_flyover()
	assert_true(controls.flyover.visible)
	var rows := controls.list.get_children()
	assert_eq(rows.map(func(entry: Button) -> String: return entry.text), ["walk", "jump"])
	(rows[1] as Button).pressed.emit()
	assert_eq(labelled_names(), ["walk"], "jump hidden from the flyover")
	var eye: Button = controls.list.get_child(1)
	assert_eq(eye.icon, AnimationLabelControls.HIDDEN_ICON, "its eye is closed")
	eye.pressed.emit()
	assert_eq(labelled_names(), ["walk", "jump"], "shown again")
	assert_true(controls.left_out.visible, "says two can't be named")
	assert_true(controls.left_out.text.begins_with("2 "))
	controls.flyover.hide()
	controls.show_all(false)
	assert_eq(labelled_names(), [], "all hidden")
	controls.show_all(true)
	assert_eq(labelled_names(), ["walk", "jump"], "all shown")
	# Only the one playing in the animation panel
	controls.set_playing_only(true)
	assert_eq(labelled_names(), [], "nothing plays")
	main.animation_panel.select_animation(1)
	await get_tree().process_frame
	assert_eq(labelled_names(), ["jump"], "the playing one")
	controls.show_all(true)
	assert_false(sheet.label_playing_only, "Show all names the chosen ones again")
	# Nothing in the packed layout, where the button isn't shown
	Global.document.perform("Packed", sheet.set_layout.bind(Spritesheet.Layout.PACKED))
	assert_eq(labelled_names(), [], "packed")
	assert_false(controls.button.visible)
	assert_false(Actions.is_available(&"animation_labels"))
	Global.document.undo()
	assert_true(controls.button.visible, "back in the grid")
	assert_true(Actions.is_enabled(&"animation_labels"))


func test_choices_are_saved_with_the_project() -> void:
	var saved := Spritesheet.new()
	saved.set_grid_size(GRID)
	for cell in row(0, 0, 5):
		saved.set_frame(cell, make_image(Color.RED))
	var shown := SheetAnimation.create("walk", row(0, 0, 2))
	var hidden := SheetAnimation.create("run", row(0, 3, 5))
	hidden.show_label = false
	saved.add_animation(shown)
	saved.add_animation(hidden)
	saved.set_label_playing_only(true)
	var path := temp_path("labels.sbelli")
	assert_eq(ProjectFile.save(saved, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_true(loaded.animations[0].show_label)
	assert_false(loaded.animations[1].show_label)
	assert_true(loaded.label_playing_only)
	saved.set_label_playing_only(false)
	assert_eq(ProjectFile.save(saved, path), OK)
	loaded.set_state(ProjectFile.load(path).state)
	assert_false(loaded.label_playing_only)
	DirAccess.remove_absolute(path)
	# Mirrored copies show their name
	assert_true(sheet_with_mirror(hidden).animations[1].show_label)


static func sheet_with_mirror(animation: SheetAnimation) -> Spritesheet:
	var mirrored := Spritesheet.new()
	mirrored.set_grid_size(GRID)
	for cell in animation.cells:
		mirrored.set_frame(cell, make_image(Color.RED))
	mirrored.add_animation(animation)
	SheetAnimation.mirror(mirrored, 0)
	return mirrored


func mouse(
	position: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true, double := false
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.double_click = double
	event.position = position
	preview._unhandled_input(event)


func test_clicking_a_name() -> void:
	await open_main()
	var labels := preview.animation_labels
	labels.place_tags(preview)
	var walk := labels.get_tag_rect(0)
	assert_true(walk.has_area(), "walk is named")
	assert_true(walk.end.x < 100, "in the left margin")
	var jump := labels.get_tag_rect(1)
	assert_true(jump.end.y < 100, "jump is named above the grid")
	assert_eq(labels.get_label_at(walk.get_center()), 0)
	# Hovering highlights it and tells what it is
	var motion := InputEventMouseMotion.new()
	motion.position = walk.get_center()
	preview._unhandled_input(motion)
	assert_eq(labels.hovered, 0)
	assert_eq(main.preview_area.container.tooltip_text, "4 frames · 12 fps · loop")
	# Clicking selects its frames and plays it
	mouse(walk.get_center())
	mouse(walk.get_center(), MOUSE_BUTTON_LEFT, false)
	assert_eq(preview.get_selected_coords(), row(0, 0, 3))
	assert_eq(main.animation_panel.get_selected(), 0)
	# Double-clicking renames it
	mouse(walk.get_center(), MOUSE_BUTTON_LEFT, true, true)
	assert_true(controls.rename_edit.visible, "renaming")
	assert_eq(controls.rename_edit.text, "walk")
	controls.rename_edit.text = "stroll"
	controls.rename_edit.text_submitted.emit("stroll")
	assert_false(controls.rename_edit.visible)
	assert_eq(sheet.animations[0].name, "stroll")
	assert_eq(Global.document.get_history()[-1], "Rename animation")
	# Right-clicking opens its menu instead of the preview's
	labels.place_tags(preview)
	mouse(jump.get_center(), MOUSE_BUTTON_RIGHT)
	mouse(jump.get_center(), MOUSE_BUTTON_RIGHT, false)
	assert_true(controls.menu.visible, "the name's menu")
	assert_eq(preview.get_selected_coords(), row(0, 0, 3), "the selection stays")
	controls.menu.id_pressed.emit(AnimationLabelControls.Item.HIDE)
	controls.menu.hide()
	assert_eq(labelled_names(), ["stroll"], "jump's name hidden")
	# Speed and type from the menu
	controls.open_menu(0, Vector2.ZERO)
	controls.speed_menu.index_pressed.emit(AnimationLabelControls.SPEEDS.find(24.0))
	controls.type_menu.id_pressed.emit(SheetAnimation.Mode.ONCE)
	controls.menu.hide()
	assert_eq(sheet.animations[0].fps, 24.0)
	assert_eq(sheet.animations[0].mode, SheetAnimation.Mode.ONCE)
	# Delete, through the animation panel
	controls.open_menu(1, Vector2.ZERO)
	controls.menu.id_pressed.emit(AnimationLabelControls.Item.DELETE)
	controls.menu.hide()
	assert_eq(sheet.animations.size(), 3)
	assert_eq(sheet.animations[1].name, "hurt")


func test_names_are_never_over_frame_numbers() -> void:
	await open_main()
	Settings.set_value(&"show_indices", true)
	# An outline around the whole second row, named at its first frame
	Global.document.perform(
		"Animation",
		sheet.add_animation.bind(SheetAnimation.create("idle", row(1, 0, 5) + row(2, 0, 0)))
	)
	var labels := preview.animation_labels
	labels.place_tags(preview)
	var idle := labels.get_tag_rect(4)
	assert_true(idle.has_area(), "idle is named")
	# Its name stands on the top edge of its first frame, over the frame above
	var first := AnimationLabels.to_screen_rect(preview, preview.cell_rect(Vector2i(0, 1)))
	assert_true(absf(idle.end.y - first.position.y) <= 2, "on the edge")
	assert_true(labels.covers(idle))
	assert_false(labels.covers(Rect2(first.get_center(), Vector2.ONE)), "not over the frame")


func test_fit_leaves_room_for_names() -> void:
	await open_main()
	preview.fit_to_view()
	var labels := preview.animation_labels
	labels.place_tags(preview)
	var view := Rect2(Vector2.ZERO, preview.get_viewport_rect().size)
	for index: int in [0, 1]:
		assert_true(view.encloses(labels.get_tag_rect(index)), "name %d in view" % index)
