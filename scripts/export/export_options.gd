class_name ExportOptions
extends RefCounted
## How a spritesheet is turned into images. Stored per sheet in
## [member Spritesheet.export_settings], except the JPG options which are user settings.

## What an export produces
enum Target {
	IMAGE,  ## The spritesheet as one image
	SPRITES,  ## Every frame as its own image, in a folder
	GODOT,  ## The spritesheet image and a Godot SpriteFrames resource
	JSON,  ## The spritesheet image and a JSON file (Aseprite and TexturePacker style)
	ATLAS,  ## Trimmed frames packed tightly, with a JSON file
	GIF,  ## One animation as an animated GIF
}
enum Existing { ADD_NUMBER, OVERWRITE, SKIP }
## The size a packed atlas's data file gives each frame, which engines line frames up by
enum FrameSize {
	CELL,  ## Its cell, so the frames of an animation line up like in the grid
	FRAME,  ## Its own, for sprites that have nothing to do with each other
}
enum MetadataFormat { NONE, JSON, GODOT }

const IMAGE_FORMATS: Array[String] = ["png", "jpg", "webp"]

var target := Target.IMAGE
## File format of the spritesheet image when exporting only the image
var image_format := "png"

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
## The data file written next to a packed atlas, one of [constant AtlasFormats.FORMATS]
var atlas_data := "json"
var atlas_frame_size := FrameSize.CELL

## File name for exported sprites. See [method SpritesheetExporter.format_sprite_name].
var sprite_name_pattern := "{index}"
var only_selected := false
var existing_files := Existing.ADD_NUMBER

## The file written next to the image for game engines, following [member target]
var metadata: MetadataFormat:
	get:
		match target:
			Target.GODOT:
				return MetadataFormat.GODOT
			Target.JSON:
				return MetadataFormat.JSON
		return MetadataFormat.NONE
	set(value):
		match value:
			MetadataFormat.GODOT:
				target = Target.GODOT
			MetadataFormat.JSON:
				target = Target.JSON
			_:
				if target in [Target.GODOT, Target.JSON]:
					target = Target.IMAGE
## Frames per second of animations in metadata
var animation_fps := 12.0
## The animation exported as a GIF, by name. Empty: every frame.
var gif_animation := ""
## How many times bigger GIF frames are than the sprites
var gif_scale := 1

const _SHEET_KEYS: Array[StringName] = [
	&"target",
	&"image_format",
	&"background",
	&"padding",
	&"spacing",
	&"extrude",
	&"atlas_data",
	&"atlas_frame_size",
	&"sprite_name_pattern",
	&"only_selected",
	&"existing_files",
	&"animation_fps",
	&"gif_animation",
	&"gif_scale",
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
	# Projects from before export targets stored which metadata to write
	if settings.get("metadata") is int and not settings.has("target"):
		metadata = settings.metadata
	for key in _SHEET_KEYS:
		if not settings.has(key):
			continue
		var value: Variant = settings[key]
		var expected := typeof(get(key))
		if typeof(value) != expected and (value is float or value is int):
			value = type_convert(value, expected)
		if typeof(value) == expected:
			set(key, value)
	if image_format not in IMAGE_FORMATS:
		image_format = "png"
	if atlas_data not in AtlasFormats.FORMATS:
		atlas_data = "json"


## Whether the export writes the spritesheet as one image
func writes_sheet_image() -> bool:
	return target in [Target.IMAGE, Target.GODOT, Target.JSON]


## Extension of the file picked when exporting, or empty for a folder
func get_file_extension() -> String:
	match target:
		Target.IMAGE:
			return image_format
		Target.SPRITES:
			return ""
		Target.GIF:
			return "gif"
	return "png"


## The animation of [param sheet] a GIF export plays, or null for every frame
func get_gif_animation(sheet: Spritesheet) -> SheetAnimation:
	for animation in sheet.animations:
		if animation.name == gif_animation:
			return animation
	return null


## The per-sheet values, for [method Spritesheet.set_export_settings]
func to_dictionary() -> Dictionary:
	var result := {}
	var defaults := ExportOptions.new()
	for key in _SHEET_KEYS:
		if get(key) != defaults.get(key):
			result[key] = get(key)
	return result
