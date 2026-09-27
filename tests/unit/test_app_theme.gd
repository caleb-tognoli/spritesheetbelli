extends "res://tests/test_case.gd"
## Icons recoloured for the light theme, like the Godot editor's

const ALIGN_ICON := "res://assets/icons/ControlAlignCenter.svg"
const PIN_ICON := "res://assets/icons/Pin.svg"


func after_each() -> void:
	AppTheme.recolor_icons(Settings.get_value(&"theme") == "light")


func test_dark_theme_keeps_icon_colours() -> void:
	assert_true(AppTheme.icon_color_map(false).is_empty())


func test_light_theme_swaps_the_greys_of_icons() -> void:
	var icon: DPITexture = load(ALIGN_ICON)
	var light := DPITexture.create_from_string(
		icon.get_source(), 1.0, 1.0, AppTheme.icon_color_map(true)
	)
	var img := light.get_image()
	assert_color(img, Vector2i(0, 0), Color("6e6e6e"), "border")
	assert_color(img, Vector2i(3, 3), Color("d6d6d6"), "background")
	assert_color(img, Vector2i(8, 8), Color("474747"), "highlight")


func test_every_icon_follows_the_theme() -> void:
	AppTheme.recolor_icons(true)
	var count := 0
	for file in ResourceLoader.list_directory(AppTheme.ICON_DIR):
		if file.get_extension() != "svg":
			continue
		count += 1
		var icon: Texture2D = load(AppTheme.ICON_DIR.path_join(file))
		assert_true(icon is DPITexture, "%s is imported as a DPITexture" % file)
		if icon is DPITexture and StringName(file.get_basename()) not in AppTheme.ICON_EXCEPTIONS:
			assert_false((icon as DPITexture).color_map.is_empty(), "%s is recoloured" % file)
	assert_true(count > 50, "finds the icons")
	AppTheme.recolor_icons(false)
	assert_true((load(PIN_ICON) as DPITexture).color_map.is_empty(), "back to dark")


func test_icons_over_sprites_keep_their_colours() -> void:
	AppTheme.recolor_icons(true)
	var pin := AppTheme.unthemed_icon(load(PIN_ICON)) as DPITexture
	assert_true(pin.color_map.is_empty())
	assert_false((load(PIN_ICON) as DPITexture).color_map.is_empty(), "the original is themed")


func test_pressed_icons_are_the_accent_in_both_themes() -> void:
	var accent := Color("4c9cff")
	for light: bool in [false, true]:
		var theme := AppTheme.build(light, accent)
		var grey := AppTheme.LIGHT_ICON_GREY if light else AppTheme.DARK_ICON_GREY
		var pressed := theme.get_color("icon_pressed_color", "Button") * grey
		assert_true(pressed.is_equal_approx(accent * AppTheme.DARK_ICON_GREY), str(light))


func test_list_selection_is_the_accent_in_both_themes() -> void:
	var accent := Color("4c9cff")
	for light: bool in [false, true]:
		var theme := AppTheme.build(light, accent)
		for type: StringName in [&"Tree", &"ItemList"]:
			var panel := (theme.get_stylebox("panel", type) as StyleBoxFlat).bg_color
			var selected := (theme.get_stylebox("selected", type) as StyleBoxFlat).bg_color
			var focused := (theme.get_stylebox("selected_focus", type) as StyleBoxFlat).bg_color
			var hovered := (theme.get_stylebox("hovered", type) as StyleBoxFlat).bg_color
			var message := "%s, light: %s" % [type, light]
			assert_true(selected.b > selected.r + 0.1, "bluish like the accent, " + message)
			assert_true(
				_distance(focused, accent) < _distance(selected, accent),
				"stronger with focus, " + message
			)
			assert_true(_distance(selected, accent) < _distance(panel, accent), message)
			var text := AppTheme.LIGHT_TEXT if light else AppTheme.DARK_TEXT
			assert_eq(Color(hovered, 1.0), text, "hovering shades with the text colour, " + message)


func test_text_on_the_selection_is_readable_whatever_the_accent() -> void:
	var worst := INF
	for light: bool in [false, true]:
		for h in 12:
			for s: float in [0.0, 0.5, 1.0]:
				for v: float in [0.1, 0.4, 0.7, 1.0]:
					var theme := AppTheme.build(light, Color.from_hsv(h / 12.0, s, v))
					var text := theme.get_color("font_selected_color", "Tree")
					assert_eq(text, theme.get_color("font_hovered_selected_color", "ItemList"))
					for style: StringName in [
						&"selected",
						&"selected_focus",
						&"hovered_selected",
						&"hovered_selected_focus",
					]:
						var box := theme.get_stylebox(style, "Tree") as StyleBoxFlat
						worst = minf(worst, AppTheme.contrast_ratio(text, box.bg_color))
	assert_true(worst >= AppTheme.MIN_CONTRAST, "contrast of %.2f" % worst)
	# A white accent in the dark theme takes the light theme's dark text
	var white := AppTheme.build(false, Color.WHITE)
	assert_eq(white.get_color("font_selected_color", "Tree"), AppTheme.LIGHT_TEXT)


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
