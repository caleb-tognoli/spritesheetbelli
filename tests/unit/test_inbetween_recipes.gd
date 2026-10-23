extends "res://tests/test_case.gd"
## In-betweens remembering how they were made: following their keys, telling when a key
## changed, and made again in their places

const FIRST := Vector2i(0, 0)
const SECOND := Vector2i(1, 0)
const THIRD := Vector2i(2, 0)

var sheet: Spritesheet
var dir := temp_path("inbetween_recipes")


func before_each() -> void:
	sheet = Spritesheet.new()
	DirAccess.make_dir_recursive_absolute(dir)
	# Three 16 px frames with a block in a different place in each, playing in "walk"
	var images: Array[Image] = []
	for i in 3:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(2 + i * 3, 4, 5, 8), Color.RED)
		images.append(img)
	sheet.add_frames(images)
	sheet.add_animation(SheetAnimation.create("walk", [FIRST, SECOND, THIRD] as Array[Vector2i]))


## Two in-betweens between the first two frames, right after the first, in "walk"
func add_two() -> Array[Vector2i]:
	var frames := InBetween.generate(
		InBetween.key_of(sheet, FIRST), InBetween.key_of(sheet, SECOND), 2
	)
	var how := {
		"spacing": InBetween.Spacing.EASE_IN,
		"motion": Vector2i(3, 0),
		"pins": [{"at": Vector2(4, 6), "to": Vector2(5, 6)}] as Array[Dictionary],
	}
	return InBetween.add(sheet, FIRST, SECOND, frames, InBetween.Place.AFTER_FIRST, {0: false}, how)


func test_inbetweens_remember_how_they_were_made() -> void:
	var cells := add_two()
	assert_eq(cells, [SECOND, THIRD])
	# The second key moved along onto the next row
	var second_key := Vector2i(0, 1)
	for i in 2:
		var recipe: Dictionary = sheet.inbetweens[cells[i]]
		assert_eq(recipe.index, i)
		assert_eq(recipe.count, 2)
		assert_eq(recipe.keys, [FIRST, second_key])
		assert_eq(recipe.spacing, InBetween.Spacing.EASE_IN)
		assert_eq(recipe.motion, Vector2i(3, 0))
		assert_eq(recipe.pins, [{"at": Vector2(4, 6), "to": Vector2(5, 6)}])
	assert_eq(InBetween.run_of(sheet, THIRD), cells, "made together, in order")
	assert_eq(InBetween.run_of(sheet, FIRST), [] as Array[Vector2i], "a key isn't one")
	assert_false(InBetween.is_stale(sheet, SECOND))
	assert_false(InBetween.is_edited(sheet, cells))
	assert_eq(InBetween.describe(sheet, THIRD), "In-between 2 of 2")
	assert_eq(InBetween.describe(sheet, FIRST), "")

	var more := InBetween.add(
		sheet,
		FIRST,
		SECOND,
		InBetween.generate(InBetween.key_of(sheet, FIRST), InBetween.key_of(sheet, SECOND), 1),
		InBetween.Place.NEW_ROW
	)
	assert_ne(sheet.inbetweens[more[0]].run, sheet.inbetweens[SECOND].run, "another run")
	assert_eq(InBetween.run_of(sheet, more[0]), more)


func test_keys_follow_their_frames() -> void:
	var cells := add_two()
	sheet.insert_row(0)
	assert_eq(sheet.inbetweens[Vector2i(1, 1)].keys, [Vector2i(0, 1), Vector2i(0, 2)], "row")
	sheet.move_frames([Vector2i(0, 1)] as Array[Vector2i], Vector2i(0, 2))
	assert_eq(sheet.inbetweens[Vector2i(1, 1)].keys, [Vector2i(0, 3), Vector2i(0, 2)], "moved")
	assert_false(InBetween.is_stale(sheet, Vector2i(1, 1)), "the same keys")
	assert_eq(cells.size(), 2)
	sheet.set_grid_size(Vector2i(3, 3))
	assert_false(InBetween.has_keys(sheet, Vector2i(1, 1)), "a key fell off the grid")
	assert_false(InBetween.is_stale(sheet, Vector2i(1, 1)), "gone, not out of date")
	assert_eq(
		InBetween.describe(sheet, Vector2i(1, 1)), "In-between 1 of 2 · a key frame was removed"
	)


func test_changing_a_key_makes_them_out_of_date() -> void:
	var cells := add_two()
	sheet.rename_frame(FIRST, "hero")
	assert_false(InBetween.is_stale(sheet, SECOND), "a new name changes no pixel")
	var before := sheet.get_state()
	FrameEdits.flip(sheet, [FIRST] as Array[Vector2i], true)
	for cell in cells:
		assert_true(InBetween.is_stale(sheet, cell), "flipped")
	assert_eq(
		InBetween.describe(sheet, SECOND), "In-between 1 of 2 · out of date: a key frame changed"
	)
	assert_false(InBetween.is_edited(sheet, cells), "the in-betweens themselves are as made")
	sheet.set_state(before)
	assert_false(InBetween.is_stale(sheet, SECOND), "undone")
	sheet.nudge_frames([Vector2i(0, 1)] as Array[Vector2i], Vector2i(1, 0))
	assert_true(InBetween.is_stale(sheet, SECOND), "the second key moved in its cell")


func test_changed_inbetweens_are_told() -> void:
	var cells := add_two()
	sheet.edit_frames(
		[THIRD] as Array[Vector2i],
		func(img: Image) -> Image:
			img.set_pixel(0, 0, Color.BLUE)
			return img
	)
	assert_true(InBetween.is_edited(sheet, cells))
	assert_false(InBetween.is_stale(sheet, THIRD), "the keys didn't change")


func test_copies_are_frames_of_their_own() -> void:
	add_two()
	assert_false(sheet.get_cell_data(SECOND).has("inbetween"), "copied without it")
	sheet.move_frames([SECOND] as Array[Vector2i], Vector2i(0, 2), true)
	assert_false(sheet.inbetweens.has(Vector2i(1, 2)), "a copy")
	assert_true(sheet.inbetweens.has(SECOND), "the original stays one")
	sheet.move_frame(THIRD, Vector2i(2, 2), true)
	assert_false(sheet.inbetweens.has(Vector2i(2, 2)))
	sheet.move_frames([SECOND] as Array[Vector2i], Vector2i(0, 3))
	assert_true(sheet.inbetweens.has(Vector2i(1, 3)), "moved, it's still one")


func test_making_them_again_keeps_their_places() -> void:
	var cells := add_two()
	var walk := sheet.animations[0]
	walk.durations = [1.0, 2.0, 1.0, 1.0, 1.0] as Array[float]
	sheet.set_animation(0, walk)
	FrameEdits.flip(sheet, [FIRST] as Array[Vector2i], true)
	var recipe: Dictionary = sheet.inbetweens[SECOND]
	var frames := InBetween.generate(
		InBetween.key_of(sheet, recipe.keys[0]), InBetween.key_of(sheet, recipe.keys[1]), 2
	)
	InBetween.replace(sheet, cells, frames, {"spacing": InBetween.Spacing.EASE_OUT})
	for i in 2:
		assert_eq(sheet.frames[cells[i]], frames[i].image, "in its place")
		assert_false(InBetween.is_stale(sheet, cells[i]), "up to date")
		assert_eq(sheet.inbetweens[cells[i]].spacing, InBetween.Spacing.EASE_OUT)
		assert_eq(sheet.inbetweens[cells[i]].run, recipe.run, "the same run")
	assert_eq(sheet.animations[0].cells, walk.cells, "played as before")
	assert_eq(sheet.animations[0].durations, walk.durations, "as long as before")
	assert_false(InBetween.is_edited(sheet, cells))


func test_projects_keep_how_inbetweens_were_made() -> void:
	add_two()
	var path := dir.path_join("recipes.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(loaded.inbetweens.keys(), sheet.inbetweens.keys())
	for cell in sheet.inbetweens:
		assert_eq(loaded.inbetweens[cell], sheet.inbetweens[cell])
	assert_false(InBetween.is_stale(loaded, SECOND), "the keys load as they were")
	assert_false(InBetween.is_edited(loaded, InBetween.run_of(loaded, SECOND)))


func test_undo_takes_them_away() -> void:
	var document := Document.new()
	document.spritesheet.set_state(sheet.get_state())
	sheet = document.spritesheet
	document.perform("Generate in-betweens", add_two)
	assert_eq(sheet.inbetweens.size(), 2)
	document.undo()
	assert_true(sheet.inbetweens.is_empty())
	document.redo()
	assert_eq(sheet.inbetweens.size(), 2)
