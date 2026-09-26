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
	&"checker_size": 8,
	&"zoom_speed": 0.2,
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
	&"sidebar_width": 0,
	&"show_history": false,
	# From the preview's side: negative is wider than the panels' smallest width
	&"history_width": 0,
	&"show_sprites": false,
	&"onion_skin": false,
}
## Settings that are remembered rather than chosen, left alone by Reset
const REMEMBERED: Array[StringName] = [
	&"last_session",
	&"recent_files",
	&"sidebar_width",
	&"show_history",
	&"history_width",
	&"show_sprites",
	&"onion_skin",
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
