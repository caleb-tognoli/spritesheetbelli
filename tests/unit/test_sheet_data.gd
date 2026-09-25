extends "res://tests/test_case.gd"


## An image with a coloured block in each quarter
static func quarters() -> Image:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)
	img.fill_rect(Rect2i(16, 0, 16, 16), Color.GREEN)
	img.fill_rect(Rect2i(0, 16, 16, 16), Color.BLUE)
	img.fill_rect(Rect2i(16, 16, 8, 16), Color.WHITE)
	return img


func test_hash_with_trimmed_frames() -> void:
	var data := (
		SheetData
		. parse_json(
			(
				JSON
				. stringify(
					{
						"frames":
						{
							"a.png":
							{
								"frame": {"x": 0, "y": 0, "w": 16, "h": 16},
								"spriteSourceSize": {"x": 4, "y": 2, "w": 16, "h": 16},
								"sourceSize": {"w": 24, "h": 20},
								"duration": 100,
							},
							"b.png": {"frame": {"x": 16, "y": 0, "w": 16, "h": 16}},
						},
						"meta": {"image": "sheet.png"},
					}
				)
			)
		)
	)
	assert_eq(data.error, "")
	assert_eq(data.image_file, "sheet.png")
	assert_eq(data.frames.size(), 2)
	var images := data.cut(quarters())
	assert_eq(images[0].get_size(), Vector2i(24, 20), "untrimmed")
	assert_color(images[0], Vector2i(4, 2), Color.RED)
	assert_color(images[0], Vector2i(0, 0), Color(0, 0, 0, 0))
	assert_eq(images[0].resource_name, "a.png")
	assert_eq(images[1].get_size(), Vector2i(16, 16))
	assert_color(images[1], Vector2i(0, 0), Color.GREEN)


func test_array_with_rotated_frame() -> void:
	# The white block is 8 wide and 16 high in the image: drawn 16 wide, turned clockwise
	var data := (
		SheetData
		. parse_json(
			(
				JSON
				. stringify(
					{
						"frames":
						[
							{
								"filename": "turned",
								"frame": {"x": 16, "y": 16, "w": 16, "h": 8},
								"rotated": true,
							}
						]
					}
				)
			)
		)
	)
	var images := data.cut(quarters())
	assert_eq(images[0].get_size(), Vector2i(16, 8))
	assert_color(images[0], Vector2i(15, 7), Color.WHITE)


func test_tags_become_rows_and_animations() -> void:
	var frames := []
	for i in 4:
		frames.append({"filename": str(i), "frame": {"x": i * 8, "y": 0, "w": 8, "h": 8}})
	var data := (
		SheetData
		. parse_json(
			(
				JSON
				. stringify(
					{
						"frames": frames,
						"meta":
						{
							"frameTags":
							[
								{"name": "idle", "from": 0, "to": 1, "direction": "pingpong"},
								{
									"name": "hit",
									"from": 3,
									"to": 3,
									"direction": "forward",
									"repeat": "1"
								},
							]
						}
					}
				)
			)
		)
	)
	var sheet := data.to_spritesheet(quarters())
	assert_eq(sheet.grid_size, Vector2i(2, 3), "idle, the untagged frame, hit")
	assert_eq(sheet.row_names, {0: "idle", 2: "hit"} as Dictionary[int, String])
	assert_true(sheet.has_frame(Vector2i(0, 1)))
	var animations := sheet.animations
	assert_eq(animations.size(), 2)
	assert_eq(animations[0].mode, SheetAnimation.Mode.PING_PONG)
	assert_eq(animations[1].mode, SheetAnimation.Mode.ONCE)
	assert_eq(animations[1].cells, [Vector2i(0, 2)] as Array[Vector2i])


func test_overlapping_tags_fill_a_grid() -> void:
	var frames := []
	for i in 5:
		frames.append({"filename": str(i), "frame": {"x": 0, "y": 0, "w": 8, "h": 8}})
	var data := SheetData.parse_json(
		JSON.stringify(
			{
				"frames": frames,
				"meta":
				{
					"frameTags":
					[{"name": "all", "from": 0, "to": 4}, {"name": "end", "from": 3, "to": 4}]
				}
			}
		)
	)
	var sheet := data.to_spritesheet(quarters())
	assert_eq(sheet.grid_size, Vector2i(3, 2))
	assert_eq(sheet.animations[1].cells, [Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i])


func test_not_sheet_data() -> void:
	assert_ne(SheetData.parse_json("[1, 2]").error, "")
	assert_ne(SheetData.parse_json('{"frames": {}}').error, "")


func test_packed_atlas_round_trip() -> void:
	var sheet := Spritesheet.new()
	var small := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	small.fill_rect(Rect2i(3, 9, 5, 4), Color.RED)
	sheet.add_frames([small, make_image(Color.BLUE, Vector2i(10, 16))] as Array[Image])
	var packed := AtlasPacker.pack(sheet)
	var options := ExportOptions.new()
	options.sprite_name_pattern = "frame{index}"
	var json := Metadata.texture_packer_json(
		Metadata.atlas_frames(sheet, packed.regions, options), "atlas.png", packed.image.get_size()
	)
	var images := SheetData.parse_json(json).cut(packed.image)
	assert_eq(images.size(), 2)
	for i in images.size():
		var coord := Vector2i(i, 0)
		assert_eq(images[i].get_data(), sheet.get_cell_image(coord).get_data(), "frame %d" % i)


func test_finds_data_next_to_image() -> void:
	var dir := OS.get_user_data_dir().path_join("tests/sheet_data")
	DirAccess.make_dir_recursive_absolute(dir)
	var image_path := dir.path_join("hero.png")
	quarters().save_png(image_path)
	var file := FileAccess.open(dir.path_join("hero.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"frames": {"a": {"frame": {"x": 0, "y": 0, "w": 16, "h": 16}}},
				"meta": {"image": "hero.png"}
			}
		)
	)
	file.close()
	assert_eq(SheetData.find_for_image(image_path), dir.path_join("hero.json"))
	var data := SheetData.load_file(dir.path_join("hero.json"))
	assert_eq(data.get_image_path(dir.path_join("hero.json")), image_path)
	assert_eq(SheetData.find_for_image(dir.path_join("other.png")), "")


func test_scattered_animations_round_trip() -> void:
	var sheet := Spritesheet.new()
	for i in 4:
		sheet.add_frames([make_image(Color(i / 4.0, 0, 1))] as Array[Image])
	var cells: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 0), Vector2i(2, 0)]
	var blink := SheetAnimation.create("blink", cells, 10)
	blink.durations = [2.0, 1.0, 1.0] as Array[float]
	sheet.add_animation(blink)
	var frames := Metadata.grid_frames(sheet, ExportOptions.new())
	var json := Metadata.sheet_json(sheet, frames, "a.png", Vector2i(64, 16), 12)
	var parsed: Dictionary = JSON.parse_string(json)
	assert_eq(parsed.meta.animations, {"blink": ["3.png", "0.png", "2.png"]})

	var imported := SheetData.parse_json(json).to_spritesheet(sheet.get_image())
	var animation := imported.animations[0]
	var numbers := animation.cells.map(func(cell: Vector2i) -> int: return imported.index_of(cell))
	assert_eq(numbers, [3, 0, 2], "the exact frames, not the range of the tag")
	assert_eq(animation.durations, [2.0, 1.0, 1.0] as Array[float])
	assert_eq(animation.fps, 10.0)
