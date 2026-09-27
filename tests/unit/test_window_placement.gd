extends "res://tests/test_case.gd"
## Where the main window goes on first launch and after, and how small it can be

## A 1920×1080 screen with a 40 px taskbar, and one to its right
const LEFT := Rect2i(0, 0, 1920, 1040)
const RIGHT := Rect2i(1920, 0, 2560, 1400)


func test_first_launch_takes_most_of_the_screen() -> void:
	var rect := WindowPlacement.get_first_rect(Rect2i(0, 0, 2560, 1400))
	assert_eq(rect.size, Vector2i(2048, 1120), "80%")
	assert_eq(rect.get_center(), Vector2i(1280, 700), "centred")
	rect = WindowPlacement.get_first_rect(LEFT)
	assert_eq(rect.size, Vector2i(1536, 832))
	rect = WindowPlacement.get_first_rect(Rect2i(0, 0, 1600, 860))
	assert_eq(rect.size, Vector2i(1280, 800), "at least 1280×800")
	assert_eq(rect.position, Vector2i(160, 30))
	rect = WindowPlacement.get_first_rect(Rect2i(0, 0, 1366, 728))
	assert_eq(rect.size, Vector2i(1280, 728), "never bigger than the screen")
	rect = WindowPlacement.get_first_rect(RIGHT)
	assert_true(RIGHT.encloses(rect), "on its own screen")


func test_small_screens_start_maximised() -> void:
	assert_true(WindowPlacement.maximizes_first(Vector2i(1366, 768)))
	assert_true(WindowPlacement.maximizes_first(Vector2i(1440, 900)))
	assert_false(WindowPlacement.maximizes_first(Vector2i(1920, 1080)))


func test_the_window_goes_back_where_it_was() -> void:
	var areas: Array[Rect2i] = [LEFT, RIGHT]
	var saved := Rect2i(2100, 100, 1500, 900)
	assert_eq(WindowPlacement.get_restored_rect(saved, 1, areas), saved)
	assert_eq(WindowPlacement.get_restored_rect(Rect2i(), 0, areas), Rect2i(), "never saved")
	assert_eq(
		WindowPlacement.get_restored_rect(saved, 1, [LEFT] as Array[Rect2i]),
		Rect2i(),
		"its screen is gone"
	)
	assert_eq(
		WindowPlacement.get_restored_rect(Rect2i(5000, 100, 800, 600), 0, areas),
		Rect2i(),
		"off every screen"
	)
	assert_eq(
		WindowPlacement.get_restored_rect(Rect2i(1800, 100, 800, 600), 0, areas),
		Rect2i(1920, 100, 800, 600),
		"moved onto the screen with most of it"
	)
	assert_eq(
		WindowPlacement.get_restored_rect(Rect2i(-50, 500, 2500, 800), 0, [LEFT] as Array[Rect2i]),
		Rect2i(0, 240, 1920, 800),
		"shrunk to fit, e.g. after the resolution went down"
	)


func test_the_smallest_size_follows_the_interface_scale() -> void:
	assert_eq(WindowPlacement.get_min_size(1.0, LEFT.size), Vector2i(960, 600))
	assert_eq(WindowPlacement.get_min_size(1.5, LEFT.size), Vector2i(1440, 900))
	assert_eq(WindowPlacement.get_min_size(2.0, LEFT.size), Vector2i(1920, 1040), "fits")
	assert_eq(WindowPlacement.get_min_size(1.25, Vector2i.ZERO), Vector2i(1200, 750))


func test_there_is_no_window_to_place_in_tests() -> void:
	assert_false(WindowPlacement.is_supported(), "headless")
	assert_eq(Global.window_placement, null)
