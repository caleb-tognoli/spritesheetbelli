extends "res://tests/test_case.gd"


static func moving_block_sheet() -> Spritesheet:
	var sheet := Spritesheet.new()
	for i in 4:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(i * 3, 4, 6, 6), Color.from_hsv(i / 4.0, 0.8, 0.9))
		sheet.add_frames([img] as Array[Image])
	return sheet


## How many times [param pattern] is in [param bytes]
static func count(bytes: PackedByteArray, pattern: PackedByteArray) -> int:
	var found := 0
	for i in bytes.size() - pattern.size() + 1:
		if bytes.slice(i, i + pattern.size()) == pattern:
			found += 1
	return found


func test_encodes_frames_and_loop() -> void:
	var data := GifEncoder.animation_frames(moving_block_sheet(), null, 10, 2)
	assert_eq(data.frames.size(), 4)
	assert_eq(data.frames[0].get_size(), Vector2i(32, 32), "scaled up")
	var bytes: PackedByteArray = await GifEncoder.encode(data.frames, data.delays, data.loop)
	assert_eq(bytes.slice(0, 6).get_string_from_ascii(), "GIF89a")
	assert_eq(bytes.decode_u16(6), 32)
	assert_eq(bytes[-1], 0x3B, "ends with the trailer")
	assert_eq(count(bytes, "NETSCAPE2.0".to_ascii_buffer()), 1, "loops")
	# Graphic control extensions: 10 hundredths of a second each
	assert_eq(count(bytes, PackedByteArray([0x21, 0xF9, 0x04, 0x09, 10, 0])), 4)


func test_once_does_not_loop_and_durations_count() -> void:
	var sheet := moving_block_sheet()
	var animation := SheetAnimation.create("hit", sheet.get_sorted_coords().slice(0, 2), 8)
	animation.durations = [1.0, 3.0] as Array[float]
	animation.mode = SheetAnimation.Mode.ONCE
	var data := GifEncoder.animation_frames(sheet, animation)
	assert_false(data.loop)
	assert_eq(data.delays, [0.125, 0.375] as Array[float])
	var bytes: PackedByteArray = await GifEncoder.encode(data.frames, data.delays, data.loop)
	assert_eq(count(bytes, "NETSCAPE2.0".to_ascii_buffer()), 0)
	# 12.5 rounds to 13, then 50 in total leaves 37
	assert_eq(count(bytes, PackedByteArray([0x21, 0xF9, 0x04, 0x09, 13, 0])), 1)
	assert_eq(count(bytes, PackedByteArray([0x21, 0xF9, 0x04, 0x09, 37, 0])), 1)


func test_palette() -> void:
	var few := make_image(Color.RED)
	few.set_pixel(0, 0, Color(0, 0, 0, 0))
	var palette := GifEncoder.build_palette([few.get_data()] as Array[PackedByteArray])
	assert_false(palette.reduced)
	assert_eq(palette.bits, 1, "transparency and red")
	var many := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			many.set_pixel(x, y, Color8(x * 8, y * 8, 100))
	palette = GifEncoder.build_palette([many.get_data()] as Array[PackedByteArray])
	assert_true(palette.reduced)
	assert_eq(palette.bits, 8)


func test_export_writes_a_gif() -> void:
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	Global.document.reset()
	add_child(main)
	await get_tree().process_frame
	var sheet := Global.spritesheet
	sheet.set_state(moving_block_sheet().get_state())
	sheet.add_animation(SheetAnimation.create("walk", sheet.get_sorted_coords()))
	var options := ExportOptions.new()
	options.target = ExportOptions.Target.GIF
	options.gif_animation = "walk"
	sheet.set_export_settings(options.to_dictionary())
	assert_true(FileController.suggested_export_path(options).ends_with("_walk.gif"))
	var path := OS.get_user_data_dir().path_join("tests/walk.gif")
	DirAccess.remove_absolute(path)
	assert_true(await main.files.export_to(path))
	assert_true(FileAccess.file_exists(path))
	main.queue_free()
	Global.document.reset()
