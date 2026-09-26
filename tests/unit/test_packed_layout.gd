extends "res://tests/test_case.gd"

var document: Document
var sheet: Spritesheet
var dir := OS.get_user_data_dir().path_join("tests/packed")


func before_each() -> void:
	document = Document.new()
	sheet = document.spritesheet
	DirAccess.make_dir_recursive_absolute(dir)


## A frame of [param size] with a coloured block at [param block] and transparency around
static func sprite(size: Vector2i, block: Rect2i, color := Color.RED) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill_rect(block, color)
	# A pixel of another colour, so flipped copies aren't the same
	img.set_pixelv(block.position, Color.BLUE)
	return img


## Sprites of different sizes, like a packed sheet of unrelated sprites
func add_sprites(count := 6) -> void:
	var images: Array[Image] = []
	for i in count:
		var size := Vector2i(10 + i * 7, 30 - i * 3)
		var color := Color.from_hsv(i / 8.0, 1, 1)
		images.append(sprite(size + Vector2i(4, 4), Rect2i(Vector2i(2, 2), size), color))
	sheet.add_frames(images)


func set_mode(mode: AtlasSettings.PackMode, values := {}) -> void:
	var settings := AtlasSettings.from_dictionary(values)
	settings.pack_mode = mode
	sheet.set_atlas_settings(settings)


func pack() -> void:
	sheet.set_layout(Spritesheet.Layout.PACKED)


func rects() -> Dictionary:
	var result := {}
	for coord in sheet.placements:
		result[coord] = PackedLayout.get_rect(sheet, coord)
	return result


func assert_no_overlaps(message := "") -> void:
	var seen := {}
	for coord in sheet.placements:
		var place: Dictionary = sheet.placements[coord]
		var key := [place.page, place.position]
		if seen.has(key):
			continue
		seen[key] = coord
		for other: Array in seen:
			if other != key and other[0] == place.page:
				var rect := PackedLayout.get_rect(sheet, coord)
				var other_rect := PackedLayout.get_rect(sheet, seen[other])
				var text := "%s %s and %s overlap" % [message, rect, other_rect]
				assert_false(rect.intersects(other_rect), text)


func test_the_grid_is_left_alone() -> void:
	add_sprites()
	assert_true(sheet.placements.is_empty(), "no places in the grid layout")


func test_packing_places_every_frame_trimmed() -> void:
	add_sprites()
	pack()
	assert_eq(sheet.placements.size(), 6)
	assert_no_overlaps()
	var place: Dictionary = sheet.placements[Vector2i(0, 0)]
	assert_eq(place.src, Rect2i(2, 2, 10, 30), "without the transparent border")
	assert_eq(PackedLayout.get_page_count(sheet), 1)
	assert_true(PackedLayout.get_occupancy(sheet) > 0.6, str(PackedLayout.get_occupancy(sheet)))


func test_pages_show_the_frames() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.AUTO, {"allow_rotation": true, "max_size": 48})
	pack()
	var pages := PackedLayout.render_pages(sheet)
	assert_eq(pages.size(), PackedLayout.get_page_count(sheet))
	for coord in sheet.placements:
		var place: Dictionary = sheet.placements[coord]
		var frame := sheet.frames[coord].get_region(place.src)
		if place.rotated:
			frame.rotate_90(CLOCKWISE)
		var rect := PackedLayout.get_rect(sheet, coord)
		assert_eq(
			pages[place.page].get_region(rect).get_data(), frame.get_data(), "frame %s" % coord
		)


func test_undo_brings_places_back_exactly() -> void:
	add_sprites()
	document.perform("Pack", sheet.set_layout.bind(Spritesheet.Layout.PACKED))
	var before := sheet.placements.duplicate()
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	document.perform("Outline", FrameEdits.outline.bind(sheet, coords, Color.BLACK, 3))
	assert_ne(sheet.placements, before, "the outlined frame grew")
	document.undo()
	assert_eq(sheet.placements, before)
	document.redo()
	assert_eq(sheet.placements[Vector2i(0, 0)].src.size, Vector2i(16, 36))
	document.undo()
	document.undo()
	assert_eq(sheet.layout, Spritesheet.Layout.GRID)


func test_restored_states_are_not_packed_again() -> void:
	add_sprites(2)
	pack()
	var state := sheet.get_state()
	# Places that overlap, as they were saved
	var placements: Dictionary = state.placements.duplicate()
	for coord: Vector2i in placements:
		var place: Dictionary = placements[coord].duplicate()
		place.position = Vector2i(0, 0)
		placements[coord] = place
	state.placements = placements
	sheet.set_state(state)
	assert_eq(sheet.placements, placements, "kept as they were")


func test_kept_frames_stay_where_they_are() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	var before := rects()
	var grown: Array[Vector2i] = [Vector2i(2, 0)]
	FrameEdits.outline(sheet, grown, Color.BLACK, 6)
	var after := rects()
	for coord: Vector2i in before:
		if coord != grown[0]:
			assert_eq(after[coord], before[coord], "%s stays" % coord)
	assert_eq(after[grown[0]].size, before[grown[0]].size + Vector2i(12, 12), "grown")
	assert_no_overlaps()
	# A smaller frame keeps its place
	FrameEdits.trim(sheet, [Vector2i(3, 0)] as Array[Vector2i])
	assert_eq(rects()[Vector2i(3, 0)], after[Vector2i(3, 0)], "trimming changes nothing")


func test_new_frames_go_in_the_free_space() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	var before := rects()
	sheet.add_frames([sprite(Vector2i(8, 8), Rect2i(0, 0, 8, 8))] as Array[Image])
	var after := rects()
	for coord: Vector2i in before:
		assert_eq(after[coord], before[coord])
	assert_eq(after.size(), 7)
	assert_no_overlaps()


func test_auto_packs_everything_again() -> void:
	add_sprites()
	pack()
	var full := PackedLayout.get_page_sizes(sheet)[0]
	sheet.remove_frames([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	var smaller := PackedLayout.get_page_sizes(sheet)[0]
	assert_true(smaller.x * smaller.y < full.x * full.y, "%s < %s" % [smaller, full])
	assert_no_overlaps()


func test_same_frames_share_a_place() -> void:
	var img := sprite(Vector2i(20, 20), Rect2i(4, 4, 8, 10))
	sheet.add_frames([img, sprite(Vector2i(9, 9), Rect2i(0, 0, 9, 9)), img] as Array[Image])
	pack()
	assert_eq(rects()[Vector2i(2, 0)], rects()[Vector2i(0, 0)], "shared")
	FrameEdits.flip(sheet, [Vector2i(2, 0)] as Array[Vector2i], true)
	assert_ne(rects()[Vector2i(2, 0)], rects()[Vector2i(0, 0)], "flipped: not the same any more")
	assert_no_overlaps()


func test_places_wait_in_the_grid_layout() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	var before := rects()
	sheet.set_layout(Spritesheet.Layout.GRID)
	sheet.move_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(0, 2))
	sheet.set_layout(Spritesheet.Layout.PACKED)
	assert_eq(rects()[Vector2i(0, 2)], before[Vector2i(0, 0)], "moved with its frame")
	assert_eq(rects()[Vector2i(1, 0)], before[Vector2i(1, 0)])


func test_copies_get_a_place_of_their_own() -> void:
	add_sprites(3)
	Settings.set_value(&"atlas_dedupe", false)
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	sheet.move_frames([Vector2i(0, 0)] as Array[Vector2i], Vector2i(0, 1), true)
	assert_ne(rects()[Vector2i(0, 1)], rects()[Vector2i(0, 0)])
	assert_no_overlaps()
	Settings.set_value(&"atlas_dedupe", true)


func test_moving_frames_by_hand() -> void:
	add_sprites(3)
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	var coords: Array[Vector2i] = [Vector2i(1, 0)]
	var page := PackedLayout.get_page_sizes(sheet)[0]
	var far := PackedLayout.moved(sheet, coords, 0, page + Vector2i(40, 0))
	assert_false(far.is_empty(), "room to the right")
	sheet.set_placements(far)
	assert_true(sheet.placements[Vector2i(1, 0)].pinned, "moved frames are pinned")
	var onto := PackedLayout.get_rect(sheet, Vector2i(0, 0)).position
	var offset := onto - PackedLayout.get_rect(sheet, Vector2i(1, 0)).position
	assert_true(PackedLayout.moved(sheet, coords, 0, offset).is_empty(), "not onto another frame")
	assert_false(PackedLayout.moved(sheet, coords, 1, Vector2i.ZERO).is_empty(), "to a new page")


func test_pinned_frames_stay_when_packing_again() -> void:
	add_sprites()
	pack()
	var coord := Vector2i(4, 0)
	var moved := PackedLayout.moved(sheet, [coord] as Array[Vector2i], 0, Vector2i(200, 0))
	sheet.set_placements(moved)
	var pinned_rect := PackedLayout.get_rect(sheet, coord)
	sheet.remove_frames([Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(PackedLayout.get_rect(sheet, coord), pinned_rect, "auto packing leaves it")
	assert_no_overlaps()
	var arranged := PackedLayout.arrange(sheet, true, true)
	sheet.set_placements(arranged.placements)
	assert_ne(PackedLayout.get_rect(sheet, coord), pinned_rect, "packed with the rest")
	assert_false(sheet.placements[coord].pinned)


func test_frames_go_on_pages() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.AUTO, {"max_size": 48, "spacing": 1})
	pack()
	assert_true(PackedLayout.get_page_count(sheet) > 1)
	for size in PackedLayout.get_page_sizes(sheet):
		assert_true(size.x <= 48 and size.y <= 48, str(size))
	assert_no_overlaps()
	var warnings: Array[String] = []
	sheet.layout_warning.connect(func(message: String) -> void: warnings.append(message))
	sheet.add_frames([make_image(Color.RED, Vector2i(60, 10))] as Array[Image])
	assert_eq(warnings.size(), 1, "too big for a page")


func test_scaling_packs_again() -> void:
	add_sprites(2)
	pack()
	sheet.set_frame_scale(Vector2(2, 2))
	assert_eq(sheet.placements[Vector2i(0, 0)].src, Rect2i(4, 4, 20, 60))
	assert_no_overlaps()


func test_reloaded_frames_keep_their_place_when_they_fit() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.KEEP)
	pack()
	var before := rects()
	var coord := Vector2i(1, 0)
	var smaller := sprite(Vector2i(14, 14), Rect2i(1, 1, 12, 12))
	sheet.set_frame(coord, smaller, {}, null)
	assert_eq(rects()[coord].position, before[coord].position, "same place, smaller")
	sheet.set_frame(coord, sprite(Vector2i(80, 80), Rect2i(0, 0, 80, 80)), {}, null)
	assert_eq(rects()[coord].size, Vector2i(80, 80), "grown, where there's room")
	assert_no_overlaps()
	for other: Vector2i in before:
		if other != coord:
			assert_eq(rects()[other], before[other])


func test_projects_keep_the_packed_layout() -> void:
	add_sprites()
	set_mode(AtlasSettings.PackMode.KEEP, {"allow_rotation": true, "spacing": 2})
	pack()
	sheet.set_placements(PackedLayout.pin_changes(sheet, [Vector2i(1, 0)] as Array[Vector2i], true))
	var project := dir.path_join("packed.sbelli")
	assert_eq(ProjectFile.save(sheet, project), OK)
	var loaded := ProjectFile.load(project)
	var reopened := Spritesheet.new()
	reopened.set_state(loaded.state)
	assert_eq(reopened.layout, Spritesheet.Layout.PACKED)
	assert_eq(reopened.placements, sheet.placements)
	assert_eq(reopened.atlas_settings.spacing, 2)
	assert_true(reopened.atlas_settings.allow_rotation)
	var grid := Spritesheet.new()
	grid.add_frames([make_image(Color.RED)] as Array[Image])
	var grid_project := dir.path_join("grid.sbelli")
	ProjectFile.save(grid, grid_project)
	var zip := ZIPReader.new()
	zip.open(grid_project)
	var data: Dictionary = JSON.parse_string(zip.read_file("project.json").get_string_from_utf8())
	zip.close()
	assert_eq(int(data.version), 1, "grid projects stay readable by older versions")
