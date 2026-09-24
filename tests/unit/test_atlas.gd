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
