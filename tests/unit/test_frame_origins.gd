extends "res://tests/test_case.gd"

var sheet: Spritesheet


func before_each() -> void:
	sheet = Spritesheet.new()


## A 16x16 frame with a 4x6 red block at [param at]
static func block_at(at: Vector2i) -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(at, Vector2i(4, 6)), Color.RED)
	return img


func test_frames_are_centred() -> void:
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(8, 8)), make_image(Color.BLUE, Vector2i(16, 12))]
			as Array[Image]
		)
	)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(4, 2, 8, 8))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(1, 0)), Rect2i(0, 0, 16, 12))
	assert_false(sheet.has_frame_origin(Vector2i(0, 0)))


func test_trim_keeps_pixels_in_place() -> void:
	sheet.add_frames([block_at(Vector2i(2, 8)), block_at(Vector2i(10, 4))] as Array[Image])
	var before := sheet.get_image()
	FrameEdits.trim(sheet, [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(sheet.frames[Vector2i(0, 0)].get_size(), Vector2i(4, 6))
	assert_eq(sheet.sprite_size, Vector2i(16, 16), "the other frame still fills the cell")
	assert_eq(sheet.get_image().get_data(), before.get_data(), "nothing moved")


func test_trimming_every_frame_shrinks_cells_together() -> void:
	sheet.add_frames([block_at(Vector2i(2, 8)), block_at(Vector2i(6, 4))] as Array[Image])
	FrameEdits.trim(sheet, sheet.get_sorted_coords())
	# Blocks span x 2..10 and y 4..14 in both cells
	assert_eq(sheet.sprite_size, Vector2i(8, 10))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)).position, Vector2i(0, 4))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(1, 0)).position, Vector2i(4, 0))


func test_nudge_and_center() -> void:
	sheet.add_frames([make_image(Color.RED, Vector2i(8, 8))] as Array[Image])
	sheet.add_frames([make_image(Color.BLUE, Vector2i(8, 8))] as Array[Image])
	var first := [Vector2i(0, 0)] as Array[Vector2i]
	sheet.nudge_frames(first, Vector2i(2, -1))
	assert_eq(sheet.sprite_size, Vector2i(10, 9), "cells grow to hold the moved frame")
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)).position, Vector2i(2, 0))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(1, 0)).position, Vector2i(0, 1))
	FrameEdits.align(sheet, first, Spritesheet.Alignment.CENTER)
	assert_false(sheet.has_frame_origin(Vector2i(0, 0)))
	assert_eq(sheet.sprite_size, Vector2i(8, 8))


func test_align_to_bottom() -> void:
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(8, 8)), make_image(Color.BLUE, Vector2i(8, 16))]
			as Array[Image]
		)
	)
	FrameEdits.align(sheet, sheet.get_sorted_coords(), Spritesheet.Alignment.BOTTOM)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(0, 8, 8, 8))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(1, 0)), Rect2i(0, 0, 8, 16))


func test_flip_and_rotate_move_origins() -> void:
	sheet.add_frames([block_at(Vector2i(0, 0)), make_image(Color.BLUE)] as Array[Image])
	var first := [Vector2i(0, 0)] as Array[Vector2i]
	FrameEdits.trim(sheet, first)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)).position, Vector2i(0, 0))
	FrameEdits.flip(sheet, first, true)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)).position, Vector2i(12, 0))
	FrameEdits.rotate(sheet, first, true)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(10, 12, 6, 4))
	FrameEdits.rotate(sheet, first, false)
	FrameEdits.flip(sheet, first, true)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)).position, Vector2i(0, 0))


func test_origins_follow_moves_and_cells() -> void:
	sheet.set_grid_size(Vector2i(4, 1))
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	sheet.nudge_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(1, 1))
	var origin := sheet.get_frame_origin(Vector2i(0, 0))
	sheet.move_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(1, 0))
	assert_eq(sheet.get_frame_origin(Vector2i(1, 0)), origin, "moved with its frame")
	assert_false(sheet.has_frame_origin(Vector2i(0, 0)), "the swapped frame is centred")
	sheet.insert_empty_cell(Vector2i(0, 0))
	assert_eq(sheet.get_frame_origin(Vector2i(2, 0)), origin, "shifted with its frame")
	sheet.remove_cell(Vector2i(0, 0))
	assert_eq(sheet.get_frame_origin(Vector2i(1, 0)), origin)
	sheet.replace_frame(Vector2i(1, 0), make_image(Color.GREEN))
	assert_false(sheet.has_frame_origin(Vector2i(1, 0)), "a new image is centred")


func test_origins_are_undone_and_saved() -> void:
	var document := Document.new()
	sheet = document.spritesheet
	sheet.add_frames([make_image(Color.RED), make_image(Color.BLUE)] as Array[Image])
	document.perform(
		"Nudge", sheet.nudge_frames.bind([Vector2i(1, 0)] as Array[Vector2i], Vector2i(-3, 2))
	)
	var origin := sheet.get_frame_origin(Vector2i(1, 0))
	var path := OS.get_user_data_dir().path_join("tests/origins.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	document.undo()
	assert_false(sheet.has_frame_origin(Vector2i(1, 0)))
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(loaded.get_frame_origin(Vector2i(1, 0)), origin)
	assert_false(loaded.has_frame_origin(Vector2i(0, 0)))
	assert_eq(loaded.sprite_size, Vector2i(19, 18))


func test_scaled_origins() -> void:
	sheet.add_frames([make_image(Color.RED, Vector2i(8, 8))] as Array[Image])
	sheet.add_frames([make_image(Color.BLUE, Vector2i(8, 8))] as Array[Image])
	sheet.nudge_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(2, 0))
	sheet.set_frame_scale(Vector2(2, 2))
	assert_eq(sheet.sprite_size, Vector2i(20, 16))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(4, 0, 16, 16))
	assert_eq(sheet.get_base_sprite_size(), Vector2i(10, 8))


func test_align_keeps_the_cell_size() -> void:
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(8, 8)), make_image(Color.BLUE, Vector2i(12, 16))]
			as Array[Image]
		)
	)
	var small := [Vector2i(0, 0)] as Array[Vector2i]
	FrameEdits.align(sheet, small, Spritesheet.Alignment.BOTTOM)
	assert_eq(sheet.sprite_size, Vector2i(12, 16), "the cell doesn't grow")
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(2, 8, 8, 8))
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(1, 0)), Rect2i(0, 0, 12, 16), "others stay")
	FrameEdits.align(sheet, small, Spritesheet.Alignment.TOP)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(2, 0, 8, 8))
	FrameEdits.align(sheet, small, Spritesheet.Alignment.RIGHT)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(4, 0, 8, 8), "keeps the top")
	FrameEdits.align(sheet, small, Spritesheet.Alignment.LEFT)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(0, 0, 8, 8))
	FrameEdits.align(sheet, small, Spritesheet.Alignment.CENTER)
	assert_false(sheet.has_frame_origin(Vector2i(0, 0)), "back in the middle")
	assert_eq(sheet.sprite_size, Vector2i(12, 16))


func test_align_brings_a_moved_frame_back_in_line() -> void:
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(8, 8)), make_image(Color.BLUE, Vector2i(8, 16))]
			as Array[Image]
		)
	)
	var small := [Vector2i(0, 0)] as Array[Vector2i]
	sheet.nudge_frames(small, Vector2i(0, 10))
	assert_eq(sheet.sprite_size, Vector2i(8, 22))
	FrameEdits.align(sheet, small, Spritesheet.Alignment.BOTTOM)
	assert_eq(sheet.sprite_size, Vector2i(8, 16), "the cell shrinks back")
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(0, 8, 8, 8))
	# Aligning every frame uses the whole cell
	FrameEdits.align(sheet, sheet.get_sorted_coords(), Spritesheet.Alignment.TOP)
	assert_eq(sheet.get_frame_rect_in_cell(Vector2i(0, 0)), Rect2i(0, 0, 8, 8))
	assert_eq(sheet.sprite_size, Vector2i(8, 16))
