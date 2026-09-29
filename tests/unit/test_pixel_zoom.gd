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


## [param zoom] and [param count] zooms stepped up from it
func steps_from(zoom: float, scale: float, count: int) -> Array[float]:
	var zooms: Array[float] = [zoom]
	for i in count:
		zooms.append(PixelZoom.step(zooms[-1], 1.25, scale))
	return zooms


func assert_near(actual: float, expected: float, text := "") -> void:
	assert_true(
		absf(actual - expected) < 0.0001, "%s: expected %s, got %s" % [text, expected, actual]
	)


func assert_zooms(actual: Array[float], expected: Array[float], text: String) -> void:
	assert_eq(actual.size(), expected.size(), text)
	for i in mini(actual.size(), expected.size()):
		assert_near(actual[i], expected[i], "%s: %d" % [text, i])


func test_levels_are_whole_screen_pixels_with_the_interface_scaled() -> void:
	var up: Array[float] = [1.0, 2.0, 3.0, 4.0]
	assert_zooms(steps_from(1, 1, 3), up, "at 100%, as before")
	assert_zooms(steps_from(1, 2, 3), up, "at 200%, as before")
	# At 150%, 1, 2, 3, 4 screen pixels
	assert_zooms(steps_from(2.0 / 3, 1.5, 3), [2.0 / 3, 4.0 / 3, 2.0, 8.0 / 3], "at 150%")
	assert_zooms(steps_from(0.8, 1.25, 3), [0.8, 1.6, 2.4, 3.2], "at 125%")
	# At 300%, a level is 3 screen pixels, as before
	assert_zooms(steps_from(1, 3, 2), [1.0, 2.0, 3.0], "at 300%")
	assert_zooms(steps_from(1.0 / 3, 3, 2), [1.0 / 3, 0.5, 1.0], "at 300%, below 100%")
	var zooms: Array[float] = [2.0 / 3]
	for i in 3:
		zooms.append(PixelZoom.step(zooms[-1], 0.8, 1.5))
	assert_zooms(
		zooms, [2.0 / 3, 1.0 / 3, 2.0 / 9, 1.0 / 6], "down at 150%: 1/2, 1/3, 1/4 screen pixel"
	)
	zooms = [1.0]
	for i in 2:
		zooms.append(PixelZoom.step(zooms[-1], 0.8, 2))
	assert_zooms(zooms, [1.0, 0.5, 1.0 / 3], "down at 200%, as before")


func test_steps_come_back_with_the_interface_scaled() -> void:
	for scale: float in [1.0, 1.25, 1.5, 2.0]:
		var unit := PixelZoom.unit(scale)
		for units: float in [1.0 / 5, 0.5, 1.0, 3.0, 12.0]:
			var zoom := units * unit
			var back := PixelZoom.step(PixelZoom.step(zoom, 1.25, scale), 0.8, scale)
			assert_near(back, zoom, "%s at %s" % [zoom, scale])


func test_fit_rounds_down_to_whole_screen_pixels() -> void:
	assert_near(PixelZoom.round_down(1.0, 1.5), 2.0 / 3, "1.5 screen pixels")
	assert_near(PixelZoom.round_down(3.0, 1.5), 8.0 / 3)
	assert_near(PixelZoom.round_down(4.0 / 3, 1.5), 4.0 / 3, "already whole")
	assert_near(PixelZoom.round_down(0.5, 1.5), 1.0 / 3, "half a screen pixel")
	assert_near(PixelZoom.round_down(1.0, 1.25), 0.8)
	assert_eq(PixelZoom.round_down(2.4, 2), 2.0, "at 200%, as before")
	for scale: float in [1.0, 1.25, 1.5, 2.0]:
		for fit: float in [0.3, 0.9, 1.0, 1.7, 5.55]:
			var zoom := PixelZoom.round_down(fit, scale)
			assert_true(zoom <= fit + 0.00001, "fits: %s at %s" % [fit, scale])
			assert_true(PixelZoom.step(zoom, 1.25, scale) > fit, "the biggest that does")
			var on_screen := zoom * scale / maxf(floorf(scale), 1)
			if on_screen >= 1:
				assert_near(on_screen, roundf(on_screen), "whole screen pixels")


func test_actual_size_is_the_nearest_whole_zoom() -> void:
	assert_eq(PixelZoom.nearest(1, 1), 1.0)
	assert_eq(PixelZoom.nearest(1, 2), 1.0)
	assert_near(PixelZoom.nearest(1, 1.5), 4.0 / 3, "the bigger one halfway")
	assert_near(PixelZoom.nearest(1, 1.25), 0.8)
	assert_near(PixelZoom.nearest(0.4, 1), 1.0 / 3)
