extends "res://tests/test_case.gd"

var sheet: Spritesheet


func before_each() -> void:
	sheet = Spritesheet.new()


func after_each() -> void:
	Settings.set_value(&"show_rulers", false)


## A 16x16 frame with a 4x6 red block at [param at]
static func block_at(at: Vector2i) -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(at, Vector2i(4, 6)), Color.RED)
	return img


## Where what's drawn of the frame at [param coord] is, from the point frames are placed
## around, like guides
func drawn(coord: Vector2i) -> Rect2i:
	var used := sheet.frames[coord].get_used_rect()
	return Rect2i(sheet.get_frame_origin(coord) + used.position, used.size)


func test_guides_are_in_order_without_repeats() -> void:
	assert_false(sheet.has_guides)
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([12, 4, 12]))
	assert_eq(sheet.get_guides(Vector2.AXIS_Y), PackedInt32Array([4, 12]))
	assert_eq(sheet.get_guides(Vector2.AXIS_X), PackedInt32Array())
	assert_true(sheet.has_guides)
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array())
	assert_false(sheet.has_guides)


func test_guides_are_counted_from_the_cells_corner() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	# 16x16 frames are centred on the point guides count from
	assert_eq(sheet.guide_to_cell(Vector2.AXIS_Y, 4), 12)
	assert_eq(sheet.cell_to_guide(Vector2.AXIS_Y, 12), 4)
	sheet.set_frame_scale(Vector2(2, 2))
	assert_eq(sheet.guide_to_cell(Vector2.AXIS_Y, 4), 24, "they scale with the frames")
	assert_eq(sheet.cell_to_guide(Vector2.AXIS_Y, 24), 4)


func test_guides_stay_with_the_frames_when_cells_grow() -> void:
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	var feet := sheet.cell_to_guide(Vector2.AXIS_Y, 16)
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([feet]))
	sheet.nudge_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(0, -3))
	assert_eq(sheet.sprite_size, Vector2i(16, 19), "the cells grew upwards")
	var other := sheet.get_frame_rect_in_cell(Vector2i(1, 0))
	assert_eq(sheet.guide_to_cell(Vector2.AXIS_Y, feet), other.end.y, "still at the feet")


func test_snapping_goes_to_the_next_guide_then_the_cells_edge() -> void:
	# The second frame keeps the cells 16 px, from -8 to 8
	sheet.add_frames([block_at(Vector2i(6, 0)), make_image(Color.BLUE)] as Array[Image])
	var block: Array[Vector2i] = [Vector2i(0, 0)]
	# The block spans y -8..-2
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([0]))
	FrameEdits.snap_to_guides(sheet, block, Vector2i.DOWN)
	assert_eq(drawn(Vector2i(0, 0)).end.y, 0)
	FrameEdits.snap_to_guides(sheet, block, Vector2i.DOWN)
	assert_eq(drawn(Vector2i(0, 0)).end.y, 8, "past the last guide, the cell's edge")
	FrameEdits.snap_to_guides(sheet, block, Vector2i.DOWN)
	assert_eq(drawn(Vector2i(0, 0)).end.y, 8, "nowhere further: stays")
	assert_eq(sheet.sprite_size, Vector2i(16, 16))
	FrameEdits.snap_to_guides(sheet, block, Vector2i.UP)
	assert_eq(drawn(Vector2i(0, 0)).position.y, 0, "the top edge going up")
	FrameEdits.snap_to_guides(sheet, block, Vector2i.UP)
	assert_eq(drawn(Vector2i(0, 0)).position.y, -8)


func test_snapping_sideways_moves_each_frame_on_its_own() -> void:
	var blocks: Array[Image] = [
		block_at(Vector2i(2, 2)), block_at(Vector2i(6, 8)), make_image(Color.BLUE)
	]
	sheet.add_frames(blocks)
	# The blocks span x -6..-2 and -2..2 from the middle of the cells, the last one keeps
	# them 16 px
	sheet.set_guides(Vector2.AXIS_X, PackedInt32Array([-4, -2]))
	var two: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	FrameEdits.snap_to_guides(sheet, two, Vector2i.RIGHT)
	assert_eq(drawn(Vector2i(0, 0)).end.x, 0, "drawn across a guide: all of it after")
	assert_eq(sheet.frames[Vector2i(0, 0)].get_size(), Vector2i(4, 6), "trimmed when moved")
	assert_eq(drawn(Vector2i(1, 0)).end.x, 8, "no guide ahead: the cell's edge")
	FrameEdits.snap_to_guides(sheet, [Vector2i(1, 0)] as Array[Vector2i], Vector2i.RIGHT)
	assert_eq(drawn(Vector2i(1, 0)).end.x, 8, "nowhere further: stays")
	assert_eq(sheet.sprite_size.x, 16)
	FrameEdits.snap_to_guides(sheet, two, Vector2i.LEFT)
	assert_eq(drawn(Vector2i(0, 0)).end.x, -2, "all of it before the guide it's across")
	assert_eq(drawn(Vector2i(1, 0)).position.x, -2)


func test_snapping_moves_frames_drawn_across_guides_past_them() -> void:
	sheet.add_frames([block_at(Vector2i(6, 5)), make_image(Color.BLUE)] as Array[Image])
	var block: Array[Vector2i] = [Vector2i(0, 0)]
	# The block spans y -3..3, across the guides at -1 and 1
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([-1, 1, 5]))
	FrameEdits.snap_to_guides(sheet, block, Vector2i.DOWN)
	assert_eq(drawn(Vector2i(0, 0)).position.y, 1, "all of it below the furthest one")
	FrameEdits.snap_to_guides(sheet, block, Vector2i.DOWN)
	assert_eq(drawn(Vector2i(0, 0)).position.y, 5, "also past the cell's edge")
	assert_eq(sheet.sprite_size.y, 19, "the cells grew to hold it")
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([7, 9]))
	FrameEdits.snap_to_guides(sheet, block, Vector2i.UP)
	assert_eq(drawn(Vector2i(0, 0)).end.y, 7, "going up, all of it above the furthest one")


func test_guides_are_undone_and_saved() -> void:
	var document := Document.new()
	sheet = document.spritesheet
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	document.perform("Guide", sheet.set_guides.bind(Vector2.AXIS_X, PackedInt32Array([-3, 5])))
	document.perform("Guide", sheet.set_guides.bind(Vector2.AXIS_Y, PackedInt32Array([7])))
	var path := temp_path("guides.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	document.undo()
	assert_eq(sheet.get_guides(Vector2.AXIS_Y), PackedInt32Array())
	assert_eq(sheet.get_guides(Vector2.AXIS_X), PackedInt32Array([-3, 5]))
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(loaded.get_guides(Vector2.AXIS_X), PackedInt32Array([-3, 5]))
	assert_eq(loaded.get_guides(Vector2.AXIS_Y), PackedInt32Array([7]))


func test_snapping_is_one_step() -> void:
	var document := Document.new()
	sheet = document.spritesheet
	sheet.add_frames([block_at(Vector2i(2, 2)), block_at(Vector2i(6, 8))] as Array[Image])
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([3, 10]))
	var before := sheet.get_image().get_data()
	document.perform(
		"Snap", FrameEdits.snap_to_guides.bind(sheet, sheet.get_sorted_coords(), Vector2i.DOWN)
	)
	document.undo()
	assert_eq(sheet.get_image().get_data(), before)


func test_animation_preview_shows_guides_with_the_rulers() -> void:
	sheet.add_frames([make_image(Color.RED)] as Array[Image])
	sheet.set_guides(Vector2.AXIS_Y, PackedInt32Array([4]))
	var player := FramePlayer.new()
	add_child(player)
	player.sheet = sheet
	player.set_cells([Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(player.stage.guides, [] as Array[PackedInt32Array], "rulers are off")
	Settings.set_value(&"show_rulers", true)
	assert_eq(
		player.stage.guides,
		[PackedInt32Array(), PackedInt32Array([12])] as Array[PackedInt32Array],
		"in pixels of the cell"
	)
	player.queue_free()
