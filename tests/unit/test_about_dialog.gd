extends "res://tests/test_case.gd"


func test_license_text_has_the_app_godot_and_its_libraries() -> void:
	var text := AboutDialog.get_license_text()
	assert_true(text.begins_with("spritesheetbelli\n\nMIT License"), "the app's own first")
	assert_true(text.contains(Engine.get_license_text().strip_edges()), "Godot's")
	assert_true(text.contains("FreeType"), "the libraries in Godot")
	for license: String in Engine.get_license_info():
		assert_true(text.contains(license), "and each of their licenses: " + license)
