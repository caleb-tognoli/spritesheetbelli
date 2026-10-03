extends Node
## User preferences, saved to user://settings.cfg.
## Read with [method get_value]; [signal changed] tells when one changes.

signal changed(key: StringName)

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Every setting and its default value. The type of the default is the setting's type.
const DEFAULTS := {
	# Adding sprites
	&"add_mode": Spritesheet.AddMode.FIRST_FREE,
	&"resize_filter": Image.INTERPOLATE_NEAREST,
	&"watch_sources": true,
	# Pivot mode and the Pivot menu, for engines that anchor frames at a point
	&"use_pivots": false,
	# Preview
	&"index_start": 0,
	&"show_grid": true,
	# Lines between pixels once zoomed in far enough, see PixelGrid
	&"show_pixel_grid": true,
	&"show_indices": true,
	# Rulers along the grid, and the guides made with them, see Rulers
	&"show_rulers": false,
	&"show_checkerboard": true,
	&"grid_color": Color(0.85, 0.85, 0.85, 0.5),
	&"background_color": Color(0.31, 0.31, 0.31),
	# How much of the accent colour covers selected frames, in percent
	&"selection_tint": 25,
	&"checker_size": 8,
	&"zoom_speed": 0.2,
	# "auto", "on" or "off", see PixelZoom
	&"pixel_perfect_zoom": "auto",
	# Export
	&"jpg_quality": 0.9,
	&"jpg_background": Color.WHITE,
	# Packing, for every sheet
	&"atlas_dedupe": true,
	&"atlas_power_of_two": false,
	&"atlas_square": false,
	# Interface
	# "system", the operating system's language, or a locale like "it", see L10n
	&"language": "system",
	# "system", following the operating system's dark mode, "dark" or "light"
	&"theme": "system",
	&"accent_color": AppTheme.DEFAULT_ACCENT,
	# The operating system's accent colour instead of accent_color, where it has one
	&"system_accent": false,
	&"ui_scale": 0.0,
	&"confirm_grid_shrink": true,
	&"restore_session": false,
	# Minutes between copies of unsaved work to recover after a crash, 0 for none, see
	# Recovery
	&"recovery_minutes": 2,
	&"show_status_bar": true,
	# Remembered between runs
	&"last_session": "",
	&"recent_files": [],
	# Widths of the sidebar on the left and of the sprites and history panels on the right,
	# 0 for as narrow as they can be, see SidebarSplit
	&"sidebar_width": 0,
	&"panels_width": 0,
	# Height of the docks under the preview, see BottomDock
	&"bottom_dock_height": 240,
	# Widths of the animation panel's preview (0: as wide as it's tall) and its list (0: as
	# narrow as it can be), see AnimationPanel
	&"animation_preview_width": 0,
	&"animation_list_width": 0,
	# Whether the animation panel is "open" or "closed" in the docks under the preview.
	# "auto" keeps it closed until the sheet has animations, then opens it once.
	&"animation_panel": "auto",
	# Whether the chosen animation's frames are also shown as text, see AnimationDetail
	&"animation_frames_text": false,
	&"show_history": false,
	&"show_sprites": false,
	# The Sprites panel lists frames under their row rather than their animation
	&"sprites_by_row": false,
	# Where the main window was left, in pixels, and whether it was maximised, see
	# WindowPlacement. No size yet before the first launch.
	&"window_rect": Rect2i(),
	&"window_screen": 0,
	&"window_maximized": false,
	&"onion_skin": false,
	# Typing a sprite size adds or takes away transparent space instead of scaling frames
	&"resize_canvas": false,
	# Behind the frames in the animation preview: "checkerboard", "color" or "export", the
	# export background
	&"animation_background": "checkerboard",
	&"animation_background_color": Color(0.31, 0.31, 0.31),
	# Add Spritesheet locks the empty cells of the added sheet
	&"lock_empty_cells": true,
	# How different a pixel can be from a background colour and still be made transparent,
	# from 0 to 1, shared by Add Spritesheet and Remove Background Colour
	&"background_tolerance": SheetBackground.DEFAULT_TOLERANCE,
	# Keys of what the command palette ran last, the latest first, see CommandPalette
	&"command_palette_recent": [],
}
## Settings that are remembered rather than chosen, left alone by Reset
const REMEMBERED: Array[StringName] = [
	&"last_session",
	&"recent_files",
	&"sidebar_width",
	&"panels_width",
	&"bottom_dock_height",
	&"animation_preview_width",
	&"animation_list_width",
	&"animation_panel",
	&"animation_frames_text",
	&"show_history",
	&"show_sprites",
	&"sprites_by_row",
	&"window_rect",
	&"window_screen",
	&"window_maximized",
	&"onion_skin",
	&"resize_canvas",
	&"animation_background",
	&"animation_background_color",
	&"lock_empty_cells",
	&"background_tolerance",
	&"command_palette_recent",
]
const MAX_RECENT_FILES := 10

## Where settings are saved. Tests use their own file.
var path := PATH
var _values := {}
var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings(from := path) -> void:
	path = from
	_values = DEFAULTS.duplicate(true)
	_config = ConfigFile.new()
	if _config.load(path) != OK:
		return
	for key: StringName in DEFAULTS:
		var value: Variant = _config.get_value(SECTION, key, DEFAULTS[key])
		# Ignore values of the wrong type, e.g. from an older version
		if typeof(value) == typeof(DEFAULTS[key]):
			_values[key] = value


func get_value(key: StringName) -> Variant:
	assert(DEFAULTS.has(key), "Unknown setting: %s" % key)
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, value: Variant) -> void:
	assert(DEFAULTS.has(key), "Unknown setting: %s" % key)
	if typeof(value) != typeof(DEFAULTS[key]):
		value = type_convert(value, typeof(DEFAULTS[key]))
	if _values.get(key) == value:
		return
	_values[key] = value
	save_settings()
	changed.emit(key)


func reset_to_defaults() -> void:
	for key: StringName in DEFAULTS:
		if key not in REMEMBERED:
			set_value(key, DEFAULTS[key])


func save_settings() -> void:
	for key: StringName in _values:
		_config.set_value(SECTION, key, _values[key])
	_config.save(path)


## Puts [param file] first in the recent files list
func add_recent_file(file: String) -> void:
	var recent := get_recent_files()
	var existing := recent.find(file)
	if existing >= 0:
		recent.remove_at(existing)
	recent.insert(0, file)
	if recent.size() > MAX_RECENT_FILES:
		recent.resize(MAX_RECENT_FILES)
	set_value(&"recent_files", Array(recent))


## Takes [param file] off the recent files list
func remove_recent_file(file: String) -> void:
	var recent := get_recent_files()
	var index := recent.find(file)
	if index >= 0:
		recent.remove_at(index)
		set_value(&"recent_files", Array(recent))


## Puts [param new_file] where [param file] is in the recent files list, e.g. where it was
## moved to. It's added first when [param file] isn't listed.
func replace_recent_file(file: String, new_file: String) -> void:
	var recent := get_recent_files()
	var index := recent.find(file)
	if index < 0:
		add_recent_file(new_file)
		return
	var existing := recent.find(new_file)
	if existing >= 0 and existing != index:
		recent.remove_at(existing)
		if existing < index:
			index -= 1
	recent[index] = new_file
	set_value(&"recent_files", Array(recent))


func get_recent_files() -> PackedStringArray:
	return PackedStringArray(get_value(&"recent_files"))


func clear_recent_files() -> void:
	set_value(&"recent_files", [])
