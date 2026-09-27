extends "res://tests/test_case.gd"


func test_fit_rounds_down_to_whole_zooms() -> void:
	assert_eq(PixelZoom.round_down(7.32), 7.0)
	assert_eq(PixelZoom.round_down(2.0), 2.0)
	assert_eq(PixelZoom.round_down(2.99999), 3.0, "rounding errors are whole")
	assert_eq(PixelZoom.round_down(1.4), 1.0)
	assert_eq(PixelZoom.round_down(0.9), 0.5, "below 100%: 50%, 33%, 25%…")
	assert_eq(PixelZoom.round_down(0.5), 0.5)
	assert_eq(PixelZoom.round_down(0.4), 1.0 / 3)
	assert_eq(PixelZoom.round_down(0.3), 0.25)


func test_steps_up_through_whole_zooms() -> void:
	assert_eq(PixelZoom.step(1, 1.25), 2.0, "at least the next level")
	assert_eq(PixelZoom.step(2, 1.25), 3.0)
	assert_eq(PixelZoom.step(8, 1.25), 10.0, "bigger steps when zoomed in")
	assert_eq(PixelZoom.step(2.4, 1.25), 3.0, "from between levels to the next one")
	assert_eq(PixelZoom.step(0.5, 1.25), 1.0)
	assert_eq(PixelZoom.step(0.25, 1.25), 1.0 / 3)
	assert_eq(PixelZoom.step(0.4, 1.25), 0.5)
	assert_eq(PixelZoom.step(0.1, 1.25), 1.0 / 8)


func test_steps_down_through_whole_zooms() -> void:
	assert_eq(PixelZoom.step(3, 0.8), 2.0)
	assert_eq(PixelZoom.step(2, 0.8), 1.0)
	assert_eq(PixelZoom.step(10, 0.8), 8.0)
	assert_eq(PixelZoom.step(2.4, 0.8), 2.0, "from between levels to the one below")
	assert_eq(PixelZoom.step(1, 0.8), 0.5)
	assert_eq(PixelZoom.step(0.5, 0.8), 1.0 / 3)
	assert_eq(PixelZoom.step(0.4, 0.8), 1.0 / 3)
	assert_eq(PixelZoom.step(1.0 / 20, 0.8), 1.0 / 25, "bigger steps when zoomed out")


func test_steps_come_back() -> void:
	for zoom: float in [1.0 / 5, 0.5, 1.0, 3.0, 12.0]:
		assert_eq(PixelZoom.step(PixelZoom.step(zoom, 1.25), 0.8), zoom, str(zoom))


func test_auto_follows_the_resize_filter() -> void:
	assert_true(PixelZoom.applies("auto", Image.INTERPOLATE_NEAREST))
	assert_false(PixelZoom.applies("auto", Image.INTERPOLATE_BILINEAR))
	assert_true(PixelZoom.applies("on", Image.INTERPOLATE_LANCZOS))
	assert_false(PixelZoom.applies("off", Image.INTERPOLATE_NEAREST))
