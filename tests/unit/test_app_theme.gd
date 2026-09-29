extends "res://tests/test_case.gd"
## Icons recoloured for the light theme, like the Godot editor's

const ALIGN_ICON := "res://assets/icons/ControlAlignCenter.svg"
const PIN_ICON := "res://assets/icons/Pin.svg"
const THEME_SETTINGS: Array[StringName] = [&"theme", &"accent_color", &"system_accent"]

## The operating system's, replaced in tests
var _is_system_dark: Callable = Global.is_system_dark
var _get_system_accent: Callable = Global.get_system_accent
## The stand-in operating system's dark mode and accent colour
var _system_dark := true
var _system_accent := Color.TRANSPARENT


func after_each() -> void:
	Global.is_system_dark = _is_system_dark
	Global.get_system_accent = _get_system_accent
	_system_dark = true
	_system_accent = Color.TRANSPARENT
	for key in THEME_SETTINGS:
		Settings.set_value(key, Settings.DEFAULTS[key])
	Global.apply_theme()
	AppTheme.recolor_icons(Global.light_theme)


func test_the_theme_follows_the_system_by_default() -> void:
	assert_eq(Settings.DEFAULTS[&"theme"], "system")
	assert_false(Settings.DEFAULTS[&"system_accent"], "the app's own accent")
	_use_stand_in_system()
	Global.apply_theme()
	assert_false(Global.light_theme, "dark like the system")
	var background := _background()
	_system_dark = false
	Global.update_system_theme()
	assert_true(Global.light_theme, "light like the system")
	assert_ne(_background(), background, "applied")


func test_the_system_theme_is_applied_again_when_it_changes() -> void:
	_use_stand_in_system()
	_system_dark = false
	Global.apply_theme()
	var applied := [0]
	var count := func() -> void: applied[0] += 1
	Global.theme_applied.connect(count)
	Global.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(applied[0], 0, "not while the system is the same")
	_system_dark = true
	Global.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(applied[0], 1, "the system turned dark")
	assert_false(Global.light_theme)
	Settings.set_value(&"theme", "light")
	assert_eq(applied[0], 2, "choosing a theme applies it")
	assert_true(Global.light_theme)
	_system_dark = false
	Global.update_system_theme()
	_system_dark = true
	Global.update_system_theme()
	assert_eq(applied[0], 2, "a chosen theme doesn't follow the system")
	Global.theme_applied.disconnect(count)


func test_the_system_accent_colour() -> void:
	_use_stand_in_system()
	_system_accent = Color.ORANGE
	Global.apply_theme()
	assert_eq(Global.accent_color, AppTheme.DEFAULT_ACCENT, "only when chosen")
	Settings.set_value(&"system_accent", true)
	assert_eq(Global.accent_color, Color.ORANGE)
	var theme := ThemeDB.get_project_theme()
	assert_eq(theme.get_color("checkbox_checked_color", "CheckBox"), Color.ORANGE, "applied")
	_system_accent = Color.GREEN
	Global.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(Global.accent_color, Color.GREEN, "follows the system's")
	assert_eq(theme.get_color("checkbox_checked_color", "CheckBox"), Color.GREEN)
	# Where the system has none, e.g. on the web, the chosen colour
	_system_accent = Color.TRANSPARENT
	Global.update_system_theme()
	assert_eq(Global.accent_color, AppTheme.DEFAULT_ACCENT, "falls back")
	Settings.set_value(&"accent_color", Color.RED)
	assert_eq(Global.accent_color, Color.RED, "to the chosen one")


func test_the_settings_window_shows_the_accent_in_use() -> void:
	_use_stand_in_system()
	_system_accent = Color.ORANGE
	var window := SettingsWindow.new()
	add_child(window)
	window.popup_centered()
	var picker := window.get_control(&"accent_color") as ColorPickerButton
	var theme_option := window.get_control(&"theme") as OptionButton
	assert_eq(theme_option.get_item_text(theme_option.selected), "System")
	assert_false(picker.disabled)
	(window.get_control(&"system_accent") as CheckBox).button_pressed = true
	assert_true(Settings.get_value(&"system_accent"))
	assert_true(picker.disabled, "the system's is used")
	assert_eq(picker.color, Color.ORANGE, "shows the system's")
	_system_accent = Color.GREEN
	Global.update_system_theme()
	assert_eq(picker.color, Color.GREEN, "as it changes")
	_system_accent = Color.TRANSPARENT
	Global.update_system_theme()
	assert_false(picker.disabled, "the system has none")
	assert_eq(picker.color, AppTheme.DEFAULT_ACCENT)
	window.queue_free()


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
	var raster := CanvasIcon.new(load(PIN_ICON)).get_raster(16).get_image()
	var colors := {}
	for y in raster.get_height():
		for x in raster.get_width():
			var color := raster.get_pixel(x, y)
			if color.a == 1:
				colors[color.to_html(false)] = true
	assert_true(colors.has("e0e0e0"), "the dark theme's colour")
	assert_false(colors.has("5a5a5a"), "not the light theme's")
	assert_false((load(PIN_ICON) as DPITexture).color_map.is_empty(), "the original is themed")


func test_icons_over_sprites_are_rasterised_at_the_size_drawn() -> void:
	var icon := CanvasIcon.new(load(PIN_ICON))
	for pixels: int in [9, 16, 28, 56]:
		assert_eq(icon.get_raster(pixels).get_size(), Vector2(pixels, pixels))
	var raster := icon.get_raster(28)
	assert_true(icon.get_raster(28) == raster, "made once")


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


func test_windows_inside_the_main_one_have_an_opaque_title_bar() -> void:
	for light: bool in [false, true]:
		var theme := AppTheme.build(light)
		var height := theme.get_constant("title_height", "Window")
		for style: StringName in [&"embedded_border", &"embedded_unfocused_border"]:
			var border := theme.get_stylebox(style, "Window") as StyleBoxFlat
			assert_eq(border.bg_color.a, 1.0, "opaque, %s" % style)
			assert_true(border.expand_margin_top >= height, "reaches over the title bar")
		var panel := theme.get_stylebox("panel", "AcceptDialog") as StyleBoxFlat
		var frame := theme.get_stylebox("embedded_border", "Window") as StyleBoxFlat
		assert_eq(frame.bg_color, panel.bg_color, "the dialogs' colour")
		assert_eq(theme.get_color("title_color", "Window"), theme.get_color("font_color", "Label"))
		assert_eq(theme.get_icon("close", "Window"), AppTheme.CLOSE, "the themed close icon")


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _use_stand_in_system() -> void:
	Global.is_system_dark = func() -> bool: return _system_dark
	Global.get_system_accent = func() -> Color: return _system_accent


static func _background() -> Color:
	return (ThemeDB.get_project_theme().get_stylebox("panel", "Panel") as StyleBoxFlat).bg_color
