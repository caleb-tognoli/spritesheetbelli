extends "res://tests/test_case.gd"


func after_each() -> void:
	Settings.reset_to_defaults()


func test_window_gets_the_scale_and_a_bigger_minimum_size() -> void:
	var window := AcceptDialog.new()
	window.min_size = Vector2i(400, 100)
	Global.scale_window(window, 1.5)
	assert_eq(window.content_scale_factor, 1.5)
	assert_eq(window.min_size, Vector2i(600, 150))
	Global.scale_window(window, 2.0)
	Global.scale_window(window, 2.0)
	assert_eq(window.min_size, Vector2i(800, 200), "scaled from its own size, only once")
	Global.scale_window(window, 1.0)
	assert_eq(window.content_scale_factor, 1.0)
	assert_eq(window.min_size, Vector2i(400, 100), "back as it was")
	window.free()


func test_embedded_windows_are_not_scaled_twice() -> void:
	Settings.set_value(&"ui_scale", 1.5)
	assert_eq(get_tree().root.content_scale_factor, 1.5)
	# Windows are embedded without a display, as on the web, and draw at the root's scale
	var window := AcceptDialog.new()
	window.min_size = Vector2i(400, 100)
	add_child(window)
	assert_true(window.is_embedded())
	assert_eq(window.content_scale_factor, 1.0)
	assert_eq(window.min_size, Vector2i(400, 100))
	Settings.set_value(&"ui_scale", 2.0)
	assert_eq(window.content_scale_factor, 1.0, "not when the setting changes either")
	window.queue_free()
