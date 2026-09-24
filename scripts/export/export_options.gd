class_name ExportOptions
extends RefCounted
## How a spritesheet is turned into images. Stored per sheet in
## [member Spritesheet.export_settings], except the JPG options which are user settings.

enum Existing { ADD_NUMBER, OVERWRITE, SKIP }
enum MetadataFormat { NONE, JSON, GODOT }

## Colour behind every frame. Formats without transparency (JPG) always use an opaque colour.
var background := Color.TRANSPARENT
## Used instead of transparency for formats that don't support it
var opaque_background := Color.WHITE
var jpg_quality := 0.9

## Pixels of empty space around the whole sheet
var padding := 0
## Pixels of empty space between cells
var spacing := 0
## Pixels by which each frame's edges are repeated outward, against texture bleeding
var extrude := 0

## File name for exported sprites. See [method SpritesheetExporter.format_sprite_name].
var sprite_name_pattern := "{index}"
var only_selected := false
var existing_files := Existing.ADD_NUMBER

## Also written next to exported images, for game engines
var metadata := MetadataFormat.NONE
## Frames per second of animations in metadata
var animation_fps := 12.0

const _SHEET_KEYS: Array[StringName] = [
	&"background",
	&"padding",
	&"spacing",
	&"extrude",
	&"sprite_name_pattern",
	&"only_selected",
	&"existing_files",
	&"metadata",
	&"animation_fps",
]


## Options from a sheet's export settings and the user's settings
static func from_sheet(sheet: Spritesheet) -> ExportOptions:
	var options := from_settings()
	options.apply(sheet.export_settings)
	return options


## Options from the user's settings only
static func from_settings() -> ExportOptions:
	var options := ExportOptions.new()
	options.jpg_quality = Settings.get_value(&"jpg_quality")
	options.opaque_background = Settings.get_value(&"jpg_background")
	return options


func apply(settings: Dictionary) -> void:
	for key in _SHEET_KEYS:
		if not settings.has(key):
			continue
		var value: Variant = settings[key]
		var expected := typeof(get(key))
		if typeof(value) != expected and (value is float or value is int):
			value = type_convert(value, expected)
		if typeof(value) == expected:
			set(key, value)


## The per-sheet values, for [method Spritesheet.set_export_settings]
func to_dictionary() -> Dictionary:
	var result := {}
	var defaults := ExportOptions.new()
	for key in _SHEET_KEYS:
		if get(key) != defaults.get(key):
			result[key] = get(key)
	return result
