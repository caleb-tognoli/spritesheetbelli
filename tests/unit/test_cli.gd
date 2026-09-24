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
	var code := Cli.run(PackedStringArray(args), output)
	output.insert(0, str(code))
	return output


func test_detects_cli_args() -> void:
	assert_true(Cli.is_cli(PackedStringArray(["--pack", "x"])))
	assert_false(Cli.is_cli(PackedStringArray([])))


func test_pack_folder() -> void:
	var out := dir.path_join("sheet.png")
	var result := run(
		["--pack", dir.path_join("frames"), "--out", out, "--columns", "2", "--padding", "1"]
	)
	assert_eq(result[0], "0", str(result))
	var img := Image.load_from_file(out)
	assert_eq(img.get_size(), Vector2i(2 * 8 + 2, 3 * 8 + 2))
	assert_true(result[1].contains("5 frames, 2×3 grid"), result[1])


func test_pack_to_project_then_export_with_sprites() -> void:
	var project := dir.path_join("packed.sbelli")
	assert_eq(run(["--pack", dir.path_join("frames"), "--out", project])[0], "0")
	var result := run(
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
	assert_eq(run(["--pack", dir])[0], "2", "no output")
	assert_eq(run(["--pack", "--out", "x.png"])[0], "2", "nothing to pack")
	assert_eq(run(["--pack", dir, "--export", "x", "--out", "y"])[0], "2", "two commands")
	assert_eq(run(["--export", dir.path_join("missing.sbelli"), "--out", "y.png"])[0], "1")
	assert_eq(run(["--help"])[0], "0")


func test_metadata_option() -> void:
	var out := dir.path_join("with_meta.png")
	var result := run(
		["--pack", dir.path_join("frames"), "--out", out, "--metadata", "godot", "--fps", "10"]
	)
	assert_eq(result[0], "0", str(result))
	assert_true(FileAccess.file_exists(dir.path_join("with_meta.tres")))
	assert_eq(run(["--pack", dir.path_join("frames"), "--out", out, "--metadata", "xml"])[0], "2")
