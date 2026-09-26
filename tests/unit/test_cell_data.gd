extends "res://tests/test_case.gd"
## What cells hold besides their frames: pivots, and everything moving along with frames

const FIRST := Vector2i(0, 0)
const SECOND := Vector2i(1, 0)

var sheet: Spritesheet
var dir := OS.get_user_data_dir().path_join("tests/cell_data")


func before_each() -> void:
	sheet = Spritesheet.new()
	DirAccess.make_dir_recursive_absolute(dir)


func add_two() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.GREEN)] as Array[Image])


func test_frames_are_centred_without_a_pivot() -> void:
	sheet.set_frame(FIRST, make_image(Color.RED, Vector2i(10, 6)))
	assert_false(sheet.has_pivot(FIRST))
	assert_eq(sheet.get_pivot(FIRST), Vector2(5, 3))
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(2, 6))
	assert_true(sheet.has_pivot(FIRST))
	assert_eq(sheet.get_pivot(FIRST), Vector2(2, 6))
	sheet.set_pivots([FIRST] as Array[Vector2i], null)
	assert_false(sheet.has_pivot(FIRST), "taken away")


func test_pivots_follow_their_frames() -> void:
	add_two()
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(1, 2))
	sheet.move_frames([FIRST] as Array[Vector2i], Vector2i(0, 1))
	assert_eq(sheet.get_pivot(Vector2i(0, 1)), Vector2(1, 2), "moved")
	sheet.move_frame(Vector2i(0, 1), SECOND)
	assert_eq(sheet.get_pivot(SECOND), Vector2(1, 2), "swapped")
	assert_false(sheet.has_pivot(Vector2i(0, 1)), "the other frame has none")
	# The grid is 2x2 now, so inserting a cell moves the frame to the next row
	sheet.insert_empty_cell(FIRST)
	assert_eq(sheet.get_pivot(Vector2i(0, 1)), Vector2(1, 2), "inserted cell")
	sheet.insert_row(0)
	assert_eq(sheet.get_pivot(Vector2i(0, 2)), Vector2(1, 2), "inserted row")
	sheet.remove_frames([Vector2i(0, 2)] as Array[Vector2i])
	assert_false(sheet.has_pivot(Vector2i(0, 2)), "removed")


func test_pivots_turn_with_their_frames() -> void:
	sheet.set_frame(FIRST, make_image(Color.RED, Vector2i(10, 6)))
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(2, 6))
	var coords: Array[Vector2i] = [FIRST]
	FrameEdits.flip(sheet, coords, true)
	assert_eq(sheet.get_pivot(FIRST), Vector2(8, 6), "flipped")
	FrameEdits.flip(sheet, coords, false)
	assert_eq(sheet.get_pivot(FIRST), Vector2(8, 0), "flipped vertically")
	FrameEdits.rotate(sheet, coords, true)
	assert_eq(sheet.get_pivot(FIRST), Vector2(6, 8), "turned clockwise")
	FrameEdits.rotate(sheet, coords, false)
	assert_eq(sheet.get_pivot(FIRST), Vector2(8, 0), "turned back")


func test_pivots_stay_on_their_pixel() -> void:
	var img := Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(3, 2, 4, 6), Color.RED)
	sheet.set_frame(FIRST, img)
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(5, 8))
	var coords: Array[Vector2i] = [FIRST]
	FrameEdits.trim(sheet, coords)
	assert_eq(sheet.get_pivot(FIRST), Vector2(2, 6), "trimmed")
	FrameEdits.outline(sheet, coords, Color.BLACK, 2)
	assert_eq(sheet.get_pivot(FIRST), Vector2(4, 8), "outlined")
	sheet.nudge_frames(coords, Vector2i(3, 1))
	assert_eq(sheet.get_pivot(FIRST), Vector2(4, 8), "moved in the cell")


func test_renaming_leaves_shared_images_alone() -> void:
	var img := make_image(Color.RED)
	img.resource_name = "star"
	sheet.set_frame(FIRST, img)
	sheet.set_frame(SECOND, img)
	sheet.rename_frame(FIRST, "  big star ")
	assert_eq(sheet.frames[FIRST].resource_name, "big star")
	assert_eq(sheet.frames[SECOND].resource_name, "star", "the other frame keeps its name")
	assert_eq(img.resource_name, "star", "images aren't changed in place")


func test_renaming_can_be_undone() -> void:
	var document := Document.new()
	document.spritesheet.set_frame(FIRST, make_image(Color.RED))
	document.perform("Rename", document.spritesheet.rename_frame.bind(FIRST, "star"))
	assert_eq(document.spritesheet.frames[FIRST].resource_name, "star")
	document.undo()
	assert_eq(document.spritesheet.frames[FIRST].resource_name, "")


func test_cells_are_copied_with_what_they_hold() -> void:
	var source := FrameSource.for_file("star.png")
	sheet.set_frame(FIRST, make_image(Color.RED, Vector2i(8, 4)), source, Vector2i(-2, -1))
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(4, 4))
	var data := sheet.get_cell_data(FIRST)
	assert_eq(data.origin, Vector2i(-2, -1))
	assert_eq(data.source, source)
	assert_eq(data.pivot, Vector2(4, 4))
	assert_false(data.has("placement"), "not packed")
	assert_eq(sheet.get_cell_data(SECOND), {}, "empty cell")

	var added := sheet.add_cells([data, data] as Array[Dictionary])
	assert_eq(added, [SECOND, Vector2i(2, 0)] as Array[Vector2i])
	for coord in added:
		assert_eq(sheet.get_frame_origin(coord), Vector2i(-2, -1), "origin")
		assert_eq(sheet.get_pivot(coord), Vector2(4, 4), "pivot")
		assert_eq(sheet.frame_sources[coord], source, "link")


func test_projects_keep_pivots() -> void:
	sheet.set_frame(FIRST, make_image(Color.RED, Vector2i(7, 5)))
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(3.5, 5))
	var project := dir.path_join("pivots.sbelli")
	assert_eq(ProjectFile.save(sheet, project), OK)
	var reopened := Spritesheet.new()
	reopened.set_state(ProjectFile.load(project).state)
	assert_eq(reopened.get_pivot(FIRST), Vector2(3.5, 5))


func test_clipboard_keeps_what_frames_hold() -> void:
	var clipboard := FrameClipboard.new()
	var data := {"image": make_image(Color.RED), "pivot": Vector2(1, 1), "placement": {}}
	clipboard.copy([data] as Array[Dictionary])
	var cells := clipboard.get_cells()
	assert_eq(cells[0].pivot, Vector2(1, 1))
	assert_false(cells[0].has("placement"), "pasted frames are packed anew")


func test_mirrored_animations_keep_pivots() -> void:
	sheet.set_frame(FIRST, make_image(Color.RED, Vector2i(10, 6)))
	sheet.set_pivots([FIRST] as Array[Vector2i], Vector2(2, 6))
	sheet.add_animation(SheetAnimation.create("walk_right", [FIRST] as Array[Vector2i]))
	SheetAnimation.mirror(sheet, 0)
	assert_eq(sheet.get_pivot(Vector2i(0, 1)), Vector2(8, 6), "flipped copy")
