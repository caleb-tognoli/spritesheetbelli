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
