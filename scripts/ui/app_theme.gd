class_name AppTheme
## Builds the interface theme from a light or dark palette and an accent colour.
## Icons are light grey SVGs, tinted through the icon colours so they work on both.

const DEFAULT_ACCENT := Color("4c9cff")


class Palette:
	var background: Color  ## Window background
	var surface: Color  ## Sidebar, menu and status bar
	var raised: Color  ## Buttons and fields
	var hover: Color
	var border: Color
	var text: Color
	var text_muted: Color
	var accent: Color


static func palette(light: bool, accent: Color) -> Palette:
	var p := Palette.new()
	p.accent = accent
	if light:
		p.background = Color("e9eaee")
		p.surface = Color("f6f7f9")
		p.raised = Color("ffffff")
		p.hover = Color("e2e5eb")
		p.border = Color("c9cdd6")
		p.text = Color("1f2329")
		p.text_muted = Color("5d6470")
	else:
		p.background = Color("1b1c1f")
		p.surface = Color("25262a")
		p.raised = Color("31333a")
		p.hover = Color("3b3e46")
		p.border = Color("454852")
		p.text = Color("e6e7ea")
		p.text_muted = Color("9da2ad")
	return p


static func build(light: bool, accent := DEFAULT_ACCENT) -> Theme:
	var p := palette(light, accent)
	var theme := Theme.new()
	# Dialogs and windows; the sidebar, menus and preview set their own smaller sizes
	theme.default_font_size = 14

	var panel := _box(p.background)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", _box(p.surface))
	for variation: StringName in [&"SidebarPanel", &"MenuPanel", &"StatusBar"]:
		theme.set_type_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, _box(p.surface))
	var toast := _box(Color(p.accent, 0.95), 6, Vector4(12, 8, 12, 8))
	theme.set_type_variation(&"Toast", "PanelContainer")
	theme.set_stylebox("panel", &"Toast", toast)
	theme.set_type_variation(&"BusyPanel", "PanelContainer")
	theme.set_stylebox(
		"panel", &"BusyPanel", _box(p.surface, 8, Vector4(20, 16, 20, 18), p.border, 1)
	)
	theme.set_stylebox("background", "ProgressBar", _box(p.raised, 3))
	theme.set_stylebox("fill", "ProgressBar", _box(p.accent, 3))
	theme.set_type_variation(&"StatusLabel", "Label")
	theme.set_font_size("font_size", &"StatusLabel", 12)
	theme.set_color("font_color", &"StatusLabel", p.text_muted)
	theme.set_type_variation(&"EmptyHint", "Label")
	theme.set_font_size("font_size", &"EmptyHint", 15)
	theme.set_color("font_color", &"EmptyHint", p.text_muted)
	theme.set_color("font_color", &"HeaderSmall", p.text_muted)
	theme.set_color("font_color", "Label", p.text)

	# Buttons and everything drawn like them
	var normal := _box(p.raised, 4, Vector4(8, 4, 8, 4))
	var hover := _box(p.hover, 4, Vector4(8, 4, 8, 4))
	var pressed := _box(Color(p.accent, 0.35), 4, Vector4(8, 4, 8, 4))
	var disabled := _box(Color(p.raised, 0.5), 4, Vector4(8, 4, 8, 4))
	var focus := _box(Color.TRANSPARENT, 4, Vector4.ZERO, p.accent, 1)
	var flat := StyleBoxEmpty.new()
	for type: StringName in [
		&"Button", &"MenuButton", &"OptionButton", &"CheckBox", &"CheckButton"
	]:
		var is_flat := type in [&"MenuButton", &"CheckBox", &"CheckButton"]
		theme.set_stylebox("normal", type, (flat as StyleBox) if is_flat else normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, (flat as StyleBox) if is_flat else disabled)
		theme.set_stylebox("focus", type, focus)
		# Room between a button's icon and its text
		theme.set_constant("h_separation", type, 8)
		theme.set_color("font_color", type, p.text)
		theme.set_color("font_hover_color", type, p.text)
		theme.set_color("font_focus_color", type, p.text)
		theme.set_color("font_pressed_color", type, p.text)
		theme.set_color("font_hover_pressed_color", type, p.text)
		theme.set_color("font_disabled_color", type, Color(p.text_muted, 0.6))
		theme.set_color("icon_normal_color", type, p.text)
		theme.set_color("icon_hover_color", type, p.text)
		theme.set_color("icon_focus_color", type, p.text)
		theme.set_color("icon_pressed_color", type, p.accent)
		theme.set_color("icon_hover_pressed_color", type, p.accent)
		theme.set_color("icon_disabled_color", type, Color(p.text_muted, 0.5))
	# Toggle buttons in the sidebar stay subtle when on
	theme.set_stylebox("pressed", "CheckBox", flat)
	theme.set_stylebox("hover_pressed", "CheckBox", hover)
	theme.set_stylebox("pressed", "CheckButton", flat)
	theme.set_stylebox("hover_pressed", "CheckButton", hover)
	theme.set_color("font_pressed_color", "CheckBox", p.text)
	theme.set_color("font_pressed_color", "CheckButton", p.text)
	theme.set_color("checkbox_checked_color", "CheckBox", p.accent)
	theme.set_color("checkbox_unchecked_color", "CheckBox", p.text_muted)
	theme.set_color("button_checked_color", "CheckButton", p.accent)
	theme.set_color("button_unchecked_color", "CheckButton", p.text_muted)

	# Text fields and spin boxes
	var field := _box(p.raised, 4, Vector4(8, 4, 8, 4), p.border, 1)
	var field_focus := _box(p.raised, 4, Vector4(8, 4, 8, 4), p.accent, 1)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", _box(Color(p.raised, 0.5), 4, Vector4(8, 4, 8, 4)))
	theme.set_color("font_color", "LineEdit", p.text)
	theme.set_color("font_uneditable_color", "LineEdit", Color(p.text_muted, 0.7))
	theme.set_color("font_placeholder_color", "LineEdit", Color(p.text_muted, 0.7))
	theme.set_color("caret_color", "LineEdit", p.text)
	theme.set_color("selection_color", "LineEdit", Color(p.accent, 0.35))
	for color: StringName in [&"up_icon_modulate", &"down_icon_modulate"]:
		theme.set_color(color, "SpinBox", p.text)
	for color: StringName in [&"up_hover_icon_modulate", &"down_hover_icon_modulate"]:
		theme.set_color(color, "SpinBox", p.accent)

	# Menus, popups and dialogs
	theme.set_color("font_color", "MenuBar", p.text)
	theme.set_color("font_hover_color", "MenuBar", p.text)
	var menu_item := _box(Color.TRANSPARENT, 4, Vector4(8, 4, 8, 4))
	theme.set_stylebox("normal", "MenuBar", menu_item)
	theme.set_stylebox("hover", "MenuBar", _box(p.hover, 4, Vector4(8, 4, 8, 4)))
	theme.set_stylebox("pressed", "MenuBar", _box(p.hover, 4, Vector4(8, 4, 8, 4)))
	var popup := _box(p.surface, 6, Vector4(4, 4, 4, 4), p.border, 1)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(Color(p.accent, 0.3), 4))
	theme.set_color("font_color", "PopupMenu", p.text)
	theme.set_color("font_hover_color", "PopupMenu", p.text)
	theme.set_color("font_disabled_color", "PopupMenu", Color(p.text_muted, 0.6))
	theme.set_color("font_accelerator_color", "PopupMenu", p.text_muted)
	theme.set_color("font_separator_color", "PopupMenu", p.text_muted)
	theme.set_stylebox("panel", "TooltipPanel", _box(p.raised, 4, Vector4(8, 6, 8, 6), p.border, 1))
	theme.set_color("font_color", "TooltipLabel", p.text)
	theme.set_stylebox("panel", "AcceptDialog", _box(p.surface, 0, Vector4(12, 12, 12, 12)))
	theme.set_stylebox(
		"embedded_border", "Window", _box(p.surface, 6, Vector4(8, 32, 8, 8), p.border, 1)
	)
	theme.set_color("title_color", "Window", p.text)
	var separator := StyleBoxLine.new()
	separator.color = p.border
	theme.set_stylebox("separator", "HSeparator", separator)
	var split := StyleBoxLine.new()
	split.color = p.border
	split.vertical = true
	theme.set_stylebox("split_bar_background", "HSplitContainer", split)
	theme.set_color("font_color", "ItemList", p.text)
	return theme


static func _box(
	color: Color,
	radius := 0,
	margins := Vector4.ZERO,
	border_color := Color.TRANSPARENT,
	border := 0,
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	if border > 0:
		box.border_color = border_color
		box.set_border_width_all(border)
	return box
