extends "res://tests/test_case.gd"


func test_rects_never_overlap() -> void:
	var sizes: Array[Vector2i] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 60:
		sizes.append(Vector2i(rng.randi_range(4, 40), rng.randi_range(4, 40)))
	var result := AtlasPacker.find_smallest_packing(sizes)
	var rects: Array[Rect2i] = []
	for i in sizes.size():
		rects.append(Rect2i(result.positions[i], sizes[i]))
	for i in rects.size():
		assert_true(Rect2i(Vector2i.ZERO, result.size).encloses(rects[i]), "inside the atlas")
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "rects %d and %d overlap" % [i, j])
	var area := 0
	for size in sizes:
		area += size.x * size.y
	assert_true(result.size.x * result.size.y < area * 1.5, "reasonably tight")


func test_pack_trims_frames() -> void:
	var sheet := Spritesheet.new()
	for i in 4:
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(8, 4, 10, 20), Color.from_hsv(i / 4.0, 1, 1))
		sheet.add_frames([img] as Array[Image])
	var packed := AtlasPacker.pack(sheet)
	assert_eq(packed.regions.size(), 4)
	var image: Image = packed.image
	assert_true(image.get_width() * image.get_height() <= 4 * 10 * 20 * 1.3, str(image.get_size()))
	var region: AtlasPacker.Region = packed.regions[0]
	assert_eq(region.rect.size, Vector2i(10, 20))
	assert_eq(region.source_rect, Rect2i(8, 4, 10, 20))
	assert_eq(region.source_size, Vector2i(32, 32))
	assert_color(image, region.rect.position, Color.from_hsv(0, 1, 1))


func test_texture_packer_json() -> void:
	var sheet := Spritesheet.new()
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 4, 4), Color.RED)
	sheet.add_frames([img] as Array[Image])
	var packed := AtlasPacker.pack(sheet)
	var frames := Metadata.atlas_frames(sheet, packed.regions, ExportOptions.new())
	var json: Dictionary = JSON.parse_string(
		Metadata.texture_packer_json(frames, "a.png", Vector2i(4, 4))
	)
	var frame: Dictionary = json.frames["0.png"]
	assert_eq(frame.frame, {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0})
	assert_true(frame.trimmed)
	assert_eq(frame.spriteSourceSize, {"x": 2.0, "y": 2.0, "w": 4.0, "h": 4.0})
	assert_eq(json.meta.image, "a.png")


func test_same_frames_are_packed_once() -> void:
	var sheet := Spritesheet.new()
	var blink := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	blink.fill_rect(Rect2i(2, 2, 6, 6), Color.RED)
	var moved := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	moved.fill_rect(Rect2i(8, 8, 6, 6), Color.RED)
	sheet.add_frames([blink, make_image(Color.BLUE, Vector2i(6, 6)), blink, moved] as Array[Image])
	var packed := AtlasPacker.pack(sheet)
	var regions: Array = packed.regions
	assert_eq(regions.size(), 4, "a region for every frame")
	assert_eq(regions[2].rect, regions[0].rect, "shared place")
	assert_eq(regions[3].rect, regions[0].rect, "same pixels elsewhere in the cell")
	assert_eq(regions[3].source_rect.position, Vector2i(8, 8), "keeps its own place")
	assert_ne(regions[1].rect, regions[0].rect)
	var image: Image = packed.image
	assert_true(image.get_width() * image.get_height() <= 2 * 36 * 2, str(image.get_size()))


func test_power_of_two_atlas() -> void:
	var sheet := Spritesheet.new()
	sheet.add_frames(
		(
			[make_image(Color.RED, Vector2i(20, 12)), make_image(Color.BLUE, Vector2i(9, 5))]
			as Array[Image]
		)
	)
	var size: Vector2i = AtlasPacker.pack(sheet, 0, 0, true).image.get_size()
	assert_eq(size.x, nearest_po2(size.x))
	assert_eq(size.y, nearest_po2(size.y))
	assert_true(size.x >= 20 and size.y >= 12)


func test_libgdx_atlas() -> void:
	var sheet := Spritesheet.new()
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 3, 5, 8), Color.RED)
	sheet.add_frames([img] as Array[Image])
	sheet.set_row_name(0, "walk")
	var options := ExportOptions.new()
	options.sprite_name_pattern = "{row_name}_{frame}"
	options.atlas_data = "atlas"
	var path := OS.get_user_data_dir().path_join("tests/gdx.png")
	var result := AtlasPacker.write(sheet, options, path)
	assert_eq(result.error, OK)
	assert_true(result.json_path.ends_with("gdx.atlas"))
	var text := FileAccess.get_file_as_string(result.json_path)
	assert_true("\ngdx.png\nsize: 5, 8\n" in text, text)
	assert_true("\nwalk_0\n  rotate: false\n  xy: 0, 0\n  size: 5, 8\n" in text, text)
	# 2 from the left, 16 - (3 + 8) = 5 from the bottom
	assert_true("  orig: 16, 16\n  offset: 2, 5\n" in text, text)
