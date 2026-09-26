extends "res://tests/test_case.gd"

var sheet: Spritesheet
var dir := OS.get_user_data_dir().path_join("tests/formats")


func before_each() -> void:
	sheet = Spritesheet.new()
	DirAccess.make_dir_recursive_absolute(dir)


## A frame with a block and a corner pixel of another colour, so turns and flips show
static func sprite(size: Vector2i, block: Rect2i, color: Color) -> Image:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill_rect(block, color)
	img.set_pixelv(block.position, Color.WHITE)
	return img


## Long frames that fit on one 64 px page only when one is turned
func add_long_frames() -> void:
	var images: Array[Image] = []
	for i in 2:
		var img := sprite(Vector2i(64, 24), Rect2i(2, 2, 60, 20), Color.from_hsv(i / 4.0, 1, 1))
		img.resource_name = "plank%d" % i
		images.append(img)
	images.append(sprite(Vector2i(24, 64), Rect2i(2, 2, 20, 60), Color.BLUE))
	images[2].resource_name = "post"
	sheet.add_frames(images)


func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func pack_with(values: Dictionary) -> void:
	sheet.set_atlas_settings(AtlasSettings.from_dictionary(values))
	sheet.set_layout(Spritesheet.Layout.PACKED)


func export_with(format: String, pattern := "{name}") -> Dictionary:
	var options := ExportOptions.new()
	options.atlas_data = format
	options.sprite_name_pattern = pattern
	return AtlasPacker.write(sheet, options, dir.path_join("%s.png" % format))


func test_turned_frames_come_back_from_texture_packer_json() -> void:
	add_long_frames()
	pack_with(
		{"allow_rotation": true, "max_size": 64, "source_size": AtlasSettings.SourceSize.SPRITE}
	)
	var result := export_with("json")
	assert_eq(result.error, OK)
	assert_eq(result.pages, 1, "one page thanks to turning")
	var text := FileAccess.get_file_as_string(result.json_path)
	assert_true('"rotated": true' in text, "some are turned")
	var data := SheetData.parse_json(text)
	var page := Image.load_from_file(result.path)
	var images := data.cut(page)
	assert_eq(images.size(), 3)
	for i in images.size():
		var coord := sheet.get_sorted_coords()[i]
		var used := sheet.frames[coord].get_used_rect()
		var expected := sheet.frames[coord].get_region(used)
		var got := images[i].get_region(Rect2i(used.position, used.size))
		assert_eq(images[i].get_size(), sheet.frames[coord].get_size(), "sprite size %d" % i)
		assert_eq(got.get_data(), expected.get_data(), "pixels of %s" % data.frames[i].name)


func test_pivots_are_written() -> void:
	sheet.add_frames([sprite(Vector2i(20, 10), Rect2i(0, 0, 20, 10), Color.RED)] as Array[Image])
	sheet.set_pivots([Vector2i(0, 0)] as Array[Vector2i], Vector2(10, 10))
	pack_with({"source_size": AtlasSettings.SourceSize.SPRITE})
	var json: Dictionary = read_json(export_with("json").json_path)
	var frame: Dictionary = json.frames.values()[0]
	assert_eq(frame.pivot, {"x": 0.5, "y": 1.0}, "the middle of the bottom")
	var xml := FileAccess.get_file_as_string(export_with("sparrow").json_path)
	assert_true('pivotX="10" pivotY="10"' in xml, xml)


func test_frames_without_a_pivot_use_the_default() -> void:
	sheet.add_frames([sprite(Vector2i(8, 8), Rect2i(0, 0, 8, 8), Color.RED)] as Array[Image])
	pack_with({"default_pivot": Vector2(0.5, 1)})
	var json: Dictionary = read_json(export_with("json").json_path)
	assert_eq(json.frames.values()[0].pivot, {"x": 0.5, "y": 1.0})


func test_pages_get_files_of_their_own() -> void:
	add_long_frames()
	pack_with({"max_size": 64})
	var result := export_with("json")
	assert_eq(result.error, OK)
	assert_true(result.pages > 1, "more than one page")
	for page: int in result.pages:
		var png := dir.path_join("json_%d.png" % page)
		var json := dir.path_join("json_%d.json" % page)
		assert_true(FileAccess.file_exists(png), png)
		var data := SheetData.load_file(json)
		assert_eq(data.image_file, png.get_file())
		assert_false(data.frames.is_empty(), "frames on page %d" % page)
	assert_eq(result.paths.size(), result.pages * 2)


func test_libgdx_atlas_has_every_page() -> void:
	add_long_frames()
	pack_with(
		{"max_size": 64, "allow_rotation": true, "source_size": AtlasSettings.SourceSize.SPRITE}
	)
	var result := export_with("atlas")
	var text := FileAccess.get_file_as_string(result.json_path)
	assert_true(text.begins_with("\natlas.png\nsize: "), text)
	assert_true("  rotate: true\n" in text, text)
	# A turned region keeps its size before turning, and is stored counter-clockwise
	for coord in sheet.get_sorted_coords():
		var place: Dictionary = sheet.placements[coord]
		if not place.rotated:
			continue
		var frame_name := sheet.frames[coord].resource_name
		var expected := (
			"\n%s\n  rotate: true\n  xy: %d, %d\n  size: %d, %d\n"
			% [frame_name, place.position.x, place.position.y, place.src.size.x, place.src.size.y]
		)
		assert_true(expected in text, expected)
		var page := Image.load_from_file(result.path)
		var stored := page.get_region(PackedLayout.get_rect(sheet, coord))
		stored.rotate_90(CLOCKWISE)
		var frame := sheet.frames[coord].get_region(place.src)
		assert_eq(stored.get_data(), frame.get_data(), "turned counter-clockwise")


func test_sparrow_xml() -> void:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 3, 5, 8), Color.RED)
	img.resource_name = "a&b"
	sheet.add_frames([img] as Array[Image])
	pack_with({})
	var text := FileAccess.get_file_as_string(export_with("sparrow").json_path)
	assert_true('<TextureAtlas imagePath="sparrow.png" width="5" height="8">' in text, text)
	var expected := (
		'<SubTexture name="a&amp;b" x="0" y="0" width="5" height="8"'
		+ ' frameX="-2" frameY="-3" frameWidth="16" frameHeight="16"'
	)
	assert_true(expected in text, text)


func test_phaser_multi_atlas() -> void:
	add_long_frames()
	pack_with({"max_size": 64})
	var result := export_with("phaser")
	var json := read_json(result.json_path)
	assert_eq(json.textures.size(), result.pages)
	var count := 0
	for texture: Dictionary in json.textures:
		assert_true(FileAccess.file_exists(dir.path_join(texture.image)), texture.image)
		count += texture.frames.size()
	assert_eq(count, 3)
	assert_eq(result.paths.size(), result.pages + 1, "one data file")


func test_godot_sprite_frames_from_an_atlas() -> void:
	add_long_frames()
	pack_with({"max_size": 64, "source_size": AtlasSettings.SourceSize.SPRITE})
	var result := export_with("godot")
	assert_eq(result.error, OK)
	var text := FileAccess.get_file_as_string(result.json_path)
	assert_true('path="godot_1.png" id="2_sheet"' in text, text)
	assert_true("margin = Rect2(2, 2, 4, 4)" in text, "trimmed borders come back")


func test_godot_cant_describe_turned_frames() -> void:
	add_long_frames()
	pack_with({"max_size": 64, "allow_rotation": true})
	var result := export_with("godot")
	assert_eq(result.error, ERR_UNAVAILABLE)
	assert_true("turned" in result.message, result.message)
	# A grid sheet is packed without turning for it
	sheet.set_layout(Spritesheet.Layout.GRID)
	assert_eq(export_with("godot").error, OK)


func test_frame_names_are_unique() -> void:
	var images: Array[Image] = []
	for color: Color in [Color.RED, Color.GREEN, Color.BLUE]:
		var img := make_image(color, Vector2i(4, 4))
		img.resource_name = "star"
		images.append(img)
	sheet.add_frames(images)
	var json: Dictionary = read_json(export_with("json").json_path)
	var names: Array = json.frames.keys()
	names.sort()
	assert_eq(names, ["star.png", "star_2.png", "star_3.png"])


func test_array_json() -> void:
	sheet.add_frames([make_image(Color.RED, Vector2i(4, 4))] as Array[Image])
	var json := read_json(export_with("json-array", "{index}").json_path)
	assert_true(json.frames is Array)
	assert_eq(json.frames[0].filename, "0.png")
	assert_eq(SheetData.parse_json(JSON.stringify(json)).frames.size(), 1, "readable")
