extends "res://tests/test_case.gd"

var dir := OS.get_user_data_dir().path_join("tests/cli")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("frames"))
	for sub: String in ["", "frames", "sprites"]:
		for f in DirAccess.get_files_at(dir.path_join(sub)):
			DirAccess.remove_absolute(dir.path_join(sub).path_join(f))
	for i in 5:
		make_image(Color.from_hsv(i / 5.0, 1, 1), Vector2i(8, 8)).save_png(
			dir.path_join("frames/f%d.png" % (i + 1))
		)


func run(args: Array) -> Array[String]:
	var output: Array[String] = []
	var code: int = await Cli.run(PackedStringArray(args), output)
	output.insert(0, str(code))
	return output


func test_detects_cli_args() -> void:
	assert_true(Cli.is_cli(PackedStringArray(["--pack", "x"])))
	assert_false(Cli.is_cli(PackedStringArray([])))


func test_pack_folder() -> void:
	var out := dir.path_join("sheet.png")
	var result := await run(
		["--pack", dir.path_join("frames"), "--out", out, "--columns", "2", "--padding", "1"]
	)
	assert_eq(result[0], "0", str(result))
	var img := Image.load_from_file(out)
	assert_eq(img.get_size(), Vector2i(2 * 8 + 2, 3 * 8 + 2))
	assert_true(result[1].contains("5 frames, 2×3 grid"), result[1])


func test_pack_to_project_then_export_with_sprites() -> void:
	var project := dir.path_join("packed.sbelli")
	assert_eq((await run(["--pack", dir.path_join("frames"), "--out", project]))[0], "0")
	var result := await run(
		[
			"--export",
			project,
			"--out",
			dir.path_join("out.webp"),
			"--sprites",
			dir.path_join("sprites"),
			"--sprite-size",
			"16x16"
		]
	)
	assert_eq(result[0], "0", str(result))
	assert_eq(Image.load_from_file(dir.path_join("out.webp")).get_size(), Vector2i(80, 16))
	assert_eq(DirAccess.get_files_at(dir.path_join("sprites")).size(), 5)


func test_usage_errors() -> void:
	assert_eq((await run(["--pack", dir]))[0], "2", "no output")
	assert_eq((await run(["--pack", "--out", "x.png"]))[0], "2", "nothing to pack")
	assert_eq((await run(["--pack", dir, "--export", "x", "--out", "y"]))[0], "2", "two commands")
	assert_eq((await run(["--export", dir.path_join("missing.sbelli"), "--out", "y.png"]))[0], "1")
	assert_eq((await run(["--help"]))[0], "0")


func test_metadata_option() -> void:
	var out := dir.path_join("with_meta.png")
	var result := await run(
		["--pack", dir.path_join("frames"), "--out", out, "--metadata", "godot", "--fps", "10"]
	)
	assert_eq(result[0], "0", str(result))
	assert_true(FileAccess.file_exists(dir.path_join("with_meta.tres")))
	assert_eq(
		(await run(["--pack", dir.path_join("frames"), "--out", out, "--metadata", "xml"]))[0], "2"
	)


func test_cut_a_grid_and_find_sprites() -> void:
	var sheet := Image.create_empty(48, 16, false, Image.FORMAT_RGBA8)
	for i in 3:
		sheet.fill_rect(Rect2i(i * 16 + 2, 2 + i, 10, 12 - i), Color.from_hsv(i / 3.0, 1, 1))
	var path := dir.path_join("strip.png")
	sheet.save_png(path)
	var result := await run(["--cut", path, "--grid", "3x1", "--out", dir.path_join("cut.sbelli")])
	assert_eq(result[0], "0", str(result))
	result = await run(
		["--cut", path, "--detect", "--align", "bottom", "--sprites", dir.path_join("sprites")]
	)
	assert_eq(result[0], "0", str(result))
	assert_eq(DirAccess.get_files_at(dir.path_join("sprites")).size(), 3)
	var first := Image.load_from_file(dir.path_join("sprites/0.png"))
	assert_eq(first.get_size(), Vector2i(10, 12), "cut to the sprites")
	assert_eq((await run(["--cut", path, "--detect", "--align", "top", "--out", "x.png"]))[0], "2")
	assert_eq((await run(["--cut", path, "--grid", "3", "--out", "x.png"]))[0], "2")


func test_cut_with_a_data_file_to_an_atlas_and_gif() -> void:
	var packed := dir.path_join("packed.png")
	await run(["--pack", dir.path_join("frames"), "--out", dir.path_join("strip.png")])
	var result := await run(
		["--pack", dir.path_join("frames"), "--out", packed, "--atlas", "--padding", "0"]
	)
	assert_eq(result[0], "0", str(result))
	assert_true(FileAccess.file_exists(dir.path_join("packed.json")))
	# The JSON next to the image is found on its own
	result = await run(["--cut", packed, "--out", dir.path_join("walk.gif"), "--scale", "2"])
	assert_eq(result[0], "0", str(result))
	var gif := GifDecoder.load_file(dir.path_join("walk.gif"))
	assert_eq(gif.frames.size(), 5)
	result = await run(
		["--cut", "res://tests/fixtures/pillow.gif", "--out", dir.path_join("p.gif")]
	)
	assert_eq(
		GifDecoder.load_file(dir.path_join("p.gif")).delays,
		[0.1, 0.2, 0.05] as Array[float],
		"plays the first animation, with its timing"
	)
	assert_eq(gif.frames[0].get_size(), Vector2i(16, 16))
	# And the GIF can be cut again
	result = await run(["--cut", dir.path_join("walk.gif"), "--sprites", dir.path_join("sprites")])
	assert_eq(result[0], "0", str(result))
	assert_eq(DirAccess.get_files_at(dir.path_join("sprites")).size(), 5)
	result = await run(["--cut", packed, "--out", dir.path_join("x.gif"), "--animation", "nope"])
	assert_eq(result[0], "2", "no such animation")


class Holder:
	var unused := AcceptDialog.new()
	var used := Node.new()


func test_unused_nodes_are_freed() -> void:
	var holder := Holder.new()
	add_child(holder.used)
	var unused := holder.unused
	Global.free_unused_nodes(holder)
	assert_false(is_instance_valid(unused), "never added to the tree: freed")
	assert_true(is_instance_valid(holder.used), "in the tree: kept")
	holder.used.queue_free()


func test_packed_layout_from_the_command_line() -> void:
	var atlas := dir.path_join("packed_atlas.png")
	var result := await run(
		[
			"--pack",
			dir.path_join("frames"),
			"--layout",
			"packed",
			"--max-size",
			"16",
			"--out",
			atlas,
			"--atlas-data",
			"atlas",
			"--sprite-size",
			"16x16",
		]
	)
	assert_eq(result[0], "0", str(result))
	assert_true(result[1].begins_with("Wrote 5 pages"), result[1])
	var text := FileAccess.get_file_as_string(dir.path_join("packed_atlas.atlas"))
	assert_true("packed_atlas_4.png" in text, "every page in one .atlas")

	# Cut it back, keeping the layout, into a project
	var project := dir.path_join("reopened.sbelli")
	result = await run(
		["--cut", dir.path_join("packed_atlas.atlas"), "--layout", "packed", "--out", project]
	)
	assert_eq(result[0], "0", str(result))
	var sheet := Spritesheet.new()
	sheet.set_state(ProjectFile.load(project).state)
	assert_eq(sheet.layout, Spritesheet.Layout.PACKED)
	assert_eq(sheet.frames.size(), 5)
	assert_eq(PackedLayout.get_page_count(sheet), 5, "one frame per page, as it was")

	# A packed project is written as an atlas, here packed again on bigger pages
	result = await run(
		[
			"--export",
			project,
			"--max-size",
			"64",
			"--repack",
			"--out",
			dir.path_join("again.png"),
			"--atlas-data",
			"json"
		]
	)
	assert_eq(result[0], "0", str(result))
	assert_true(result[1].contains("again.json: 5 frames"), result[1])
	var data := SheetData.load_file(dir.path_join("again.json"))
	assert_eq(data.frames.size(), 5)
	assert_eq(data.pages.size(), 0, "one page")


func test_packed_layout_usage_errors() -> void:
	var out := dir.path_join("x.png")
	var frames := dir.path_join("frames")
	assert_eq((await run(["--pack", frames, "--layout", "tight", "--out", out]))[0], "2")
	assert_eq((await run(["--pack", frames, "--max-size", "4", "--out", out]))[0], "2")
