extends "res://tests/test_case.gd"
## What the status bar says about the cell under the mouse

const PATH := "C:/art/characters/slime/slime_walk_02.png"

var main: Control
var preview: SpritesheetPreview


func before_each() -> void:
	Global.document.reset()
	main = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	preview = main.preview
	var images: Array[Image] = []
	for i in 3:
		images.append(make_image(Color.from_hsv(i / 3.0, 1, 1)))
	var sources: Array[Dictionary] = [{}, {}, FrameSource.for_file(PATH)]
	Global.document.perform(
		"Add", Global.spritesheet.add_frames.bind(images, Spritesheet.AddMode.FIRST_FREE, sources)
	)


func after_each() -> void:
	main.queue_free()
	Global.document.reset()


func test_paths_are_shortened_to_their_folder() -> void:
	assert_eq(PreviewArea.shorten_path(PATH), "slime/slime_walk_02.png")
	assert_eq(PreviewArea.shorten_path("C:/walk.png"), "C:/walk.png", "no folder to show")
	assert_eq(PreviewArea.shorten_path("/walk.png"), "/walk.png")
	assert_eq(PreviewArea.shorten_path("walk.png"), "walk.png")


func test_the_status_bar_shows_a_short_path_and_the_tooltip_the_whole_one() -> void:
	preview._set_hovered_cell(Vector2i(2, 0))
	var text: String = main.cell_info.text
	assert_true(text.ends_with(" · slime/slime_walk_02.png"), text)
	assert_false(PATH in text)
	assert_true(PATH in main.preview_area.container.tooltip_text, "the preview's tooltip")
	Actions.run(&"layout_packed")
	text = main.cell_info.text
	assert_true(text.begins_with("Frame 2"), "follows the layout: " + text)
	assert_true(text.ends_with(" · slime/slime_walk_02.png"), text)


func test_leaving_the_preview_clears_the_cell_info() -> void:
	preview._set_hovered_cell(Vector2i(0, 0))
	assert_true(main.cell_info.text.begins_with("Cell 0"), main.cell_info.text)
	main.preview_area.container.mouse_exited.emit()
	assert_eq(main.cell_info.text, "")
	assert_eq(main.preview_area.container.tooltip_text, "")
	assert_eq(preview.hovered_cell, SpritesheetPreview.NO_CELL)


func test_another_document_clears_the_cell_info() -> void:
	preview._set_hovered_cell(Vector2i(2, 0))
	assert_true("slime_walk" in main.cell_info.text)
	Global.document.mark_saved()
	main.files.new_spritesheet()
	assert_eq(main.cell_info.text, "", "after New")
	assert_eq(preview.hovered_cell, SpritesheetPreview.NO_CELL)


func test_editing_the_hovered_cell_updates_the_cell_info() -> void:
	preview._set_hovered_cell(Vector2i(1, 0))
	assert_true("16×16 px" in main.cell_info.text, main.cell_info.text)
	preview.set_selected_coords([Vector2i(1, 0)] as Array[Vector2i])
	Actions.run(&"delete_frames")
	assert_true(main.cell_info.text.contains("Empty"), "no stale frame: " + main.cell_info.text)
	Global.document.undo()
	assert_true("16×16 px" in main.cell_info.text, "back: " + main.cell_info.text)
