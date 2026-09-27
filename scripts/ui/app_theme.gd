class_name AppTheme
## Builds the interface theme from a light or dark palette and an accent colour.
## Icons are Godot editor SVGs drawn for dark backgrounds. Like the editor, the light
## theme swaps their greys for darker ones, see [constant LIGHT_ICON_COLORS].

const DEFAULT_ACCENT := Color("4c9cff")
## The text colour of each theme
const DARK_TEXT := Color("e6e7ea")
const LIGHT_TEXT := Color("1f2329")
## How readable text on selected list rows is at least, as a contrast ratio (WCAG's AA
## level for text)
const MIN_CONTRAST := 4.5
## Every SVG in here is imported as a DPITexture and recoloured with the theme
const ICON_DIR := "res://assets/icons"
## Icon colours in the light theme, from the Godot editor's (editor_color_map.cpp)
const LIGHT_ICON_COLORS := {
	"#e0e0e0": "#5a5a5a",  # Common icon colour
	"#ffffff": "#414141",
	"#000000": "#bfbfbf",  # The see-through backdrop of the Zoom* icons
	"#808080": "#808080",
	"#b3b3b3": "#363636",
	"#f9f9f9": "#606060",
	# Icons in three greys, such as ControlAlign*
	"#d6d6d6": "#474747",  # Highlighted part
	"#474747": "#d6d6d6",  # Background part
	"#919191": "#6e6e6e",  # Border part
}
## Icons that keep their colours in the light theme
const ICON_EXCEPTIONS: Array[StringName] = [&"StatusWarning"]
## The common icon grey in each theme, to turn pressed icons into the accent colour
const DARK_ICON_GREY := Color("e0e0e0")
const LIGHT_ICON_GREY := Color("5a5a5a")
const ARROW_DOWN := preload("res://assets/icons/GuiTreeArrowDown.svg")
const ARROW_RIGHT := preload("res://assets/icons/GuiTreeArrowRight.svg")
const CLOSE := preload("res://assets/icons/Close.svg")
## The height of the title bar Godot draws over windows drawn inside the main one
const TITLE_HEIGHT := 32

## The icons recoloured so far, kept loaded so that they stay recoloured
static var _icons: Dictionary[String, DPITexture] = {}


class Palette:
	var background: Color  ## Window background
	var surface: Color  ## Sidebar, menu and status bar
	var raised: Color  ## Buttons and fields
	var hover: Color
	var border: Color
	var text: Color
	var text_muted: Color
	var accent: Color
	var accent_text: Color  ## Text in the accent colour, such as headings
	var error: Color  ## Text saying what's wrong
	## How strongly list rows, scroll bars and guides are shaded with the text colour
	var shade: float
	## The shade over hovered list rows, selected or not
	var hovered: Color
	## Selected list rows, in the accent colour, and stronger while the list has focus
	var selected: Color
	var selected_focus: Color
	## Text on selected list rows, see [method AppTheme.readable_text]
	var selected_text: Color


static func palette(light: bool, accent: Color) -> Palette:
	var p := Palette.new()
	p.accent = accent
	if light:
		p.background = Color("e9eaee")
		p.surface = Color("f6f7f9")
		p.raised = Color("ffffff")
		p.hover = Color("e2e5eb")
		p.border = Color("c9cdd6")
		p.text = LIGHT_TEXT
		p.text_muted = Color("5d6470")
		p.accent_text = accent.darkened(0.35)
		p.error = Color("c43d2b")
		p.shade = 0.6
		p.selected = p.background.blend(Color(accent, 0.3))
		p.selected_focus = p.background.blend(Color(accent, 0.45))
	else:
		p.background = Color("1b1c1f")
		p.surface = Color("25262a")
		p.raised = Color("31333a")
		p.hover = Color("3b3e46")
		p.border = Color("454852")
		p.text = DARK_TEXT
		p.text_muted = Color("9da2ad")
		p.accent_text = accent.lightened(0.45)
		p.error = Color(1.0, 0.55, 0.45)
		p.shade = 1.0
		p.selected = p.background.blend(Color(accent, 0.4))
		p.selected_focus = p.background.blend(Color(accent, 0.6))
	p.hovered = Color(p.text, 0.07 * p.shade)
	# Hovered, the selection is shaded like the other rows
	p.selected_text = readable_text(
		[
			p.selected,
			p.selected_focus,
			p.selected.blend(p.hovered),
			p.selected_focus.blend(p.hovered)
		],
		p.text
	)
	p.selected = _readable_under(p.selected_text, p.selected, p.hovered)
	p.selected_focus = _readable_under(p.selected_text, p.selected_focus, p.hovered)
	return p


## The text colour most readable on every one of [param backgrounds]: [param text], or
## the other theme's when it stands out more, e.g. on a very light accent in the dark
## theme
static func readable_text(backgrounds: Array[Color], text: Color) -> Color:
	var best := text
	var best_contrast := 0.0
	for candidate: Color in [text, LIGHT_TEXT if text == DARK_TEXT else DARK_TEXT]:
		var contrast := INF
		for background in backgrounds:
			contrast = minf(contrast, contrast_ratio(candidate, background))
		if contrast > best_contrast:
			best = candidate
			best_contrast = contrast
	return best


## [param background] darkened under light [param text] or lightened under dark text,
## as little as it takes to reach [constant MIN_CONTRAST], also shaded as [param hovered]
static func _readable_under(text: Color, background: Color, hovered: Color) -> Color:
	var darken := text.get_luminance() > 0.5
	for i in 30:
		var contrast := minf(
			contrast_ratio(text, background), contrast_ratio(text, background.blend(hovered))
		)
		if contrast >= MIN_CONTRAST:
			break
		background = background.darkened(0.05) if darken else background.lightened(0.05)
	return background


## The contrast ratio between two opaque colours, from 1 (the same) to 21 (black and
## white), as defined by WCAG
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func build(light: bool, accent := DEFAULT_ACCENT) -> Theme:
	var p := palette(light, accent)
	recolor_icons(light)
	var theme := Theme.new()
	# Dialogs and windows; the sidebar, menus and preview set their own smaller sizes
	theme.default_font_size = 14

	var panel := _box(p.background)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", _box(p.surface))
	for variation: StringName in [&"SidebarPanel", &"MenuPanel", &"StatusBar"]:
		theme.set_type_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, _box(p.surface))
	theme.set_type_variation(&"Toolbar", "PanelContainer")
	var toolbar := _box(p.surface, 0, Vector4(6, 3, 6, 3))
	toolbar.border_color = p.border
	toolbar.border_width_bottom = 1
	theme.set_stylebox("panel", &"Toolbar", toolbar)
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
	theme.set_color("font_color", &"HeaderSmall", p.text_muted)
	theme.set_type_variation(&"ErrorLabel", &"StatusLabel")
	theme.set_color("font_color", &"ErrorLabel", p.error)
	theme.set_type_variation(&"AccentLabel", "Label")
	theme.set_color("font_color", &"AccentLabel", p.accent_text)
	theme.set_color("font_color", "Label", p.text)

	# Buttons and everything drawn like them
	var normal := _box(p.raised, 4, Vector4(8, 4, 8, 4))
	var hover := _box(p.hover, 4, Vector4(8, 4, 8, 4))
	var pressed := _box(Color(p.accent, 0.35), 4, Vector4(8, 4, 8, 4))
	var disabled := _box(Color(p.raised, 0.5), 4, Vector4(8, 4, 8, 4))
	var focus := _box(Color.TRANSPARENT, 4, Vector4.ZERO, p.accent, 1)
	var flat := StyleBoxEmpty.new()
	# Icons keep their own colours. Pressed ones become the accent colour, the same in both
	# themes although the light theme's icons are darker.
	var icon_grey := LIGHT_ICON_GREY if light else DARK_ICON_GREY
	var icon_pressed := p.accent * DARK_ICON_GREY / icon_grey
	icon_pressed.a = 1.0
	# Dark icons fade into a light background sooner
	var icon_disabled := Color(1, 1, 1, 0.55 if light else 0.4)
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
		theme.set_color("icon_normal_color", type, Color.WHITE)
		theme.set_color("icon_hover_color", type, Color.WHITE)
		theme.set_color("icon_focus_color", type, Color.WHITE)
		theme.set_color("icon_pressed_color", type, icon_pressed)
		theme.set_color("icon_hover_pressed_color", type, icon_pressed)
		theme.set_color("icon_disabled_color", type, icon_disabled)
	# Toolbar buttons are flat until hovered or pressed, like Godot's
	theme.set_type_variation(&"ToolbarButton", "Button")
	var tool_margins := Vector4(5, 3, 5, 3)
	theme.set_stylebox("normal", &"ToolbarButton", _box(Color.TRANSPARENT, 4, tool_margins))
	theme.set_stylebox("hover", &"ToolbarButton", _box(p.hover, 4, tool_margins))
	theme.set_stylebox("pressed", &"ToolbarButton", _box(Color(p.accent, 0.25), 4, tool_margins))
	theme.set_stylebox(
		"hover_pressed", &"ToolbarButton", _box(Color(p.accent, 0.35), 4, tool_margins)
	)
	theme.set_stylebox("disabled", &"ToolbarButton", _box(Color.TRANSPARENT, 4, tool_margins))
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
	theme.set_color("clear_button_color", "LineEdit", p.text)
	theme.set_color("clear_button_color_pressed", "LineEdit", p.accent)
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
	# Arrows from the icons, so they follow the theme like them
	theme.set_icon("submenu", "PopupMenu", ARROW_RIGHT)
	theme.set_icon("arrow", "OptionButton", ARROW_DOWN)
	# Controls floating over the preview
	theme.set_stylebox(
		"panel", &"PreviewOverlay", _box(Color(p.surface, 0.9), 6, Vector4(4, 3, 4, 3), p.border, 1)
	)
	theme.set_type_variation(&"PreviewOverlay", "PanelContainer")
	# The frame editor: the sheet's sprites, and the timeline of frames with cards that
	# light up when hovered
	for entry: Array in [
		[&"EditorSection", _box(p.background, 6, Vector4(8, 8, 8, 8))],
		[&"TimelinePanel", _box(p.background, 6, Vector4(8, 8, 8, 8), Color(p.accent, 0.45), 1)],
		[&"TimelineFrame", _box(p.raised, 6, Vector4(4, 2, 4, 6), p.border, 1)],
		[&"TimelineFrameHover", _box(p.raised, 6, Vector4(4, 2, 4, 6), p.accent, 1)],
	]:
		theme.set_stylebox("panel", entry[0], entry[1])
		theme.set_type_variation(entry[0], "PanelContainer")
	# Floating panels of fields look like menus, with room around the fields
	theme.set_stylebox(
		"panel", "PopupPanel", _box(p.surface, 6, Vector4(12, 10, 12, 10), p.border, 1)
	)
	theme.set_stylebox("panel", "TooltipPanel", _box(p.raised, 4, Vector4(8, 6, 8, 6), p.border, 1))
	theme.set_color("font_color", "TooltipLabel", p.text)
	theme.set_stylebox("panel", "AcceptDialog", _box(p.surface, 0, Vector4(12, 12, 12, 12)))
	# Dialog buttons as wide as each other, e.g. OK as Cancel (see DialogButtons)
	theme.set_constant("buttons_min_width", "AcceptDialog", DialogButtons.MIN_WIDTH)
	_add_embedded_windows(theme, p)
	var separator := StyleBoxLine.new()
	separator.color = p.border
	theme.set_stylebox("separator", "HSeparator", separator)
	var split := StyleBoxLine.new()
	split.color = p.border
	split.vertical = true
	theme.set_stylebox("split_bar_background", "HSplitContainer", split)
	# The handle for dragging the sidebars wider always shows
	theme.set_constant("autohide", "HSplitContainer", 0)
	# And the one for dragging the animation panel under the preview taller
	theme.set_type_variation(&"CanvasSplit", "VSplitContainer")
	var canvas_split := StyleBoxLine.new()
	canvas_split.color = p.border
	theme.set_stylebox("split_bar_background", &"CanvasSplit", canvas_split)
	theme.set_constant("autohide", &"CanvasSplit", 0)
	# The animation preview's scrub bar: a thin track, in the accent colour up to the grabber
	theme.set_type_variation(&"ScrubBar", "HSlider")
	var track := Vector4(0, 2, 0, 2)
	theme.set_stylebox("slider", &"ScrubBar", _box(Color(p.text, 0.2 * p.shade), 2, track))
	theme.set_stylebox("grabber_area", &"ScrubBar", _box(Color(p.accent, 0.8), 2, track))
	theme.set_stylebox("grabber_area_highlight", &"ScrubBar", _box(p.accent, 2, track))
	_add_lists(theme, p, focus)
	return theme


## Windows drawn inside the main window instead of as the system's own, which is every
## window on the web: Godot draws their title bar and border around them from the
## stylebox, which reaches past the window by its expand margins. Like the Godot editor's,
## the title bar is the colour of the dialogs, with the title in the text colour and the
## close icon. Separate windows keep the system's title bar.
static func _add_embedded_windows(theme: Theme, p: Palette) -> void:
	var frame := _box(p.surface, 6, Vector4(8, 0, 8, 0), p.border, 1)
	frame.corner_radius_bottom_left = 0
	frame.corner_radius_bottom_right = 0
	# The border goes just outside the window, and the title bar above it
	frame.expand_margin_left = 1
	frame.expand_margin_right = 1
	frame.expand_margin_bottom = 1
	frame.expand_margin_top = TITLE_HEIGHT
	# Focused or not: Godot's own is grey
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_constant("title_height", "Window", TITLE_HEIGHT)
	theme.set_font_size("title_font_size", "Window", 14)
	theme.set_color("title_color", "Window", p.text)
	# The close icon's top-left corner, from the window's top-right one: centred in the
	# title bar, as far from the right edge as from the top and bottom
	var margin := (TITLE_HEIGHT - CLOSE.get_height()) / 2
	theme.set_constant("close_h_offset", "Window", CLOSE.get_width() + margin)
	theme.set_constant("close_v_offset", "Window", CLOSE.get_height() + margin)
	theme.set_icon("close", "Window", CLOSE)
	theme.set_icon("close_pressed", "Window", CLOSE)


## Trees and item lists: a sunken background, rows shaded with the text colour when
## hovered and in the accent colour when selected, and scroll bars to match
static func _add_lists(theme: Theme, p: Palette, focus: StyleBox) -> void:
	var margins := Vector4(4, 4, 4, 4)
	var hovered := _box(p.hovered, 3, margins)
	var cursor := _box(Color.TRANSPARENT, 3, margins, p.text_muted, 1)
	for type: StringName in [&"Tree", &"ItemList"]:
		var panel_margins := Vector4(4, 4, 4, 5) if type == &"Tree" else margins
		theme.set_stylebox("panel", type, _box(p.background, 3, panel_margins))
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("hovered", type, hovered)
		# Hovered, the selection is shaded like the other rows
		for entry: Array in [
			[&"selected", p.selected],
			[&"selected_focus", p.selected_focus],
			[&"hovered_selected", p.selected.blend(p.hovered)],
			[&"hovered_selected_focus", p.selected_focus.blend(p.hovered)],
		]:
			theme.set_stylebox(entry[0], type, _box(entry[1], 3, margins))
		# The keyboard cursor only shows while the list has focus
		theme.set_stylebox("cursor", type, cursor)
		theme.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, p.text)
		theme.set_color("font_hovered_color", type, p.text)
		theme.set_color("font_selected_color", type, p.selected_text)
		theme.set_color("font_hovered_selected_color", type, p.selected_text)
		theme.set_color("guide_color", type, Color(p.text, 0.2 * p.shade))
	theme.set_stylebox("hovered_dimmed", "Tree", _box(Color(p.text, 0.03 * p.shade), 3, margins))
	theme.set_stylebox("button_hover", "Tree", hovered)
	theme.set_stylebox("button_pressed", "Tree", _box(Color(p.text, 0.3 * p.shade), 3, margins))
	theme.set_color("font_hovered_dimmed_color", "Tree", p.text)
	theme.set_color("font_disabled_color", "Tree", Color(p.text_muted, 0.6))
	theme.set_color("custom_button_font_highlight", "Tree", p.text)
	theme.set_color("title_button_color", "Tree", p.text)
	theme.set_color("drop_position_color", "Tree", p.accent)
	for color: StringName in [
		&"relationship_line_color", &"parent_hl_line_color", &"children_hl_line_color"
	]:
		theme.set_color(color, "Tree", p.border)
	theme.set_icon("arrow", "Tree", ARROW_DOWN)
	theme.set_icon("arrow_collapsed", "Tree", ARROW_RIGHT)

	# Scroll bars keep Godot's shapes, in the palette's colours
	var defaults := ThemeDB.get_default_theme()
	for type: StringName in [&"HScrollBar", &"VScrollBar"]:
		for entry: Array in [
			[&"scroll", Color(p.background, 0.6)],
			[&"grabber", Color(p.text, 0.4 * p.shade)],
			[&"grabber_highlight", Color(p.text, 0.75 * p.shade)],
			[&"grabber_pressed", Color(p.text_muted, 0.75)],
		]:
			var box := defaults.get_stylebox(entry[0], type).duplicate() as StyleBoxFlat
			box.bg_color = entry[1]
			theme.set_stylebox(entry[0], type, box)


## The colours swapped in the icons: none in the dark theme
static func icon_color_map(light: bool) -> Dictionary:
	var colors := {}
	if light:
		for from: String in LIGHT_ICON_COLORS:
			colors[Color(from)] = Color(LIGHT_ICON_COLORS[from])
	return colors


## Recolours every icon in place, so the buttons, menus and lists that show one follow
## the theme. Each is drawn again from its SVG at the interface's scale.
static func recolor_icons(light: bool) -> void:
	var colors := icon_color_map(light)
	for file in ResourceLoader.list_directory(ICON_DIR):
		if file.get_extension() != "svg" or StringName(file.get_basename()) in ICON_EXCEPTIONS:
			continue
		if not _icons.has(file):
			var icon := load(ICON_DIR.path_join(file)) as DPITexture
			if icon == null:
				push_warning("%s isn't imported as a DPITexture" % file)
				continue
			_icons[file] = icon
		if _icons[file].color_map != colors:
			_icons[file].color_map = colors


## A copy of [param icon] in its own colours, for drawing over sprites rather than on the
## interface
static func unthemed_icon(icon: Texture2D) -> Texture2D:
	var copy := icon.duplicate() as Texture2D
	if copy is DPITexture:
		(copy as DPITexture).color_map = {}
	return copy


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
