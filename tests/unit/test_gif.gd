extends "res://tests/test_case.gd"

const MAIN_SCENE := "res://ui/main/main.tscn"


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
	var main: Control = load(MAIN_SCENE).instantiate()
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


func test_decodes_what_it_encodes() -> void:
	var sheet := moving_block_sheet()
	var animation := SheetAnimation.create("run", sheet.get_sorted_coords(), 10)
	animation.durations = [1.0, 2.0, 1.0, 1.0] as Array[float]
	var data := GifEncoder.animation_frames(sheet, animation)
	var bytes: PackedByteArray = await GifEncoder.encode(data.frames, data.delays, data.loop)
	var decoded := GifDecoder.decode(bytes)
	assert_eq(decoded.frames.size(), 4)
	assert_eq(decoded.delays, [0.1, 0.2, 0.1, 0.1] as Array[float])
	assert_true(decoded.loop)
	for i in 4:
		var expected: Image = data.frames[i]
		var frame: Image = decoded.frames[i]
		for point: Vector2i in [Vector2i(0, 0), Vector2i(i * 3 + 1, 5), Vector2i(15, 15)]:
			var want := expected.get_pixelv(point)
			var got := frame.get_pixelv(point)
			assert_eq(got.a > 0.5, want.a > 0.5, "frame %d at %s" % [i, point])
			if want.a > 0.5:
				assert_eq(got.to_rgba32(), want.to_rgba32(), "frame %d at %s" % [i, point])


func test_decodes_a_gif_from_another_app() -> void:
	# Made with Pillow: interlaced, 20×16, each frame a block further right
	var gif := GifDecoder.load_file("res://tests/fixtures/pillow.gif")
	assert_false(gif.has("error"), str(gif.get("error")))
	assert_eq(gif.frames.size(), 3)
	assert_eq(gif.delays, [0.1, 0.2, 0.05] as Array[float])
	var colors: Array[Color] = [Color8(220, 40, 40), Color8(40, 200, 60), Color8(50, 80, 230)]
	for i in 3:
		var frame: Image = gif.frames[i]
		assert_eq(frame.get_size(), Vector2i(20, 16))
		assert_eq(frame.get_pixel(3 + i * 4, 5), colors[i], "frame %d" % i)
		assert_eq(frame.get_pixel(0, 0), Color.WHITE)
		assert_eq(frame.get_pixel(19, 15).a, 0.0, "transparent")
	assert_eq(gif.frames[2].get_pixel(3, 5).a, 0.0, "earlier frames were cleared")


func test_bad_gifs() -> void:
	assert_true(GifDecoder.decode(PackedByteArray([1, 2, 3])).has("error"))
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/pillow.gif")
	var cut := GifDecoder.decode(bytes.slice(0, bytes.size() / 2))
	assert_false(cut.has("frames") and cut.frames.is_empty(), "no crash on a cut file")


func test_opening_and_adding_gifs() -> void:
	var main: Control = load(MAIN_SCENE).instantiate()
	Global.document.reset()
	add_child(main)
	await get_tree().process_frame
	var path := ProjectSettings.globalize_path("res://tests/fixtures/pillow.gif")
	main.files.open_path(path)
	await get_tree().process_frame
	var sheet := Global.spritesheet
	assert_eq(sheet.frames.size(), 3)
	assert_eq(sheet.row_names.get(0), "pillow")
	var animation := sheet.animations[0]
	assert_eq(animation.fps, 20.0)
	assert_eq(animation.durations, [2.0, 4.0, 1.0] as Array[float])
	assert_false(Global.document.is_dirty, "opening isn't a change")

	await main.files.show_add_spritesheet_window(path)
	assert_eq(sheet.frames.size(), 6, "added below")
	assert_eq(sheet.animations[1].name, "pillow2")
	assert_eq(sheet.animations[1].cells[0], Vector2i(0, 1))
	Global.document.undo()
	assert_eq(sheet.frames.size(), 3)

	await main.files.add_sprites_from_paths(PackedStringArray([path]))
	assert_eq(sheet.frames.size(), 6, "as sprites, every frame")
	main.queue_free()
	Global.document.reset()
