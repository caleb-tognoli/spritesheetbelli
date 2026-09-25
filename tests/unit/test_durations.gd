extends "res://tests/test_case.gd"

var sheet: Spritesheet


func before_each() -> void:
	sheet = Spritesheet.new()
	sheet.set_grid_size(Vector2i(4, 1))
	for i in 4:
		sheet.set_frame(Vector2i(i, 0), make_image(Color(i / 4.0, 0, 0)))


func test_parse_and_format_durations() -> void:
	var parsed := SheetAnimation.parse_numbers("0-2, 3*2, 1 * 0.5")
	assert_eq(parsed.numbers, [0, 1, 2, 3, 1] as Array[int])
	assert_eq(parsed.durations, [1.0, 1.0, 1.0, 2.0, 0.5] as Array[float])
	assert_eq(SheetAnimation.parse_numbers("0-3*2").durations, [2.0, 2.0, 2.0, 2.0] as Array[float])
	assert_eq(SheetAnimation.parse_numbers("3*x").error, "3*x")
	assert_eq(SheetAnimation.parse_numbers("3*0").error, "3*0")
	assert_eq(SheetAnimation.parse_numbers("*2").error, "*2")
	var numbers: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	var durations: Array[float] = [1, 1, 1, 2, 2, 2, 0.5]
	var text := SheetAnimation.format_numbers(numbers, durations)
	assert_eq(text, "0-2, 3-5*2, 6*0.5")
	assert_eq(SheetAnimation.parse_numbers(text).durations, durations)


func test_durations_follow_cells() -> void:
	var animation := SheetAnimation.create("walk", sheet.get_sorted_coords())
	animation.durations = [1.0, 2.0, 3.0, 4.0] as Array[float]
	sheet.add_animation(animation)
	sheet.remove_cell(Vector2i(1, 0))
	var kept := sheet.animations[0]
	assert_eq(kept.cells, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(kept.durations, [1.0, 3.0, 4.0] as Array[float])
	sheet.remove_frames([Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(kept.get_frame_durations(sheet), [3.0, 4.0] as Array[float], "empty cells skipped")


func test_length_and_ping_pong() -> void:
	var animation := SheetAnimation.create("hop", sheet.get_sorted_coords().slice(0, 3), 10)
	animation.durations = [1.0, 2.0, 3.0] as Array[float]
	assert_eq(animation.get_length(sheet), 0.6)
	animation.mode = SheetAnimation.Mode.PING_PONG
	assert_eq(animation.get_playback_durations(sheet), [1.0, 2.0, 3.0, 2.0] as Array[float])
	assert_eq(animation.get_length(sheet), 0.8)


func test_player_holds_long_frames() -> void:
	var player := FramePlayer.new()
	add_child(player)
	player.sheet = sheet
	player.fps = 10
	player.set_cells([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], [1.0, 3.0])
	player._process(0.11)
	assert_eq(player.get_current_cell(), Vector2i(1, 0))
	player._process(0.2)
	assert_eq(player.get_current_cell(), Vector2i(1, 0), "shown for three frames")
	player._process(0.1)
	assert_eq(player.get_current_cell(), Vector2i(0, 0))
	player.queue_free()


func test_exports_write_durations() -> void:
	var animation := SheetAnimation.create("walk", sheet.get_sorted_coords().slice(0, 2), 10)
	animation.durations = [1.0, 2.5] as Array[float]
	sheet.add_animation(animation)
	var tres := Metadata.sprite_frames_tres(
		Metadata.grid_frames(sheet, ExportOptions.new()), Metadata.animations(sheet), "a.png", 12
	)
	assert_true('"duration": 2.5' in tres, tres)
	var ms := Metadata.frame_durations(sheet, 12)
	assert_eq(ms, {0: 100, 1: 250}, "frames in no animation use the export speed")


func test_imported_durations() -> void:
	var frames := []
	for i in 3:
		(
			frames
			. append(
				{
					"filename": str(i),
					"frame": {"x": i * 8, "y": 0, "w": 8, "h": 8},
					"duration": 200 if i == 2 else 100,
				}
			)
		)
	var data := SheetData.parse_json(
		JSON.stringify(
			{"frames": frames, "meta": {"frameTags": [{"name": "a", "from": 0, "to": 2}]}}
		)
	)
	var imported := data.to_spritesheet(make_image(Color.RED, Vector2i(24, 8))).animations[0]
	assert_eq(imported.fps, 10.0)
	assert_eq(imported.durations, [1.0, 1.0, 2.0] as Array[float])


func test_durations_are_saved() -> void:
	var animation := SheetAnimation.create("walk", sheet.get_sorted_coords())
	animation.durations = [1.0, 1.0, 2.0, 0.5] as Array[float]
	sheet.add_animation(animation)
	var path := OS.get_user_data_dir().path_join("tests/durations.sbelli")
	assert_eq(ProjectFile.save(sheet, path), OK)
	var loaded := Spritesheet.new()
	loaded.set_state(ProjectFile.load(path).state)
	assert_eq(loaded.animations[0].durations, animation.durations)


func test_mirror_animation() -> void:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.RED)
	sheet.set_frame(Vector2i(0, 0), img)
	sheet.set_row_name(0, "walk_right")
	var animation := SheetAnimation.create("walk_right", sheet.get_sorted_coords().slice(0, 2), 8)
	animation.cells.append(Vector2i(0, 0))
	animation.durations = [2.0, 1.0, 1.0] as Array[float]
	animation.mode = SheetAnimation.Mode.PING_PONG
	sheet.add_animation(animation)
	sheet.nudge_frames([Vector2i(1, 0)] as Array[Vector2i], Vector2i(3, 0))

	var index := sheet.mirror_animation(0)
	assert_eq(index, 1)
	var mirrored := sheet.animations[1]
	assert_eq(mirrored.name, "walk_left")
	assert_eq(sheet.row_names.get(1), "walk_left")
	assert_eq(mirrored.cells, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(mirrored.durations, [2.0, 1.0, 1.0] as Array[float])
	assert_eq(mirrored.fps, 8.0)
	assert_eq(mirrored.mode, SheetAnimation.Mode.PING_PONG)
	assert_color(sheet.frames[Vector2i(0, 1)], Vector2i(7, 0), Color.RED, "flipped")
	assert_eq(
		sheet.get_frame_origin(Vector2i(1, 1)).x, -sheet.get_frame_origin(Vector2i(1, 0)).x - 16
	)
	assert_eq(Spritesheet.mirrored_name("run"), "run_flipped")
	assert_eq(Spritesheet.mirrored_name("Left punch"), "Right punch")
