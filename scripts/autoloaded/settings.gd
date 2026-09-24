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
	# Interface
	&"ui_scale": 0.0,
	&"confirm_grid_shrink": true,
	&"restore_session": false,
	# Remembered between runs
	&"last_session": "",
}
## Settings that are remembered rather than chosen, left alone by Reset
const REMEMBERED: Array[StringName] = [&"last_session"]

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
