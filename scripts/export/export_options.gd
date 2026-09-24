class_name ExportOptions
extends RefCounted
## How a spritesheet is turned into an image.

## Colour behind every frame. Formats without transparency (JPG) always use an opaque colour.
var background := Color.TRANSPARENT
## Used instead of transparency for formats that don't support it
var opaque_background := Color.WHITE
var jpg_quality := 0.9
