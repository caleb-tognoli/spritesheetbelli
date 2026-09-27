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
	&"show_indices": true,
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
	&"theme": "dark",
	&"accent_color": AppTheme.DEFAULT_ACCENT,
	&"ui_scale": 0.0,
	&"confirm_grid_shrink": true,
	&"restore_session": false,
	&"show_status_bar": true,
	# Remembered between runs
	&"last_session": "",
	&"recent_files": [],
	# Widths of the sidebar on the left and of the sprites and history panels on the right,
	# 0 for as narrow as they can be, see SidebarSplit
	&"sidebar_width": 0,
	&"panels_width": 0,
	# Height of the animation panel under the preview, and the widths of its preview (0: as
	# wide as it's tall) and its list (0: as narrow as it can be), see AnimationPanel
	&"animation_panel_height": 240,
	&"animation_preview_width": 0,
	&"animation_list_width": 0,
	# Whether the animation panel is "open" or "closed". "auto" keeps it closed until the
	# sheet has animations, then opens it once.
	&"animation_panel": "auto",
	&"show_history": false,
	&"show_sprites": false,
	# Where the main window was left, in pixels, and whether it was maximised, see
	# WindowPlacement. No size yet before the first launch.
	&"window_rect": Rect2i(),
	&"window_screen": 0,
	&"window_maximized": false,
	&"onion_skin": false,
	# Behind the frames in the animation preview: "checkerboard", "color" or "export", the
	# export background
	&"animation_background": "checkerboard",
	&"animation_background_color": Color(0.31, 0.31, 0.31),
	# Add Spritesheet locks the empty cells of the added sheet
	&"lock_empty_cells": true,
}
## Settings that are remembered rather than chosen, left alone by Reset
const REMEMBERED: Array[StringName] = [
	&"last_session",
	&"recent_files",
	&"sidebar_width",
	&"panels_width",
	&"animation_panel_height",
	&"animation_preview_width",
	&"animation_list_width",
	&"animation_panel",
	&"show_history",
	&"show_sprites",
	&"window_rect",
	&"window_screen",
	&"window_maximized",
	&"onion_skin",
	&"animation_background",
	&"animation_background_color",
	&"lock_empty_cells",
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


func get_recent_files() -> PackedStringArray:
	return PackedStringArray(get_value(&"recent_files"))


func clear_recent_files() -> void:
	set_value(&"recent_files", [])
