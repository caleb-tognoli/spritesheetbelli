extends "res://tests/test_case.gd"

const FIRST := Vector2i(0, 0)
const SECOND := Vector2i(1, 0)

var sheet: Spritesheet
var dir := OS.get_user_data_dir().path_join("tests/sources")


func before_each() -> void:
	sheet = Spritesheet.new()
	DirAccess.make_dir_recursive_absolute(dir)


## A 10x7 frame with a red block and a blue pixel, so flips and turns show
static func drawing(size := Vector2i(10, 7)) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 1, 5, 4), Color.RED)
	img.set_pixel(3, 2, Color.BLUE)
	return img


## Adds [param img] linked to a file, next to an unlinked 16x16 frame
func add_linked(img: Image) -> void:
	sheet.add_frames(
		[img, make_image(Color.GREEN)] as Array[Image],
		Spritesheet.AddMode.FIRST_FREE,
		[FrameSource.for_file("walk.png")] as Array[Dictionary]
	)


## Reloading [param pixels] with the edits made gives the frame as it is now
func assert_rebuilds(pixels: Image, message: String) -> void:
	var result := FrameSource.rebuild(sheet.frame_sources[FIRST], pixels, true)
	var img: Image = result.image
	assert_eq(img.get_size(), sheet.frames[FIRST].get_size(), message + " size")
	assert_eq(img.get_data(), sheet.frames[FIRST].get_data(), message + " pixels")
	var origin: Vector2i = (
		result.origin if result.origin != null else -((img.get_size() + Vector2i.ONE) / 2)
	)
	assert_eq(origin, sheet.get_frame_origin(FIRST), message + " origin")


func test_every_edit_can_be_made_again() -> void:
	var first := [FIRST] as Array[Vector2i]
	var edits := {
		"flip": func() -> void: FrameEdits.flip(sheet, first, true),
		"flip vertically": func() -> void: FrameEdits.flip(sheet, first, false),
		"rotate": func() -> void: FrameEdits.rotate(sheet, first, true),
		"rotate back": func() -> void: FrameEdits.rotate(sheet, first, false),
		"trim": func() -> void: FrameEdits.trim(sheet, first),
		"colour key": func() -> void: FrameEdits.color_key(sheet, first, Color.BLUE),
		"outline": func() -> void: FrameEdits.outline(sheet, first, Color.BLACK, 2, true),
		"nudge": func() -> void: sheet.nudge_frames(first, Vector2i(3, -1)),
		"align": func() -> void: sheet.align_frames(first, Spritesheet.Alignment.BOTTOM),
		"set origin": func() -> void: sheet.set_frame_origin(FIRST, Vector2i(-2, -9)),
	}
	# Each on its own, then all of them one after the other
	for edit_name: String in edits:
		sheet = Spritesheet.new()
		add_linked(drawing())
		edits[edit_name].call()
		assert_true(FrameSource.has_edits(sheet.frame_sources[FIRST]), edit_name + " recorded")
		assert_rebuilds(drawing(), edit_name)
	sheet = Spritesheet.new()
	add_linked(drawing())
	for edit_name: String in edits:
		edits[edit_name].call()
		assert_rebuilds(drawing(), "after " + edit_name)


func test_unlinked_frames_record_nothing() -> void:
	add_linked(drawing())
	FrameEdits.flip(sheet, [SECOND] as Array[Vector2i], true)
	sheet.nudge_frames([SECOND] as Array[Vector2i], Vector2i.ONE)
	assert_false(sheet.frame_sources.has(SECOND))
	assert_false(FrameSource.has_edits(sheet.frame_sources[FIRST]))


func test_reset_goes_back_to_the_file() -> void:
	add_linked(drawing())
	var first := [FIRST] as Array[Vector2i]
	FrameEdits.trim(sheet, first)
	sheet.nudge_frames(first, Vector2i(4, 4))
	var redrawn := drawing(Vector2i(12, 12))
	var result := FrameSource.rebuild(sheet.frame_sources[FIRST], redrawn, false)
	assert_eq((result.image as Image).get_data(), redrawn.get_data())
	assert_eq(result.origin, null, "centred")


func test_edits_follow_a_redrawn_frame() -> void:
	add_linked(make_image(Color.RED, Vector2i(8, 8)))
	var first := [FIRST] as Array[Vector2i]
	sheet.nudge_frames(first, Vector2i(2, 0))
	FrameEdits.flip(sheet, first, true)
	assert_eq(sheet.get_frame_origin(FIRST), Vector2i(-6, -4))
	# 2px wider: centred at -5, moved to -3, flipped to 3 - 10
	var result := FrameSource.rebuild(
		sheet.frame_sources[FIRST], make_image(Color.RED, Vector2i(10, 8)), true
	)
	assert_eq(result.origin, Vector2i(-7, -4))


func test_sources_follow_their_frames() -> void:
	var source := FrameSource.for_file("a.png")
	sheet.set_frame(FIRST, drawing(), source)
	sheet.set_frame(SECOND, drawing())
	sheet.move_frames([FIRST] as Array[Vector2i], Vector2i(1, 0))
	assert_eq(sheet.frame_sources.get(SECOND), source, "moved, swapping")
	assert_false(sheet.frame_sources.has(FIRST))
	sheet.move_frame(SECOND, Vector2i(2, 0), true)
	assert_eq(sheet.frame_sources.get(Vector2i(2, 0)), source, "copied")
	sheet.insert_row(0)
	assert_eq(sheet.frame_sources.get(Vector2i(1, 1)), source, "row inserted above")
	sheet.remove_cell(Vector2i(0, 1))
	assert_eq(sheet.frame_sources.get(Vector2i(0, 1)), source, "cell removed before")
	sheet.set_grid_size(Vector2i(1, 2))
	assert_eq(sheet.frame_sources.keys(), [Vector2i(0, 1)], "grid shrunk")
	sheet.set_frame(Vector2i(0, 1), drawing())
	assert_true(sheet.frame_sources.is_empty(), "new pixels aren't linked")


func test_undo_brings_edits_back() -> void:
	var doc := Document.new()
	doc.spritesheet.set_frame(FIRST, drawing(), FrameSource.for_file("a.png"))
	var first := [FIRST] as Array[Vector2i]
	doc.perform("Flip", FrameEdits.flip.bind(doc.spritesheet, first, true))
	assert_true(FrameSource.has_edits(doc.spritesheet.frame_sources[FIRST]))
	doc.undo()
	assert_false(FrameSource.has_edits(doc.spritesheet.frame_sources[FIRST]))
	doc.redo()
	assert_true(FrameSource.has_edits(doc.spritesheet.frame_sources[FIRST]))


func test_mirrored_animation_copies_are_linked() -> void:
	sheet.set_frame(FIRST, drawing(), FrameSource.for_file("a.png"))
	var walk := SheetAnimation.new()
	walk.name = "walk"
	walk.cells = [FIRST] as Array[Vector2i]
	sheet.add_animation(walk)
	SheetAnimation.mirror(sheet, 0)
	var copy := sheet.animations[1].cells[0]
	assert_eq(sheet.frame_sources[copy].path, "a.png")
	assert_eq(sheet.frame_sources[copy].ops, [{"op": "flip", "horizontal": true}])


func test_cutting_regions() -> void:
	var img := drawing()
	var loaded := {"image:s.png": img}
	var source := FrameSource.for_region("s.png", Rect2i(2, 1, 5, 4))
	assert_eq(
		FrameSource.cut(source, loaded).get_data(), img.get_region(Rect2i(2, 1, 5, 4)).get_data()
	)
	loaded["image:s.png"] = make_image(Color.RED, Vector2i(4, 4))
	assert_eq(FrameSource.cut(source, loaded), null, "outside a smaller image")
	assert_eq(FrameSource.cut(source, {}), null, "file not read")


func test_slicer_and_detector_link_frames() -> void:
	var img := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(1, 2, 4, 6), Color.RED)
	img.fill_rect(Rect2i(10, 4, 4, 4), Color.RED)
	assert_eq(Slicer.slice(img, Vector2i(2, 1)).rects[SECOND], Rect2i(8, 0, 8, 8))

	var rows := SpriteDetector.detect(img)
	var detected := SpriteDetector.to_spritesheet(
		img, rows, Spritesheet.Alignment.BOTTOM, "sheet.png"
	)
	var source: Dictionary = detected.frame_sources[SECOND]
	assert_eq(source.rect, [10, 4, 4, 4])
	assert_false(FrameSource.has_edits(source), "aligning isn't an edit")
	var origin: Array = source.origin
	assert_eq(Vector2i(origin[0], origin[1]), detected.get_frame_origin(SECOND))
	var reset := FrameSource.rebuild(source, img.get_region(Rect2i(10, 4, 4, 4)), false)
	assert_eq(reset.origin, detected.get_frame_origin(SECOND), "reset keeps the alignment")


func test_data_frames_are_found_by_name_after_repacking() -> void:
	var image_path := dir.path_join("packed.png")
	var data_path := dir.path_join("packed.json")
	var img := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 4, 4), Color.RED)
	img.fill_rect(Rect2i(4, 0, 4, 4), Color.BLUE)
	var entry := '{"frame": {"x": %d, "y": 0, "w": 4, "h": 4}}'
	var json := '{"frames": {"a": %s, "b": %s}}' % [entry, entry]
	var data := SheetData.parse_json(json % [0, 4])
	var imported := data.to_spritesheet(img, image_path, data_path)
	var source: Dictionary = imported.frame_sources[SECOND]
	assert_eq(source.name, "b")
	assert_eq(FrameSource.get_paths(source), PackedStringArray([image_path, data_path]))

	# Packed the other way round
	var file := FileAccess.open(data_path, FileAccess.WRITE)
	file.store_string(json % [4, 0])
	file.close()
	img.save_png(image_path)
	var key := FrameSource.get_load_key(source)
	var pixels := FrameSource.cut(source, {key: FrameSource.load_key(key)})
	assert_color(pixels, Vector2i.ZERO, Color.RED, "b is now where a was")


func test_gif_frames_are_linked_by_index() -> void:
	var path := "res://tests/fixtures/pillow.gif"
	var gif := GifDecoder.load_file(path)
	GifDecoder.add_to_sheet(sheet, gif, "pillow", path)
	var last := Vector2i(gif.frames.size() - 1, 0)
	var source: Dictionary = sheet.frame_sources[last]
	assert_eq(source.gif_frame, last.x)
	var key := FrameSource.get_load_key(source)
	var pixels := FrameSource.cut(source, {key: FrameSource.load_key(key)})
	assert_eq(pixels.get_data(), sheet.frames[last].get_data())


func test_projects_keep_links() -> void:
	var image_path := dir.path_join("art/walk.png")
	DirAccess.make_dir_recursive_absolute(image_path.get_base_dir())
	drawing().save_png(image_path)
	sheet.set_frame(FIRST, drawing(), FrameSource.for_file(image_path))
	FrameEdits.color_key(sheet, [FIRST] as Array[Vector2i], Color(1, 0, 0), 0.25)
	var project := dir.path_join("walk.sbelli")
	assert_eq(ProjectFile.save(sheet, project), OK)

	var loaded := ProjectFile.load(project)
	var sources: Dictionary = loaded.state.sources
	assert_eq(sources[FIRST], sheet.frame_sources[FIRST])
	var reopened := Spritesheet.new()
	reopened.set_state(loaded.state)
	assert_rebuilds_in(reopened, drawing())


func assert_rebuilds_in(other: Spritesheet, pixels: Image) -> void:
	sheet = other
	assert_rebuilds(pixels, "reopened")


func test_relative_paths() -> void:
	assert_eq(FrameSource.relative_path("C:/a/b/x.png", "C:/a/c"), "../b/x.png")
	assert_eq(FrameSource.relative_path("C:/a/x.png", "C:/a"), "x.png")
	assert_eq(FrameSource.relative_path("D:/x.png", "C:/a"), "D:/x.png", "another drive")
	# A moved project finds images next to it, else keeps the old path
	var moved := dir.path_join("moved")
	DirAccess.make_dir_recursive_absolute(moved)
	make_image(Color.RED).save_png(moved.path_join("x.png"))
	assert_eq(FrameSource.resolve_path("C:/old/x.png", "x.png", moved), moved.path_join("x.png"))
	assert_eq(FrameSource.resolve_path("C:/old/y.png", "y.png", moved), "C:/old/y.png")
