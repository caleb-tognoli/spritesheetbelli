class_name ExportOptions
extends RefCounted
## How a spritesheet is turned into an image.

## Colour behind every frame. Formats without transparency (JPG) always use an opaque colour.
var background := Color.TRANSPARENT
## Used instead of transparency for formats that don't support it
var opaque_background := Color.WHITE
var jpg_quality := 0.9


## Options from the user's settings
static func from_settings() -> ExportOptions:
	var options := ExportOptions.new()
	options.jpg_quality = Settings.get_value(&"jpg_quality")
	options.opaque_background = Settings.get_value(&"jpg_background")
	return options
