extends "res://tests/test_case.gd"


func test_loads_in_order_with_failures() -> void:
	var dir := OS.get_user_data_dir().path_join("tests/loader")
	DirAccess.make_dir_recursive_absolute(dir)
	var paths: PackedStringArray = []
	for i in 30:
		var path := dir.path_join("img%d.png" % i)
		make_image(Color(i / 30.0, 0, 0), Vector2i(8, 8)).save_png(path)
		paths.append(path)
	paths.insert(5, dir.path_join("missing.png"))
	var reports: Array[int] = []
	var images := await ImageLoader.load_all(
		paths, func(done: int, _total: int) -> void: reports.append(done)
	)
	assert_eq(images.size(), 31)
	assert_true(images[5] == null, "missing file")
	assert_eq(images[6].resource_name, "img5.png", "order kept")
	assert_true(images[30].get_pixel(0, 0).r > 0.9)


func test_progress_overlay_waits_before_showing() -> void:
	Notify.progress("Loading", 1, 10)
	assert_false(Notify.is_progress_visible(), "quick tasks don't flash it")
	Notify._progress_started -= 1000
	Notify.progress("Loading", 2, 10)
	assert_true(Notify.is_progress_visible())
	Notify.hide_progress()
	assert_false(Notify.is_progress_visible())


func test_run_busy_shows_the_overlay_while_working() -> void:
	var seen := [false]
	var result: Variant = await Notify.run_busy(
		"Working",
		func() -> int:
			seen[0] = Notify.is_progress_visible()
			return 5
	)
	assert_eq(result, 5)
	assert_true(seen[0], "visible during the work")
	assert_false(Notify.is_progress_visible(), "hidden after")
	assert_eq(await Notify.run_busy("Quick", func() -> int: return 6, false), 6, "not slow")


func test_color_key_on_raw_bytes() -> void:
	var img := Image.create_empty(4, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.MAGENTA)
	img.set_pixel(1, 0, Color.RED)
	ImageUtils.color_key(img, Color.MAGENTA)
	assert_eq(img.get_pixel(0, 0).a, 0.0)
	assert_eq(img.get_pixel(1, 0), Color.RED, "other colours stay")
