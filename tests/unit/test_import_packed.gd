extends "res://tests/test_case.gd"
## Opening packed sheets keeps where their frames are

const LEGACY_ATLAS := """
hero.png
size: 64, 32
format: RGBA8888
filter: Nearest, Nearest
repeat: none
walk
  rotate: false
  xy: 2, 4
  size: 10, 12
  orig: 16, 16
  offset: 3, 1
  index: 0
walk
  rotate: true
  xy: 20, 4
  size: 10, 12
  orig: 16, 16
  offset: 0, 0
  index: 1

hero2.png
size: 32, 32
format: RGBA8888
filter: Nearest, Nearest
repeat: none
jump
  rotate: false
  xy: 0, 0
  size: 8, 8
  orig: 8, 8
  offset: 0, 0
  index: -1
"""
const NEW_ATLAS := """page.png
size:64,64
filter:Linear,Linear
coin
bounds:4,6,10,12
offsets:1,2,14,16
rotate:90
"""

var dir := OS.get_user_data_dir().path_join("tests/import_packed")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


## A frame with a block and a corner pixel of another colour, so turns show
static func sprite(size: Vector2i, block: Rect2i, color: Color) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill_rect(block, color)
	img.set_pixelv(block.position, Color.WHITE)
	return img


## A packed sheet of named, trimmed frames on more than one page, some turned and with pivots
static func packed_sheet() -> Spritesheet:
	var sheet := Spritesheet.new()
	var images: Array[Image] = []
	for i in 5:
		var size := Vector2i(20 + i * 9, 14 + (i % 3) * 11)
		var img := sprite(
			size + Vector2i(6, 4), Rect2i(Vector2i(3, 2), size), Color.from_hsv(i / 6.0, 1, 1)
		)
		img.resource_name = "part_%d" % i
		images.append(img)
	sheet.add_frames(images)
	sheet.set_pivots([Vector2i(1, 0)] as Array[Vector2i], Vector2(5, 30))
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)]
	sheet.add_animation(SheetAnimation.create("spin", cells))
	var settings := AtlasSettings.new()
	settings.max_size = 64
	settings.allow_rotation = true
	sheet.set_atlas_settings(settings)
	sheet.set_layout(Spritesheet.Layout.PACKED)
	return sheet


## Every frame's rectangle on its page, by frame name
static func rects_by_name(sheet: Spritesheet) -> Dictionary:
	var result := {}
	for coord in sheet.frames:
		var place: Dictionary = sheet.placements[coord]
		result[sheet.frames[coord].resource_name.get_basename()] = [
			place.page, PackedLayout.get_rect(sheet, coord), place.rotated
		]
	return result


## Exports [param sheet] in [param format], opens it again and returns the reopened sheet
func reopen(sheet: Spritesheet, format: String) -> Spritesheet:
	var options := ExportOptions.new()
	options.atlas_frame_size = ExportOptions.FrameSize.FRAME
	options.atlas_data = format
	options.sprite_name_pattern = "{name}"
	var result := AtlasPacker.write(sheet, options, dir.path_join(format + ".png"))
	assert_eq(result.error, OK, format)
	var data := SheetData.load_file(result.json_path)
	assert_eq(data.error, "", format)
	var paths := data.get_page_paths(result.json_path)
	var others: Array[Image] = []
	for page in range(1, paths.size()):
		others.append(Image.load_from_file(paths[page]))
	return data.to_spritesheet(
		Image.load_from_file(paths[0]), paths[0], result.json_path, true, others
	)


func test_legacy_libgdx_atlas() -> void:
	var data := LibgdxAtlas.parse(LEGACY_ATLAS)
	assert_eq(data.error, "")
	assert_eq(data.pages, PackedStringArray(["hero.png", "hero2.png"]))
	assert_eq(data.page_sizes, [Vector2i(64, 32), Vector2i(32, 32)] as Array[Vector2i])
	assert_eq(data.frames.size(), 3)
	var walk := data.frames[0]
	assert_eq(walk.name, "walk_0", "indexed regions are told apart")
	assert_eq(walk.rect, Rect2i(2, 4, 10, 12))
	assert_eq(walk.source_size, Vector2i(16, 16))
	# 1 from the bottom of 16: 16 - 1 - 12 = 3 from the top
	assert_eq(walk.source_rect, Rect2i(3, 3, 10, 12))
	assert_true(data.frames[1].rotated)
	assert_true(data.frames[1].counter_clockwise)
	assert_eq(data.frames[2].name, "jump")
	assert_eq(data.frames[2].page, 1)


func test_new_libgdx_atlas() -> void:
	var data := LibgdxAtlas.parse(NEW_ATLAS)
	var coin := data.frames[0]
	assert_eq(coin.rect, Rect2i(4, 6, 10, 12))
	assert_eq(coin.source_size, Vector2i(14, 16))
	assert_eq(coin.source_rect, Rect2i(1, 2, 10, 12))
	assert_true(coin.rotated)


func test_turned_libgdx_frames_are_turned_back() -> void:
	var frame := sprite(Vector2i(10, 12), Rect2i(0, 0, 10, 12), Color.RED)
	var stored := frame.duplicate()
	stored.rotate_90(COUNTERCLOCKWISE)
	var page := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	page.blit_rect(stored, Rect2i(Vector2i.ZERO, stored.get_size()), Vector2i(20, 4))
	var data := LibgdxAtlas.parse(LEGACY_ATLAS)
	var cut := SheetData.cut_frame(page, data.frames[1])
	assert_eq(cut.get_size(), Vector2i(16, 16))
	assert_eq(cut.get_region(Rect2i(0, 4, 10, 12)).get_data(), frame.get_data())


func test_texture_packer_pivots_and_phaser_pages() -> void:
	var json := {
		"textures":
		[
			{
				"image": "a.png",
				"frames":
				[
					{
						"filename": "x",
						"frame": {"x": 0, "y": 0, "w": 4, "h": 4},
						"pivot": {"x": 0.5, "y": 1}
					}
				]
			},
			{
				"image": "b.png",
				"frames": [{"filename": "y", "frame": {"x": 2, "y": 2, "w": 4, "h": 4}}]
			},
		]
	}
	var data := SheetData.parse_json(JSON.stringify(json))
	assert_eq(data.format, "phaser")
	assert_eq(data.pages, PackedStringArray(["a.png", "b.png"]))
	assert_eq(data.frames[0].pivot, Vector2(0.5, 1))
	assert_eq(data.frames[1].page, 1)
	assert_eq(data.frames[1].pivot, Vector2(-1, -1), "none given")


func test_round_trips_keep_every_place() -> void:
	var sheet := packed_sheet()
	assert_true(PackedLayout.get_page_count(sheet) > 1, "more than one page")
	var expected := rects_by_name(sheet)
	for format: String in ["json", "phaser", "atlas", "json-array"]:
		var reopened := reopen(sheet, format)
		assert_eq(reopened.layout, Spritesheet.Layout.PACKED, format)
		assert_eq(rects_by_name(reopened), expected, format + ": same places")
		var export := ExportOptions.from_sheet(reopened)
		assert_eq(export.atlas_data, format, "exported the same way again")
		assert_eq(export.sprite_name_pattern, "{name}")
		# Pivots and animations come back where the format has them
		if format != "atlas":
			assert_eq(reopened.animations.size(), 1, format + " animation")
			assert_eq(reopened.animations[0].cells.size(), 3, format + " animation frames")
			var coord := Vector2i(1, 0)
			assert_eq(reopened.get_pivot(coord), sheet.get_pivot(coord), format + " pivot")
		# Frames added to a reopened atlas leave the others alone
		reopened.add_frames([make_image(Color.BLACK, Vector2i(6, 6))] as Array[Image])
		var after := rects_by_name(reopened)
		for frame_name: String in expected:
			assert_eq(after[frame_name], expected[frame_name], format + ": %s stays" % frame_name)


func test_same_pixels_in_two_places_stay_in_both() -> void:
	var sheet := Spritesheet.new()
	var img := sprite(Vector2i(8, 8), Rect2i(0, 0, 8, 8), Color.RED)
	sheet.add_frames([img, img] as Array[Image])
	var places := {
		Vector2i(0, 0): PackedLayout.new_place(0, Vector2i(0, 0), Rect2i(0, 0, 8, 8)),
		Vector2i(1, 0): PackedLayout.new_place(0, Vector2i(20, 0), Rect2i(0, 0, 8, 8)),
	}
	PackedLayout.adopt(sheet, places, Vector2i(64, 64))
	assert_eq(PackedLayout.get_rect(sheet, Vector2i(1, 0)).position, Vector2i(20, 0))


func test_found_sprites_can_stay_where_they_are() -> void:
	var img := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(3, 5, 10, 8), Color.RED)
	img.fill_rect(Rect2i(30, 2, 6, 20), Color.BLUE)
	var rows := SpriteDetector.detect(img)
	var sheet := SpriteDetector.to_spritesheet(img, rows, Spritesheet.Alignment.CENTER, "", true)
	assert_eq(sheet.layout, Spritesheet.Layout.PACKED)
	var rects: Array[Rect2i] = []
	for coord in sheet.get_sorted_coords():
		rects.append(PackedLayout.get_rect(sheet, coord))
	rects.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
	assert_eq(rects, [Rect2i(3, 5, 10, 8), Rect2i(30, 2, 6, 20)] as Array[Rect2i])


func test_opening_an_atlas_keeps_it_packed() -> void:
	Global.document.reset()
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sheet := packed_sheet()
	var options := ExportOptions.new()
	options.sprite_name_pattern = "{name}"
	options.atlas_data = "atlas"
	var result := AtlasPacker.write(sheet, options, dir.path_join("opened.png"))
	main.files.open_path(result.json_path)
	await get_tree().process_frame
	var window: AddSpritesheetWindow = main.files.add_spritesheet_window
	assert_true(window.keep_layout.button_pressed, "on when opening")
	assert_eq(window.spritesheet.frames.size(), 5, "every page is read")
	window.add_spritesheet_to_global()
	await get_tree().process_frame
	var opened := Global.spritesheet
	assert_eq(opened.layout, Spritesheet.Layout.PACKED)
	assert_eq(rects_by_name(opened), rects_by_name(sheet))
	assert_false(Global.document.is_dirty, "opening isn't a change")
	main.queue_free()
	Global.document.reset()
